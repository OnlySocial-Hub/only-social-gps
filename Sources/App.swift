import SwiftUI
import AppKit

@main
struct OnlySocialGPSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("Only Social GPS", id: "main") {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView().environment(model)
        }

        MenuBarExtra {
            MenuBarPanel().environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Template icon + spoofed count + "!" on errors (DESIGN.md §7).
struct MenuBarLabel: View {
    let model: AppModel
    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: Theme.menuBarIcon)
            if model.spoofedCount > 0 { Text("\(model.spoofedCount)").font(.system(size: 12, weight: .medium)).monospacedDigit() }
            if model.errorCount > 0 || model.engineDotIsError { Text("!").font(.system(size: 12, weight: .bold)) }
        }
    }
}

/// Menu commands with keyboard shortcuts (DESIGN.md §2).
struct AppCommands: Commands {
    let model: AppModel

    private var selected: String? { model.route.udid }
    private var ready: Bool { model.engineReady }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Only Social GPS") { model.showAbout = true }
        }
        CommandGroup(replacing: .newItem) { }
        CommandMenu("Phone") {
            Button("Locate") { if let u = selected { model.locate(u) } }
                .keyboardShortcut("l", modifiers: .command).disabled(selected == nil || !ready)
            Button("Pin phone here") { if let u = selected { model.pin(u) } }
                .keyboardShortcut(.return, modifiers: .command).disabled(selected == nil || !ready)
            Button("Release") { if let u = selected { model.release(u) } }
                .keyboardShortcut(.delete, modifiers: .command).disabled(selected == nil || !ready)
            Button("Re-check proxy") { if let u = selected { model.reCheck(u) } }
                .keyboardShortcut("r", modifiers: .command).disabled(selected == nil || !ready)
            Button("Restart worker") { if let u = selected { model.restartWorker(u) } }
                .disabled(selected == nil || !ready)
            Divider()
            Button("Copy UDID") { if let u = selected { Clipboard.copy(u) } }.disabled(selected == nil)
            Button("Copy proxy (masked)") { if let r = model.selectedRecord { Clipboard.copy(ProxyParser.mask(r.proxy)) } }
                .disabled(selected == nil)
        }
        CommandMenu("Fleet") {
            Button("All phones") { model.select(.fleet) }.keyboardShortcut("1", modifiers: .command)
            ForEach(Array(model.orderedRecords.prefix(8).enumerated()), id: \.element.udid) { i, r in
                Button(r.handle) { model.select(.phone(r.udid)) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 2)")), modifiers: .command)
            }
            Divider()
            Button("Locate all") { model.locateAll() }.keyboardShortcut("l", modifiers: [.command, .shift]).disabled(!ready)
            Button("Pin all") { model.pinAll() }.keyboardShortcut(.return, modifiers: [.command, .shift]).disabled(!ready)
            Button("Release all") { model.releaseAll() }.disabled(!ready)
            Button("Re-apply all") { model.reapplyAll() }.disabled(!ready)
            Divider()
            Button("Paste proxy list…") { model.openBulkSheet() }.keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Fit fleet") { model.fitFleet() }.keyboardShortcut("0", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            Button(model.inspectorShown ? "Hide Inspector" : "Show Inspector") {
                withAnimation(.easeOut(duration: 0.2)) { model.inspectorShown.toggle() }
                model.scheduleSave()
            }.keyboardShortcut("i", modifiers: [.command, .option])
            Button("Find") { model.focusRequest = model.selectedRecord?.mode == .manual ? .address : .search }
                .keyboardShortcut("f", modifiers: .command)
            Divider()
            Button("Show Engine Log") { AppDelegate.shared.showEngineLog() }
            Button("Open Log Folder") { AppDelegate.shared.openLogFolder() }
        }
    }
}

enum Clipboard {
    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
