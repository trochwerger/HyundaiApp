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
        }
        .overlay(alignment: .top) {
            if vm.busy != nil || vm.lastResult != nil {
                CommandStatusBanner(busy: vm.busy, result: vm.lastResult) {
                    dismissTask?.cancel()
                    vm.clearResult()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.busy)
        .animation(.easeInOut(duration: 0.2), value: vm.lastResult)
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
}

private struct CommandStatusBanner: View {
    let busy: ControlsViewModel.Command?
    let result: ControlsViewModel.Result?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let busy {
                ProgressView()
                Text(busy.inFlightMessage)
            } else if let result {
                switch result {
                case .success(let message):
                    Image(systemName: "checkmark.circle.fill")
                    Text(message)
                case .failure(let message):
                    Image(systemName: "xmark.circle.fill")
                    Text(message)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(foregroundColor)
        .onTapGesture {
            guard busy == nil, result != nil else { return }
            dismiss()
        }
    }

    private var backgroundColor: Color {
        guard busy == nil, let result else {
            return Color.secondary.opacity(0.15)
        }

        switch result {
        case .success:
            return Color.green.opacity(0.12)
        case .failure:
            return Color.red.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        guard busy == nil, let result else {
            return .primary
        }

        switch result {
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
}

#Preview {
    NavigationStack {
        ControlsView()
    }
}
