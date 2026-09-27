import SwiftUI

/// Toast stack (DESIGN.md §4.9): glass capsules, bottom-centre above the strip, max 3, hover pauses.
struct ToastStack: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            ForEach(model.toasts) { t in
                ToastView(toast: t)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.toasts)
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let toast: Toast
    @State private var hover = false

    private var glyph: (String, Color) {
        switch toast.kind {
        case .ok: ("checkmark.circle.fill", p.ok)
        case .busy: ("clock", p.busy)
        case .info: ("info.circle", p.blueText)
        case .error: ("xmark.octagon", p.error)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: glyph.0).font(.system(size: 14, weight: .semibold)).foregroundStyle(glyph.1)
            Text(toast.text).font(.system(size: 13, weight: .medium)).foregroundStyle(p.textPrimary).lineLimit(1)
            if let a = toast.actionTitle {
                Button(a) { toast.action?(); model.dismissToast(toast.id) }.buttonStyle(TextButtonStyle())
            }
            Button { model.dismissToast(toast.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(p.textTertiary)
            }
            .buttonStyle(.plain)
            .opacity(hover ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background { GlassBackground(shape: Capsule()) }
        .toastShadow(p)
        .onHover { hover = $0 }
        .accessibilityLabel(toast.text)
    }
}
