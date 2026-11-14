import SwiftUI

struct ServerSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var status: Status = .idle

    private enum Status: Equatable { case idle, checking, ok, failed(String) }

    var body: some View {
        NavigationStack {
            Form {
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
                            Text("Test connection")
                            Spacer()
                            switch status {
                            case .idle: EmptyView()
                            case .checking: ProgressView()
                            case .ok: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(Color.pos)
                            case .failed: Label("Unreachable", systemImage: "xmark.circle.fill").foregroundStyle(Color.neg)
                            }
                        }
                    }
                } header: {
                    Text("Server address")
                } footer: {
                    if case .failed(let message) = status { Text(message).foregroundStyle(Color.neg) }
                }

                Section("Running your own server") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Evenly keeps your data on a server you control. Start it on a computer with Node.js 22 or newer:")
                        Text("HOST=0.0.0.0 npm start").font(.system(.footnote, design: .monospaced))
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surface2, in: RoundedRectangle(cornerRadius: 8))
                        Text("Then enter that computer's address here, for example http://192.168.1.20:4173. In the iOS Simulator, http://127.0.0.1:4173 works without any extra setup.")
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.ink2)
                    .padding(.vertical, 4)
                }

                Section {
                    Button("Use simulator default") { address = AppState.defaultServer }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let url = AppState.normalize(address) { app.serverAddress = url.absoluteString }
                        dismiss()
                    }
                    .disabled(AppState.normalize(address) == nil)
                }
            }
            .onAppear { address = app.serverAddress }
        }
    }

    private func test() async {
        guard let url = AppState.normalize(address) else { status = .failed("Enter an address like http://192.168.1.20:4173"); return }
        status = .checking
        do {
            status = try await APIClient(baseURL: url).health() ? .ok : .failed("The server answered, but not like Evenly.")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
