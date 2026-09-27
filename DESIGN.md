# Only Social GPS — DESIGN.md (the implementable spec)

Direction: **Mission Control** — a dark three-pane console. Left, a dense roster you scan in a second. Centre, the map framed as an instrument in a bezel with a telemetry strip along its foot. Right, an inspector that follows the selection. The icon's gradient is used as *light* (glows, a lit edge, pin halos, three slow lobes behind glass) and as *paint* in exactly five places: the primary button, the selected row's bar + tint, the spoofed pin, the spoofed dot, the gradient field. Nowhere else — no gradient text, borders, icons or sliders. Everything is SwiftUI on macOS 15+ (Liquid Glass behind `if #available(macOS 26, *)`), SF Pro, SF Symbols, MapKit; the only image assets are `icon-mark.png` and `MenuBarIcon*.png` loaded with `NSImage(named:)` / `NSImage(contentsOf:)` from `Contents/Resources` (no asset catalog).
Judging and the reasons for every grafted or overridden idea: `Design/judging.md`.

## 1. Window and layout

- `WindowGroup("Only Social GPS")` `.defaultSize(width: 1280, height: 820)`; root view `.frame(minWidth: 1000, minHeight: 700)`; `.windowToolbarStyle(.unified)`; title hidden (`.navigationTitle("")` + `window.titleVisibility = .hidden`). AppKit glue in `applicationDidFinishLaunching`: `window.setFrameAutosaveName("OSGPS.main")` (restores size/position), `window.backgroundColor = NSColor(bg.window)`, `window.tabbingMode = .disallowed`, `window.minSize = (1000, 700)`.
- Colour scheme: `.preferredColorScheme(model.settings.theme.colorScheme)` on the root (`nil` = system, default **dark**).
- Root: `ZStack { GradientField(); switch model.phase { .probing, .setup: SetupView() ; default: ConsoleView() } }`.
- `ConsoleView` = `HSplitView { RosterView() ; MapStage() ; if model.inspectorShown { InspectorView() } }`. The panes are our own views over the field: roster and inspector get `.background(PaneMaterial())` (§3f). **Not** `NavigationSplitView`/`.inspector`: their columns draw behind-window materials that hide in-window content, so the field would never show through the panels.

Sizes in points (toolbar is 52 tall on top of these):

