import SwiftUI

/// Worker details disclosure at the foot of the phone panel: pid, state, restarts, last error, Restart.
struct WorkerDisclosure: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let udid: String
    @State private var expanded = false

    var body: some View {
        let rt = model.rt(udid)
        let ws = model.workerStatus[udid]
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
                if expanded { model.fetchWorkerStatus() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(p.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Worker").font(.osSection).tracking(0.6).foregroundStyle(p.textTertiary)
                    Spacer()
                    Text(rt.state.rawValue).font(.osMonoSmall).foregroundStyle(p.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Worker details")

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    KeyValueRow(key: "pid", value: ws?.pid.map(String.init) ?? "—")
                    KeyValueRow(key: "state", value: rt.state.rawValue)
                    KeyValueRow(key: "restarts", value: "\(max(rt.restarts, ws?.restarts ?? 0))")
                    if let hb = ws?.lastHeartbeat {
                        KeyValueRow(key: "heartbeat", value: Fmt.ago(Date(timeIntervalSince1970: hb), now: model.tick))
                    }
                    if let t = ws?.target ?? rt.target { KeyValueRow(key: "target", value: Fmt.coord(t.lat, t.lon)) }
                    if let a = ws?.applied ?? rt.applied { KeyValueRow(key: "applied", value: Fmt.coord(a.lat, a.lon)) }
                    if let e = ws?.lastError ?? rt.lastError {
                        KeyValueRow(key: "last error", value: e)
                    }
                    HStack(spacing: 8) {
                        Button("Restart worker") { model.restartWorker(udid) }.buttonStyle(SecondaryButtonStyle(compact: true))
                        Button("Show log") { AppDelegate.shared.showEngineLog() }.buttonStyle(TextButtonStyle())
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(.leading, 15)
                .transition(.opacity)
            }
        }
    }
}
