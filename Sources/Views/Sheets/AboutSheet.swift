import SwiftUI
import AppKit

/// About sheet (DESIGN.md §9.3): mark, name, version, engine versions, log folder, diagnostics.
struct AboutSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: Space.m) {
            MarkImage(size: 96).padding(.top, Space.s)
            VStack(spacing: 4) {
                Text("Only Social GPS").font(.osTitle).foregroundStyle(p.textPrimary)
                Text("Version \(Theme.appVersion) (\(Theme.appBuild))").font(.osMeta).foregroundStyle(p.textSecondary)
            }
            VStack(spacing: 3) {
                Text("engine \(model.engineInfo?.engineVersion ?? "—")").font(.osMono).foregroundStyle(p.textMono)
                Text("python \(model.engineInfo?.python ?? "—")").font(.osMono).foregroundStyle(p.textMono)
                Text("pymobiledevice3 \(model.engineInfo?.pymobiledevice3 ?? "—")").font(.osMono).foregroundStyle(p.textMono)
            }
            HStack(spacing: Space.l) {
                Button("Open log folder") { AppDelegate.shared.openLogFolder() }.buttonStyle(TextButtonStyle())
                Button(copied ? "Copied" : "Copy diagnostics") {
                    Clipboard.copy(model.diagnostics)
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
                }
                .buttonStyle(TextButtonStyle())
            }
            Spacer(minLength: 0)
            Button("OK") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 120)
                .keyboardShortcut(.defaultAction)
        }
        .padding(Space.xl)
        .frame(width: 360, height: 340)
        .background(p.bgWindow)
    }
}
