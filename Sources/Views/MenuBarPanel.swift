import SwiftUI
import AppKit

/// Menu-bar extra panel (DESIGN.md §7): header · phone rows · Re-apply all / Release all · open / quit.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var scheme
    @State private var confirmRelease = false

    var body: some View {
        let p = Palette.current(model.settings.theme.colorScheme ?? scheme)
        VStack(spacing: 0) {
            header(p)
            Hairline().environment(\.palette, p)
            content(p)
            Hairline().environment(\.palette, p)
            footer(p)
        }
        .frame(width: 300)
        .background(p.panel)
        .environment(\.palette, p)
        .preferredColorScheme(model.settings.theme.colorScheme)
        .confirmationDialog("Release \(model.heldCount) phones to their real GPS?", isPresented: $confirmRelease, titleVisibility: .visible) {
            Button("Release all", role: .destructive) { model.releaseAll() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func header(_ p: Palette) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Only Social GPS").font(.osRowTitle).foregroundStyle(p.textPrimary)
                    Circle().fill(engineColor(p)).frame(width: 6, height: 6)
                }
                Text(summary).font(.osCaption).foregroundStyle(p.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, Space.m)
        .frame(height: 44)
    }

    private var summary: String {
        switch model.phase {
        case .probing: return "Checking Python…"
        case .setup: return "Finish setup in the app"
        case .engineStarting: return "Starting engine…"
        case .engineDead: return "Engine stopped"
        case .ready:
            let n = model.records.count
            if n == 0 { return "No iPhones on USB" }
            var parts = ["\(n) phone\(n == 1 ? "" : "s")", "\(model.spoofedCount) spoofed"]
            if model.unpluggedCount > 0 { parts.append("\(model.unpluggedCount) unplugged") }
            if model.errorCount > 0 { parts.append("\(model.errorCount) error\(model.errorCount == 1 ? "" : "s")") }
            return parts.joined(separator: " · ")
        }
    }

    private func engineColor(_ p: Palette) -> Color {
        switch model.phase {
        case .ready: return model.errorCount > 0 ? p.busy : p.ok
        case .engineDead: return p.error
        case .engineStarting: return p.busy
        default: return p.off
        }
    }

    @ViewBuilder private func content(_ p: Palette) -> some View {
        switch model.phase {
        case .engineStarting:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Starting engine…").font(.osMeta).foregroundStyle(p.textSecondary) }
                .padding(Space.m)
        case .engineDead(let code):
            HStack(spacing: 8) {
                Circle().fill(p.error).frame(width: 6, height: 6)
                Text("Engine stopped (exit \(code))").font(.osMeta).foregroundStyle(p.error)
                Spacer()
                Button("Restart") { model.restartEngine() }.buttonStyle(TextButtonStyle())
            }
            .padding(Space.m)
        case .setup, .probing:
            Text("Finish setup in the app").font(.osMeta).foregroundStyle(p.textSecondary).padding(Space.m)
        case .ready:
            if model.orderedRecords.isEmpty {
                Text("No iPhones on USB").font(.osMeta).foregroundStyle(p.textSecondary).padding(Space.m)
            } else {
                VStack(spacing: 1) {
                    ForEach(model.orderedRecords) { r in
                        MenuBarRow(record: r) { open(.phone(r.udid)) }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
        }
    }

    private func footer(_ p: Palette) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Re-apply all") { model.reapplyAll() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.engineReady || !model.records.values.contains { $0.desired != nil })
                Button("Release all") {
                    if model.heldCount >= 2 { confirmRelease = true } else { model.releaseAll() }
                }
                .buttonStyle(SecondaryButtonStyle(destructive: true))
                .disabled(!model.engineReady || !model.records.values.contains { $0.target != nil })
            }
            HStack {
                Button("Open Only Social GPS") { open(nil) }.buttonStyle(TextButtonStyle())
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(TextButtonStyle())
            }
        }
        .padding(Space.m)
    }

    private func open(_ route: Route?) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
        AppDelegate.shared.showMainWindow()
        if let route { model.select(route) }
    }
}

struct MenuBarRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let record: PhoneRecord
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let vs = model.viewState(for: record.udid)
        Button(action: action) {
            HStack(spacing: 8) {
                StatusDot(state: vs, size: 6).frame(width: 12)
                Text(record.handle).font(.system(size: 12, weight: .medium)).foregroundStyle(p.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                StatusPill(state: vs, compact: true).fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                if hover {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(p.raised)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(vs.isUnplugged ? 0.55 : 1)
        .onHover { hover = $0 }
        .accessibilityLabel("\(record.handleBare), \(vs.accessibilityText)")
    }
}
