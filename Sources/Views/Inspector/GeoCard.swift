import SwiftUI

/// Geo result card (DESIGN.md §4.5): empty · loading · success · stale · degraded · unreachable · providers failed.
struct GeoCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let udid: String

    private var record: PhoneRecord { model.record(udid) ?? PhoneRecord(udid: udid) }
    private var locating: Bool { model.geoInFlight[udid] != nil }
    private var failure: GeoFailure? { model.geoFailure[udid] }
    private var compact: Bool { model.windowWidth < 1100 }

    var body: some View {
        let r = record
        Group {
            if locating {
                loadingCard
            } else if let f = failure {
                failureCard(f)
            } else if let g = r.geo {
                resultCard(g, stale: !r.geoMatchesProxy, applied: model.isPinned(r) || (r.target != nil && r.target == r.candidate))
            } else {
                emptyCard
            }
        }
        .animation(.easeOut(duration: 0.2), value: locating)
    }

    // MARK: States

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe").font(.system(size: 24, weight: .light)).foregroundStyle(p.textTertiary)
            Text("Locate to see the exit IP").font(.osBody).foregroundStyle(p.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: Radius.bezel, style: .continuous)
            .stroke(p.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private var loadingCard: some View {
        GlassCard(radius: Radius.bezel, padding: Space.m) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ShimmerBar(width: 24, height: 18)
                    VStack(alignment: .leading, spacing: 6) { ShimmerBar(width: 110); ShimmerBar(width: 150, height: 7) }
                }
                ShimmerBar(width: 170)
                ShimmerBar(width: 130)
                ShimmerBar(width: 190)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 11, height: 11)
                    Text(stageText).font(.osCaption).foregroundStyle(p.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stageText: String {
        switch model.geoStage[udid] ?? "connecting" {
        case "connecting": "Connecting through proxy…"
        case "querying ip-api.com": "Querying ip-api.com…"
        case "querying ipwho.is": "Trying ipwho.is…"
        case "querying ipinfo.io": "Trying ipinfo.io…"
        case "fallback_gateway": "Looking up the gateway…"
        default: "Working…"
        }
    }

    private func resultCard(_ g: GeoResult, stale: Bool, applied: Bool) -> some View {
        GlassCard(radius: Radius.bezel, padding: Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                if compact {
                    Text("\(g.flagEmoji) \(g.cityLine) · \(g.isp ?? "")").font(.osHeader).foregroundStyle(p.textPrimary).lineLimit(1)
                    Text("\(g.ip ?? "?") · \(g.timezone ?? "")").font(.osMono).foregroundStyle(p.textMono).lineLimit(1)
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        Text(g.flagEmoji).font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(g.cityLine).font(.osHeader).foregroundStyle(p.textPrimary).lineLimit(1)
                            Text(g.regionLine).font(.osMeta).foregroundStyle(p.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    if !g.ispLine.isEmpty {
                        row("network", g.ispLine, mono: false)
                    }
                    HStack(spacing: 0) {
                        row("number", g.ip ?? "?", mono: true)
                        Spacer(minLength: 4)
                        if let ip = g.ip { CopyButton(text: ip) }
                    }
                    if let tz = g.timezone {
                        TimelineView(.periodic(from: .now, by: 60)) { _ in
                            row("clock", "\(tz) · \(Fmt.localTime(in: tz))", mono: false)
                        }
                    }
                    row("location", Fmt.coord(g.lat, g.lon), mono: true)
                }
                if g.isDegraded {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(p.busy)
                        Text(g.note ?? "Gateway IP — may differ from exit IP").font(.osCaption).foregroundStyle(p.busy)
                    }
                }
                Hairline().padding(.top, 2)
                HStack(spacing: 6) {
                    if stale {
                        Text("Proxy changed — Locate again").font(.osCaption).foregroundStyle(p.busy)
                    } else {
                        Text("via \(g.provider ?? "?") · \(String(format: "%.1f", (g.elapsedMs ?? 0) / 1000)) s")
                            .font(.osCaption).foregroundStyle(g.isStale ? p.busy : p.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if g.isStale && !stale { Circle().fill(p.busy).frame(width: 6, height: 6) }
                    Button(stale ? "Locate" : "Re-check") { model.reCheck(udid) }
                        .buttonStyle(TextButtonStyle())
                        .disabled(!model.isConnected(udid))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if applied && !stale {
                RoundedRectangle(cornerRadius: Radius.bezel, style: .continuous).stroke(p.gradientLight, lineWidth: 1).opacity(0.35)
            }
        }
        .overlay(alignment: .leading) {
            if g.isDegraded {
                RoundedRectangle(cornerRadius: 1.5).fill(p.busy).frame(width: 3).padding(.vertical, 10).padding(.leading, 5)
            }
        }
    }

    private func failureCard(_ f: GeoFailure) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            GlassCard(radius: Radius.bezel, padding: Space.m, tint: f.kind == .unreachable ? p.pillError : nil) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: f.kind == .parse ? "xmark.circle.fill" : "xmark.octagon")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(p.error)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title(f)).font(.osHeader).foregroundStyle(p.textPrimary)
                            Text(f.message).font(.osCaption).foregroundStyle(p.textSecondary).lineLimit(3)
                            if let s = f.lastStage, f.kind == .providersFailed {
                                Text("last stage: \(s)").font(.osMonoSmall).foregroundStyle(p.textTertiary)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Button("Retry") { model.locate(udid) }.buttonStyle(SecondaryButtonStyle(compact: true))
                        if f.kind == .providersFailed {
                            Text("Switch to Manual to place the pin yourself").font(.osCaption).foregroundStyle(p.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5).fill(p.error).frame(width: 3).padding(.vertical, 10).padding(.leading, 5)
            }
            if let fb = f.fallback {
                GlassCard(radius: Radius.bezel, padding: Space.m) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(fb.flagEmoji).font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(fb.cityLine).font(.osHeader).foregroundStyle(p.textPrimary)
                                Text(fb.regionLine).font(.osMeta).foregroundStyle(p.textSecondary)
                            }
                        }
                        Text("Gateway IP — may differ from exit IP").font(.osCaption).foregroundStyle(p.busy)
                        Text("\(fb.ip ?? "?") · \(fb.isp ?? "")").font(.osMonoSmall).foregroundStyle(p.textMono)
                        Button("Use gateway location anyway") { model.useGatewayLocation(udid) }
                            .buttonStyle(SecondaryButtonStyle(compact: true))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(p.busy).frame(width: 3).padding(.vertical, 10).padding(.leading, 5)
                }
                .opacity(0.7)
            }
        }
    }

    private func title(_ f: GeoFailure) -> String {
        switch f.kind {
        case .unreachable: "Proxy unreachable"
        case .providersFailed: "All 3 providers failed"
        case .parse: "Proxy didn't parse"
        }
    }

    private func row(_ symbol: String, _ text: String, mono: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(p.textTertiary).frame(width: 14)
            Text(text).font(mono ? .osMono : .osMeta).foregroundStyle(mono ? p.textMono : p.textSecondary)
                .lineLimit(1).textSelection(.enabled)
        }
    }
}

