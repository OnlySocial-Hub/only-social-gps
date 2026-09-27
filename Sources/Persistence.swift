import Foundation

// MARK: - Environment (OSGPS_*)

enum Env {
    private static let e = ProcessInfo.processInfo.environment
    static let snapshotPath: String? = e["OSGPS_SNAPSHOT"].flatMap { $0.isEmpty ? nil : $0 }
    static let isSnapshot: Bool = snapshotPath != nil
    static let mockFile: String? = e["OSGPS_MOCK"].flatMap { $0.isEmpty ? nil : $0 }
    static let screen: String = (e["OSGPS_SCREEN"] ?? "fleet").lowercased()
    static let select: String? = e["OSGPS_SELECT"].flatMap { $0.isEmpty ? nil : $0 }
    static let engineChoice: String = (e["OSGPS_ENGINE"] ?? "").lowercased()
    /// Snapshot mode uses the mock unless `OSGPS_ENGINE=real` (picture the live fleet, never spoofing);
    /// interactive mode uses the real hub unless `OSGPS_ENGINE=mock`.
    static let useMock: Bool = isSnapshot ? engineChoice != "real" : engineChoice == "mock"
    /// Mock scenario: snapshot mode forces `snapshot`; interactive mock defaults to `normal`.
    static let mockScenario: String = {
        if isSnapshot {
            switch screen {
            case "empty": return "empty"
            case "starting", "crash": return "snapshot"
            default: return "snapshot"
            }
        }
        return e["OSGPS_SCENARIO"] ?? "normal"
    }()
    static let reduceMotionOverride: Bool = isSnapshot || e["OSGPS_NO_MOTION"] == "1"
    static let lightMode: Bool = isSnapshot && screen == "light"
    /// Minimum settle time before the snapshot is taken (seconds; `OSGPS_SNAPSHOT_DELAY`, default 2.5).
    static let snapshotDelay: Double = e["OSGPS_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 2.5
    /// Upper bound on waiting for the map image / sheet (seconds; `OSGPS_SNAPSHOT_MAXWAIT`, default 25).
    static let snapshotMaxWait: Double = e["OSGPS_SNAPSHOT_MAXWAIT"].flatMap(Double.init) ?? 25
    /// `OSGPS_MAP=live` captures the real MapKit view instead of the MKMapSnapshotter fallback.
    static let snapshotLiveMap: Bool = e["OSGPS_MAP"]?.lowercased() == "live"
}

// MARK: - Persistence

enum Persistence {
    static let appName = "Only Social GPS"

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appName, isDirectory: true)
    }
    static var stateURL: URL { supportDir.appendingPathComponent("state.json") }
    static var logDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/OnlySocialGPS", isDirectory: true)
    }
    static var appLogURL: URL { logDir.appendingPathComponent("app.log") }
    static var engineLogURL: URL { logDir.appendingPathComponent("engine.log") }
    static let farmNamesURL = URL(fileURLWithPath: "/Users/james/Desktop/iphone-bot copy/.devicenames.json")

    static func load() -> PersistedState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        do { return try JSONCoding.decoder.decode(PersistedState.self, from: data) }
        catch {
            AppLog.write("state.json unreadable: \(error)")
            return nil
        }
    }

    /// Atomic write: encode, write to a temp file next to the target, then replace.
    static func save(_ state: PersistedState) {
        do {
            try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            let data = try JSONCoding.encoder.encode(state)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            AppLog.write("state.json write failed: \(error)")
        }
    }

    /// Farm nickname pre-fill (read-only, best effort).
    static func farmNicknames() -> [String: String] {
        guard let data = try? Data(contentsOf: farmNamesURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in obj { if let s = v as? String { out[k] = s } }
        return out
    }

    /// Engine directory: bundled Contents/Resources/Engine, else ../Engine next to a bare executable.
    static var engineDir: URL {
        if let r = Bundle.main.resourceURL {
            let bundled = r.appendingPathComponent("Engine", isDirectory: true)
            if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("mock_engine.py").path) { return bundled }
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = dir.appendingPathComponent("Engine", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("mock_engine.py").path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: "/Applications/Only Social GPS.app/Contents/Resources/Engine")
    }
}

// MARK: - App log (stderr + ~/Library/Logs/OnlySocialGPS/app.log)

enum AppLog {
    private static let queue = DispatchQueue(label: "osgps.log")
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
    static func write(_ message: String) {
        let line = "[app \(fmt.string(from: Date()))] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        queue.async {
            do {
                try FileManager.default.createDirectory(at: Persistence.logDir, withIntermediateDirectories: true)
                let url = Persistence.appLogURL
                if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int, size > 2_000_000 {
                    try? FileManager.default.removeItem(at: url)
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                let fh = try FileHandle(forWritingTo: url)
                try fh.seekToEnd()
                try fh.write(contentsOf: Data(line.utf8))
                try fh.close()
            } catch {}
        }
    }
}

