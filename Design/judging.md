# Design judging — Only Social GPS

Judge: synthesis agent. Inputs: `proposal-mission-control.md` (P1), `proposal-native-editorial.md` (P2), `proposal-immersive-map.md` (P3), read in full against `BRIEF.md` §UX and `PROTOCOL.md`.

## Independent checks performed before scoring
- Re-sampled `Resources/icon-1024.png` with Pillow (`scratchpad/judge.py`): ground `#0E1118` at (512,512), (512,60), (900,900); `#2D7DFF` at (192,480), `#764AFF` at (710,484), `#AB31FF` at (838,592), hottest magenta `#BF35FF` at (771,703). All three proposals' samples are consistent with this (P2/P3 differ by ≤ 4 units per channel from picking neighbouring pixels).
- Recomputed WCAG contrast for 20 claimed pairs across the three docs: every figure matched to two decimals (e.g. P1 white-on-`#2468E6` 5.00, P2 `#9DA8FF`-on-`#232042` 6.99, P3 `#7D869A`-on-`#171B27` 4.70, white-on-raw-blue 4.10–4.13 fails). No proposal overstated a ratio.
- Feasibility review against the build constraints (swiftc, no Xcode project, no asset catalog, `cacheDisplay` snapshots, macOS 15 target with 26 glass).

## Scores (1–10)

| Criterion | P1 Mission Control | P2 Native Editorial | P3 Immersive Map |
|---|---|---|---|
| Operator efficiency (3 jobs) | **9** — 44pt rows with city subtitle, map gets the full column, fleet counters, telemetry strip, full ⌘ set, bulk sheet with mapping preview | 8 — same skeleton, but the 148pt header repeats what the pill + geo card show and takes map height; strong context menu, ⌘2–9, route persistence, "Hide Window" on quit | 7 — 64pt rows, cards cover 656 of 1280pt so the usable map is 560 wide, inspector scrolls at 1000 wide, real-GPS phones lose their labels |
| First-impression wow | 8 — power-on sequence, lit-edge selection, bezel-framed instrument map, gradient-as-light | 7 — "Apple shipped it" restraint; the wow is the header typography, quieter than the brief's ask | **9** — full-bleed map, mark becomes the map, 20 000 km camera flight |
| Feasibility (pure SwiftUI, swiftc) | 8 — standard `List`/`Map`/`Canvas`; custom drag via `MapProxy.convert`; a `.inspector` clamping risk it already hedges | **9** — the most native control set (`Picker`, `.bordered`, `.alert`, `Table`); fewest custom views | 6 — `.blendMode(.screen)` over a hosted `MKMapView` will not composite; `.safeAreaInset` camera fitting unverified; glass blur over a live map is a constant redraw; a veil over the `Map` also dims the pins inside it; custom quit sheet needs extra AppKit plumbing; and a snapshot in which the Metal map layer renders blank would show nothing verifiable |
| Coherence with icon | 8 — measured stops, "light vs lamp" discipline; adds cyan `#4FD1FF` and green as extra hues | **9** — gradient allowed in exactly five places, direction matches the mark, no green | 8 — gradient literally as light on the map; three text tints + green + `accent.hot` widen the palette |
| Coverage of required states | 8 — 9 row / 6 pill / 5 geo-card / 7 pin states, engine dead, About; no Settings surface for the four global options | **9** — explicit state matrix §10, 8 s/20 s engine escalation, released transient, context menu, Settings; About sheet was trimmed out | 8 — all seven brief states; engine-dead not designed; About delegated to the standard panel |
| Legibility / accessibility | **9** — full contrast tables both modes incl. pills; explicit tab order; Reduce Transparency / Increase Contrast substitutions | 8 — computed; light tertiary 4.22 needs its own mitigation; 8 % hairlines | 7 — computed against an assumed tile brightness; text on glass over moving map tiles cannot be guaranteed |
| **Raw total** | **50** | **50** | 45 |
| Weighted (efficiency ×2, wow ×1.5, feasibility ×1.5, coverage ×1.5, coherence ×1, legibility ×1) | **71.0** | 70.5 | 63.5 |

## Verdict
P1 and P2 tie on the raw sum; the tie is broken on the two things the brief names first — information density for the operator and a genuine wow — where P1 leads. **Mission Control wins.** P2 is the runner-up by half a point and is the better *engineered* document; most of its ideas transfer directly because the two share the same three-column skeleton. P3 is the most exciting picture and the least buildable one; its intro and its menu-bar error mark are taken, its architecture is not.

## Grafted into DESIGN.md
From P2: the five-place gradient rule (as a discipline, not a colour); hollow neutral "Real GPS" dot and no green for phone status; the quit alert's third button (**Hide Window**, default); engine-starting escalation at 8 s / 20 s instead of a 6 s hard cap; row context menu; persisted route; `ViewThatFits` compact geo card; bulk sheet "By handle" auto-detect + "Locate all after applying" toggle; a Settings scene for the four global options; the local-time line in the geo card; the required-state matrix.
From P3: the far-out camera start and staggered pin drops in the first-launch sequence; the "!" suffix on the template menu-bar icon when a phone is in error; `Esc` to deselect back to the fleet; the 12 km fly-to distance rule; the rule that only one primary button is lit per panel; the pin label chip on `#0E1118 @ 85 %`.
Dropped from P1: cyan `status.mono` (values use a neutral mono tint), the 10pt pill text (11 semibold), the gradient ring on the segmented control (native picker), the 6 s engine cap.

## Decisions the judge adds (not in any proposal)
1. The three panes are an `HSplitView` inside a root `ZStack` with the gradient field, not `NavigationSplitView` + `.inspector`: the split view's sidebar/inspector columns draw behind-window materials that hide in-window content, so the "glass over a gradient field" the brief asks for would be invisible in exactly the two panels that should show it. SwiftUI `Material` backgrounds on our own panes blend within the window and show the field.
2. Snapshot mode renders the main window's content view **and** any attached sheet (`window.attachedSheet?.contentView`) composited at the sheet's frame, because `bulk` and `about` are sheets and a plain `cacheDisplay` of the main view would not include them.
3. If the MapKit layer captures blank in `cacheDisplay`, snapshot mode swaps the live `Map` for an `MKMapSnapshotter` image with the annotation views drawn at `snapshot.point(for:)` — specified as a fallback, tried only if the first snapshot proves it necessary.
4. No veil over the map: `.standard(emphasis: .muted)` in dark mode plus the 8pt bezel frame is how the tile tone is reconciled with `#0E1118`, without dimming the pins.
