# Proposal: "Mission Control" — Only Social GPS

Direction: a dark instrument panel for an operator who runs a fleet. Left, a dense roster you can scan in under a second. Center, the map is the hero and is framed like an instrument in a bezel. Right, an inspector that changes with the selection. Xcode's Devices window crossed with a flight-ops console: information density, glowing status, rigorous alignment on an 8pt grid. The icon gradient never appears as paint on big surfaces; it appears as **light** — a glow behind a status dot, a 2pt lit edge on the selected row, the halo of a spoofed pin, three slow lobes of coloured light behind glass. The one solid use is the primary button, which is "the lamp that is lit".

Everything below is pure SwiftUI on macOS 15+ (Liquid Glass behind `if #available(macOS 26, *)`), SF Symbols, MapKit, SF Pro. No custom fonts, no image assets except the OS mark PNGs.

---

## 1. Window layout

### 1a. Default 1280 × 820 (unified toolbar 52pt, three columns 272 / 688 / 320)

```
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│ ●●●   [⌕ Search phones        ]     Locate all   Pin all   Release all      ⊞ Map ▾   ⓘ     │ 52 toolbar
├────────────────────┬─────────────────────────────────────────────────────┬───────────────────┤
│ FLEET              │ ┌─────────────────────────────────────────────────┐ │ @nat.hunterrr     │
│ ▌◉ All phones      │ │                                                 │ │ iPhone XR · iOS   │
│    4 phones·3 spoof│ │                                                 │ │ 18.7.9            │
│                    │ │           ┌ @onlyemspage ┐                      │ │ 00008020-000A28…  │
│ PHONES             │ │           ◉ London                              │ │───────────────────│
│ ▌● @nat.hunterrr   │ │                                                 │ │ ● Spoofed         │
│    iPhone XR·London│ │                          ◎ This Mac · Dartmouth │ │   London, GB      │
│  ● @onlyemspage    │ │     ◉ @ellybelly…                               │ │   applied 14:02   │
│    iPhone XR·London│ │       Dallas                                    │ │   held 1h 12m     │
│  ◐ @onlyglazertori │ │                                                 │ │───────────────────│
│    iPhone XR·Locat…│ │                       ○ @onlyglazertori         │ │ [Proxy|Manual|Off]│
│  ○ @ellybelly…     │ │                         locating…               │ │ Proxy             │
│    iPhone 11·Unplug│ │                                                 │ │ [socks5h://u:••••]│
│                    │ │                                                 │ │  ✓ socks5h · 1080 │
│                    │ │                                                 │ │      [ Locate ]   │
│                    │ │                                                 │ │ ┌───────────────┐ │
│                    │ │                                                 │ │ │🇬🇧 London      │ │
│                    │ │                                                 │ │ │ England · GB  │ │
│                    │ │                                                 │ │ │ Virgin Media  │ │
│                    │ │                                                 │ │ │ 82.12.4.9     │ │
│                    │ │                                                 │ │ │ Europe/London │ │
│                    │ │                                                 │ │ └───────────────┘ │
│                    │ │ ENGINE ● 4 workers   51.5074, -0.1278   THIS MAC│ │ Scatter ──●── 0 m │
│                    │ └─────────────────────────────────────────────────┘ │ [ Pin phone here ]│
│ Engine · connected │                                                     │ [    Release     ]│
│ py 3.14.6·pmd3 10.7│                                                     │ ▸ Worker  pid 4812│
├────────────────────┴─────────────────────────────────────────────────────┴───────────────────┤
     272                              688 (map inset 8, r10)                       320
```

Region sizes at 1280×820 (points):
- Toolbar 52 (`.toolbar`, `.windowToolbarStyle(.unified)`), window title hidden, search field 220 wide in the sidebar column.
- Sidebar 272 (min 220, ideal 272, max 320). Rows 44 tall, 12 inset, 8pt grid. Section headers 24 tall. Footer 44.
- Map column fills. Map is inset 8 on all sides inside a `RoundedRectangle(cornerRadius: 10)` with a 1pt hairline, so the gradient field shows as a bezel around the instrument. Telemetry strip 28 tall overlaid at the bottom of the map.
- Inspector 320 (min 292, ideal 320, max 360). 16 inset, 12 between blocks, 20 between sections.

