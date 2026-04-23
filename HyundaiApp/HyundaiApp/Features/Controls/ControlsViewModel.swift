import SwiftUI

@MainActor
final class ControlsViewModel: ObservableObject {
    enum Result: Equatable {
        case success(String)
        case failure(String)
    }

    @Published var busyCommand: String?
    @Published var lastResult: Result?

    let client: CarAPIClient

    init(client: CarAPIClient = CarAPIClient()) {
        self.client = client
    }

    func lock() async {
        busyCommand = "lock"
        defer { busyCommand = nil }

        do {
            let response = try await client.lock()
            lastResult = .success(response.ok ? "Vehicle locked." : "Lock command completed.")
        } catch {
            lastResult = .failure(error.localizedDescription)
        }
    }

    func unlock() async {
        busyCommand = "unlock"
        defer { busyCommand = nil }

        do {
            let response = try await client.unlock()
            lastResult = .success(response.ok ? "Vehicle unlocked." : "Unlock command completed.")
        } catch {
            lastResult = .failure(error.localizedDescription)
        }
    }

    func clearResult() {
        lastResult = nil
    }
}
