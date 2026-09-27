import SwiftUI
import AppKit

/// Probing spinner and the setup card for a missing Python / pymobiledevice3 (DESIGN.md §8).
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var copied = false

    var body: some View {
        ZStack {
            switch model.phase {
            case .probing:
                VStack(spacing: 12) {
                    ProgressView().controlSize(.regular)
                    Text("Checking Python…").font(.osBody).foregroundStyle(p.textSecondary)
                }
            case .setup(let path, let version, let reason):
                setupCard(path: path, version: version, reason: reason)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setupCard(path: String?, version: String?, reason: String) -> some View {
        let noPython = path == nil
        let pyLabel = path ?? "/opt/homebrew/bin/python3"
        let breakFlag = pyLabel.contains("/opt/homebrew/") || pyLabel.contains("/usr/local/")
        let command = noPython ? "brew install python && pip3 install pymobiledevice3"
            : "pip3 install pymobiledevice3" + (breakFlag ? " --break-system-packages" : "")
        return GlassCard(radius: Radius.sheetCard, padding: Space.xxl) {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack { Spacer(); MarkImage(size: 96); Spacer() }
                Text("One thing to install")
                    .font(.osDisplay).tracking(-0.4).foregroundStyle(p.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(noPython
                     ? "Only Social GPS drives iPhones through pymobiledevice3, which needs Python 3. No python3 was found on this Mac."
                     : "Only Social GPS drives iPhones through pymobiledevice3, which isn't installed for \(pyLabel).")
                    .font(.osBody).foregroundStyle(p.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Text(command)
                        .font(.osMono).foregroundStyle(p.textMono)
                        .textSelection(.enabled)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Button {
                        Clipboard.copy(command)
                        withAnimation(.easeOut(duration: 0.15)) { copied = true }
                        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); withAnimation { copied = false } }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").foregroundStyle(copied ? p.ok : p.textSecondary)
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Copy command")
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(p.raised))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(p.hairline, lineWidth: 1))

                Text(noPython ? "No python3 found — install with brew install python"
                     : "Detected Python \(version ?? "?") at \(pyLabel)" + (reason.contains("timed out") || reason.contains("exited") ? " · \(reason)" : ""))
                    .font(.osCaption).foregroundStyle(p.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                HStack(spacing: Space.s) {
                    Button("Choose Python…") {
                        AppDelegate.shared.choosePython { model.choosePython($0) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button {
                        model.recheckSetup()
                    } label: {
                        Text(model.probing ? "Checking…" : "Check again").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(loading: model.probing))
                    .disabled(model.probing)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, Space.s)
            }
            .frame(width: 520 - 2 * Space.xxl)
        }
        .frame(width: 520)
    }
}
