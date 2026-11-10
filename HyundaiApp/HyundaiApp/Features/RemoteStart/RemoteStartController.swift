import Foundation
import SwiftUI

/// Tracks the current remote start for the Car screen and the Live Activity.
///
/// Battery-safety rules: this type never sends a vehicle command. It only
/// asks Bluelink whether the car confirmed one (`/actions/{id}`, a server
/// read) and asks the dashboard for saved status (`force=false`).
@MainActor
final class RemoteStartController: ObservableObject {
    /// Seconds between confirmation checks (matches the library's own pace).
    static let pollInterval: Duration = .seconds(10)
    /// While running and the app is open, how often to re-read saved status.
    static let statusInterval: TimeInterval = 120
    /// Outcomes older than this are dropped on launch.
    static let outcomeLifetime: TimeInterval = 60 * 60

    @Published private(set) var session: RemoteStartSession?

    /// Re-reads the backend's saved status. Must not force a refresh.
    var refreshSavedStatus: (() async -> Void)?
    var vehicleName = "Your car"

    private let client: CarAPIClient
    private let defaults: UserDefaults?
    private let liveActivity = RemoteStartLiveActivity()
    private var pollTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var lastStatusRequest: Date?

    private static let storageKey = "remoteStartSession"

    init(client: CarAPIClient, defaults: UserDefaults? = UserDefaults(suiteName: PersistenceController.appGroupIdentifier)) {
        self.client = client
        self.defaults = defaults
        session = Self.load(from: defaults)
        if let ended = session?.endedAt, Date().timeIntervalSince(ended) > Self.outcomeLifetime {
            session = nil
        }
        resume()
    }

    // MARK: - Events from the dashboard

    /// The start command was accepted by the backend.
    func began(response: CommandResponseDTO?, durationMinutes: Int, temperature: Double, defrost: Bool, batteryPercent: Int?) {
        session = RemoteStartSession(
            actionID: response?.actionID,
            sentAt: Date(),
            durationMinutes: durationMinutes,
            targetTemperature: temperature,
            defrost: defrost,
            startBatteryPercent: batteryPercent
        )
        commit()
        resume()
    }

    /// The stop command was accepted by the backend.
    func stopped() {
        update { $0.stopped(at: Date()) }
    }

    /// A saved-status read finished.
    func statusUpdated(_ status: StatusDTO?) {
        guard let status else { return }
        let statusTime = status.lastUpdatedAt.flatMap(VehicleStatusPresentation.parseDate)
        update {
            $0.applyStatus(
                engineRunning: status.engineIsRunning,
                climateOn: status.airControlIsOn,
                statusTime: statusTime,
                batteryPercent: status.evBatteryPercentage,
                at: Date()
            )
        }
    }

    func dismiss() {
        guard let session, !session.isActive else { return }
        self.session = nil
        commit()
    }

    // MARK: - Loops

    private func resume() {
        guard let session, session.isActive else { return }

        if session.shouldPollActionStatus(at: Date()), pollTask == nil {
            pollTask = Task { [weak self] in await self?.pollConfirmation() }
        }
        if clockTask == nil {
            clockTask = Task { [weak self] in await self?.runClock() }
        }
    }

    private func pollConfirmation() async {
        defer { pollTask = nil }
        while let session, let actionID = session.actionID, session.shouldPollActionStatus(at: Date()) {
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled else { return }
            do {
                let result = try await client.actionStatus(id: actionID)
                update { $0.applyActionStatus(result.status, at: Date()) }
            } catch {
                // A failed read just means we ask again next time; the
                // command itself is never re-sent.
                update { $0.expireConfirmationIfNeeded(at: Date()) }
            }
        }
    }

    private func runClock() async {
        defer { clockTask = nil }
        while let session, session.isActive {
            update { $0.tick(at: Date()) }

            let now = Date()
            let wantsStatus = self.session?.stage == .running || self.session?.stage == .unconfirmed
            if wantsStatus, now.timeIntervalSince(lastStatusRequest ?? .distantPast) >= Self.statusInterval {
                lastStatusRequest = now
                await refreshSavedStatus?()
            }

            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
        }
    }

    // MARK: - State

    private func update(_ change: (inout RemoteStartSession) -> Void) {
        guard var next = session else { return }
        change(&next)
        guard next != session else { return }
        session = next
        commit()
    }

    private func commit() {
        if let session, let data = try? JSONEncoder().encode(session) {
            defaults?.set(data, forKey: Self.storageKey)
        } else {
            defaults?.removeObject(forKey: Self.storageKey)
        }
        liveActivity.sync(session, vehicleName: vehicleName)
    }

    private static func load(from defaults: UserDefaults?) -> RemoteStartSession? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(RemoteStartSession.self, from: data)
    }
}
