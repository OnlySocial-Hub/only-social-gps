import SwiftUI
import CoreLocation

/// Telemetry strip along the foot of the map (DESIGN.md §4.10): 28pt, glass, mono 11.
struct TelemetryStrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("ENGINE").font(.osMonoSmall).foregroundStyle(p.textTertiary)
                engineDot
                Text(engineText).font(.osMonoSmall).foregroundStyle(p.textMono).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(centreText).font(.osMonoSmall).foregroundStyle(p.textMono).lineLimit(1)
                .contentTransition(.numericText())
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Text("THIS MAC").font(.osMonoSmall).foregroundStyle(p.textTertiary)
                Text(macText).font(.osMonoSmall).foregroundStyle(p.textMono).lineLimit(1)
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: 28)
        .background { GlassBackground(shape: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)) }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var engineDot: some View {
        let color: Color = {
            if case .engineDead = model.phase { return p.error }
            if model.phase == .engineStarting { return model.engineFailed ? p.error : p.busy }
            if model.errorCount > 0 { return p.busy }
            return p.ok
        }()
        if model.phase == .engineStarting && !model.engineFailed {
            Text("◌").font(.osMonoSmall).foregroundStyle(p.busy)
        } else {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color.opacity(0.6), radius: 3)
        }
    }

    private var engineText: String {
        switch model.phase {
        case .ready: return "ready · \(model.workerCount) worker\(model.workerCount == 1 ? "" : "s")"
        case .engineStarting: return model.engineFailed ? "didn't start" : "starting…"
        case .engineDead(let code): return "stopped (exit \(code))"
        default: return "—"
        }
    }

    private var centreText: String {
        if let c = model.hoverCoordinate { return Fmt.coord(c.latitude, c.longitude) }
        if let r = model.selectedRecord, let t = r.desired ?? r.candidate { return Fmt.coord(t.lat, t.lon) }
        return "—"
    }

    private var macText: String {
        guard let m = model.myLocation else { return "locating…" }
        let place = [m.city, m.region.map { Fmt.regionAbbrev($0) }].compactMap { $0 }.joined(separator: ", ")
        return "\(place) · \(m.ip ?? "?")"
    }

}
