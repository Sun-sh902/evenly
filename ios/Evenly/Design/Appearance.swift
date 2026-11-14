import SwiftUI
import UIKit

/// Light, dark, or whatever the iPhone is set to.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: t("Automatic")
        case .light: t("Light")
        case .dark: t("Dark")
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Owns the app's light/dark choice. It sets the style on the window itself, so
/// sheets and alerts follow too, and animates the switch: the new look spreads out
/// in a circle from where you tapped. With Reduce Motion it crossfades instead.
@MainActor
@Observable
final class AppearanceController {
    static let shared = AppearanceController()
    static let key = "evenly.appearance"

    private(set) var choice: AppAppearance
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choice = defaults.string(forKey: Self.key).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    /// Call once the window exists so a saved choice applies from the first frame on.
    func applySaved() {
        Self.window?.overrideUserInterfaceStyle = choice.style
    }

    /// - Parameter origin: where the reveal starts, in window coordinates.
    func select(_ new: AppAppearance, from origin: CGPoint?, reduceMotion: Bool) {
        guard new != choice else { return }
        choice = new
        defaults.set(new.rawValue, forKey: Self.key)

        guard let window = Self.window else { return }
        let before = window.traitCollection.userInterfaceStyle
        let after = new.style == .unspecified ? window.windowScene?.screen.traitCollection.userInterfaceStyle ?? before : new.style
        // Nothing visible changes (e.g. Light → Automatic during the day): no animation needed.
        guard before != after else { window.overrideUserInterfaceStyle = new.style; return }

        if reduceMotion {
            UIView.transition(with: window, duration: 0.3, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                window.overrideUserInterfaceStyle = new.style
            }
            return
        }

        guard let snapshot = window.snapshotView(afterScreenUpdates: false) else {
            window.overrideUserInterfaceStyle = new.style
            return
        }
        window.addSubview(snapshot)
        window.overrideUserInterfaceStyle = new.style

        // The old look stays on top with a growing hole cut out of it.
        let bounds = window.bounds
        let center = origin ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = Self.coveringRadius(from: center, in: bounds)
        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        mask.frame = bounds
        let start = Self.holePath(in: bounds, center: center, radius: 0.1)
        let end = Self.holePath(in: bounds, center: center, radius: radius)
        mask.path = end
        snapshot.layer.mask = mask

        CATransaction.begin()
        CATransaction.setCompletionBlock { snapshot.removeFromSuperview() }
        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = start
        grow.toValue = end
        grow.duration = 0.55
        // Strong ease-out: quick to answer the tap, gentle as it reaches the edges.
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        mask.add(grow, forKey: "reveal")
        CATransaction.commit()
    }

    /// The radius that reaches the farthest corner, so the circle always covers the screen.
    nonisolated static func coveringRadius(from p: CGPoint, in rect: CGRect) -> CGFloat {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        return corners.map { hypot($0.x - p.x, $0.y - p.y) }.max() ?? 0
    }

    private static func holePath(in rect: CGRect, center: CGPoint, radius: CGFloat) -> CGPath {
        let path = UIBezierPath(rect: rect)
        path.append(UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true))
        return path.cgPath
    }

    private static var window: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ??
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first }.first
    }
}

/// Three options in one track; the selection slides between them.
struct AppearancePicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumb
    @State private var frames: [AppAppearance: CGRect] = [:]

    var body: some View {
        let controller = AppearanceController.shared
        HStack(spacing: 4) {
            ForEach(AppAppearance.allCases) { option in
                let selected = controller.choice == option
                Button {
                    let f = frames[option]
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 1)) {
                        controller.select(option, from: f.map { CGPoint(x: $0.midX, y: $0.midY) }, reduceMotion: reduceMotion)
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.symbol)
                            .font(.system(size: 18, weight: .medium))
                            .symbolEffect(.bounce, value: selected)
                        Text(option.label).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(selected ? Color.ink : Color.ink3)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(light: 0xFFFFFF, dark: 0x5B5B60))
                                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PickerPressStyle())
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .background(GeometryReader { g in
                    Color.clear.onAppear { frames[option] = g.frame(in: .global) }
                        .onChange(of: g.frame(in: .global)) { _, f in frames[option] = f }
                })
            }
        }
        .padding(4)
        // Same track as the system segmented control further down the form.
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .sensoryFeedback(.selection, trigger: controller.choice)
    }
}

private struct PickerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 1), value: configuration.isPressed)
    }
}