// MARK: - Snapshot seed (DESIGN.md §10)

enum SnapshotSeed {
    static let udids = ["00008020-000A283934E9002E", "00008020-00092D843405002E",
                        "00008020-001019503499002E", "00008030-0009193402B8402E"]
    static let handles = ["@nat.hunterrr", "@onlyemspage", "@onlyglazertori", "@ellybellywellyyy"]

    static func geo(city: String, region: String, country: String, cc: String, lat: Double, lon: Double,
                    tz: String, isp: String, org: String, asn: String, ip: String, age: Double = 120) -> GeoResult {
        GeoResult(ip: ip, lat: lat, lon: lon, city: city, region: region, country: country, countryCode: cc,
                  isp: isp, org: org, asn: asn, timezone: tz, provider: "ip-api.com", viaProxy: true, note: nil,
                  checkedAt: Date().timeIntervalSince1970 - age, elapsedMs: 1240, flag: Fmt.flag(cc))
    }

    static func state() -> PersistedState {
        let now = Date().timeIntervalSince1970
        let proxies = ["socks5h://jm_ldn:hunter2pass@lon.isp-proxy.net:1080",
                       "dal.isp-proxy.net:1080:jm_dal:s3cretpw",
                       "jm_par:parispw@par.isp-proxy.net:1080",
                       "socks5://jm_ber:berlinpw@ber.isp-proxy.net:1080"]
        let geos = [
            geo(city: "London", region: "England", country: "United Kingdom", cc: "GB", lat: 51.5074, lon: -0.1278,
                tz: "Europe/London", isp: "Virgin Media", org: "Virgin Media Limited", asn: "AS5089", ip: "82.12.4.9"),
            geo(city: "Dallas", region: "Texas", country: "United States", cc: "US", lat: 32.7767, lon: -96.7970,
                tz: "America/Chicago", isp: "AT&T Internet", org: "AT&T Services, Inc.", asn: "AS7018", ip: "99.104.22.7", age: 340),
            geo(city: "Paris", region: "Île-de-France", country: "France", cc: "FR", lat: 48.8566, lon: 2.3522,
                tz: "Europe/Paris", isp: "Orange", org: "Orange S.A.", asn: "AS3215", ip: "90.2.118.41", age: 900),
            geo(city: "Berlin", region: "Berlin", country: "Germany", cc: "DE", lat: 52.5200, lon: 13.4050,
                tz: "Europe/Berlin", isp: "Deutsche Telekom", org: "Deutsche Telekom AG", asn: "AS3320", ip: "91.64.7.200", age: 4000),
        ]
        var records: [String: PhoneRecord] = [:]
        for i in 0..<4 {
            var r = PhoneRecord(udid: udids[i])
            r.nickname = handles[i]
            r.proxy = proxies[i]
            r.mode = .proxy
            r.geo = geos[i]
            r.geoProxy = ProxyParser.canonical(proxies[i])
            r.target = Target(lat: geos[i].lat, lon: geos[i].lon)
            r.scatter = 0
            r.pinnedScatter = 0
            r.model = i == 3 ? "iPhone 11" : "iPhone XR"
            r.ios = i == 3 ? "18.7.8" : "18.7.9"
            r.firstSeen = now - 3600 + Double(i)
            r.lastSeenAt = i == 3 ? now - 1800 : now
            r.lastAppliedAt = now - 600 - Double(i * 40)
            records[udids[i]] = r
        }
        var s = PersistedState()
        s.records = records
        s.settings.theme = Env.lightMode ? .light : .dark
        s.settings.hasLaunchedBefore = true
        s.route = .fleet
        return s
    }

    static let macLocation = GeoResult(ip: "142.166.71.14", lat: 44.6713, lon: -63.5772, city: "Dartmouth",
                                       region: "Nova Scotia", country: "Canada", countryCode: "CA", isp: "Bell Canada",
                                       org: "Bell Aliant", asn: "AS855", timezone: "America/Halifax", provider: "ip-api.com",
                                       viaProxy: false, note: nil, checkedAt: Date().timeIntervalSince1970, elapsedMs: 312, flag: "🇨🇦")

    static let bulkSample = """
    @nat.hunterrr, socks5h://jm_ldn:hunter2pass@lon.isp-proxy.net:1080
    @onlyemspage dal.isp-proxy.net:1080:jm_dal:s3cretpw
    @onlyglazertori, jm_par:parispw@par.isp-proxy.net:1080
    @ellybellywellyyy, not-a-proxy
    """
}
