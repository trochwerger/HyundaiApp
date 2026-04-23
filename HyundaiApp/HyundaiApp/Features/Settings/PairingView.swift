import SwiftUI

struct PairingView: View {
    @StateObject private var vm = PairingViewModel()

    var body: some View {
        Form {
            Section("Backend") {
                TextField("Backend URL", text: $vm.backendURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("API key", text: $vm.apiKey)
            }

            Section("Actions") {
                Button("Save") {
                    do {
                        try vm.save()
                    } catch {
                        vm.testState = .failure(error.localizedDescription)
                    }
                }

                Button("Test connection") {
                    Task {
                        await vm.testConnection()
                    }
                }
                .disabled(vm.testState == .testing)
            }

            Section {
                statusView
            }
        }
        .navigationTitle("Pairing")
    }

    @ViewBuilder
    private var statusView: some View {
        switch vm.testState {
        case .idle:
            Text("Enter your backend URL and API key to connect.")
                .foregroundStyle(.secondary)
        case .testing:
            HStack(spacing: 12) {
                ProgressView()
                Text("Testing connection…")
            }
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    NavigationStack {
        PairingView()
    }
}
