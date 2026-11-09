import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Car", systemImage: "car.fill") {
                NavigationStack {
                    DashboardView()
                }
            }

            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
    }
}

#Preview {
    RootView()
}
