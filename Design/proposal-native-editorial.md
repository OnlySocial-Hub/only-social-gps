# Only Social GPS — Design proposal: "Native Editorial"
**Thesis.** The most Mac-like app we can build. Three columns the OS already knows how to draw
(sidebar → content → inspector), a large typographic header that reads like a magazine deck
("@nat.hunterrr / London, United Kingdom 🇬🇧 / Spoofed"), and exactly one gradient — the one
in the icon — used in exactly five places. Everything else is system material, system type,
system controls. The wow is that it looks like Apple shipped it.

Palette source: `Resources/icon-1024.png`, sampled with Pillow (3×3 averages, alpha>250):

| sample point | hex | role |
|---|---|---|
| O left edge (210,512) | `#2D76FD` | gradient stop 0 (blue) |
| O bottom-left (300,650) / O bottom (430,705) | `#5C60FD` / `#794DFD` | intermediate tones (not tokens) |
| S waist (690,500) | `#7243FC` | gradient stop 0.55 (violet) |
| S right belly (805,600) / S bottom-right (760,690) | `#A333FE` / `#AE2DFE` | gradient stop 1 (magenta, `#AE2DFE`) |
| overlap shadow (560,400) / S top-right tip (790,360) | `#0A1C6C` / `#4F1EC8` | deep tones (glow core) |
| background (512,512) / (512,60) / (900,900) | `#0E1118` | window background |

Gradient direction in the icon is top-left → bottom-right (blue O, magenta S), so every use of
the accent is `LinearGradient(stops: [#2D76FD @ 0, #7243FC @ 0.55, #AE2DFE @ 1], start: .topLeading, end: .bottomTrailing)`.

## 1. Window layout
Default 1280×820. Minimum 1000×700 (`.windowResizability(.contentMinSize)` + `.frame(minWidth: 1000, minHeight: 700)`). Frame autosaved by `WindowGroup` (NSWindow frame autosave — free).
### 1280×820 (device selected)
```
┌─ 52 ─ unified toolbar (system) ───────────────────────────────────────────────────────────────┐
│ ◧  Only Social GPS                                    [Locate ⌘L] [Pin ⌘⏎]        ⓘ inspector │
├──────240──────┬──────────────────────── 720 ─────────────────────────┬──────── 320 ───────────┤
│ SIDEBAR       │ HEADER (148 tall, solid window bg)                    │ INSPECTOR              │
│               │                                                       │                        │
│ ▣ Fleet       │  @nat.hunterrr                     ● Spoofed · London │ PROXY                  │
│               │  34pt bold, -0.6 tracking          pill, top-right    │ ┌────────────────────┐ │
│ PHONES        │                                                       │ │socks5h://u:••••@…  ◉│ │
│ ● nat.hunterrr│  London, United Kingdom  🇬🇧                          │ └────────────────────┘ │
│   XR · 18.7.9 │  22pt semibold                                        │ socks5h · 45.12.8.3:1080│
│ ● onlyemspage │                                                       │ [ Locate ]  Re-check   │
│   XR · 18.7.9 │  iPhone XR · iOS 18.7.9 · 51.5074, -0.1278 · Virgin   │                        │
│ ○ glazertori  │  13pt secondary, mono for numbers                     │ 🇬🇧 London, England    │
│   Unplugged   ├───────────────────────────────────────────────────────┤ IP   185.22.9.114      │
│ ● ellybelly   │ MAP (720 × 620)                                       │ ISP  Virgin Media      │
│   11 · 18.7.8 │                                                       │ TZ   Europe/London     │
│               │        ◎ This Mac · Dartmouth (hollow ring)           │ checked 2 min ago      │
│               │                                                       │                        │
│               │                        ● nat.hunterrr (gradient pin)  │ MODE                   │
│               │                          ╰ scatter ring 750 m         │ [Proxy | Manual | Off] │
│               │                                                       │ SCATTER    750 m       │
│               │                                                       │ ○────●────────  0–3 km │
│               │                                                       │                        │
│ ─────────────  │                                     ⊕ compass/scale   │ ┌────────────────────┐ │
│ ◎ Dartmouth,NS│      ┌───────────────────────────┐                    │ │  Pin phone here  ⏎ │ │ ← gradient
│ ● engine ok   │      │ ✓ Pinned to London  (toast)│                    │ └────────────────────┘ │
│               │      └───────────────────────────┘                    │      Release  ⌘⌫        │
└───────────────┴───────────────────────────────────────────────────────┴────────────────────────┘
```

