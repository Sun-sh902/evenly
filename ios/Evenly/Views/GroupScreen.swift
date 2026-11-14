import SwiftUI

enum GroupSheet: Identifiable {
    case newExpense
    case editExpense(Entry)
    case payment(entry: Entry?, suggestion: Transfer?)
    case settings
    case export(URL)

    var id: String {
        switch self {
        case .newExpense: "new"
        case .editExpense(let e): "edit-\(e.id)"
        case .payment(let e, let s): "pay-\(e?.id ?? "")-\(s?.from ?? "")-\(s?.to ?? "")"
        case .settings: "settings"
        case .export(let url): "export-\(url.lastPathComponent)"
        }
    }
}

enum ActivityFilter: String, CaseIterable, Identifiable {
    case all = "All", expenses = "Expenses", payments = "Payments"
    var id: String { rawValue }
}

struct GroupScreen: View {
    let groupId: String
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: GroupStore?
    @State private var sheet: GroupSheet?
    @State private var query = ""
    @State private var filter: ActivityFilter = .all
    @State private var savedTick = 0

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .task(id: groupId) {
            let s = GroupStore(groupId: groupId, app: app)
            store = s
            await s.load()
            await s.pollForever()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let store { Task { await store.refresh(announce: true) } }
        }
        .onChange(of: sheet == nil) { _, closed in store?.isEditing = !closed }
    }

    @ViewBuilder
    private func content(_ store: GroupStore) -> some View {
        switch store.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .missing:
            unavailable("Nothing here", "This group was deleted, or the link is mistyped.")
        case .failed(let message):
            VStack(spacing: 16) {
                unavailable("Can't load this group", message)
                Button("Try again") { Task { await store.load() } }.buttonStyle(GhostButtonStyle())
            }
        case .ready:
            if let g = store.group { ready(g, store) }
        }
    }

    private func unavailable(_ title: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.display(34))
            Text(text).font(.system(size: 15)).foregroundStyle(Color.ink3).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ready(_ g: GroupSnapshot, _ store: GroupStore) -> some View {
        @Bindable var store = store
        let me = app.meVersion >= 0 ? app.me(in: g) : nil
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header(g)
                MeBar(group: g, me: me) { id in
                    withAnimation(.snappy) { app.setMe(id, groupId: g.id) }
                } onSettle: { t in
                    sheet = .payment(entry: nil, suggestion: t)
                }
                StatsRow(group: g)
                BalancesCard(group: g, me: me)
                SettleCard(group: g) { sheet = .payment(entry: nil, suggestion: $0) }
                ActivitySection(group: g, me: me, query: $query, filter: $filter) { entry in
                    sheet = entry.isTransfer ? .payment(entry: entry, suggestion: nil) : .editExpense(entry)
                } onAdd: {
                    sheet = .newExpense
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .refreshable { await store.load() }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(g.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The large serif header already names the group; keep the bar clean.
            ToolbarItem(placement: .principal) { Text("").accessibilityHidden(true) }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: app.client?.webLink(for: g.id) ?? URL(string: "https://github.com/Sun-sh902/evenly")!,
                          subject: Text(g.name),
                          message: Text("Join \(g.name) on Evenly")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share invite link")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { sheet = .settings } label: { Label("Group settings", systemImage: "gearshape") }
                    Button {
                        Task {
                            do { sheet = .export(try await store.exportCSV()) } catch { store.toast = error.localizedDescription }
                        }
                    } label: { Label("Export CSV", systemImage: "tablecells") }
                    if me != nil {
                        Button { app.setMe(nil, groupId: g.id) } label: { Label("Switch who you are", systemImage: "person.crop.circle") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button { sheet = .newExpense } label: {
                Label("Add expense", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
            .padding(.trailing, 20)
            .padding(.bottom, 12)
        }
        .toast($store.toast)
        .sensoryFeedback(.success, trigger: savedTick)
        .sheet(item: $sheet) { which in
            switch which {
            case .newExpense:
                ExpenseEditor(store: store, group: g, entry: nil, defaultPayer: me ?? app.lastPayer(groupId: g.id)) { savedMessage($0) }
            case .editExpense(let entry):
                ExpenseEditor(store: store, group: g, entry: entry, defaultPayer: nil) { savedMessage($0) }
            case .payment(let entry, let suggestion):
                PaymentEditor(store: store, group: g, entry: entry, suggestion: suggestion) { savedMessage($0) }
            case .settings:
                GroupSettingsView(store: store, group: g, me: me) { deleted in
                    if deleted { app.path.removeAll() } else { savedMessage("Settings saved") }
                }
            case .export(let url):
                ShareSheet(items: [url]).presentationDetents([.medium, .large])
            }
        }
    }

    private func header(_ g: GroupSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(g.members.count) \(g.members.count == 1 ? "person" : "people") · \(g.currency)")
                .font(.system(size: 13)).foregroundStyle(Color.ink3)
            Text(g.name).font(.display(38)).tracking(-0.8).lineLimit(2).minimumScaleFactor(0.7)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func savedMessage(_ text: String) {
        savedTick += 1
        store?.toast = text
    }
}

// MARK: - Sections

private struct MeBar: View {
    let group: GroupSnapshot
    let me: String?
    let onPick: (String?) -> Void
    let onSettle: (Transfer) -> Void

    var body: some View {
        if group.members.count >= 2 {
            if let me { mine(me) } else { ask }
        }
    }

    private var ask: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Which one are you?").font(.system(size: 16, weight: .semibold))
                Text("Evenly will show your own balance and pick you as the payer. Saved on this device only.")
                    .font(.system(size: 13)).foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: 8) {
                ForEach(group.members) { m in
                    PersonChip(name: m.name, colorIndex: group.colorIndex(of: m.id), selected: false) { onPick(m.id) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.brand.opacity(0.25)))
    }

    private func mine(_ me: String) -> some View {
        let net = group.net(of: me)
        let owes = group.transfers.filter { $0.from == me }
        let owed = group.transfers.filter { $0.to == me }
        return HStack(spacing: 14) {
            Avatar(name: group.name(of: me), colorIndex: group.colorIndex(of: me), size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("Viewing as \(group.name(of: me))").font(.system(size: 13)).foregroundStyle(Color.ink3)
                Group {
                    if net > 0 {
                        Text("You get back ") + Text(group.format(net)).font(.amount(17)).foregroundColor(.pos)
                    } else if net < 0 {
                        Text("You owe ") + Text(group.format(-net)).font(.amount(17)).foregroundColor(.neg)
                    } else {
                        Text(group.entries.isEmpty ? "Nothing logged yet" : "You're all square")
                    }
                }
                .font(.system(size: 17))
                let others = (net < 0 ? owes.map { group.name(of: $0.to) } : owed.map { group.name(of: $0.from) })
                if !others.isEmpty {
                    Text("\(net < 0 ? "to" : "from") \(others.joined(separator: ", "))")
                        .font(.system(size: 13)).foregroundStyle(Color.ink3).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if net < 0, let first = owes.first {
                Button { onSettle(first) } label: {
                    Text("Settle").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(PrimaryButtonStyle(tint: .brand, foreground: .brandInk))
                .controlSize(.small)
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct StatsRow: View {
    let group: GroupSnapshot

    var body: some View {
        let cats = group.stats.byCategory.sorted { $0.value > $1.value }
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total group spend").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.paper.opacity(0.6))
                Text(group.format(group.stats.totalSpent))
                    .font(.display(44)).tracking(-1).lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(Color.paper)
                if !cats.isEmpty {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(cats, id: \.key) { c in
                                Capsule().fill(CategoryStyle.of(c.key).color)
                                    .frame(width: max(4, (geo.size.width - CGFloat(cats.count - 1) * 2) * CGFloat(c.value) / CGFloat(max(1, group.stats.totalSpent))))
                            }
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack(alignment: .topTrailing) {
                    Color.ink
                    Circle().stroke(Color.brand.opacity(0.5), lineWidth: 1.5).frame(width: 150).offset(x: 40, y: -50)
                    Circle().stroke(Color.paper.opacity(0.25), lineWidth: 1.5).frame(width: 150).offset(x: -10, y: -50)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                stat("Expenses logged", "\(group.stats.expenseCount)", detail: nil)
                if let top = cats.first {
                    stat("Biggest category", CategoryStyle.of(top.key).label,
                         detail: "\(Int((Double(top.value) / Double(max(1, group.stats.totalSpent)) * 100).rounded()))%")
                } else {
                    stat("Biggest category", "-", detail: nil)
                }
            }
        }
    }

    private func stat(_ k: String, _ v: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(k).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink3)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(v).font(.display(28)).lineLimit(1).minimumScaleFactor(0.6)
                if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(Color.ink3) }
            }
        }
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

private struct BalancesCard: View {
    let group: GroupSnapshot
    let me: String?

    var body: some View {
        let maxAbs = max(1, group.balances.map { abs($0.net) }.max() ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            Text("Balances").sectionTitle()
            ForEach(group.balances, id: \.memberId) { b in
                HStack(spacing: 12) {
                    Avatar(name: group.name(of: b.memberId), colorIndex: group.colorIndex(of: b.memberId))
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Text(group.name(of: b.memberId)).font(.system(size: 15, weight: .medium)).lineLimit(1)
                            if b.memberId == me {
                                Text("you").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.brand)
                                    .padding(.horizontal, 7).padding(.vertical, 1)
                                    .background(Color.brandSoft, in: Capsule())
                            }
                        }
                        DivergingBar(value: b.net, maxAbs: maxAbs)
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(b.net == 0 ? group.format(0) : group.format(b.net, signed: true))
                            .font(.amount(14))
                            .foregroundStyle(b.net > 0 ? Color.pos : b.net < 0 ? Color.neg : Color.ink3)
                        Text(b.net > 0 ? "gets back" : b.net < 0 ? "owes" : "all square")
                            .font(.system(size: 12)).foregroundStyle(Color.ink3)
                    }
                    // Fixed column so every bar shares the same centre line.
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 112, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}

private struct DivergingBar: View {
    let value: Int
    let maxAbs: Int

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let w = half * CGFloat(abs(value)) / CGFloat(maxAbs)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surface2)
                Rectangle().fill(Color.lineStrong).frame(width: 1, height: 12).offset(x: half, y: 0)
                if value != 0 {
                    Capsule().fill(value > 0 ? Color.pos : Color.neg)
                        .frame(width: max(4, w))
                        .offset(x: value > 0 ? half : half - max(4, w))
                }
            }
        }
        .frame(height: 6)
        .animation(.spring(duration: 0.5), value: value)
        .accessibilityHidden(true)
    }
}

private struct SettleCard: View {
    let group: GroupSnapshot
    let onRecord: (Transfer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settle up").sectionTitle()
                Spacer()
                if !group.transfers.isEmpty {
                    Text("\(group.transfers.count) payment\(group.transfers.count == 1 ? "" : "s")")
                        .font(.system(size: 12)).foregroundStyle(Color.ink3)
                }
            }
            if group.entries.isEmpty {
                Text("Suggested payments appear here once you log something.")
                    .font(.system(size: 14)).foregroundStyle(Color.ink3)
            } else if group.transfers.isEmpty {
                Label("Everyone is settled up. Nice.", systemImage: "party.popper")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.pos)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.posSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ForEach(group.transfers, id: \.self) { t in
                    HStack(spacing: 12) {
                        Avatar(name: group.name(of: t.from), colorIndex: group.colorIndex(of: t.from))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(group.name(of: t.from)).fontWeight(.semibold)
                                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink3)
                                Text(group.name(of: t.to))
                            }
                            .font(.system(size: 14))
                            .lineLimit(1)
                            Text(group.format(t.amount)).font(.amount(14))
                        }
                        Spacer(minLength: 0)
                        Button("Mark paid") { onRecord(t) }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(Color.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.line))
                            .foregroundStyle(Color.ink)
                            .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.line))
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Mark paid") { onRecord(t) }
                }
            }
        }
        .card()
    }
}