| Region | 1280 × 820 | 1000 × 700 (min) | Construct |
|---|---|---|---|
| Roster | 272 wide (`.frame(minWidth: 220, idealWidth: 272, maxWidth: 320)`) | 220 | `VStack { SearchField 28 ; List(selection:) ; RosterFooter 44 }` |
| Map stage | fills (min 480) | 480 | `MapReader { Map(…) }` inset 8 on all sides, clipped `RoundedRectangle(10)`, 1pt `hairline` stroke; overlays: telemetry strip, toasts, banners |
| Inspector | 320 (`minWidth: 292, idealWidth: 320, maxWidth: 360`) | 300 | `ScrollView { VStack(alignment: .leading, spacing: 12) }.padding(16)` |

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ ●●●  [⌕ Search phones]        Locate all  Pin all  Release all   Paste list   ⊞  ▯   │ 52
├──────────────────┬───────────────────────────────────────────────┬─────────────────────┤
│ FLEET            │ ┌───────────────────────────────────────────┐ │ @nat.hunterrr       │
│ ▌◉ All phones    │ │            ◉ @onlyemspage                 │ │ iPhone XR · iOS 18.7│
│    4 · 3 spoofed │ │              London                       │ │ 00008020-000A28… ⧉  │
│ PHONES           │ │                       ◎ This Mac          │ │ [● Spoofed · London]│
│ ▌◉ nat.hunterrr  │ │   ◉ @ellybelly…                           │ │  applied 14:02      │
│    XR · London   │ │     Dallas          ◌ @onlyglazertori     │ │ [Proxy|Manual|Off]  │
│  ◉ onlyemspage   │ │                       unplugged           │ │ PROXY               │
│    XR · London   │ │                                           │ │ [socks5h://u:••@…◉] │
│  ◐ onlyglazertori│ │                                           │ │ ✓ socks5h · host:1080│
│    XR · Applying…│ │                                           │ │ ┌ 🇬🇧 London ──────┐ │
│  ○ ellybelly…    │ │                                           │ │ │ England · GB     │ │
│    11 · Unplugged│ │ ENGINE ● 4 workers  51.5074,-0.1278  MAC  │ │ │ 82.12.4.9 · VM   │ │
│                  │ └───────────────────────────────────────────┘ │ └──────────────────┘ │
│ ● Engine ready   │                                               │ SCATTER ──●── exact │
│ py 3.14.6·pmd3   │                                               │ [ Pin phone here ]  │
├──────────────────┴───────────────────────────────────────────────┴─────────────────────┤
        272                          688 (map inset 8)                       320
```

Below 1100 wide the geo card uses its compact form (§4.5) and row subtitles truncate tail; nothing hides. Toolbar (`.toolbar`): `ToolbarItemGroup(placement: .primaryAction)` = Locate all (`location.magnifyingglass`), Pin all (`mappin.and.ellipse`), Release all (`location.slash`), Paste proxy list (`list.clipboard`); `ToolbarItem(placement: .automatic)` = map style `Menu` (`map`), inspector toggle (`sidebar.trailing`). All `.bordered` system buttons, `.labelStyle(.titleAndIcon)`, icon-only below 1120 wide.

## 2. Navigation, selection, keyboard

- `enum Route: Hashable, Codable { case fleet; case phone(String) }` bound to the roster `List(selection: $model.route)`; persisted in state.json and restored on launch. `.fleet` is always the first row and cannot be removed.
- `.fleet` → inspector shows FleetPanel, camera fits every pin + the Mac marker. `.phone(udid)` → PhonePanel; camera flies to that phone's target (or keeps its position if it has none). Hot-plug never changes selection; an unplugged selected phone stays selected and greyed. Clicking a pin selects its phone; `Esc` (with focus in map or roster) returns to `.fleet`; clicking empty map does nothing (avoids accidental deselect while panning).
- Shortcuts, declared in `.commands { CommandMenu("Phone") … CommandMenu("Fleet") … }` so they appear with keys: ⌘1 fleet · ⌘2–⌘9 nth phone · ↑/↓ move selection · ⌘L Locate · ⌘⏎ Pin phone here · ⌘⌫ Release · ⌘R Re-check · ⌘⇧L Locate all · ⌘⇧⏎ Pin all · ⌘⇧V Paste proxy list · ⌘0 fit fleet · ⌘F focus search (Manual mode: address field) · ⌥⌘I toggle inspector · ⌘, Settings · ⌘Q quit (confirmation §9.2).
- Tab order: search → roster (one stop; ⏎ focuses the proxy field) → toolbar → inspector top-to-bottom (mode ←/→, proxy field, eye, Locate, geo copy buttons, manual fields, scatter ←/→ 50 m and ⌥ 500 m, Pin, Release, worker disclosure) → map (arrows pan, +/− zoom). Focus ring: system ring, never suppressed; custom rows add a 2pt `focus` ring inset 2, radius 6.
- Row context menu: Locate · Pin · Release · Re-check proxy · Restart worker · Rename… · Copy UDID · Copy proxy (masked).

## 3. Tokens (`Theme.swift`)

### 3a. Dark (default, the hero) — all pairs computed (`scratchpad/tokens_final.py`)
| Token | Hex | Use / contrast |
|---|---|---|
| `bg.window` | `#0E1118` | window ground = icon ground |
| `bg.field` | `#0B0E14` | under the gradient field, map bezel frame |
| `surface.panel` | `#141925` | roster/inspector tint under material, Reduce-Transparency solid fill |
| `surface.raised` | `#1B2130` | cards, fields, secondary buttons |
| `surface.selected` | `#242148` | selected row fill (= violet 16 % over panel) |
| `hairline` | `#262D3D` | 1pt separators, map bezel stroke, field borders |
| `text.primary` | `#F2F4F8` | 17.2 / 16.0 / 14.6 / 13.8 on bg / panel / raised / selected |
| `text.secondary` | `#A9B1C3` | 8.8 / 8.2 / 7.5 / 7.0 |
| `text.tertiary` | `#848C9C` | 5.6 / 5.2 / 4.8 — section labels, meta; never on `surface.selected` (4.48) |
| `text.mono` | `#C8CEDA` | coordinates, IPs, UDIDs, pids — 12.0 / 11.1 / 10.2 |
| `text.hint` | `#5A6378` | placeholders and disabled only (exempt) |
| `accent.blue / violet / magenta` | `#2D7DFF` / `#764AFF` / `#AB31FF` | light only: glows, halos, rings, edge bar, field lobes (≥ 3.5 vs panel as non-text) |
| `accent.blueText / violetText / magentaText` | `#5C9BFF` / `#9A7DFF` / `#C466FF` | the hues as text/glyphs — 6.4 / 5.7 / 5.6 on panel |
| `gradient.light` | `#2D7DFF → #764AFF → #AB31FF`, `.topLeading → .bottomTrailing` | spoofed pin, spoofed dot, selected-row bar, field, halos |
| `gradient.lamp` | `#2468E6 → #6740E8 → #9429E6` | primary button fill only — white label 5.00 / 6.04 / 5.65 |
| `status.busy` | `#FFB340` | locating, applying, reconnecting — 9.9 on panel |
| `status.error` | `#FF5A5F` | error, crash loop — 5.8 |
| `status.ok` | `#37D67A` | engine-healthy dot, parse ✓, success toasts only (never a phone status) — 9.3 |
| `status.off` | `#848C9C` | hollow "Real GPS" ring, unplugged |
| `focus` | `#5C9BFF` | 2pt focus ring |
| pill fills | spoofed `#26224C` · busy `#352F29` · error `#35222D` · off `#242936` · blue `#182948` | text on them: primary 13.5 · busy 7.4 · error 4.9 · secondary 6.8 · blueText 5.2 |
| `chip.label` | `#0E1118` @ 85 % | pin label backing — white on it over the brightest dark tile 18.3 |

### 3b. Light (acceptable, not the hero)
`bg.window #F2F3F7` · `bg.field #EAECF2` · `surface.panel #FFFFFF` · `surface.raised #F7F8FB` · `surface.selected #EFE9FF` · `hairline #DCE0EA` · `text.primary #111420` (16.5+) · `text.secondary #48506A` (6.8+) · `text.tertiary #5F6983` (4.6+; use secondary for anything < 12pt) · `text.mono #3A4150` · `text.hint #9AA3B8` · `accent.*Text #1A62D2 / #5D3DE0 / #8F1FD6` (4.8+) · `status.busy #8F5200` · `status.error #C4262E` · `status.ok #157A45` · `status.off #5F6983` · `focus #1A62D2` · pills at 12 % over white (`#EFE9FF / #F2EAE0 / #F8E5E6 / #ECEDF0 / #E3EFE9`, text ≥ 4.56) · gradients unchanged (`lamp` with white 5.6 / 6.5 / 6.3) · field lobes at 10 %.

### 3c. Spacing, radii, shadows
- Spacing scale 4 / 8 / 12 / 16 / 20 / 24 / 32: 4 inside a component, 8 between siblings, 12 between blocks, 16 pane padding, 20 between inspector sections, 24 above the primary action group.
- Radii: 6 rows/focus, 8 buttons/fields/chips, 10 map bezel and geo card, 12 glass cards and banners, 14 sheets' inner cards, capsule for pills/toasts.
- Shadows: `card` 0 8 24 black 35 % · `toast` 0 8 24 black 45 % · `lampGlow` 0 6 16 `accent.violet` 35 % (hover 45 %) · `spoofGlow` radius 8 `accent.violet` 55 % on pins, radius 6 60 % on dots.

### 3d. Type (SF Pro via `.system(size:weight:design:)`, never smaller than 11)
| Role | Spec | Where |
|---|---|---|
| Display | 28 semibold, tracking −0.4 | setup title, empty-state title |
| Counter | 26 semibold `.monospacedDigit()` | fleet counters |
| Title | 17 semibold | inspector handle, sheet titles |
| Header | 15 semibold | geo card city, banner titles |
| Row title / body | 13 semibold / 13 regular | roster handle / descriptions |
| Label | 13 semibold | button labels |
| Meta | 12 regular secondary | model · iOS lines |
| Section | 11 semibold, uppercase, tracking 0.6, tertiary | FLEET · PHONES · PROXY · SCATTER |
| Caption / pill | 11 regular secondary / 11 semibold | timestamps / pills, chips, pin labels |
| Mono | 12 regular `.monospaced` `.monospacedDigit()`, `text.mono` | coordinates, IPs, UDIDs, ports, the pip command |
| Mono small | 11 regular `.monospaced` | telemetry strip, footer, error excerpts |

### 3e. Gradient field (`GradientField.swift`)
`TimelineView(.animation(minimumInterval: 1/30, paused: paused))` + `Canvas`: three circles filled with `.radialGradient` (colour → clear) of radius 0.45·min(w,h), colours `accent.blue / violet / magenta` at 16 % (light 10 %), centres on Lissajous paths with periods 47 / 61 / 53 s, amplitude 18 % w × 12 % h, phases 0 / 2.1 / 4.2 rad, over `bg.field`. `paused` when Reduce Motion, when the window is not key, or when `NSWindow.occlusionState` lacks `.visible`. No `.blur` (the radial fill is already soft).

### 3f. Glass (`PaneMaterial`, `GlassCard`)
macOS 26: `.glassEffect(.regular.tint(surface.panel.opacity(0.6)), in: shape)` inside one `GlassEffectContainer` per pane for cards, telemetry strip, toasts, menu-bar rows. Panes themselves use `.background(.regularMaterial)` tinted with `surface.panel` at 55 % on every OS (Apple advises against glass on large sheets). Fallback (macOS 15) for cards: `.background(.ultraThinMaterial, in: shape)` + 1pt `hairline` stroke + `card` shadow. Reduce Transparency: every material → solid `surface.panel`, field at 6 %.

## 4. Components (every state)

### 4.1 Derived display state (`PhoneViewState`, one function in StateStore)
| Inputs | Pill text | Dot | Pin |
|---|---|---|---|
| device absent from `devices` (known from state.json) | Unplugged · will re-apply (if target) / Unplugged | hollow dashed `status.off` | target pin at 35 %, dashed |
| `idle`/`released`, no target or mode Off | Real GPS | hollow 1.5pt `status.off` ring | none (counted on the Mac chip) |
| geolocate in flight for this phone | Locating… | `status.busy`, pulse | pending pin at last target, else none |
| `connecting` / `tunnel_up` | Applying… | `status.busy` half-ring `circle.lefthalf.filled` | pending |
| `simulating` | Spoofed · City, CC | `gradient.light` fill + glow | spoofed |
| `reconnecting` | Reconnecting · try N · Ns (live countdown) | `status.busy` + rotating `arrow.triangle.2.circlepath` 9pt | spoofed at 60 % + busy badge |
| `error` | Error | `status.error` + `exclamationmark.triangle.fill` 11pt | error pin |
City = geo record city when mode Proxy, reverse-geocoded name (`CLGeocoder`, cached) when Manual, else "lat, lon" mono.

### 4.2 Phone row (roster, 44pt, `.listRowInsets(EdgeInsets(12))`)
`HStack(spacing: 10) { StatusDot(8) ; VStack(spacing: 2) { handle 13 semibold ; "XR · 18.7.9 · London" 11 secondary } ; Spacer ; trailing glyph }` (short model · iOS version · state/city, per BRIEF §UX-1; the inspector title block spells out "iPhone XR · iOS 18.7.9"). States: the seven of §4.1 plus **hover** (`surface.raised` 60 %), **selected** (`surface.selected` fill radius 6 + 2pt `gradient.light` bar on the leading edge, the only gradient in the roster), **focused** (2pt `focus` ring). Unplugged rows sit at 55 % opacity and keep their place (sorted by `first_seen`, stable). Accessibility label: "nat.hunterrr, iPhone XR, Spoofed, London, United Kingdom". Double-click the handle → inline rename.
"All phones" row: `◉` glyph `square.grid.2x2`, title "All phones", subtitle "4 phones · 3 spoofed".

### 4.3 Status pill (`Capsule`, 20pt, padding 8×3, dot 6 + 6 gap, text 11 semibold)
| State | Fill | Text | Dot |
|---|---|---|---|
| Real GPS | `#242936` | secondary | hollow `status.off` |
| Locating… / Applying… | `#352F29` | `status.busy` | busy, pulsing |
| Spoofed · London, GB | `#26224C` | primary | `gradient.light` + glow |
| Reconnecting · try 3 · 5 s | `#352F29` | `status.busy` | busy; countdown `.contentTransition(.numericText())` |
| Error | `#35222D` | `status.error` | error |
| Unplugged | `#242936` | secondary | dashed hollow |
| Starting… | `#182948` | `accent.blueText` | `ProgressView` 10pt |
Text changes cross-fade 200 ms; width animates with the same curve. On macOS 26 the pill is `.glassEffect(.regular.tint(fill), in: .capsule)`; elsewhere a plain `Capsule` fill.

### 4.4 Proxy field (inspector)
`TextField` `.textFieldStyle(.plain)` in a 32pt `surface.raised` box, radius 8, 1pt `hairline`, mono 12; trailing 28×28 `eye`/`eye.slash` button. Unfocused it renders the normalised masked form (`socks5h://user:•••@host:1080`); focused it shows the raw string; reveal is per-session, never persisted. Passwords never reach a log line.
Parse line under it (18pt, caption): `ProxyParser.swift` gives instant client-side feedback on every keystroke; the engine's `parse_proxy` (debounced 250 ms) is authoritative and overrides it.
- empty: hint "host:port:user:pass · user:pass@host:port · socks5://…"
- valid: `checkmark.circle.fill` `status.ok` + "socks5h · host:1080 · user jm…" secondary
- HTTP: `info.circle` busy + "HTTP proxy — treated as http://"
- invalid: `xmark.circle.fill` error + engine message; border → `status.error`
- locating: field disabled 70 %, Locate shows spinner + `geo_progress` stage ("querying ipwho.is")
- multi-line paste: toast "3 lines pasted — Paste as list…" (opens the bulk sheet pre-filled)
- proxy edited after a Locate: geo card footer turns amber "Proxy changed — Locate again"; Pin disabled until re-located.

### 4.5 Geo result card (`GlassCard`, radius 10, padding 12; 1pt `gradient.light` ring at 35 % when this result is the applied target)
Full: flag emoji 20pt (regional indicators from `country_code`) + city 15 semibold · "England · United Kingdom" 12 secondary · `network` ISP (+ org if different) 12 · IP mono + 24pt `doc.on.doc` copy · `clock` timezone + live local time (`TimelineView(.periodic(from:by: 60))`) · coordinates mono · footer 11: "via ip-api.com · 1.2 s · checked 2 min ago" + **Re-check** text button (⌘R).
States:
- **empty** — dashed 1pt hairline outline, `globe` 24pt tertiary, "Locate to see the exit IP".
- **loading** — 5 shimmer bars 8pt on `surface.raised` + the `geo_progress` stage line ("Connecting through proxy…" → "Querying ip-api.com…" → "Trying ipwho.is…").
- **success** — the full form above.
- **stale** (> 10 min) — footer turns `status.busy`, Re-check gets a 6pt busy dot.
- **degraded** — amber 3pt left bar, "Gateway IP — may differ from exit IP", secondary button "Use gateway location anyway".
- **unreachable** — red 3pt left bar, "Proxy unreachable — " + engine message, Retry; if `fallback` is present the degraded card is stacked beneath at 70 %.
- **providers failed** — "All 3 providers failed", last stage, Retry, hint "Switch to Manual to place the pin yourself".
Compact form (< 1100 wide, chosen by `ViewThatFits`): "🇬🇧 London · Virgin Media" / "82.12.4.9 · Europe/London".
This-Mac variant (fleet panel): hollow ring instead of a flag, title "This Mac · Dartmouth, Nova Scotia", "Bell Canada · America/Halifax", public IP mono.

### 4.6 Mode control
Native `Picker(selection:) { Proxy · Manual · Off }.pickerStyle(.segmented)`, 28pt, full width; disabled while the engine starts. Proxy → §4.4 + geo card + "last checked". Manual → address `TextField` (⌘F) with `MKLocalSearchCompleter` results in a popover list (≤ 6 rows, 13 title + 11 subtitle; ⏎ runs `MKLocalSearch` and moves the pin), lat/lon mono fields validated −90…90 / −180…180 (error border on bad input), hint "Drag the pin or click the map". Off → sections below at 35 % + "Phone uses its real GPS"; choosing Off releases (reversible, no confirm).

### 4.7 Scatter slider
`Slider(value:in: 0...3000, step: 50)`, tint `accent.violet`, readout mono 44 wide "exact" / "750 m" / "1.2 km", ticks 0/1/2/3 km as 11 tertiary, caption "Random offset so phones on one ISP don't share a pixel". Live `MapCircle` while dragging (200 ms). The offset is re-rolled only on Pin and stored, so re-applies land on the same spot.

### 4.8 Buttons (`PrimaryButtonStyle`, `SecondaryButtonStyle`)
- **Primary**: 32pt, radius 8, `gradient.lamp` fill, white 13 semibold, 1pt `gradient.light` ring at 60 %, `lampGlow`. Hover `.brightness(0.06)`, pressed `.brightness(-0.08)` + glow radius 4, disabled `surface.raised` fill + `text.hint` label + no glow, loading `ProgressView` 14pt + stage text at fixed width. **One lit lamp per panel**: PhonePanel — Locate until a fresh geo result exists for the current proxy, then Pin phone here (label "Pinned" and disabled when the applied target equals the current target + scatter). FleetPanel — Pin all. Bulk sheet — Apply. Setup — Check again.
- **Secondary**: 32pt, `surface.raised`, 1pt `hairline`, `text.primary` (Release, Re-check, Retry, Cancel, Locate all). **Destructive** variant: label `status.error` (Release all, Quit and Release).
- **Text button**: 12 medium `accent.blueText`, underline on hover (Copy, Show log, Paste as list…). Icon buttons 28×28 radius 8.

### 4.9 Toasts (map overlay, bottom-centre, above the telemetry strip)
Glass capsule 36pt, glyph 14 + 13 medium text + optional text button. ok `checkmark.circle.fill` `status.ok` ("Pinned @nat.hunterrr to London") · busy · info · error (`xmark.octagon` error, "Worker for @onlyemspage crashed — Retry", 8 s). Max 3 stacked, newest at bottom, auto-dismiss 4 s, hover pauses. Errors of one episode toast once, not per attempt.

### 4.10 Telemetry strip (map overlay, 28pt, inset 8, glass, mono 11)
Leading "ENGINE ● ready · 4 workers" (dot: ok / busy / error) · centre live cursor lat/lon while hovering the map (`onContinuousHover` + `MapProxy.convert`), otherwise the selected target · trailing "THIS MAC · Dartmouth, NS · 142.x.x.x". Text `text.mono`, labels tertiary.

### 4.11 Banners (inspector top, radius 12, 12 padding, 3pt left bar)
Amber: "Unplugged — will re-apply London when it returns" (target kept; Locate/Pin disabled, Release enabled) · "Tunnel dropped — retrying in 5 s (try 3)". Red: "Worker keeps failing (5 restarts)" + last error mono small (`.lineLimit(3)`, "Show more"), "Retrying in 42 s" (hub's 60 s cycle), **Retry now** (`worker_restart`) + Show log. Red on the map (top edge): "Engine stopped (exit 1) — Restart" · "Engine didn't start — Retry · Show log".

### 4.12 Fleet panel (inspector, route `.fleet`)
Counters row (26 semibold + 11 section label): PHONES · SPOOFED · BUSY/ERRORS. This-Mac geo card. Actions: Paste proxy list… (secondary, ⌘⇧V), Locate all (secondary), **Pin all** (primary), Release all (destructive). Chips: one 28pt row per phone (dot, handle 12 medium, compact pill "London" / state) — click selects. Engine line: "Engine ● ready · Python 3.14.6 · pymobiledevice3 10.7.3 · pid 4812" mono small.

### 4.13 Roster footer (44pt) and search
Footer: dot + "Engine ready" 11 / "py 3.14.6 · pmd3 10.7.3" mono small; states Starting… (spinner) / Slow to start · Show log (amber, > 8 s) / Didn't start · Retry (red, > 20 s) / Stopped · Restart (red). Search field 28pt filters rows by handle, model, city, UDID.

## 5. Map

- `Map(position: $model.camera, interactionModes: .all)` `.mapStyle(model.settings.mapStyle.value)` where Muted (default) = `.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)`, Standard = `.standard(elevation: .flat, pointsOfInterest: .excludingAll)`, Imagery = `.hybrid(elevation: .flat, pointsOfInterest: .excludingAll)`. `.mapControls { MapCompass(); MapScaleView() }`, `.coordinateSpace(.named("map"))`. Dark tiles follow the colour scheme; no veil over the map (it would dim the pins) — the 8pt bezel frame in `bg.field` reconciles tile tone with the ground.
- Camera: `MapCameraPosition`. Fly-to on phone selection: `.camera(MapCamera(centerCoordinate: target, distance: max(12_000, scatter × 8), heading: 0, pitch: 0))`, 900 ms easeInOut (500 ms if < 50 km away; flights > 3000 km first zoom out to 6000 km at 40 % of the duration). Fit fleet (`.fleet`, ⌘0, after launch re-apply): `.region` from the bounding box of all targets + the Mac, padded 25 %, minimum span 0.5°, 700 ms. Empty fleet: Mac at distance 40 km.
- Annotations: `Annotation(handle, coordinate:, anchor: .center) { PinView }` with `.annotationTitles(.hidden)`; every pin carries a label chip under it (11 semibold on `chip.label`, radius 6, padding 4×8, offset y+16) reading the handle plus a state suffix where noted:
  - **spoofed** — 22pt circle `gradient.light`, 1.5pt white ring 85 %, halo ring scale 1.35 at 40 %, `spoofGlow`; chip = handle.
  - **pending** — 22pt hollow 1.5pt `status.busy`, 6pt inner dot, pulsing halo; chip "handle · locating…" / "· applying…".
  - **reconnecting** — spoofed pin at 60 % + 9pt `status.busy` badge top-trailing; chip "· reconnecting".
  - **error** — 22pt hollow 1.5pt `status.error`, `exclamationmark` 10pt inside; chip "· error".
  - **unplugged** — spoofed pin at 35 %, ring `StrokeStyle(dash: [3,3])`; chip "· unplugged".
  - **Mac** — 14pt hollow 1.5pt white 80 % ring with 4pt crosshair ticks, no glow; chip "This Mac · Dartmouth · 2 on real GPS" (real-GPS phones are counted here, not drawn; hovering lists their handles via `.help`).
  - **selected** — scale 1.15, chip gains a 1pt `gradient.light` stroke; other pins in fleet view render at 0.9.
  - Z-order: selected > error > spoofed > pending > Mac.
- Manual drag: `DragGesture(coordinateSpace: .named("map"))` on the pin content; while dragging scale 1.15, shadow 14, chip shows live lat/lon mono; on end `proxy.convert(value.location, from: .named("map"))` sets the target and the drop spring plays. Click on the map in Manual mode (`onTapGesture` via `MapReader`) moves the pin. Scatter: `MapCircle(center:radius:)` fill `accent.violet` 12 %, stroke 1pt `accent.violet` 60 %, only when radius > 0.
- Overlap: pins whose targets are within 500 m get a deterministic `.offset` of ±14pt (index order) so labels stay readable; `Annotation` coordinates do not tween — target moves are interpolated in the model over 400 ms.

## 6. Motion (all `withAnimation`; Reduce Motion → pulses static at 70 %, camera instant, field frozen, springs → 200 ms easeOut)
| What | Spec |
|---|---|
| Dot / pill colour | 240 ms easeInOut, glow radius animates with it; pill text `.contentTransition(.opacity)` 200 ms, digits `.numericText()` |
| Busy pulse | 1.6 s easeInOut autoreverse: glow 0.35 → 0.9, scale 1 → 1.12 |
| Spoofed light-up | `spring(response: 0.42, dampingFraction: 0.72)`: dot 0.6 → 1, glow 0 → 60 %; edge bar 200 ms |
| Row selection | 160 ms easeOut fill; edge bar grows 0 → full height |
| Inspector content swap | 220 ms: out opacity 120 ms, in `.move(edge: .bottom)` 8pt + opacity, keyed by route |
| Camera | fly 900 / 500 ms, fit 700 ms (§5) |
| Pin drop | `spring(response: 0.45, dampingFraction: 0.7)` scale 0.6 → 1 from y−12; halo 1 → 2.2, 0.6 → 0 over 900 ms, once; label +150 ms |
| Pin release | 260 ms easeIn to scale 0.6, opacity 0 |
| Pending ring | 1.2 s easeOut loop, 14 → 40pt, 0.6 → 0; reconnecting badge rotates 1 rev / 4 s |
| Scatter ring | 200 ms easeOut follows the slider |
| Toast | in `spring(0.35, 0.8)` from y+24; out 200 ms fade |
| Skeleton shimmer | 1.2 s linear `LinearGradient` sweep, 18 % highlight |
| Lamp hover | 150 ms, glow radius 10 → 14 |
| Setup → console | 300 ms: setup opacity → 0 while the console scales 0.98 → 1 |
| Gradient field | §3e, 24 s visible period, 30 fps cap |

**First-launch sequence ("power-on", ≤ 2.2 s; skipped entirely in snapshot mode and under Reduce Motion; later launches at half stagger):** t0 window appears dark, field fades 0 → 16 % over 600 ms; t0.2 map at camera distance 9000 km centred on the Mac, Mac ring draws itself (`trim` 0 → 1, 300 ms); t0.4–1.4 as `devices` lands rows slide in from the leading edge 120 ms apart, each dot lighting with the light-up spring; t1.4+ if re-apply-on-launch has targets, pins drop 120 ms apart as workers report `simulating` and the camera fits the fleet (700 ms); the strip reads "ENGINE ● ready · 4 workers". With no targets the fleet panel's "Paste proxy list…" gets one 900 ms gradient-ring sweep — the only hint the app ever gives. Any click or key skips to the settled state.

## 7. Menu-bar extra
`MenuBarExtra(isInserted: .constant(true)) { MenuBarPanel() } label: { Image(nsImage: Theme.menuBarIcon) ; if spoofed > 0 { Text("\(spoofed)") } ; if anyError { Text("!") } }` `.menuBarExtraStyle(.window)`. `Theme.menuBarIcon = NSImage(named: "MenuBarIcon")` (picks the @2x automatically from `Contents/Resources`) with `isTemplate = true`, size 18×18. Panel 300 wide, `surface.panel`, glass rows on 26:
- Header 40pt: "Only Social GPS" 13 semibold + engine dot; "4 phones · 3 spoofed · 1 unplugged" 11 secondary.
- Rows 32pt: dot · handle 12 medium · compact pill (city or state). Click → `NSApp.activate`, window front, route = `.phone(udid)`. ↑/↓ and ⏎ work.
- Footer 44pt: **Re-apply all** (lamp, 26pt) · Release all (secondary; confirms if ≥ 2 spoofed) · text button "Open Only Social GPS" · "Quit" (goes through §9.2).
- States: Starting… rows replaced by a spinner line; no phones "No iPhones on USB"; engine dead red row "Engine stopped — Restart"; setup needed "Finish setup in the app".

## 8. Screens
- **Probing (0–3 s)**: `ProgressView` + "Checking Python…" centred over the field; no columns yet.
- **Setup** (Python / pymobiledevice3 missing; replaces the console over the field): centred 520-wide `GlassCard` padding 24: `icon-mark.png` 96pt with a `spoofGlow`; Display "One thing to install"; body 13 secondary "Only Social GPS drives iPhones through pymobiledevice3, which isn't installed for `/opt/homebrew/bin/python3`."; command block (`surface.raised`, radius 8, mono 12, 40pt) `pip3 install pymobiledevice3` (+ `--break-system-packages` when the interpreter path contains `/opt/homebrew/` or `/usr/local/`) with a Copy button (`doc.on.doc` → `checkmark` 1.5 s); caption "Detected Python 3.14.6 at /opt/homebrew/bin/python3" or "No python3 found — install with `brew install python`"; **Check again** (primary, spinner while re-probing) · Choose Python… (secondary, `NSOpenPanel`). Success dissolves into the console (300 ms).
- **Engine starting**: roster shows state.json rows greyed 55 % with subtitle "—" (or 3 shimmer rows if none), footer "Starting engine…", toolbar and inspector disabled, strip "ENGINE ◌ starting…". > 8 s footer amber "Slow to start · Show log"; > 20 s red "Engine didn't start · Retry · Show log" + map banner.
- **Engine died**: map banner "Engine stopped (exit N) — Restart", rows take the Unplugged appearance, footer red, menu-bar dot red; Restart respawns and re-sends `hello` + `set_all`.
- **Empty (no phones, engine ready)**: roster placeholder row `cable.connector` 20pt tertiary "No iPhones on USB" / "Plug one in — it appears within 2 s", footer "Watching USB…" with a pulsing busy dot; map on the Mac at 40 km; fleet panel counters 0, a checklist card (USB cable · "Trust this computer" tapped · Developer Mode on — grey rings that fill `status.ok` as the first device reports `paired` / `developer_mode`), Paste list enabled, Pin all disabled. Previously known phones still list as Unplugged rows — this screen is only for a truly empty list.
- **Unplugged while spoofed**, **Reconnecting**, **Crash-looping**: row/pin per §4.1, inspector banner per §4.11, toast once per episode.
- **Proxy unreachable / providers failing**: geo card states §4.5; Pin relabels "Pin to gateway location" when only the fallback exists.

## 9. Sheets
### 9.1 Bulk paste (`.sheet`, 640 × 520, `bg.window`)
Title "Paste proxy list" 17 semibold; left `TextEditor` mono 12 on `surface.raised` (300 wide, placeholder "one proxy per line, or `handle, proxy` / `handle proxy`"); right preview `Table` (Phone · Proxy masked · Status pill: Parsed / Bad line / No phone for this line / Handle not found / Ignored); mapping `Picker` "By list order | By handle" auto-selects By handle when ≥ 1 line starts with a known handle; counter "3 of 4 phones will get a proxy"; footer `Toggle` "Locate all after applying" (on), Cancel, **Apply** (primary, disabled until ≥ 1 mapped line). Failed lines get a red 3pt left bar. Nothing applies until Apply.
### 9.2 Quit confirmation (`NSAlert` from `applicationShouldTerminate` → `.terminateLater`)
Only when ≥ 1 phone is `simulating` / `reconnecting`: "Quitting returns 4 phones to their real GPS." / "Only Social GPS holds each phone's location only while it runs. Hide the window to keep them pinned." Buttons: **Quit and Release** (destructive) · **Hide Window** (default, `orderOut`; Dock and menu bar stay) · Cancel. On quit: send `shutdown`, wait ≤ 4 s for exit, then `reply(toApplicationShouldTerminate: true)`.
### 9.3 About (`.sheet`, 360 × 300)
`icon-mark.png` 96pt with glow, "Only Social GPS" 17 semibold, version + build 12 secondary, engine / Python / pymobiledevice3 versions mono 12, text buttons "Open log folder" (`~/Library/Logs/OnlySocialGPS`) and "Copy diagnostics", OK.
### 9.4 Settings (`Settings` scene, ⌘,, `Form` `.formStyle(.grouped)` 420 × 300)
Launch at login (`SMAppService.mainApp`), Re-apply on launch (default on), Map style (Muted / Standard / Imagery), Theme (System / Dark / Light), Python (path + Choose…), "Show engine log".

## 9.5 Launch flow and persistence (what the UI reflects)
1. `phase = .probing`: find Python (`/opt/homebrew/bin/python3` → `/usr/local/bin/python3` → `env python3`, or the Settings override), 3 s `import pymobiledevice3` probe → `.setup` on failure.
2. `phase = .engineStarting`: load `state.json` (rows appear greyed at once), spawn the hub, wait for the `hello` event, send `hello`, then `set_all` with every record whose mode ≠ Off and `reapplyOnLaunch` is on, then `my_location`.
3. `phase = .ready` on the first `devices` event; the power-on sequence (§6) plays; pins drop as `device_state` reports `simulating`.
4. Every `device_state` / `devices` / `geo_progress` event mutates `AppModel` on the main actor; `state.json` is written atomically (debounced 500 ms) on any record change: nickname, proxy, mode, target, geo record, scatter, `lastAppliedAt`, `lastSeenAt`, model, iOS, plus the globals and `route`.
5. Nicknames are pre-filled from `/Users/james/Desktop/iphone-bot copy/.devicenames.json` (read-only, best effort) the first time a UDID is seen; the user's rename wins afterwards.

## 9.6 Strings (use verbatim so every agent's snapshot reads the same)
| Key | Text |
|---|---|
| pill.real | Real GPS |
| pill.locating / applying | Locating… / Applying… |
| pill.spoofed | Spoofed · {City}, {CC} |
| pill.reconnecting | Reconnecting · try {n} · {s} s |
| pill.unplugged | Unplugged · will re-apply |
| row.empty | No iPhones on USB / Plug one in — it appears within 2 s |
| banner.unplugged | Unplugged — will re-apply {City} when it returns |
| banner.crash | Worker keeps failing ({n} restarts) |
| banner.engineDead | Engine stopped (exit {code}) — Restart |
| toast.pinned | Pinned @{handle} to {City} |
| toast.unplugged | @{handle} unplugged — {City} will re-apply on reconnect |
| toast.pasted | {n} lines pasted — Paste as list… |
| geo.empty | Locate to see the exit IP |
| geo.gateway | Gateway IP — may differ from exit IP |
| geo.unreachable | Proxy unreachable — {message} |
| geo.failed | All 3 providers failed |
| geo.stale | Proxy changed — Locate again |
| setup.title / setup.cmd | One thing to install / pip3 install pymobiledevice3 |
| quit.title | Quitting returns {n} phones to their real GPS. |
| quit.body | Only Social GPS holds each phone's location only while it runs. Hide the window to keep them pinned. |
| strip.engine | ENGINE ● ready · {n} workers |

SF Symbols used (nothing else): `square.grid.2x2`, `circle.lefthalf.filled`, `arrow.triangle.2.circlepath`, `exclamationmark.triangle.fill`, `exclamationmark`, `checkmark.circle.fill`, `xmark.circle.fill`, `xmark.octagon`, `info.circle`, `eye`, `eye.slash`, `doc.on.doc`, `checkmark`, `globe`, `network`, `clock`, `cable.connector`, `hand.raised`, `hammer`, `location.magnifyingglass`, `mappin.and.ellipse`, `location.slash`, `list.clipboard`, `map`, `sidebar.trailing`, `magnifyingglass`, `gearshape`.

## 10. Snapshot mode (`OSGPS_SNAPSHOT=/path/out.png`)
Mock engine by default (`OSGPS_ENGINE=mock`), the intro skipped, animations disabled, **the user's state.json neither read nor written** — the app seeds a built-in snapshot state. With `OSGPS_ENGINE=real` the snapshot instead pictures the live fleet through the real hub: state.json is read (nicknames/models) but every target is stripped and re-apply disabled so the hub only ever receives an empty desired map, the renderer waits for `phase == .ready` and the Mac's location, and nothing is written. Otherwise the app seeds a built-in snapshot state (nicknames from the four handles, proxies, targets London / Dallas / Berlin, geo records) so every panel has content. The mock is launched with `--scenario snapshot` (all four default phones present; `set_all` answered within 500 ms as: phone 1 `simulating` London, phone 2 `simulating` Dallas, phone 3 `reconnecting` attempt 3 / retry 5 s, phone 4 absent from `devices` with target Berlin remembered). After 2.5 s the app renders at 2× (`NSBitmapImageRep` with pixelsWide/High = 2 × bounds, `size` = bounds, then `cacheDisplay(in:to:)`) and exits 0. If a sheet is attached (`window.attachedSheet`) its `contentView` is rendered the same way and composited at the sheet's frame offset. `OSGPS_SCREEN` selects:

| Value | Route / surface | What an agent must see |
|---|---|---|
| `fleet` (default) | `.fleet` | 4 rows (2 spoofed gradient dots, 1 reconnecting amber, 1 unplugged 55 %), map fitted to 3 pins + Mac ring, telemetry strip, fleet counters 4 · 2 · 1, This-Mac card, Pin all lit |
| `device` | `.phone(OSGPS_SELECT ?? first)` | title block, Spoofed pill, Proxy mode, masked proxy field with ✓ parse line, full geo card with 🇬🇧 London ring-highlighted, scatter "exact", "Pinned" disabled lamp + Release, map flown to London at 12 km |
| `setup` | setup screen | mark, title, command block with `--break-system-packages`, Check again lit |
| `bulk` | `.fleet` + bulk sheet with 4 sample lines pre-filled | preview table showing Parsed ×3 + Bad line ×1, "3 of 4 phones will get a proxy", Apply lit |
| `about` | `.fleet` + About sheet | mark, versions in mono |
Optional extras the engineer may add: `empty`, `crash`, `starting`, `light`. If the map area renders blank in the PNG (Metal layer not captured by `cacheDisplay`), snapshot mode swaps the live `Map` for `SnapshotMapView`: an `MKMapSnapshotter` image of the same region with the same `PinView`s placed at `snapshot.point(for:)` — fallback only, tried after the first real snapshot.

## 11. Build order (`build.sh` compiles `$(find Sources -name '*.swift')` with `-swift-version 5 -O -parse-as-library`)
1. `Sources/Theme.swift` — `Color(hex:)`, `Palette` (dark/light structs, `Palette.current(scheme)`), gradients, `Font` helpers, spacing/radius constants, shadow modifiers, `PaneMaterial`, `GlassCard`, `PrimaryButtonStyle`, `SecondaryButtonStyle`, `menuBarIcon`, `markImage`.
2. `Sources/Models.swift` — Codable mirrors of PROTOCOL.md (`Device`, `Proxy`, `GeoResult`, `EngineState`, `DeviceStateEvent`, `WorkerStatus`), `Target`, `Mode`, `PhoneRecord` (persisted per-UDID fields), `PersistedState`, `Route`, `Toast`, `PhoneViewState`, marketing-name fallback.
3. `Sources/ProxyParser.swift` — client-side pre-validation only: the BRIEF §Proxy grammar (all notations, the 4-field ambiguity rule, IPv6 brackets, quotes/whitespace/trailing slash), `mask(_:)`, `normalized`; used for instant feedback and masking, never for `curl_args`.
4. `Sources/EngineClient.swift` — Python discovery + 3 s `import pymobiledevice3` probe, `Process` spawn of hub or mock, NDJSON framing, `request(_:) async throws` with ids and continuations, `AsyncStream` of events, stderr → app log, exit detection and restart, `shutdown` with 4 s budget.
5. `Sources/Persistence.swift` — Application Support path, atomic Codable read/write of `state.json`, snapshot seed (`SnapshotSeed`), env parsing (`OSGPS_*`).
6. `Sources/StateStore.swift` — `@MainActor @Observable final class AppModel`: phase, devices, records, `viewState(for:)` (§4.1), route, camera, toasts, engine health/escalation timers, geo requests + stale timers, countdowns, actions (locate, pin, release, reCheck, bulkApply, locateAll, pinAll, reapplyAll, releaseAll, restartWorker, rename), launch sequence (`hello` → `set_all`), intro scheduler.
7. `Sources/Snapshot.swift` — `OSGPS_SNAPSHOT` renderer (2× rep, sheet compositing, exit 0), `SnapshotMapView` fallback.
8. `Sources/AppDelegate.swift` — `NSApplicationDelegate`: window autosave/min size/background, `applicationShouldTerminate` alert (§9.2), Hide Window, Console/log opening, activation from the menu bar.
9. `Sources/App.swift` — `@main OnlySocialGPSApp`: `WindowGroup`, `Settings`, `MenuBarExtra`, `.commands` (§2), environment injection.
10. `Sources/Views/GradientField.swift` · `RootView.swift` (phase switch, `ConsoleView` HSplitView, toolbar).
11. `Sources/Views/RosterView.swift` (search, sections, `PhoneRow`, `StatusDot`, footer, empty placeholder) · `StatusPill.swift`.
12. `Sources/Views/MapStage.swift` (bezel, `Map`, camera logic, drag, scatter circle, banners) · `PinViews.swift` · `TelemetryStrip.swift` · `ToastView.swift`.
13. `Sources/Views/Inspector/InspectorView.swift` · `PhonePanel.swift` · `FleetPanel.swift` · `ProxyField.swift` · `GeoCard.swift` · `ManualSection.swift` (search completer, lat/lon) · `ScatterSlider.swift` · `Banners.swift` · `WorkerDisclosure.swift`.
14. `Sources/Views/Sheets/BulkPasteSheet.swift` · `AboutSheet.swift` · `SettingsView.swift`.
15. `Sources/Views/SetupView.swift` · `Sources/Views/MenuBarPanel.swift`.
Compile after steps 1–2, 6, 9, 10, 12, 13, 15; snapshot `fleet` after 12, `device` after 13, `setup`/`bulk`/`about` after 14–15.

## 12. Risks and fallbacks (decide at first compile, do not fight the API)
- `HSplitView` ignores `idealWidth` on some OS versions → set initial widths by giving the roster and inspector `.frame(width:)` until the user drags, then release to min/max (store the dragged width in `@State`).
- `.glassEffect` / `GlassEffectContainer` unavailable or mis-rendering → `.ultraThinMaterial` path everywhere; both paths use the same tokens, snapshot both if 26 is available.
- `Annotation` drag: if `DragGesture` fights the map's pan, gate it with `.highPriorityGesture` on the pin only and `allowsHitTesting(false)` on the chip.
- MapKit dark land is warmer (~`#1C1C1E`) than `#0E1118`: accepted — the bezel makes the map read as a screen inside the console. Do not add a veil over the `Map` (it dims the annotations).
- Sheets are separate windows: §10 compositing. If `attachedSheet` is nil at 2.5 s (sheet animation), wait up to 0.5 s more.
- `MenuBarExtra` label with icon + text: if the count text refuses to render beside a template image, keep the icon only and put the count in the panel header.
- Flag emoji render as Apple Color Emoji raster: keep ≤ 20pt.
