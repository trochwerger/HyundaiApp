import Foundation

public struct SnapshotInput: Equatable {
    public let timestamp: Date
    public let odometerKm: Double?
    public let fuelPercent: Int?
    public let evBatteryPercent: Int?
    public let engineIsRunning: Bool?

    public init(
        timestamp: Date,
        odometerKm: Double?,
        fuelPercent: Int?,
        evBatteryPercent: Int?,
        engineIsRunning: Bool?
    ) {
        self.timestamp = timestamp
        self.odometerKm = odometerKm
        self.fuelPercent = fuelPercent
        self.evBatteryPercent = evBatteryPercent
        self.engineIsRunning = engineIsRunning
    }
}

public struct DetectedTrip: Equatable {
    public let startAt: Date
    public let endAt: Date
    public let startOdometerKm: Double?
    public let endOdometerKm: Double?
    public let distanceKm: Double
    public let startFuelPercent: Int?
    public let endFuelPercent: Int?
    public let startSoc: Int?
    public let endSoc: Int?
    public let estimatedKwh: Double?
    public let estimatedLiters: Double?
    public let mode: TripMode

    public init(
        startAt: Date,
        endAt: Date,
        startOdometerKm: Double?,
        endOdometerKm: Double?,
        distanceKm: Double,
        startFuelPercent: Int?,
        endFuelPercent: Int?,
        startSoc: Int?,
        endSoc: Int?,
        estimatedKwh: Double?,
        estimatedLiters: Double?,
        mode: TripMode
    ) {
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
        self.mode = mode
    }
}

public enum TripBuilder {
    public struct Constants {
        public static let phevBatteryKwh: Double = 13.8
        public static let phevTankLiters: Double = 42.0
        public static let minOdometerDeltaKm: Double = 0.3
        public static let idleCloseGapSeconds: TimeInterval = 20 * 60
        public static let maxInterSnapshotGapSeconds: TimeInterval = 4 * 60 * 60
    }

    public static func buildTrips(from snapshots: [SnapshotInput]) -> [DetectedTrip] {
        let ordered = snapshots.sorted { $0.timestamp < $1.timestamp }
        guard ordered.count >= 2 else {
            return []
        }

        if ordered.contains(where: { $0.engineIsRunning != nil }) {
            return buildIgnitionTrips(from: ordered)
        }

        return buildOdometerTrips(from: ordered)
    }

    private static func buildIgnitionTrips(from snapshots: [SnapshotInput]) -> [DetectedTrip] {
        var trips: [DetectedTrip] = []
        var startSnapshot: SnapshotInput?

        for snapshot in snapshots {
            switch (startSnapshot != nil, snapshot.engineIsRunning) {
            case (false, .some(true)):
                startSnapshot = snapshot
            case (true, .some(false)):
                if let startSnapshot, let trip = makeTrip(start: startSnapshot, end: snapshot) {
                    trips.append(trip)
                }
                startSnapshot = nil
            default:
                continue
            }
        }

        if let startSnapshot, let lastSnapshot = snapshots.last, let trip = makeTrip(start: startSnapshot, end: lastSnapshot) {
            trips.append(trip)
        }

        return trips
    }

    private static func buildOdometerTrips(from snapshots: [SnapshotInput]) -> [DetectedTrip] {
        var trips: [DetectedTrip] = []
        var tripStart: SnapshotInput?
        var lastDriveEnd: SnapshotInput?

        for index in 0..<(snapshots.count - 1) {
            let current = snapshots[index]
            let next = snapshots[index + 1]
            let timeDelta = next.timestamp.timeIntervalSince(current.timestamp)
            let odometerDelta: Double?
            if let currentOdometer = current.odometerKm, let nextOdometer = next.odometerKm {
                odometerDelta = nextOdometer - currentOdometer
            } else {
                odometerDelta = nil
            }
            let isDriveEvent = timeDelta <= Constants.maxInterSnapshotGapSeconds
                && (odometerDelta ?? -1) >= Constants.minOdometerDeltaKm

            if isDriveEvent {
                if tripStart == nil {
                    tripStart = current
                }
                lastDriveEnd = next
                continue
            }

            guard let start = tripStart, let end = lastDriveEnd else {
                continue
            }

            let idleGap = next.timestamp.timeIntervalSince(end.timestamp)
            if idleGap > Constants.idleCloseGapSeconds || timeDelta > Constants.maxInterSnapshotGapSeconds {
                if let trip = makeTrip(start: start, end: end) {
                    trips.append(trip)
                }
                tripStart = nil
                lastDriveEnd = nil
            }
        }

        if let start = tripStart, let end = lastDriveEnd, let trip = makeTrip(start: start, end: end) {
            trips.append(trip)
        }

        return trips
    }

    private static func makeTrip(start: SnapshotInput, end: SnapshotInput) -> DetectedTrip? {
        let distanceKm = max(0, (end.odometerKm ?? start.odometerKm ?? 0) - (start.odometerKm ?? end.odometerKm ?? 0))
        if let startOdometerKm = start.odometerKm,
           let endOdometerKm = end.odometerKm,
           endOdometerKm - startOdometerKm < Constants.minOdometerDeltaKm {
            return nil
        }

        return DetectedTrip(
            startAt: start.timestamp,
            endAt: end.timestamp,
            startOdometerKm: start.odometerKm,
            endOdometerKm: end.odometerKm,
            distanceKm: distanceKm,
            startFuelPercent: start.fuelPercent,
            endFuelPercent: end.fuelPercent,
            startSoc: start.evBatteryPercent,
            endSoc: end.evBatteryPercent,
            estimatedKwh: estimatedKwh(startSoc: start.evBatteryPercent, endSoc: end.evBatteryPercent),
            estimatedLiters: estimatedLiters(startFuel: start.fuelPercent, endFuel: end.fuelPercent),
            mode: mode(start: start, end: end, distanceKm: distanceKm)
        )
    }

    private static func estimatedKwh(startSoc: Int?, endSoc: Int?) -> Double? {
        guard let startSoc, let endSoc, startSoc > endSoc else {
            return nil
        }

        return Double(startSoc - endSoc) / 100.0 * Constants.phevBatteryKwh
    }

    private static func estimatedLiters(startFuel: Int?, endFuel: Int?) -> Double? {
        guard let startFuel, let endFuel, startFuel > endFuel else {
            return nil
        }

        return Double(startFuel - endFuel) / 100.0 * Constants.phevTankLiters
    }

    private static func mode(start: SnapshotInput, end: SnapshotInput, distanceKm: Double) -> TripMode {
        guard let startSoc = start.evBatteryPercent,
              let endSoc = end.evBatteryPercent,
              let startFuel = start.fuelPercent,
              let endFuel = end.fuelPercent else {
            return .unknown
        }

        let socDropped = startSoc - endSoc >= 1
        let fuelDropped = startFuel - endFuel >= 1

        switch (socDropped, fuelDropped) {
        case (true, true):
            return .hybrid
        case (true, false):
            return .evOnly
        case (false, true):
            return .iceOnly
        case (false, false):
            return distanceKm > 0 ? .mixed : .unknown
        }
    }
}
