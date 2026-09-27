# Only Social GPS — Build Brief (verified facts, decisions, rules)

## What it is
A native macOS app named **Only Social GPS** that lives in `/Applications` and the Dock. It lists every iPhone plugged into this Mac mini over USB, lets the operator enter the SOCKS5 proxy each phone is using, geolocates that proxy's **exit IP**, and pins the phone's GPS to that spot (or any manually chosen spot). It keeps the spoof alive for as long as the app runs and re-applies it automatically whenever a phone reconnects. The operator (James) runs an Instagram phone farm; each phone already routes through its own ISP proxy, and the GPS must match the proxy's city so the phone's location story is consistent.

## Hard rules for every agent
- NEVER modify, create, or delete anything inside `/Users/james/Desktop/iphone-bot copy`, `iphone-bot-backups`, `WebDriverAgent`, `ReelImporter`, `Caffeinate`, or any other existing Desktop folder. Reading them is fine.
- NEVER kill, restart, or signal any process you did not start yourself. Live farm processes: `sudo ios tunnel start` (root), `ios forward …`, `ios runwda …`, `node src/index.js` (tmux session `bot`), cloudflared, the ella bot. `pkill python3` or `pkill -f pymobiledevice3` is FORBIDDEN (other tooling uses it). Kill only PIDs you spawned.
- All work goes in `/Users/james/Desktop/Only Social GPS/` and the session scratchpad.
- Real-phone testing is allowed ONLY on the idle phone, UDID `00008020-000A283934E9002E`. Use ONLY coordinate **44.6835, -63.5778** (Dartmouth, Nova Scotia — where the phones physically sit) for tests, and ALWAYS clear the simulation and stop your worker afterwards. Never set a location on the other three phones during development.
- No sudo. Nothing here needs root. Never prompt for a password.
- The app must never ask the user to run commands it could run itself, except `pip` installs which it should show as a copyable command.

## Environment (verified 2026-09-15)
- macOS 26.5 (Tahoe), Apple Silicon arm64, 10 CPUs, 16 GB RAM, one 1920×1080 display, user `james` (admin).
- Xcode 26.6 at `/Applications/Xcode.app`; `swiftc` = Swift 6.3.3; macOS 26.5 SDK; `xcrun devicectl` works.
- Python: `/opt/homebrew/bin/python3` = Python 3.14.6 (Homebrew; the interpreter binary is `/opt/homebrew/opt/python@3.14/bin/python3.14`). Installed: pymobiledevice3 10.7.3, Pillow 12.3, requests, fastapi, uvicorn, cryptography. NOT installed: PySocks, httpx. Use `/usr/bin/curl` 8.7.1 (SOCKS5 built in) for proxy connections.
- `timeout`/`gtimeout` are NOT installed. Use `perl -e 'alarm shift; exec @ARGV' 30 <cmd…>` or Python for timeouts. Never use a foreground `sleep` longer than a few seconds in the harness.
- `screencapture` is BLOCKED (no screen-recording permission): agents cannot screenshot the screen. The app provides its own snapshot mode instead (see App section).
- `/Applications` is group-writable by `admin`; james is in `admin`. Install with `ditto`/`cp -R`, no sudo.
- The Mac's public IP geolocates to Dartmouth, Nova Scotia, Canada (Bell Canada), timezone America/Halifax. Internet works.
- The farm's `iphone-bot copy/.devicenames.json` (READ-ONLY) maps UDID → Instagram handle. Use it to pre-fill nicknames.

## The phones (all USB, all iOS 18 → the iOS 17+ tunnel path applies)
| UDID | Model | iOS | Farm handle | Driven by the farm right now? |
|---|---|---|---|---|
| 00008020-000A283934E9002E | iPhone XR (iPhone11,8) | 18.7.9 | @nat.hunterrr | **NO — idle. The only phone you may test on.** |
| 00008020-00092D843405002E | iPhone XR (iPhone11,8) | 18.7.9 | @onlyemspage | yes |
| 00008020-001019503499002E | iPhone XR "Work Phone" | 18.7.9 | @onlyglazertori | yes |
| 00008030-0009193402B8402E | iPhone 11 (iPhone12,1) | 18.7.8 | @ellybellywellyyy | yes |

