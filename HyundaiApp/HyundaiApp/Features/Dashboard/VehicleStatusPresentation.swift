import Foundation

/// Pure, deterministic formatting of a vehicle status for the dashboard.
/// Views pass in the latest `StatusDTO` and render these values; no view
/// derives display strings itself.
public struct VehicleStatusPresentation: Equatable {
    public enum LockState: Equatable {
        case locked
        case unlocked
        case unknown
    }

    public enum ChargeState: Equatable {
        case charging
        case pluggedIn
        case unplugged
        case unknown
    }

    public enum Freshness: Equatable {
        case fresh
        case stale
        case unknown
    }

    /// Status older than this is flagged as stale on the dashboard.
    public static let staleAfter: TimeInterval = 6 * 60 * 60

    public let title: String
    public let subtitle: String?
    public let batteryFraction: Double?
    public let batteryText: String
    public let evRangeText: String
    public let fuelFraction: Double?
    public let fuelText: String
    public let fuelRangeText: String
    public let totalRangeText: String
    public let lockState: LockState
    public let chargeState: ChargeState
    public let outsideTemperatureText: String?
    public let updatedText: String
    public let freshness: Freshness

    public init(status: StatusDTO?, lastRefresh: Date?, now: Date) {
        title = Self.title(for: status)
        subtitle = Self.subtitle(for: status)

        batteryFraction = Self.fraction(status?.evBatteryPercentage)
        batteryText = Self.percentText(status?.evBatteryPercentage)
        evRangeText = Self.distanceText(status?.evDrivingRange, unit: status?.evDrivingRangeUnit)

        fuelFraction = Self.fraction(status?.fuelLevel)
        fuelText = Self.percentText(status?.fuelLevel)
        fuelRangeText = Self.distanceText(status?.fuelDrivingRange, unit: status?.fuelDrivingRangeUnit)
        totalRangeText = Self.distanceText(status?.totalDrivingRange, unit: status?.totalDrivingRangeUnit)

        switch status?.isLocked {
        case .some(true): lockState = .locked
        case .some(false): lockState = .unlocked
        case .none: lockState = .unknown
        }

        if status?.evBatteryIsCharging == true {
            chargeState = .charging
        } else if let plugged = status?.evBatteryIsPluggedIn {
            chargeState = plugged > 0 ? .pluggedIn : .unplugged
        } else if status?.evBatteryIsCharging == false {
            chargeState = .unplugged
        } else {
            chargeState = .unknown
        }

        outsideTemperatureText = status?.outsideTemperature.map { "\(Int($0.rounded()))°" }

        let updatedAt = status?.lastUpdatedAt.flatMap(Self.parseDate) ?? lastRefresh
        if let updatedAt {
            let age = max(0, now.timeIntervalSince(updatedAt))
            updatedText = "Updated \(Self.relativeText(age))"
            freshness = age > Self.staleAfter ? .stale : .fresh
        } else {
            updatedText = "Not updated yet"
            freshness = .unknown
        }
    }

    public var lockText: String {
        switch lockState {
        case .locked: return "Locked"
        case .unlocked: return "Unlocked"
        case .unknown: return "Lock unknown"
        }
    }

    public var lockSymbol: String {
        switch lockState {
        case .locked: return "lock.fill"
        case .unlocked: return "lock.open.fill"
        case .unknown: return "lock.trianglebadge.exclamationmark"
        }
    }

    public var chargeText: String {
        switch chargeState {
        case .charging: return "Charging"
        case .pluggedIn: return "Plugged in"
        case .unplugged: return "Not plugged in"
        case .unknown: return "Charging unknown"
        }
    }

    public var chargeSymbol: String {
        switch chargeState {
        case .charging: return "bolt.fill"
        case .pluggedIn: return "powerplug.fill"
        case .unplugged: return "powerplug"
        case .unknown: return "bolt.slash"
        }
    }

    // MARK: - Helpers

    static func title(for status: StatusDTO?) -> String {
        let model = status?.model?.trimmingCharacters(in: .whitespaces) ?? ""
        let name = status?.name?.trimmingCharacters(in: .whitespaces) ?? ""
        if !model.isEmpty { return Self.displayCase(model) }
        if !name.isEmpty { return Self.displayCase(name) }
        return "Your car"
    }

    static func subtitle(for status: StatusDTO?) -> String? {
        let year = status?.year.map(String.init)
        let name = status?.name?.trimmingCharacters(in: .whitespaces) ?? ""
        let model = status?.model?.trimmingCharacters(in: .whitespaces) ?? ""
        // The title shows the model; add the nickname only if it says something else.
        let nickname = (!name.isEmpty && !model.isEmpty && !model.localizedCaseInsensitiveContains(name))
            ? displayCase(name) : nil
        let parts = [year, nickname].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let acronyms: Set<String> = ["PHEV", "HEV", "EV", "N", "XRT", "AWD", "FWD"]

    /// Bluelink returns names in upper case ("TUCSON PHEV"). Keep known
    /// acronyms upper case and title-case the rest.
    static func displayCase(_ value: String) -> String {
        value.split(separator: " ").map { word in
            let text = String(word)
            if acronyms.contains(text.uppercased()) { return text.uppercased() }
            return text.prefix(1).uppercased() + text.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    public static func fraction(_ percent: Int?) -> Double? {
        guard let percent else { return nil }
        return min(max(Double(percent) / 100, 0), 1)
    }

    public static func percentText(_ percent: Int?) -> String {
        guard let percent else { return "—" }
        return "\(min(max(percent, 0), 100))%"
    }

    public static func distanceText(_ value: Double?, unit: String?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) \(Self.unitText(unit))"
    }

    static func unitText(_ unit: String?) -> String {
        let trimmed = unit?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        switch trimmed {
        case "mi", "mile", "miles": return "mi"
        default: return "km"
        }
    }

    public static func relativeText(_ age: TimeInterval) -> String {
        let minutes = Int(age / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h ago" }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    public static func parseDate(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
