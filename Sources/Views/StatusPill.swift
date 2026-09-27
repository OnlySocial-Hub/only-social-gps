import SwiftUI

/// Glass background helper: Liquid Glass on 26 (inside `.background`, which captures correctly),
/// material + hairline before. Use as `.background { GlassBackground(shape: ..., tint: ...) }`.
struct GlassBackground<S: InsettableShape>: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    var tint: Color? = nil
    var stroke: Bool = true

    var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(tint ?? p.panel)
            } else if #available(macOS 26.0, *), !Env.isSnapshot {
                // Liquid Glass corrupts cacheDisplay captures, so snapshot mode takes the material path.
                shape.fill(.clear).glassEffect(.regular.tint((tint ?? p.panel).opacity(0.75)), in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill((tint ?? p.panel).opacity(0.6))
            }
            if stroke { shape.strokeBorder(p.hairline, lineWidth: 1) }
        }
    }
}

/// Status pill (DESIGN.md §4.3): capsule 20pt, 8×3 padding, 6pt dot + 6 gap, 11 semibold.
struct StatusPill: View {
    @Environment(\.palette) private var p
    let state: PhoneViewState
    var compact: Bool = false

    private var fill: Color {
        switch state {
        case .real, .unplugged: p.pillOff
        case .locating, .applying, .reconnecting: p.pillBusy
        case .spoofed: p.pillSpoofed
        case .error: p.pillError
        case .starting: p.pillBlue
        }
    }
    private var textColor: Color {
        switch state {
        case .real, .unplugged: p.textSecondary
        case .locating, .applying, .reconnecting: p.busy
        case .spoofed: p.textPrimary
        case .error: p.error
        case .starting: p.blueText
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if case .starting = state {
                ProgressView().controlSize(.mini).scaleEffect(0.55).frame(width: 10, height: 10)
            } else {
                StatusDot(state: state, size: 6)
            }
            Text(compact ? state.compactText : state.pillText)
                .font(.osPill)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: 20)
        .background { GlassBackground(shape: Capsule(), tint: fill, stroke: false) }
        .animation(.easeInOut(duration: 0.2), value: state)
        .accessibilityLabel(state.accessibilityText)
    }
}
