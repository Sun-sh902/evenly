import SwiftUI

/// The home screen: your net balance in type, then your groups as a stack of
/// ink cards. Tap a card to open it in place; tap again to tuck it back.
struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showServer = false
    /// Which card is open. Kept in its own object so that opening a card redraws only the
    /// stack, not the whole home screen (balance, header, every digit) on the tap's frame.
    @State private var selection = WalletSelection()
    @State private var adding: AddTarget?
    @State private var savedTick = 0

    private var dashboard: Dashboard { app.dashboard() }

    /// One spring for the whole stack: critically damped, so it settles without wobble
    /// and picks up from wherever it is if tapped again mid-flight.
    private var stackAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 1)
    }

    var body: some View {
        @Bindable var app = app
        let d = dashboard
        let cards = walletItems(d)
        NavigationStack(path: $app.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if cards.isEmpty && !app.homeLoaded {
                        // First load still running (a few milliseconds): show nothing rather than the intro.
                        Color.clear.frame(height: 1)
                    } else if cards.isEmpty {
                        EmptyHome(isLocal: app.isLocal)
                            .padding(.top, 8)
                    } else {
                        // No logo or app name up here: people know which app they're in (Apple's
                        // branding guidance). The balance itself is the header, as in Weather.
                        BalanceSummary(dashboard: d)
                            .padding(.top, 4)
                        groupsHeader(count: cards.count)
                            .padding(.top, 34)
                            .padding(.bottom, 14)
                        WalletStack(items: cards, selection: selection) { item, index, isOpen, recede in
                            WalletCard(item: item, tone: WalletTone.at(index), isOpen: isOpen, recede: recede,
                                       onTap: { toggle(item.id) },
                                       onAdd: { add(item) },
                                       onOpen: { app.path = [item.id] })
                                .contextMenu { menu(for: item) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .background(Color.paper.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Color.paper.opacity(0), Color.paper.opacity(0.92), Color.paper],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) { floatingBar }
            // A system bar with no title: it carries only the settings control (Liquid Glass
            // on iOS 26) and gives the content a proper scroll-edge fade under the status bar.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showServer = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(t("Settings"))
                }
            }
            .navigationDestination(for: String.self) { GroupScreen(groupId: $0) }
            .sheet(isPresented: $showCreate) { CreateGroupView() }
            .sheet(isPresented: $showJoin) { JoinGroupView() }
            .sheet(isPresented: $showServer, onDismiss: { Task { await refresh() } }) { ServerSettingsView() }
            .sheet(item: $adding, onDismiss: { Task { await app.refreshHome() } }) { target in
                ExpenseEditor(store: target.store, group: target.group, entry: nil,
                              defaultPayer: app.me(in: target.group) ?? app.lastPayer(groupId: target.group.id)) { message in
                    savedTick += 1
                    app.pendingNotice = message
                }
            }
            .task(id: "\(app.mode.rawValue)|\(app.serverAddress)") { await refresh() }
            .onChange(of: app.path) { _, path in if path.isEmpty { Task { await app.refreshHome() } } }
            .onChange(of: cards.map(\.id)) { _, ids in
                if let e = selection.expanded, !ids.contains(e) { selection.expanded = nil }
            }
            .refreshable { await refresh() }
            .toast($app.pendingNotice)
            .sensoryFeedback(.success, trigger: savedTick)
        }
        .tint(.ink)
    }

    private func toggle(_ id: String) {
        // The generator was woken on touch-down, so this costs nothing on the tap's frame.
        Haptics.selection()
        // An explicit transaction animates everything the change moves, including the
        // footer below the stack (a value-scoped .animation only covered the stack itself).
        withAnimation(stackAnimation) {
            selection.expanded = selection.expanded == id ? nil : id
        }
    }

    private func add(_ item: WalletItem) {
        guard let g = item.snapshot else { app.path = [item.id]; return }
        adding = AddTarget(store: GroupStore(groupId: g.id, app: app), group: g)
    }

    @ViewBuilder
    private func menu(for item: WalletItem) -> some View {
        if item.snapshot != nil {
            Button { add(item) } label: { Label(t("Add expense"), systemImage: "plus") }
        }
        Button { app.path = [item.id] } label: { Label(t("View details"), systemImage: "arrow.up.right") }
        if !app.isLocal {
            Button(role: .destructive) {
                withAnimation(stackAnimation) { app.forget(item.id) }
            } label: { Label(t("Remove from this device"), systemImage: "minus.circle") }
        }
    }

    private func walletItems(_ d: Dashboard) -> [WalletItem] {
        if !d.groups.isEmpty { return d.groups.map(WalletItem.init) }
        // Server groups we couldn't load right now: show what this device remembers.
        return app.groupList.map(WalletItem.init)
    }

    // MARK: Groups header

    private func groupsHeader(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(t("Your groups")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink2)
            Text("\(count)").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Color.ink3)
            Spacer()
            if !app.isLocal {
                Button { showJoin = true } label: {
                    Label(t("Join"), systemImage: "link").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(PressScaleStyle(scale: 0.94))
                .foregroundStyle(Color.ink2)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Floating action

    private var floatingBar: some View {
        Button { showCreate = true } label: {
            Label(t("New group"), systemImage: "plus")
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 26)
                .frame(height: 54)
        }
        .buttonStyle(FloatingButtonStyle())
        .padding(.bottom, 10)
    }

    private func refresh() async {
        await app.refreshHome()
        guard !app.isLocal else { await app.refreshMeta(); return }
        // Only fetch server metadata when the server answers; a failed health check is silent here.
        if (try? await app.client?.health()) == true { await app.refreshMeta() }
    }
}

