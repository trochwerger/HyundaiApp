import Foundation

/// One remote start, from "sent" to "finished" or "failed".
///
/// Pure and deterministic: every transition takes `now` and the facts the app
/// learned (Bluelink's action status, the saved vehicle status). Nothing here
/// talks to the network or decides to send a command.
public struct RemoteStartSession: Codable, Equatable {
    public enum Stage: String, Codable, Equatable {
        /// Command sent; waiting for the car to confirm.
        case confirming
        /// The car didn't answer in time. It may or may not be running;
        /// saved status can still confirm it.
        case unconfirmed
        /// The car confirmed; engine and climate on.
        case running
        /// Hyundai reported the start failed.
        case failed
        /// Time ran out, the user stopped it, or saved status shows it off.
        case finished
    }

    /// How long to keep asking Bluelink for the command's outcome.
    public static let confirmationTimeout: TimeInterval = 120
    /// Saved status must be at least this much newer than the confirmation
    /// before an "engine off" reading ends the session early.
    public static let statusGrace: TimeInterval = 30

    public var actionID: String?
    public var sentAt: Date
    public var durationMinutes: Int
    public var targetTemperature: Double
    public var defrost: Bool
    public var stage: Stage
    public var confirmedAt: Date?
    public var endedAt: Date?
    public var failureMessage: String?
    public var startBatteryPercent: Int?
    public var endBatteryPercent: Int?

    public init(
        actionID: String?,
        sentAt: Date,
        durationMinutes: Int,
        targetTemperature: Double,
        defrost: Bool,
        startBatteryPercent: Int?
    ) {
        self.actionID = actionID
        self.sentAt = sentAt
        self.durationMinutes = max(1, durationMinutes)
        self.targetTemperature = targetTemperature
        self.defrost = defrost
        self.stage = .confirming
        self.startBatteryPercent = startBatteryPercent
    }

    // MARK: - Derived values

    public var duration: TimeInterval { TimeInterval(durationMinutes * 60) }

    public var endsAt: Date? { confirmedAt.map { $0.addingTimeInterval(duration) } }

    public var isActive: Bool {
        stage == .confirming || stage == .unconfirmed || stage == .running
    }

    public func remaining(at now: Date) -> TimeInterval {
        guard stage == .running, let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// Fraction of the run time left, 1 → 0.
    public func remainingFraction(at now: Date) -> Double {
        guard stage == .running else { return 0 }
        return min(1, max(0, remaining(at: now) / duration))
    }

    public func shouldPollActionStatus(at now: Date) -> Bool {
        stage == .confirming && actionID != nil
            && now.timeIntervalSince(sentAt) <= Self.confirmationTimeout
    }

    public var ranFor: TimeInterval? {
        guard let confirmedAt, let endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(confirmedAt))
    }

    public var batteryUsed: Int? {
        guard let start = startBatteryPercent, let end = endBatteryPercent else { return nil }
        return max(0, start - end)
    }

    // MARK: - Transitions

    /// Applies Bluelink's answer for the command ("pending", "success", "failed", "timeout").
    public mutating func applyActionStatus(_ status: String, at now: Date) {
        guard stage == .confirming else { return }
        switch status.lowercased() {
        case "success":
            stage = .running
            confirmedAt = now
        case "failed":
            stage = .failed
            endedAt = now
            failureMessage = "Hyundai reported the remote start failed."
        case "timeout":
            stage = .unconfirmed
        default:
            expireConfirmationIfNeeded(at: now)
        }
    }

    /// Stops waiting once the confirmation window has passed.
    public mutating func expireConfirmationIfNeeded(at now: Date) {
        if stage == .confirming, now.timeIntervalSince(sentAt) > Self.confirmationTimeout {
            stage = .unconfirmed
        }
    }

    /// Applies a saved (cached) vehicle status read.
    public mutating func applyStatus(
        engineRunning: Bool?,
        climateOn: Bool?,
        statusTime: Date?,
        batteryPercent: Int?,
        at now: Date
    ) {
        let isOn = engineRunning == true || climateOn == true
        let isOff = engineRunning == false && climateOn != true

        switch stage {
        case .confirming, .unconfirmed:
            // Saved status taken after we sent the command and showing the
            // engine on is confirmation enough.
            if isOn, let statusTime, statusTime >= sentAt {
                stage = .running
                confirmedAt = statusTime
            }
        case .running:
            guard let confirmedAt else { return }
            if isOff, let statusTime,
               statusTime.timeIntervalSince(confirmedAt) > Self.statusGrace {
                finish(at: min(statusTime, now), batteryPercent: batteryPercent)
            } else if let batteryPercent {
                endBatteryPercent = batteryPercent
            }
        case .failed, .finished:
            break
        }
    }

    /// Ends the session when the run time is up, or gives up on a start the
    /// car never confirmed once it would have ended anyway.
    public mutating func tick(at now: Date) {
        expireConfirmationIfNeeded(at: now)
        if stage == .running, let endsAt, now >= endsAt {
            finish(at: endsAt, batteryPercent: nil)
        } else if stage == .unconfirmed,
                  now.timeIntervalSince(sentAt) > duration + Self.confirmationTimeout {
            stage = .failed
            endedAt = now
            failureMessage = "The car never confirmed the remote start."
        }
    }

    /// The user's stop command succeeded.
    public mutating func stopped(at now: Date) {
        guard isActive else { return }
        if confirmedAt == nil { confirmedAt = sentAt }
        finish(at: now, batteryPercent: nil)
    }

    private mutating func finish(at time: Date, batteryPercent: Int?) {
        stage = .finished
        endedAt = time
        if let batteryPercent { endBatteryPercent = batteryPercent }
    }

    // MARK: - Formatting

    /// "8:42" style countdown.
    public static func countdownText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "10 min", "45 s".
    public static func durationText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 { return "\(seconds) s" }
        return "\(Int((Double(seconds) / 60).rounded())) min"
    }
}
