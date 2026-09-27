// LocalBridge — a tiny loopback HTTP endpoint so the iPhone-Bot proxy feature can
// ask this app to match a phone's GPS to its proxy. Binds 127.0.0.1 only (never
// reachable off this Mac). All work goes through AppModel, so the app's own UI
// reflects it and one engine still owns every phone (no GPS conflicts).
//
//   GET  /osgps/ping                          -> { ok, app, version, devices:[udid…] }
//   POST /osgps/set-from-proxy { udid, proxy } -> { ok, geo:{lat,lon,city,region,country,ip} } | { ok:false, error }
//   POST /osgps/release        { udid }        -> { ok }

import Foundation
import Network

@MainActor
final class LocalBridge {
    static let shared = LocalBridge()
    private var listener: NWListener?

    func start(port: UInt16 = 8765) {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            let l = try NWListener(using: params)
            l.newConnectionHandler = { conn in Task { @MainActor in LocalBridge.shared.accept(conn) } }
            l.stateUpdateHandler = { state in if case .failed(let e) = state { NSLog("OS GPS LocalBridge failed: \(e)") } }
            l.start(queue: .main)
            listener = l
            NSLog("OS GPS LocalBridge listening on 127.0.0.1:\(port)")
        } catch { NSLog("OS GPS LocalBridge could not start: \(error)") }
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            Task { @MainActor in
                var buf = buffer
                if let d = data { buf.append(d) }
                if let req = HTTPRequest.parse(buf) {
                    await LocalBridge.shared.route(conn, req)
                } else if isComplete || error != nil {
                    conn.cancel()
                } else {
                    LocalBridge.shared.receive(conn, buffer: buf) // header/body not complete yet
                }
            }
        }
    }

    private func route(_ conn: NWConnection, _ req: HTTPRequest) async {
        var status = 200
        var obj: [String: Any] = ["ok": false, "error": "not found"]
        let model = AppModel.shared
        switch (req.method, req.path) {
        case ("GET", "/osgps/ping"):
            obj = ["ok": true, "app": "only-social-gps",
                   "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                   "devices": model.knownUDIDs]
        case ("POST", "/osgps/set-from-proxy"):
            let udid = (req.json?["udid"] as? String) ?? ""
            let proxy = (req.json?["proxy"] as? String) ?? ""
            if udid.isEmpty || proxy.isEmpty {
                status = 400; obj = ["ok": false, "error": "missing udid or proxy"]
            } else if model.records[udid] == nil {
                status = 404; obj = ["ok": false, "error": "Only Social GPS doesn’t see phone \(udid) — is it plugged in and detected?"]
            } else if let geo = await model.setFromProxy(udid, proxy) {
                obj = ["ok": true, "geo": ["lat": geo.lat, "lon": geo.lon,
                                           "city": geo.city ?? "", "region": geo.region ?? "",
                                           "country": geo.country ?? "", "ip": geo.ip ?? ""]]
            } else {
                status = 502; obj = ["ok": false, "error": "couldn’t geolocate the proxy (unreachable or lookup failed)"]
            }
        case ("POST", "/osgps/release"):
            let udid = (req.json?["udid"] as? String) ?? ""
            if !udid.isEmpty { model.release(udid) }
            obj = ["ok": true]
        default:
            status = 404
        }
        respond(conn, status: status, json: obj)
    }

    private func respond(_ conn: NWConnection, status: Int, json: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        var head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\n"
        head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8); out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let json: [String: Any]?

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return nil } // headers incomplete
        guard let headerStr = String(data: data.subdata(in: 0..<sep.lowerBound), encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        var contentLength = 0
        for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
            contentLength = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let bodyStart = sep.upperBound
        if data.count - bodyStart < contentLength { return nil } // body not fully received
        var json: [String: Any]? = nil
        if contentLength > 0 {
            let bodyData = data.subdata(in: bodyStart..<(bodyStart + contentLength))
            json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
        }
        return HTTPRequest(method: parts[0], path: parts[1], json: json)
    }
}
