import SwiftUI
import MapKit

/// Address search completer (MKLocalSearchCompleter) as an observable helper.
@MainActor @Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    var searching = false
    var error: String? = nil
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.pointOfInterestFilter = .excludingAll
    }

    func update(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { results = []; return }
        completer.queryFragment = t
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didUpdateResults: Void) {}
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = Array(completer.results.prefix(6))
        Task { @MainActor in self.results = r }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    func resolve(completion: MKLocalSearchCompletion?, query: String) async -> CLLocationCoordinate2D? {
        searching = true
        defer { searching = false }
        let request: MKLocalSearch.Request
        if let completion { request = MKLocalSearch.Request(completion: completion) }
        else { request = MKLocalSearch.Request(); request.naturalLanguageQuery = query }
        request.resultTypes = [.address, .pointOfInterest]
        do {
            let resp = try await MKLocalSearch(request: request).start()
            error = nil
            return resp.mapItems.first?.placemark.coordinate
        } catch {
            self.error = "No results for “\(query)”"
            return nil
        }
    }
}

/// Manual mode (DESIGN.md §4.6): address search with completions, lat/lon fields, hint.
struct ManualSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    let udid: String
    @State private var search = AddressSearch()
    @State private var query = ""
    @State private var latText = ""
    @State private var lonText = ""
    @State private var latBad = false
    @State private var lonBad = false
    @State private var showResults = false
    @FocusState private var addressFocused: Bool
    @FocusState private var latFocused: Bool
    @FocusState private var lonFocused: Bool

    private var record: PhoneRecord { model.record(udid) ?? PhoneRecord(udid: udid) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // address search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(p.textTertiary)
                TextField("Search an address or place", text: $query)
                    .textFieldStyle(.plain)
                    .font(.osBody)
                    .foregroundStyle(p.textPrimary)
                    .focused($addressFocused)
                    .onSubmit { Task { await choose(nil) } }
                if search.searching { ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 12, height: 12) }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(p.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(addressFocused ? p.focus : p.hairline, lineWidth: 1))
            .popover(isPresented: $showResults, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(search.results.enumerated()), id: \.offset) { _, r in
                        Button { Task { await choose(r) } } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(.osBody).foregroundStyle(p.textPrimary).lineLimit(1)
                                Text(r.subtitle).font(.osCaption).foregroundStyle(p.textSecondary).lineLimit(1)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 280)
                .padding(.vertical, 4)
            }
            if let e = search.error {
                Text(e).font(.osCaption).foregroundStyle(p.error)
            }

            // lat / lon
            HStack(spacing: 8) {
                coordField("Latitude", text: $latText, bad: latBad, focused: $latFocused) { commitCoords() }
                coordField("Longitude", text: $lonText, bad: lonBad, focused: $lonFocused) { commitCoords() }
            }
            HStack(spacing: 6) {
                Text("Drag the pin or click the map").font(.osCaption).foregroundStyle(p.textTertiary)
                Spacer()
                if let t = record.manualTarget, let name = model.manualNames[AppModel.geoKey(t)] {
                    Text(name).font(.osCaption).foregroundStyle(p.textSecondary).lineLimit(1)
                }
            }
        }
        .onAppear {
            syncFields()
            if model.focusRequest == .address { addressFocused = true; model.focusRequest = nil }
        }
        .onChange(of: model.focusRequest) { _, req in
            if req == .address { addressFocused = true; model.focusRequest = nil }
        }
        .onChange(of: query) { _, q in
            search.update(q)
            showResults = addressFocused && !q.isEmpty && !search.results.isEmpty
        }
        .onChange(of: search.results.count) { _, n in showResults = addressFocused && n > 0 && !query.isEmpty }
        .onChange(of: record.manualTarget) { _, _ in if !latFocused && !lonFocused { syncFields() } }
    }

    private func coordField(_ label: String, text: Binding<String>, bad: Bool, focused: FocusState<Bool>.Binding, commit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.osCaption).foregroundStyle(p.textTertiary)
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .font(.osMono)
                .foregroundStyle(p.textPrimary)
                .focused(focused)
                .onSubmit(commit)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(p.raised))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(bad ? p.error : (focused.wrappedValue ? p.focus : p.hairline), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private func syncFields() {
        if let t = record.manualTarget {
            latText = String(format: "%.5f", t.lat)
            lonText = String(format: "%.5f", t.lon)
        }
        latBad = false; lonBad = false
    }

    private func commitCoords() {
        let lat = Double(latText.trimmingCharacters(in: .whitespaces))
        let lon = Double(lonText.trimmingCharacters(in: .whitespaces))
        latBad = !(lat.map { (-90...90).contains($0) } ?? false)
        lonBad = !(lon.map { (-180...180).contains($0) } ?? false)
        guard !latBad, !lonBad, let lat, let lon else { return }
        let t = Target(lat: lat, lon: lon)
        model.setManualTarget(udid, t)
        model.flyTo(t, scatter: record.scatter)
    }

    private func choose(_ completion: MKLocalSearchCompletion?) async {
        showResults = false
        let q = completion?.title ?? query
        guard !q.isEmpty else { return }
        if let c = await search.resolve(completion: completion, query: q) {
            let t = Target(c)
            model.setManualTarget(udid, t)
            model.flyTo(t, scatter: record.scatter)
            query = completion.map { "\($0.title)\($0.subtitle.isEmpty ? "" : ", \($0.subtitle)")" } ?? q
            syncFields()
        }
    }
}