private struct AddTarget: Identifiable {
    let store: GroupStore
    let group: GroupSnapshot
    var id: String { group.id }
}

// MARK: - Balance

/// The headline number set in type on the page itself, no card around it.
private struct BalanceSummary: View {
    let dashboard: Dashboard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 → 1 the first time home opens each day: the number comes into focus. Every
    /// other visit it is simply there, so a screen opened daily never feels slow.
    @State private var focus: Double

    init(dashboard: Dashboard) {
        self.dashboard = dashboard
        _focus = State(initialValue: DailyReveal.claim() ? 0 : 1)
    }

    var body: some View {
        let p = dashboard.primary
        let digits = p?.digits ?? 2
        let currency = p?.currency ?? "USD"
        let format: (Int, Bool) -> String = { Money.format($0, currency: currency, digits: digits, signed: $1) }
        let value = dashboard.knowsYou ? (p?.net ?? 0) : (p?.spentThisMonth ?? 0)

        VStack(alignment: .leading, spacing: 10) {
            Text(dashboard.knowsYou ? t("Net balance") : t("Spent this month"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink3)

            let headline = format(value, dashboard.knowsYou && value != 0)
            // Serif to match the group screen's titles; digits roll when the balance changes.
            RollingNumber(text: headline, size: RollingNumber.fittedSize(for: headline), tracking: -1.2)
                .foregroundStyle(Color.ink)
                .padding(.vertical, -6)
                .blur(radius: reduceMotion ? 0 : (1 - focus) * 12)
                .opacity(0.15 + 0.85 * focus)
                .onAppear {
                    guard focus == 0 else { return }
                    withAnimation(.easeOut(duration: reduceMotion ? 0.3 : 0.8)) { focus = 1 }
                }

            if dashboard.knowsYou, let p {
                HStack(spacing: 0) {
                    figure(t("To receive"), format(p.owedToYou, false), dot: .pos)
                    Rectangle().fill(Color.line).frame(width: 1, height: 26).padding(.horizontal, 18)
                    figure(t("To pay"), format(p.youOwe, false), dot: .neg)
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            } else {
                Text(t("Open a group and choose who you are to see your balance here."))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let others = dashboard.totals.dropFirst()
            if !others.isEmpty {
                Text(others.map { o in
                    "\(o.currency) \(Money.format(dashboard.knowsYou ? o.net : o.spentThisMonth, currency: o.currency, digits: o.digits, signed: dashboard.knowsYou && o.net != 0))"
                }.joined(separator: "   "))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.ink3)
                .lineLimit(2)
            }

            // Without any identity the header already asks you to choose one; say it once.
            if dashboard.knowsYou { uncountedNote }
        }
        .accessibilityElement(children: .combine)
    }

    /// Shown under the totals when some unsettled groups don't know who you are yet,
    /// so a missing balance is never mistaken for a wrong one.
    @ViewBuilder
    private var uncountedNote: some View {
        if dashboard.uncountedGroups > 0 {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 12, weight: .semibold))
                Text(tCount(dashboard.uncountedGroups,
                            one: "%@ group isn't counted yet: open it and choose who you are.",
                            other: "%@ groups aren't counted yet: open them and choose who you are."))
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
        }
    }