Region sizes (pt): sidebar 240 (min 200 / ideal 240 / max 300); content = remainder;
inspector 320 (min 280 / ideal 320 / max 380). Header 148 = 20 top pad + 41 handle line + 8 + 28
city line + 6 + 18 meta line + 27 bottom pad; hairline (1 px, white 8%) between header and map.
Sidebar row 44 tall, 2 lines. Inspector content inset 16, section gap 24. Toast 36 tall, bottom 20.
### 1000×700 (minimum)
```
┌─ 52 ─ toolbar ────────────────────────────────────────────────────────────────┐
├──200──┬──────────────────── 520 ──────────────────────┬──────── 280 ──────────┤
│ Fleet │ HEADER (108 tall)                              │ PROXY                 │
│ ───── │ @nat.hunterrr            ● Spoofed · London    │ [socks5h://u:••@… ◉]  │
│ ● nat │ London, United Kingdom 🇬🇧 · XR · 18.7.9       │ [Locate]              │
│ ● ems ├────────────────────────────────────────────────┤ 🇬🇧 London · 185.22…  │
│ ○ tori│ MAP (520 × 540)                                │ ISP Virgin Media      │
│ ● elly│                                                │ MODE [Prx|Man|Off]    │
│       │                                                │ SCATTER ○──●──  750 m │
│ ───── │                                                │ [ Pin phone here ]    │
│ ◎ NS  │                                                │  Release              │
└───────┴────────────────────────────────────────────────┴───────────────────────┘
```

At ≤ 1100 wide the header collapses to 2 lines (28pt handle, meta joins the city line) —
`ViewThatFits` picks the layout. Below 1180 the inspector is still a column; the user can hide it
(⌥⌘I) and it becomes a trailing overlay sheet on next reveal (system behaviour of `.inspector`).
### Fleet view (sidebar selection = Fleet)
Header "Fleet / 4 phones · 3 spoofed · 1 unplugged" (same 148 header) over a map fitted to all
pins + the Mac ring; under it a chip strip (dot + handle + city, 28 tall, glass on macOS 26).
Inspector = "Paste proxy list…" (⇧⌘V), Locate all, Pin all, Release all, and the Mac's geo card.
### SwiftUI construct map
| region | construct |
|---|---|
| window | `WindowGroup` `.defaultSize(width: 1280, height: 820)`, root `.frame(minWidth: 1000, minHeight: 700)` |
| columns | `NavigationSplitView(columnVisibility:) { sidebar } detail: { content }` + `.inspector(isPresented:) { InspectorView }` `.inspectorColumnWidth(min: 280, ideal: 320, max: 380)` `.navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)` |
| sidebar | `List(selection: $route)` `.listStyle(.sidebar)`, `Section("Phones")`, footer via `.safeAreaInset(edge: .bottom)` |
| header | `VStack(alignment: .leading)` inside `.safeAreaInset(edge: .top)` of the map (solid `bg.window`, not glass) |
| map | `Map(position: $camera, interactionModes: .all) { Annotation(...) { PinView } ; MapCircle(center:radius:) }` `.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))` `.mapControls { MapCompass(); MapScaleView() }`; `MapReader` for tap-to-place in Manual |
| gradient field | `TimelineView(.animation(minimumInterval: 1/20, paused: reduceMotion))` + `Canvas` drawing 3 radial gradients, `.blur(radius: 120)`, as `.background` of the root `ZStack` |
| glass | macOS 26: `GlassEffectContainer { … }` with `.glassEffect(.regular, in: .capsule)` on toast, pin labels, fleet chips, menu-bar popover cards. Fallback `.regularMaterial` / `.ultraThinMaterial` in the same shapes |
| toolbar | `.toolbar { ToolbarItemGroup(placement: .primaryAction) { Locate; Pin } ; ToolbarItem { inspector toggle } }` |
| toasts | `.overlay(alignment: .bottom)` on the content column, `.transition(.move(edge: .bottom).combined(with: .opacity))` |
| sheets | `.sheet(item: $sheet)` (bulk paste); `.alert` for quit (driven from `NSApplicationDelegateAdaptor.applicationShouldTerminate → .terminateLater`) |
| setup / empty | root `switch model.phase` — `.setup` replaces the whole window body; `.noPhones` is a content-column overlay |
| menu bar | `MenuBarExtra("Only Social GPS", image: "MenuBarIcon") { … }.menuBarExtraStyle(.window)` |

## 2. Navigation model
- One `enum Route: Hashable { case fleet; case device(String) }` bound to the sidebar `List`.
  Route is persisted (last selection restored on launch). No push navigation anywhere.
- Inspector is context-bound: `.device` → DeviceInspector; `.fleet` → FleetInspector. It never
  changes column; only its content cross-fades (200 ms).
- Sheets: `bulkPaste`, `about`. Alerts: `quit`, `releaseAllConfirm` (only when ≥ 2 phones spoofed).
- Full-window phases (mutually exclusive, before any route): `.probingPython` (0–3 s spinner),
  `.setup` (Python/pymobiledevice3 missing), `.engineStarting`, `.ready`.
