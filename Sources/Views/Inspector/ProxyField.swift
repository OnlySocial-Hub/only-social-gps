import SwiftUI

/// Proxy field (DESIGN.md §4.4): masked when unfocused, raw when focused or revealed; parse line under it.
struct ProxyField: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let udid: String
    @State private var raw: String = ""
    @State private var lastGood: String = ""
    @FocusState private var focused: Bool
    @State private var hover = false

    private var revealed: Bool { model.revealProxy.contains(udid) }
    private var feedback: ProxyFeedback? { model.proxyFeedback[udid] }
    private var locating: Bool { model.geoInFlight[udid] != nil }
    private var showRaw: Bool { focused || revealed || raw.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    TextField("host:port:user:pass", text: $raw)
                        .textFieldStyle(.plain)
                        .font(.osMono)
                        .foregroundStyle(p.textPrimary)
                        .focused($focused)
                        .opacity(showRaw ? 1 : 0)
                        .onSubmit { if case .valid = ProxyParser.parse(raw) { model.locate(udid) } }
                    if !showRaw {
                        Text(ProxyParser.mask(raw))
                            .font(.osMono)
                            .foregroundStyle(p.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .contentShape(Rectangle())
                            .onTapGesture { focused = true }
                            .accessibilityLabel("Proxy, masked")
                    }
                }
                .padding(.leading, 8)
                Button {
                    if revealed { model.revealProxy.remove(udid) } else { model.revealProxy.insert(udid) }
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(IconButtonStyle())
                .help(revealed ? "Hide password" : "Reveal password (this session only)")
                .padding(.trailing, 2)
            }
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(p.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(borderColor, lineWidth: 1))
            .opacity(locating ? 0.7 : 1)
            .disabled(locating)
            .onHover { hover = $0 }

            parseLine
                .frame(height: 18)
        }
        .onAppear {
            raw = model.record(udid)?.proxy ?? ""
            lastGood = raw
            if model.proxyFeedback[udid] == nil { model.refreshProxyFeedback(udid) }
            if model.focusRequest == .proxy { focused = true; model.focusRequest = nil }
        }
        .onChange(of: model.focusRequest) { _, req in
            if req == .proxy { focused = true; model.focusRequest = nil }
        }
        .onChange(of: raw) { _, new in
            if new.contains("\n") || new.contains("\r") {
                let lines = new.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if lines.count > 1 {
                    let text = new
                    raw = lastGood
                    model.toast(.info, "\(lines.count) lines pasted — ", action: "Paste as list…") { model.openBulkSheet(prefill: text) }
                    return
                }
                raw = lines.first ?? ""
                return
            }
            lastGood = new
            if model.record(udid)?.proxy != new { model.setProxy(udid, new) }
        }
        .onChange(of: model.record(udid)?.proxy ?? "") { _, new in
            if new != raw { raw = new; lastGood = new }
        }
    }

    private var borderColor: Color {
        if focused { return p.focus }
        if let f = feedback, f.kind == .invalid { return p.error }
        return p.hairline
    }

    @ViewBuilder private var parseLine: some View {
        HStack(spacing: 5) {
            if let f = feedback, !raw.isEmpty {
                switch f.kind {
                case .valid:
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(p.ok)
                    Text(f.text).font(.osCaption).foregroundStyle(p.textSecondary)
                case .http:
                    Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(p.busy)
                    Text(f.text).font(.osCaption).foregroundStyle(p.textSecondary)
                case .invalid:
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(p.error)
                    Text(f.text).font(.osCaption).foregroundStyle(p.error)
                }
            } else if locating, let stage = model.geoStage[udid] {
                ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 11, height: 11)
                Text(stage).font(.osCaption).foregroundStyle(p.textSecondary)
            } else {
                Text("host:port:user:pass · user:pass@host:port · socks5://…").font(.osCaption).foregroundStyle(p.textHint)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .animation(.easeOut(duration: 0.15), value: feedback)
    }
}