    private func figure(_ title: String, _ value: String, dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.ink3)
            }
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .tracking(-0.3)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
        }
    }
}

// MARK: - Wallet stack

/// What a card needs, whether the group is loaded or only remembered.
struct WalletItem: Identifiable, Equatable {
    let id: String
    let name: String
    let memberNames: [String]
    let currency: String
    let digits: Int
    let spend: Int
    /// Your net in this group; nil when you haven't said who you are or it isn't loaded.
    let net: Int?
    /// Everyone in the group is at zero, so it's settled whoever you are.
    let settled: Bool
    let snapshot: GroupSnapshot?

    init(_ s: Dashboard.GroupSummary) {
        id = s.group.id
        name = s.group.name
        memberNames = s.group.members.map(\.name)
        currency = s.group.currency
        digits = s.group.digits
        spend = s.group.stats.totalSpent
        net = s.yourNet
        settled = s.group.stats.settled
        snapshot = s.group
    }

    init(_ r: RecentGroup) {
        id = r.id
        name = r.name
        memberNames = r.memberNames
        currency = r.currency
        digits = r.digits
        spend = r.total
        net = nil
        settled = false
        snapshot = nil
    }

    func format(_ minor: Int) -> String { Money.format(minor, currency: currency, digits: digits) }
}

/// Where each card sits. Pure so it can be tested: every card shows a peek with its
/// name and balance, the open one shows in full, and the last one is never covered.
enum WalletLayout {
    static let peek: CGFloat = 70
    static let gap: CGFloat = 12
    static let collapsedHeight: CGFloat = 190
    static let openHeight: CGFloat = 258

    struct Frame: Equatable { var y: CGFloat; var height: CGFloat }

    static func frames(count: Int, open: Int?) -> (frames: [Frame], total: CGFloat) {
        var y: CGFloat = 0
        var frames: [Frame] = []
        for i in 0..<count {
            let isOpen = i == open
            frames.append(Frame(y: y, height: isOpen ? openHeight : collapsedHeight))
            y += isOpen ? openHeight + gap : peek
        }
        return (frames, frames.last.map { $0.y + $0.height } ?? 0)
    }

    /// How far a card steps back while another is open: the ones it covers recede
    /// more the deeper they are, the ones below it only dim a little.
    static func recede(index: Int, open: Int?) -> Double {
        guard let open, index != open else { return 0 }
        return index < open ? min(1, 0.6 + 0.2 * Double(open - index - 1)) : 0.35
    }
}

/// Four steps of one ink, so neighbouring cards differ by a single step and nothing clashes.
/// The order runs dark → light → dark so long lists never jump from lightest to darkest.
enum WalletTone {
    static let light: [UInt32] = [0x16181D, 0x24282E, 0x33383F, 0x434951]
    static let dark: [UInt32] = [0x1D1F24, 0x272A30, 0x31353C, 0x3C4148]

    static func step(_ index: Int) -> Int {
        let n = light.count, period = 2 * (n - 1)
        let p = index % period
        return p < n ? p : period - p
    }

    static func at(_ index: Int) -> Color {
        let s = step(index)
        return Color(light: light[s], dark: dark[s])
    }
}

@MainActor
@Observable
final class WalletSelection {
    var expanded: String?
}

private struct WalletStack<Card: View>: View {
    let items: [WalletItem]
    let selection: WalletSelection
    let card: (WalletItem, Int, Bool, Double) -> Card