private struct ActivitySection: View {
    let group: GroupSnapshot
    let me: String?
    @Binding var query: String
    @Binding var filter: ActivityFilter
    let onOpen: (Entry) -> Void
    let onAdd: () -> Void

    private var visible: [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return group.entries.filter { e in
            switch filter {
            case .all: break
            case .expenses: if e.isTransfer { return false }
            case .payments: if !e.isTransfer { return false }
            }
            guard !q.isEmpty else { return true }
            let hay = "\(e.title) \(e.note) \(group.name(of: e.paidBy)) \(CategoryStyle.of(e.category).label)".lowercased()
            return hay.contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity").font(.display(28)).tracking(-0.5)
                Spacer()
            }
            .padding(.top, 8)
            if !group.entries.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.ink3)
                    TextField("Search expenses", text: $query)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ink3) }
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.line))
            }
            Picker("Filter", selection: $filter) {
                ForEach(ActivityFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if group.entries.isEmpty {
                empty
            } else if visible.isEmpty {
                Text("No matches. Try a different search or filter.")
                    .font(.system(size: 15)).foregroundStyle(Color.ink3)
                    .frame(maxWidth: .infinity).padding(.vertical, 32)
            } else {
                VStack(spacing: 0) {
                    ForEach(days, id: \.date) { day in
                        HStack {
                            Text(Day.label(day.date)).sectionTitle()
                            Spacer()
                            let total = day.items.filter { !$0.isTransfer }.reduce(0) { $0 + $1.amount }
                            if total > 0 { Text(group.format(total)).font(.system(size: 12)).foregroundStyle(Color.ink3) }
                        }
                        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 6)
                        ForEach(day.items) { e in
                            Button { onOpen(e) } label: { row(e) }.buttonStyle(RowButtonStyle())
                        }
                    }
                }
                .padding(.bottom, 8)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.line))
            }
        }
    }

    private var days: [(date: String, items: [Entry])] {
        var order: [String] = []
        var map: [String: [Entry]] = [:]
        for e in visible {
            if map[e.date] == nil { order.append(e.date) }
            map[e.date, default: []].append(e)
        }
        return order.map { ($0, map[$0]!) }
    }

    private func row(_ e: Entry) -> some View {
        let style = CategoryStyle.of(e.category)
        let payer = e.paidBy == me ? "You" : group.name(of: e.paidBy)
        return HStack(spacing: 14) {
            CategoryIcon(category: e.category)
            VStack(alignment: .leading, spacing: 2) {
                if e.isTransfer {
                    Text("\(payer) paid \(e.recipient == me ? "you" : group.name(of: e.recipient))")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.ink2)
                    Text(e.title).font(.system(size: 13)).foregroundStyle(Color.ink3)
                } else {
                    Text(e.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.ink)
                    Text("\(Text(payer).fontWeight(.medium).foregroundColor(.ink2)) paid · \(summary(e))\(e.note.isEmpty ? "" : " · \(e.note)")")
                        .font(.system(size: 13)).foregroundStyle(Color.ink3)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(group.format(e.amount)).font(.amount(15)).foregroundStyle(e.isTransfer ? Color.pos : Color.ink)
                Text(e.isTransfer ? "payment" : style.label).font(.system(size: 12)).foregroundStyle(Color.ink3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens for editing")
    }

    private func summary(_ e: Entry) -> String {
        let mode = SplitMode(rawValue: e.splitMode) ?? .equal
        if mode == .equal {
            return e.shares.count == group.members.count ? "split equally" : "split \(e.shares.count) way\(e.shares.count == 1 ? "" : "s")"
        }
        return mode.summary
    }

    private var empty: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.surface2).frame(width: 56, height: 70).offset(x: -16, y: 6)
                RoundedRectangle(cornerRadius: 10).fill(Color.surface).frame(width: 56, height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.lineStrong))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Color.brand).offset(x: 8, y: 8)
                    }
                    .offset(x: 12)
            }
            .padding(.bottom, 8)
            Text("A clean slate").font(.display(28))
            Text("Log the first expense and Evenly keeps a running tally of who owes whom.")
                .font(.system(size: 15)).foregroundStyle(Color.ink3).multilineTextAlignment(.center)
            Button(action: onAdd) { Label("Add the first expense", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .card()
    }
}

private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Color.surface2 : Color.clear)
    }
}
