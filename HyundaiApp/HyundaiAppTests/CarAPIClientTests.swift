import Foundation
import XCTest
import HyundaiApp

final class CarAPIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testHealthSuccess() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/health")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"status":"ok"}"#.utf8)
            )
        }

        let client = makeClient()
        let response = try await client.health()

        XCTAssertEqual(response.status, "ok")
    }

    func testStatusSuccessDecodesOptionalFields() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/status")
            XCTAssertEqual(request.url?.query, "force=false")

            let payload = """
            {
              "is_locked": true,
              "fuel_level": 75,
              "ev_battery_percentage": 82,
              "ev_driving_range": 48.0,
              "total_driving_range": 650.0,
              "last_updated_at": "2026-04-23T14:05:12+00:00"
            }
            """

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(payload.utf8)
            )
        }

        let client = makeClient()
        let status = try await client.status(force: false)

        XCTAssertEqual(status.isLocked, true)
        XCTAssertEqual(status.fuelLevel, 75)
        XCTAssertEqual(status.evBatteryPercentage, 82)
        XCTAssertEqual(status.evDrivingRange, 48.0)
        XCTAssertEqual(status.totalDrivingRange, 650.0)
        XCTAssertEqual(status.lastUpdatedAt, "2026-04-23T14:05:12+00:00")
    }

    func testStatusDecodesStringBackedTemperatureAndLocationDoubles() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/status")
            XCTAssertEqual(request.url?.query, "force=false")

            let payload = """
            {
              "id": "x",
              "air_temperature": "22.0",
              "outside_temperature": "18.5",
              "location": {
                "latitude": "45.5",
                "longitude": "-73.6",
                "last_updated_at": "2026-05-10T19:15:50+00:00"
              }
            }
            """

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(payload.utf8)
            )
        }

        let client = makeClient()
        let status = try await client.status(force: false)

        XCTAssertEqual(status.id, "x")
        XCTAssertEqual(status.airTemperature, 22.0)
        XCTAssertEqual(status.outsideTemperature, 18.5)
        XCTAssertEqual(status.location?.latitude, 45.5)
        XCTAssertEqual(status.location?.longitude, -73.6)
        XCTAssertEqual(status.location?.lastUpdatedAt, "2026-05-10T19:15:50+00:00")
    }

    func testLockSendsBearerHeaderAndPostsToCorrectPath() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/command/lock")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"ok":true,"command":"lock"}"#.utf8)
            )
        }

        let client = makeClient()
        let response = try await client.lock()

        XCTAssertEqual(response.ok, true)
        XCTAssertEqual(response.command, "lock")
    }

    func testForce4xxDoesNotRetry() async {
        let counter = LockedCounter()

        MockURLProtocol.handler = { request in
            counter.increment()
            return (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data(#"{"detail":"invalid api key"}"#.utf8)
            )
        }

        let client = makeClient()

        do {
            _ = try await client.vehicle()
            XCTFail("Expected HTTP error")
        } catch let error as CarAPIError {
            XCTAssertEqual(error, .http(status: 401, message: "invalid api key"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(counter.value, 1)
    }

    func testRateLimitedMessageIncludesRetryAfter() async {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/status")
            XCTAssertEqual(request.url?.query, "force=true")

            return (
                HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                Data(#"{"detail":{"error":"rate_limited","retry_after_seconds":347}}"#.utf8)
            )
        }

        let client = makeClient()

        do {
            _ = try await client.status(force: true)
            XCTFail("Expected HTTP error")
        } catch let error as CarAPIError {
            XCTAssertEqual(error, .http(status: 429, message: "Live refresh throttled — try again in 347s"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkErrorRetriesOnce() async throws {
        let counter = LockedCounter()

        MockURLProtocol.handler = { request in
            let attempt = counter.increment()
            if attempt == 1 {
                throw URLError(.networkConnectionLost)
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"status":"ok"}"#.utf8)
            )
        }

        let client = makeClient()
        let response = try await client.health()

        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(counter.value, 2)
    }

    func testMissingTokenThrowsNotPaired() async {
        let client = makeClient(tokenProvider: { nil })
        MockURLProtocol.handler = { _ in
            XCTFail("Handler should not be invoked")
            throw URLError(.badURL)
        }

        do {
            _ = try await client.status(force: false)
            XCTFail("Expected notPaired")
        } catch let error as CarAPIError {
            XCTAssertEqual(error, .notPaired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeClient(tokenProvider: @escaping () -> String? = { "test-token" }) -> CarAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        return CarAPIClient(
            session: session,
            baseURLProvider: { URL(string: "http://example.com")! },
            tokenProvider: tokenProvider
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage += 1
        return storage
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