    var body: some View {
        let open = items.firstIndex { $0.id == selection.expanded }
        let layout = WalletLayout.frames(count: items.count, open: open)
        ZStack(alignment: .top) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let f = layout.frames[i]
                card(item, i, i == open, WalletLayout.recede(index: i, open: open))
                    .environment(\.walletCardPlacement, .init(
                        // Shade falls on a card directly behind, not on the page or into the gap below an open card.
                        shadeAbove: i > 0 && i - 1 != open,
                        // Blurred shadows are re-rendered off-screen every frame they move, so only
                        // the bottom card casts one (it frames the stack on the page).
                        castsShadow: i == items.count - 1))
                    .frame(height: f.height)
                    .offset(y: f.y)
                    .zIndex(Double(i))
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: layout.total, maxHeight: layout.total, alignment: .top)
        .onAppear { DeviceTilt.shared.start() }
        .onDisappear { DeviceTilt.shared.stop() }
    }
}

struct WalletCardPlacement: Equatable {
    var shadeAbove = false
    var castsShadow = false
}

private struct WalletCardPlacementKey: EnvironmentKey {
    static let defaultValue = WalletCardPlacement()
}

extension EnvironmentValues {
    var walletCardPlacement: WalletCardPlacement {
        get { self[WalletCardPlacementKey.self] }
        set { self[WalletCardPlacementKey.self] = newValue }
    }
}

private struct WalletCard: View {
    let item: WalletItem
    let tone: Color
    let isOpen: Bool
    /// 0 for cards in focus; up to 1 for cards behind an open one, which shrink and dim.
    var recede: Double = 0
    let onTap: () -> Void
    let onAdd: () -> Void
    let onOpen: () -> Void

    @State private var pressed = false
    @Environment(\.walletCardPlacement) private var placement

    private static let mint = Color(hex: 0xA9DFC3)
    private static let coral = Color(hex: 0xF1B19D)

    var body: some View {
        // The card's size comes from the stack; the content hangs from the top and is
        // clipped, so opening reveals the actions like pulling a card out of a sleeve.
        // Everything here is chosen to stay on the GPU's fast path while cards move:
        // plain rounded-corner clipping, no masks, no blend modes, no per-card blur.
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        tone
            .overlay { CardSheen() }
            .overlay(alignment: .top) { content }
            .overlay { Color.black.opacity(0.34 * recede).allowsHitTesting(false) }
            .overlay(alignment: .top) {
                // A hairline catching light along the top edge and corners, which separates
                // each card from the one behind. It is drawn at a fixed size (so it never
                // redraws while the card resizes) and cut with a plain rectangle where the
                // corners end; the card's clip keeps the inner half of the 2pt stroke.
                shape.stroke(Color.white.opacity(0.13), lineWidth: 2)
                    .frame(height: WalletLayout.collapsedHeight)
                    .frame(height: 26, alignment: .top)
                    .clipped()
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .background(alignment: .top) {
                // A soft band of shade on the card behind, just above this card's edge:
                // reads as a shadow without a blur pass.
                if placement.shadeAbove {
                    LinearGradient(colors: [.black.opacity(0), .black.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 14)
                        // Inset so it stays on the card behind even when that card shrinks back 4%.
                        .padding(.horizontal, 10)
                        .offset(y: -14)
                        .allowsHitTesting(false)
                }
            }
            .background {
                if placement.castsShadow {
                    shape.fill(tone).shadow(color: .black.opacity(0.16), radius: 14, y: 6)
                }
            }
            .scaleEffect(1 - 0.04 * recede, anchor: .top)
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 1), value: pressed)
            .environment(\.colorScheme, .dark)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) { summary }
                .buttonStyle(PressReporter { down in
                    pressed = down
                    // Wake the haptic engine as the finger lands, so the tick on release is
                    // instant. Started cold, it blocked the first frames of the animation.
                    if down { Haptics.prepareSelection() }
                })
                .accessibilityHint(isOpen ? t("Tap to close") : t("Tap to open"))
            actions
                .padding(.horizontal, 18)
                .padding(.top, 2)
                .opacity(isOpen ? 1 : 0)
                .offset(y: isOpen ? 0 : 10)
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(tCount(item.memberNames.count, one: "%@ person", other: "%@ people")) · \(item.currency)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                status.layoutPriority(1)
            }
            .frame(height: WalletLayout.peek - 18, alignment: .top)

            VStack(alignment: .leading, spacing: 4) {
                Text(t("Total group spend"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                Text(item.format(item.spend))
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.9)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.top, 12)

            HStack {
                InkAvatarStack(names: item.memberNames, ring: tone)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        if item.net == nil && item.settled {
            // Settled for everyone, so it's settled for you too: no need to know who you are.
            settledLabel
        } else if item.net == nil && item.snapshot != nil {
            // Money is still owed in this group, but we don't know which member you are.
            VStack(alignment: .trailing, spacing: 3) {
                Text(t("Not counted"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 13, weight: .semibold))
                    Text(t("Which one are you?")).font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.8))
            }
        } else if let net = item.net {
            if net == 0 {
                settledLabel
            } else {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(net > 0 ? t("To receive") : t("To pay"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                    Text(item.format(abs(net)))
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .tracking(-0.3)
                        .foregroundStyle(net > 0 ? Self.mint : Self.coral)
                        .lineLimit(1)
                }
            }
        }
    }

    private var settledLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            Text(t("Settled")).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.55))
        .padding(.top, 2)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if item.snapshot != nil {
                Button(action: onAdd) {
                    Label(t("Add expense"), systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(Color(hex: 0x16181D))
                        .background(.white, in: Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.96))
            }
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Text(t("View details"))
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(.white)
                .background(.white.opacity(0.1), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            }
            .buttonStyle(PressScaleStyle(scale: 0.96))
        }
    }
}

