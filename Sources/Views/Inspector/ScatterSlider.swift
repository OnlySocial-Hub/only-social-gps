import SwiftUI

/// Scatter slider (DESIGN.md §4.7): 0–3000 m in 50 m steps, violet tint, mono readout, ticks, caption.
struct ScatterSlider: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let udid: String
    @State private var value: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Slider(value: $value, in: 0...3000, step: 50) { editing in
                    if editing { model.draggingScatter[udid] = value } else {
                        model.draggingScatter[udid] = nil
                        model.setScatter(udid, value)
                    }
                }
                .tint(p.violet)
                .controlSize(.small)
                .accessibilityLabel("Scatter radius")
                .accessibilityValue(Fmt.metres(value))
                Text(Fmt.metres(value))
                    .font(.osMono)
                    .foregroundStyle(p.textMono)
                    .frame(width: 48, alignment: .trailing)
                    .contentTransition(.numericText())
            }
            HStack {
                ForEach(["0", "1 km", "2 km", "3 km"], id: \.self) { t in
                    Text(t).font(.osCaption).foregroundStyle(p.textTertiary)
                    if t != "3 km" { Spacer() }
                }
            }
            .padding(.trailing, 58)
            .padding(.horizontal, 2)
            Text("Random offset so phones on one ISP don't share a pixel")
                .font(.osCaption).foregroundStyle(p.textTertiary)
                .padding(.top, 2)
        }
        .onAppear { value = model.record(udid)?.scatter ?? 0 }
        .onChange(of: model.record(udid)?.scatter ?? 0) { _, new in if new != value { value = new } }
        .onChange(of: value) { _, new in
            if model.draggingScatter[udid] != nil { model.draggingScatter[udid] = new }
            else if (model.record(udid)?.scatter ?? 0) != new { model.setScatter(udid, new) }
        }
    }
}
