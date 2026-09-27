# Proposal — "Immersive Map"

Direction in one sentence: the map is the window. Every iPhone is a glowing pin with its handle; the roster and the inspector are two glass cards floating over the map; choosing a phone flies the camera to it. There is no sidebar, no toolbar band, no white chrome — the only opaque surface the operator ever sees is a sheet.

Why this direction fits the job: the operator's three jobs (see phones live → set a proxy and pin → manage the fleet) are all *spatial* questions ("where is each phone claiming to be, and does it match the proxy?"). A map that is always visible answers job 3 at a glance and gives jobs 1–2 an immediate visual confirmation. The icon's gradient becomes literal light on the map.

All colour values below are sampled from `Resources/icon-1024.png` with Pillow (script: 7-point background average, 12-point ring sweep of the O, 15-point spine sweep of the S). Contrast ratios are computed (WCAG 2.x relative luminance), not estimated.

---

## 1. Window layout

Window: `WindowGroup` + `.windowStyle(.hiddenTitleBar)` + `.toolbarBackground(.hidden, for: .windowToolbar)` so the map runs under the title bar; `.defaultSize(width: 1280, height: 820)`; `.frame(minWidth: 1000, minHeight: 700)`; `NSWindow.setFrameAutosaveName("main")` in the AppKit glue for size/position memory. Whole content is one `ZStack`, **not** `NavigationSplitView` (split views cannot put the map behind both panes and force opaque, edge-attached sidebars).

Region sizes at 1280 × 820 (points):

```
 0        16      312   328                                   888   904        1264 1280
 ┌─────────────────────────────────────────────────────────────────────────────────┐ 0
 │ ●●●   (transparent unified toolbar, 38pt, window-draggable)   [Locate all][Pin all][Paste list] [⚙] │ 38
 │ ┌────────────────┐                                            ┌────────────────┐ │ 50
 │ │ Phones      4  │       ·  · ✦ MAP, full-bleed under everything  ·    ·        │ │ Inspector      │ │
 │ │ ● engine ok    │                                            │                │ │
 │ ├────────────────┤          ◉ @onlyemspage                   │ @nat.hunterrr  │ │
 │ │ ◉ @nat.hunterrr│           (Spoofed · Dallas)               │ iPhone XR·18.7 │ │
 │ │   XR · 18.7.9  │                                            │ [Spoofed·Lon.] │ │
 │ │  Spoofed·London│                     ◉ @onlyglazertori      ├────────────────┤ │
 │ ├────────────────┤                       (London)             │ Proxy Manual Off│ │
 │ │ ◉ @onlyemspage │                                            │ ┌────────────┐ │ │
 │ │   XR · 18.7.9  │     ○ This Mac (Dartmouth, NS)             │ │socks5h://… │ │ │
 │ │  Spoofed·Dallas│                                            │ └────────────┘ │ │
 │ ├────────────────┤                                            │ ✓ socks5h · …  │ │
 │ │ ◌ @onlyglazert…│                ◉ @ellybellywellyyy         │ [ Locate  ⌘L ] │ │
 │ │   XR · 18.7.9  │                  (Reconnecting)            ├────────────────┤ │
 │ │  Unplugged     │                                            │ 🇬🇧 London      │ │
 │ ├────────────────┤                                            │ England, UK    │ │
 │ │ ◉ @ellybelly…  │                                            │ IP 81.2.69.142 │ │
 │ │   11 · 18.7.8  │                                            │ ISP Virgin Med.│ │
 │ │  Reconnecting  │                                            │ TZ Europe/Lon. │ │
 │ │                │                                            ├────────────────┤ │
 │ │                │                                            │ Scatter ──●─ 0m│ │
 │ │                │                                            │                │ │
 │ ├────────────────┤            ┌──────────────────────┐        │ [Pin phone here]│ │
 │ │ ○ This Mac     │            │ ✓ Pinned @nat… London │ toast │ [Re-check][Rel.]│ │
 │ │ Dartmouth · Bell│           └──────────────────────┘        │                │ │
 │ │ py 3.14 · pmd3 │                                        ⊕ N │                │ │
 │ └────────────────┘                                            └────────────────┘ │ 804
 └─────────────────────────────────────────────────────────────────────────────────┘ 820
```

