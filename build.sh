#!/bin/bash
# Builds "Only Social GPS.app" into dist/ from Sources/*.swift with swiftc (no Xcode project).
#   ./build.sh            build only
#   ./build.sh --install  build, copy to /Applications (no sudo) and relaunch
#   ./build.sh --clean    remove dist/ first
# Idempotent: every run rebuilds dist/ from scratch.
set -euo pipefail
cd "$(dirname "$0")"

NAME="Only Social GPS"
EXE="OnlySocialGPS"
APP="dist/$NAME.app"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --clean) rm -rf dist ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "build.sh: unknown option '$arg'" >&2; exit 2 ;;
  esac
done

fail() { echo "build.sh: ERROR: $*" >&2; exit 1; }

SWIFTC="${SWIFTC:-/usr/bin/swiftc}"
[ -x "$SWIFTC" ] || SWIFTC="$(command -v swiftc || true)"
[ -n "$SWIFTC" ] && [ -x "$SWIFTC" ] || fail "swiftc not found (install Xcode or the Command Line Tools)"
[ -f Info.plist ] || fail "Info.plist missing"
[ -f Resources/AppIcon.icns ] || fail "Resources/AppIcon.icns missing"
[ -d Engine ] || fail "Engine/ missing"

SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find Sources -name '*.swift' -print0 | sort -z)
[ "${#SOURCES[@]}" -gt 0 ] || fail "no Swift sources in Sources/"

ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos15.0"

echo "Compiling ${#SOURCES[@]} Swift files for $TARGET …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Engine"

if ! "$SWIFTC" -O -swift-version 5 -parse-as-library \
    -target "$TARGET" \
    -module-name OnlySocialGPS \
    -framework SwiftUI -framework AppKit -framework MapKit -framework CoreLocation \
    -framework ServiceManagement \
    "${SOURCES[@]}" -o "$APP/Contents/MacOS/$EXE"; then
  fail "swiftc failed (see errors above)"
fi

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for png in Resources/icon-mark.png Resources/icon-1024.png Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png; do
  [ -f "$png" ] && cp "$png" "$APP/Contents/Resources/" || echo "build.sh: warning: $png missing" >&2
done
cp Engine/*.py "$APP/Contents/Resources/Engine/"
if [ -d Engine/tests ]; then
  mkdir -p "$APP/Contents/Resources/Engine/tests"
  cp Engine/tests/*.py "$APP/Contents/Resources/Engine/tests/" 2>/dev/null || true
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || fail "codesign failed"
echo "Built $APP"

if [ "$INSTALL" = 1 ]; then
  DEST="/Applications/$NAME.app"
  [ -w /Applications ] || fail "/Applications is not writable by $(id -un)"
  # Ask a running copy to quit gracefully (it releases the phones), then replace the bundle.
  if pgrep -xq "$EXE"; then
    # The AppleScript quit runs the app's normal quit path (it releases the phones). If a phone is
    # held the app shows its "Quit and Release" confirmation and the quit blocks on it; rather than
    # replace the bundle under a running app, fall back to SIGTERM (the hub releases on stdin EOF).
    ( osascript -e "tell application id \"com.onlysocial.gps\" to quit" >/dev/null 2>&1 || true ) &
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do pgrep -xq "$EXE" || break; sleep 0.5; done
    if pgrep -xq "$EXE"; then
      echo "build.sh: running copy did not quit (confirmation dialog?) — sending SIGTERM" >&2
      pkill -TERM -x "$EXE" || true
      for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq "$EXE" || break; sleep 0.5; done
    fi
  fi
  rm -rf "$DEST"
  ditto "$APP" "$DEST" || fail "ditto to $DEST failed"
  echo "Installed $DEST"
  open -a "$DEST" || fail "could not launch $DEST"
  echo "Launched $NAME"
fi
