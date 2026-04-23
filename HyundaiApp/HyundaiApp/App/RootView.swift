import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
                .tabItem {
                    Label("Dashboard", systemImage: "car.fill")
                }

            NavigationStack {
                ControlsView()
            }
                .tabItem {
                    Label("Controls", systemImage: "lock.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    RootView()
}
