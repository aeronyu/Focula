import Foundation
import XCTest
@testable import WatchMyBackCore

final class ActivityServicesTests: XCTestCase {
    func testFrameDeduplicatorSkipsImmediateDuplicateBytes() {
        let deduplicator = FrameDeduplicator()
        let frame = Data([1, 2, 3, 4, 5])

        XCTAssertTrue(deduplicator.shouldClassify(frame))
        XCTAssertFalse(deduplicator.shouldClassify(frame))
        XCTAssertTrue(deduplicator.shouldClassify(Data([1, 2, 3, 4, 6])))
    }

    func testFrameDeduplicatorSkipsFramesSeenInRecentWindow() {
        let deduplicator = FrameDeduplicator(recentLimit: 3)
        let first = Data([1])
        let second = Data([2])
        let third = Data([3])

        XCTAssertTrue(deduplicator.shouldClassify(first))
        XCTAssertTrue(deduplicator.shouldClassify(second))
        XCTAssertFalse(deduplicator.shouldClassify(first))
        XCTAssertTrue(deduplicator.shouldClassify(third))
        XCTAssertFalse(deduplicator.shouldClassify(second))
    }

    func testFrameDeduplicatorClassifiesAgainAfterRecentWindowRollsOver() {
        let deduplicator = FrameDeduplicator(recentLimit: 2)
        let first = Data([1])

        XCTAssertTrue(deduplicator.shouldClassify(first))
        XCTAssertTrue(deduplicator.shouldClassify(Data([2])))
        XCTAssertTrue(deduplicator.shouldClassify(Data([3])))
        XCTAssertTrue(deduplicator.shouldClassify(first))
    }

    @MainActor
    func testScreenCaptureProviderFailsBeforeCaptureWhenPermissionMissing() async throws {
        let provider = ScreenCaptureKitSnapshotProvider(
            permissionChecker: StaticScreenCapturePermissionChecker(isGranted: false)
        )

        do {
            _ = try await provider.captureJPEGData()
            XCTFail("Expected permission error")
        } catch let error as ScreenSnapshotError {
            XCTAssertEqual(error, .permissionDenied)
        }
    }

    func testRestartPromptAppearsAfterPermissionRequestDelay() {
        let requestedAt = Date(timeIntervalSince1970: 100)

        XCTAssertFalse(ScreenCapturePermissionGuidance.restartRequired(
            requestedAt: requestedAt,
            now: Date(timeIntervalSince1970: 101),
            delay: 1.5
        ))
        XCTAssertTrue(ScreenCapturePermissionGuidance.restartRequired(
            requestedAt: requestedAt,
            now: Date(timeIntervalSince1970: 102),
            delay: 1.5
        ))
    }

    func testSamplingPolicyUsesConfiguredIntervalWhileActive() {
        XCTAssertEqual(
            SamplingPolicy.nextInterval(strategy: .balanced, configuredInterval: 90, idleSeconds: 10),
            90
        )
    }

    func testSamplingPolicyBacksOffWhenIdle() {
        XCTAssertEqual(
            SamplingPolicy.nextInterval(strategy: .balanced, configuredInterval: 30, idleSeconds: 90),
            120
        )
        XCTAssertEqual(
            SamplingPolicy.nextInterval(strategy: .balanced, configuredInterval: 180, idleSeconds: 600),
            300
        )
    }

    func testSamplingPolicyStrategiesUseDifferentCadences() {
        XCTAssertEqual(SamplingPolicy.nextInterval(strategy: .responsive, configuredInterval: 60, idleSeconds: 10), 20)
        XCTAssertEqual(SamplingPolicy.nextInterval(strategy: .quiet, configuredInterval: 60, idleSeconds: 10), 120)
        XCTAssertEqual(SamplingPolicy.nextInterval(strategy: .manualOnly, configuredInterval: 60, idleSeconds: 10), 0)
    }

    func testDisplayContextSelectionKeepsFocusedDisplayPrimaryAndOtherDisplayedScreensAsContext() {
        let displays = [
            DisplayCaptureCandidate(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), isOnScreen: true),
            DisplayCaptureCandidate(id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100), isOnScreen: true),
            DisplayCaptureCandidate(id: 3, frame: CGRect(x: 200, y: 0, width: 100, height: 100), isOnScreen: false)
        ]

        let selection = DisplayCaptureSelection.select(displays: displays, focusedWindowFrame: CGRect(x: 120, y: 20, width: 20, height: 20))

        XCTAssertEqual(selection.primary?.id, 2)
        XCTAssertEqual(selection.context.map(\.id), [1])
    }

    func testSampleDurationUsesConfiguredFallbackForFirstSample() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            SamplingPolicy.sampleDuration(lastSampleAt: nil, now: now, fallbackInterval: 75),
            75
        )
        XCTAssertEqual(
            SamplingPolicy.sampleDuration(
                lastSampleAt: Date(timeIntervalSince1970: 950),
                now: now,
                fallbackInterval: 75
            ),
            50
        )
    }
}

private struct StaticScreenCapturePermissionChecker: ScreenCapturePermissionChecking {
    let isGranted: Bool

    var hasScreenCapturePermission: Bool {
        isGranted
    }
}
