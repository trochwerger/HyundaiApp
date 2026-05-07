import SwiftUI

struct ControlsView: View {
    @StateObject private var vm: ControlsViewModel
    @State private var dismissTask: Task<Void, Never>?

    init(client: CarAPIClient = CarAPIClient()) {
        _vm = StateObject(wrappedValue: ControlsViewModel(client: client))
    }

    var body: some View {
        Form {
            Section("Lock / Unlock") {
                HStack(spacing: 12) {
                    commandButton(title: "Lock", command: .lock, tint: .blue)
                    commandButton(title: "Unlock", command: .unlock, tint: .orange)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section("Remote Start") {
                Stepper(value: $vm.startTemp, in: 17...27, step: 1) {
                    Text("Cabin temp: \(Int(vm.startTemp)) °C")
                }

                Stepper(value: $vm.startDuration, in: 1...30, step: 1) {
                    Text("Duration: \(vm.startDuration) min")
                }

                Toggle("Defrost", isOn: $vm.defrost)

                commandButton(title: "Start", command: .startClimate, tint: .green)
            }

            Section {
                commandButton(title: "Stop climate", command: .stopClimate, tint: .red)
            }

            Section("Charging") {
                commandButton(title: "Charge start", command: .chargeStart, tint: .teal)
                commandButton(title: "Charge stop", command: .chargeStop, tint: .pink)
            }

            Section {
                statusView
            }
        }
        .navigationTitle("Controls")
        .onChange(of: vm.lastResult) { _, newValue in
            dismissTask?.cancel()

            guard newValue != nil else { return }
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    vm.clearResult()
                }
            }
        }
    }

    private func commandButton(
        title: String,
        command: ControlsViewModel.Command,
        tint: Color,
    ) -> some View {
        Button {
            Task {
                await vm.perform(command)
            }
        } label: {
            HStack {
                Spacer()
                if vm.busy == command {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.headline)
                }
                Spacer()
            }
            .frame(minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(vm.busy != nil)
    }

    @ViewBuilder
    private var statusView: some View {
        switch vm.lastResult {
        case .success(let message):
            statusLabel(message: message, systemImage: "checkmark.circle.fill", color: .green)
        case .failure(let message):
            statusLabel(message: message, systemImage: "xmark.circle.fill", color: .red)
        case nil:
            Text("Send a command to update the vehicle state.")
                .foregroundStyle(.secondary)
        }
    }

    private func statusLabel(message: String, systemImage: String, color: Color) -> some View {
        Label(message, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(color)
            .onTapGesture {
                dismissTask?.cancel()
                vm.clearResult()
            }
    }
}

#Preview {
    NavigationStack {
        ControlsView()
    }
}