SwiftUI mapping:
- Root: `ZStack { GradientField(); NavigationSplitView(columnVisibility:) { Roster } detail: { MapStage() .inspector(isPresented: $model.inspectorShown) { InspectorView() } } }`
- Sidebar column: `List(selection: $model.selection)` with `Section` headers, `.listStyle(.sidebar)`, `.navigationSplitViewColumnWidth(min: 220, ideal: 272, max: 320)`, `.searchable(text:placement:.sidebar)`.
- Inspector: `.inspector` (macOS 14+) + `.inspectorColumnWidth(min: 292, ideal: 320, max: 360)`. Content is a `ScrollView { VStack(alignment: .leading, spacing: 12) }`.
- Map: `Map(position: $model.camera, interactionModes: .all) { MapContentBuilder annotations }`, `.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))`, `.mapControls { MapCompass(); MapScaleView() }`, wrapped in `MapReader` for drag-to-coordinate conversion. Telemetry strip and toasts are `.overlay(alignment: .bottom)` on the map.
- Glass: panels on macOS 26 use `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))` inside one `GlassEffectContainer`; fallback `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))`.

### 1b. Minimum 1000 × 700 (220 / 480 / 300)

```
┌────────────────────────────────────────────────────────────────────────────┐
│ ●●●  [⌕ Search    ]   Locate all  Pin all  Release all    ⊞ ▾  ⓘ         │ 52
├──────────────┬───────────────────────────────────────┬─────────────────────┤
│ FLEET        │ ┌───────────────────────────────────┐ │ @nat.hunterrr       │
│ ▌◉ All phones│ │                                   │ │ iPhone XR · 18.7.9  │
│ PHONES       │ │        ◉ @onlyemspage             │ │ ● Spoofed · London  │
│ ▌● nat.hunt… │ │                                   │ │ [Proxy|Manual|Off]  │
│   XR·London  │ │              ◎ This Mac           │ │ [socks5h://u:••••]  │
│ ● onlyemsp…  │ │   ◉ @ellybelly…                   │ │        [ Locate ]   │
│   XR·London  │ │                                   │ │ 🇬🇧 London · Virgin  │
│ ◐ onlyglaz…  │ │                 ○ onlyglazertori  │ │ 82.12.4.9 · Eu/Lon  │
│   XR·Locati… │ │                                   │ │ Scatter ──●── 0 m   │
│ ○ ellybell…  │ │ ENGINE ● 4   51.50,-0.12   MAC    │ │ [ Pin phone here ]  │
│   11·Unplug… │ └───────────────────────────────────┘ │ [    Release     ]  │
│ Engine · ok  │                                       │ ▸ Worker            │
├──────────────┴───────────────────────────────────────┴─────────────────────┤
      220                      480                              300
```

Below 1100 wide the geo card collapses to its two-line form (§5.4) and the sidebar subtitle truncates city with `.truncationMode(.tail)`; nothing hides. `.frame(minWidth: 1000, minHeight: 700)` on the root; `.windowResizability(.contentSize)` is NOT used so the window stays free-form. Size/position restored via `NSWindow.setFrameAutosaveName("main")`.

---

## 2. Navigation model

One window, no push navigation. **Selection drives everything.** The sidebar `List` has a stable enum selection: `.fleet` or `.phone(udid)`.

- `.fleet` (the "All phones" row, always first, cannot be removed): map fits every pin + the Mac marker (`MapCameraPosition.region` from a computed bounding box, 48pt padding); inspector shows the Fleet panel (§5.13).
- `.phone(udid)`: map keeps the current camera unless the phone has a target, in which case it flies to the target at 0.9 s (§6); inspector shows the Phone panel.
- Hot-plug never changes selection. If the selected phone is unplugged it stays selected and greyed (§5.1 state 7).
- Modal surfaces: bulk paste sheet (`.sheet`), quit confirmation (`NSAlert` from `applicationShouldTerminate` returning `.terminateLater`), About (`.sheet`), setup screen (replaces the whole window content, §5.11).
- Keyboard: `⌘1` select fleet, `↑/↓` move selection in roster, `⌘L` Locate, `⌘⏎` Pin phone here, `⌘⌫` Release, `⌘⇧R` Re-check, `⌘⇧V` Paste proxy list, `⌘F` focus search, `⌥⌘I` toggle inspector, `⌘0` fit fleet, `⌘+/-` map zoom. All declared in `.commands { }` so they appear in the menu bar with their shortcuts.
- Menu-bar extra (§7) opens the window and selects the phone clicked (`NSApp.activate`, then set selection).

---

## 3. Colour tokens

### 3a. Measured from `Resources/icon-1024.png` (Pillow, saturated-pixel median per x-band and brightest pixel per hue family)

