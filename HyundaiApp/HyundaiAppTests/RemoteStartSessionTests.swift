import Foundation
import XCTest
import HyundaiApp

final class RemoteStartSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(duration: Int = 10, battery: Int? = 81) -> RemoteStartSession {
        RemoteStartSession(
            actionID: "tx-1",
            sentAt: t0,
            durationMinutes: duration,
            targetTemperature: 22,
            defrost: false,
            startBatteryPercent: battery
        )
    }

    func testSuccessStartsCountdownFromConfirmation() {
        var s = session()
        XCTAssertTrue(s.shouldPollActionStatus(at: t0.addingTimeInterval(10)))

        s.applyActionStatus("pending", at: t0.addingTimeInterval(10))
        XCTAssertEqual(s.stage, .confirming)

        let confirmed = t0.addingTimeInterval(30)
        s.applyActionStatus("success", at: confirmed)
        XCTAssertEqual(s.stage, .running)
        XCTAssertEqual(s.confirmedAt, confirmed)
        XCTAssertEqual(s.endsAt, confirmed.addingTimeInterval(600))
        XCTAssertFalse(s.shouldPollActionStatus(at: confirmed))

        let later = confirmed.addingTimeInterval(78)
        XCTAssertEqual(s.remaining(at: later), 522, accuracy: 0.001)
        XCTAssertEqual(RemoteStartSession.countdownText(s.remaining(at: later)), "8:42")
        XCTAssertEqual(s.remainingFraction(at: later), 0.87, accuracy: 0.001)
    }

    func testFailureIsTerminal() {
        var s = session()
        s.applyActionStatus("failed", at: t0.addingTimeInterval(40))

        XCTAssertEqual(s.stage, .failed)
        XCTAssertNotNil(s.failureMessage)
        XCTAssertFalse(s.isActive)

        s.applyActionStatus("success", at: t0.addingTimeInterval(50))
        XCTAssertEqual(s.stage, .failed)
    }

    func testNoAnswerBecomesUnconfirmedThenStatusCanConfirm() {
        var s = session()
        s.applyActionStatus("pending", at: t0.addingTimeInterval(121))
        XCTAssertEqual(s.stage, .unconfirmed)
        XCTAssertFalse(s.shouldPollActionStatus(at: t0.addingTimeInterval(121)))
        XCTAssertTrue(s.isActive)

        s.applyStatus(engineRunning: true, climateOn: true, statusTime: t0.addingTimeInterval(90), batteryPercent: 81, at: t0.addingTimeInterval(130))
        XCTAssertEqual(s.stage, .running)
        XCTAssertEqual(s.confirmedAt, t0.addingTimeInterval(90))
    }

    func testUnconfirmedGivesUpAfterTheRunWouldHaveEnded() {
        var s = session()
        s.applyActionStatus("timeout", at: t0.addingTimeInterval(60))

        s.tick(at: t0.addingTimeInterval(600))
        XCTAssertEqual(s.stage, .unconfirmed)

        s.tick(at: t0.addingTimeInterval(721))
        XCTAssertEqual(s.stage, .failed)
        XCTAssertEqual(s.failureMessage, "The car never confirmed the remote start.")
    }

    func testTimeoutStatusMarksUnconfirmed() {
        var s = session()
        s.applyActionStatus("timeout", at: t0.addingTimeInterval(60))
        XCTAssertEqual(s.stage, .unconfirmed)
    }

    func testStatusFromBeforeTheCommandDoesNotConfirm() {
        var s = session()
        s.applyStatus(engineRunning: true, climateOn: true, statusTime: t0.addingTimeInterval(-60), batteryPercent: nil, at: t0.addingTimeInterval(5))
        XCTAssertEqual(s.stage, .confirming)
    }

    func testTickFinishesWhenTimeRunsOut() {
        var s = session()
        s.applyActionStatus("success", at: t0)

        s.tick(at: t0.addingTimeInterval(599))
        XCTAssertEqual(s.stage, .running)

        s.tick(at: t0.addingTimeInterval(700))
        XCTAssertEqual(s.stage, .finished)
        XCTAssertEqual(s.endedAt, t0.addingTimeInterval(600))
        XCTAssertEqual(s.ranFor, 600)
    }

    func testSavedStatusShowingEngineOffEndsEarly() {
        var s = session()
        s.applyActionStatus("success", at: t0)

        // Too close to the confirmation: could be a stale reading.
        s.applyStatus(engineRunning: false, climateOn: false, statusTime: t0.addingTimeInterval(10), batteryPercent: 80, at: t0.addingTimeInterval(20))
        XCTAssertEqual(s.stage, .running)

        s.applyStatus(engineRunning: false, climateOn: false, statusTime: t0.addingTimeInterval(240), batteryPercent: 79, at: t0.addingTimeInterval(300))
        XCTAssertEqual(s.stage, .finished)
        XCTAssertEqual(s.endedAt, t0.addingTimeInterval(240))
        XCTAssertEqual(s.batteryUsed, 2)
    }

    func testClimateStillOnKeepsRunning() {
        var s = session()
        s.applyActionStatus("success", at: t0)
        s.applyStatus(engineRunning: false, climateOn: true, statusTime: t0.addingTimeInterval(200), batteryPercent: 80, at: t0.addingTimeInterval(210))
        XCTAssertEqual(s.stage, .running)
        XCTAssertEqual(s.endBatteryPercent, 80)
    }

    func testUserStopFinishesAndIsIdempotent() {
        var s = session()
        s.applyActionStatus("success", at: t0)
        s.stopped(at: t0.addingTimeInterval(120))

        XCTAssertEqual(s.stage, .finished)
        XCTAssertEqual(s.ranFor, 120)

        s.stopped(at: t0.addingTimeInterval(300))
        XCTAssertEqual(s.endedAt, t0.addingTimeInterval(120))
    }

    func testCodableRoundTrip() throws {
        var s = session()
        s.applyActionStatus("success", at: t0)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(RemoteStartSession.self, from: data), s)
    }

    func testFormatting() {
        XCTAssertEqual(RemoteStartSession.countdownText(0), "0:00")
        XCTAssertEqual(RemoteStartSession.countdownText(59.2), "1:00")
        XCTAssertEqual(RemoteStartSession.countdownText(600), "10:00")
        XCTAssertEqual(RemoteStartSession.durationText(45), "45 s")
        XCTAssertEqual(RemoteStartSession.durationText(600), "10 min")
    }
}
