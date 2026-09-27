import SwiftUI

/// Fleet inspector (DESIGN.md §4.12): counters, This-Mac card, actions, chips, engine line.
struct FleetPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            counters
            SectionLabel("This Mac").padding(.top, Space.s)
            MacGeoCard()

            if model.isEmptyFleet { EmptyFleetChecklist().padding(.top, Space.xs) }

            VStack(spacing: Space.s) {
                Button("Paste proxy list…") { model.openBulkSheet() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!model.engineReady)
                    .overlay {
                        if model.hintSweep {
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(p.gradientRing, lineWidth: 1.5)
                                .transition(.opacity)
                        }
                    }
                Button("Locate all") { model.locateAll() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!model.engineReady || !model.records.values.contains { !$0.proxy.isEmpty && model.isConnected($0.udid) })
                Button("Pin all") { model.pinAll() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.canPinAll)
                Button("Release all") { model.releaseAll() }
                    .buttonStyle(SecondaryButtonStyle(destructive: true))
                    .disabled(!model.engineReady || !model.records.values.contains { $0.target != nil })
            }
            .padding(.top, Space.m)

            if !model.orderedRecords.isEmpty {
                SectionLabel("Phones").padding(.top, Space.s)
                VStack(spacing: 2) {
                    ForEach(model.orderedRecords) { r in
                        PhoneChip(record: r)
                    }
                }
            }

            engineLine.padding(.top, Space.s)
        }
    }

    private var counters: some View {
        HStack(alignment: .top, spacing: 0) {
            counter(model.records.count, "Phones")
            counter(model.spoofedCount, "Spoofed")
            counter(model.busyOrErrorCount, "Busy/Errors", color: model.errorCount > 0 ? p.error : (model.busyOrErrorCount > 0 ? p.busy : nil))
        }
    }

    private func counter(_ n: Int, _ label: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.osCounter).foregroundStyle(color ?? p.textPrimary).contentTransition(.numericText())
            SectionLabel(label).lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var engineLine: some View {
        HStack(spacing: 6) {
            Text("Engine").font(.osMonoSmall).foregroundStyle(p.textTertiary)
            Circle().fill(engineColor).frame(width: 6, height: 6)
            Text(engineText).font(.osMonoSmall).foregroundStyle(p.textTertiary).lineLimit(2)
        }
    }

    private var engineColor: Color {
        switch model.phase {
        case .ready: return p.ok
        case .engineDead: return p.error
        case .engineStarting: return model.engineFailed ? p.error : p.busy
        default: return p.off
        }
    }

    private var engineText: String {
        switch model.phase {
        case .ready:
            let i = model.engineInfo
            return "ready · Python \(i?.python ?? "?") · pymobiledevice3 \(i?.pymobiledevice3 ?? "?") · pid \(i?.pid ?? 0)"
        case .engineStarting: return model.engineFailed ? "didn't start" : "starting…"
        case .engineDead(let c): return "stopped (exit \(c))"
        default: return "—"
        }
    }
}

/// 28pt phone chip row: dot · handle · compact pill; click selects.
struct PhoneChip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let record: PhoneRecord
    @State private var hover = false

    var body: some View {
        let vs = model.viewState(for: record.udid)
        Button { model.select(.phone(record.udid)) } label: {
            HStack(spacing: 8) {
                StatusDot(state: vs, size: 6).frame(width: 12)
                Text(record.handle).font(.system(size: 12, weight: .medium)).foregroundStyle(p.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                StatusPill(state: vs, compact: true).fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hover ? p.raised : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(vs.isUnplugged ? 0.55 : 1)
        .onHover { hover = $0 }
        .accessibilityLabel("\(record.handleBare), \(vs.accessibilityText)")
    }
}

/// Empty-fleet checklist (§8): rings fill as the first device reports paired / developer mode.
struct EmptyFleetChecklist: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    var body: some View {
        GlassCard(radius: Radius.card, padding: Space.m) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Waiting for an iPhone").font(.osHeader).foregroundStyle(p.textPrimary)
                item("USB cable connected", done: model.everHadDevices)
                item("“Trust This Computer” tapped on the phone", done: model.devices.contains { $0.paired == true })
                item("Developer Mode on (Settings › Privacy & Security)", done: model.devices.contains { $0.developerMode == true })
                Text("Phones appear here within 2 s of plugging in.").font(.osCaption).foregroundStyle(p.textTertiary).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func item(_ text: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(done ? p.ok : p.off, lineWidth: 1.5)
                if done { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(p.ok) }
            }
            .frame(width: 14, height: 14)
            Text(text).font(.osBody).foregroundStyle(done ? p.textSecondary : p.textPrimary)
        }
    }
}