| Sample | Hex |
|---|---|
| Background (every corner, centre) | `#0E1118` |
| Blue end, brightest (x=192,y=480) | `#2D7DFF` |
| Blue band median x184–249 | `#2E72FB` |
| Violet mid, brightest (x=710,y=484) | `#764AFF` |
| Violet band median x446–512 | `#673CDD` |
| Magenta end, brightest (x=838,y=592) | `#AB31FF` |
| Magenta band median x774–840 | `#9C31FF` |
| Shadow lobes in the overlaps | `#0A409E` · `#332897` · `#481FC3` |

The mark's hue runs 219° → 254° → 273°. Note: the "magenta" is an electric purple-magenta, not pink; the proposal never drifts toward `#FF2D95`-style pinks.

### 3b. Dark (default)

| Token | Hex | Use |
|---|---|---|
| `bg.window` | `#0E1118` | window ground = icon ground |
| `bg.field` | `#0B0E14` | under the gradient field, map bezel |
| `surface.panel` | `#141925` | sidebar/inspector fallback fill (materials tint toward this) |
| `surface.raised` | `#1B2130` | cards, fields, secondary buttons |
| `surface.selected` | `#1E2436` | selected row fill |
| `hairline` | `#262D3D` | 1pt separators, map bezel stroke (1.28:1 vs panel — intentionally quiet) |
| `text.primary` | `#F2F4F8` | |
| `text.secondary` | `#A9B1C3` | |
| `text.tertiary` | `#7E88A0` | section headers, meta |
| `text.hint` | `#5A6378` | disabled + placeholder only |
| `accent.blue` | `#2D7DFF` | light: glows, rings, edge bar |
| `accent.violet` | `#764AFF` | light |
| `accent.magenta` | `#AB31FF` | light |
| `accent.blueText` | `#5C9BFF` | blue as text/icon |
| `accent.violetText` | `#9A7DFF` | violet as text/icon |
| `accent.magentaText` | `#C466FF` | magenta as text/icon |
| `lamp` gradient | `#2468E6 → #6740E8 → #9429E6` | primary button fill (icon gradient darkened ~10% so white text passes AA) |
| `light` gradient | `#2D7DFF → #764AFF → #AB31FF` | every non-text glow, ring, halo, spoofed pin, selected edge |
| `status.ok` | `#37D67A` | real GPS / applied |
| `status.busy` | `#FFB340` | locating, connecting, reconnecting |
| `status.error` | `#FF5A5F` | error, crash loop |
| `status.mono` | `#4FD1FF` | coordinates, IPs, the Mac's real marker |
| `status.off` | `#7E88A0` | disconnected, mode off |
| `focus` | `#5C9BFF` | 2pt focus ring |

Gradient field lobes: three radial gradients, centres drifting (§6), colours `#2D7DFF`, `#764AFF`, `#AB31FF` at 16% opacity, blur radius 120, over `bg.field`. Behind glass this reads as light on a console, never as a painted background.

### 3c. Light variant

| Token | Hex |
|---|---|
| `bg.window` | `#F2F3F7` |
| `bg.field` | `#EAECF2` |
| `surface.panel` | `#FFFFFF` |
| `surface.raised` | `#F7F8FB` |
| `surface.selected` | `#E8ECF6` |
| `hairline` | `#DCE0EA` |
| `text.primary` | `#111420` |
| `text.secondary` | `#48506A` |
| `text.tertiary` | `#5F6983` |
| `text.hint` | `#9AA3B8` |
| `accent.blue / violet / magenta` (text and lamp) | `#1A62D2` / `#5D3DE0` / `#8F1FD6` |
| `light` gradient (glows only) | `#2D7DFF → #764AFF → #AB31FF` at 22% opacity |
| `status.ok / busy / error / mono / off` | `#157A45` / `#8F5200` / `#C4262E` / `#086C90` / `#5F6983` |

Gradient field in light mode: same lobes at 10% — a faint aurora, not a wash.

---

## 4. Type scale (SF Pro via `.system(size:weight:design:)`)

| Role | Size / weight | Where |
|---|---|---|
| Inspector title | 17 semibold | handle at top of Phone panel |
| Fleet counters | 26 semibold, `.monospacedDigit()` | "3" spoofed / "4" phones |
| Header | 15 semibold | inspector section titles |
| Section label | 11 semibold, uppercase, tracking 0.6, `text.tertiary` | FLEET / PHONES / PROXY / SCATTER |
| Row title | 13 semibold | handle in roster |
| Row subtitle | 11 regular, `text.secondary` | "iPhone XR · London" |
| Body | 13 regular | descriptions, banners |
| Label | 12 medium | buttons, segmented control |
| Caption | 11 regular, `text.secondary` | timestamps, "last checked 14:02" |
| Pill | 10 medium, tracking 0.2 | status pills |
| Mono | 12 regular `.monospaced` | lat/lon, IP, UDID, pid, mono values in `status.mono` or `text.secondary` |
| Mono small | 11 regular `.monospaced` | telemetry strip, sidebar footer |

