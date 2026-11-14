import SwiftUI

struct ServerSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var mode: StorageMode = .device
    @State private var address = ""
    @State private var status: Status = .idle
    @State private var importing = false
    @State private var importResult: String?
    @State private var importSucceeded = false

    private enum Status: Equatable { case idle, checking, ok, failed(String) }

    var body: some View {
        @Bindable var localizer = Localizer.shared
        NavigationStack {
            Form {
                Section {
                    Picker(t("Language"), selection: $localizer.choice) {
                        ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    Text(t("Language"))
                } footer: {
                    Text(t("Changes apply right away. \"Follow system\" uses your iPhone's language."))
                }

                Section {
                    AppearancePicker()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text(t("Appearance"))
                } footer: {
                    Text(t("Changes apply right away. \"Automatic\" follows your iPhone's light or dark setting."))
                }

                Section {
                    Picker(t("Store groups on"), selection: $mode) {
                        ForEach(StorageMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text(t("Where your groups live"))
                } footer: {
                    Text(mode == .device
                         ? t("Everything is saved on this iPhone and works offline, with no Mac or server needed. Groups can't be shared with others in this mode. Your data is included in iCloud and computer backups of this iPhone.")
                         : t("Groups live on an Evenly server you run, so friends can join with a link and see the same numbers. The server has to be reachable from this iPhone."))
                }

                if mode == .server {
                    serverSection
                    helpSection
                } else if !app.recents.isEmpty {
                    importSection
                }
            }
            .navigationTitle(t("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Save")) {
                        if mode == .server, let url = AppState.normalize(address) { app.serverAddress = url.absoluteString }
                        app.mode = mode
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(mode == .server && AppState.normalize(address) == nil)
                }
            }
            .onAppear {
                mode = app.mode
                address = app.serverAddress
            }
        }
    }

    private var serverSection: some View {
        Section {
            TextField("http://192.168.1.20:4173", text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .onChange(of: address) { status = .idle }
            Button {
                Task { await test() }
            } label: {
                HStack {
                    Text(t("Test connection"))
                    Spacer()
                    switch status {
                    case .idle: EmptyView()
                    case .checking: ProgressView()
                    case .ok: Label(t("Connected"), systemImage: "checkmark.circle.fill").foregroundStyle(Color.pos)
                    case .failed: Label(t("Unreachable"), systemImage: "xmark.circle.fill").foregroundStyle(Color.neg)
                    }
                }
            }
        } header: {
            Text(t("Server address"))
        } footer: {
            if case .failed(let message) = status { Text(message).foregroundStyle(Color.neg) }
        }
    }

    private var helpSection: some View {
        Section(t("Running your own server")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("Start the server on a computer with Node.js 22 or newer:"))
                Text("HOST=0.0.0.0 npm start").font(.system(.footnote, design: .monospaced))
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface2, in: RoundedRectangle(cornerRadius: 8))
                Text(t("Then enter that computer's address, for example http://192.168.1.20:4173. In the iOS Simulator, http://127.0.0.1:4173 works without extra setup."))
            }
            .font(.footnote)
            .foregroundStyle(Color.ink2)
            .padding(.vertical, 4)
        }
    }

    private var importSection: some View {
        Section {
            Button {
                Task { await copyFromServer() }
            } label: {
                HStack {
                    Label(t("Copy my server groups to this iPhone"), systemImage: "square.and.arrow.down")
                    Spacer()
                    if importing { ProgressView() }
                }
            }
            .disabled(importing)
        } header: {
            Text(t("Bring your groups along"))
        } footer: {
            Text(importResult ?? tCount(app.recents.count, one: "Copies the %@ server group you've opened on this iPhone. The server must be reachable right now. The original on the server is not changed.", other: "Copies the %@ server groups you've opened on this iPhone. The server must be reachable right now. The originals on the server are not changed."))
                .foregroundStyle(importSucceeded ? Color.pos : Color.ink3)
        }
    }

    private func test() async {
        guard let url = AppState.normalize(address) else { status = .failed(t("Enter an address like %@", "http://192.168.1.20:4173")); return }
        status = .checking
        do {
            status = try await APIClient(baseURL: url).health() ? .ok : .failed(t("The server answered, but not like Evenly."))
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func copyFromServer() async {
        importing = true
        defer { importing = false }
        do {
            let n = try await app.importServerGroups()
            importResult = tCount(n, one: "Copied %@ group to this iPhone. Tap Save to start using it.", other: "Copied %@ groups to this iPhone. Tap Save to start using them.")
            importSucceeded = true
        } catch {
            importResult = t("Couldn't copy: %@", error.localizedDescription)
            importSucceeded = false
        }
    }
}
