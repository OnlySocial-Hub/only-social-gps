import Foundation
import CoreLocation
import SwiftUI

// MARK: - Protocol mirrors (PROTOCOL.md)

struct Device: Codable, Identifiable, Hashable {
    var udid: String
    var name: String?
    var productType: String?
    var modelName: String?
    var ios: String?
    var build: String?
    var connection: String?
    var developerMode: Bool?
    var ddiMounted: Bool?
    var paired: Bool?
    var serial: String?
    var timezone: String?
    var firstSeen: Double?
    var lastSeen: Double?
    var id: String { udid }

    var marketingName: String { modelName ?? Models.marketingName(productType) ?? productType ?? "iPhone" }
}

struct ProxyInfo: Codable, Hashable {
    var scheme: String
    var host: String
    var port: Int
    var username: String?
    var password: String?
    var normalized: String
    var curlArgs: [String]?
}

struct GeoResult: Codable, Hashable {
    var ip: String?
    var lat: Double
    var lon: Double
    var city: String?
    var region: String?
    var country: String?
    var countryCode: String?
    var isp: String?
    var org: String?
    var asn: String?
    var timezone: String?
    var provider: String?
    var viaProxy: Bool?
    var note: String?
    var checkedAt: Double?
    var elapsedMs: Double?
    var flag: String?

    var checkedDate: Date? { checkedAt.map { Date(timeIntervalSince1970: $0) } }
    var isDegraded: Bool { note != nil || viaProxy == false }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var flagEmoji: String { flag ?? Fmt.flag(countryCode) }
    var cityLine: String { city ?? region ?? country ?? "Unknown" }
    var regionLine: String {
        [region, country].compactMap { $0 }.filter { !$0.isEmpty && $0 != city }.joined(separator: " · ")
    }
    var ispLine: String {
        var parts: [String] = []
        if let isp, !isp.isEmpty { parts.append(isp) }
        if let org, !org.isEmpty, org != isp { parts.append(org) }
        return parts.joined(separator: " · ")
    }
    var isStale: Bool { (checkedDate.map { Date().timeIntervalSince($0) } ?? 0) > 600 }
}

enum EngineState: String, Codable {
    case idle, connecting, tunnelUp = "tunnel_up", simulating, reconnecting, error, released, disconnected
}

struct Target: Codable, Hashable {
    var lat: Double
    var lon: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
    init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lon = c.longitude }
    var isValid: Bool { (-90...90).contains(lat) && (-180...180).contains(lon) }
    func distance(to other: Target) -> CLLocationDistance {
        CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: other.lat, longitude: other.lon))
    }
}

struct AppliedTarget: Codable, Hashable {
    var lat: Double
    var lon: Double
    var at: Double?
    var target: Target { Target(lat: lat, lon: lon) }
}

struct DeviceStateEvent: Codable {
    var udid: String
    var state: EngineState
    var target: Target?
    var applied: AppliedTarget?
    var message: String?
    var attempt: Int?
    var retryIn: Double?
}

struct WorkerStatus: Codable {
    var pid: Int?
    var state: EngineState?
    var target: Target?
    var applied: AppliedTarget?
    var restarts: Int?
    var lastError: String?
    var lastHeartbeat: Double?
}

struct HelloResult: Codable {
    var engineVersion: String?
    var python: String?
    var pymobiledevice3: String?
    var pid: Int?
    var capabilities: [String]?
}

struct EngineError: Error, LocalizedError {
    var code: String
    var message: String
    var fallback: GeoResult?
    var errorDescription: String? { message }
}

// MARK: - Persisted app state

enum Mode: String, Codable, CaseIterable, Identifiable {
    case proxy, manual, off
    var id: String { rawValue }
    var title: String {
        switch self { case .proxy: "Proxy"; case .manual: "Manual"; case .off: "Off" }
    }
}

enum MapStyleChoice: String, Codable, CaseIterable, Identifiable {
    case muted, standard, imagery
    var id: String { rawValue }
    var title: String {
        switch self { case .muted: "Muted"; case .standard: "Standard"; case .imagery: "Imagery" }
    }
}

enum ThemeChoice: String, Codable, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "System"; case .dark: "Dark"; case .light: "Light" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .dark: .dark; case .light: .light }
    }
}

struct PhoneRecord: Codable, Identifiable, Hashable {
    var udid: String
    var nickname: String = ""
    var proxy: String = ""
    var mode: Mode = .off
    var target: Target? = nil            // pinned base target (geo or manual), without scatter; nil = released
    var manualTarget: Target? = nil      // draft pin position in Manual mode
    var scatterOffset: Target? = nil     // rolled offset in degrees, re-rolled on Pin
    var pinnedScatter: Double? = nil     // scatter radius that was in force at the last Pin
    var geo: GeoResult? = nil
    var geoProxy: String? = nil          // the proxy string the geo record was produced for
    var scatter: Double = 0
    var lastAppliedAt: Double? = nil
    var lastSeenAt: Double? = nil
    var model: String? = nil
    var ios: String? = nil
    var firstSeen: Double? = nil
    var manualName: String? = nil        // reverse-geocoded label for manual targets
    var id: String { udid }

