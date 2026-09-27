import SwiftUI

/// Bulk paste sheet (DESIGN.md §9.1): editor on the left, mapping preview on the right, Apply.
struct BulkPasteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var byHandle = false
    @State private var userPickedMapping = false
    @State private var locateAfter = true

    enum Mapping: String, CaseIterable, Identifiable {
        case order = "By list order", handle = "By handle"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("Paste proxy list").font(.osTitle).foregroundStyle(p.textPrimary)
                Spacer()
                Picker("Mapping", selection: Binding(get: { byHandle ? Mapping.handle : .order },
                                                     set: { byHandle = $0 == .handle; userPickedMapping = true })) {
                    ForEach(Mapping.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }

            HStack(alignment: .top, spacing: Space.m) {
                editor
                    .frame(width: 260)
                preview
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: Space.m) {
                Toggle("Locate all after applying", isOn: $locateAfter)
                    .toggleStyle(.checkbox)
                    .font(.osBody)
                    .foregroundStyle(p.textSecondary)
                Spacer()
                Text(counterText).font(.osCaption).foregroundStyle(p.textSecondary)
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
                Button("Apply") { apply() }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(width: 120)
                    .disabled(mapped.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 720, height: 520)
        .background(p.bgWindow)
        .onAppear {
            text = model.bulkPrefill
            autoMapping()
        }
        .onChange(of: text) { _, _ in autoMapping() }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.osMono)
                .foregroundStyle(p.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(6)
            if text.isEmpty {
                Text("one proxy per line, or\nhandle, proxy / handle proxy")
                    .font(.osMono).foregroundStyle(p.textHint)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(p.raised))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(p.hairline, lineWidth: 1))
    }

    private var preview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("PHONE").frame(width: 118, alignment: .leading)
                Text("PROXY").frame(maxWidth: .infinity, alignment: .leading)
                Text("STATUS").frame(width: 84, alignment: .leading)
            }
            .font(.osSection).tracking(0.6).foregroundStyle(p.textTertiary).lineLimit(1)
            .padding(.horizontal, 10).frame(height: 28)
            Hairline()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(lines) { l in
                        HStack(spacing: 8) {
                            Text(l.udid.flatMap { model.record($0)?.handle } ?? (l.handle ?? "—"))
                                .font(.osBody).foregroundStyle(l.udid == nil ? p.textTertiary : p.textPrimary).lineLimit(1)
                                .frame(width: 118, alignment: .leading)
                            Text(compactProxy(l.proxy)).font(.osMonoSmall).foregroundStyle(p.textMono).lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(ProxyParser.mask(l.proxy))
                            statusPill(l.status).frame(width: 84, alignment: .leading)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(alignment: .leading) {
                            if case .badLine = l.status {
                                RoundedRectangle(cornerRadius: 1.5).fill(p.error).frame(width: 3).padding(.vertical, 6)
                            }
                        }
                        Hairline().opacity(0.6)
                    }
                    if lines.isEmpty {
                        Text("Paste on the left to preview the mapping").font(.osCaption).foregroundStyle(p.textTertiary)
                            .frame(maxWidth: .infinity).padding(.top, 24)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(p.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(p.hairline, lineWidth: 1))
    }

    private func statusPill(_ s: ProxyParser.BulkLine.Status) -> some View {
        let (text, color, fill): (String, Color, Color) = {
            switch s {
            case .parsed: return ("Parsed", p.ok, p.pillBlue)
            case .badLine: return ("Bad line", p.error, p.pillError)
            case .noPhone: return ("No phone", p.busy, p.pillBusy)
            case .handleNotFound: return ("Handle?", p.busy, p.pillBusy)
            case .ignored: return ("Ignored", p.textSecondary, p.pillOff)
            }
        }()
        return Text(text).font(.osPill).foregroundStyle(color)
            .padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().fill(fill))
            .help(helpText(s))
    }

    /// "host:1080 · user" for parsed lines (never the password), the raw text otherwise.
    private func compactProxy(_ raw: String) -> String {
        if case .valid(let p) = ProxyParser.parse(raw) {
            return p.hostPort + (p.username.map { " · \($0)" } ?? "")
        }
        return raw
    }

    private func helpText(_ s: ProxyParser.BulkLine.Status) -> String {
        switch s {
        case .badLine(let why): return why
        case .noPhone: return "More lines than phones in the list"
        case .handleNotFound: return "No phone with this handle"
        default: return ""
        }
    }

    // MARK: Mapping

    private var lines: [ProxyParser.BulkLine] {
        let raw = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let phones = model.orderedRecords
        var out: [ProxyParser.BulkLine] = []
        var orderIndex = 0
        for (i, line) in raw.enumerated() where !line.isEmpty {
            let (handle, proxy) = ProxyParser.splitBulkLine(line)
            var status: ProxyParser.BulkLine.Status = .parsed
            var udid: String? = nil
            if case .invalid(let why) = ProxyParser.parse(proxy) { status = .badLine(why) }
            else if case .empty = ProxyParser.parse(proxy) { status = .badLine("empty") }
            if byHandle {
                if let h = handle, let r = phones.first(where: { $0.handleBare.lowercased() == h.lowercased().replacingOccurrences(of: "@", with: "") }) {
                    udid = r.udid
                } else if case .parsed = status { status = .handleNotFound }
            } else {
                if orderIndex < phones.count { udid = phones[orderIndex].udid; orderIndex += 1 }
                else if case .parsed = status { status = .noPhone }
            }
            out.append(ProxyParser.BulkLine(id: i, raw: line, handle: handle, proxy: proxy, status: status, udid: udid))
        }
        return out
    }

    private var mapped: [(udid: String, proxy: String)] {
        lines.compactMap { l in
            if case .parsed = l.status, let u = l.udid { return (u, l.proxy) }
            return nil
        }
    }

    private var counterText: String {
        let n = Set(mapped.map(\.udid)).count
        return "\(n) of \(model.records.count) phones will get a proxy"
    }

    private func autoMapping() {
        guard !userPickedMapping else { return }
        let handles = Set(model.orderedRecords.map { $0.handleBare.lowercased() })
        let any = text.components(separatedBy: .newlines).contains { line in
            let h = ProxyParser.splitBulkLine(line).handle?.lowercased().replacingOccurrences(of: "@", with: "")
            return h.map { handles.contains($0) } ?? false
        }
        byHandle = any
    }

    private func apply() {
        var seen = Set<String>()
        var assignments: [(udid: String, proxy: String)] = []
        for m in mapped where !seen.contains(m.udid) { seen.insert(m.udid); assignments.append(m) }
        model.bulkApply(assignments, locateAfter: locateAfter)
        dismiss()
    }
}
