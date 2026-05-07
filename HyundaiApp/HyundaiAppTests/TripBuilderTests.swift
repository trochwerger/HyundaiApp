import XCTest
import HyundaiApp

final class TripBuilderTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testEmptyInputProducesNoTrips() {
        XCTAssertTrue(TripBuilder.buildTrips(from: []).isEmpty)
    }

    func testSingleSnapshotProducesNoTrips() {
        let trips = TripBuilder.buildTrips(from: [
            snapshot(at: 0, odometerKm: 1_000, fuelPercent: 80, evBatteryPercent: 60, engineIsRunning: true)
        ])

        XCTAssertTrue(trips.isEmpty)
    }

    func testIgnitionModeDetectsSingleEvTrip() {
        let trips = TripBuilder.buildTrips(from: [
            snapshot(at: 0, odometerKm: 1_000, fuelPercent: 80, evBatteryPercent: 60, engineIsRunning: false),
            snapshot(at: 60, odometerKm: 1_000, fuelPercent: 80, evBatteryPercent: 60, engineIsRunning: true),
            snapshot(at: 600, odometerKm: 1_008, fuelPercent: 80, evBatteryPercent: 53, engineIsRunning: true),
            snapshot(at: 1_200, odometerKm: 1_015, fuelPercent: 80, evBatteryPercent: 50, engineIsRunning: false),
        ])

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].distanceKm, 15, accuracy: 0.001)
        XCTAssertEqual(trips[0].mode, .evOnly)
    }

    func testIgnitionModeClosesOpenTripAtLastSnapshot() {
        let trips = TripBuilder.buildTrips(from: [
            snapshot(at: 0, odometerKm: 2_000, fuelPercent: 75, evBatteryPercent: 55, engineIsRunning: false),
            snapshot(at: 120, odometerKm: 2_000, fuelPercent: 75, evBatteryPercent: 55, engineIsRunning: true),
            snapshot(at: 900, odometerKm: 2_012, fuelPercent: 74, evBatteryPercent: 49, engineIsRunning: true),
        ])

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].endAt, referenceDate.addingTimeInterval(900))
        XCTAssertEqual(trips[0].distanceKm, 12, accuracy: 0.001)
    }

    func testIgnitionModeDropsTinyJitterTrips() {
        let trips = TripBuilder.buildTrips(from: [
            snapshot(at: 0, odometerKm: 500, fuelPercent: 70, evBatteryPercent: 50, engineIsRunning: false),
            snapshot(at: 60, odometerKm: 500, fuelPercent: 70, evBatteryPercent: 50, engineIsRunning: true),
            snapshot(at: 180, odometerKm: 500.2, fuelPercent: 70, evBatteryPercent: 49, engineIsRunning: false),
        ])

        XCTAssertTrue(trips.isEmpty)
    }

    func testOdometerModeDetectsTwoTripsWithExpectedModes() {
        let trips = TripBuilder.buildTrips(from: [
            snapshot(at: 0, odometerKm: 100, fuelPercent: 80, evBatteryPercent: 70, engineIsRunning: nil),
            snapshot(at: 300, odometerKm: 104, fuelPercent: 79, evBatteryPercent: 68, engineIsRunning: nil),
            snapshot(at: 600, odometerKm: 108, fuelPercent: 78, evBatteryPercent: 65, engineIsRunning: nil),
            snapshot(at: 2_100, odometerKm: 108, fuelPercent: 78, evBatteryPercent: 65, engineIsRunning: nil),
            snapshot(at: 2_400, odometerKm: 112, fuelPercent: 77, evBatteryPercent: 65, engineIsRunning: nil),
            snapshot(at: 2_700, odometerKm: 118, fuelPercent: 76, evBatteryPercent: 65, engineIsRunning: nil),
        ])

        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(trips[0].mode, .hybrid)
        XCTAssertEqual(trips[1].mode, .iceOnly)
    }

    func testOdometerModeSplitsTripAcrossLongInterSnapshotGap() {
        let trips = TripBuilder.buildTrips(from: [
            snapshot(at: 0, odometerKm: 100, fuelPercent: 80, evBatteryPercent: 70, engineIsRunning: nil),
            snapshot(at: 300, odometerKm: 103, fuelPercent: 79, evBatteryPercent: 69, engineIsRunning: nil),
            snapshot(at: 18_000, odometerKm: 107, fuelPercent: 78, evBatteryPercent: 68, engineIsRunning: nil),
            snapshot(at: 18_300, odometerKm: 111, fuelPercent: 77, evBatteryPercent: 67, engineIsRunning: nil),
        ])

        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(trips[0].distanceKm, 3, accuracy: 0.001)
        XCTAssertEqual(trips[1].distanceKm, 4, accuracy: 0.001)
    }

    func testModeClassificationEvOnly() {
        XCTAssertEqual(classifyTrip(startFuel: 80, endFuel: 80, startSoc: 60, endSoc: 55), .evOnly)
    }

    func testModeClassificationHybrid() {
        XCTAssertEqual(classifyTrip(startFuel: 80, endFuel: 79, startSoc: 60, endSoc: 55), .hybrid)
    }

    func testModeClassificationIceOnly() {
        XCTAssertEqual(classifyTrip(startFuel: 80, endFuel: 79, startSoc: 60, endSoc: 60), .iceOnly)
    }

    func testModeClassificationMixed() {
        XCTAssertEqual(classifyTrip(startFuel: 80, endFuel: 80, startSoc: 60, endSoc: 60), .mixed)
    }

    func testModeClassificationUnknownWhenDataIsMissing() {
        let trips = TripBuilder.buildTrips(from: [
            snapshot(at: 0, odometerKm: 100, fuelPercent: 80, evBatteryPercent: nil, engineIsRunning: nil),
            snapshot(at: 300, odometerKm: 104, fuelPercent: 80, evBatteryPercent: nil, engineIsRunning: nil),
        ])

        XCTAssertEqual(trips.first?.mode, .unknown)
    }

    func testEnergyAndFuelEstimatesMatchExpectedMath() {
        let trips = TripBuilder.buildTrips(from: [
            snapshot(at: 0, odometerKm: 100, fuelPercent: 80, evBatteryPercent: 70, engineIsRunning: nil),
            snapshot(at: 300, odometerKm: 105, fuelPercent: 75, evBatteryPercent: 60, engineIsRunning: nil),
        ])

        XCTAssertEqual(trips.count, 1)
        XCTAssertNotNil(trips[0].estimatedKwh)
        XCTAssertNotNil(trips[0].estimatedLiters)
        XCTAssertEqual(trips[0].estimatedKwh ?? 0, 1.38, accuracy: 0.0001)
        XCTAssertEqual(trips[0].estimatedLiters ?? 0, 2.1, accuracy: 0.0001)
    }

    private func classifyTrip(startFuel: Int?, endFuel: Int?, startSoc: Int?, endSoc: Int?) -> TripMode? {
        let trips = TripBuilder.buildTrips(from: [
            snapshot(at: 0, odometerKm: 100, fuelPercent: startFuel, evBatteryPercent: startSoc, engineIsRunning: nil),
            snapshot(at: 300, odometerKm: 104, fuelPercent: endFuel, evBatteryPercent: endSoc, engineIsRunning: nil),
        ])

        return trips.first?.mode
    }

    private func snapshot(
        at offset: TimeInterval,
        odometerKm: Double?,
        fuelPercent: Int?,
        evBatteryPercent: Int?,
        engineIsRunning: Bool?
    ) -> SnapshotInput {
        SnapshotInput(
            timestamp: referenceDate.addingTimeInterval(offset),
            odometerKm: odometerKm,
            fuelPercent: fuelPercent,
            evBatteryPercent: evBatteryPercent,
            engineIsRunning: engineIsRunning
        )
    }
}