Developer Mode is on, the personalized Developer Disk Image (DDI) is mounted (verified), all are paired/trusted.

## How GPS spoofing works here (verified on the idle phone)
- iOS 17+: location is simulated through the DVT instruments service `com.apple.instruments.server.services.LocationSimulation`, reached over an RSD tunnel. pymobiledevice3 10.7.3 opens that tunnel **without root** using its in-process "userspace" tunnel (`--userspace` on the CLI, `UserspaceRsdTunnel` in the library).
- Verified working while the farm's root go-ios tunnel (`sudo ios tunnel start`) is up for the same phones. They coexist.
- CLI proof: `pymobiledevice3 developer dvt simulate-location clear --userspace --udid <UDID>` → exit 0; `… set --userspace --udid <UDID> -- 44.6835 -63.5778` → works and BLOCKS ("press return to stop").
- **The simulated location lasts only while the DVT connection is open.** The CLI's `set` blocks for exactly that reason; when the process exits the phone reverts to real GPS. Therefore the engine must HOLD a live DVT + LocationSimulation channel per phone for as long as the spoof is wanted, and re-establish + re-apply after any drop (cable unplug, phone reboot, tunnel error).
- **Only ONE userspace tunnel per Python process** (PyTCP's stack is a process-global singleton; a second `aopen()` raises). Therefore: **one worker process per phone**. A worker costs ~125 MB RSS; four phones ≈ 0.5 GB, acceptable.
- Library API (pymobiledevice3 10.7.3, asyncio):
  ```python
  from pymobiledevice3.remote.userspace_tunnel import UserspaceRsdTunnel
  from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
  from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

  tunnel = UserspaceRsdTunnel(serial=udid)            # autopair=True by default
  rsd = await tunnel.aopen()                           # RemoteServiceDiscoveryService
  async with DvtProvider(rsd) as dvt, LocationSimulation(dvt) as sim:
      await sim.set(lat, lon)                          # call again to move the pin
      ...                                              # keep this block alive = keep the spoof alive
      await sim.clear()                                # restores real GPS
  await tunnel.aclose()
  ```
  - Discovery without a tunnel: `from pymobiledevice3 import usbmux; devs = await usbmux.list_devices()` → `MuxDevice(devid, serial, connection_type)`; keep `is_usb`.
  - Details without a tunnel: `from pymobiledevice3.lockdown import create_using_usbmux; ld = await create_using_usbmux(serial=udid, autopair=False)`; `await ld.get_value(key='DeviceName')` etc. or `ld.all_values`; keys: DeviceName, ProductType, ProductVersion, SerialNumber, TimeZone, DeviceColor, WiFiAddress; `await ld.get_developer_mode_status()`; `await ld.close()`. Shell alternatives: `pymobiledevice3 usbmux list` (JSON: DeviceName, ProductType, ProductVersion, UniqueDeviceID) and `pymobiledevice3 lockdown info --udid X`.
  - DDI check: `pymobiledevice3 mounter list --udid X` (JSON; look for `"IsMounted": true`). Auto-mount if missing: `from pymobiledevice3.services.mobile_image_mounter import auto_mount; await auto_mount(lockdown)` (CLI: `pymobiledevice3 mounter auto-mount --udid X`). Needs internet or Xcode's DDI copy; Xcode is installed.
  - Exceptions: `pymobiledevice3.exceptions` — `PyMobileDevice3Exception` (base), `DeviceNotFoundError`, `NotPairedError`, `NotTrustedError`, `DeveloperModeIsNotEnabledError`, `ConnectionTerminatedError`, `StreamClosedError`, `InvalidServiceError`, `UserspaceTunnelUnavailableError`, `ConnectionFailedToUsbmuxdError`.
  - Optional fallback if the userspace tunnel fails: reuse the farm's go-ios tunnel: `ios tunnel ls` → `[{"address":"fd9d:…::1","rsdPort":63598,"udid":"…"}]`, then `RemoteServiceDiscoveryService((address, port))` + `await rsd.connect()`. Nice-to-have, not required.
- Product-type → marketing names needed: iPhone11,8 = iPhone XR; iPhone12,1 = iPhone 11; iPhone12,3 = iPhone 11 Pro; iPhone12,5 = iPhone 11 Pro Max; iPhone12,8 = iPhone SE (2nd gen); iPhone13,1 = 12 mini; iPhone13,2 = 12; iPhone13,3 = 12 Pro; iPhone13,4 = 12 Pro Max; iPhone14,4 = 13 mini; iPhone14,5 = 13; iPhone14,2 = 13 Pro; iPhone14,3 = 13 Pro Max; iPhone14,6 = SE (3rd gen); iPhone14,7 = 14; iPhone14,8 = 14 Plus; iPhone15,2 = 14 Pro; iPhone15,3 = 14 Pro Max; iPhone15,4 = 15; iPhone15,5 = 15 Plus; iPhone16,1 = 15 Pro; iPhone16,2 = 15 Pro Max; iPhone17,3 = 16; iPhone17,4 = 16 Plus; iPhone17,1 = 16 Pro; iPhone17,2 = 16 Pro Max; iPhone17,5 = 16e; iPhone18,x = 17 family. Unknown → show the raw ProductType.

## Proxy → location (decisions)
- Accept every common SOCKS5 notation: `host:port:user:pass`, `user:pass@host:port`, `socks5://user:pass@host:port`, `socks5h://…`, `host:port` (no auth), `http://…`/`https://…` (treat as an HTTP proxy), IPv6 hosts in brackets, surrounding quotes/whitespace, trailing `/`. If the 4-field colon form is ambiguous, the rule is: if field 2 is numeric → `host:port:user:pass`; else if field 4 is numeric → `user:pass:host:port`.
- Geolocate the **exit IP** by connecting THROUGH the proxy from the Mac with curl: `/usr/bin/curl -sS --max-time 15 --socks5-hostname 'user:pass@host:port' 'http://ip-api.com/json/?fields=status,message,country,countryCode,regionName,region,city,zip,lat,lon,timezone,isp,org,as,query'` (use `--proxy http://…` for HTTP proxies; pass credentials via `--proxy-user` to avoid URL-encoding pitfalls). Provider chain with fallback: ip-api.com (HTTP only on the free tier, 45 req/min) → `https://ipwho.is/` → `https://ipinfo.io/json` (loc is `"lat,lon"`). Normalise into one record (see PROTOCOL.md GeoResult).
- If the proxy connection fails, return a clear error AND a degraded lookup of the proxy host itself (resolve the hostname, geolocate that IP directly) flagged `"gateway IP — may differ from exit IP"`.
- Also geolocate the Mac's own public IP (direct, cached 10 min) so the UI can show the "real location" reference.
- Never log proxy passwords. Mask them in every log line and in the UI by default (reveal on click).

## Engine (Python, `Engine/`)
- `osgps_engine.py` — **hub**, spawned by the app. Speaks newline-delimited JSON on stdin/stdout (PROTOCOL.md). Responsibilities: USB discovery (poll `usbmux.list_devices()` every 2 s; lockdown details cached per UDID and refreshed on reconnect), one **worker subprocess per phone** that has a desired location, forward commands, aggregate state, proxy geolocation (curl subprocesses, concurrent), Mac public-IP geo. The hub keeps a "desired state" map; the app sends the full map on startup and deltas afterwards. The hub persists nothing (the app owns persistence).
- `osgps_engine.py --worker UDID` — **worker**: one userspace tunnel + DVT + LocationSimulation. Commands on stdin: `set {lat,lon}`, `clear`, `quit`. Emits state transitions (connecting → tunnel_up → simulating / released / reconnecting / error). Reconnect with backoff 1, 2, 5, 10, 20, 30 s (cap), re-applying the last desired location automatically. Heartbeat every 5 s; the hub kills and respawns a worker that misses 3 heartbeats. On `quit` and on SIGTERM the worker clears the simulation first (best effort, 3 s budget), then closes the tunnel.
- When a phone disappears from usbmux, the hub marks it `disconnected`, stops its worker, keeps its desired target, and respawns the worker when the phone reappears.
- Logs go to stderr AND to `~/Library/Logs/OnlySocialGPS/engine.log` (RotatingFileHandler, 2 MB × 3). stdout is protocol only. Every line stdout emits must be valid JSON.
- Must be runnable from the terminal for testing: `printf '{"id":1,"cmd":"list_devices"}\n' | /opt/homebrew/bin/python3 Engine/osgps_engine.py`.
- `mock_engine.py` — same protocol, fake phones (from a JSON file or built-in defaults: the four real phones above), scripted state transitions with realistic delays, fake `geolocate_proxy` results (deterministic from a hash of the proxy string, e.g. London / Dallas / Berlin), so the app can be developed and snapshotted without hardware.
- Python 3.14 idioms: `asyncio.run`, `asyncio.create_subprocess_exec`, no deprecated `get_event_loop()`. Standard library only, plus pymobiledevice3.
- Unit tests in `Engine/tests/` (pytest if available, else `unittest`) for the proxy parser, geo normalisation, and protocol framing. Tests must not need hardware.

## App (Swift, `Sources/`)
- Pure SwiftUI with AppKit glue, built with `swiftc -O -parse-as-library Sources/*.swift` by `build.sh` into `dist/Only Social GPS.app`; ad-hoc codesigned (`codesign --force --deep --sign -`); `build.sh --install` copies it to `/Applications/Only Social GPS.app` (no sudo) and relaunches it. Bundle id `com.onlysocial.gps`, `CFBundleIconFile` = `AppIcon`, display name "Only Social GPS", `LSMinimumSystemVersion` 15.0, `NSHighResolutionCapable`. It must appear in the Dock (NOT `LSUIElement`) and ALSO offer a menu-bar status item (template icon `Resources/MenuBarIcon.png`/`@2x`) with a compact fleet summary and quick "Release all / Re-apply all". Copy the pattern of `/Users/james/Desktop/Caffeinate/build.sh` + `Info.plist` (read-only reference).
- Deployment target macOS 15; use `if #available(macOS 26, *)` to adopt Liquid Glass (`.glassEffect()`, `GlassEffectContainer`) with `.ultraThinMaterial`/`.regularMaterial` fallbacks. Compile OFTEN; if a modern API will not compile, fall back rather than fight it.
- The bundle carries the engine at `Contents/Resources/Engine/*.py`. At launch the app finds Python (`/opt/homebrew/bin/python3`, then `/usr/local/bin/python3`, then `/usr/bin/env python3`), verifies `import pymobiledevice3` (a 3 s probe), and if missing shows a friendly setup screen with the copyable fix `pip3 install pymobiledevice3` (Homebrew Python may need `--break-system-packages`).
- Keep every HTTP fetch in the engine (ATS would block plain-HTTP from Swift). MapKit (`Map`, `MKLocalSearch`, `MKReverseGeocoder`/`CLGeocoder`) needs no key and is fine from Swift.
- State persistence: `~/Library/Application Support/Only Social GPS/state.json` (Codable, atomic writes). Per UDID: nickname, proxy string, mode (`proxy` | `manual` | `off`), target {lat, lon}, geo record, scatter radius (m), lastAppliedAt, lastSeenAt, model, iOS. Global: launch-at-login (SMAppService), reapply-on-launch (default on), map style, theme.
- On launch: start the hub, send `hello`, send `set_all` with every desired target, and let the engine bring every connected phone back to its spot. Quitting the app releases all phones (inherent — say so in the UI on quit if any phone is spoofed: "Quitting returns 4 phones to their real GPS. Quit anyway?").
- Snapshot mode (MANDATORY, for agent verification): if env `OSGPS_SNAPSHOT=/path/out.png` is set, the app launches with the mock engine (env `OSGPS_MOCK=/path/mock.json` optional; `OSGPS_SCREEN=<fleet|device|setup|bulk|about>` optional; `OSGPS_SELECT=<udid>` optional), waits 2.5 s, renders the main window's content view (`bitmapImageRepForCachingDisplay` + `cacheDisplay(in:to:)`) to PNG at 2× and exits 0. `OSGPS_ENGINE=mock` alone runs the app interactively against the mock engine. Agents read the PNG with the Read tool to look at the UI.
- Swift 6 language mode is NOT required; use `-swift-version 5` to avoid strict-concurrency churn, but keep UI mutations on the main actor (`@MainActor` observable model). Use `@Observable` (macOS 14+) not ObservableObject.

## UX (what the operator does)
1. Opens the app → sees every phone plugged in, live (hot-plug within ~2 s): nickname (farm handle), model, iOS, a status pill (Real GPS / Locating… / Spoofed · City, Country / Reconnecting / Error) and a colored dot. The window opens at ~1280×820, remembers size/position.
2. Clicks a phone → enters/pastes its SOCKS5 proxy (masked password) → **Locate** → sees exit IP, ISP, city, region, country, flag, timezone, plus a pin on the map → **Pin phone here**. Mode **Proxy** = follow the proxy's geolocation (with a Re-check button and "last checked" time); mode **Manual** = address search (MKLocalSearch), drag the pin, or type lat/lon; a **Scatter** slider (0–3 km, default 0 = exact) adds a random offset so phones on the same ISP don't all sit on one pixel; **Release** returns to real GPS.
3. Fleet view: one map with every phone's pin (labelled by nickname) and the Mac's real location as a hollow marker; per-phone chips; bulk "Paste proxy list" sheet that maps lines to phones in list order (or `handle, proxy` / `handle proxy` pairs) with a preview before applying; "Locate all" + "Pin all".
4. Every state must be designed: no phones connected, engine starting, Python/pymobiledevice3 missing, proxy unreachable, geo provider failing, phone unplugged while spoofed (kept in the list, greyed, "will re-apply when it returns"), worker crash-looping (show the last error and a Retry).
5. Feel: a premium native Mac app. Dark by default (matches the OS mark); the icon's blue → violet → magenta gradient is THE accent (use it for the primary action, the selected state, the status glow, the spoofed pin); glass panels over a subtle, slow animated gradient field; SF Pro (system) type with a disciplined scale; SF Symbols only; information density over decoration — but a genuine "wow" first impression. Keyboard reachable, focus visible, light mode acceptable but dark is the hero.

## Deliverables checklist
- `Engine/osgps_engine.py`, `Engine/mock_engine.py`, `Engine/proxy_geo.py` (parser + geolocation), `Engine/tests/`
- `Sources/*.swift`, `Info.plist`, `build.sh`, `Resources/AppIcon.icns` (exists), `Resources/icon-1024.png`, `Resources/icon-mark.png`, `Resources/MenuBarIcon*.png` (exist)
- `dist/Only Social GPS.app` built, and installed to `/Applications/Only Social GPS.app`
- `README.md` — what it is, how it works (the tunnel/DVT facts above in plain words), how to build, how to run tests, troubleshooting
- `DESIGN.md` — the design system actually implemented
