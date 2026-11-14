import SwiftUI

@main
struct EvenlyApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(app)
                .tint(.brand)
                .onOpenURL { app.open($0) }
                .task { await app.refreshMeta() }
        }
    }
}
