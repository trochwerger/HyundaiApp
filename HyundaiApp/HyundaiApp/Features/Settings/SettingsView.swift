import SwiftUI

struct SettingsView: View {
    @AppStorage("debugScreenEnabled") private var debugScreenEnabled = false

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Pairing") {
                    PairingView()
                }

                Section("Debug") {
                    Toggle("Show debug tools", isOn: $debugScreenEnabled)

                    if debugScreenEnabled {
                        NavigationLink("Snapshots & Trips") {
                            DebugView()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
