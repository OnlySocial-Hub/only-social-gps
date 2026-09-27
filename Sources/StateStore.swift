import SwiftUI
import MapKit
import Observation
import ServiceManagement

// MARK: - Geo failure (per phone)

struct GeoFailure: Equatable {
    enum Kind: Equatable { case unreachable, providersFailed, parse }
    var kind: Kind
    var message: String
    var fallback: GeoResult?
    var lastStage: String?
}

struct ProxyFeedback: Equatable {
    enum Kind: Equatable { case valid, http, invalid }
    var kind: Kind
    var text: String
}

// MARK: - AppModel

@MainActor @Observable
final class AppModel {
    enum Phase: Equatable {
        case probing
        case setup(pythonPath: String?, pythonVersion: String?, reason: String)
        case engineStarting
        case ready
        case engineDead(code: Int32)
    }

    // Phase & engine
    var phase: Phase = .probing
    var engineInfo: HelloResult? = nil
    var engineStartedAt: Date? = nil
    var engineSlow = false          // > 8 s without hello
    var engineFailed = false        // > 20 s without hello
    var engineExitCode: Int32? = nil
    var engineRestartIn: Int? = nil
    var pythonPath: String? = nil
    var probing = false
    var logLines: [String] = []

    // Data
    var devices: [Device] = []
    var deviceMap: [String: Device] = [:]
    var records: [String: PhoneRecord] = [:]
    var runtime: [String: PhoneRuntime] = [:]
    var settings = AppSettings()
    var route: Route = .fleet
    var myLocation: GeoResult? = nil
    var everHadDevices = false

    // UI
    var camera: MapCameraPosition = .automatic
    var toasts: [Toast] = []
    var searchText = ""
    var showBulkSheet = false
    var bulkPrefill = ""
    var showAbout = false
    var inspectorShown = true
    var tick = Date()
    var draggingScatter: [String: Double] = [:]
    var revealProxy: Set<String> = []
    var introActive = false
    var hintSweep = false
    var hoverCoordinate: CLLocationCoordinate2D? = nil
    var focusRequest: FocusRequest? = nil
    enum FocusRequest: Equatable { case search, proxy, address }
    var windowActive = true
    var windowVisible = true
    var windowWidth: CGFloat = 1280
    var snapshotMapReady = false      // set by SnapshotMapView once its tiles arrived (snapshot mode)

    // Geo
    var geoInFlight: [String: Int] = [:]        // udid -> request id
    var geoStage: [String: String] = [:]
    var geoFailure: [String: GeoFailure] = [:]
    var proxyFeedback: [String: ProxyFeedback] = [:]
    var manualNames: [String: String] = [:]     // "lat,lon" -> place name
    var pendingPinToast: Set<String> = []
    var workerStatus: [String: WorkerStatus] = [:]

    // Private machinery
    @ObservationIgnored private var engine: EngineClient? = nil
    @ObservationIgnored private var restartAttempt = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>? = nil
    @ObservationIgnored private var escalationTask: Task<Void, Never>? = nil
    @ObservationIgnored private var restartTask: Task<Void, Never>? = nil
    @ObservationIgnored private var parseTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var tickTimer: Timer? = nil
    @ObservationIgnored private var shuttingDown = false
    @ObservationIgnored private var previouslyConnected: Set<String> = []
    @ObservationIgnored private var geocoder = CLGeocoder()
    @ObservationIgnored private var geocodeQueue: [String] = []
    @ObservationIgnored private var geocodeBusy = false
    @ObservationIgnored private var farmNames: [String: String] = [:]
    @ObservationIgnored private var lastFitKey = ""
    @ObservationIgnored private var reapplyPending = false
    @ObservationIgnored private var hasSentSetAll = false
    @ObservationIgnored let isSnapshot = Env.isSnapshot
    @ObservationIgnored var reduceMotion = Env.reduceMotionOverride

    let backoff: [Double] = [1, 2, 5, 10, 20, 30]

    init() {}

    // MARK: Derived collections

    /// Every known phone (state.json ∪ engine devices), stable order by first_seen.
    var orderedRecords: [PhoneRecord] {
        records.values.sorted { a, b in
            let fa = a.firstSeen ?? deviceMap[a.udid]?.firstSeen ?? 0
            let fb = b.firstSeen ?? deviceMap[b.udid]?.firstSeen ?? 0
            if fa != fb { return fa < fb }
            return a.udid < b.udid
        }
    }

