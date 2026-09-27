import SwiftUI
import AppKit

// MARK: - Color helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - Palette (DESIGN.md §3a / §3b)

struct Palette {
    let bgWindow: Color
    let bgField: Color
    let panel: Color
    let raised: Color
    let selected: Color
    let hairline: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textMono: Color
    let textHint: Color
    let blue: Color
    let violet: Color
    let magenta: Color
    let blueText: Color
    let violetText: Color
    let magentaText: Color
    let busy: Color
    let error: Color
    let ok: Color
    let off: Color
    let focus: Color
    let pillSpoofed: Color
    let pillBusy: Color
    let pillError: Color
    let pillOff: Color
    let pillBlue: Color
    let chipLabel: Color
    let fieldLobeOpacity: Double
    let isDark: Bool

    static let dark = Palette(
        bgWindow: Color(hex: 0x0E1118), bgField: Color(hex: 0x0B0E14),
        panel: Color(hex: 0x141925), raised: Color(hex: 0x1B2130), selected: Color(hex: 0x242148),
        hairline: Color(hex: 0x262D3D),
        textPrimary: Color(hex: 0xF2F4F8), textSecondary: Color(hex: 0xA9B1C3), textTertiary: Color(hex: 0x848C9C),
        textMono: Color(hex: 0xC8CEDA), textHint: Color(hex: 0x5A6378),
        blue: Color(hex: 0x2D7DFF), violet: Color(hex: 0x764AFF), magenta: Color(hex: 0xAB31FF),
        blueText: Color(hex: 0x5C9BFF), violetText: Color(hex: 0x9A7DFF), magentaText: Color(hex: 0xC466FF),
        busy: Color(hex: 0xFFB340), error: Color(hex: 0xFF5A5F), ok: Color(hex: 0x37D67A), off: Color(hex: 0x848C9C),
        focus: Color(hex: 0x5C9BFF),
        pillSpoofed: Color(hex: 0x26224C), pillBusy: Color(hex: 0x352F29), pillError: Color(hex: 0x35222D),
        pillOff: Color(hex: 0x242936), pillBlue: Color(hex: 0x182948),
        chipLabel: Color(hex: 0x0E1118, opacity: 0.85),
        fieldLobeOpacity: 0.16, isDark: true)

    static let light = Palette(
        bgWindow: Color(hex: 0xF2F3F7), bgField: Color(hex: 0xEAECF2),
        panel: Color(hex: 0xFFFFFF), raised: Color(hex: 0xF7F8FB), selected: Color(hex: 0xEFE9FF),
        hairline: Color(hex: 0xDCE0EA),
        textPrimary: Color(hex: 0x111420), textSecondary: Color(hex: 0x48506A), textTertiary: Color(hex: 0x5F6983),
        textMono: Color(hex: 0x3A4150), textHint: Color(hex: 0x9AA3B8),
        blue: Color(hex: 0x2D7DFF), violet: Color(hex: 0x764AFF), magenta: Color(hex: 0xAB31FF),
        blueText: Color(hex: 0x1A62D2), violetText: Color(hex: 0x5D3DE0), magentaText: Color(hex: 0x8F1FD6),
        busy: Color(hex: 0x8F5200), error: Color(hex: 0xC4262E), ok: Color(hex: 0x157A45), off: Color(hex: 0x5F6983),
        focus: Color(hex: 0x1A62D2),
        pillSpoofed: Color(hex: 0xEFE9FF), pillBusy: Color(hex: 0xF2EAE0), pillError: Color(hex: 0xF8E5E6),
        pillOff: Color(hex: 0xECEDF0), pillBlue: Color(hex: 0xE3EFE9),
        chipLabel: Color(hex: 0xFFFFFF, opacity: 0.92),
        fieldLobeOpacity: 0.10, isDark: false)

    static func current(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }

