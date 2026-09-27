import SwiftUI
import AppKit

/// Root: preferred colour scheme → palette injection → phase switch (DESIGN.md §1).
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ThemedRoot()
            .preferredColorScheme(model.settings.theme.colorScheme)
    }
}

private struct ThemedRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette.current(model.settings.theme.colorScheme ?? scheme)
        ZStack {
            GradientField(paused: !model.windowActive || !model.windowVisible)
            switch model.phase {
            case .probing, .setup:
                SetupView()
                    .transition(.opacity)
            default:
                ConsoleView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(model.reduceMotion ? nil : .easeOut(duration: 0.3), value: phaseKey)
        .ignoresSafeArea()
        .frame(minWidth: 1000, minHeight: 700)
        .background(palette.bgWindow)
        .environment(\.palette, palette)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { model.windowWidth = $0 }
        .sheet(isPresented: Binding(get: { model.showBulkSheet }, set: { model.showBulkSheet = $0 })) {
            BulkPasteSheet().environment(model).environment(\.palette, palette)
                .preferredColorScheme(model.settings.theme.colorScheme)
        }
        .sheet(isPresented: Binding(get: { model.showAbout }, set: { model.showAbout = $0 })) {
            AboutSheet().environment(model).environment(\.palette, palette)
                .preferredColorScheme(model.settings.theme.colorScheme)
        }
        .navigationTitle("")
    }

    private var phaseKey: Int {
        switch model.phase { case .probing: 0; case .setup: 1; default: 2 }
    }
}

/// Console: header bar · HSplitView { roster · map stage · inspector }.
struct ConsoleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            ConsoleHeader()
            Hairline()
            HSplitView {
                RosterView()
                    .frame(minWidth: 220, idealWidth: 272, maxWidth: 320)
                    .frame(maxHeight: .infinity)
                    .background(PaneMaterial())
                MapStage()
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                if model.inspectorShown {
                    InspectorView()
                        .frame(minWidth: 292, idealWidth: 320, maxWidth: 360)
                        .frame(maxHeight: .infinity)
                        .background(PaneMaterial())
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .onTapGesture { if model.introActive { model.skipIntro() } }
    }
}

/// 52pt header drawn in-content (the title bar is hidden): wordmark · actions · map style · inspector.
struct ConsoleHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    private var ready: Bool { model.engineReady }
    private var iconOnly: Bool { model.windowWidth < 1120 }

    var body: some View {
        HStack(spacing: Space.s) {
            // traffic-light clearance
            Color.clear.frame(width: 70, height: 1)
            HStack(spacing: 8) {
                MarkImage(size: 22)
                Text("Only Social GPS").font(.osRowTitle).foregroundStyle(p.textPrimary)
            }
            .accessibilityHidden(true)
            Spacer(minLength: Space.l)

            HStack(spacing: 6) {
                headerButton("Locate all", "location.magnifyingglass", help: "Geolocate every phone's proxy (⌘⇧L)",
                             enabled: ready && model.records.values.contains { !$0.proxy.isEmpty }) { model.locateAll() }
                headerButton("Pin all", "mappin.and.ellipse", help: "Pin every located phone (⌘⇧⏎)",
                             enabled: model.canPinAll) { model.pinAll() }
                headerButton("Release all", "location.slash", help: "Return every phone to its real GPS", destructive: true,
                             enabled: ready && model.records.values.contains { $0.target != nil }) { model.releaseAll() }
                headerButton("Paste list", "list.clipboard", help: "Paste a proxy list (⌘⇧V)", enabled: ready) { model.openBulkSheet() }
            }

            Rectangle().fill(p.hairline).frame(width: 1, height: 20).padding(.horizontal, 6)

            Menu {
                Picker("Map style", selection: Binding(get: { model.settings.mapStyle }, set: { model.settings.mapStyle = $0; model.scheduleSave() })) {
                    ForEach(MapStyleChoice.allCases) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "map").font(.system(size: 13, weight: .medium)).foregroundStyle(p.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 28)
            .help("Map style")

            Button {
                withAnimation(.easeOut(duration: 0.2)) { model.inspectorShown.toggle() }
                model.scheduleSave()
            } label: { Image(systemName: "sidebar.trailing") }
            .buttonStyle(IconButtonStyle())
            .help("Toggle the inspector (⌥⌘I)")
        }
        .padding(.trailing, Space.m)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(PaneMaterial())
    }

    private func headerButton(_ title: String, _ symbol: String, help: String, destructive: Bool = false, enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                if !iconOnly { Text(title) }
            }
        }
        .buttonStyle(SecondaryButtonStyle(destructive: destructive, compact: true))
        .disabled(!enabled)
        .help(help)
    }
}