    /// The coordinate the engine is asked to hold: base target + scatter offset.
    var desired: Target? {
        guard let target, mode != .off else { return nil }
        guard let off = scatterOffset, scatter > 0 else { return target }
        return Target(lat: target.lat + off.lat, lon: target.lon + off.lon)
    }
    /// Where a Pin would send the phone right now (before scatter): geo in Proxy mode, the draft in Manual.
    var candidate: Target? {
        switch mode {
        case .proxy: return geoMatchesProxy ? geo.map { Target(lat: $0.lat, lon: $0.lon) } : nil
        case .manual: return manualTarget
        case .off: return nil
        }
    }
    var handle: String { nickname.isEmpty ? Fmt.shortUDID(udid) : nickname }
    var handleBare: String { handle.hasPrefix("@") ? String(handle.dropFirst()) : handle }
    var geoMatchesProxy: Bool { geo != nil && geoProxy == ProxyParser.canonical(proxy) }
}

struct AppSettings: Codable, Hashable {
    var launchAtLogin: Bool = false
    var reapplyOnLaunch: Bool = true
    var mapStyle: MapStyleChoice = .muted
    var theme: ThemeChoice = .dark
    var pythonPath: String? = nil
    var inspectorShown: Bool = true
    var hasLaunchedBefore: Bool = false
}

enum Route: Hashable, Codable {
    case fleet
    case phone(String)
    var udid: String? { if case .phone(let u) = self { return u } else { return nil } }
}

struct PersistedState: Codable {
    var version: Int = 1
    var records: [String: PhoneRecord] = [:]
    var settings: AppSettings = AppSettings()
    var route: Route = .fleet
}

// MARK: - View-level derived state (§4.1)

enum PhoneViewState: Equatable {
    case starting
    case unplugged(hasTarget: Bool)
    case real
    case locating
    case applying
    case spoofed(city: String)
    case reconnecting(attempt: Int, seconds: Int)
    case error(message: String)

    var isBusy: Bool {
        switch self { case .locating, .applying, .reconnecting, .starting: true; default: false }
    }
    var isSpoofed: Bool { if case .spoofed = self { return true } else { return false } }
    var isError: Bool { if case .error = self { return true } else { return false } }
    var isUnplugged: Bool { if case .unplugged = self { return true } else { return false } }
    var isReconnecting: Bool { if case .reconnecting = self { return true } else { return false } }

    var pillText: String {
        switch self {
        case .starting: "Starting…"
        case .unplugged(let t): t ? "Unplugged · will re-apply" : "Unplugged"
        case .real: "Real GPS"
        case .locating: "Locating…"
        case .applying: "Applying…"
        case .spoofed(let city): "Spoofed · \(city)"
        case .reconnecting(let n, let s): "Reconnecting · try \(n) · \(s) s"
        case .error: "Error"
        }
    }
    /// Short form for chips and the menu bar.
    var compactText: String {
        switch self {
        case .starting: "Starting…"
        case .unplugged: "Unplugged"
        case .real: "Real GPS"
        case .locating: "Locating…"
        case .applying: "Applying…"
        case .spoofed(let city): city.components(separatedBy: ",").first ?? city
        case .reconnecting: "Reconnecting"
        case .error: "Error"
        }
    }
    var accessibilityText: String {
        switch self {
        case .spoofed(let city): "Spoofed, \(city)"
        default: pillText
        }
    }
}

// MARK: - Toasts (§4.9)

struct Toast: Identifiable, Equatable {
    enum Kind: Equatable { case ok, busy, info, error }
    let id = UUID()
    var kind: Kind
    var text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var duration: Double = 4
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

// MARK: - Runtime (non-persisted) per-phone state

struct PhoneRuntime {
    var state: EngineState = .idle
    var target: Target? = nil
    var applied: AppliedTarget? = nil
    var message: String? = nil
    var attempt: Int? = nil
    var retryAt: Date? = nil
    var restarts: Int = 0
    var lastError: String? = nil
    var errorEpisodeToasted = false
    var unplugToasted = false
}

// MARK: - Marketing names (BRIEF.md table)

enum Models {
    static let table: [String: String] = [
        "iPhone11,8": "iPhone XR", "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2nd gen)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max", "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,6": "iPhone SE (3rd gen)",
        "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e",
    ]
    static func marketingName(_ productType: String?) -> String? {
        guard let productType else { return nil }
        if let n = table[productType] { return n }
        if productType.hasPrefix("iPhone18,") { return "iPhone 17" }
        return nil
    }
    /// "iPhone XR" -> "XR" for tight row subtitles.
    static func shortModel(_ name: String?) -> String {
        guard let name else { return "iPhone" }
        return name.replacingOccurrences(of: "iPhone ", with: "")
    }
}

// MARK: - JSON coding helpers

enum JSONCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    static func decode<T: Decodable>(_ type: T.Type, from any: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: any, options: [])
        return try decoder.decode(type, from: data)
    }
}
