import SwiftUI

/// Inspector for one phone (DESIGN.md §4.4–4.8, §4.11).
struct PhonePanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let udid: String

    private var record: PhoneRecord { model.record(udid) ?? PhoneRecord(udid: udid) }
    private var vs: PhoneViewState { model.viewState(for: udid) }
    private var connected: Bool { model.isConnected(udid) }
    private var locating: Bool { model.geoInFlight[udid] != nil }

    var body: some View {
        let r = record
        VStack(alignment: .leading, spacing: Space.m) {
            titleBlock(r)
            PhoneBanners(udid: udid)

            Picker("Mode", selection: Binding(get: { r.mode }, set: { model.setMode(udid, $0) })) {
                ForEach(Mode.allCases) { m in Text(m.title).tag(m) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .disabled(!model.engineReady)
            .padding(.top, Space.s)
            .accessibilityLabel("Location mode")

            Group {
                switch r.mode {
                case .proxy:
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Proxy").padding(.top, Space.s)
                        ProxyField(udid: udid)
                        GeoCard(udid: udid)
                            .padding(.top, Space.xs)
                        lastChecked(r)
                    }
                case .manual:
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Manual").padding(.top, Space.s)
                        ManualSection(udid: udid)
                    }
                case .off:
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Location").padding(.top, Space.s)
                        Text("Phone uses its real GPS").font(.osBody).foregroundStyle(p.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    SectionLabel("Scatter").padding(.top, Space.m)
                    ScatterSlider(udid: udid)
                }
                .opacity(r.mode == .off ? 0.35 : 1)
                .disabled(r.mode == .off)
            }

            actions(r)
                .padding(.top, Space.m)

            WorkerDisclosure(udid: udid)
                .padding(.top, Space.s)
        }
    }

    // MARK: Title block

    private func titleBlock(_ r: PhoneRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.handle).font(.osTitle).foregroundStyle(p.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
            }
            Text("\(r.model ?? model.device(udid)?.marketingName ?? "iPhone") · iOS \(r.ios ?? model.device(udid)?.ios ?? "?")")
                .font(.osMeta).foregroundStyle(p.textSecondary)
            HStack(spacing: 2) {
                Text(Fmt.shortUDID(udid)).font(.osMono).foregroundStyle(p.textMono).help(udid)
                CopyButton(text: udid, size: 20)
            }
            HStack(spacing: 8) {
                StatusPill(state: vs)
                if let at = r.lastAppliedAt, vs.isSpoofed || vs.isReconnecting {
                    Text("applied \(Fmt.clock(Date(timeIntervalSince1970: at)))").font(.osCaption).foregroundStyle(p.textSecondary)
                } else if case .error(let m) = vs {
                    Text(m).font(.osCaption).foregroundStyle(p.error).lineLimit(1)
                }
            }
            .padding(.top, 2)
        }
    }

    private func lastChecked(_ r: PhoneRecord) -> some View {
        Group {
            if let g = r.geo, r.geoMatchesProxy {
                HStack(spacing: 4) {
                    Text("Last checked \(Fmt.ago(g.checkedDate, now: model.tick))").font(.osCaption)
                        .foregroundStyle(g.isStale ? p.busy : p.textTertiary)
                    Spacer()
                }
            }
        }
    }

    // MARK: Actions (§4.8: one lit lamp per panel)

    @ViewBuilder private func actions(_ r: PhoneRecord) -> some View {
        let needsLocate = r.mode == .proxy && !r.geoMatchesProxy
        let hasFallback = model.geoFailure[udid]?.fallback != nil
        let pinned = model.isPinned(r)
        VStack(spacing: Space.s) {
            if needsLocate && !hasFallback {
                Button {
                    model.locate(udid)
                } label: {
                    Text(locating ? (stageText ?? "Locating…") : "Locate").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(loading: locating))
                .disabled(locating || !connected || !proxyValid(r) || !model.engineReady)
                .keyboardShortcut("l", modifiers: .command)
                .help("Geolocate this proxy's exit IP (⌘L)")
            } else {
                Button {
                    if needsLocate && hasFallback { model.useGatewayLocation(udid) }
                    model.pin(udid)
                } label: {
                    Text(pinned ? "Pinned" : (needsLocate && hasFallback ? "Pin to gateway location" : "Pin phone here")).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(loading: vs == .applying))
                .disabled(pinned || !connected || (r.candidate == nil && !hasFallback) || r.mode == .off || locating || !model.engineReady)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Hold the phone's GPS at this spot (⌘⏎)")
            }
            Button("Release") { model.release(udid) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(r.target == nil && ![.simulating, .connecting, .tunnelUp, .reconnecting, .error].contains(model.rt(udid).state))
                .help("Return this phone to its real GPS (⌘⌫)")
        }
    }

    private var stageText: String? {
        guard let s = model.geoStage[udid] else { return nil }
        switch s {
        case "connecting": return "Connecting through proxy…"
        case "querying ip-api.com": return "Querying ip-api.com…"
        case "querying ipwho.is": return "Trying ipwho.is…"
        case "querying ipinfo.io": return "Trying ipinfo.io…"
        case "fallback_gateway": return "Looking up gateway…"
        default: return s
        }
    }

    private func proxyValid(_ r: PhoneRecord) -> Bool {
        if case .valid = ProxyParser.parse(r.proxy) { return true }
        return false
    }
}