Line heights are system defaults; vertical rhythm is 4pt inside components, 8pt between, 12/20 between blocks/sections. Numbers everywhere use `.monospacedDigit()` so counters do not jitter.

---

## 5. Component inventory (every state)

### 5.1 Phone row (sidebar, 44pt)
Layout: `HStack(spacing: 10) { StatusDot; VStack(alignment:.leading, spacing:2) { handle; model · city } ; Spacer; trailing glyph }`, `.listRowInsets(12)`. Selected row: `surface.selected` fill + a 2pt vertical `light` gradient bar on the leading edge (`overlay(alignment:.leading)`) — that bar is the only gradient in the roster.
1. **Real GPS / idle** — dot `status.ok` 8pt, no glow. Subtitle "iPhone XR · Real GPS".
2. **Locating…** — dot `status.busy`, glow pulse (§6). Subtitle "iPhone XR · Locating…".
3. **Connecting / tunnel up** — dot half-ring in `status.busy` (SF `circle.lefthalf.filled`), subtitle "Applying…".
4. **Spoofed** — dot filled with `light` gradient + 6pt glow shadow at 60%. Subtitle "iPhone XR · London, GB".
5. **Reconnecting** — dot `status.busy` with a tiny rotating `arrow.triangle.2.circlepath` 9pt at the trailing edge; subtitle "Reconnecting · try 3 in 5 s".
6. **Error** — dot `status.error`, trailing `exclamationmark.triangle.fill` 11pt in `status.error`.
7. **Unplugged while spoofed** — whole row at 55% opacity, dot `status.off` hollow ring, subtitle "Unplugged · will re-apply". Row keeps its place (sorted by first_seen, stable).
8. **Hover** — `surface.raised` fill at 60%.
9. **Focused (keyboard)** — 2pt `focus` ring inset 2, corner 6.
Accessibility label is one sentence: "nat.hunterrr, iPhone XR, Spoofed, London, United Kingdom".

### 5.2 Status pill (inspector, fleet chips, menu bar)
`Capsule` 20pt tall, 8pt horizontal padding, dot 6pt + text 10 medium. Fill = status colour at 14% over panel; text = the status colour where it passes AA, otherwise `text.primary`:
- Real GPS: fill `#193331`, text `#37D67A`.
- Locating… / Applying… / Reconnecting: fill `#352F29`, text `#FFB340`, dot pulses.
- Spoofed · London, GB: fill `#26224C` (violet 18%), text `text.primary`, dot = `light` gradient with glow.
- Error: fill `#35222D`, text `#FF5A5F`.
- Unplugged: fill `#232936`, text `text.secondary`, dot hollow.
- Off (mode off, no target): fill `#232936`, text `text.secondary` (tertiary would only reach 4.10 here).

### 5.3 Proxy field (inspector)
`TextField` styled `.plain` inside a 32pt `surface.raised` rounded-8 box with 1pt `hairline`; mono 12. Password is masked by rendering the normalized form with `••••` — the raw string lives in the model; an eye button (SF `eye` / `eye.slash`) toggles reveal per field, default masked, never persisted as revealed.
Live parse feedback line under the field, 11 caption, updates on every keystroke via `parse_proxy` debounced 250 ms:
- Empty: "Paste host:port:user:pass, user:pass@host:port or socks5://…" in `text.hint`.
- Parsing: "…" nothing for <250 ms, then result.
- Valid: `checkmark.circle.fill` in `status.ok` + "socks5h · proxy.example.net:1080 · user jm…" in `text.secondary`.
- Valid but HTTP: `info.circle` in `status.busy` + "HTTP proxy — treated as http://".
- Invalid: `xmark.circle.fill` in `status.error` + the engine's message; field border becomes `status.error` 1pt.
- Locate in flight: field disabled at 70%, Locate button shows spinner + stage text from `geo_progress` ("querying ipwho.is").
Paste of a multi-line string into a single field offers a toast "3 lines pasted — open bulk paste?" with a button.

