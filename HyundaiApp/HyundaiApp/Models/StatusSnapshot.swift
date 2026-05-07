import Foundation
import SwiftData

@Model
public final class StatusSnapshot {
    public var id: UUID = UUID()
    public var timestamp: Date = Date()
    public var odometerKm: Double? = nil
    public var fuelPercent: Int? = nil
    public var evBatteryPercent: Int? = nil
    public var evRangeKm: Double? = nil
    public var fuelRangeKm: Double? = nil
    public var isLocked: Bool? = nil
    public var isCharging: Bool? = nil
    public var engineIsRunning: Bool? = nil
    public var latitude: Double? = nil
    public var longitude: Double? = nil
    public var rawJSON: String = ""

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        odometerKm: Double? = nil,
        fuelPercent: Int? = nil,
        evBatteryPercent: Int? = nil,
        evRangeKm: Double? = nil,
        fuelRangeKm: Double? = nil,
        isLocked: Bool? = nil,
        isCharging: Bool? = nil,
        engineIsRunning: Bool? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        rawJSON: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.odometerKm = odometerKm
        self.fuelPercent = fuelPercent
        self.evBatteryPercent = evBatteryPercent
        self.evRangeKm = evRangeKm
        self.fuelRangeKm = fuelRangeKm
        self.isLocked = isLocked
        self.isCharging = isCharging
        self.engineIsRunning = engineIsRunning
        self.latitude = latitude
        self.longitude = longitude
        self.rawJSON = rawJSON
    }

    public static func make(from dto: StatusDTO, rawJSON: String, receivedAt: Date = Date()) -> StatusSnapshot {
        StatusSnapshot(
            timestamp: parsedTimestamp(from: dto.lastUpdatedAt, fallback: receivedAt),
            odometerKm: convertedDistance(dto.odometer, unit: dto.odometerUnit),
            fuelPercent: dto.fuelLevel,
            evBatteryPercent: dto.evBatteryPercentage,
            evRangeKm: convertedDistance(dto.evDrivingRange, unit: dto.evDrivingRangeUnit),
            fuelRangeKm: convertedDistance(dto.fuelDrivingRange, unit: dto.fuelDrivingRangeUnit),
            isLocked: dto.isLocked,
            isCharging: dto.evBatteryIsCharging,
            engineIsRunning: dto.engineIsRunning,
            latitude: dto.location?.latitude,
            longitude: dto.location?.longitude,
            rawJSON: rawJSON
        )
    }

    private static func parsedTimestamp(from rawValue: String?, fallback: Date) -> Date {
        guard let rawValue, !rawValue.isEmpty else {
            return fallback
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: rawValue) {
            return date
        }

        let plainFormatter = ISO8601DateFormatter()
        if let date = plainFormatter.date(from: rawValue) {
            return date
        }

        return fallback
    }

    private static func convertedDistance(_ value: Double?, unit: String?) -> Double? {
        guard let value else {
            return nil
        }

        guard unit?.lowercased().hasPrefix("mi") == true else {
            return value
        }

        return value * 1.609344
    }
}

public extension StatusSnapshot {
    var snapshotInput: SnapshotInput {
        SnapshotInput(
            timestamp: timestamp,
            odometerKm: odometerKm,
            fuelPercent: fuelPercent,
            evBatteryPercent: evBatteryPercent,
            engineIsRunning: engineIsRunning
        )
    }
}
