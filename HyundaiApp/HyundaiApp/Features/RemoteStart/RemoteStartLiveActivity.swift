import ActivityKit
import Foundation

/// Starts, updates and ends the remote start Live Activity from the app.
/// Updates are local (no push token); the countdown renders on-device.
@MainActor
final class RemoteStartLiveActivity {
    private var activity: Activity<RemoteStartActivityAttributes>?

    init() {
        // Reattach to an activity left over from a previous launch.
        activity = Activity<RemoteStartActivityAttributes>.activities.first
    }

    func sync(_ session: RemoteStartSession?, vehicleName: String) {
        guard let session else {
            end(with: nil)
            return
        }

        let state = Self.contentState(for: session)

        if session.isActive {
            if let activity {
                Task { await activity.update(ActivityContent(state: state, staleDate: session.endsAt)) }
            } else {
                start(session, state: state, vehicleName: vehicleName)
            }
        } else {
            end(with: state)
        }
    }

    private func start(
        _ session: RemoteStartSession,
        state: RemoteStartActivityAttributes.ContentState,
        vehicleName: String
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RemoteStartActivityAttributes(
            vehicleName: vehicleName,
            targetTemperature: Int(session.targetTemperature.rounded())
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: session.endsAt),
            pushType: nil
        )
    }

    private func end(with state: RemoteStartActivityAttributes.ContentState?) {
        guard let activity else { return }
        self.activity = nil
        Task {
            if let state {
                // Leave the outcome on the Lock Screen briefly.
                await activity.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: .after(Date().addingTimeInterval(15 * 60))
                )
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    static func contentState(for session: RemoteStartSession) -> RemoteStartActivityAttributes.ContentState {
        switch session.stage {
        case .confirming, .unconfirmed:
            return .init(phase: .confirming, startedAt: nil, endsAt: nil, message: nil)
        case .running:
            return .init(phase: .running, startedAt: session.confirmedAt, endsAt: session.endsAt, message: nil)
        case .finished:
            let ran = session.ranFor.map { "Ran \(RemoteStartSession.durationText($0))" } ?? "Finished"
            return .init(phase: .finished, startedAt: nil, endsAt: nil, message: ran)
        case .failed:
            return .init(phase: .failed, startedAt: nil, endsAt: nil, message: session.failureMessage)
        }
    }
}