/// Member initials on an ink card; the ring matches the card so overlaps read cleanly.
private struct InkAvatarStack: View {
    let names: [String]
    let ring: Color
    var limit = 4

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(names.prefix(limit).enumerated()), id: \.offset) { i, n in
                Avatar(name: n, colorIndex: i, size: 28)
                    .background(Circle().fill(ring))
                    .overlay(Circle().strokeBorder(ring, lineWidth: 2))
                    .zIndex(Double(10 - i))
            }
            if names.count > limit {
                Text("+\(names.count - limit)")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.1), in: Circle())
                    .background(Circle().fill(ring))
                    .overlay(Circle().strokeBorder(ring, lineWidth: 2))
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

// MARK: - Empty state

/// No groups yet: the pitch in type, then the three steps on ink tiles.
private struct EmptyHome: View {
    let isLocal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(t("Split the bill,")).foregroundStyle(Color.ink)
                Text(t("not the friendship.")).foregroundStyle(Color.ink3)
            }
            .font(.display(40))
            .tracking(-0.8)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text(isLocal
                 ? t("Track shared costs for trips, flats and dinners. No sign-up, no limits, and everything stays on this iPhone, even offline.")
                 : t("Track shared costs for trips, flats and dinners. Nobody signs up and nobody hits a limit. Share one link and the whole group is in."))
                .font(.system(size: 15))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                step(0, "person.2", t("Make a group"), t("Name it, add the people. That's the whole setup."))
                step(1, "square.split.2x1", t("Log what you spend"), t("Split equally, by exact amounts, by shares or by percent. Pennies always add up."))
                step(2, "arrow.left.arrow.right", t("Settle in fewer moves"), t("Evenly works out the smallest set of payments so everyone ends at zero."))
            }
            .padding(.top, 14)
        }
    }

    private func step(_ i: Int, _ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold)).tracking(-0.2).foregroundStyle(.white)
                Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.58)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("0\(i + 1)").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.35))
        }
        .padding(16)
        .background(WalletTone.at(i), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Button styles

/// Glass on iOS 26 (it floats over content), solid ink before that.
private struct FloatingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .foregroundStyle(Color.paper)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 1), value: configuration.isPressed)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            return AnyView(label.glassEffect(.regular.tint(.ink).interactive(), in: Capsule()))
        }
        #endif
        return AnyView(label
            .background(Color.ink, in: Capsule())
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10))
    }
}

/// Shrinks on touch-down, not on release, so the press is felt immediately.
private struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 1), value: configuration.isPressed)
    }
}

/// Reports the press so the whole card (not just the tapped part) can respond.
private struct PressReporter: ButtonStyle {
    let onChange: (Bool) -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, p in onChange(p) }
    }
}
