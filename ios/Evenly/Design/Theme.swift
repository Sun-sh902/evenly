import SwiftUI
import UIKit

// Design tokens shared with the web app (public/styles.css).

extension Color {
    static let paper = Color(light: 0xF5F3EE, dark: 0x111214)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1B1C20)
    static let surface2 = Color(light: 0xF0EDE6, dark: 0x232429)
    static let fieldBackground = Color(light: 0xFBFAF7, dark: 0x16171A)
    static let line = Color(light: 0xE4E0D6, dark: 0x2C2D33)
    static let lineStrong = Color(light: 0xD3CEC1, dark: 0x3A3B42)
    static let ink = Color(light: 0x16181D, dark: 0xF1EFE9)
    static let ink2 = Color(light: 0x4A4D55, dark: 0xB7B6B1)
    static let ink3 = Color(light: 0x8A8C92, dark: 0x7D7D80)
    static let brand = Color(light: 0x1D6B52, dark: 0x7FD1A8)
    static let brandInk = Color(light: 0xFFFFFF, dark: 0x0E1F17)
    static let brandSoft = Color(light: 0xDCEFE6, dark: 0x1D3A2D)
    static let pos = Color(light: 0x1D7A58, dark: 0x7FD1A8)
    static let posSoft = Color(light: 0xD8EEE3, dark: 0x1D3A2D)
    static let neg = Color(light: 0xC4502F, dark: 0xF0927A)
    static let negSoft = Color(light: 0xF6E0D7, dark: 0x3F2620)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Palette {
    static let members: [UInt32] = [0x2F7FD8, 0xD0573B, 0x1D8A63, 0x8D5BD6, 0xC98A12, 0xD0467F, 0x2B9BB0, 0x6B7D26, 0xB5562B, 0x4C63D2]
    static func member(_ index: Int) -> Color { Color(hex: members[abs(index) % members.count]) }
}

struct CategoryStyle {
    let label: String
    let symbol: String
    let color: Color

    static func of(_ key: String) -> CategoryStyle {
        switch key {
        case "food": CategoryStyle(label: t("Food & drink"), symbol: "fork.knife", color: Color(hex: 0xD9822B))
        case "groceries": CategoryStyle(label: t("Groceries"), symbol: "basket", color: Color(hex: 0x5F9A2C))
        case "transport": CategoryStyle(label: t("Transport"), symbol: "car", color: Color(hex: 0x2F7FD8))
        case "stay": CategoryStyle(label: t("Stay"), symbol: "bed.double", color: Color(hex: 0x8D5BD6))
        case "fun": CategoryStyle(label: t("Fun"), symbol: "ticket", color: Color(hex: 0xD0467F))
        case "utilities": CategoryStyle(label: t("Bills"), symbol: "bolt", color: Color(hex: 0xC8A21A))
        case "shopping": CategoryStyle(label: t("Shopping"), symbol: "bag", color: Color(hex: 0x2B9BB0))
        case "transfer": CategoryStyle(label: t("Settlement"), symbol: "arrow.left.arrow.right", color: Color(hex: 0x1D8A63))
        default: CategoryStyle(label: t("General"), symbol: "doc.text", color: Color(hex: 0x7A7F8C))
        }
    }
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
    static func amount(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Reusable modifiers

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.line))
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardModifier(padding: padding)) }

    func sectionTitle() -> some View {
        font(.system(size: 12, weight: .semibold)).tracking(0.8).textCase(.uppercase).foregroundStyle(Color.ink3)
    }

    func fieldStyle() -> some View {
        padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.line))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .ink
    var foreground: Color = .paper
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, 22)
            .frame(minHeight: 52)
            .background(tint, in: Capsule())
            .foregroundStyle(foreground)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 18)
            .frame(minHeight: 46)
            .background(Color.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.line))
            .foregroundStyle(Color.ink)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
