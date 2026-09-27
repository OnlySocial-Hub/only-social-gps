import SwiftUI
import MapKit

// MARK: - Pin model

struct PinItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case spoofed
        case pending(String)      // "locating…" / "applying…"
        case reconnecting
        case error
        case unplugged
        case draft                // candidate not yet pinned (draggable in Manual)
    }
    let udid: String
    let handle: String
    let lat: Double
    let lon: Double
    let kind: Kind
    var offset: CGSize = .zero
    var scatter: Double = 0
    var id: String { udid }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    var chipText: String {
        switch kind {
        case .spoofed: handle
        case .pending(let s): "\(handle) · \(s)"
        case .reconnecting: "\(handle) · reconnecting"
        case .error: "\(handle) · error"
        case .unplugged: "\(handle) · unplugged"
        case .draft: "\(handle) · drop here"
        }
    }
    var zIndex: Double {
        switch kind { case .error: 4; case .spoofed: 3; case .pending, .draft: 2; case .reconnecting: 3; case .unplugged: 1 }
    }
}

extension AppModel {
    /// Every pin to draw (§4.1 / §5), with overlap offsets for targets within 500 m.
    var pinItems: [PinItem] {
        var items: [PinItem] = []
        for r in orderedRecords {
            let vs = viewState(for: r.udid)
            let handle = r.handleBare
            if let d = r.desired {
                switch vs {
                case .unplugged: items.append(PinItem(udid: r.udid, handle: handle, lat: d.lat, lon: d.lon, kind: .unplugged, scatter: r.scatter))
                case .locating: items.append(PinItem(udid: r.udid, handle: handle, lat: d.lat, lon: d.lon, kind: .pending("locating…"), scatter: r.scatter))
                case .applying: items.append(PinItem(udid: r.udid, handle: handle, lat: d.lat, lon: d.lon, kind: .pending("applying…"), scatter: r.scatter))
                case .spoofed: items.append(PinItem(udid: r.udid, handle: handle, lat: d.lat, lon: d.lon, kind: .spoofed, scatter: r.scatter))
                case .reconnecting: items.append(PinItem(udid: r.udid, handle: handle, lat: d.lat, lon: d.lon, kind: .reconnecting, scatter: r.scatter))
                case .error: items.append(PinItem(udid: r.udid, handle: handle, lat: d.lat, lon: d.lon, kind: .error, scatter: r.scatter))
                case .starting: items.append(PinItem(udid: r.udid, handle: handle, lat: d.lat, lon: d.lon, kind: .pending("starting…"), scatter: r.scatter))
                case .real: break
                }
            } else if route.udid == r.udid, let c = r.candidate {
                let kind: PinItem.Kind = vs == .locating ? .pending("locating…") : .draft
                items.append(PinItem(udid: r.udid, handle: handle, lat: c.lat, lon: c.lon, kind: kind, scatter: r.scatter))
            }
        }
        // deterministic ±14pt offsets for near-coincident pins
        for i in items.indices {
            var bump = 0
            for j in 0..<i {
                let a = CLLocation(latitude: items[i].lat, longitude: items[i].lon)
                let b = CLLocation(latitude: items[j].lat, longitude: items[j].lon)
                if a.distance(from: b) < 500 { bump += 1 }
            }
            if bump > 0 {
                let dx: CGFloat = bump % 2 == 1 ? 14 : -14
                let dy: CGFloat = bump >= 2 ? 14 : 0
                items[i].offset = CGSize(width: dx, height: dy)
            }
        }
        return items
    }

    var realGPSHandles: [String] {
        orderedRecords.filter { isConnected($0.udid) && viewState(for: $0.udid) == .real }.map(\.handleBare)
    }

    var macChipLabel: String {
        let city = myLocation?.city ?? "Locating…"
        let n = realGPSHandles.count
        return "This Mac · \(city) · \(n) on real GPS"
    }
}

// MARK: - Chip placement (labels of near-coincident pins fan out instead of stacking)

enum ChipPlacement: Equatable { case below, above, trailing, leading }

enum PinLayout {
    struct Item { let id: String; let point: CGPoint; let chipWidth: CGFloat }
    static let chipHeight: CGFloat = 21
    static let glyphHalf: CGFloat = 15

