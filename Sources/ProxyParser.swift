import Foundation

/// Client-side pre-validation of proxy strings (BRIEF.md §Proxy grammar). Used for instant
/// keystroke feedback and masking only; the engine's `parse_proxy` is authoritative.
enum ProxyParser {
    struct ParseFailure: Error { let text: String; init(_ t: String) { text = t } }

    struct Parsed: Equatable {
        var scheme: String
        var host: String
        var port: Int
        var username: String?
        var password: String?
        var isHTTP: Bool { scheme == "http" || scheme == "https" }
        var hostPort: String { (host.contains(":") ? "[\(host)]" : host) + ":\(port)" }
        var normalized: String {
            var cred = ""
            if let username, !username.isEmpty {
                cred = password != nil && !(password!.isEmpty) ? "\(username):***@" : "\(username)@"
            }
            return "\(scheme)://\(cred)\(hostPort)"
        }
        var masked: String {
            var cred = ""
            if let username, !username.isEmpty {
                cred = password != nil && !(password!.isEmpty) ? "\(username):•••@" : "\(username)@"
            }
            return "\(scheme)://\(cred)\(hostPort)"
        }
        /// Short summary line for the parse feedback: "socks5h · host:1080 · user jm…"
        var summary: String {
            var parts = [scheme, hostPort]
            if let username, !username.isEmpty {
                let short = username.count > 6 ? String(username.prefix(6)) + "…" : username
                parts.append("user \(short)")
            }
            return parts.joined(separator: " · ")
        }
    }

    enum Result: Equatable {
        case empty
        case valid(Parsed)
        case invalid(String)
    }

    static func parse(_ raw: String) -> Result {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let f = s.first, f == "\"" || f == "'" { s.removeFirst() }
        while let l = s.last, l == "\"" || l == "'" { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.isEmpty { return .empty }
        if s.contains("\n") { return .invalid("one proxy per field — use Paste as list for several") }
        if s.contains(" ") { return .invalid("unexpected space") }

        var scheme = "socks5h"
        if let range = s.range(of: "://") {
            let sc = s[..<range.lowerBound].lowercased()
            switch sc {
            case "socks5h": scheme = "socks5h"
            case "socks5", "socks": scheme = "socks5"
            case "http", "https": scheme = sc
            default: return .invalid("unsupported scheme '\(sc)'")
            }
            s = String(s[range.upperBound...])
            if s.isEmpty { return .invalid("missing host after \(sc)://") }
        }

        var user: String? = nil
        var pass: String? = nil
        var hostPart = s
        if let at = s.lastIndex(of: "@") {
            let creds = String(s[..<at])
            hostPart = String(s[s.index(after: at)...])
            if let colon = creds.firstIndex(of: ":") {
                user = String(creds[..<colon]).removingPercentEncoding ?? String(creds[..<colon])
                pass = String(creds[creds.index(after: colon)...]).removingPercentEncoding ?? String(creds[creds.index(after: colon)...])
            } else {
                user = creds.removingPercentEncoding ?? creds
            }
            if user?.isEmpty == true { user = nil }
            switch splitHostPort(hostPart) {
            case .success(let hp): return .valid(Parsed(scheme: scheme, host: hp.0, port: hp.1, username: user, password: pass))
            case .failure(let e): return .invalid(e.text)
            }
        }

        if hostPart.hasPrefix("[") {
            switch splitHostPort(hostPart) {
            case .success(let hp): return .valid(Parsed(scheme: scheme, host: hp.0, port: hp.1, username: nil, password: nil))
            case .failure(let e): return .invalid(e.text)
            }
        }
        let parts = hostPart.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.count {
        case 1:
            return .invalid("missing port — expected host:port")
        case 2:
            switch splitHostPort(hostPart) {
            case .success(let hp): return .valid(Parsed(scheme: scheme, host: hp.0, port: hp.1, username: nil, password: nil))
            case .failure(let e): return .invalid(e.text)
            }
        case 4:
            if let p = port(parts[1]) {
                guard !parts[0].isEmpty else { return .invalid("empty host") }
                return .valid(Parsed(scheme: scheme, host: parts[0], port: p, username: parts[2], password: parts[3]))
            }
            if let p = port(parts[3]) {
                guard !parts[2].isEmpty else { return .invalid("empty host") }
                return .valid(Parsed(scheme: scheme, host: parts[2], port: p, username: parts[0], password: parts[1]))
            }
            return .invalid("4-field form needs a numeric port in field 2 or 4")
        case 3:
            return .invalid("3 fields — expected host:port:user:pass")
        default:
            return .invalid("unrecognised proxy notation (\(parts.count) fields)")
        }
    }

    private static func port(_ s: String) -> Int? {
        guard let p = Int(s), (1...65535).contains(p), s.allSatisfy(\.isNumber) else { return nil }
        return p
    }

    private static func splitHostPort(_ hp: String) -> Swift.Result<(String, Int), ParseFailure> {
        if hp.hasPrefix("[") {
            guard let end = hp.firstIndex(of: "]") else { return .failure(ParseFailure("unterminated IPv6 bracket")) }
            let host = String(hp[hp.index(after: hp.startIndex)..<end])
            let rest = String(hp[hp.index(after: end)...])
            guard rest.hasPrefix(":"), let p = port(String(rest.dropFirst())) else { return .failure(ParseFailure("bad port after IPv6 host")) }
            return .success((host, p))
        }
        let parts = hp.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return .failure(ParseFailure("expected host:port")) }
        guard !parts[0].isEmpty else { return .failure(ParseFailure("empty host")) }
        guard let p = port(parts[1]) else { return .failure(ParseFailure("bad port '\(parts[1])'")) }
        return .success((parts[0], p))
    }

    /// Masked display form ("socks5h://user:•••@host:1080") or the raw text with any password blanked.
    static func mask(_ raw: String) -> String {
        switch parse(raw) {
        case .valid(let p): return p.masked
        case .empty: return ""
        case .invalid:
            // best effort: hide anything that looks like a password
            if let at = raw.lastIndex(of: "@"), let colon = raw[..<at].lastIndex(of: ":") {
                return String(raw[...colon]) + "•••" + String(raw[at...])
            }
            return raw
        }
    }

    /// Stable key so "did the proxy change since the last Locate?" compares canonical forms.
    static func canonical(_ raw: String) -> String {
        if case .valid(let p) = parse(raw) {
            return "\(p.scheme)://\(p.username ?? ""):\(p.password ?? "")@\(p.hostPort)"
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bulk-paste line parsing: "proxy", "handle, proxy" or "handle proxy".
    struct BulkLine: Identifiable, Equatable {
        enum Status: Equatable { case parsed, badLine(String), noPhone, handleNotFound, ignored }
        let id: Int
        var raw: String
        var handle: String?
        var proxy: String
        var status: Status
        var udid: String?
    }

    static func splitBulkLine(_ line: String) -> (handle: String?, proxy: String) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if let comma = t.firstIndex(of: ",") {
            let h = t[..<comma].trimmingCharacters(in: .whitespaces)
            let p = t[t.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            if !h.isEmpty && !p.isEmpty && !h.contains(":") { return (h, p) }
        }
        let ws = t.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if ws.count >= 2, !ws[0].contains(":") { return (ws[0], ws[1...].joined(separator: " ")) }
        return (nil, t)
    }
}
