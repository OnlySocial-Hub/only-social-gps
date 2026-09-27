import SwiftUI
import AppKit

/// Left pane: search · FLEET row · PHONES rows · engine footer (DESIGN.md §4.2, §4.13).
struct RosterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    @State private var renaming: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: Binding(get: { model.searchText }, set: { model.searchText = $0 }), focused: $searchFocused)
                .padding(.horizontal, Space.m)
                .padding(.top, Space.m)
                .padding(.bottom, Space.s)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    SectionLabel("Fleet").padding(.horizontal, Space.l).padding(.top, Space.xs).padding(.bottom, Space.xs)
                    FleetRow(selected: model.route == .fleet) { model.select(.fleet) }
                        .padding(.horizontal, Space.s)

                    SectionLabel("Phones").padding(.horizontal, Space.l).padding(.top, Space.m).padding(.bottom, Space.xs)
                    if model.filteredRecords.isEmpty {
                        if model.searchText.isEmpty { EmptyRosterRow(phase: model.phase) } else {
                            Text("No phones match “\(model.searchText)”").font(.osMeta).foregroundStyle(p.textTertiary)
                                .padding(.horizontal, Space.l).padding(.vertical, Space.s)
                        }
                    } else {
                        ForEach(Array(model.filteredRecords.enumerated()), id: \.element.udid) { index, r in
                            PhoneRow(record: r, index: index, selected: model.route == .phone(r.udid),
                                     renaming: Binding(get: { renaming == r.udid }, set: { renaming = $0 ? r.udid : nil }))
                                .padding(.horizontal, Space.s)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                }
                .padding(.bottom, Space.s)
            }
            .focusable()
            .focused($listFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
            .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
            .onKeyPress(.escape) { model.select(.fleet); return .handled }
            .onKeyPress(.return) { if model.route.udid != nil { model.focusRequest = .proxy; return .handled }; return .ignored }

            Hairline()
            RosterFooter()
        }
        .onChange(of: model.focusRequest) { _, req in
            if req == .search { searchFocused = true; model.focusRequest = nil }
        }
    }
}

// MARK: - Search

struct SearchField: View {
    @Environment(\.palette) private var p
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(p.textTertiary)
            TextField("Search phones", text: $text)
                .textFieldStyle(.plain)
                .font(.osBody)
                .foregroundStyle(p.textPrimary)
                .focused(focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(p.textTertiary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(p.raised))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(focused.wrappedValue ? p.focus : p.hairline, lineWidth: 1))
        .help("Filter by handle, model, city or UDID (⌘F)")
    }
}

// MARK: - Rows

/// Row chrome shared by the fleet row and phone rows: hover fill, selected fill + gradient bar.
private struct RowChrome<Content: View>: View {
    @Environment(\.palette) private var p
    var selected: Bool
    var dimmed: Bool = false
    var action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hover = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, Space.m)
                .frame(height: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(selected ? p.selected : (hover ? p.raised.opacity(0.6) : .clear))
                if selected {
                    RoundedRectangle(cornerRadius: 1).fill(p.gradientLight).frame(width: 2)
                        .padding(.vertical, 6)
                        .padding(.leading, 0)
                        .transition(.scale(scale: 0.2, anchor: .center).combined(with: .opacity))
                }
            }
        }
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous).inset(by: 2).stroke(p.focus, lineWidth: 2)
            }
        }
        .animation(.easeOut(duration: 0.16), value: selected)
        .onHover { hover = $0 }
        .opacity(dimmed ? 0.55 : 1)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
    }
}

struct FleetRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    var selected: Bool
    var action: () -> Void

    var body: some View {
        RowChrome(selected: selected, action: action) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? p.violetText : p.textSecondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All phones").font(.osRowTitle).foregroundStyle(p.textPrimary)
                    Text(subtitle).font(.osCaption).foregroundStyle(p.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityLabel("All phones, \(subtitle)")
    }

    private var subtitle: String {
        let n = model.records.count
        if n == 0 { return "No phones yet" }
        return "\(n) phone\(n == 1 ? "" : "s") · \(model.spoofedCount) spoofed"
    }
}

