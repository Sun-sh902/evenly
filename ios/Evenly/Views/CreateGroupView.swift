import SwiftUI

struct CreateGroupView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var currency = Locale.current.currency?.identifier ?? "USD"
    @State private var people: [String] = []
    @State private var draft = ""
    @State private var error: String?
    @State private var saving = false
    @FocusState private var focus: Field?

    private enum Field { case name, person }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start a group").font(.display(34)).tracking(-0.6)
                        Text("Takes ten seconds. You can add more people later.").font(.system(size: 15)).foregroundStyle(Color.ink3)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Group name").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink2)
                        TextField("Lisbon trip", text: $name)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .person }
                            .fieldStyle()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Currency").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink2)
                        Picker("Currency", selection: $currency) {
                            ForEach(Money.currencyCodes, id: \.self) { Text("\($0)  \(Money.symbol(for: $0).trimmingCharacters(in: .whitespaces))").tag($0) }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fieldStyle()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("People").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink2)
                        if !people.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(Array(people.enumerated()), id: \.element) { i, person in
                                    HStack(spacing: 6) {
                                        Avatar(name: person, colorIndex: i, size: 26)
                                        Text(person).font(.system(size: 15, weight: .medium))
                                        Button { withAnimation { people.removeAll { $0 == person } } } label: {
                                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.ink3)
                                                .frame(width: 22, height: 22)
                                        }
                                        .accessibilityLabel("Remove \(person)")
                                    }
                                    .padding(.leading, 4).padding(.trailing, 6).frame(height: 34)
                                    .background(Color.surface, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.line))
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                        HStack {
                            TextField(people.isEmpty ? "Type a name, then return" : "Add another", text: $draft)
                                .focused($focus, equals: .person)
                                .submitLabel(.done)
                                .onSubmit { commit(); focus = .person }
                                .textInputAutocapitalization(.words)
                                // Commas are split on return, Add or Create rather than on every
                                // keystroke: rewriting the field mid-typing drops characters.
                            if !draft.isEmpty {
                                Button("Add") { commit() }.font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .fieldStyle()
                        Text("Add yourself too. Separate names with return or a comma.").font(.system(size: 13)).foregroundStyle(Color.ink3)
                    }

                    if let error {
                        Text(error).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.neg)
                    }

                    Button(action: create) {
                        HStack {
                            if saving { ProgressView().tint(Color.paper) }
                            Text("Create group")
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(saving)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                if !Money.currencyCodes.contains(currency) { currency = "USD" }
                focus = .name
            }
        }
        .tint(.ink)
    }

    private func commit() {
        let names = draft.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(32)) }
        var dupes: [String] = []
        for n in names {
            if people.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) { dupes.append(n) } else {
                withAnimation(.spring(duration: 0.3)) { people.append(n) }
            }
        }
        draft = ""
        error = dupes.isEmpty ? nil : "\(dupes.joined(separator: ", ")) \(dupes.count > 1 ? "are" : "is") already on the list."
    }

    private func create() {
        commit()
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = "Give your group a name."; focus = .name; return }
        guard !people.isEmpty else { error = "Add at least one person."; focus = .person; return }
        guard let backend = app.backend else { error = "Set a server address first."; return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let g = try await backend.createGroup(name: trimmed, currency: currency, members: people)
                app.remember(g)
                dismiss()
                try? await Task.sleep(for: .milliseconds(350))
                app.path = [g.id]
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
