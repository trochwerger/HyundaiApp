import ActivityKit
import Foundation

/// Live Activity data for a remote start. Compiled into both the app and the
/// widget extension. The countdown is rendered on-device from `endsAt`, so
/// the activity keeps ticking with no network access.
struct RemoteStartActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case confirming
            case running
            case finished
            case failed
        }

        var phase: Phase
        /// When the car confirmed (countdown start).
        var startedAt: Date?
        /// When the run ends (countdown target).
        var endsAt: Date?
        /// Short line for finished / failed states.
        var message: String?
    }

    var vehicleName: String
    var targetTemperature: Int

    /// Opens the app and asks to confirm stopping. The extension never sends
    /// vehicle commands itself.
    static let stopURL = URL(string: "hyundaiapp://remote-start/stop")!
}
