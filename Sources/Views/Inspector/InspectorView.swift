import SwiftUI

/// Right pane: FleetPanel for `.fleet`, PhonePanel for `.phone(udid)`; content swaps keyed by route (§6).
struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            Group {
                switch model.route {
                case .fleet:
                    FleetPanel().id("fleet")
                case .phone(let udid):
                    if model.record(udid) != nil {
                        PhonePanel(udid: udid).id(udid)
                    } else {
                        FleetPanel().id("fleet")
                    }
                }
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.asymmetric(insertion: .offset(y: 8).combined(with: .opacity), removal: .opacity))
        }
        .animation(model.reduceMotion ? nil : .easeOut(duration: 0.22), value: model.route)
        .disabled(model.phase == .engineStarting)
        .opacity(model.phase == .engineStarting ? 0.6 : 1)
    }
}

/// Row helper: label + value used in title blocks and disclosures.
struct KeyValueRow: View {
    @Environment(\.palette) private var p
    let key: String
    let value: String
    var mono = true
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key).font(.osCaption).foregroundStyle(p.textTertiary).frame(width: 64, alignment: .leading)
            Text(value).font(mono ? .osMonoSmall : .osCaption).foregroundStyle(mono ? p.textMono : p.textSecondary)
                .lineLimit(2).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

/// Small copy button: doc.on.doc → checkmark for 1.5 s.
struct CopyButton: View {
    @Environment(\.palette) private var p
    let text: String
    var size: CGFloat = 24
    @State private var copied = false
    var body: some View {
        Button {
            Clipboard.copy(text)
            withAnimation(.easeOut(duration: 0.15)) { copied = true }
            Task { try? await Task.sleep(nanoseconds: 1_500_000_000); withAnimation { copied = false } }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(copied ? p.ok : p.textTertiary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy")
        .accessibilityLabel("Copy")
    }
}
