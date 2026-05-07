import SwiftUI

@MainActor
final class ControlsViewModel: ObservableObject {
    enum Command: String, Equatable {
        case lock
        case unlock
        case startClimate
        case stopClimate
        case chargeStart
        case chargeStop

        var displayName: String {
            switch self {
            case .lock:
                return "Lock"
            case .unlock:
                return "Unlock"
            case .startClimate:
                return "Remote start"
            case .stopClimate:
                return "Stop climate"
            case .chargeStart:
                return "Charge start"
            case .chargeStop:
                return "Charge stop"
            }
        }

        var command: String {
            switch self {
            case .lock:
                return "lock"
            case .unlock:
                return "unlock"
            case .startClimate:
                return "startClimate"
            case .stopClimate:
                return "stopClimate"
            case .chargeStart:
                return "chargeStart"
            case .chargeStop:
                return "chargeStop"
            }
        }

        var successMessage: String {
            switch self {
            case .lock:
                return "Vehicle locked."
            case .unlock:
                return "Vehicle unlocked."
            case .startClimate:
                return "Remote start sent."
            case .stopClimate:
                return "Climate stop sent."
            case .chargeStart:
                return "Charging start sent."
            case .chargeStop:
                return "Charging stop sent."
            }
        }
    }

    enum Result: Equatable {
        case success(String)
        case failure(String)
    }

    @Published var busy: Command?
    @Published var lastResult: Result?
    @Published var startTemp: Double = 22
    @Published var startDuration: Int = 10
    @Published var defrost: Bool = false

    let client: CarAPIClient

    init(client: CarAPIClient = CarAPIClient()) {
        self.client = client
    }

    func perform(_ command: Command) async {
        busy = command
        defer { busy = nil }

        do {
            switch command {
            case .lock:
                _ = try await client.lock()
            case .unlock:
                _ = try await client.unlock()
            case .startClimate:
                _ = try await client.startClimate(temp: startTemp, defrost: defrost, duration: startDuration)
            case .stopClimate:
                _ = try await client.stopClimate()
            case .chargeStart:
                _ = try await client.chargeStart()
            case .chargeStop:
                _ = try await client.chargeStop()
            }

            lastResult = .success(command.successMessage)
        } catch {
            lastResult = .failure(error.localizedDescription)
        }
    }

    func clearResult() {
        lastResult = nil
    }
}