### 5.4 Geo result card
Rounded-12 glass card, 12 padding, `light` gradient 1pt ring at 35% opacity when the result is what the phone is currently pinned to.
Full form: row 1 flag emoji 20pt + city 15 semibold; row 2 "England · United Kingdom" 12 secondary; row 3 `network` glyph + ISP 12; row 4 mono IP in `status.mono` 12 + copy button; row 5 `clock` + timezone + local time (live, `TimelineView(.periodic(1 min))`); footer 11 caption: "via ip-api.com · 1.2 s · checked 14:02" + **Re-check** text button.
States: skeleton (5 shimmering bars 8pt tall, `surface.raised`, 1.2 s shimmer), **degraded** (amber left bar 3pt, note "Gateway IP — may differ from exit IP" in `status.busy`, secondary button "Use gateway location anyway"), **unreachable** (red left bar, "Proxy unreachable — connection timed out after 15 s", Retry, and the degraded card stacked beneath if `fallback` present), **providers failed** ("All 3 providers failed", last stage, Retry), **stale** (target set, proxy edited since: amber footer "Proxy changed — Locate again"). Compact two-line form (<1100 wide): "🇬🇧 London · Virgin Media" / "82.12.4.9 · Europe/London".

### 5.5 Map pins (`Annotation` with custom `View`, `MapContentBuilder`)
- **Spoofed**: 22pt circle filled `light` gradient, 1.5pt white inner ring at 85%, 2pt gradient halo at 40% (scale 1.35), shadow radius 8 in `accent.violet` 55%. Label chip under it: handle 11 semibold on `surface.panel` 85%, rounded 6, offset y+16.
- **Pending** (connecting / tunnel_up / locating): 22pt hollow circle, 1.5pt `status.busy` stroke, inner dot 6pt, pulsing halo. Chip text "locating…" in caption.
- **Reconnecting**: spoofed pin at 60% opacity + 9pt `status.busy` badge top-trailing.
- **Error**: 22pt hollow, 1.5pt `status.error`, `exclamationmark` 10 inside.
- **Unplugged**: spoofed pin at 35%, dashed ring (`StrokeStyle(dash:[3,3])`), chip "unplugged".
- **Real (this Mac)**: 14pt hollow 1.5pt `status.mono` ring with 4pt crosshair ticks, chip "This Mac · Dartmouth". Never has a glow.
- **Manual drag**: on `DragGesture` the pin scales 1.15, shadow radius 14, chip shows live lat/lon mono; on release `MapProxy.convert(point, from: .local)` sets the target, pin settles with the drop spring (§6). Scatter shows as a translucent disc (`MapCircle`, `light` gradient 12%) of the chosen radius.
- Fleet view labels every pin by handle; overlapping pins nudge ±14pt along a short spiral (client-side, deterministic by udid hash).

### 5.6 Mode segmented control
`Picker(selection:) { Proxy | Manual | Off }.pickerStyle(.segmented)` 28pt tall, full width. Selected segment gets a 1pt `light` gradient ring on top of the system selection (overlay). Off disables the sections below (35% opacity) and shows a one-line explanation "Phone uses its real GPS".

### 5.7 Scatter slider
`Slider(value:in:0...3000, step:50)` with a mono readout "0 m" / "1.2 km" 12 at the trailing end, 44 wide, `.monospacedDigit()`. Track tint `accent.violet`. Label "SCATTER" section style; helper caption "Random offset so phones on one ISP don't share a pixel". 0 shows "exact".

### 5.8 Buttons
- **Primary** ("Pin phone here", "Locate", "Pin all", "Re-apply all"): 32pt, full width in inspector, `lamp` gradient fill, white label 12 medium, 1pt `light` ring at 60%, outer glow shadow radius 10 `accent.violet` 35%. Hover: brightness +6%; pressed: brightness −8%, glow radius 4; disabled: `surface.raised` fill, `text.hint` label, no glow; loading: label swaps to `ProgressView` + stage text.
- **Secondary** ("Release", "Re-check", "Retry", "Cancel"): 32pt, `surface.raised` fill, 1pt `hairline`, `text.primary` label. Destructive variant ("Release all"): label `status.error`.
- **Text button** ("Copy", "Show log"): 12 medium `accent.blueText`, underline on hover.
- Toolbar buttons use `.buttonStyle(.bordered)` unchanged — native is correct in the toolbar.

### 5.9 Toasts
Bottom-centre of the map, 36pt tall, glass capsule, leading SF glyph tinted by kind, 12 medium text, optional trailing text button. Kinds: ok (`checkmark.circle.fill`, `status.ok`) e.g. "Pinned @nat.hunterrr to London"; busy; error ("Worker for @onlyemspage crashed — Retry"); info. Stack max 3, newest at bottom, auto-dismiss 4 s (errors 8 s, hover pauses). Enter/exit §6.