    // Gradients (§3a): light = paint for the five permitted places; lamp = primary button fill only.
    var gradientLight: LinearGradient {
        LinearGradient(colors: [blue, violet, magenta], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var gradientLamp: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x2468E6), Color(hex: 0x6740E8), Color(hex: 0x9429E6)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var gradientRing: AngularGradient {
        AngularGradient(colors: [blue, violet, magenta, blue], center: .center)
    }
}

// Environment plumbing so every view reads `@Environment(\.palette)`.
private struct PaletteKey: EnvironmentKey { static let defaultValue: Palette = .dark }
extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Type scale (§3d)

extension Font {
    static let osDisplay = Font.system(size: 28, weight: .semibold)
    static let osCounter = Font.system(size: 26, weight: .semibold).monospacedDigit()
    static let osTitle = Font.system(size: 17, weight: .semibold)
    static let osHeader = Font.system(size: 15, weight: .semibold)
    static let osRowTitle = Font.system(size: 13, weight: .semibold)
    static let osBody = Font.system(size: 13, weight: .regular)
    static let osLabel = Font.system(size: 13, weight: .semibold)
    static let osMeta = Font.system(size: 12, weight: .regular)
    static let osSection = Font.system(size: 11, weight: .semibold)
    static let osCaption = Font.system(size: 11, weight: .regular)
    static let osPill = Font.system(size: 11, weight: .semibold)
    static let osMono = Font.system(size: 12, weight: .regular, design: .monospaced).monospacedDigit()
    static let osMonoSmall = Font.system(size: 11, weight: .regular, design: .monospaced).monospacedDigit()
    static let osTextButton = Font.system(size: 12, weight: .medium)
}

// MARK: - Spacing, radii (§3c)

enum Space {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 20, xxl: CGFloat = 24, xxxl: CGFloat = 32
}
enum Radius {
    static let row: CGFloat = 6, control: CGFloat = 8, bezel: CGFloat = 10, card: CGFloat = 12, sheetCard: CGFloat = 14
}

// MARK: - Section label

struct SectionLabel: View {
    @Environment(\.palette) private var p
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.osSection)
            .tracking(0.6)
            .foregroundStyle(p.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Materials (§3f)

/// Pane background: regular material tinted with surface.panel at 55 %; solid under Reduce Transparency.
struct PaneMaterial: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            p.panel
        } else {
            ZStack {
                Rectangle().fill(.regularMaterial)
                p.panel.opacity(0.55)
            }
        }
    }
}

/// Glass card: Liquid Glass on macOS 26, ultraThinMaterial + hairline + card shadow before.
struct GlassCard<Content: View>: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = Radius.card
    var padding: CGFloat = Space.m
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content()
            .padding(padding)
            .background {
                if reduceTransparency {
                    shape.fill(tint ?? p.panel)
                } else if #available(macOS 26.0, *), !Env.isSnapshot {
                    shape.fill(.clear).glassEffect(.regular.tint((tint ?? p.panel).opacity(0.6)), in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                    shape.fill((tint ?? p.panel).opacity(0.5))
                }
            }
            .overlay(shape.stroke(p.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(p.isDark ? 0.35 : 0.12), radius: 12, x: 0, y: 8)
    }
}

// MARK: - Shadows (§3c)

extension View {
    func cardShadow(_ p: Palette) -> some View { shadow(color: .black.opacity(p.isDark ? 0.35 : 0.14), radius: 12, x: 0, y: 8) }
    func toastShadow(_ p: Palette) -> some View { shadow(color: .black.opacity(p.isDark ? 0.45 : 0.18), radius: 12, x: 0, y: 8) }
    func lampGlow(_ p: Palette, hover: Bool = false, on: Bool = true) -> some View {
        shadow(color: p.violet.opacity(on ? (hover ? 0.45 : 0.35) : 0), radius: hover ? 10 : 8, x: 0, y: 6)
    }
    func spoofGlow(_ p: Palette, radius: CGFloat = 8, opacity: Double = 0.55) -> some View {
        shadow(color: p.violet.opacity(opacity), radius: radius)
    }
}

// MARK: - Buttons (§4.8)
// Each style hands its configuration to an inner View so hover/press state has a stable identity.

struct PrimaryButtonStyle: ButtonStyle {
    var loading: Bool = false
    func makeBody(configuration: Configuration) -> some View { PrimaryButtonBody(configuration: configuration, loading: loading) }
}

private struct PrimaryButtonBody: View {
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let loading: Bool
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        let pressed = configuration.isPressed
        HStack(spacing: 6) {
            if loading { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14) }
            configuration.label
                .font(.osLabel)
                .lineLimit(1)
        }
        .foregroundStyle(isEnabled ? .white : p.textHint)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .background {
            if isEnabled {
                shape.fill(p.gradientLamp)
                    .brightness(pressed ? -0.08 : (hover ? 0.06 : 0))
            } else {
                shape.fill(p.raised)
            }
        }
        .overlay {
            if isEnabled { shape.stroke(p.gradientLight, lineWidth: 1).opacity(0.6) }
            else { shape.stroke(p.hairline, lineWidth: 1) }
        }
        .shadow(color: p.violet.opacity(isEnabled ? (pressed ? 0.25 : (hover ? 0.45 : 0.35)) : 0),
                radius: pressed ? 4 : (hover ? 10 : 8), x: 0, y: 6)
        .contentShape(shape)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var destructive: Bool = false
    var compact: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration, destructive: destructive, compact: compact)
    }
}

