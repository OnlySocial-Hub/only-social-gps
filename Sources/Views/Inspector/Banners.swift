import SwiftUI

/// Inspector banners (DESIGN.md §4.11): amber for unplugged / tunnel dropped, red for crash-looping.
struct PhoneBanners: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let udid: String
    @State private var showMore = false

    private var record: PhoneRecord { model.record(udid) ?? PhoneRecord(udid: udid) }

    var body: some View {
        let vs = model.viewState(for: udid)
        let rt = model.rt(udid)
        VStack(spacing: Space.s) {
            switch vs {
            case .unplugged(let hasTarget):
                Banner(color: p.busy, tint: p.pillBusy, title: hasTarget
                       ? "Unplugged — will re-apply \(model.shortCity(for: record)) when it returns"
                       : "Unplugged — plug the phone back in over USB",
                       subtitle: hasTarget ? "The target is remembered; Locate and Pin wait for the phone." : nil)
            case .reconnecting(let n, let s):
                Banner(color: p.busy, tint: p.pillBusy, title: "Tunnel dropped — retrying in \(s) s (try \(n))",
                       subtitle: rt.message)
            case .error(let msg):
                Banner(color: p.error, tint: p.pillError,
                       title: rt.restarts > 0 ? "Worker keeps failing (\(rt.restarts) restart\(rt.restarts == 1 ? "" : "s"))" : "Worker failed",
                       subtitle: nil) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(msg).font(.osMonoSmall).foregroundStyle(p.textMono)
                            .lineLimit(showMore ? nil : 3)
                            .textSelection(.enabled)
                        HStack(spacing: 10) {
                            if msg.count > 120 {
                                Button(showMore ? "Show less" : "Show more") { showMore.toggle() }.buttonStyle(TextButtonStyle())
                            }
                            Text("Retrying automatically every 60 s").font(.osCaption).foregroundStyle(p.textTertiary)
                        }
                        HStack(spacing: 8) {
                            Button("Retry now") { model.restartWorker(udid) }.buttonStyle(SecondaryButtonStyle(compact: true))
                            Button("Show log") { AppDelegate.shared.showEngineLog() }.buttonStyle(TextButtonStyle())
                        }
                    }
                }
            default:
                EmptyView()
            }
        }
        .animation(.easeOut(duration: 0.2), value: vs)
    }
}

struct Banner<Extra: View>: View {
    @Environment(\.palette) private var p
    let color: Color
    let tint: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var extra: () -> Extra

    init(color: Color, tint: Color, title: String, subtitle: String? = nil, @ViewBuilder extra: @escaping () -> Extra) {
        self.color = color; self.tint = tint; self.title = title; self.subtitle = subtitle; self.extra = extra
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.osHeader).foregroundStyle(p.textPrimary).fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.osCaption).foregroundStyle(p.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            extra()
        }
        .padding(Space.m)
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(tint)
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(p.hairline, lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3).padding(.vertical, 10).padding(.leading, 6)
            }
        }
    }
}

extension Banner where Extra == EmptyView {
    init(color: Color, tint: Color, title: String, subtitle: String? = nil) {
        self.init(color: color, tint: tint, title: title, subtitle: subtitle) { EmptyView() }
    }
}