- Shortcuts: ⌘1 Fleet · ⌘2…⌘9 nth phone · ↑↓ move selection · ⌘L Locate · ⌘R Re-check ·
  ⌘⏎ Pin · ⌘⌫ Release · ⇧⌘V Paste proxy list · ⌥⌘I toggle inspector · ⌘F address search
  (Manual mode) · ⌘, Settings · ⌘Q quit (with confirmation if any phone spoofed).

## 3. Colour tokens
Dark first. Every text token below was contrast-checked (section 9).
### Dark (default)
| token | hex | use |
|---|---|---|
| `bg.window` | `#0E1118` | content column, header, sheets — identical to the icon background |
| `bg.sidebar` | `#0B0D13` | sidebar (under system sidebar material at 100% opacity) |
| `bg.inspector` | `#12151D` | inspector column |
| `surface.1` | `#161A24` | cards (geo result), text fields |
| `surface.2` | `#1C2130` | hover on cards, segmented control track |
| `hairline` | white @ 8% (`#21242A` composite) | all dividers, card borders |
| `hairline.strong` | white @ 12% (`#2B2E34`) | focused/hovered borders, Increase Contrast |
| `text.primary` | `#F2F4F8` | handle, values, row titles |
| `text.secondary` | `#A9B0BE` | meta lines, row subtitles |
| `text.tertiary` | `#848C9C` | section labels, "checked 2 min ago", placeholders |
| `text.mono` | `#C8CEDA` | coordinates, IPs, UDIDs, curl stages |
| `accent.gradient` | `#2D76FD → #7243FC → #AE2DFE` | primary button, selection bar, spoofed pin, spoofed dot/glow, gradient field |
| `accent.button` | `#2266E8 → #6236E6 → #9A28EA` | the gradient darkened 12% so a white label clears 4.5:1 at every stop |
| `accent.text` | `#9DA8FF` | links, tinted labels ("Locating…", "Re-check"), pending pin ring |
| `accent.tint` | violet @ 14% over surface (`#232042`) | status-pill fill for Spoofed, selection fill in lists |
| `status.locating` | `#2D76FD` | dot only |
| `status.warn` | `#F5B942` | Reconnecting / gateway-fallback (tint `#353028`) |
| `status.error` | `#FF6B6B` | Error / crash-loop / parse error (tint `#37252E`) |
| `status.neutral` | `#848C9C` | Real GPS dot (hollow), Unplugged, Released |

Deliberately **no green**. "Spoofed" is the success state and it wears the gradient; a second
success colour would dilute the one accent.
### Light
| token | hex |
|---|---|
| `bg.window` `#F5F6FA` · `bg.sidebar` `#ECEEF3` · `bg.inspector` `#F0F1F5` · `surface.1` `#FFFFFF` · `surface.2` `#F2F3F7` |
| `hairline` black @ 8% · `text.primary` `#14171F` · `text.secondary` `#545C6E` · `text.tertiary` `#6E7688` · `text.mono` `#3A4150` |
| `accent.gradient` unchanged · `accent.button` unchanged · `accent.text` `#4A2FD6` · `accent.tint` violet @ 12% over white (`#EEE8FF`) |
| `status.warn` `#9A5B00` (tint `#F3EBE0`) · `status.error` `#C42B1C` (tint `#F8E6E4`) · `status.neutral` `#6E7688` |

Theme follows the system by default; Settings offers Dark / Light / System. Dark is the hero
and every snapshot in `DESIGN.md` should be dark.
### Where the gradient is allowed — the whole list
1. Primary button fill (`accent.button` variant).
2. Sidebar selection: 3pt leading bar in `accent.gradient` + row fill `accent.tint`.
3. Spoofed map pin fill + its 10pt glow.
4. Spoofed status dot (8pt) + 6pt glow, in rows, pills, menu bar.
5. The gradient field behind the window: three radial blobs at 6–8% opacity.

Nowhere else. No gradient text, no gradient icons, no gradient borders, no gradient sliders.

