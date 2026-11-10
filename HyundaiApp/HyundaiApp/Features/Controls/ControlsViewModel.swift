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

        var inFlightMessage: String {
            switch self {
            case .lock:
                return "Locking…"
            case .unlock:
                return "Unlocking…"
            case .startClimate:
                return "Sending remote start…"
            case .stopClimate:
                return "Stopping climate…"
            case .chargeStart:
                return "Sending charge start…"
            case .chargeStop:
                return "Sending charge stop…"
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
                return "Remote start sent. Waiting for the car…"
            case .stopClimate:
                return "Remote start stopped."
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

    /// Sends a command once (never retried) and returns the backend's
    /// response on success.
    @discardableResult
    func perform(_ command: Command) async -> CommandResponseDTO? {
        busy = command
        defer { busy = nil }

        do {
            let response: CommandResponseDTO
            switch command {
            case .lock:
                response = try await client.lock()
            case .unlock:
                response = try await client.unlock()
            case .startClimate:
                response = try await client.startClimate(temp: startTemp, defrost: defrost, duration: startDuration)
            case .stopClimate:
                response = try await client.stopClimate()
            case .chargeStart:
                response = try await client.chargeStart()
            case .chargeStop:
                response = try await client.chargeStop()
            }

            lastResult = .success(command.successMessage)
            return response
        } catch {
            lastResult = .failure(error.localizedDescription)
            return nil
        }
    }

    func clearResult() {
        lastResult = nil
    }
}