    static func chipWidth(for text: String) -> CGFloat { CGFloat(text.count) * 6.4 + 16 }

    /// Greedy label placement: every chip tries below → above → trailing → leading and takes the
    /// first side that hits no glyph, no chip placed so far and stays inside `size`; if every side
    /// collides, the least-overlapping one wins. Pins earlier in the list get first pick.
    static func placements(_ items: [Item], in size: CGSize? = nil) -> [String: ChipPlacement] {
        var out: [String: ChipPlacement] = [:]
        let glyphs = items.map { CGRect(x: $0.point.x - glyphHalf, y: $0.point.y - glyphHalf, width: glyphHalf * 2, height: glyphHalf * 2) }
        var placed: [CGRect] = []
        let cycle: [ChipPlacement] = [.below, .above, .trailing, .leading]
        for (i, item) in items.enumerated() {
            var best: (ChipPlacement, CGFloat)? = nil
            for placement in cycle {
                let r = rect(for: placement, item: item)
                var overlap: CGFloat = 0
                if let size {
                    if r.minX < 0 { overlap += -r.minX * r.height }
                    if r.maxX > size.width { overlap += (r.maxX - size.width) * r.height }
                    if r.minY < 0 { overlap += -r.minY * r.width }
                    if r.maxY > size.height { overlap += (r.maxY - size.height) * r.width }
                }
                for (j, g) in glyphs.enumerated() where j != i { overlap += r.intersection(g).area }
                for c in placed { overlap += r.intersection(c).area }
                if overlap == 0 { best = (placement, 0); break }
                if best == nil || overlap < best!.1 { best = (placement, overlap) }
            }
            let chosen = best?.0 ?? .below
            out[item.id] = chosen
            placed.append(rect(for: chosen, item: item))
        }
        return out
    }

    static func rect(for placement: ChipPlacement, item: Item) -> CGRect {
        let w = item.chipWidth, h = chipHeight, p = item.point
        switch placement {
        case .below: return CGRect(x: p.x - w / 2, y: p.y + glyphHalf + 2, width: w, height: h)
        case .above: return CGRect(x: p.x - w / 2, y: p.y - glyphHalf - 2 - h, width: w, height: h)
        case .trailing: return CGRect(x: p.x + glyphHalf + 4, y: p.y - h / 2, width: w, height: h)
        case .leading: return CGRect(x: p.x - glyphHalf - 4 - w, y: p.y - h / 2, width: w, height: h)
        }
    }
}

private extension CGRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}

// MARK: - Pin view (§5 annotations)