| Region | Frame (x, y, w, h) | SwiftUI construct |
|---|---|---|
| Map canvas | 0, 0, 1280, 820 | `Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) { … }.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)).ignoresSafeArea()` |
| Map veil | same | `Color(hex: 0x0E1118).opacity(0.35).allowsHitTesting(false)` over the map — pulls MapKit's dark tiles toward the icon background |
| Gradient field | same | `MeshGradient(width: 3, height: 3, …)` in a `TimelineView(.animation(minimumInterval: 1/30))`, opacity 0.10, `.blendMode(.screen)`, `.allowsHitTesting(false)` |
| Title strip | 0, 0, 1280, 38 | system unified-compact toolbar, background hidden; traffic lights at their native spot; `.toolbar { ToolbarItemGroup(placement: .primaryAction) }` for the three fleet actions + gear |
| Roster card | 16, 50, 296, 754 | `VStack` in `.glassEffect(.regular, in: .rect(cornerRadius: 20))` (macOS 26) / `.background(.ultraThinMaterial)` + tint (macOS 15); rows in a `ScrollView` + `LazyVStack` |
| Inspector card | 904, 50, 360, 754 | same glass; content is a `ScrollView`; switches between *Fleet* and *Phone* content by selection |
| Unobstructed map | 328, 38, 560, 782 | the Map gets `.safeAreaInset(edge: .leading) { Color.clear.frame(width: 312) }` and `.trailing … 376` so camera fitting (`.region`, `.rect`) and `MapCompass`/`MapScaleView` respect the cards (verify at build; fallback = manual inset of the `MKMapRect`) |
| Toast zone | centred at x 608, y 760, w ≤ 420, h 44 each | `overlay(alignment: .bottom)` on the map, `VStack(spacing: 8)` of toasts, max 3 |
| Map controls | bottom-right of unobstructed area (x 840–880, y 740–800) | `.mapControls { MapCompass(); MapScaleView() }` |

Minimum size 1000 × 700 (nothing collapses; everything narrows; inspector scrolls):

```
 0   16     272 288                     648 664       984 1000
 ┌──────────────────────────────────────────────────────────┐ 0
 │ ●●●                     [Locate all][Pin all][Paste][⚙]  │ 38
 │ ┌──────────┐                            ┌────────────┐   │ 50
 │ │ Phones 4 │        ◉ @onlyemspage      │ @nat.hunt… │   │
 │ ├──────────┤                            │ XR · 18.7.9│   │
 │ │◉ @nat.h… │   ○ This Mac               │ [Spoofed]  │   │
 │ │ Spoofed  │                 ◉ @ellyb…  ├────────────┤   │
 │ ├──────────┤                            │Proxy Man Off│  │
 │ │◉ @onlye… │                            │ [socks5h…] │   │
 │ │ Spoofed  │                            │ [Locate]   │   │
 │ ├──────────┤                            │ 🇬🇧 London  │   │
 │ │◌ @onlyg… │                            │ IP · ISP · │   │
 │ │ Unplugged│                            │ TZ         │   │
 │ ├──────────┤                            │ Scatter    │   │
 │ │◉ @ellyb… │   ┌────────────┐           │ [Pin here] │   │
 │ │ Reconn.  │   │ toast      │           │ [Re-check] │   │
 │ ├──────────┤   └────────────┘        ⊕  │ (scrolls)  │   │
 │ │○ This Mac│                            │            │   │
 │ └──────────┘                            └────────────┘   │ 684
 └──────────────────────────────────────────────────────────┘ 700
```

At 1000 wide: roster 256 × 634, inspector 320 × 634, unobstructed map 360 × 662. Phone rows drop to 60pt; the status pill truncates its city ("Spoofed · London"). The three toolbar actions keep icons and drop labels below 1120 wide (`.labelStyle(.iconOnly)`).

---

## 2. Navigation model

- One window, one screen, zero push/pop. The entire navigation state is `selectedUDID: String?` on the `@MainActor @Observable AppModel`.
- `nil` → **Fleet mode**: inspector shows the fleet card, camera fits all pins + the Mac marker (48pt inner padding).
- `some` → **Phone mode**: inspector shows that phone, camera flies to its target (or to the Mac if it has none), the roster row and the pin both render selected.
- Ways to select: click a roster row; click a pin; `⌘1`…`⌘9`; `↑`/`↓` with focus in the roster; click a chip in the fleet card. Ways to deselect: `Esc`, click empty map, `⌘0` (also re-fits all).
- Sheets (never windows): **Paste proxy list** (`⌘⇧V`), **Quit confirmation** (intercepts `⌘Q` via `NSApplicationDelegate.applicationShouldTerminate` when any phone is `simulating`/`reconnecting`), **Settings** (`⌘,` — a 420pt sheet, not a Settings scene, so it stays glass-adjacent). About uses the standard panel.
- **Setup screen** (Python/pymobiledevice3 missing) replaces the card layer: map stays behind at 80% veil, one centred 520pt card. **Engine starting** is not a screen; it is a state of the roster header.
- Snapshot mapping: `OSGPS_SCREEN=fleet` → `selectedUDID = nil`; `device` → first phone (or `OSGPS_SELECT`); `setup` → setup card; `bulk` → paste sheet open; `about` → about panel. The first-launch intro (§8) must be finished by 2.2 s so the 2.5 s snapshot captures the settled state.

