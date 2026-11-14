import SwiftUI

struct PaymentEditor: View {
    let store: GroupStore
    let group: GroupSnapshot
    let entry: Entry?
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    @State private var from: String
    @State private var to: String
    @State private var date: Date
    @State private var error: String?
    @State private var saving = false
    @State private var confirmDelete = false

    init(store: GroupStore, group: GroupSnapshot, entry: Entry?, suggestion: Transfer?, onSaved: @escaping (String) -> Void) {
        self.store = store
        self.group = group
        self.entry = entry
        self.onSaved = onSaved
        let from = entry?.paidBy ?? suggestion?.from ?? group.members[0].id
        let to = entry?.recipient ?? suggestion?.to ?? group.members.first { $0.id != from }?.id ?? from
        let minor = entry?.amount ?? suggestion?.amount
        _amount = State(initialValue: minor.map { Money.plain($0, digits: group.digits) } ?? "")
        _from = State(initialValue: from)
        _to = State(initialValue: to)
        _date = State(initialValue: entry.flatMap { Day.date(from: $0.date) } ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Money.symbol(for: group.currency).trimmingCharacters(in: .whitespaces))
                                .font(.display(34)).foregroundStyle(Color.ink3)
                            TextField(group.digits > 0 ? "0.00" : "0", text: $amount)
                                .font(.display(ExpenseEditor.amountFontSize(for: amount) - 8))
                                .keyboardType(group.digits > 0 ? .decimalPad : .numberPad)
                                .fixedSize()
                                .accessibilityLabel(t("Amount"))
                        }
                        Text(t("Money handed over outside the app, by cash or bank transfer."))
                            .font(.system(size: 13)).foregroundStyle(Color.ink3).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker(t("From"), selection: $from) {
                        ForEach(group.members) { m in Text(m.name).tag(m.id) }
                    }
                    Picker(t("To"), selection: $to) {
                        ForEach(group.members) { m in Text(m.name).tag(m.id) }
                    }
                    DatePicker(t("Date"), selection: $date, displayedComponents: .date)
                        .environment(\.locale, Localizer.shared.locale)
                }

                if let error {
                    Section { Text(error).foregroundStyle(Color.neg) }
                }

                if entry != nil {
                    Section {
                        Button(t("Delete payment"), role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle(entry == nil ? t("Record a payment") : t("Edit payment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button(entry == nil ? t("Record") : t("Save")) { save() }.fontWeight(.semibold) }
                }
            }
            .confirmationDialog(t("Delete this payment?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(t("Delete"), role: .destructive) { remove() }
            }
        }
        .tint(.ink)
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let minor = Money.parse(amount, digits: group.digits), minor > 0 else { error = t("Enter an amount."); return }
        guard from != to else { error = t("Pick two different people."); return }
        saving = true
        let payload = TransferPayload(
            amount: Money.plain(minor, digits: group.digits), paidBy: from, to: to,
            date: Day.string(from: date), title: entry?.title ?? "Settlement"
        )
        Task {
            defer { saving = false }
            do {
                try await store.savePayment(payload, editing: entry?.id)
                dismiss()
                onSaved(entry == nil ? t("%@ paid %@", group.name(of: from), group.name(of: to)) : t("Payment updated"))
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
                onSaved(t("Payment deleted"))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
