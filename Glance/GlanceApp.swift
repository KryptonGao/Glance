import SwiftUI

@main
struct GlanceApp: App {
    init() {
        // Move provider settings saved by earlier builds into the shared App Group.
        _ = ProviderConfig.load()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