## 4. Type scale (SF Pro via `.system`, no custom fonts)
| role | spec | SwiftUI |
|---|---|---|
| Header handle | 34 / Bold / tracking −0.6 / line 41 | `.system(size: 34, weight: .bold)` `.tracking(-0.6)` |
| Header handle (≤1100 w) | 28 / Bold / −0.4 | `ViewThatFits` alternate |
| Header city | 22 / Semibold / −0.2 | `.title2.weight(.semibold)` |
| Header meta | 13 / Regular / secondary; numbers mono 13 Medium | `.body` + `.system(size: 13, weight: .medium, design: .monospaced)` |
| Sheet / setup title | 22 / Semibold | `.title2.weight(.semibold)` |
| Section label (inspector) | 11 / Semibold / uppercase / +0.6 tracking / tertiary | `.caption.weight(.semibold)` `.textCase(.uppercase)` |
| Row title | 13 / Medium | `.body.weight(.medium)` |
| Row subtitle | 11 / Regular / secondary | `.caption` |
| Body / field text | 13 / Regular | `.body` |
| Button label | 13 / Semibold | `.body.weight(.semibold)` |
| Status pill | 11 / Semibold | `.caption.weight(.semibold)` |
| Pin label | 11 / Semibold | same |
| Toast | 13 / Medium | `.body.weight(.medium)` |
| Mono value (IP, lat/lon, UDID) | 12 / Regular / monospaced / `text.mono` | `.system(size: 12, design: .monospaced)` `.monospacedDigit()` |
| Mono command (setup) | 13 / Regular / monospaced | same, in a `surface.1` block |
| Fine print ("checked 2 min ago") | 11 / Regular / tertiary | `.caption` |

Never bolder than Bold, never smaller than 11. Line spacing: system defaults. Text is left-aligned
everywhere except the toast and the setup screen (centered).

## 5. Component inventory (every state)
### 5.1 Phone row (sidebar, 44 tall)
Layout: `[dot 8 · 12 gap] [title 13 medium / subtitle 11 secondary] … [trailing 11 tertiary]`.
Title = nickname (farm handle, no @ in the sidebar; @ appears only in the header). Subtitle =
"iPhone XR · 18.7.9". Trailing = city ("London") when spoofed, else empty.

| state | dot | subtitle | row |
|---|---|---|---|
| Real GPS (idle) | hollow ring 8pt, 1.5pt `status.neutral` | model · iOS | normal |
| Locating / connecting / tunnel_up | `status.locating` filled, pulse (see §6) | "Locating…" / "Connecting…" / "Applying…" | normal |
| Spoofed (simulating) | gradient filled + 6pt glow | model · iOS · trailing city | normal |
| Reconnecting | `status.warn` filled | "Reconnecting · try 3 · 10 s" (countdown live) | normal |
| Error / crash-loop | `status.error` filled | "Worker failed ×3 — tunnel refused" (1 line, tail-truncated) | normal |
| Unplugged (disconnected) | hollow ring, dashed | "Unplugged · will re-apply" | 55% opacity (`#8A8C91` text, 5.8:1) |
| Released (transient 2 s) | hollow ring | "Released" | normal, then → Real GPS |
| Hover | — | — | white 4% fill |
| Selected | — | — | `accent.tint` fill + 3pt gradient bar on the leading edge, radius 6 |
| Selected + unplugged | — | — | same, 55% content opacity |

Context menu (⌃-click / menu key): Locate · Pin · Release · Re-check proxy · Restart worker ·
Rename… · Copy UDID · Copy proxy (masked). Rows are draggable? No.
### 5.2 Status pill (header top-right, 22 tall, capsule, padding 8×4, 11 Semibold, dot 8 + 6 gap)
| state | fill | text | dot |
|---|---|---|---|
| Real GPS | white 6% | `text.secondary` | hollow neutral |
| Locating… | blue 14% (`#192742`) | `accent.text` | locating, pulse |
| Spoofed · London, GB | `accent.tint` | `accent.text` | gradient + glow |
| Reconnecting · 10 s | warn tint | `status.warn` | warn |
| Error | error tint | `status.error` | error |
| Unplugged | white 6% | `text.tertiary` | dashed hollow |
| Released | white 6% | `text.secondary` | hollow → fades to Real GPS |

Text changes cross-fade (`.contentTransition(.opacity)`, 200 ms); countdown digits use
`.contentTransition(.numericText())`. On macOS 26 the pill is `.glassEffect(.regular.tint(tintColour), in: .capsule)`.
### 5.3 Proxy field
`TextField` 28 tall, `surface.1`, hairline border, radius 6, 12pt mono. Trailing 20×20 eye
button (`eye` / `eye.slash`). Not focused → renders `Proxy.normalized` from the engine
(`socks5h://user:•••@host:port`, password masked). Focused → raw string, still masked unless
the eye is on (reveal resets to masked when focus leaves). Below the field one 11pt line:

| state | line | field |
|---|---|---|
| empty | placeholder "host:port:user:pass or socks5://…" | normal |
| valid | "socks5h · 45.12.8.3:1080 · user" `text.secondary`, leading `checkmark.circle` in `accent.text` | normal |
| invalid | "Can't read this — expected host:port:user:pass" `status.error` | 1pt `status.error` border |
| locating | "Connecting through proxy…" → stage text from `geo_progress`, `accent.text` | disabled, trailing `ProgressView().controlSize(.small)` |
| multi-line paste | line "3 lines pasted — Paste as list…" as a link | opens bulk sheet pre-filled |
| unchanged since last locate | — | Re-check appears next to Locate |