struct PinView: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: PinItem
    var selected: Bool
    var dim: Bool
    var dragging: Bool = false
    var liveText: String? = nil
    var placement: ChipPlacement = .below
    @State private var pulse = false
    @State private var spin = false

    private var scale: CGFloat { dragging ? 1.15 : (selected ? 1.15 : (dim ? 0.9 : 1)) }

    /// The 30×30 glyph frame is the annotation's whole layout box, so `anchor: .center` (live map)
    /// and `.position` (static map) both land the glyph exactly on the coordinate; the chip hangs
    /// off it as an overlay and never shifts the glyph.
    var body: some View {
        glyph
            .frame(width: 30, height: 30)
            .scaleEffect(scale)
            .overlay(alignment: overlayAlignment) { chipOverlay }
            .offset(item.offset)
            .onAppear { if !reduceMotion && !Env.isSnapshot { pulse = true; spin = true } }
            .accessibilityLabel(item.chipText)
    }

    /// The chip is aligned to the glyph box's near edge, then pushed just outside it.
    private var overlayAlignment: Alignment {
        switch placement { case .below: .top; case .above: .bottom; case .trailing: .leading; case .leading: .trailing }
    }
    private var chipOverlay: some View {
        let dx: CGFloat, dy: CGFloat
        switch placement {
        case .below: (dx, dy) = (0, 32)
        case .above: (dx, dy) = (0, -32)
        case .trailing: (dx, dy) = (34, 0)
        case .leading: (dx, dy) = (-34, 0)
        }
        return chip.offset(x: dx, y: dy)
    }

    @ViewBuilder private var glyph: some View {
        switch item.kind {
        case .spoofed:
            ZStack {
                Circle().stroke(p.violet.opacity(0.4), lineWidth: 1.5).frame(width: 30, height: 30)
                Circle().fill(p.gradientLight).frame(width: 22, height: 22)
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
                    .shadow(color: p.violet.opacity(0.55), radius: 8)
            }
        case .reconnecting:
            ZStack(alignment: .topTrailing) {
                Circle().fill(p.gradientLight).frame(width: 22, height: 22)
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
                    .opacity(0.6)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(p.busy)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 4).repeatForever(autoreverses: false), value: spin)
                    .offset(x: 4, y: -4)
            }
            .frame(width: 30, height: 30)
        case .pending:
            ZStack {
                Circle().stroke(p.busy.opacity(pulse ? 0 : 0.6), lineWidth: 1.5)
                    .frame(width: pulse ? 40 : 14, height: pulse ? 40 : 14)
                    .animation(reduceMotion ? nil : .easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
                Circle().stroke(p.busy, lineWidth: 1.5).frame(width: 22, height: 22)
                Circle().fill(p.busy).frame(width: 6, height: 6)
            }
        case .draft:
            ZStack {
                Circle().stroke(p.blueText, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 22, height: 22)
                Circle().fill(p.blueText).frame(width: 6, height: 6)
            }
        case .error:
            ZStack {
                Circle().stroke(p.error, lineWidth: 1.5).frame(width: 22, height: 22)
                Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundStyle(p.error)
            }
        case .unplugged:
            Circle().fill(p.gradientLight).frame(width: 22, height: 22)
                .overlay(Circle().stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                .opacity(0.35)
        }
    }

    private var chip: some View {
        Text(liveText ?? item.chipText)
            .font(liveText != nil ? .osMonoSmall : .osPill)
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: 0x0E1118, opacity: 0.85)))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(p.gradientLight, lineWidth: 1) }
            }
            .opacity(item.kind == .unplugged ? 0.7 : 1)
            .allowsHitTesting(false)
    }
}

/// The Mac's own location: hollow ring with crosshair ticks, no glow.
struct MacPinView: View {
    @Environment(\.palette) private var p
    let label: String
    var handles: [String] = []
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.8), lineWidth: 1.5).frame(width: 14, height: 14)
            ForEach(0..<4, id: \.self) { i in
                Rectangle().fill(.white.opacity(0.8)).frame(width: 1.5, height: 4)
                    .offset(y: -9)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
        }
        .frame(width: 24, height: 24)
        .overlay(alignment: .top) {
            Text(label)
                .font(.osPill)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: 0x0E1118, opacity: 0.85)))
                .offset(y: 26)
                .allowsHitTesting(false)
        }
        .help(handles.isEmpty ? "This Mac" : "On real GPS: " + handles.joined(separator: ", "))
        .accessibilityLabel(label)
    }
}

// MARK: - Status dot (§4.2)

struct StatusDot: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: PhoneViewState
    var size: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        ZStack {
            switch state {
            case .spoofed:
                Circle().fill(p.gradientLight)
                    .shadow(color: p.violet.opacity(0.6), radius: 6)
            case .real:
                Circle().stroke(p.off, lineWidth: 1.5)
            case .unplugged:
                Circle().stroke(p.off, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
            case .locating:
                Circle().fill(p.busy)
                    .shadow(color: p.busy.opacity(pulse ? 0.9 : 0.35), radius: 4)
                    .scaleEffect(pulse ? 1.12 : 1)
            case .applying:
                Image(systemName: "circle.lefthalf.filled").resizable().foregroundStyle(p.busy)
            case .reconnecting:
                Circle().fill(p.busy).shadow(color: p.busy.opacity(0.5), radius: 4)
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9, weight: .bold)).foregroundStyle(p.busy)
                    .offset(x: size * 0.9, y: -size * 0.7)
            case .error:
                Circle().fill(p.error)
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(p.error)
                    .offset(x: size * 0.9, y: -size * 0.7)
            case .starting:
                ProgressView().controlSize(.mini).scaleEffect(0.6)
            }
        }
        .frame(width: size, height: size)
        .onAppear { if !reduceMotion && !Env.isSnapshot { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true } } }
        .animation(.easeInOut(duration: 0.24), value: state)
    }
}
