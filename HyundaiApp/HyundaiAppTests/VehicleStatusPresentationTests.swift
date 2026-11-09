import Foundation
import XCTest
import HyundaiApp

final class VehicleStatusPresentationTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-09T23:00:00Z")!

    private func status(_ json: String) throws -> StatusDTO {
        try JSONDecoder().decode(StatusDTO.self, from: Data(json.utf8))
    }

    func testFullStatusFormatsEveryField() throws {
        let dto = try status("""
        {
          "name": "TUCSON",
          "model": "TUCSON PHEV",
          "year": 2025,
          "ev_battery_percentage": 81,
          "ev_driving_range": 47.6,
          "ev_driving_range_unit": "km",
          "fuel_level": 59,
          "fuel_driving_range": 402.2,
          "total_driving_range": 450,
          "total_driving_range_unit": "km",
          "is_locked": true,
          "ev_battery_is_charging": false,
          "ev_battery_is_plugged_in": 0,
          "outside_temperature": 4.6,
          "last_updated_at": "2026-11-09T22:52:00+00:00"
        }
        """)

        let p = VehicleStatusPresentation(status: dto, lastRefresh: nil, now: now)

        XCTAssertEqual(p.title, "Tucson PHEV")
        XCTAssertEqual(p.subtitle, "2025")
        XCTAssertEqual(p.batteryText, "81%")
        XCTAssertEqual(p.batteryFraction ?? -1, 0.81, accuracy: 0.0001)
        XCTAssertEqual(p.evRangeText, "48 km")
        XCTAssertEqual(p.fuelText, "59%")
        XCTAssertEqual(p.fuelRangeText, "402 km")
        XCTAssertEqual(p.totalRangeText, "450 km")
        XCTAssertEqual(p.lockState, .locked)
        XCTAssertEqual(p.lockText, "Locked")
        XCTAssertEqual(p.chargeState, .unplugged)
        XCTAssertEqual(p.outsideTemperatureText, "5°")
        XCTAssertEqual(p.updatedText, "Updated 8 min ago")
        XCTAssertEqual(p.freshness, .fresh)
    }

    func testMissingStatusShowsPlaceholders() {
        let p = VehicleStatusPresentation(status: nil, lastRefresh: nil, now: now)

        XCTAssertEqual(p.title, "Your car")
        XCTAssertNil(p.subtitle)
        XCTAssertNil(p.batteryFraction)
        XCTAssertEqual(p.batteryText, "—")
        XCTAssertEqual(p.totalRangeText, "—")
        XCTAssertEqual(p.lockState, .unknown)
        XCTAssertEqual(p.chargeState, .unknown)
        XCTAssertEqual(p.updatedText, "Not updated yet")
        XCTAssertEqual(p.freshness, .unknown)
    }

    func testChargingAndPluggedInStates() throws {
        let charging = try status(#"{"ev_battery_is_charging": true, "ev_battery_is_plugged_in": 1}"#)
        let plugged = try status(#"{"ev_battery_is_charging": false, "ev_battery_is_plugged_in": 2}"#)

        XCTAssertEqual(VehicleStatusPresentation(status: charging, lastRefresh: nil, now: now).chargeState, .charging)
        XCTAssertEqual(VehicleStatusPresentation(status: plugged, lastRefresh: nil, now: now).chargeState, .pluggedIn)
    }

    func testUnlockedAndNickname() throws {
        let dto = try status(#"{"name": "Blue Bird", "model": "TUCSON PHEV", "year": 2025, "is_locked": false}"#)
        let p = VehicleStatusPresentation(status: dto, lastRefresh: nil, now: now)

        XCTAssertEqual(p.lockState, .unlocked)
        XCTAssertEqual(p.lockSymbol, "lock.open.fill")
        XCTAssertEqual(p.subtitle, "2025 · Blue Bird")
    }

    func testStaleWhenOlderThanSixHoursAndFallsBackToLastRefresh() throws {
        let old = try status(#"{"last_updated_at": "2026-11-08T21:00:00Z"}"#)
        let p = VehicleStatusPresentation(status: old, lastRefresh: nil, now: now)
        XCTAssertEqual(p.updatedText, "Updated 1 day ago")
        XCTAssertEqual(p.freshness, .stale)

        let noTimestamp = try status("{}")
        let refreshed = VehicleStatusPresentation(
            status: noTimestamp,
            lastRefresh: now.addingTimeInterval(-30),
            now: now
        )
        XCTAssertEqual(refreshed.updatedText, "Updated just now")
        XCTAssertEqual(refreshed.freshness, .fresh)
    }

    func testRelativeTextBuckets() {
        XCTAssertEqual(VehicleStatusPresentation.relativeText(59), "just now")
        XCTAssertEqual(VehicleStatusPresentation.relativeText(60 * 59), "59 min ago")
        XCTAssertEqual(VehicleStatusPresentation.relativeText(60 * 60 * 5), "5 h ago")
        XCTAssertEqual(VehicleStatusPresentation.relativeText(60 * 60 * 72), "3 days ago")
    }

    func testPercentClampsAndMilesUnit() {
        XCTAssertEqual(VehicleStatusPresentation.percentText(120), "100%")
        XCTAssertEqual(VehicleStatusPresentation.fraction(-5), 0)
        XCTAssertEqual(VehicleStatusPresentation.distanceText(10.4, unit: "mi"), "10 mi")
        XCTAssertEqual(VehicleStatusPresentation.distanceText(10.4, unit: "1"), "10 km")
    }

    func testFractionalSecondTimestampsParse() {
        XCTAssertNotNil(VehicleStatusPresentation.parseDate("2026-11-09T22:52:00.123+00:00"))
        XCTAssertNil(VehicleStatusPresentation.parseDate("yesterday"))
    }
}
