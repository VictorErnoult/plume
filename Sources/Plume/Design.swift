import AppKit
import CoreText
import SwiftUI

/// Art direction of the window. The base comes from the soyakil.fr portfolio:
/// neutral grays, Geist, radius of 8, drawn keyboard keys, floating bar at the bottom,
/// line icons, a discreet sound on every gesture. No accent color: what must stand
/// out takes the text color (white in dark, near black in light). A touch
/// of play and motion: streaks, records, activity, counters.
enum UI {
    // MARK: Colors

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        func make(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? make(dark, darkAlpha) : make(light, lightAlpha)
            })
    }

    // The portfolio's six grays, from the background to the foreground.
    static let window = dynamic(light: 0xF7F7F7, dark: 0x0F0F0F)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x151515)
    static let raised = dynamic(light: 0xF1F1F1, dark: 0x1B1B1B)
    static let line = dynamic(light: 0xE6E6E6, dark: 0x242424)
    /// Background of the bar's active entry, outline of the keys.
    static let active = dynamic(light: 0xD9D9D9, dark: 0x2F2F2F)
    static let hover = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.055)
    static let selected = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.075, darkAlpha: 0.09)
    static let text = dynamic(light: 0x292929, dark: 0xEDEDED)
    static let text2 = dynamic(light: 0x5D5D5D, dark: 0xA1A1A1)
    static let text3 = dynamic(light: 0x9E9E9E, dark: 0x6E6E6E)
    /// Text set on a solid button (which takes the text color).
    static let onText = dynamic(light: 0xFFFFFF, dark: 0x111111)
    static let success = Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)
    /// "beta" label: a mauve, readable on both backgrounds.
    static let beta = dynamic(light: 0x7C4DCC, dark: 0xC9A7FF)
    /// Activity intensity, from weakest to strongest: from discreet gray to the text color.
    static let activity: [Color] = [
        dynamic(light: 0xD0D0D0, dark: 0x3A3A3A),
        dynamic(light: 0x9E9E9E, dark: 0x6E6E6E),
        dynamic(light: 0x5D5D5D, dark: 0xA1A1A1),
        text,
    ]

    static let radius: CGFloat = 8
    static let pagePadding: CGFloat = 36
    /// Space left at the bottom of each page for the floating bar.
    static let dockClearance: CGFloat = 96

    // MARK: Motion

    /// Sharp deceleration: starts fast, settles softly.
    static let ease = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.38)
    static let quick = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.2)
    static let spring = Animation.spring(duration: 0.38, bounce: 0.22)

    // MARK: Typography

    private static var cache: [String: Font] = [:]

    private static func variable(_ family: String, _ size: CGFloat, _ weight: Font.Weight) -> Font? {
        let value: CGFloat
        switch weight {
        case .medium: value = 500
        case .semibold: value = 600
        case .bold, .heavy, .black: value = 700
        default: value = 400
        }
        let key = "\(family)-\(size)-\(value)"
        if let font = cache[key] { return font }
        let weightAxis = 2_003_265_652  // "wght"
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .variation: [weightAxis: value],
        ])
        guard let font = NSFont(descriptor: descriptor, size: size).map({ Font($0) }) else { return nil }
        cache[key] = font
        return font
    }

    /// Variable-weight Geist; system font if it could not be loaded.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard Fonts.available, let font = variable("Geist", size, weight) else { return .system(size: size, weight: weight) }
        return font
    }

    /// Geist Mono, for durations and aligned numbers.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard Fonts.available, let font = variable("Geist Mono", size, weight) else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return font
    }
}

extension Bundle {
    /// `Resources/<name>` folder of the repo, when the binary is launched from `.build` rather
    /// than from the app: we walk up from the executable to `Package.swift`. No path
    /// of the build machine is thus written into the binary.
    static func repositoryResource(_ name: String) -> URL? {
        var directory = main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        while let current = directory, current.path != "/" {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("Package.swift").path) {
                return current.appendingPathComponent("Resources/\(name)", isDirectory: true)
            }
            directory = current.deletingLastPathComponent()
        }
        return nil
    }
}

