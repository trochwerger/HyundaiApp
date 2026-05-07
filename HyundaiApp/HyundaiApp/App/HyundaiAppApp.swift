import SwiftUI
import SwiftData

@main
struct HyundaiAppApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(PersistenceController.shared)
        }
    }
}