Never logged. Copy from the context menu copies the masked form.
### 5.4 Geo result card (`surface.1`, radius 10, hairline, padding 14)
```
🇬🇧  London, England                 ← 15 Semibold, flag 20pt (Unicode regional indicators, no asset)
     United Kingdom                  ← 13 secondary
─ hairline ─
IP     185.22.9.114                  ← label 11 tertiary uppercase, value 12 mono
ISP    Virgin Media · AS5089
TZ     Europe/London · 14:32 local   ← local time computed in Swift with TimeZone(identifier:)
Checked 2 min ago · ip-api.com · 1.2 s          Re-check ↻    ← 11 tertiary, Re-check = accent.text link
```

| state | rendering |
|---|---|
| empty | dashed hairline (1pt, dash 4/4), centered 12pt tertiary "Locate to see the exit IP" |
| loading | header shows "Locating…" in `accent.text`; one 11pt stage line; no skeleton, no shimmer |
| success | as above |
| gateway fallback | full card + top bar warn tint: `exclamationmark.triangle` "Gateway IP — may differ from exit IP" 11 Semibold `status.warn` |
| proxy unreachable, no fallback | error tint bar "Couldn't connect through this proxy — connection refused" + Retry (bordered) |
| all providers failed | error tint bar "Location providers unreachable (ip-api.com, ipwho.is, ipinfo.io)" + Retry |
| stale (> 10 min) | "Checked 3 h ago" turns `status.warn`; Re-check link gets a 6pt warn dot |
| Mac's own location (fleet inspector) | same card, header "This Mac · Dartmouth, Nova Scotia", hollow ring instead of flag |
### 5.5 Map pins (`Annotation` with custom content, anchor `.center`)
| kind | shape | label |
|---|---|---|
| Spoofed | 28pt circle, `accent.gradient`, 2pt white ring, `iphone` glyph 13pt white; glow = same circle `.blur(10)` at 40% behind | capsule under pin, glass/material, 11 Semibold `text.primary`, nickname |
| Pending (target set, not yet `simulating`) | 28pt circle, `surface.1` 60%, dashed ring 1.5pt `accent.text` (dash 3/3) rotating 360°/2 s | nickname + "…" |
| Reconnecting | as Spoofed but ring `status.warn`, glow off | nickname · "reconnecting" |
| Error | as Spoofed but fill `surface.1`, ring `status.error`, glyph `exclamationmark` | nickname · "error" |
| Unplugged (target remembered) | Spoofed pin at 45% opacity, dashed neutral ring | nickname · "unplugged" |
| Real (This Mac) | 18pt hollow ring, 2pt `status.neutral`, no fill | "This Mac · Dartmouth" 11 tertiary |
| Manual drag | Spoofed pin scaled 1.15 while dragging, label hidden, coordinates shown live in the header meta line | — |
| Scatter ring | `MapCircle(center: target, radius: scatter)` fill gradient 10%, stroke 1pt `accent.text` 40% | — |
| Fleet, two pins < 24pt apart | labels stack vertically (VStack in one Annotation), pins keep their spot | — |