struct PhoneRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let record: PhoneRecord
    let index: Int
    var selected: Bool
    @Binding var renaming: Bool
    @State private var draft = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        let vs = model.viewState(for: record.udid)
        RowChrome(selected: selected, dimmed: vs.isUnplugged, action: { model.select(.phone(record.udid)) }) {
            HStack(spacing: 10) {
                StatusDot(state: vs, size: 8).frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    if renaming {
                        TextField("Nickname", text: $draft)
                            .textFieldStyle(.plain)
                            .font(.osRowTitle)
                            .foregroundStyle(p.textPrimary)
                            .focused($renameFocused)
                            .onSubmit { commitRename() }
                            .onExitCommand { renaming = false }
                            .onAppear { draft = record.nickname; renameFocused = true }
                    } else {
                        Text(record.handle).font(.osRowTitle).foregroundStyle(p.textPrimary).lineLimit(1)
                            .onTapGesture(count: 2) { renaming = true }
                    }
                    Text(model.rosterSubtitle(for: record)).font(.osCaption).foregroundStyle(p.textSecondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 4)
                trailingGlyph(vs)
            }
        }
        .contextMenu {
            Button("Locate") { model.locate(record.udid) }
            Button("Pin phone here") { model.pin(record.udid) }.disabled(record.candidate == nil)
            Button("Release") { model.release(record.udid) }.disabled(record.target == nil)
            Button("Re-check proxy") { model.reCheck(record.udid) }
            Button("Restart worker") { model.restartWorker(record.udid) }
            Divider()
            Button("Rename…") { renaming = true }
            Button("Copy UDID") { Clipboard.copy(record.udid) }
            Button("Copy proxy (masked)") { Clipboard.copy(ProxyParser.mask(record.proxy)) }
        }
        .accessibilityLabel("\(record.handleBare), \(record.model ?? "iPhone"), \(vs.accessibilityText)")
        .help(record.udid)
    }

    @ViewBuilder private func trailingGlyph(_ vs: PhoneViewState) -> some View {
        switch vs {
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(p.error)
        case .reconnecting(_, let s):
            Text("\(s) s").font(.osMonoSmall).foregroundStyle(p.busy).contentTransition(.numericText())
        case .locating, .applying:
            ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 12, height: 12)
        default:
            EmptyView()
        }
    }

    private func commitRename() {
        model.rename(record.udid, to: draft)
        renaming = false
    }
}

struct EmptyRosterRow: View {
    @Environment(\.palette) private var p
    let phase: AppModel.Phase
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: phase == .engineStarting ? "hourglass" : "cable.connector")
                .font(.system(size: 20)).foregroundStyle(p.textTertiary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                if phase == .engineStarting {
                    ForEach(0..<3, id: \.self) { _ in ShimmerBar(width: 140).padding(.vertical, 6) }
                } else {
                    Text("No iPhones on USB").font(.osRowTitle).foregroundStyle(p.textSecondary)
                    Text("Plug one in — it appears within 2 s").font(.osCaption).foregroundStyle(p.textTertiary)
                }
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
    }
}

/// Skeleton shimmer bar (§6): 1.2 s linear sweep, 18 % highlight.
struct ShimmerBar: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var width: CGFloat = 120
    var height: CGFloat = 8
    @State private var phase: CGFloat = -1
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(p.raised)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(width: width, height: height)
            .onAppear {
                guard !reduceMotion, !Env.isSnapshot else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1.2 }
            }
    }
}

// MARK: - Footer (§4.13)

struct RosterFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            dot.frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title).font(.osCaption).foregroundStyle(titleColor).lineLimit(1)
                    if let a = actionTitle {
                        Button(a) { action() }.buttonStyle(TextButtonStyle())
                    }
                }
                Text(subtitle).font(.osMonoSmall).foregroundStyle(p.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.l)
        .frame(height: 44)
        .onAppear { if !Env.isSnapshot { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true } } }
    }

    @ViewBuilder private var dot: some View {
        switch model.phase {
        case .ready:
            if model.devices.isEmpty {
                Circle().fill(p.busy).opacity(pulse ? 1 : 0.5)
            } else {
                Circle().fill(p.ok).shadow(color: p.ok.opacity(0.5), radius: 4)
            }
        case .engineStarting:
            if model.engineFailed { Circle().fill(p.error) }
            else if model.engineSlow { Circle().fill(p.busy) }
            else { ProgressView().controlSize(.mini).scaleEffect(0.5) }
        case .engineDead: Circle().fill(p.error)
        default: Circle().stroke(p.off, lineWidth: 1.5)
        }
    }

    private var title: String {
        switch model.phase {
        case .ready: return model.devices.isEmpty ? "Watching USB…" : "Engine ready"
        case .engineStarting:
            if model.engineFailed { return "Engine didn't start" }
            if model.engineSlow { return "Slow to start" }
            return "Starting engine…"
        case .engineDead: return "Engine stopped"
        case .probing: return "Checking Python…"
        case .setup: return "Setup needed"
        }
    }
    private var titleColor: Color {
        switch model.phase {
        case .engineDead: return p.error
        case .engineStarting: return model.engineFailed ? p.error : (model.engineSlow ? p.busy : p.textSecondary)
        default: return p.textSecondary
        }
    }
    private var subtitle: String {
        if let info = model.engineInfo {
            return "py \(info.python ?? "?") · pmd3 \(info.pymobiledevice3 ?? "?")"
        }
        if case .engineDead(let code) = model.phase {
            if let n = model.engineRestartIn, n > 0 { return "exit \(code) · restart in \(n) s" }
            return "exit \(code)"
        }
        return Env.useMock ? "mock engine" : (model.pythonPath ?? "python3")
    }
    private var actionTitle: String? {
        switch model.phase {
        case .engineDead: return "Restart"
        case .engineStarting: return model.engineFailed ? "Retry" : (model.engineSlow ? "Show log" : nil)
        default: return nil
        }
    }
    private func action() {
        switch model.phase {
        case .engineDead: model.restartEngine()
        case .engineStarting: if model.engineFailed { model.restartEngine() } else { AppDelegate.shared.showEngineLog() }
        default: break
        }
    }
}
