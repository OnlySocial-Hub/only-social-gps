import Foundation

// MARK: - Python discovery and pymobiledevice3 probe

enum PythonProbe {
    enum Outcome: Equatable {
        case ok(version: String, pmd3: String)
        case missingPmd3(version: String)
        case noPython
        case failed(String)
    }

    static let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]

    /// First existing interpreter (override wins), else `env python3` resolved through PATH, else nil.
    static func find(override: String?) -> String? {
        if let override, !override.isEmpty, FileManager.default.isExecutableFile(atPath: override) { return override }
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        let env = Process()
        env.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        env.arguments = ["python3", "-c", "import sys; print(sys.executable)"]
        let out = Pipe()
        env.standardOutput = out
        env.standardError = FileHandle.nullDevice
        do {
            try env.run()
            env.waitUntilExit()
            let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if env.terminationStatus == 0, !path.isEmpty { return path }
        } catch {}
        return nil
    }

    /// 3 s `import pymobiledevice3` probe.
    static func probe(python: String, timeout: TimeInterval = 3) async -> Outcome {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: python)
            p.arguments = ["-c",
                "import sys; print(sys.version.split()[0]); import pymobiledevice3, importlib.metadata as m; print(m.version('pymobiledevice3'))"]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            let gate = ProbeGate()
            p.terminationHandler = { proc in
                let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let lines = text.split(separator: "\n").map(String.init)
                guard gate.claim() else { return }
                if proc.terminationStatus == 0, lines.count >= 2 {
                    cont.resume(returning: .ok(version: lines[0], pmd3: lines[1]))
                } else if let v = lines.first, !v.isEmpty {
                    cont.resume(returning: .missingPmd3(version: v))
                } else {
                    cont.resume(returning: .failed("python exited \(proc.terminationStatus)"))
                }
            }
            do { try p.run() } catch {
                _ = gate.claim()
                cont.resume(returning: .noPython)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if gate.claim() {
                    p.terminate()
                    cont.resume(returning: .failed("probe timed out after \(Int(timeout)) s"))
                }
            }
        }
    }
}

/// One-shot gate shared by the probe's termination handler and its timeout.
final class ProbeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if claimed { return false }; claimed = true; return true }
}

// MARK: - Events

enum EngineEvent {
    case hello(pid: Int?, version: String?)
    case devices([Device])
    case deviceState(DeviceStateEvent)
    case geoProgress(id: Int, stage: String)
    case log(level: String, udid: String?, message: String)
}

// MARK: - Client

/// Spawns the Python hub (or the mock), speaks NDJSON over pipes. Thread-safe; callbacks are
/// delivered on the main queue.
final class EngineClient {
    enum Kind {
        case hub
        case mock(scenario: String, devicesFile: String?)
    }

    let python: String
    let engineDir: URL
    let kind: Kind
    var onEvent: ((EngineEvent) -> Void)?
    var onExit: ((Int32) -> Void)?
    var onStderr: ((String) -> Void)?

    private let lock = NSLock()
    private var process: Process?
    private var stdin: FileHandle?
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextId = 1
    private var exited = false
    private(set) var pid: Int32 = 0

    init(python: String, engineDir: URL, kind: Kind) {
        self.python = python
        self.engineDir = engineDir
        self.kind = kind
    }

    var isRunning: Bool { locked { process?.isRunning ?? false } }

    func makeId() -> Int { locked { nextId += 1; return nextId } }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
    private var canSend: Bool { locked { !exited && stdin != nil } }
    private func register(_ id: Int, _ cont: CheckedContinuation<[String: Any], Error>) { locked { pending[id] = cont } }
    private var liveProcess: Process? { locked { (exited ? nil : process).flatMap { $0.isRunning ? $0 : nil } } }