    var filteredRecords: [PhoneRecord] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return orderedRecords }
        return orderedRecords.filter { r in
            r.handle.lowercased().contains(q) || r.udid.lowercased().contains(q)
                || (r.model ?? "").lowercased().contains(q) || cityLabel(for: r).lowercased().contains(q)
        }
    }

    func isConnected(_ udid: String) -> Bool { deviceMap[udid] != nil }
    func record(_ udid: String) -> PhoneRecord? { records[udid] }
    func device(_ udid: String) -> Device? { deviceMap[udid] }
    func rt(_ udid: String) -> PhoneRuntime { runtime[udid] ?? PhoneRuntime() }

    var selectedRecord: PhoneRecord? { route.udid.flatMap { records[$0] } }

    var spoofedCount: Int { records.keys.filter { viewState(for: $0).isSpoofed }.count }
    var busyOrErrorCount: Int {
        records.keys.filter { let s = viewState(for: $0); return (s.isBusy && s != .starting) || s.isError }.count
    }
    var errorCount: Int { records.keys.filter { viewState(for: $0).isError }.count }
    var unpluggedCount: Int { records.keys.filter { !isConnected($0) }.count }
    var connectedCount: Int { devices.count }
    var workerCount: Int {
        runtime.values.filter { [.connecting, .tunnelUp, .simulating, .reconnecting, .error].contains($0.state) }.count
    }
    var anyHeld: Bool { runtime.values.contains { $0.state == .simulating || $0.state == .reconnecting } }
    var heldCount: Int { runtime.values.filter { $0.state == .simulating || $0.state == .reconnecting }.count }
    var engineReady: Bool { phase == .ready }
    var isEmptyFleet: Bool { phase == .ready && devices.isEmpty && records.isEmpty }
    var engineDotIsError: Bool { if case .engineDead = phase { return true }; return engineFailed }

    // MARK: §4.1 derived view state

    func viewState(for udid: String) -> PhoneViewState {
        guard let r = records[udid] else { return .real }
        if case .engineStarting = phase { return .starting }   // nothing is known until the first `devices` event
        if case .engineDead = phase { return .unplugged(hasTarget: r.desired != nil) }
        if !isConnected(udid) { return .unplugged(hasTarget: r.desired != nil) }
        if geoInFlight[udid] != nil { return .locating }
        let s = rt(udid)
        switch s.state {
        case .connecting, .tunnelUp: return .applying
        case .simulating: return .spoofed(city: cityLabel(for: r))
        case .reconnecting:
            let secs = max(0, Int((s.retryAt?.timeIntervalSince(tick) ?? 0).rounded(.up)))
            return .reconnecting(attempt: s.attempt ?? 1, seconds: secs)
        case .error: return .error(message: s.message ?? s.lastError ?? "worker error")
        case .idle, .released, .disconnected: return .real
        }
    }

    /// "London, GB" for Proxy mode, reverse-geocoded name for Manual, else "lat, lon".
    func cityLabel(for r: PhoneRecord) -> String {
        switch r.mode {
        case .proxy:
            if let g = r.geo {
                if let city = g.city, let cc = g.countryCode { return "\(city), \(cc)" }
                return g.cityLine
            }
        case .manual:
            if let t = r.target ?? r.manualTarget {
                if let name = manualNames[Self.geoKey(t)] { return name }
                return Fmt.coord(t.lat, t.lon, digits: 3)
            }
        case .off: break
        }
        if let t = r.target { return Fmt.coord(t.lat, t.lon, digits: 3) }
        return "—"
    }
    /// Just the city part ("London") for toasts and chips.
    func shortCity(for r: PhoneRecord) -> String {
        let l = cityLabel(for: r)
        return l.components(separatedBy: ",").first ?? l
    }
    static func geoKey(_ t: Target) -> String { String(format: "%.3f,%.3f", t.lat, t.lon) }

    func rosterSubtitle(for r: PhoneRecord) -> String {
        let model = Models.shortModel(r.model ?? deviceMap[r.udid]?.marketingName)
        let vs = viewState(for: r.udid)
        let second: String
        switch vs {
        case .spoofed: second = shortCity(for: r)
        case .starting: second = "—"
        case .unplugged: second = "Unplugged"
        case .real: second = "Real GPS"
        default: second = vs.compactText
        }
        // BRIEF §UX-1: the roster row shows nickname, model, iOS and state. The bare version keeps
        // the longest state ("Reconnecting" + countdown) on one line; the inspector spells out "iOS".
        let ios = r.ios ?? deviceMap[r.udid]?.ios
        return [model, ios, second].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Launch flow (§9.5)

    func start() {
        loadFarmNamesInBackground()
        if isSnapshot {
            if Env.useMock {
                let seed = SnapshotSeed.state()
                records = seed.records
                settings = seed.settings
                myLocation = SnapshotSeed.macLocation
            } else {
                // OSGPS_ENGINE=real snapshot: picture the live fleet through the real hub, never spoof.
                // Persisted nicknames/models are kept; every target is stripped and re-apply disabled,
                // so the hub is only ever asked for an empty desired map.
                if let s = Persistence.load() { records = s.records; settings = s.settings }
                for k in Array(records.keys) {
                    records[k]!.target = nil
                    records[k]!.manualTarget = nil
                    records[k]!.mode = .off
                }
                settings.reapplyOnLaunch = false
            }
            inspectorShown = true
            applySnapshotRoute()
            if Env.screen == "setup" {
                phase = .setup(pythonPath: "/opt/homebrew/bin/python3", pythonVersion: "3.14.6",
                               reason: "pymobiledevice3 is not installed")
                return
            }
            if Env.screen == "starting" { phase = .engineStarting; return }
            if Env.screen == "crash" { phase = .engineDead(code: 1); engineExitCode = 1; return }
            spawnEngine()
            return
        }
        if let s = Persistence.load() {
            records = s.records
            settings = s.settings
            route = s.route
            inspectorShown = s.settings.inspectorShown
        }
        if case .phone(let u) = route, records[u] == nil { route = .fleet }
        startTick()
        if Env.useMock {
            pythonPath = PythonProbe.find(override: settings.pythonPath) ?? "/usr/bin/python3"
            spawnEngine()
        } else {
            Task { await probeAndStart() }
        }
    }

    /// The farm's nickname file lives on the Desktop. For an app launched by LaunchServices the first
    /// read there blocks inside open(2) until the user answers macOS's "access your Desktop folder"
    /// dialog — so it must never run on the main thread. Names are applied whenever they arrive.
    private func loadFarmNamesInBackground() {
        Task.detached(priority: .utility) {
            let names = Persistence.farmNicknames()
            await MainActor.run { AppModel.shared.applyFarmNames(names) }
        }
    }

    func applyFarmNames(_ names: [String: String]) {
        farmNames = names
        guard !Env.useMock, !names.isEmpty else { return }
        var changed = false
        for (udid, name) in names where records[udid] != nil && records[udid]!.nickname.isEmpty {
            records[udid]!.nickname = name
            changed = true
        }
        if changed { scheduleSave() }
    }

    private func applySnapshotRoute() {
        switch Env.screen {
        case "device":
            let fallback = Env.useMock ? SnapshotSeed.udids[0] : (records.keys.sorted().first ?? SnapshotSeed.udids[0])
            let udid = Env.select ?? fallback
            route = records[udid] != nil ? .phone(udid) : (records[fallback] != nil ? .phone(fallback) : .fleet)
        case "bulk":
            route = .fleet
            bulkPrefill = SnapshotSeed.bulkSample
            showBulkSheet = true
        case "about":
            route = .fleet
            showAbout = true
        case "empty":
            records = [:]
            route = .fleet
        default:
            route = .fleet
        }
    }

    func probeAndStart() async {
        phase = .probing
        probing = true
        defer { probing = false }
        guard let py = PythonProbe.find(override: settings.pythonPath) else {
            phase = .setup(pythonPath: nil, pythonVersion: nil, reason: "No python3 found")
            return
        }
        pythonPath = py
        switch await PythonProbe.probe(python: py) {
        case .ok(let v, let pm):
            log("python \(v) with pymobiledevice3 \(pm) at \(py)")
            spawnEngine()
        case .missingPmd3(let v):
            phase = .setup(pythonPath: py, pythonVersion: v, reason: "pymobiledevice3 is not installed")
        case .noPython:
            phase = .setup(pythonPath: nil, pythonVersion: nil, reason: "No python3 found")
        case .failed(let why):
            phase = .setup(pythonPath: py, pythonVersion: nil, reason: why)
        }
    }

    /// Setup screen → "Check again".
    func recheckSetup() { Task { await probeAndStart() } }

    func choosePython(_ path: String) {
        settings.pythonPath = path
        scheduleSave()
        recheckSetup()
    }

    // MARK: Engine lifecycle

    func spawnEngine() {
        shuttingDown = false
        engineInfo = nil
        engineSlow = false
        engineFailed = false
        engineExitCode = nil
        engineRestartIn = nil
        hasSentSetAll = false
        phase = .engineStarting
        engineStartedAt = Date()
        let python = pythonPath ?? PythonProbe.find(override: settings.pythonPath) ?? "/usr/bin/python3"
        pythonPath = python
        let kind: EngineClient.Kind = Env.useMock ? .mock(scenario: Env.mockScenario, devicesFile: Env.mockFile) : .hub
        let client = EngineClient(python: python, engineDir: Persistence.engineDir, kind: kind)
        client.onEvent = { [weak self] ev in self?.handle(ev) }
        client.onExit = { [weak self] code in self?.engineExited(code) }
        client.onStderr = { [weak self] line in self?.log(line, fromEngine: true) }
        engine = client
        do {
            try client.start()
            log("engine spawned pid \(client.pid) (\(Env.useMock ? "mock \(Env.mockScenario)" : "hub"))")
        } catch {
            log("engine failed to start: \(error)")
            phase = .engineDead(code: -1)
            engineExitCode = -1
            scheduleRestart()
            return
        }
        escalationTask?.cancel()
        escalationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled, self.engineInfo == nil, self.phase == .engineStarting else { return }
            self.engineSlow = true
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled, self.engineInfo == nil, self.phase == .engineStarting else { return }
            self.engineFailed = true
        }
    }

    private func engineExited(_ code: Int32) {
        escalationTask?.cancel()
        guard !shuttingDown else { return }
        log("engine exited with \(code)")
        engineExitCode = code
        phase = .engineDead(code: code)
        for k in runtime.keys { runtime[k]?.state = .disconnected }
        geoInFlight.removeAll()
        geoStage.removeAll()
        scheduleRestart()
    }

    private func scheduleRestart() {
        restartTask?.cancel()
        let delay = backoff[min(restartAttempt, backoff.count - 1)]
        restartAttempt += 1
        engineRestartIn = Int(delay)
        restartTask = Task { [weak self] in
            var left = delay
            while left > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                left -= 1
                self?.engineRestartIn = Int(left)
            }
            guard let self, !Task.isCancelled else { return }
            self.reapplyPending = true
            self.spawnEngine()
        }
    }

    /// "Restart" from a banner: immediate.
    func restartEngine() {
        restartTask?.cancel()
        restartAttempt = 0
        engine?.terminate()
        reapplyPending = true
        spawnEngine()
    }

    func shutdownEngine() async {
        shuttingDown = true
        restartTask?.cancel()
        escalationTask?.cancel()
        await engine?.shutdown()
        engine = nil
    }

    func terminateEngineNow() {
        shuttingDown = true
        engine?.terminate()
    }

    private func handshake() async {
        guard let engine else { return }
        do {
            let r = try await engine.request("hello", ["app_version": Theme.appVersion], timeout: 15)
            engineInfo = try? JSONCoding.decode(HelloResult.self, from: r)
            restartAttempt = 0
            engineSlow = false
            engineFailed = false
            escalationTask?.cancel()
        } catch {
            log("hello failed: \(error.localizedDescription)")
        }
        if settings.reapplyOnLaunch || reapplyPending || (isSnapshot && Env.useMock) {
            await sendSetAll()
        }
        reapplyPending = false
        await refreshMyLocation()
    }

    private func sendSetAll() async {
        guard let engine else { return }
        var targets: [String: Any] = [:]
        for r in records.values {
            if let d = r.desired { targets[r.udid] = ["lat": d.lat, "lon": d.lon] }
        }
        hasSentSetAll = true
        do {
            _ = try await engine.request("set_all", ["targets": targets], timeout: 30)
            log("set_all sent for \(targets.count) phones")
        } catch {
            log("set_all failed: \(error.localizedDescription)")
        }
    }

    func refreshMyLocation() async {
        guard let engine else { return }
        if let r = try? await engine.request("my_location", timeout: 40),
           let g = try? JSONCoding.decode(GeoResult.self, from: r) {
            myLocation = g
            if route == .fleet { fitFleet(animated: !isSnapshot) }
        }
    }

    // MARK: Event handling

    private func handle(_ ev: EngineEvent) {
        switch ev {
        case .hello(let pid, let version):
            log("engine hello pid \(pid ?? 0) v\(version ?? "?")")
            Task { await handshake() }
        case .devices(let list):
            applyDevices(list)
        case .deviceState(let e):
            applyDeviceState(e)
        case .geoProgress(let id, let stage):
            if let udid = geoInFlight.first(where: { $0.value == id })?.key {
                geoStage[udid] = stage
            }
        case .log(let level, let udid, let message):
            log("[\(level)]\(udid.map { " [\($0.suffix(6))]" } ?? "") \(message)", fromEngine: true)
        }
    }

    private func applyDevices(_ list: [Device]) {
        let wasReady = phase == .ready
        devices = list
        deviceMap = Dictionary(uniqueKeysWithValues: list.map { ($0.udid, $0) })
        let now = Date().timeIntervalSince1970
        for d in list {
            var r = records[d.udid] ?? PhoneRecord(udid: d.udid)
            if records[d.udid] == nil, let name = farmNames[d.udid] { r.nickname = name }
            if r.nickname.isEmpty, let name = farmNames[d.udid] { r.nickname = name }
            r.model = d.marketingName
            r.ios = d.ios ?? r.ios
            r.lastSeenAt = now
            if r.firstSeen == nil { r.firstSeen = d.firstSeen ?? now }
            records[d.udid] = r
        }
        let connected = Set(list.map(\.udid))
        for udid in previouslyConnected.subtracting(connected) {
            guard let r = records[udid] else { continue }
            runtime[udid, default: PhoneRuntime()].state = .disconnected
            if r.desired != nil, wasReady, !runtime[udid]!.unplugToasted {
                runtime[udid]!.unplugToasted = true
                toast(.info, "@\(r.handleBare) unplugged — \(shortCity(for: r)) will re-apply on reconnect")
            }
        }
        for udid in connected.subtracting(previouslyConnected) {
            runtime[udid, default: PhoneRuntime()].unplugToasted = false
        }
        previouslyConnected = connected
        if !list.isEmpty { everHadDevices = true }
        if phase == .engineStarting {
            phase = .ready
            if !isSnapshot && !reduceMotion { playIntro() }
            if case .phone(let u) = route, let r = records[u], let t = r.desired ?? r.candidate {
                flyTo(t, scatter: r.scatter)
            }
        }
        scheduleSave()
        if route == .fleet { fitFleet(animated: wasReady && !isSnapshot) }
    }

    private func applyDeviceState(_ e: DeviceStateEvent) {
        var s = runtime[e.udid] ?? PhoneRuntime()
        let previous = s.state
        s.state = e.state
        s.target = e.target
        s.applied = e.applied
        s.message = e.message
        s.attempt = e.attempt
        s.retryAt = e.retryIn.map { Date().addingTimeInterval($0) }
        if e.state != .error { s.errorEpisodeToasted = false } else { s.lastError = e.message }
        if e.state == .connecting, previous == .error || previous == .reconnecting { s.restarts += 1 }
        runtime[e.udid] = s
        guard let r = records[e.udid] else { return }
        switch e.state {
        case .simulating:
            if let at = e.applied?.at { records[e.udid]?.lastAppliedAt = at } else { records[e.udid]?.lastAppliedAt = Date().timeIntervalSince1970 }
            if pendingPinToast.remove(e.udid) != nil {
                toast(.ok, "Pinned @\(r.handleBare) to \(shortCity(for: r))")
            }
            scheduleSave()
        case .error:
            if !s.errorEpisodeToasted {
                runtime[e.udid]?.errorEpisodeToasted = true
                toast(.error, "Worker for @\(r.handleBare) crashed — \(e.message ?? "error")", action: "Retry",
                      duration: 8) { [weak self] in self?.restartWorker(e.udid) }
            }
        default: break
        }
    }

    // MARK: Actions

    func select(_ route: Route) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.16)) { self.route = route }
        switch route {
        case .fleet: fitFleet(animated: !reduceMotion)
        case .phone(let u):
            if let r = records[u], let t = r.desired ?? r.candidate ?? r.target {
                flyTo(t, scatter: r.scatter)
            }
        }
        scheduleSave()
    }

    func selectPhone(at index: Int) {
        let list = orderedRecords
        guard index >= 0, index < list.count else { return }
        select(.phone(list[index].udid))
    }

    func moveSelection(_ delta: Int) {
        let list = filteredRecords
        guard !list.isEmpty else { return }
        switch route {
        case .fleet:
            if delta > 0 { select(.phone(list[0].udid)) }
        case .phone(let u):
            guard let i = list.firstIndex(where: { $0.udid == u }) else { select(.fleet); return }
            let n = i + delta
            if n < 0 { select(.fleet) } else if n < list.count { select(.phone(list[n].udid)) }
        }
    }

    func rename(_ udid: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        records[udid]?.nickname = trimmed
        scheduleSave()
    }

    /// Instant client-side parse feedback (no engine round trip).
    func refreshProxyFeedback(_ udid: String) {
        let text = records[udid]?.proxy ?? ""
        switch ProxyParser.parse(text) {
        case .empty: proxyFeedback[udid] = nil
        case .valid(let p): proxyFeedback[udid] = ProxyFeedback(kind: p.isHTTP ? .http : .valid, text: p.isHTTP ? "HTTP proxy — treated as \(p.scheme)://" : p.summary)
        case .invalid(let why): proxyFeedback[udid] = ProxyFeedback(kind: .invalid, text: why)
        }
    }

    func setProxy(_ udid: String, _ text: String) {
        guard records[udid] != nil else { return }
        records[udid]?.proxy = text
        scheduleSave()
        refreshProxyFeedback(udid)
        // authoritative engine parse, debounced 250 ms
        parseTasks[udid]?.cancel()
        guard let engine, engineReady, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        parseTasks[udid] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                let r = try await engine.request("parse_proxy", ["proxy": text], timeout: 10)
                guard !Task.isCancelled, self.records[udid]?.proxy == text else { return }
                if let p = try? JSONCoding.decode(ProxyInfo.self, from: r) {
                    let http = p.scheme == "http" || p.scheme == "https"
                    var summary = "\(p.scheme) · \(p.host.contains(":") ? "[\(p.host)]" : p.host):\(p.port)"
                    if let u = p.username, !u.isEmpty { summary += " · user \(u.count > 6 ? String(u.prefix(6)) + "…" : u)" }
                    self.proxyFeedback[udid] = ProxyFeedback(kind: http ? .http : .valid, text: http ? "HTTP proxy — treated as \(p.scheme)://" : summary)
                }
            } catch let e as EngineError {
                guard !Task.isCancelled, self.records[udid]?.proxy == text else { return }
                if e.code == "parse_error" { self.proxyFeedback[udid] = ProxyFeedback(kind: .invalid, text: e.message) }
            } catch {}
        }
    }

    func setMode(_ udid: String, _ mode: Mode) {
        guard var r = records[udid], r.mode != mode else { return }
        r.mode = mode
        if mode == .manual, r.manualTarget == nil {
            r.manualTarget = r.target ?? r.geo.map { Target(lat: $0.lat, lon: $0.lon) } ?? myLocation.map { Target(lat: $0.lat, lon: $0.lon) }
        }
        records[udid] = r
        if mode == .off { release(udid) } else { scheduleSave() }
        if let t = r.candidate, route.udid == udid { flyTo(t, scatter: r.scatter) }
    }

    func setManualTarget(_ udid: String, _ t: Target) {
        guard t.isValid else { return }
        records[udid]?.manualTarget = t
        scheduleSave()
        reverseGeocode(t)
    }

    func setScatter(_ udid: String, _ metres: Double) {
        records[udid]?.scatter = max(0, min(3000, metres))
        scheduleSave()
    }

    func locate(_ udid: String) {
        guard let engine, let r = records[udid], geoInFlight[udid] == nil else { return }
        let proxy = r.proxy
        guard case .valid = ProxyParser.parse(proxy) else {
            proxyFeedback[udid] = ProxyFeedback(kind: .invalid, text: "Enter a proxy first")
            return
        }
        let id = engine.makeId()
        geoInFlight[udid] = id
        geoStage[udid] = "connecting"
        geoFailure[udid] = nil
        Task { [weak self] in
            defer { self?.geoInFlight[udid] = nil; self?.geoStage[udid] = nil }
            do {
                let res = try await engine.request("geolocate_proxy", ["proxy": proxy], id: id, timeout: 60)
                let geo = try JSONCoding.decode(GeoResult.self, from: res)
                guard let self else { return }
                self.applyGeo(udid, geo, forProxy: proxy)
            } catch let e as EngineError {
                guard let self else { return }
                switch e.code {
                case "proxy_unreachable":
                    self.geoFailure[udid] = GeoFailure(kind: .unreachable, message: e.message, fallback: e.fallback, lastStage: self.geoStage[udid])
                case "parse_error":
                    self.geoFailure[udid] = GeoFailure(kind: .parse, message: e.message, fallback: nil, lastStage: nil)
                    self.proxyFeedback[udid] = ProxyFeedback(kind: .invalid, text: e.message)
                default:
                    self.geoFailure[udid] = GeoFailure(kind: .providersFailed, message: e.message, fallback: nil, lastStage: self.geoStage[udid])
                }
            } catch {
                self?.geoFailure[udid] = GeoFailure(kind: .providersFailed, message: error.localizedDescription, fallback: nil, lastStage: nil)
            }
        }
    }

    private func applyGeo(_ udid: String, _ geo: GeoResult, forProxy proxy: String) {
        guard var r = records[udid] else { return }
        r.geo = geo
        r.geoProxy = ProxyParser.canonical(proxy)
        if r.mode == .off { r.mode = .proxy }
        records[udid] = r
        scheduleSave()
        // Proxy mode follows the proxy: if the phone is held somewhere else, move it.
        if r.mode == .proxy, r.target != nil, let held = r.target, held.distance(to: Target(lat: geo.lat, lon: geo.lon)) > 100 {
            pin(udid)
        }
        if route.udid == udid { flyTo(Target(lat: geo.lat, lon: geo.lon), scatter: r.scatter) }
    }

    /// Use the degraded gateway result as if it were the exit IP.
    func useGatewayLocation(_ udid: String) {
        guard let f = geoFailure[udid]?.fallback, let r = records[udid] else { return }
        applyGeo(udid, f, forProxy: r.proxy)
        geoFailure[udid] = nil
    }

    func pin(_ udid: String) {
        guard let engine, var r = records[udid], let base = r.candidate else { return }
        r.target = base
        if r.scatter > 0 {
            r.scatterOffset = Self.rollOffset(radius: r.scatter, lat: base.lat)
        } else {
            r.scatterOffset = nil
        }
        r.pinnedScatter = r.scatter
        records[udid] = r
        scheduleSave()
        guard let d = r.desired else { return }
        pendingPinToast.insert(udid)
        if r.mode == .manual { reverseGeocode(base) }
        Task {
            do { _ = try await engine.request("set_desired", ["udid": udid, "target": ["lat": d.lat, "lon": d.lon]], timeout: 20) }
            catch { self.toast(.error, "Couldn't pin @\(r.handleBare) — \(error.localizedDescription)") }
        }
        if route.udid == udid { flyTo(d, scatter: r.scatter) }
    }

    func isPinned(_ r: PhoneRecord) -> Bool {
        guard let t = r.target, let c = r.candidate, t == c, r.pinnedScatter == r.scatter else { return false }
        let st = rt(r.udid).state
        return [.connecting, .tunnelUp, .simulating, .reconnecting].contains(st)
    }

    static func rollOffset(radius: Double, lat: Double) -> Target {
        let angle = Double.random(in: 0..<(2 * .pi))
        let dist = radius * sqrt(Double.random(in: 0...1))
        let dLat = dist * cos(angle) / 111_320
        let dLon = dist * sin(angle) / (111_320 * max(0.1, cos(lat * .pi / 180)))
        return Target(lat: dLat, lon: dLon)
    }

    func release(_ udid: String) {
        guard var r = records[udid] else { return }
        let had = r.target != nil
        r.target = nil
        r.scatterOffset = nil
        r.pinnedScatter = nil
        records[udid] = r
        scheduleSave()
        pendingPinToast.remove(udid)
        guard let engine, had || rt(udid).state != .idle else { return }
        Task { _ = try? await engine.request("release", ["udid": udid], timeout: 20) }
    }

    func reCheck(_ udid: String) { locate(udid) }

    /// Set a phone from a proxy string, end to end — used by the iPhone-Bot proxy
    /// connector. Stores the proxy, geolocates it THROUGH the proxy, applies the
    /// exit location and pins the phone there so its GPS matches the proxy. Returns
    /// the GeoResult (for the caller to show), or nil on failure.
    func setFromProxy(_ udid: String, _ proxy: String) async -> GeoResult? {
        guard let engine, records[udid] != nil, !proxy.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        setProxy(udid, proxy)
        do {
            let res = try await engine.request("geolocate_proxy", ["proxy": proxy], timeout: 45)
            let geo = try JSONCoding.decode(GeoResult.self, from: res)
            applyGeo(udid, geo, forProxy: proxy)
            pin(udid)
            return geo
        } catch { return nil }
    }

    /// The udids Only Social GPS currently sees (for the connector's status ping).
    var knownUDIDs: [String] { Array(records.keys) }

    func restartWorker(_ udid: String) {
        guard let engine else { return }
        runtime[udid]?.errorEpisodeToasted = false
        Task { _ = try? await engine.request("worker_restart", ["udid": udid], timeout: 20) }
    }

    func fetchWorkerStatus() {
        guard let engine, engineReady else { return }
        Task { [weak self] in
            guard let r = try? await engine.request("worker_status", timeout: 10),
                  let workers = r["workers"] as? [String: Any] else { return }
            var out: [String: WorkerStatus] = [:]
            for (udid, v) in workers {
                if let d = v as? [String: Any], let ws = try? JSONCoding.decode(WorkerStatus.self, from: d) { out[udid] = ws }
            }
            self?.workerStatus = out
        }
    }

    func locateAll() {
        for r in orderedRecords where isConnected(r.udid) && !r.proxy.isEmpty { locate(r.udid) }
    }

    /// Pin every connected phone that has somewhere to go (re-sending an identical target is harmless
    /// and doubles as "re-apply" for a phone stuck in error).
    func pinAll() {
        for r in orderedRecords where isConnected(r.udid) && r.candidate != nil { pin(r.udid) }
    }
    var canPinAll: Bool { engineReady && records.values.contains { $0.candidate != nil && isConnected($0.udid) } }

    func reapplyAll() {
        Task { await sendSetAll() }
    }

    func releaseAll() {
        for k in records.keys {
            records[k]?.target = nil
            records[k]?.scatterOffset = nil
            records[k]?.pinnedScatter = nil
        }
        pendingPinToast.removeAll()
        scheduleSave()
        guard let engine else { return }
        Task { _ = try? await engine.request("release_all", timeout: 30) }
    }

    /// Bulk sheet Apply: assign proxies, optionally locate.
    func bulkApply(_ assignments: [(udid: String, proxy: String)], locateAfter: Bool) {
        for a in assignments {
            guard records[a.udid] != nil else { continue }
            records[a.udid]?.proxy = a.proxy
            if records[a.udid]?.mode == .off { records[a.udid]?.mode = .proxy }
            setProxy(a.udid, a.proxy)
        }
        scheduleSave()
        toast(.ok, "\(assignments.count) prox\(assignments.count == 1 ? "y" : "ies") assigned")
        if locateAfter { for a in assignments { locate(a.udid) } }
    }

    func openBulkSheet(prefill: String = "") {
        bulkPrefill = prefill
        showBulkSheet = true
    }

    // MARK: Camera (§5)

    func flyTo(_ t: Target, scatter: Double) {
        let distance = max(12_000, scatter * 8)
        let cam = MapCamera(centerCoordinate: t.coordinate, distance: distance, heading: 0, pitch: 0)
        if reduceMotion || isSnapshot {
            camera = .camera(cam)
        } else {
            withAnimation(.easeInOut(duration: 0.9)) { camera = .camera(cam) }
        }
    }

    func fitFleet(animated: Bool = true) {
        var coords: [CLLocationCoordinate2D] = []
        for r in records.values {
            if let d = r.desired, rt(r.udid).state != .idle || !isConnected(r.udid) || d.isValid { coords.append(d.coordinate) }
        }
        if let m = myLocation { coords.append(m.coordinate) }
        let position: MapCameraPosition
        if coords.isEmpty {
            position = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 44.67, longitude: -63.58), distance: 40_000, heading: 0, pitch: 0))
        } else if coords.count == 1 {
            position = .camera(MapCamera(centerCoordinate: coords[0], distance: 40_000, heading: 0, pitch: 0))
        } else {
            let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
            let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
            let span = MKCoordinateSpan(latitudeDelta: max(0.5, (maxLat - minLat) * 1.5),
                                        longitudeDelta: max(0.5, (maxLon - minLon) * 1.5))
            position = .region(MKCoordinateRegion(center: center, span: span))
        }
        let key = "\(coords.count)-\(coords.map { "\($0.latitude),\($0.longitude)" }.joined())"
        guard key != lastFitKey || route == .fleet else { return }
        lastFitKey = key
        if animated && !reduceMotion && !isSnapshot {
            withAnimation(.easeInOut(duration: 0.7)) { camera = position }
        } else {
            camera = position
        }
    }

    // MARK: Reverse geocoding for manual pins

    func reverseGeocode(_ t: Target) {
        let key = Self.geoKey(t)
        guard manualNames[key] == nil, !geocodeQueue.contains(key), !isSnapshot else { return }
        geocodeQueue.append(key)
        pumpGeocode()
    }

    private func pumpGeocode() {
        guard !geocodeBusy, let key = geocodeQueue.first else { return }
        geocodeBusy = true
        let parts = key.split(separator: ",").compactMap { Double($0) }
        let loc = CLLocation(latitude: parts[0], longitude: parts[1])
        geocoder.reverseGeocodeLocation(loc) { [weak self] marks, _ in
            Task { @MainActor in
                guard let self else { return }
                self.geocodeQueue.removeFirst()
                self.geocodeBusy = false
                if let m = marks?.first {
                    let name = [m.locality ?? m.subAdministrativeArea ?? m.administrativeArea, m.isoCountryCode]
                        .compactMap { $0 }.joined(separator: ", ")
                    self.manualNames[key] = name.isEmpty ? Fmt.coord(parts[0], parts[1], digits: 3) : name
                } else {
                    self.manualNames[key] = Fmt.coord(parts[0], parts[1], digits: 3)
                }
                self.pumpGeocode()
            }
        }
    }

    // MARK: Toasts (§4.9)

    func toast(_ kind: Toast.Kind, _ text: String, action: String? = nil, duration: Double = 4, handler: (() -> Void)? = nil) {
        let t = Toast(kind: kind, text: text, actionTitle: action, action: handler, duration: duration)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toasts.append(t)
            if toasts.count > 3 { toasts.removeFirst(toasts.count - 3) }
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            self?.dismissToast(t.id)
        }
    }

    func dismissToast(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.2)) { toasts.removeAll { $0.id == id } }
    }

    // MARK: Persistence

    func scheduleSave() {
        guard !isSnapshot else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard !isSnapshot else { return }
        var s = PersistedState()
        s.records = records
        var st = settings
        st.inspectorShown = inspectorShown
        s.settings = st
        s.route = route
        Persistence.save(s)
    }

    func setLaunchAtLogin(_ on: Bool) {
        settings.launchAtLogin = on
        scheduleSave()
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            log("launch at login: \(error.localizedDescription)")
            toast(.error, "Launch at login: \(error.localizedDescription)")
        }
    }

    // MARK: Tick, intro, logs

    private func startTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick = Date() }
        }
    }

    private func playIntro() {
        introActive = true
        let hasTargets = records.values.contains { $0.desired != nil }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            self?.introActive = false
            if !hasTargets {
                self?.hintSweep = true
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.hintSweep = false
            }
        }
    }

    func skipIntro() { introActive = false }

    func log(_ line: String, fromEngine: Bool = false) {
        if !fromEngine { AppLog.write(line) }
        logLines.append(line)
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
    }

    var diagnostics: String {
        var s = "Only Social GPS \(Theme.appVersion) (\(Theme.appBuild))\n"
        s += "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        s += "python: \(pythonPath ?? "?") \(engineInfo?.python ?? "")\n"
        s += "engine: \(engineInfo?.engineVersion ?? "?") pid \(engineInfo?.pid ?? 0) pymobiledevice3 \(engineInfo?.pymobiledevice3 ?? "?")\n"
        s += "phase: \(phase)\n"
        for r in orderedRecords {
            s += "\(r.handle) \(r.udid) \(r.model ?? "") \(r.ios ?? "") mode=\(r.mode.rawValue) state=\(rt(r.udid).state.rawValue) proxy=\(ProxyParser.mask(r.proxy))\n"
        }
        s += "--- last log lines ---\n" + logLines.suffix(40).joined(separator: "\n")
        return s
    }
}
