import SwiftUI

@main
struct EvenlyApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            LocalizedRoot {
                HomeView()
            }
                .environment(app)
                .tint(.brand)
                .onOpenURL { app.open($0) }
                .task { await app.refreshMeta() }
                .onAppear { AppearanceController.shared.applySaved() }
        }
    }
}

/// Applies the chosen language's locale to system controls such as date pickers.
/// Reading `Localizer.shared` here makes the whole tree update when it changes.
private struct LocalizedRoot<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.environment(\.locale, Localizer.shared.locale)
    }
}
