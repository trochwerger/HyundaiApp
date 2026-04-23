import SwiftUI

struct ControlsView: View {
    @StateObject private var vm: ControlsViewModel
    @State private var dismissTask: Task<Void, Never>?

    init(client: CarAPIClient = CarAPIClient()) {
        _vm = StateObject(wrappedValue: ControlsViewModel(client: client))
    }

    var body: some View {
        VStack(spacing: 20) {
            commandButton(title: "Lock", command: "lock", tint: .blue) {
                await vm.lock()
            }

            commandButton(title: "Unlock", command: "unlock", tint: .orange) {
                await vm.unlock()
            }

            statusView

            Spacer()
        }
        .padding()
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
        command: String,
        tint: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack {
                Spacer()
                if vm.busyCommand == command {
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
        .disabled(vm.busyCommand != nil)
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