    func start() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        var args: [String]
        switch kind {
        case .hub:
            args = ["-u", engineDir.appendingPathComponent("osgps_engine.py").path]
        case .mock(let scenario, let file):
            args = ["-u", engineDir.appendingPathComponent("mock_engine.py").path, "--scenario", scenario]
            if let file { args += ["--devices", file] }
        }
        p.arguments = args
        p.currentDirectoryURL = engineDir
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.terminationHandler = { [weak self] proc in
            self?.handleExit(proc.terminationStatus)
        }
        try p.run()
        lock.lock()
        process = p
        stdin = inPipe.fileHandleForWriting
        exited = false
        pid = p.processIdentifier
        lock.unlock()
        startReader(outPipe.fileHandleForReading, isStdout: true)
        startReader(errPipe.fileHandleForReading, isStdout: false)
    }

    /// Dedicated blocking-read thread per pipe: never deadlocks however much the engine prints.
    private func startReader(_ fh: FileHandle, isStdout: Bool) {
        let t = Thread { [weak self] in
            let fd = fh.fileDescriptor
            var buffer = Data()
            let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
            defer { chunk.deallocate(); try? fh.close() }
            while true {
                let n = read(fd, chunk, 65536)
                if n <= 0 { break }
                buffer.append(chunk, count: n)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                    buffer.removeSubrange(buffer.startIndex...nl)
                    guard let self else { return }
                    if isStdout { self.handleLine(lineData) } else { self.handleStderr(lineData) }
                }
            }
            if !buffer.isEmpty, let self {
                if isStdout { self.handleLine(buffer) } else { self.handleStderr(buffer) }
            }
        }
        t.name = isStdout ? "engine-stdout" : "engine-stderr"
        t.qualityOfService = .userInitiated
        t.start()
    }

    private func handleStderr(_ data: Data) {
        guard let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
        let cb = onStderr
        DispatchQueue.main.async { cb?(s) }
    }

    private func handleLine(_ data: Data) {
        guard !data.isEmpty else { return }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if let s = String(data: data, encoding: .utf8) { handleStderr(Data("[non-JSON stdout] \(s)".utf8)) }
            return
        }
        if let idAny = obj["id"], obj["ok"] != nil, obj["event"] == nil {
            let id = (idAny as? Int) ?? Int((idAny as? String) ?? "") ?? -1
            lock.lock()
            let cont = pending.removeValue(forKey: id)
            lock.unlock()
            guard let cont else { return }
            if (obj["ok"] as? Bool) == true {
                cont.resume(returning: (obj["result"] as? [String: Any]) ?? [:])
            } else {
                let err = obj["error"] as? [String: Any] ?? [:]
                var fallback: GeoResult? = nil
                if let fb = err["fallback"] as? [String: Any] { fallback = try? JSONCoding.decode(GeoResult.self, from: fb) }
                cont.resume(throwing: EngineError(code: (err["code"] as? String) ?? "error",
                                                  message: (err["message"] as? String) ?? "engine error",
                                                  fallback: fallback))
            }
            return
        }
        guard let event = obj["event"] as? String else { return }
        var parsed: EngineEvent? = nil
        switch event {
        case "hello":
            parsed = .hello(pid: obj["pid"] as? Int, version: obj["engine_version"] as? String)
        case "devices":
            let list = (obj["devices"] as? [[String: Any]]) ?? []
            let devices = list.compactMap { try? JSONCoding.decode(Device.self, from: $0) }
            parsed = .devices(devices)
        case "device_state":
            if let ev = try? JSONCoding.decode(DeviceStateEvent.self, from: obj) { parsed = .deviceState(ev) }
        case "geo_progress":
            let id = (obj["id"] as? Int) ?? Int((obj["id"] as? String) ?? "") ?? -1
            parsed = .geoProgress(id: id, stage: (obj["stage"] as? String) ?? "")
        case "log":
            parsed = .log(level: (obj["level"] as? String) ?? "info", udid: obj["udid"] as? String,
                          message: (obj["message"] as? String) ?? "")
        default:
            break
        }
        guard let parsed else { return }
        let cb = onEvent
        DispatchQueue.main.async { cb?(parsed) }
    }

    private func handleExit(_ status: Int32) {
        lock.lock()
        let wasExited = exited
        exited = true
        let conts = pending
        pending.removeAll()
        try? stdin?.close()
        stdin = nil
        lock.unlock()
        for (_, c) in conts {
            c.resume(throwing: EngineError(code: "engine_exited", message: "engine exited (\(status))"))
        }
        if !wasExited {
            let cb = onExit
            DispatchQueue.main.async { cb?(status) }
        }
    }

    /// Fire-and-forget write.
    func send(_ obj: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        lock.lock()
        let fh = stdin
        lock.unlock()
        guard let fh else { return }
        do { try fh.write(contentsOf: data) } catch {}
    }

    /// Request/reply with continuation keyed by id.
    func request(_ cmd: String, _ params: [String: Any] = [:], id: Int? = nil) async throws -> [String: Any] {
        let rid = id ?? makeId()
        var obj = params
        obj["id"] = rid
        obj["cmd"] = cmd
        guard canSend else { throw EngineError(code: "engine_down", message: "engine is not running") }
        return try await withCheckedThrowingContinuation { cont in
            register(rid, cont)
            send(obj)
        }
    }

    /// Request with a timeout (seconds).
    func request(_ cmd: String, _ params: [String: Any] = [:], id: Int? = nil, timeout: TimeInterval) async throws -> [String: Any] {
        let rid = id ?? makeId()
        return try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask { try await self.request(cmd, params, id: rid) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw EngineError(code: "timeout", message: "\(cmd) timed out after \(Int(timeout)) s")
            }
            let first = try await group.next()!
            group.cancelAll()
            self.cancelPending(rid)
            return first
        }
    }

    private func cancelPending(_ id: Int) {
        lock.lock()
        let c = pending.removeValue(forKey: id)
        lock.unlock()
        c?.resume(throwing: EngineError(code: "cancelled", message: "cancelled"))
    }

    /// Clean shutdown: `shutdown` request, wait ≤ 4 s for exit, then SIGTERM.
    func shutdown() async {
        guard let p = liveProcess else { return }
        _ = try? await request("shutdown", timeout: 4)
        let deadline = Date().addingTimeInterval(4)
        while p.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if p.isRunning { p.terminate() }
        let hard = Date().addingTimeInterval(1)
        while p.isRunning && Date() < hard { try? await Task.sleep(nanoseconds: 50_000_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }

    func terminate() {
        lock.lock()
        let p = process
        lock.unlock()
        guard let p, p.isRunning else { return }
        p.terminate()
    }
}
