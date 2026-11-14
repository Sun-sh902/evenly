import SwiftUI
import UIKit

struct JoinGroupView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var parsed: InviteLink.Parsed? { InviteLink.parse(text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Join a group").font(.display(34)).tracking(-0.6)
                    Text("Paste the invite link someone shared with you.").font(.system(size: 15)).foregroundStyle(Color.ink3)
                }
                HStack {
                    TextField("http://host:4173/g/abc123", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focused)
                    if UIPasteboard.general.hasStrings {
                        Button("Paste") { text = UIPasteboard.general.string ?? "" }
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .padding(.vertical, 8)
                .fieldStyle()

                if let p = parsed, let server = p.server, AppState.normalize(server.absoluteString) != app.serverURL {
                    Label("This link is on \(server.host ?? "another server"). Evenly will connect there.", systemImage: "info.circle")
                        .font(.system(size: 13)).foregroundStyle(Color.ink2)
                }
                if let error {
                    Text(error).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.neg)
                }
                Button {
                    guard let p = parsed else { error = "That doesn't look like an Evenly link."; return }
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        app.open(p)
                    }
                } label: {
                    Text("Open group").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(text.isEmpty)
                Spacer()
            }
            .padding(20)
            .background(Color.paper.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { focused = true }
        }
        .tint(.ink)
        .presentationDetents([.medium, .large])
    }
}
