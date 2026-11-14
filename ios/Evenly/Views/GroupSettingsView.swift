import SwiftUI

struct GroupSettingsView: View {
    let store: GroupStore
    let group: GroupSnapshot
    let me: String?
    /// Called with `true` when the group was deleted.
    let onDone: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var currency: String
    @State private var newPerson = ""
    @State private var renaming: Member?
    @State private var renameText = ""
    @State private var error: String?
    @State private var busy = false
    @State private var confirmDelete = false

    init(store: GroupStore, group: GroupSnapshot, me: String?, onDone: @escaping (Bool) -> Void) {
        self.store = store
        self.group = group
        self.me = me
        self.onDone = onDone
        _name = State(initialValue: group.name)
        _currency = State(initialValue: group.currency)
    }

    /// The live group, so the people list updates after adds and renames.
    private var live: GroupSnapshot { store.group ?? group }

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Name", text: $name)
                    Picker("Currency", selection: $currency) {
                        ForEach(Money.currencyCodes, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section {
                    ForEach(live.members) { m in
                        HStack(spacing: 12) {
                            Avatar(name: m.name, colorIndex: live.colorIndex(of: m.id), size: 30)
                            Text(m.name)
                            if m.id == me { Text("you").font(.caption.weight(.semibold)).foregroundStyle(Color.brand) }
                            Spacer()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { run { try await store.removeMember(m.id) } } label: { Label("Remove", systemImage: "trash") }
                            Button { renameText = m.name; renaming = m } label: { Label("Rename", systemImage: "pencil") }.tint(.ink2)
                        }
                        .contextMenu {
                            Button { renameText = m.name; renaming = m } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) { run { try await store.removeMember(m.id) } } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                    HStack {
                        TextField("Add someone", text: $newPerson)
                            .textInputAutocapitalization(.words)
                            .onSubmit(addPerson)
                        Button("Add", action: addPerson).disabled(newPerson.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("People")
                } footer: {
                    Text("Swipe left on a person to rename or remove them. People on existing expenses can't be removed.")
                }

                if let error {
                    Section { Text(error).foregroundStyle(Color.neg) }
                }

                Section {
                    Button("Delete this group", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Removes every expense and payment for everyone with the link. This cannot be undone.")
                }
            }
            .navigationTitle("Group settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Save", action: save).fontWeight(.semibold) }
                }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let m = renaming { run { try await store.renameMember(m.id, to: renameText) } }
                }
            }
            .confirmationDialog("Delete \(group.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete group", role: .destructive) {
                    run {
                        try await store.deleteGroup()
                        dismiss()
                        onDone(true)
                    }
                }
            } message: {
                Text("Everyone with the link loses access. This cannot be undone.")
            }
        }
        .tint(.ink)
    }

    private func addPerson() {
        let n = newPerson.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        run {
            try await store.addMember(n)
            newPerson = ""
        }
    }

    private func save() {
        run {
            try await store.updateGroup(name: name, currency: currency)
            dismiss()
            onDone(false)
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do { try await work() } catch { self.error = error.localizedDescription }
        }
    }
}