private struct SecondaryButtonBody: View {
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let destructive: Bool
    let compact: Bool
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        configuration.label
            .font(.osLabel)
            .lineLimit(1)
            .foregroundStyle(isEnabled ? (destructive ? p.error : p.textPrimary) : p.textHint)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(height: compact ? 26 : 32)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(shape.fill(p.raised).brightness(configuration.isPressed ? -0.05 : (hover ? 0.05 : 0)))
            .overlay(shape.stroke(p.hairline, lineWidth: 1))
            .contentShape(shape)
            .onHover { hover = $0 }
    }
}

struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TextButtonBody(configuration: configuration) }
}

private struct TextButtonBody: View {
    @Environment(\.palette) private var p
    let configuration: ButtonStyleConfiguration
    @State private var hover = false
    var body: some View {
        configuration.label
            .font(.osTextButton)
            .foregroundStyle(p.blueText)
            .underline(hover)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { IconButtonBody(configuration: configuration) }
}

private struct IconButtonBody: View {
    @Environment(\.palette) private var p
    let configuration: ButtonStyleConfiguration
    @State private var hover = false
    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(p.textSecondary)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(hover ? p.raised : .clear))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

// MARK: - Images from Contents/Resources (no asset catalog)

enum Theme {
    static let resourceURL: URL = Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")

    static let menuBarIcon: NSImage = {
        let img = NSImage(named: "MenuBarIcon")
            ?? NSImage(contentsOf: resourceURL.appendingPathComponent("MenuBarIcon.png"))
            ?? NSImage(systemSymbolName: "location.fill", accessibilityDescription: "Only Social GPS")!
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    static let markImage: NSImage? = {
        NSImage(named: "icon-mark") ?? NSImage(contentsOf: resourceURL.appendingPathComponent("icon-mark.png"))
    }()

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
    static var appBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }
}

// MARK: - Small shared views

struct MarkImage: View {
    @Environment(\.palette) private var p
    var size: CGFloat = 96
    var body: some View {
        Group {
            if let img = Theme.markImage {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(p.gradientLight)
            }
        }
        .frame(width: size, height: size)
        .spoofGlow(p, radius: 18, opacity: 0.5)
    }
}

/// Hairline divider in the palette colour.
struct Hairline: View {
    @Environment(\.palette) private var p
    var body: some View { Rectangle().fill(p.hairline).frame(height: 1) }
}

// MARK: - Formatting helpers

enum Fmt {
    static func coord(_ lat: Double, _ lon: Double, digits: Int = 4) -> String {
        String(format: "%.\(digits)f, %.\(digits)f", lat, lon)
    }
    static func metres(_ m: Double) -> String {
        if m <= 0 { return "exact" }
        if m < 1000 { return "\(Int(m)) m" }
        return String(format: "%.1f km", m / 1000)
    }
    static func ago(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s) s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 { return "\(s / 3600) h ago" }
        return "\(s / 86400) d ago"
    }
    static func clock(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
    static func localTime(in tz: String?) -> String {
        guard let tz, let zone = TimeZone(identifier: tz) else { return "" }
        let f = DateFormatter(); f.timeZone = zone; f.dateFormat = "HH:mm"; return f.string(from: Date())
    }
    static func regionAbbrev(_ region: String) -> String {
        let map = ["Nova Scotia": "NS", "Ontario": "ON", "Quebec": "QC", "British Columbia": "BC", "Alberta": "AB",
                   "New Brunswick": "NB", "Manitoba": "MB", "Saskatchewan": "SK", "Newfoundland and Labrador": "NL",
                   "Prince Edward Island": "PE", "England": "ENG", "Texas": "TX", "California": "CA", "New York": "NY",
                   "Florida": "FL", "Illinois": "IL", "Washington": "WA"]
        return map[region] ?? region
    }
    static func shortUDID(_ udid: String) -> String {
        udid.count > 14 ? String(udid.prefix(14)) + "…" : udid
    }
    static func flag(_ cc: String?) -> String {
        guard let cc, cc.count == 2 else { return "" }
        return cc.uppercased().unicodeScalars.compactMap { s -> String? in
            guard let u = UnicodeScalar(0x1F1E6 + s.value - 65) else { return nil }
            return String(u)
        }.joined()
    }
}