---

## 3. Colour tokens

Sampling results (Pillow, RGBA, alpha > 250 only):
- Background: `#0E1118` at (80,80), (512,900), (880,880), (512,512); `#0F1119` at (512,120), (940,512), (160,512). Icon background = **#0E1118**.
- O outer ring, centre (400,512) r = 205: 180° `#2D78FD`, 150° `#2073F0`, 120° `#1864D7`, 210° `#426AFC`, 240° `#5E59FB`, 270° `#7C54FF`, 300° `#7F44FB`, 0° `#6449FA`. Left stroke at (215,512): `#2E75FD`.
- S spine: (640,490) `#6147F8`, (700,520) `#7A43FE`, (760,560) `#943EFF`, (800,610) `#A633FF`, (790,660) `#AD34FF`, (740,700) `#AB2FFF`. Most saturated magenta pixel on the mark: `#BF35FF` at (771,703), hue 281°. Most saturated blue: hue 212°.
- The brand gradient is therefore blue **#2E75FD** → violet **#7445FC** → magenta **#A033FF**, running roughly 135° (top-left to bottom-right) with the violet midpoint where the letters overlap.

### Dark (default, the hero)

| Token | Value | Derivation / use |
|---|---|---|
| `canvas.base` | `#0E1118` | icon background; window background before the map loads; setup/empty ground |
| `map.veil` | `#0E1118` @ 35% | over MapKit dark tiles; brightest veiled tile ≈ `#20232A` (assuming MapKit's brightest dark land/road tile ≈ `#2A2D34`) |
| `surface.glass` | `#141826` @ 72% tint on `.regular` glass / `.ultraThinMaterial` | cards; effective worst-case surface ≈ **`#171B27`** (all card contrast checks use this) |
| `surface.raised` | `#1C2130` | sheets, menus, popovers, Reduce-Transparency fallback for cards |
| `surface.field` | `#0E1118` @ 60% | text fields, segmented track, slider track |
| `stroke.hairline` | `#FFFFFF` @ 10% | card edge, row separators, field border |
| `stroke.strong` | `#FFFFFF` @ 18% | hover borders; 30% under Increase Contrast |
| `text.primary` | `#F2F4F8` | 15.6:1 on glass |
| `text.secondary` | `#A9B0C0` | 7.9:1 on glass |
| `text.tertiary` | `#7D869A` | 4.7:1 on glass — captions and timestamps only |
| `accent.blue` | `#2E75FD` | fills, dots, gradient start (icon O left stroke) |
| `accent.violet` | `#7445FC` | fills, selected state, scatter circle (icon S middle bar) |
| `accent.magenta` | `#A033FF` | fills, gradient end, spoofed glow (icon S bowl) |
| `accent.hot` | `#BF35FF` | 1pt highlight on the selected pin's ring only |
| `accent.deepBlue` | `#1864D7` | button gradient start (the icon's O ring at 120°) — chosen because white on `#2E75FD` is only 4.13:1, white on `#1864D7` is 5.46:1 |
| `gradient.brand` | linear 135°: `#2E75FD` 0% → `#7445FC` 50% → `#A033FF` 100% | spoofed pin fill, selected-row bar, status glow, intro shimmer |
| `gradient.button` | linear 135°: `#1864D7` → `#7445FC` → `#A033FF` | primary buttons (all three stops pass 4.5:1 with white) |
| `accent.blueText` | `#6FA0FF` | links, "Locating…" text, focus ring — 6.67:1 |
| `accent.violetText` | `#A88BFF` | "Spoofed" pill text — 6.38:1 |
| `accent.magentaText` | `#CF7BFF` | coordinates of the selected pin — 6.49:1 |
| `status.real` | `#9AA3B5` | Real GPS dot/pill — 6.77:1 |
| `status.locating` | `#6FA0FF` | pulsing dot |
| `status.reconnecting` | `#F5B342` | 9.33:1 |
| `status.error` | `#FF6B81` | 6.28:1 |
| `status.ok` | `#4ADE80` | engine-healthy dot — 9.86:1 |
| `glow.spoofed` | radial `#A033FF` 45% → 0% over 28pt | behind spoofed pins and the selected row's dot |
| `shadow.card` | 0 12 32 `#000000` @ 45% + inner top 1pt `#FFFFFF` @ 6% | cards |
| `shadow.button` | 0 6 16 `#7445FC` @ 35% | primary button |
| `chip.label` | `#0E1118` @ 85% | pin label backing — white on it over the brightest tile: 18.3:1 |

### Light (acceptable, not the hero)

| Token | Value | Note |
|---|---|---|
| `canvas.base` | `#F3F4F8` | |
| `map.veil` | `#FFFFFF` @ 20% | |
| `surface.glass` | `#FFFFFF` @ 78% | effective ≈ `#FAFAFC` over a light tile |
| `surface.raised` | `#FFFFFF` | |
| `surface.field` | `#0E1118` @ 5% | |
| `stroke.hairline` / `strong` | `#0E1118` @ 10% / 18% | |
| `text.primary` | `#121623` | 18.0:1 on card |
| `text.secondary` | `#4E5668` | 7.36:1 |
| `text.tertiary` | `#687083` | 4.96:1 on white, 4.76:1 on light glass (`#6F7789` failed at 4.49 — rejected) |
| accents (fills, gradients) | identical hexes to dark | the gradient is the brand; it does not change with theme |
| `accent.blueText` / `violetText` / `magentaText` | `#1F5FE0` / `#5B2FE0` / `#8A1FE0` | 5.57 / 7.17 / 6.26:1 |
| `status.reconnecting` / `error` / `ok` / `real` | `#A86400` / `#D12645` / `#15803D` / `#5C6577` | 4.68 / 5.15 / 5.02 / ≥ 5:1 |
| `shadow.card` | 0 8 24 `#0E1118` @ 18% | |

---

## 4. Type scale (SF Pro via `.system`, no custom fonts)

| Role | Size / weight | Extras | Where |
|---|---|---|---|
| Display | 28 / semibold | tracking −0.4 | empty state, setup title, intro |
| Title | 17 / semibold | | card headers ("Phones"), selected nickname, geo city |
| Header | 11 / semibold | uppercase, tracking +0.6, `text.secondary` | section labels PROXY · LOCATION · SCATTER |
| Body | 13 / regular | | rows, descriptions |
| Body emphasised | 13 / medium | | nickname in rows, button labels use 13 / semibold |
| Caption | 11 / regular | `text.secondary` / `text.tertiary` | model · iOS, "checked 2 min ago" |
| Pill | 11 / semibold | | status pills, chips |
| Mono | 12 / regular, `design: .monospaced` | `.monospacedDigit()` on all numerals in Body | coordinates, IPs, ports, UDIDs, the pip command |
| Mono small | 11 / regular monospaced | | error excerpts, log lines |
| Pin label | 11 / semibold | on `chip.label` | map annotations |

Spacing grid: 4pt base; 8 inside components, 12 between related elements, 16 card padding, 20 between inspector sections, 24 above the primary action group.

---

## 5. Component inventory

**Phone row** (`Button` in the roster's `LazyVStack`, 64pt × full width, 12pt padding, radius 12): left 10pt status dot (+ 28pt glow when spoofed) · nickname 13 medium + "iPhone XR · 18.7.9" caption · right-aligned status pill.
States: `idle` (grey dot, pill "Real GPS") · `connecting`/`tunnel_up` (blue dot pulsing, pill "Starting…" with 10pt `ProgressView`) · `simulating` (gradient dot + glow, pill "Spoofed · London, GB") · `reconnecting` (amber dot pulsing slow, pill "Reconnecting · 5 s") · `error` (red dot steady, pill "Error", row shows a `chevron.right` hint) · `released` (grey, pill "Real GPS" — 2 s crossfade from previous) · `disconnected` (row at 55% opacity, dot becomes a dashed 1pt ring, pill "Unplugged · will re-apply", row stays in place) · **hover** `#FFFFFF` @ 6% · **selected** `#7445FC` @ 22% fill (effective `#2B2456`, primary text 12.8:1, secondary 6.48:1) + 2pt `gradient.brand` bar on the left edge via `matchedGeometryEffect` · **focused** 2pt `accent.blueText` inset ring.
Context menu: Locate · Pin · Release · Copy UDID · Copy proxy (masked) · Restart worker.

**Status pill** (`Capsule`, 20pt tall, 8pt horizontal padding, Pill type): Real GPS (`status.real` @ 16% fill, `status.real` text) · Locating… (`accent.blue` @ 16%, `accent.blueText`, 6pt dot pulses) · Spoofed · City, CC (`accent.violet` @ 16% fill, 1pt `gradient.brand` stroke, `accent.violetText`) · Reconnecting · Ns (`status.reconnecting` @ 16%, amber text, countdown via `contentTransition(.numericText())`) · Error (`status.error` @ 16%, red text) · Unplugged (`status.real` @ 10%, dashed 1pt stroke, grey text) · Starting (blue @ 16%, spinner). Light text on the magenta fill was rejected (4.32:1) — that is why pills use tinted fills + accentText, never solid brand fills.

**Proxy field** (36pt, `surface.field`, hairline stroke, radius 10, Mono 12; `TextField` bound to the raw string): placeholder "host:port:user:pass  or  socks5://user:pass@host:port". Unfocused it renders the engine's `normalized` form (`socks5h://jd_04:•••••@45.12.8.2:1080`); focused it shows the raw string for editing; an `eye`/`eye.slash` 28pt icon button at the trailing edge reveals the password in the unfocused form (reveal is per-session, never persisted). Below it an 18pt **live parse line** fed by `parse_proxy` debounced 250 ms: `checkmark.circle.fill` green + "socks5h · 45.12.8.2:1080 · user jd_04" (Caption) or `xmark.octagon.fill` red + "Can't parse — expected host:port" ; empty string → the line is blank. Paste (`⌘V`) strips quotes/whitespace/trailing slash visibly. Focus ring 2pt `accent.blueText`.

**Geo result card** (inset card on `surface.field`, radius 14, 16pt padding): header row — flag emoji 22pt (from `country_code`, `regionalIndicator` transform), city Title, "England, United Kingdom" Body secondary; rows on a 2-column grid (label Header, value Body / Mono): IP `81.2.69.142` (mono, `doc.on.doc` copy button 24pt), ISP "Virgin Media" (org in caption if different), ASN `AS5089`, Timezone `Europe/London` + live local time "14:02" (mono, updates each minute), coordinates `51.5074, −0.1278` (mono, `accent.magentaText` when this is the applied target). Footer caption: "Checked 2 min ago · ip-api.com · 1.2 s".
States: **empty** (dashed hairline outline, `globe` 24pt tertiary, "Locate to see the exit IP") · **loading** (3 shimmering skeleton rows + stage text from `geo_progress`: "Connecting through proxy…" → "Querying ip-api.com…" → "Trying ipwho.is…") · **success** · **stale** (> 10 min: footer turns amber, Re-check button gains a dot) · **proxy unreachable** (red header `exclamationmark.triangle.fill` "Proxy unreachable" + engine message in Mono small; if `fallback` present, the fallback record renders beneath at 70% opacity with an amber banner "Gateway IP — may differ from exit IP" and a secondary button "Use gateway location anyway") · **geo failed** ("All three providers failed" + Retry; hint "Switch to Manual to place the pin yourself").

**Map pins** (`Annotation(coordinate:anchor: .center)`; custom view; z-order: selected > error > spoofed > pending > real):
- *Spoofed*: 14pt circle filled with `gradient.brand`, 2pt `#FFFFFF` ring, 28pt `glow.spoofed` halo, label chip below (Pin label on `chip.label`, radius 6, 4×8 padding).
- *Pending* (`connecting`/`tunnel_up`/Locating): 14pt `accent.blue` fill, white ring, an expanding pulse ring 14 → 40pt, opacity 0.6 → 0, 1.2 s loop.
- *Real* (idle/released, drawn at the Mac's location): 10pt `status.real` fill, no glow, no label — the handle is only shown for spoofed/pending phones so real-GPS phones stack quietly on the Mac marker; hovering the Mac marker lists them.
- *Mac* ("This Mac"): 16pt hollow ring, 2pt `#FFFFFF` @ 80%, label "This Mac · Dartmouth".
- *Reconnecting*: amber fill, dashed 1.5pt ring rotating 1 rev / 4 s; *Error*: `status.error` fill with `exclamationmark` 8pt white; *Disconnected*: the target pin at 40% opacity, dashed grey ring, label italic-less but suffixed "(unplugged)".
- *Selected*: scale 1.25, ring becomes `accent.hot`, label chip gets a 1pt `gradient.brand` stroke.
- *Scatter*: `MapCircle(center:radius:)` `accent.violet` @ 12% fill, 1pt `accent.violet` @ 60% stroke, only when radius > 0. Manual mode also draws a draggable pin (`.draggable` gesture on the Annotation with `MapReader`/`MapProxy.convert` to get coordinates).

**Mode segmented control** (custom 3-segment capsule, 32pt tall, `surface.field` track, 2pt inset): Proxy · Manual · Off. Selected segment = `gradient.button` fill + white 13 medium; unselected = `text.secondary`; `←`/`→` move selection when focused; `Picker(.segmented)` is the fallback if the custom control misbehaves. Choosing **Off** is the Release action (confirms nothing — it is reversible). Manual mode swaps the proxy section for: search field (`MKLocalSearch`, results in a 5-row list), lat/lon Mono fields with validation (−90…90, −180…180), and "Drag the pin on the map" caption.

**Scatter slider** (`Slider(value:in: 0…3000, step: 50)`, tint `accent.violet`, 24pt tall): value label Mono "0 m · exact" / "1 250 m"; ticks at 0 / 1 / 2 / 3 km as captions; live `MapCircle` while dragging; caption "Re-rolled on every Pin so phones on one ISP don't share a pixel."

**Buttons**: *Primary* 36pt, radius 10, `gradient.button`, white 13 semibold, `shadow.button`; hover +6% brightness; pressed scale 0.97; disabled 40% opacity and no shadow; loading = 14pt spinner replaces the leading symbol, label stays. *Secondary* 36pt, `surface.field` fill, hairline stroke, `text.primary`; hover `#FFFFFF` @ 8%. *Destructive text* ("Release") `status.error` text, no fill, 28pt. *Icon buttons* 28 × 28, radius 8, symbol 15pt medium. Primary in phone mode: **Locate** (until a geo result exists) → **Pin phone here** (after); Re-check and Release are secondary/destructive beneath. Fleet mode: **Pin all** primary, **Locate all** and **Paste proxy list…** secondary.

**Toasts** (glass capsule, 44pt, radius 22, symbol + Body + optional action, `overlay(alignment: .bottom)`): success `checkmark.circle.fill` `status.ok` ("Pinned @nat.hunterrr in London"); info; warning amber; error red persists until dismissed (`xmark` 24pt), others auto-dismiss after 4 s; max 3 stacked, oldest evicted.

**Sheets** (`surface.raised`, system sheet): *Paste proxy list* 640 × 520 — left half `TextEditor` Mono 12 ("one proxy per line, or `handle, proxy` / `handle proxy` pairs"), right half preview `Table` with columns Phone · Proxy (masked) · Parse (✓ / ✗ reason); detection caption "Matched by handle" or "Mapped in list order — line 5 has no phone"; footer toggle "Locate after applying" (on) + secondary Cancel + primary "Apply to 4 phones". *Quit confirmation* — custom 420pt sheet, not an `Alert`: OS mark 32pt, Title "Quitting returns 4 phones to their real GPS.", Body "They will be pinned again the next time the app starts.", buttons: secondary **Keep running** (default, `Return`), destructive-styled primary **Quit anyway** (`⌘Q` again / `⌘⏎`).

**Setup screen** (map behind at 80% veil, centred 520 × ~360 glass card, 24pt padding): OS mark 64pt with the gradient shimmer, Display "One thing before we start", Body "Only Social GPS talks to your iPhones through pymobiledevice3. It isn't installed for `/opt/homebrew/bin/python3` yet." Code block (`surface.field`, Mono 12) `pip3 install pymobiledevice3` with a copy button and a small toggle "Homebrew Python needs `--break-system-packages`" that rewrites the command; primary **Check again** (re-runs the 3 s probe, spinner while probing); caption with the detected interpreter path and version. Variant copy for *no Python at all* ("We couldn't find python3 — install it with Homebrew: `brew install python`").

**Empty state (no phones)**: camera parks on the Mac (distance 40 km) with the hollow marker breathing (ring 16 → 20pt, 3 s). Roster body: `cable.connector` 36pt `text.tertiary`, Title "No iPhones on USB", Body secondary "Plug one in — it appears here within two seconds.", caption "Engine running · Python 3.14.6 · pymobiledevice3 10.7.3". Fleet inspector shows 0 chips, Paste list enabled (targets can be prepared ahead), Pin all disabled.

**Engine starting**: roster header pill "Starting engine…" with spinner; 3 skeleton rows shimmer (0.9 s sweep); toolbar actions disabled; > 8 s: caption "Taking longer than usual…" + text button "Show log" (opens `~/Library/Logs/OnlySocialGPS/engine.log` in Console).

**Unplugged while spoofed**: row/pin as above; inspector gets an amber banner "Unplugged · target kept · re-applies when it returns" with the target coords; Locate/Pin disabled; Release stays enabled (clears the desired target).

**Crash-looping worker**: red banner in the inspector: "Worker keeps failing" + `last_error` in Mono small (3 lines, "Show more" expands), "Restarts: 4 · retrying every 60 s", buttons primary **Retry now** (`worker_restart`) + secondary **Show log**. Pin turns error style; toast once per burst, not per restart.

**Fleet inspector** (nothing selected): summary line "4 phones · 2 spoofed · 1 reconnecting · 1 real"; wrap of per-phone chips (Pill style, click selects); actions; "This Mac" geo result (compact: flag, city, ISP, IP); engine line (python / pymobiledevice3 / pid, `status.ok` dot); map-style toggle (Muted · Standard · Imagery-off, keeps the veil).

---

## 6. Motion spec

| What | Duration / curve | Detail |
|---|---|---|
| Layout / selection | `.spring(response: 0.35, dampingFraction: 0.85)` | selection bar slides between rows (`matchedGeometryEffect`), inspector content crossfades with an 8pt vertical slide (250 ms) |
| Colour / opacity | `.easeInOut(duration: 0.2)` | dot colour, pill fill, row opacity on disconnect |
| Pill text | `contentTransition(.numericText())` / `.opacity` 200 ms | countdowns tick without jumping |
| Locating / pending pulse | 1.2 s loop, `.easeOut`, `repeatForever` | ring scale 1 → 2.85 (14 → 40pt), opacity 0.6 → 0 |
| Reconnecting | 4 s / rev linear | dashed ring rotates; pulse slows to 2 s |
| Camera fly-to (select) | 0.9 s `.easeInOut` on `MapCameraPosition.camera(MKMapCamera(lookingAt:, distance: 12 000 m, pitch: 0, heading: 0))` | distance = max(12 km, scatter × 8); from far away MapKit's own arc is used |
| Camera fit-all (deselect / `⌘0`) | 0.7 s `.easeInOut` to `.rect(fitting all, inset 48)` | |
| Pin drop (first `simulating`) | scale 0.4 → 1 with `.spring(response: 0.45, dampingFraction: 0.6)`; halo 0 → 28pt over 600 ms; label fades in 150 ms after | |
| Pin move (target change) | 400 ms `.easeInOut` | annotation coordinates are interpolated in the model via `TimelineView` (SwiftUI `Annotation` does not tween coordinates) |
| Gradient field | 24 s loop, control points drift ±0.06 | `MeshGradient` 3×3, opacity 0.10 dark / 0.06 light; paused when the window is not key; static under Reduce Motion |
| Glow breathe (spoofed dot in roster) | 3 s loop | halo opacity 0.35 ↔ 0.55 |
| Toast | in 250 ms spring (from +8pt, 0 α), out 200 ms ease | |
| Skeleton shimmer | 0.9 s linear sweep | gradient `#FFFFFF` @ 0 → 8% → 0 |
| Reduce Motion | all loops static, fly-to becomes a 200 ms crossfade of the camera, pin drop becomes a fade | via `@Environment(\.accessibilityReduceMotion)` |

---

## 7. Menu-bar extra

`MenuBarExtra { … } label: { Image("MenuBarIcon") }` with `.menuBarExtraStyle(.window)` (template PNG, existing asset). When any phone is in `error` or has been `reconnecting` > 30 s, the label appends the text "!" (SF-symbol-free, template-safe). Panel 300pt wide, `surface.raised`, 12pt padding:
- Header: "4 phones · 2 spoofed · 1 real" Body + engine dot (`status.ok` / amber / red).
- Rows 32pt: dot · nickname 13 medium · compact pill (city only). Click opens the main window with that phone selected (`openWindow` + `selectedUDID`).
- Footer: primary small (28pt) **Re-apply all** · secondary **Release all** · text link "Open Only Social GPS". No Quit here — quitting is a decision that belongs to the window's confirmation sheet.
- Updates live from the same `AppModel`; keyboard: `↑`/`↓` rows, `Return` opens.

---

## 8. The "wow" moment (first launch only)

Timeline, total 2.2 s, any click or key skips to the end state:
- 0 ms — window appears on `canvas.base`; the OS mark (`icon-mark.png`, 96pt) sits centred with a `gradient.brand` shimmer sweeping across it once (700 ms). No text.
- 300 ms — the map fades in beneath (veil 100% → 35% over 900 ms) while the camera starts over the North Atlantic at 20 000 km and flies down to the fleet (or the Mac) over 1.8 s `.easeInOut`. The gradient field fades in at the same time.
- 1 100 ms — roster slides in from −24pt on the left, inspector from +24pt on the right, both 350 ms spring; the mark shrinks and glides into the roster header (`matchedGeometryEffect`) and becomes the 20pt app mark next to "Phones".
- 1 300 ms onward — pins drop in staggered by 120 ms in roster order as `device_state` arrives; each spoofed pin's halo blooms. The camera fit-all settles by 2 100 ms.
- Every later launch: a 600 ms version (no globe; map fades, cards slide, pins drop). Reduce Motion: a single 400 ms crossfade.
- Why this is the wow: the operator sees the icon *become* the map, then sees four glowing pins land in four countries that they know are one desk in Dartmouth. It demonstrates the whole product in two seconds without a word of onboarding.

---

## 9. Accessibility

Contrast (computed; glass surface modelled as `#141826` @ 72% over the brightest veiled tile `#20232A` → `#171B27`):

| Pair | Ratio | Verdict |
|---|---|---|
| `text.primary` #F2F4F8 on glass / on canvas #0E1118 | 15.60 / 17.15 | AAA |
| `text.secondary` #A9B0C0 on glass / canvas | 7.90 / 8.69 | AAA |
| `text.tertiary` #7D869A on glass / canvas | 4.70 / 5.17 | AA (captions only) |
| `accent.blueText` #6FA0FF on glass | 6.67 | AA (also ≥ 3:1 as a focus ring) |
| `accent.violetText` #A88BFF / `magentaText` #CF7BFF on glass | 6.38 / 6.49 | AA |
| white on `gradient.button` stops #1864D7 / #7445FC / #A033FF | 5.46 / 5.25 / 4.76 | AA at every stop (13 semibold) |
| white on #2E75FD (rejected as a button start) | 4.13 | fail — hence `accent.deepBlue` |
| `status.reconnecting` #F5B342 / `error` #FF6B81 / `ok` #4ADE80 / `real` #9AA3B5 on glass | 9.33 / 6.28 / 9.86 / 6.77 | AA+ |
| pin label white on `chip.label` over the brightest tile | 18.26 | AAA |
| `text.primary` on the selected row (#2B2456) / secondary | 12.80 / 6.48 | AAA / AA |
| raw `accent.blue` #2E75FD, `violet` #7445FC, `magenta` #A033FF as text on glass | 4.15 / 3.27 / 3.61 | never used as text |
| Light: primary #121623 on white / secondary #4E5668 / tertiary #687083 | 18.03 / 7.36 / 4.96 | AAA / AAA / AA |
| Light: blueText #1F5FE0 / violetText #5B2FE0 / magentaText #8A1FE0 on white | 5.57 / 7.17 / 6.26 | AA |
| Light: amber #A86400 / red #D12645 / green #15803D on white | 4.68 / 5.15 / 5.02 | AA |

Hairline strokes (1.34:1) are decorative and are backed by shadow; under Increase Contrast they go to 30% white and the map veil to 50%. Reduce Transparency swaps `surface.glass` for opaque `surface.raised`.

Keyboard flow: Tab order = toolbar actions → roster (one focus stop, `↑`/`↓` move the selection, `Return` focuses the proxy field) → inspector top-to-bottom (mode control `←`/`→`, proxy field, eye toggle, Locate, geo copy buttons, slider `←`/`→` 50 m steps, primary button) → map (arrow keys pan, `+`/`−` zoom). Shortcuts: `⌘L` Locate · `⌘⏎` Pin phone here · `⌘R` Re-check · `⌘⌫` Release · `⌘⇧L` Locate all · `⌘⇧⏎` Pin all · `⌘⇧V` Paste proxy list · `⌘0` fit all / deselect · `⌘1`–`⌘9` select phone · `⌘,` settings · `Esc` deselect / close sheet. Focus ring: 2pt `accent.blueText` + 4pt outer glow at 30%, never suppressed. Hit targets ≥ 24 × 24; rows 64pt. VoiceOver: row label "nat.hunterrr, iPhone XR, spoofed in London, United Kingdom"; pins carry the same label; the map is `accessibilityElement(children: .contain)`; toasts post as `.announcement`. Live regions: the roster header count and pills announce changes via `accessibilityValue`.

---

## 10. Build notes, risks, open questions

- Cards use `GlassEffectContainer { … }.glassEffect(.regular.tint(#141826 @ 0.72), in: .rect(cornerRadius: 20))` on macOS 26 and `.background(.ultraThinMaterial)` + `Color(#141826).opacity(0.55)` + hairline stroke + `shadow.card` on macOS 15. Both paths render the same tokens; snapshot both.
- Whether SwiftUI `Map` honours `.safeAreaInset` for camera fitting must be confirmed on the first build; if not, compute the fit region manually with the card widths as inset ratios (312/1280 and 376/1280).
- MapKit dark tile colours are assumed (brightest ≈ `#2A2D34`); after the first snapshot, re-sample the real tile behind a card and re-run the contrast script if the sample is lighter than `#2A2D34`.
- `Annotation` coordinate tweening is done in the model (400 ms `TimelineView` interpolation) — small cost, worth it.
- The 2.5 s snapshot must capture the settled state: the intro ends at 2.2 s and is skipped entirely when `OSGPS_SNAPSHOT` is set.
- Nothing in this proposal needs an image asset beyond `icon-mark.png` and `MenuBarIcon*.png`; every glyph is an SF Symbol (`cable.connector`, `globe`, `eye`, `eye.slash`, `doc.on.doc`, `checkmark.circle.fill`, `xmark.octagon.fill`, `exclamationmark.triangle.fill`, `location.fill`, `mappin.and.ellipse`, `arrow.clockwise`, `gearshape`).