### 5.10 Sheets
- **Bulk paste** (`.sheet`, 640×520): left `TextEditor` mono 12 on `surface.raised`; right a live preview table (`Table` or `Grid`): row per line → "→ handle" mapping with status pill (Parsed / Bad line / No phone for this line / Handle not found), mapping rule shown as a segmented control "By list order | By handle". Footer: count "3 of 4 lines map to phones", Cancel, **Apply & Locate all** (primary). Lines that fail are highlighted with a red left bar; nothing applies until the user clicks Apply.
- **Quit confirmation**: `NSAlert` critical style: "Quitting returns 4 phones to their real GPS." / "The spoof lives only while Only Social GPS is running." Buttons: Quit (default) / Cancel. Only when ≥1 phone is spoofed or reconnecting.
- **About**: small sheet with the mark PNG at 96pt, version, engine/python versions in mono, log folder link.

### 5.11 Setup screen (Python / pymobiledevice3 missing)
Replaces the whole window content over the gradient field. Centred 520-wide column: mark PNG 120pt with its glow; title 17 "One thing to install"; body 13 "Only Social GPS drives iPhones through pymobiledevice3, which isn't installed for `/opt/homebrew/bin/python3`."; mono copy box 40pt with the exact command `pip3 install pymobiledevice3` (append `--break-system-packages` when Homebrew Python detected) and a Copy button; caption "Detected Python 3.14.6 at /opt/homebrew/bin/python3" or "No python3 found on PATH"; buttons **Check again** (primary) and "Choose Python…" (secondary, `NSOpenPanel`). The engine-starting spinner appears here too after Check again.

### 5.12 Empty state (no phones on USB)
Sidebar: below FLEET a single placeholder row, `cable.connector` 20pt `text.tertiary`, "No iPhones on USB", subtitle "Plug one in — it appears within 2 s". Map: only the Mac marker, camera on the Mac. Inspector: a checklist card: `cable.connector` USB cable · `hand.raised` "Trust this computer" tapped · `hammer` Developer Mode on — each line with a grey ring that fills green as the first device reports `paired` / `developer_mode`.

### 5.13 Fleet panel (inspector when `.fleet` selected)
Counters row: 4 PHONES · 3 SPOOFED · 1 LOCATING (26 semibold + 11 label). Then a **This Mac** card (real IP geo, mono IP, "Bell Canada · America/Halifax"). Then "Paste proxy list…" (secondary, `⌘⇧V`), **Locate all**, **Pin all** (primary), "Release all" (destructive secondary). Then chips: one 28pt row per phone (dot, handle, pill) — clicking selects that phone.

### 5.14 Engine states (whole-app)
- **Starting**: sidebar shows 3 skeleton rows (shimmer), telemetry strip "ENGINE ◌ starting…", inspector "Waiting for engine…" caption; hard cap 6 s then an error banner with "Show log" + "Restart engine".
- **Hello received, no devices yet**: empty state (§5.12).
- **Engine died**: red banner top of map "Engine stopped (exit 1) — Restart", roster rows go to Unplugged appearance, menu-bar dot red.
- **Worker crash-looping** (state error with `restarts ≥ 3`): row red (§5.1-6); inspector shows a red banner "Worker keeps crashing (5 restarts)" with the last error in a mono 3-line box (`.lineLimit(3)`, expandable), buttons **Retry** (`worker_restart`) and "Show log"; pin becomes the error pin.
- **Phone unplugged while spoofed**: §5.1-7, inspector amber banner "Unplugged — will re-apply London when it returns", pin at 35%.

### 5.15 Telemetry strip (map overlay, 28pt)
Glass strip, mono 11: leading "ENGINE ● connected · 4 workers" (dot per engine state) · centre live cursor lat/lon while hovering the map (`onContinuousHover` + `MapProxy.convert`), otherwise the selected target · trailing "THIS MAC · Dartmouth, NS · 142.x.x.x" in `status.mono`. This strip is the flight-ops signature.

---

## 6. Motion spec

