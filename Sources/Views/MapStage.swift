import SwiftUI
import MapKit

/// Centre pane: the map as an instrument in a bezel, with strip, toasts and banners (DESIGN.md §1, §5).
struct MapStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var dragPoint: CGPoint? = nil
    @State private var dragUDID: String? = nil
    @State private var hoverPoint: CGPoint? = nil
    @State private var placements: [String: ChipPlacement] = [:]
    @State private var mapSize: CGSize = .zero

    private var useStaticMap: Bool { Env.isSnapshot && !Env.snapshotLiveMap }

    var body: some View {
        @Bindable var m = model
        ZStack {
            p.bgField
            Group {
                if useStaticMap {
                    SnapshotMapView(region: staticRegion, style: model.settings.mapStyle)
                } else {
                    liveMap
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.bezel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.bezel, style: .continuous).stroke(p.hairline, lineWidth: 1))
            .padding(Space.s)

            // overlays
            VStack(spacing: 0) {
                MapBanner().padding(.horizontal, Space.l).padding(.top, Space.l)
                Spacer()
                ToastStack().padding(.bottom, Space.s)
                TelemetryStrip().padding(.horizontal, Space.l).padding(.bottom, Space.l)
            }
        }
        .coordinateSpace(.named("map"))
        .onKeyPress(.escape) { model.select(.fleet); return .handled }
    }

    private var staticRegion: MKCoordinateRegion {
        if let r = model.camera.region { return r }
        if let c = model.camera.camera {
            let metres = c.distance
            let latDelta = metres / 111_000
            return MKCoordinateRegion(center: c.centerCoordinate,
                                      span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: latDelta * 1.6))
        }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 44.67, longitude: -63.58),
                                  span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
    }

    private var liveMap: some View {
        @Bindable var m = model
        return MapReader { proxy in
            Map(position: $m.camera, interactionModes: .all) {
                ForEach(model.pinItems) { item in
                    Annotation(item.handle, coordinate: item.coordinate, anchor: .center) {
                        pin(item, proxy: proxy)
                    }
                    .annotationTitles(.hidden)
                }
                if let mac = model.myLocation {
                    Annotation("This Mac", coordinate: mac.coordinate, anchor: .center) {
                        MacPinView(label: model.macChipLabel, handles: model.realGPSHandles)
                    }
                    .annotationTitles(.hidden)
                }
                if let r = model.selectedRecord, let c = r.desired ?? r.candidate {
                    let radius = model.draggingScatter[r.udid] ?? r.scatter
                    if radius > 0 {
                        MapCircle(center: c.coordinate, radius: radius)
                            .foregroundStyle(p.violet.opacity(0.12))
                            .stroke(p.violet.opacity(0.6), lineWidth: 1)
                    }
                }
            }
            .mapStyle(mapStyle)
            .mapControls { MapCompass(); MapScaleView() }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0; recomputePlacements(proxy) }
            .onMapCameraChange(frequency: .continuous) { _ in recomputePlacements(proxy) }
            .onChange(of: model.pinItems.map { "\($0.udid)\($0.lat)\($0.lon)" }.joined()) { _, _ in recomputePlacements(proxy) }
            .onTapGesture { point in
                guard let r = model.selectedRecord, r.mode == .manual, let c = proxy.convert(point, from: .local) else { return }
                model.setManualTarget(r.udid, Target(c))
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let pt): model.hoverCoordinate = proxy.convert(pt, from: .local)
                case .ended: model.hoverCoordinate = nil
                }
            }
            .overlay {
                if let pt = dragPoint, let udid = dragUDID, let r = model.record(udid) {
                    let c = proxy.convert(pt, from: .local)
                    PinView(item: PinItem(udid: udid, handle: r.handleBare, lat: c?.latitude ?? 0, lon: c?.longitude ?? 0, kind: .draft),
                            selected: true, dim: false, dragging: true,
                            liveText: c.map { Fmt.coord($0.latitude, $0.longitude) })
                        .position(pt)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Project every pin to screen points and fan out the chips of pins that would collide (§5 overlap).
    private func recomputePlacements(_ proxy: MapProxy) {
        let pts = model.pinItems.compactMap { item -> PinLayout.Item? in
            guard let pt = proxy.convert(item.coordinate, to: .local) else { return nil }
            return PinLayout.Item(id: item.udid, point: pt, chipWidth: PinLayout.chipWidth(for: item.chipText))
        }
        let next = PinLayout.placements(pts, in: mapSize == .zero ? nil : mapSize)
        if next != placements { placements = next }
    }

    private func pin(_ item: PinItem, proxy: MapProxy) -> some View {
        let selected = model.route.udid == item.udid
        let draggable = selected && (model.record(item.udid)?.mode == .manual)
        return PinView(item: item, selected: selected, dim: model.route == .fleet ? false : !selected,
                       placement: placements[item.udid] ?? .below)
            .opacity(dragUDID == item.udid && dragPoint != nil ? 0.3 : 1)
            .onTapGesture { model.select(.phone(item.udid)) }
            .highPriorityGesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named("map"))
                    .onChanged { v in
                        guard draggable else { return }
                        dragUDID = item.udid
                        dragPoint = mapLocal(v.location)
                    }
                    .onEnded { v in
                        defer { dragPoint = nil; dragUDID = nil }
                        guard draggable, let c = proxy.convert(mapLocal(v.location), from: .local) else { return }
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                            model.setManualTarget(item.udid, Target(c))
                        }
                    },
                including: draggable ? .all : .subviews)
            .zIndex(item.zIndex + (selected ? 10 : 0))
    }

    /// The map view is inset 8pt in the stage's named space.
    private func mapLocal(_ pt: CGPoint) -> CGPoint { CGPoint(x: pt.x - Space.s, y: pt.y - Space.s) }

    private var mapStyle: MapStyle {
        switch model.settings.mapStyle {
        case .muted: .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)
        case .standard: .standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false)
        case .imagery: .hybrid(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false)
        }
    }
}

// MARK: - Map banner (engine stopped / didn't start) §4.11

struct MapBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    var body: some View {
        Group {
            if case .engineDead(let code) = model.phase {
                banner(text: (model.engineRestartIn ?? 0) > 0 ? "Engine stopped (exit \(code)) — restarting in \(model.engineRestartIn ?? 0) s" : "Engine stopped (exit \(code))", actions: [("Restart", { model.restartEngine() }), ("Show log", { AppDelegate.shared.showEngineLog() })])
            } else if model.phase == .engineStarting && model.engineFailed {
                banner(text: "Engine didn't start", actions: [("Retry", { model.restartEngine() }), ("Show log", { AppDelegate.shared.showEngineLog() })])
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func banner(text: String, actions: [(String, () -> Void)]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.octagon").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.error)
            Text(text).font(.osHeader).foregroundStyle(p.textPrimary).lineLimit(1)
            Spacer(minLength: 8)
            ForEach(actions, id: \.0) { a in
                Button(a.0, action: a.1).buttonStyle(SecondaryButtonStyle(compact: true))
            }
        }
        .padding(Space.m)
        .background {
            ZStack(alignment: .leading) {
                GlassBackground(shape: RoundedRectangle(cornerRadius: Radius.card, style: .continuous), tint: p.pillError)
                RoundedRectangle(cornerRadius: 1.5).fill(p.error).frame(width: 3).padding(.vertical, 8).padding(.leading, 6)
            }
        }
        .cardShadow(p)
        .frame(maxWidth: 720)
    }
}
