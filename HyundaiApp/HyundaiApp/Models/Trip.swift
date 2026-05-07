import Foundation
import SwiftData

public enum TripMode: String, Codable {
    case evOnly
    case hybrid
    case iceOnly
    case mixed
    case unknown
}

@Model
public final class Trip {
    public var id: UUID = UUID()
    public var startAt: Date = Date()
    public var endAt: Date = Date()
    public var startOdometerKm: Double? = nil
    public var endOdometerKm: Double? = nil
    public var distanceKm: Double = 0
    public var startFuelPercent: Int? = nil
    public var endFuelPercent: Int? = nil
    public var startSoc: Int? = nil
    public var endSoc: Int? = nil
    public var estimatedKwh: Double? = nil
    public var estimatedLiters: Double? = nil
    public var modeRaw: String = TripMode.unknown.rawValue

    public var mode: TripMode {
        get { TripMode(rawValue: modeRaw) ?? .unknown }
        set { modeRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        startAt: Date = Date(),
        endAt: Date = Date(),
        startOdometerKm: Double? = nil,
        endOdometerKm: Double? = nil,
        distanceKm: Double = 0,
        startFuelPercent: Int? = nil,
        endFuelPercent: Int? = nil,
        startSoc: Int? = nil,
        endSoc: Int? = nil,
        estimatedKwh: Double? = nil,
        estimatedLiters: Double? = nil,
        mode: TripMode = .unknown
    ) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.startOdometerKm = startOdometerKm
        self.endOdometerKm = endOdometerKm
        self.distanceKm = distanceKm
        self.startFuelPercent = startFuelPercent
        self.endFuelPercent = endFuelPercent
        self.startSoc = startSoc
        self.endSoc = endSoc
        self.estimatedKwh = estimatedKwh
        self.estimatedLiters = estimatedLiters
        self.modeRaw = mode.rawValue
    }

    public convenience init(detected: DetectedTrip) {
        self.init(
            startAt: detected.startAt,
            endAt: detected.endAt,
            startOdometerKm: detected.startOdometerKm,
            endOdometerKm: detected.endOdometerKm,
            distanceKm: detected.distanceKm,
            startFuelPercent: detected.startFuelPercent,
            endFuelPercent: detected.endFuelPercent,
            startSoc: detected.startSoc,
            endSoc: detected.endSoc,
            estimatedKwh: detected.estimatedKwh,
            estimatedLiters: detected.estimatedLiters,
            mode: detected.mode
        )
    }
}
