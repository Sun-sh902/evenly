import SwiftUI

struct ExpenseEditor: View {
    let store: GroupStore
    let group: GroupSnapshot
    let entry: Entry?
    let onSaved: (String) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String
    @State private var title: String
    @State private var category: String
    @State private var paidBy: String
    @State private var date: Date
    @State private var note: String
    @State private var mode: SplitMode
    @State private var included: Set<String>
    @State private var values: [String: String]
    @State private var error: String?
    @State private var saving = false
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case amount, title, note, value(String) }

    init(store: GroupStore, group: GroupSnapshot, entry: Entry?, defaultPayer: String?, onSaved: @escaping (String) -> Void) {
        self.store = store
        self.group = group
        self.entry = entry
        self.onSaved = onSaved
        let mode = SplitMode(rawValue: entry?.splitMode ?? "equal") ?? .equal
        var values: [String: String] = [:]
        if let entry, mode != .equal {
            for s in entry.shares {
                values[s.memberId] = mode == .exact ? Money.plain(s.share, digits: group.digits) : SplitCalculator.clean(s.weight ?? 0)
            }
        }
        let payer = entry?.paidBy ?? defaultPayer
        _amount = State(initialValue: entry.map { Money.plain($0.amount, digits: group.digits) } ?? "")
        _title = State(initialValue: entry?.title ?? "")
        _category = State(initialValue: entry?.category ?? "general")
        _paidBy = State(initialValue: group.member(payer)?.id ?? group.members[0].id)
        _date = State(initialValue: entry.flatMap { Day.date(from: $0.date) } ?? Date())
        _note = State(initialValue: entry?.note ?? "")
        _mode = State(initialValue: mode)
        _included = State(initialValue: Set(entry?.shares.map(\.memberId) ?? group.members.map(\.id)))
        _values = State(initialValue: values)
    }

    private var minor: Int? { Money.parse(amount, digits: group.digits) }

    /// Big serif amount that steps down for long numbers so it never clips.
    static func amountFontSize(for text: String) -> CGFloat {
        let n = max(text.count, 4)
        return n <= 6 ? 64 : max(34, 64 - CGFloat(n - 6) * 6)
    }

    private var preview: SplitPreview {
        SplitCalculator.preview(
            amount: minor, mode: mode, memberIds: group.members.map(\.id), included: included,
            values: values, format: { group.format($0) }, digits: group.digits
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    amountHero
                    categoryPicker
                    payerPicker
                    splitSection
                    detailsSection
                    if let error {
                        Text(error)
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.neg)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.negSoft, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if entry != nil {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label(t("Delete expense"), systemImage: "trash").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GhostButtonStyle())
                        .foregroundStyle(Color.neg)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.surface.ignoresSafeArea())
            .navigationTitle(entry == nil ? t("New expense") : t("Edit expense"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button(entry == nil ? t("Add") : t("Save")) { save() }.fontWeight(.semibold)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(t("Done")) { focus = nil }
                }
            }
            .confirmationDialog(t("Delete this expense?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(t("Delete"), role: .destructive) { remove() }
            } message: {
                Text(t("Balances will be recalculated for everyone."))
            }
            .onAppear { if entry == nil { focus = .amount } }
        }
        .tint(.ink)
        .interactiveDismissDisabled(saving)
    }

    // MARK: Sections

    private var amountHero: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Money.symbol(for: group.currency).trimmingCharacters(in: .whitespaces))
                    .font(.display(36)).foregroundStyle(Color.ink3)
                TextField(group.digits > 0 ? "0.00" : "0", text: $amount)
                    .font(.display(Self.amountFontSize(for: amount)))
                    .tracking(-1.5)
                    .keyboardType(group.digits > 0 ? .decimalPad : .numberPad)
                    .focused($focus, equals: .amount)
                    .fixedSize()
                    .onChange(of: amount) { _, v in
                        let filtered = v.filter { $0.isNumber || (group.digits > 0 && ($0 == "." || $0 == ",")) }
                            .replacingOccurrences(of: ",", with: ".")
                        if filtered != v { amount = filtered }
                    }
                    .accessibilityLabel(t("Amount"))
            }
            .frame(maxWidth: .infinity)
            .lineLimit(1)

            TextField(t("What was it for?"), text: $title)
                .multilineTextAlignment(.center)
                .font(.system(size: 17))
                .focused($focus, equals: .title)
                .submitLabel(.done)
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(Color.fieldBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.line))
                .frame(maxWidth: 360)
                .accessibilityLabel(t("Description"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Category")).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(app.categories, id: \.self) { c in
                        let style = CategoryStyle.of(c)
                        let on = category == c
                        Button { category = c } label: {
                            HStack(spacing: 6) {
                                Image(systemName: style.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(style.color)
                                Text(style.label).font(.system(size: 14, weight: on ? .semibold : .regular))
                            }
                            .padding(.horizontal, 12).frame(height: 36)
                            .background(on ? style.color.opacity(0.14) : Color.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? style.color.opacity(0.5) : Color.line))
                            .foregroundStyle(on ? Color.ink : Color.ink2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(1)
            }
        }
    }

    private var payerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Paid by")).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink2)
            FlowLayout(spacing: 8) {
                ForEach(group.members) { m in
                    PersonChip(name: m.name, colorIndex: group.colorIndex(of: m.id), selected: paidBy == m.id) { paidBy = m.id }
                }
            }
        }
    }

    private var splitSection: some View {
        let p = preview
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("Split")).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink2)
                Spacer()
            }
            Picker(t("Split method"), selection: $mode) {
                ForEach(SplitMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, m in reseed(m) }

            VStack(spacing: 0) {
                ForEach(Array(group.members.enumerated()), id: \.element.id) { index, m in
                    if index > 0 { Divider().overlay(Color.line) }
                    participantRow(m, share: p.shares[m.id] ?? 0)
                }
            }
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.line))

            HStack {
                Text(p.message)
                    .foregroundStyle(p.tone == .bad ? Color.neg : p.tone == .good ? Color.pos : Color.ink3)
                Spacer()
                Text(t("%@/%@ people", String(included.count), String(group.members.count))).foregroundStyle(Color.ink3)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 4)
        }
    }

    private func participantRow(_ m: Member, share: Int) -> some View {
        let on = included.contains(m.id)
        return HStack(spacing: 10) {
            Button {
                if on { included.remove(m.id) } else { included.insert(m.id) }
                if mode != .equal { reseed(mode) }
            } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(on ? Color.ink : Color.lineStrong)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("Include %@", m.name))
            .accessibilityAddTraits(on ? .isSelected : [])

            Avatar(name: m.name, colorIndex: group.colorIndex(of: m.id), size: 30).opacity(on ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(.system(size: 15, weight: .medium)).lineLimit(1).opacity(on ? 1 : 0.45)
                if mode != .equal && on {
                    Text(group.format(share)).font(.amount(12, weight: .regular)).foregroundStyle(Color.ink3)
                }
            }
            Spacer(minLength: 4)
            if mode != .equal && on {
                HStack(spacing: 2) {
                    TextField(mode == .exact ? (group.digits > 0 ? "0.00" : "0") : "0", text: binding(for: m.id))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.amount(15))
                        .focused($focus, equals: .value(m.id))
                    if mode == .percent { Text("%").foregroundStyle(Color.ink3) }
                    if mode == .shares { Text("×").foregroundStyle(Color.ink3) }
                }
                .padding(.horizontal, 10)
                .frame(width: 100, height: 38)
                .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.line))
                .accessibilityLabel("\(m.name) \(mode.label)")
            } else {
                Text(on ? group.format(share) : t("not included"))
                    .font(on ? .amount(14) : .system(size: 13))
                    .foregroundStyle(on ? Color.ink2 : Color.ink3)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(on ? Color.clear : Color.fieldBackground)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DatePicker(t("Date"), selection: $date, in: ...Date.distantFuture, displayedComponents: .date)
                .font(.system(size: 15))
                .environment(\.locale, Localizer.shared.locale)
            VStack(alignment: .leading, spacing: 8) {
                Text(t("Note (optional)")).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink2)
                TextField(t("Receipt number, details"), text: $note, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focus, equals: .note)
                    .padding(.vertical, 12)
                    .fieldStyle()
            }
        }
    }

    // MARK: Logic

    private func binding(for id: String) -> Binding<String> {
        Binding(get: { values[id] ?? "" }, set: { values[id] = $0 })
    }

    private func reseed(_ m: SplitMode) {
        let ids = group.members.map(\.id).filter { included.contains($0) }
        values = SplitCalculator.seed(mode: m, ids: ids, amount: minor, digits: group.digits)
    }

    private func save() {
        focus = nil
        guard let minor, minor > 0 else {
            error = group.digits > 0 ? t("Enter an amount, like 24.50.") : t("Enter a whole amount, like 2400.")
            focus = .amount
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = t("Add a short description."); focus = .title; return }
        let p = preview
        guard p.isValid else { error = p.message.isEmpty ? t("Check how the cost is split.") : p.message; return }

        let ids = group.members.map(\.id).filter { included.contains($0) }
        let payload = ExpensePayload(
            title: trimmed,
            amount: Money.plain(minor, digits: group.digits),
            paidBy: paidBy,
            category: category,
            date: Day.string(from: date),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            split: SplitPayload(mode: mode.rawValue, participants: ids.map {
                SplitParticipant(memberId: $0, value: mode == .equal ? nil : (values[$0].flatMap { $0.isEmpty ? nil : $0 } ?? "0"))
            })
        )
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await store.saveExpense(payload, editing: entry?.id)
                dismiss()
                onSaved(entry == nil ? t("%@ added", trimmed) : t("Changes saved"))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func remove() {
        guard let entry else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.deleteEntry(entry.id)
                dismiss()
                onSaved(t("Expense deleted"))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