| What | Duration / curve | Detail |
|---|---|---|
| Status dot colour | 240 ms `easeInOut` | colour + glow radius animate together |
| Busy pulse (locating / reconnecting) | 1.6 s `easeInOut` `.repeatForever(autoreverses: true)` | glow opacity 0.35 → 0.9, dot scale 1.0 → 1.12 |
| Spoofed light-up | 420 ms `spring(response: 0.42, dampingFraction: 0.72)` | dot scale 0.6 → 1, glow 0 → 60%, edge bar fades in 200 ms |
| Pill text change | 200 ms | `.contentTransition(.opacity)`; width animates with the same curve |
| Row selection | 160 ms `easeOut` | fill + 2pt edge bar (edge bar slides from 0 to full height) |
| Camera fly-to (city → city) | 900 ms `easeInOut` on `MapCameraPosition` | via `withAnimation`; >3000 km flights zoom out to distance 6000 km at 40% then in |
| Camera local move (<50 km) | 500 ms `easeInOut` | |
| Fit fleet | 700 ms `easeInOut` | |
| Pin drop | 450 ms `spring(response: 0.45, dampingFraction: 0.7)` | scale 0.6 → 1 from y−12; halo ring scales 1 → 2.2 and fades 0.6 → 0 over 900 ms, once |
| Pin release | 260 ms `easeIn` | scale to 0.6, opacity 0; the real-GPS state has no pin |
| Gradient field | 24 s loop, `TimelineView(.animation(minimumInterval: 1/30))` | 3 lobes move on Lissajous paths (amplitude 18% of width, 12% of height, phases 0 / 2.1 / 4.2 rad); frozen under Reduce Motion |
| Toast | in 260 ms `spring(response: 0.35, dampingFraction: 0.8)` from y+24; out 200 ms fade | |
| Sheet | system | |
| Skeleton shimmer | 1.2 s linear repeat | `LinearGradient` sweep, 18% highlight |
| Primary button glow on hover | 150 ms | shadow radius 10 → 14 |

Reduce Motion: pulses become static 70% glow, camera moves are instant, field frozen, springs become 200 ms easeOut.

---

## 7. Menu-bar extra

`MenuBarExtra(isInserted: .constant(true)) { … } label: { Image("MenuBarIcon").renderingMode(.template); Text("3") }` with `.menuBarExtraStyle(.window)`. The label shows the mark plus the spoofed count (no count when 0). Popover 300 wide:
- Header 40pt: "Only Social GPS" 13 semibold + engine dot + "4 phones · 3 spoofed" caption.
- One 32pt row per phone: dot, handle 12 medium, compact pill (city or state). Click → opens main window, selects that phone.
- Footer 44pt: **Re-apply all** (lamp, 26pt tall) and "Release all" (secondary). A text button "Open Only Social GPS" and the shortcut hint "⌘Q quits and releases".
- States: engine starting → rows replaced by "Starting engine…"; no phones → "No iPhones on USB"; engine dead → red row "Engine stopped — Restart".
The template icon stays monochrome; the count text carries the "glow" idea in the menu bar.

---

## 8. The "wow" moment: the power-on sequence (first launch, ≤ 2.5 s)

1. t=0: window appears already dark; gradient field fades in from 0 to 16% over 600 ms — the console comes alive.
2. t=0.2 s: map renders zoomed out to camera distance 9000 km centred on the Mac's real location; the Mac marker draws its crosshair ring (300 ms).
3. t=0.4–1.4 s: as the engine's first `devices` event lands, roster rows appear staggered 120 ms apart, each dot lighting green with the light-up spring — you watch the fleet come online.
4. t=1.4–2.4 s: if `reapply-on-launch` has targets, pins drop one after another (120 ms stagger) on the still-zoomed-out map, each halo ring expanding, and the camera fits the fleet at 700 ms. The telemetry strip reads "ENGINE ● connected · 4 workers".
5. If there are no targets yet, the inspector's Fleet panel highlights "Paste proxy list…" with a single 900 ms gradient-ring sweep — the only hint the app ever gives.
Subsequent launches run the same sequence at half the stagger (60 ms). Reduce Motion: all appear at once.

---

## 9. Accessibility

### 9a. Contrast (WCAG 2.x relative luminance, computed with Pillow-side script)

Dark, text on surfaces (≥ 4.5 required for text, ≥ 3.0 for UI glyphs/rings):

| Text | on `bg` #0E1118 | on `panel` #141925 | on `raised` #1B2130 | on `selected` #1E2436 |
|---|---|---|---|---|
| primary #F2F4F8 | 17.15 | 15.95 | 14.59 | 14.01 |
| secondary #A9B1C3 | 8.78 | 8.17 | 7.47 | 7.17 |
| tertiary #7E88A0 | 5.32 | 4.95 | 4.53 | 4.35 (only used for section headers, which never sit on selected) |
| blueText #5C9BFF | 6.82 | 6.35 | 5.81 | 5.58 |
| violetText #9A7DFF | 6.07 | 5.65 | 5.17 | 4.96 |
| magentaText #C466FF | 6.02 | 5.60 | 5.12 | 4.92 |
| status.ok #37D67A | 9.95 | 9.25 | 8.46 | 8.13 |
| status.busy #FFB340 | 10.59 | 9.85 | 9.01 | 8.65 |
| status.error #FF5A5F | 6.19 | 5.75 | 5.26 | 5.06 |
| status.mono #4FD1FF | 10.70 | 9.95 | 9.10 | 8.74 |
| hint #5A6378 (disabled/placeholder, exempt) | 3.14 | 2.92 | 2.67 | 2.57 |