Selected phone's pin is 1.0 scale; other phones' pins in Fleet are 0.85 scale, labels at 90% opacity.
### 5.6 Mode segmented control
`Picker("Mode", selection:) { Proxy · Manual · Off }.pickerStyle(.segmented)`, native. Off =
release. Disabled during engine starting. Manual reveals: address `TextField` (⌘F,
`MKLocalSearch` completions in a popover list of ≤ 6 rows, 13pt title + 11pt subtitle),
lat/lon mono fields (12pt, validated −90…90 / −180…180, error border on bad input), and the
hint "Drag the pin or click the map" 11 tertiary. Proxy reveals: "Last checked 2 min ago" +
Re-check. Off shows a single line "Phone reports its real GPS."
### 5.7 Scatter slider
`Slider(value:, in: 0...3000, step: 50)` with label row: "SCATTER" section label left, value
right in mono ("Exact" at 0, else "750 m"). Tick marks at 0 / 1 / 2 / 3 km via 4 tiny labels
under the track (11 tertiary). Live preview: the scatter ring on the map animates radius
(200 ms). Re-rolled offset only when Pin is pressed; the offset is stored so re-applies land on
the same spot.
### 5.8 Buttons
| kind | spec |
|---|---|
| Primary ("Pin phone here", "Locate", "Apply", "Check again") | `.buttonStyle(PrimaryGradient)`: 28 tall (`.controlSize(.large)`), radius 8, `accent.button` fill, white 13 Semibold, 1pt inner top highlight white 12%. Hover: `.brightness(0.06)`. Pressed: `.brightness(-0.08)`, scale 0.985. Disabled: 35% opacity, label `#5E6066`. Loading: label → `ProgressView` 14pt + "Locating…", width fixed. Default button (⏎) in the inspector = Pin when a target exists, else Locate. |
| Secondary ("Re-check", "Retry", "Show log", "Cancel") | `.bordered`, `.controlSize(.large)`, system material |
| Destructive ("Release", "Release all", "Quit and Release") | `.bordered` with `.tint(status.error)` label; in the quit alert `.destructive` role |
| Toolbar | `.borderless` with SF Symbol + text, system |
| Link ("Paste as list…", "Re-check ↻") | 11/13 `accent.text`, underline on hover only |
### 5.9 Toasts (content column, bottom-center, 36 tall, capsule, glass / `.regularMaterial`)
Icon 14pt leading + 13 Medium text; one visible at a time, FIFO queue, auto-dismiss 4 s
(errors persist until dismissed or superseded). Variants: info (`info.circle`, `text.secondary`),
success (`checkmark.circle` in `accent.text`, gradient dot), warning (`exclamationmark.triangle`
`status.warn`), error (`xmark.octagon` `status.error` + trailing "Retry" link). Examples:
"Pinned nat.hunterrr to London" · "onlyemspage unplugged — London will re-apply on reconnect" ·
"Proxy unreachable for glazertori — Retry".
### 5.10 Sheets
**Bulk paste** (640×520, `bg.window`): title "Paste proxy list" 22 Semibold; left `TextEditor`
(mono 12, `surface.1`, 300 wide); right preview `Table` (Phone · Proxy (masked) · Status);
mapping `Picker` "By list order / By handle" (auto-selects By handle when ≥ 1 line starts with a
known handle); footer: "Locate all after applying" `Toggle`, Cancel, **Apply** (primary, disabled
until ≥ 1 mapped line). Row states: matched (normal), unmatched handle (warn tint, "no phone
named x"), parse error (error tint, "can't read"), extra lines beyond phone count (tertiary,
"ignored"). Counter under the table: "3 of 4 phones will get a proxy".

