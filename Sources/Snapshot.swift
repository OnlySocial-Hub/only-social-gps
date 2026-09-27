import AppKit
import SwiftUI
import MapKit

/// OSGPS_SNAPSHOT renderer (DESIGN.md §10): after 2.5 s render the main window (content + toolbar)
/// at 2×, composite an attached sheet at its frame offset, write PNG, exit 0.
@MainActor enum Snapshot {
    static let scale: CGFloat = 2

    /// Wait `Env.snapshotDelay`, then poll until the map image has loaded (and the sheet is attached
    /// when one is expected) or `Env.snapshotMaxWait` has elapsed, then render.
    static func schedule(window: NSWindow) {
        guard let path = Env.snapshotPath else { return }
        let expectsSheet = Env.screen == "bulk" || Env.screen == "about"
        let needsMap = Env.screen != "setup" && !Env.snapshotLiveMap
        let start = Date()
        func poll() {
            let elapsed = Date().timeIntervalSince(start)
            let model = AppModel.shared
            let mapOK = !needsMap || model.snapshotMapReady
            let sheetOK = !expectsSheet || window.attachedSheet != nil
            // Real hub (OSGPS_ENGINE=real): the fleet arrives ~1-2 s after spawn; wait for it and for
            // the Mac's own location so the picture shows the phones rather than "Starting…".
            let fleetOK = Env.useMock || Env.screen == "setup" || (model.phase == .ready && model.myLocation != nil)
            if (mapOK && sheetOK && fleetOK) || elapsed >= Env.snapshotMaxWait {
                if !(mapOK && sheetOK && fleetOK) {
                    FileHandle.standardError.write(Data("[snapshot] gave up waiting (map \(mapOK), sheet \(sheetOK), fleet \(fleetOK)) after \(Int(elapsed)) s\n".utf8))
                }
                // one more runloop turn so the last image/layout pass is on screen
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { render(window: window, to: path) }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Env.snapshotDelay) { poll() }
    }

    static func makeRep(_ size: NSSize) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        rep?.size = size
        return rep
    }

    static func capture(_ view: NSView) -> NSBitmapImageRep? {
        let bounds = view.bounds
        guard let rep = makeRep(bounds.size) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep
    }

    static func render(window: NSWindow, to path: String) {
        window.displayIfNeeded()
        // The theme frame (contentView's superview) includes the titlebar/toolbar strip.
        let root: NSView = window.contentView?.superview ?? window.contentView!
        guard let main = capture(root) else { fail("could not create bitmap rep") }
        var output = main
        if let sheet = window.attachedSheet, let sheetView = sheet.contentView, let sheetRep = capture(sheetView) {
            if let composed = makeRep(root.bounds.size) {
                NSGraphicsContext.saveGraphicsState()
                if let ctx = NSGraphicsContext(bitmapImageRep: composed) {
                    NSGraphicsContext.current = ctx
                    let full = NSRect(origin: .zero, size: root.bounds.size)
                    main.draw(in: full)
                    // both frames are in screen coordinates (origin bottom-left) like the bitmap
                    let origin = NSPoint(x: sheet.frame.origin.x - window.frame.origin.x,
                                         y: sheet.frame.origin.y - window.frame.origin.y)
                    // dim the window under the sheet a little, like AppKit does
                    NSColor.black.withAlphaComponent(0.25).setFill()
                    full.fill(using: .sourceOver)
                    sheetRep.draw(in: NSRect(origin: origin, size: sheetView.bounds.size))
                    ctx.flushGraphics()
                }
                NSGraphicsContext.restoreGraphicsState()
                output = composed
            }
        }
        guard let png = output.representation(using: .png, properties: [:]) else { fail("PNG encode failed") }
        do {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path))
        } catch { fail("write failed: \(error)") }
        FileHandle.standardError.write(Data("[snapshot] wrote \(path) (\(output.pixelsWide)×\(output.pixelsHigh))\n".utf8))
        AppModel.shared.terminateEngineNow()
        exit(0)
    }

    static func fail(_ why: String) -> Never {
        FileHandle.standardError.write(Data("[snapshot] FAILED: \(why)\n".utf8))
        AppModel.shared.terminateEngineNow()
        exit(3)
    }
}

/// Static map fallback for snapshots (MKMapSnapshotter) when the live Metal map does not
/// render into `cacheDisplay`. Draws the same PinViews at `snapshot.point(for:)` and reports
/// `AppModel.snapshotMapReady` so the renderer waits for the tiles.
struct SnapshotMapView: View {
    @Environment(\.palette) private var p
    @Environment(AppModel.self) private var model
    let region: MKCoordinateRegion
    let style: MapStyleChoice
    @State private var image: NSImage? = nil
    @State private var snapshot: MKMapSnapshotter.Snapshot? = nil
    @State private var takenKey = ""
    @State private var failed = false
    @State private var pendingTask: Task<Void, Never>? = nil