Pills (text on its 14% tint over panel): ok 7.09 · busy 7.41 · error 4.85 · mono 7.41 · off (secondary text on #232936) 6.77 · spoofed (primary on #26224C) 13.47.
Primary button white label on `lamp` stops: 5.00 / 6.04 / 5.65 (the raw icon gradient would give 3.83 at the blue end — that is why the fill is darkened and the true hues live in the ring and glow). Non-text glows/rings vs panel: blue 4.59, magenta 3.86, violet 3.51 — all ≥ 3.0. Focus ring #5C9BFF vs panel 6.35, vs raised 5.81.

Light, text on surfaces:

| Text | on `bg` #F2F3F7 | on `panel` #FFFFFF | on `raised` #F7F8FB | on `selected` #E8ECF6 |
|---|---|---|---|---|
| primary #111420 | 16.54 | 18.34 | 17.27 | 15.51 |
| secondary #48506A | 7.20 | 7.98 | 7.52 | 6.75 |
| tertiary #5F6983 | 4.94 | 5.48 | 5.16 | 4.63 |
| blue #1A62D2 | 5.09 | 5.64 | 5.31 | 4.77 |
| violet #5D3DE0 | 5.90 | 6.54 | 6.16 | 5.53 |
| magenta #8F1FD6 | 5.68 | 6.30 | 5.93 | 5.33 |
| ok #157A45 | 4.85 | 5.38 | 5.07 | 4.55 |
| busy #8F5200 | 5.61 | 6.22 | 5.86 | 5.26 |
| error #C4262E | 5.17 | 5.73 | 5.40 | 4.85 |
| mono #086C90 | 5.32 | 5.90 | 5.56 | 4.99 |

Light pills (12% tint): ok 4.56 · busy 5.22 · error 4.73 · mono 4.95 · blue 4.75. Light lamp gradient with white label: 5.64 / 6.54 / 6.30.

### 9b. Keyboard and assistive
- Full tab order: search → roster → toolbar → inspector top-to-bottom (mode → proxy field → eye → Locate → geo card buttons → scatter → Pin → Release → worker disclosure). `.focusable()` on custom rows; `.focused($field, equals:)` moves focus into the proxy field on `⌘L` when empty.
- Every custom control has `.accessibilityLabel` + `.accessibilityValue` (pill: "Status, Spoofed, London, United Kingdom"; scatter: "Scatter, 1.2 kilometres"). Pins are `.accessibilityElement` with the handle and state; the map itself exposes `.accessibilityAction(named: "Fit fleet")`.
- Colour is never the only signal: every state has a glyph or text alongside the dot (§5.1). Busy pulse and error glyph differ in shape, not only hue.
- Reduce Transparency: materials fall back to `surface.panel` opaque; the gradient field drops to 6%. Increase Contrast: hairlines go to `#3A4356` / `#C4CAD8`, tertiary text to secondary.
- Minimum hit targets 28×28 for icon buttons (eye, copy), 32 tall for all buttons.

---

## 10. Risks and decisions I am taking

- `Annotation` views are not natively draggable in SwiftUI `Map`; drag is implemented with a `DragGesture` on the annotation view and `MapProxy.convert` — verified pattern on macOS 14+, keep the camera `interactionModes` intact during drag by setting `.allowsHitTesting` only on the pin.
- `.inspector` is macOS 14+, fine for the 15.0 target; if its width clamps oddly at 1000 wide, fall back to `HSplitView(map, inspector.frame(width: 300))`.
- MapKit dark style follows the environment colour scheme; we force `.preferredColorScheme(.dark)` on the window for the dark-default and let the user toggle to light via the theme setting.
- The gradient field costs one `Canvas` redraw at 30 fps; on the Mac mini this is negligible, and it pauses when the window is occluded (`NSWindow.occlusionState`).
- Glass on macOS 26 applies to: geo card, telemetry strip, toasts, menu-bar popover rows. Sidebar and inspector keep the system materials so they behave like every other Mac app.