**Quit confirmation** (`.alert`): "Quitting returns 4 phones to their real GPS." / "Only Social
GPS holds each phone's location only while it runs. Hide the window to keep them pinned."
Buttons: **Quit and Release** (destructive) · Hide Window (default) · Cancel. Only shown when
≥ 1 phone is `simulating`/`reconnecting`; otherwise quit is immediate.
### 5.11 Setup screen (full window, replaces columns)
Centered column 440 wide: `icon-mark.png` at 96 tall (the only image asset besides the OS
marks), "Python setup needed" 22 Semibold, body 13 secondary ("Only Social GPS talks to your
iPhones through pymobiledevice3, which isn't installed for /opt/homebrew/bin/python3."),
command block (`surface.1`, radius 8, mono 13, trailing Copy button, `doc.on.doc` → `checkmark`
for 1.5 s): `pip3 install pymobiledevice3` and a second line `pip3 install --break-system-packages pymobiledevice3`
under "If Homebrew Python refuses:". Primary **Check again** (probe 3 s, spinner in-button),
secondary "Choose Python…" (`NSOpenPanel`). States: no Python found (body changes, command
becomes `brew install python`), module missing, probing, probe OK → whole screen dissolves
(300 ms) into the three columns.
### 5.12 Empty state (no phones on USB, engine ready)
Sidebar: one placeholder row "No phones" 13 tertiary + hollow dashed dot. Content: header
"No iPhones on USB" 34 Bold / "Plug a phone in — it appears here within 2 seconds." 13
secondary; map at 40% opacity centered on the Mac's ring; a 6pt `status.locating` dot next to
the footer text "Watching USB…" pulses. Inspector: fleet actions disabled, Mac geo card live.
Previously known phones (from state.json) still list as Unplugged rows — this state is only
for a truly empty list.
### 5.13 Engine starting
Sidebar rows from `state.json` appear immediately, greyed 55%, subtitles "—"; footer "Starting
engine…" with a small `ProgressView`; inspector controls disabled; header pill "Starting…".
After 8 s without `hello`: footer becomes warn "Engine is slow to start · Show log". After 20 s:
error "Engine didn't start · Retry · Show log".
### 5.14 Crash-looping worker
Row: error dot, subtitle "Worker failed ×3". Header pill: Error. Inspector top banner (error tint,
radius 8): title "Worker keeps failing" 13 Semibold, last error in mono 11 (≤ 3 lines,
selectable), "Retrying in 42 s" countdown (hub's 60 s cycle), buttons **Retry now** ·
Show log. Map pin: Error style. Toast once per episode, not per attempt.

## 6. Motion spec
Global default `.animation(.smooth(duration: 0.28))`; Reduce Motion → all durations 0 except
camera (which becomes an instant jump) and the field (which freezes at frame 0).

| what | duration / curve | detail |
|---|---|---|
| Status dot colour | 200 ms easeInOut | fill cross-fade; hollow↔filled via opacity of the inner disc |
| Locating pulse | 1.2 s easeInOut, autoreverse, repeat | dot scale 1 → 1.35, opacity 1 → 0.55; a 16pt ring at 30% expands 1 → 2.2 and fades every 1.2 s |
| Spoofed glow arrive | 400 ms `.spring(response: 0.4, dampingFraction: 0.7)` | glow scale 0.6 → 1; one-shot bloom ring 1 → 1.6, opacity 0.5 → 0 over 600 ms |
| Pill text | 200 ms | `.contentTransition(.opacity)`; digits `.numericText()` |
| Header swap (selection change) | 220 ms | old header opacity → 0 (120 ms), new one `.move(edge: .bottom)` 8pt + opacity in; keyed by udid |
| Camera fly-to | < 50 km: 600 ms; else 900 ms; easeInOut | `withAnimation { camera = .region(...) }`; fleet fit = `.automatic` + 48pt insets |
| Pin drop | 350 ms `.spring(response: 0.35, dampingFraction: 0.65)` | scale 0 → 1 + y −12 → 0; label fades in 150 ms later |
| Pending ring | 2 s linear, repeat | dash rotation 360°; on `simulating` dash → solid via 250 ms opacity crossfade |
| Scatter ring | 200 ms easeOut | radius follows the slider live |
| Manual drag | none while dragging; 250 ms spring on release | pin scale 1.15 → 1; header lat/lon updates every frame |
| Toast in / out | in 350 ms `.spring(response: 0.35, dampingFraction: 0.8)` from +12 y; out 200 ms opacity | |
| Setup → app | 300 ms | setup opacity → 0 while columns scale 0.98 → 1 + opacity |
| Gradient field | 3 blobs, periods 47 s / 61 s / 53 s (coprime-ish so it never repeats visibly) | centres move on Lissajous paths (amplitude 22% of window), radius 45% of min(w,h), blur 120, opacities blue 7% / violet 8% / magenta 6%. 20 fps cap. Paused when the window is not key or occluded (`NSWindow.occlusionState`) |

Rule: nothing loops forever at full opacity. The only perpetual motion is the field (near-black)
and the pulse of a dot that is actively doing something.

## 7. Menu-bar extra
`MenuBarExtra` with the template `MenuBarIcon.png` (monochrome OS mark, 18×18 / 36×36) and
`.menuBarExtraStyle(.window)`. Popover 300 wide, `bg.window` with glass cards on macOS 26:

```
 Only Social GPS                ● engine ok
 4 phones · 3 spoofed · 1 unplugged          ← 13 Medium / 11 secondary
 ─────────────────────────────────────────
 ● nat.hunterrr         London, GB           ← rows 32 tall, dot + 13 + trailing 11 secondary
 ● onlyemspage          Dallas, US
 ○ onlyglazertori       Unplugged · will re-apply
 ● ellybellywellyyy     Berlin, DE
 ─────────────────────────────────────────
 [ Re-apply all ]   [ Release all ]          ← bordered, .small; Release all asks if ≥ 2 spoofed
 Open Only Social GPS                ⌘O      ← link row; brings the window forward
 Quit                                ⌘Q      ← goes through the same quit confirmation
```

Clicking a row opens the window on that phone. The template icon can't carry colour, so the
state lives inside the popover; the icon is the only thing in the menu bar. The extra is always
present while the app runs (the app is also in the Dock; both are required by the brief).

## 8. The wow on first launch: "the fleet arrives"
No splash, no logo. The window opens at 1280×820 on `bg.window` with the field already drifting
(t=0 frame is pre-rendered so there's no pop). Sidebar and inspector are present but empty; the
map is at world zoom, dark, no pins.

0.0 s → engine `hello`. 0.3–1.0 s → the Mac's hollow ring draws itself on the map (`trim` 0 → 1,
700 ms) while the camera flies world → Dartmouth (900 ms). 1.0–1.6 s → as `devices` arrives,
sidebar rows slide in from the leading edge, 60 ms stagger, 220 ms each; the header types in the
first phone's handle (single move+fade, not a typewriter). 1.6 s+ → if reapply-on-launch has
targets, each pin drops at its city as its worker reports `simulating` (real timing, ~2–6 s per
phone, staggered by the hardware), the row dot blooms, and after the last drop the camera re-fits
to the whole fleet (900 ms). At that instant the only gradient on screen is the pins, the
selection bar and one button. That restraint is the impression: it reads as an OS feature, not
an app.
Later launches: same sequence, rows appear instantly (no stagger); never repeated per selection.

## 9. Accessibility
### Contrast (WCAG 2.x, computed from the tokens above)
| pair | ratio | verdict |
|---|---|---|
| `text.primary` #F2F4F8 on `bg.window` #0E1118 | 17.15 | AAA |
| `text.primary` on `surface.1` #161A24 | 15.80 | AAA |
| `text.secondary` #A9B0BE on `bg.window` | 8.67 | AAA |
| `text.tertiary` #848C9C on `bg.window` / `surface.1` | 5.59 / 5.15 | AA (11pt captions ok) |
| `text.mono` #C8CEDA on `surface.1` | 11.01 | AAA |
| `accent.text` #9DA8FF on `bg.window` / `surface.1` / `accent.tint` #232042 | 8.52 / 7.85 / 6.99 | AAA |
| white on `accent.button` stops #2266E8 / #6236E6 / #9A28EA | 5.08 / 6.58 / 5.43 | AA (13pt semibold) |
| white on raw gradient #2D76FD | 4.10 | **fails** → why buttons use the darkened variant |
| `status.warn` #F5B942 on warn tint #353028 | 7.42 | AAA |
| `status.error` #FF6B6B on error tint #37252E / `bg.window` | 5.16 / 6.80 | AA / AAA |
| unplugged row text (55%) #8A8C91 on `bg.sidebar` | 5.77 | AA |
| disabled label #5E6066 on `bg.window` | 3.00 | non-text UI threshold only (intentional) |
| light: `text.primary` #14171F on #F5F6FA / #FFFFFF | 16.59 / 17.92 | AAA |
| light: `text.secondary` #545C6E on #F5F6FA | 6.21 | AA |
| light: `text.tertiary` #6E7688 on #F5F6FA | 4.22 | AA-large; captions get `text.secondary` in light mode when < 13pt |
| light: `accent.text` #4A2FD6 on #F5F6FA / violet tint #EEE8FF | 7.29 / 6.60 | AAA |
| light: `status.warn` #9A5B00 on #F5F6FA / its tint | 5.02 / 4.59 | AA |
| light: `status.error` #C42B1C on #F5F6FA / its tint | 5.24 / 4.70 | AA |

Increase Contrast: hairline 8% → 16%, `text.tertiary` → `text.secondary`, glass → solid
`surface.1`, glow removed. Reduce Transparency: every glass/material → solid token surface.
Colour is never the only signal: every dot has a distinct shape (filled / hollow / dashed / glyph)
and every pill has a word.
### Keyboard flow
Tab order: sidebar list (↑↓ select, ⏎ focuses inspector) → toolbar buttons → map (arrow keys
pan when focused, ⌘± zoom, ⏎ in Manual mode drops the pin at the map centre) → inspector: proxy
field → reveal → Locate → mode picker (←→) → [Manual: address field, lat, lon] → scatter slider
(←→ 50 m, ⌥←→ 500 m) → Pin (default, ⏎) → Release. Focus ring is the system ring (never
suppressed). Every pin, pill and row carries an `accessibilityLabel` of the form
"nat.hunterrr, spoofed, London, United Kingdom, iPhone XR"; `accessibilityValue` on the slider
reads "750 metres". Live regions: toast text and the crash-loop banner post
`AccessibilityNotification.Announcement`.

## 10. Required-state matrix
| state | sidebar | header | inspector | map | toast | menu bar |
|---|---|---|---|---|---|---|
| no phones | "No phones" placeholder | "No iPhones on USB" | fleet actions disabled | Mac ring, 40% | — | "0 phones" |
| engine starting | greyed rows | pill Starting… | disabled | Mac ring | — | "engine starting" |
| Python missing | — | setup screen replaces everything | — | — | — | "setup needed" |
| proxy unreachable | row unchanged | pill unchanged | error bar + gateway card + Retry; Pin relabelled "Pin to gateway location" | pending pin at gateway with warn ring | error toast w/ Retry | — |
| geo providers failing | unchanged | unchanged | error bar listing providers + Retry | — | error toast | — |
| unplugged while spoofed | 55%, "will re-apply" | pill Unplugged | target kept, controls enabled | pin 45% dashed | warning toast once | ○ row |
| crash-looping | error dot, "failed ×3" | pill Error | banner + Retry now + Show log + countdown | error pin | error toast once | ● red row |
| reconnecting | warn dot + countdown | pill Reconnecting · 10 s | banner (warn) "Tunnel dropped, retrying" | warn ring | — | warn row |

## 11. Risks and open decisions
- `.inspector` sizing differs between macOS 15 and 26; if it refuses 280 at 1000 wide, use
  `HSplitView` for content/inspector (same look, manual divider).
- Standard dark map land is ~`#1C1C1E`, warmer than `#0E1118`: use `.standard(emphasis: .muted)`
  plus a 12% `bg.window` multiply overlay on the map.
- Glass pill inside a solid header may halo on macOS 26 — ship the material fallback there if so.
- Flag emoji are 20pt raster (Apple Color Emoji); keep them ≤ 20pt.