/// This-Mac variant (§4.5): hollow ring instead of a flag.
struct MacGeoCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    var body: some View {
        GlassCard(radius: Radius.bezel, padding: Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(p.textSecondary, lineWidth: 1.5).frame(width: 14, height: 14)
                        ForEach(0..<4, id: \.self) { i in
                            Rectangle().fill(p.textSecondary).frame(width: 1.5, height: 3).offset(y: -9).rotationEffect(.degrees(Double(i) * 90))
                        }
                    }
                    .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        if let m = model.myLocation {
                            Text("This Mac · \(m.cityLine)\(m.region.map { ", \(Fmt.regionAbbrev($0))" } ?? "")").font(.osHeader).foregroundStyle(p.textPrimary).lineLimit(1)
                            Text("\(m.isp ?? "?") · \(m.timezone ?? "")").font(.osMeta).foregroundStyle(p.textSecondary).lineLimit(1)
                        } else {
                            Text("This Mac").font(.osHeader).foregroundStyle(p.textPrimary)
                            Text(model.engineReady ? "Locating public IP…" : "Waiting for engine").font(.osMeta).foregroundStyle(p.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let m = model.myLocation {
                    HStack(spacing: 6) {
                        Image(systemName: "number").font(.system(size: 11)).foregroundStyle(p.textTertiary).frame(width: 14)
                        Text(m.ip ?? "?").font(.osMono).foregroundStyle(p.textMono).textSelection(.enabled)
                        Spacer(minLength: 0)
                        if let ip = m.ip { CopyButton(text: ip) }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "location").font(.system(size: 11)).foregroundStyle(p.textTertiary).frame(width: 14)
                        Text(Fmt.coord(m.lat, m.lon)).font(.osMono).foregroundStyle(p.textMono).textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