/// Loading of the embedded fonts (free SIL OFL license).
enum Fonts {
    private(set) static var available = false

    static func register() {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true)
        // Binary launched outside the app (development): the fonts are in the repo.
        let development = Bundle.repositoryResource("Fonts")
        for directory in [bundled, development].compactMap({ $0 }) {
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            else { continue }
            for url in files where url.pathExtension == "ttf" {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            if NSFontManager.shared.availableFontFamilies.contains("Geist") { break }
        }
        available = NSFontManager.shared.availableFontFamilies.contains("Geist")
    }
}

// MARK: - Components

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var fill: Color = UI.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).strokeBorder(UI.line, lineWidth: 1))
    }
}

/// Everything clickable sinks slightly under the finger.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

struct PlumeButton: View {
    enum Kind { case primary, secondary, ghost }

    var title: String?
    var icon: Glyph?
    var kind: Kind = .secondary
    var help: String?
    /// Sound played on click; by default, only solid buttons sound.
    var sound: Sounds.Kind?
    var action: () -> Void
    @State private var hovering = false

    private var foreground: Color {
        kind == .primary ? UI.onText : UI.text
    }

    private var background: Color {
        switch kind {
        case .primary: return UI.text.opacity(hovering ? 0.86 : 1)
        case .secondary: return hovering ? UI.selected : UI.hover
        case .ghost: return hovering ? UI.hover : .clear
        }
    }

    var body: some View {
        Button {
            if let sound = sound ?? (kind == .primary ? .click : nil) { Sounds.play(sound) }
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Icon(icon, size: 14)
                        .id(icon)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
                if let title { Text(title).font(UI.sans(13, .medium)) }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, title == nil ? 9 : 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(background))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover {
            hovering = $0
            if $0 { Sounds.hover(.hoverButton) }
        }
        .animation(UI.quick, value: hovering)
        .help(help ?? title ?? "")
    }
}

/// Switch: when on, it takes the text color; the knob slides with a slight bounce.
struct PlumeSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            Sounds.play(configuration.isOn ? .toggleOff : .toggleOn)
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? UI.text : UI.active)
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? UI.onText : Color.white)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .padding(2.5)
                }
                .animation(.spring(duration: 0.28, bounce: 0.3), value: configuration.isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A keyboard key, drawn as on the portfolio.
struct Keycap: View {
    var label: String

    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(UI.sans(11, .medium))
            .foregroundStyle(UI.text)
            .padding(.horizontal, 5)
            .frame(minWidth: 20)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(UI.raised))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(UI.active, lineWidth: 1))
            // The thicker bottom edge gives the key its thickness.
            .overlay(alignment: .bottom) {
                UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5, style: .continuous)
                    .fill(UI.active)
                    .frame(height: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// A shortcut written as keys: one key per modifier, one for the rest.
struct Keycaps: View {
    var shortcut: String

    private var keys: [String] {
        var keys: [String] = []
        var rest = ""
        for character in shortcut {
            if "⌃⌥⇧⌘".contains(character) { keys.append(String(character)) } else { rest.append(character) }
        }
        if !rest.isEmpty { keys.append(rest) }
        return keys
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in Keycap(key) }
        }
    }
}

/// Number that counts up to its value when it appears or changes.
struct CountingText: View, Animatable {
    var value: Double
    var format: (Double) -> String

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
    }
}

/// Appearance of a block: it rises a few points as it is revealed, with a delay
/// proportional to its rank for a cascade effect.
struct Rise: ViewModifier {
    var index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                withAnimation(UI.ease.delay(Double(index) * 0.045)) { shown = true }
            }
    }
}

extension View {
    func rise(_ index: Int = 0) -> some View { modifier(Rise(index: index)) }

    /// Discreet sound when the pointer arrives on the element.
    func hoverSound(_ kind: Sounds.Kind) -> some View {
        onHover { if $0 { Sounds.hover(kind) } }
    }
}
