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
            SamplingPolicy.nextInterval(configuredInterval: 90, idleSeconds: 10),
            90
        )
    }

    func testSamplingPolicyBacksOffWhenIdle() {
        XCTAssertEqual(
            SamplingPolicy.nextInterval(configuredInterval: 30, idleSeconds: 90),
            120
        )
        XCTAssertEqual(
            SamplingPolicy.nextInterval(configuredInterval: 180, idleSeconds: 600),
            300
        )
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
