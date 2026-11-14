import SwiftUI
import CoreMotion
import UIKit

// MARK: - Haptics

/// One long-lived generator, woken ahead of time. A feedback generator used cold has to
/// spin up the Taptic Engine on the main thread, which cost visible frames on a real iPhone.
@MainActor
enum Haptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    /// Call when a gesture begins (touch-down) so the engine is ready by the time it fires.
    static func prepareSelection() { selectionGenerator.prepare() }

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }
}

// MARK: - Rolling number

/// A number whose digits roll like an odometer when the value changes. Each digit
/// sits on its own wheel; the top and bottom edges fade so digits slide in from
/// inside the line instead of popping. With Reduce Motion it crossfades instead.
struct RollingNumber: View {
    let text: String
    var size: CGFloat
    var weight: Font.Weight = .regular
    var design: Font.Design = .serif
    var tracking: CGFloat = 0
    /// The colour behind the number, used for the fade at the wheel edges.
    var fade: Color = .paper

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Cell: Equatable, Identifiable {
        /// Counted from the right, so the ones digit keeps its identity when the number grows.
        let id: Int
        let char: Character
        var digit: Int? { char.isASCII ? char.wholeNumberValue : nil }
    }

    static func cells(_ text: String) -> [Cell] {
        let chars = Array(text)
        return chars.enumerated().map { Cell(id: chars.count - 1 - $0.offset, char: $0.element) }
    }

    /// How far to pull the number left so its ink lines up with text above it. Only a
    /// leading sign carries noticeable side bearing in the serif (~5.4% of the size);
    /// currency symbols such as "¥" and "$" already sit on the edge.
    static func opticalInset(for text: String, size: CGFloat) -> CGFloat {
        guard let first = text.first, "+-−".contains(first) else { return 0 }
        return size * 0.054
    }

    /// Shrinks long amounts so they stay on one line without truncating.
    static func fittedSize(for text: String, base: CGFloat = 56, comfortable: Int = 10, minimum: CGFloat = 32) -> CGFloat {
        guard text.count > comfortable else { return base }
        return max(minimum, base - CGFloat(text.count - comfortable) * base * 0.08)
    }

    var body: some View {
        let font = Font.system(size: size, weight: weight, design: design).monospacedDigit()
        let line = (size * 1.22).rounded()
        Group {
            if reduceMotion {
                Text(text).font(font).tracking(tracking)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: text)
            } else {
                HStack(spacing: 0) {
                    ForEach(Self.cells(text)) { cell in
                        if let d = cell.digit {
                            DigitWheel(digit: d, font: font, line: line)
                        } else {
                            Text(String(cell.char)).font(font).frame(height: line)
                        }
                    }
                }
                .tracking(tracking)
                // Digits slide in from behind a fade in the page colour at the top and bottom.
                // An overlay rather than a mask: a mask is re-composited off-screen on every
                // frame anything else on the screen animates.
                .overlay(alignment: .top) {
                    LinearGradient(colors: [fade, fade.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: line * 0.2)
                }
                .overlay(alignment: .bottom) {
                    // Thinner than the top fade: the comma's tail reaches down into this band.
                    LinearGradient(colors: [fade.opacity(0), fade], startPoint: .top, endPoint: .bottom)
                        .frame(height: line * 0.1)
                }
                .allowsHitTesting(false)
                .animation(.spring(response: 0.55, dampingFraction: 1), value: text)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct DigitWheel: View {
    let digit: Int
    let font: Font
    let line: CGFloat

    var body: some View {
        Text("0").font(font).hidden().frame(height: line)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { Text("\($0)").font(font).frame(height: line) }
                }
                .offset(y: -CGFloat(digit) * line)
            }
            .clipped()
    }
}

// MARK: - Device tilt

/// Smoothed device tilt in -1...1, shared by every card's sheen. Updates only while
/// something on screen is using it.
@MainActor
@Observable
final class DeviceTilt {
    static let shared = DeviceTilt()

    private(set) var x: Double = 0
    private(set) var y: Double = 0

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var users = 0

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated { self?.apply(motion.attitude) }
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { manager.stopDeviceMotionUpdates() }
    }

    private func apply(_ a: CMAttitude) {
        // Held naturally the phone leans back about 40°, so that is the resting point.
        let tx = max(-1, min(1, a.roll / 0.6))
        let ty = max(-1, min(1, (a.pitch - 0.7) / 0.6))
        let nx = x + (tx - x) * 0.12
        let ny = y + (ty - y) * 0.12
        // Every write redraws every card's sheen, so ignore movement too small to see
        // (about a third of a point). A phone lying still then costs no redraws at all.
        if abs(nx - x) > 0.002 || abs(ny - y) > 0.002 { x = nx; y = ny }
    }
}

/// A faint band of light across an ink card that drifts as the phone tilts,
/// the way light moves over a real card. Still when Reduce Motion is on.
struct CardSheen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tilt = DeviceTilt.shared
        let dx = reduceMotion ? 0 : tilt.x
        let dy = reduceMotion ? 0 : tilt.y
        GeometryReader { g in
            LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.32),
                                   .init(color: .white.opacity(0.055), location: 0.5),
                                   .init(color: .white.opacity(0), location: 0.68)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: g.size.width * 2, height: max(g.size.height, 260))
                .offset(x: -g.size.width * 0.5 + CGFloat(dx) * g.size.width * 0.4,
                        y: CGFloat(dy) * 30 - 20)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Once-a-day reveal

enum DailyReveal {
    static let key = "evenly.home.revealedDay"

    static func today(_ now: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// True the first time this is asked on a given day; it then remembers the day.
    static func claim(_ defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        let day = today(now)
        guard defaults.string(forKey: key) != day else { return false }
        defaults.set(day, forKey: key)
        return true
    }
}
