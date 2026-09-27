import SwiftUI

/// Three slow radial lobes of the icon's hues over bg.field (DESIGN.md §3e).
struct GradientField: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var paused: Bool = false

    private struct Lobe { let color: KeyPath<Palette, Color>; let periodX: Double; let periodY: Double; let phase: Double }
    private let lobes: [Lobe] = [
        Lobe(color: \.blue, periodX: 47, periodY: 61, phase: 0),
        Lobe(color: \.violet, periodX: 61, periodY: 53, phase: 2.1),
        Lobe(color: \.magenta, periodX: 53, periodY: 47, phase: 4.2),
    ]

    var body: some View {
        let frozen = paused || reduceMotion || Env.isSnapshot
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: frozen)) { ctx in
            Canvas(rendersAsynchronously: true) { gc, size in
                let t = Env.isSnapshot ? 11.0 : ctx.date.timeIntervalSinceReferenceDate
                let radius = 0.45 * min(size.width, size.height) * 1.6
                let opacity = reduceTransparency ? 0.06 : p.fieldLobeOpacity
                for (i, lobe) in lobes.enumerated() {
                    let cx = size.width * (0.5 + 0.30 * sin(2 * .pi * t / lobe.periodX + lobe.phase) + [-0.18, 0.2, -0.05][i])
                    let cy = size.height * (0.5 + 0.22 * cos(2 * .pi * t / lobe.periodY + lobe.phase) + [-0.15, -0.1, 0.25][i])
                    let center = CGPoint(x: cx, y: cy)
                    let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
                    let color = p[keyPath: lobe.color]
                    gc.fill(Path(ellipseIn: rect),
                            with: .radialGradient(Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
                                                  center: center, startRadius: 0, endRadius: radius))
                }
            }
        }
        .background(p.bgField)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
