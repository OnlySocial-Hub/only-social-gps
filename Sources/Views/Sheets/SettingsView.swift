import SwiftUI
import AppKit

/// Settings scene (DESIGN.md §9.4): launch at login, re-apply on launch, map style, theme, Python, log.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Toggle("Re-apply locations on launch", isOn: Binding(get: { model.settings.reapplyOnLaunch }, set: { model.settings.reapplyOnLaunch = $0; model.scheduleSave() }))
            } footer: {
                Text("Phones return to their real GPS whenever the app quits; re-apply brings them back next launch.")
            }
            Section {
                Picker("Map style", selection: Binding(get: { model.settings.mapStyle }, set: { model.settings.mapStyle = $0; model.scheduleSave() })) {
                    ForEach(MapStyleChoice.allCases) { s in Text(s.title).tag(s) }
                }
                Picker("Theme", selection: Binding(get: { model.settings.theme }, set: { model.settings.theme = $0; model.scheduleSave() })) {
                    ForEach(ThemeChoice.allCases) { t in Text(t.title).tag(t) }
                }
            }
            Section {
                LabeledContent("Python") {
                    HStack(spacing: 8) {
                        Text(model.settings.pythonPath ?? model.pythonPath ?? "auto")
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                        Button("Choose…") {
                            AppDelegate.shared.choosePython { model.choosePython($0) }
                        }
                        if model.settings.pythonPath != nil {
                            Button("Auto") { model.settings.pythonPath = nil; model.scheduleSave(); model.recheckSetup() }
                        }
                    }
                }
                LabeledContent("Engine") {
                    HStack(spacing: 8) {
                        Text(engineText).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                        Button("Show engine log") { AppDelegate.shared.showEngineLog() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 320)
    }

    private var engineText: String {
        if let i = model.engineInfo { return "v\(i.engineVersion ?? "?") · pid \(i.pid ?? 0)" }
        switch model.phase {
        case .engineDead(let c): return "stopped (exit \(c))"
        case .engineStarting: return "starting…"
        default: return "—"
        }
    }
}
