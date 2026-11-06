import AwakeCore
import Darwin
import Foundation
import XCTest

final class SessionControllerTests: XCTestCase {
    @MainActor
    func testStartsInactiveAndOffReleasesOnlyOwnedProcess() throws {
        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        unrelated.arguments = ["-i", "-t", "30"]
        try unrelated.run()
        defer {
            if unrelated.isRunning { unrelated.terminate(); unrelated.waitUntilExit() }
        }
        let session = SessionController()
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.ownedProcessIdentifier)
        session.start()
        let owned = try XCTUnwrap(session.ownedProcessIdentifier)
        XCTAssertTrue(session.isActive)
        XCTAssertNil(session.remainingSeconds)
        XCTAssertEqual(kill(owned, 0), 0)
        session.stop()
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.ownedProcessIdentifier)
        XCTAssertEqual(kill(owned, 0), -1)
        XCTAssertNil(session.errorMessage)
        XCTAssertTrue(unrelated.isRunning)
        session.stop()
        XCTAssertTrue(unrelated.isRunning)
    }

    @MainActor
    func testReplacementAndEveryHourPreset() throws {
        let session = SessionController()
        defer { session.stop() }
        session.start()
        var previous = try XCTUnwrap(session.ownedProcessIdentifier)
        for hours in 1...4 {
            session.start(duration: Double(hours * 3600), hours: hours)
            let current = try XCTUnwrap(session.ownedProcessIdentifier)
            XCTAssertNotEqual(current, previous)
            XCTAssertEqual(kill(previous, 0), -1)
            XCTAssertEqual(kill(current, 0), 0)
            XCTAssertEqual(session.selectedHours, hours)
            XCTAssertEqual(session.remainingTime, "\(hours):00:00")
            previous = current
        }
        session.start()
        XCTAssertEqual(kill(previous, 0), -1)
        XCTAssertNil(session.remainingSeconds)
        XCTAssertNil(session.selectedHours)
    }

    @MainActor
    func testRealTimerExpiresAndCleansUp() async throws {
        let session = SessionController()
        defer { session.stop() }
        session.start(duration: 1)
        let owned = try XCTUnwrap(session.ownedProcessIdentifier)
        try await Task.sleep(for: .seconds(1.6))
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.remainingTime)
        XCTAssertNil(session.ownedProcessIdentifier)
        XCTAssertEqual(kill(owned, 0), -1)
        XCTAssertNil(session.errorMessage)
    }

    @MainActor
    func testUnexpectedChildExitUpdatesState() async throws {
        let session = SessionController()
        defer { session.stop() }
        session.start()
        let owned = try XCTUnwrap(session.ownedProcessIdentifier)
        XCTAssertEqual(kill(owned, SIGTERM), 0)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(session.isActive)
        XCTAssertNotNil(session.errorMessage)
    }
}