    private var regionKey: String {
        String(format: "%.4f,%.4f,%.4f,%.4f,%@", region.center.latitude, region.center.longitude,
               region.span.latitudeDelta, region.span.longitudeDelta, style.rawValue)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                p.bgField
                if let image, let snapshot {
                    Image(nsImage: image).resizable().frame(width: geo.size.width, height: geo.size.height)
                    let items = model.pinItems
                    let points = items.map { PinLayout.Item(id: $0.udid, point: point(snapshot, $0.coordinate, geo.size), chipWidth: PinLayout.chipWidth(for: $0.chipText)) }
                    let placements = PinLayout.placements(points, in: geo.size)
                    ForEach(items) { item in
                        let pt = point(snapshot, item.coordinate, geo.size)
                        PinView(item: item, selected: model.route.udid == item.udid,
                                dim: model.route == .fleet ? false : model.route.udid != item.udid,
                                placement: placements[item.udid] ?? .below)
                            .position(pt)
                            .zIndex(item.zIndex + (model.route.udid == item.udid ? 10 : 0))
                    }
                    if let m = model.myLocation {
                        MacPinView(label: model.macChipLabel).position(point(snapshot, m.coordinate, geo.size))
                    }
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "map").font(.system(size: 24, weight: .light)).foregroundStyle(p.textTertiary)
                        Text("Map tiles unavailable").font(.osCaption).foregroundStyle(p.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear { schedule(size: geo.size) }
            .onChange(of: regionKey) { _, _ in schedule(size: geo.size) }
            .onChange(of: geo.size) { _, new in schedule(size: new) }
        }
    }

    /// Snapshot points are in the image's own space (2× the view, origin bottom-left on macOS);
    /// the view is in points with a top-left origin.
    private func point(_ snap: MKMapSnapshotter.Snapshot, _ c: CLLocationCoordinate2D, _ size: CGSize) -> CGPoint {
        let raw = snap.point(for: c)
        let scale = snap.image.size.width > 0 ? size.width / snap.image.size.width : 0.5
        return CGPoint(x: raw.x * scale, y: size.height - raw.y * scale)
    }

    private func key(for size: CGSize) -> String { regionKey + String(format: "@%.0fx%.0f", size.width, size.height) }

    /// Debounced so a burst of camera/size changes at launch starts one snapshotter, not three.
    /// The key includes the view size: a snapshot taken before the panes settled would otherwise
    /// be stretched and its projected pin points would no longer match the tiles.
    private func schedule(size: CGSize) {
        guard size.width > 0, size.height > 0, takenKey != key(for: size) else { return }
        model.snapshotMapReady = false
        pendingTask?.cancel()
        let key = key(for: size)
        pendingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, key == self.key(for: size) else { return }
            takenKey = key
            take(size: size, key: key, scale: 2)
        }
    }

    private func take(size: CGSize, key: String, scale: CGFloat) {
        let opts = MKMapSnapshotter.Options()
        opts.region = region
        opts.size = CGSize(width: size.width * scale, height: size.height * scale)
        opts.appearance = NSAppearance(named: p.isDark ? .darkAqua : .aqua)
        opts.pointOfInterestFilter = .excludingAll
        opts.mapType = style == .imagery ? .hybridFlyover : (style == .muted ? .mutedStandard : .standard)
        opts.showsBuildings = false
        let started = Date()
        MKMapSnapshotter(options: opts).start { snap, error in
            DispatchQueue.main.async {
                guard key == self.takenKey else { return }
                if let snap {
                    self.snapshot = snap
                    self.image = snap.image
                    self.failed = false
                    self.model.snapshotMapReady = true
                    FileHandle.standardError.write(Data(String(format: "[snapshot] map image ready in %.1f s\n", Date().timeIntervalSince(started)).utf8))
                } else if scale > 1 {
                    FileHandle.standardError.write(Data("[snapshot] map snapshotter failed (\(error?.localizedDescription ?? "?")) — retrying at 1×\n".utf8))
                    self.take(size: size, key: key, scale: 1)
                } else {
                    FileHandle.standardError.write(Data("[snapshot] map snapshotter failed twice (\(error?.localizedDescription ?? "?"))\n".utf8))
                    self.failed = true
                    self.model.snapshotMapReady = true
                }
            }
        }
    }
}
