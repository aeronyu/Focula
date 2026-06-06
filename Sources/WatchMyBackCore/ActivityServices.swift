import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

public struct FrontmostAppSnapshot: Equatable, Sendable {
    public var appName: String
    public var bundleIdentifier: String?

    public init(appName: String, bundleIdentifier: String?) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
    }
}

public protocol FrontmostAppProviding: Sendable {
    @MainActor
    func currentApp() -> FrontmostAppSnapshot
}

public struct NSWorkspaceFrontmostAppProvider: FrontmostAppProviding {
    public init() {}

    public func currentApp() -> FrontmostAppSnapshot {
        let app = NSWorkspace.shared.frontmostApplication
        return FrontmostAppSnapshot(
            appName: app?.localizedName ?? "Unknown App",
            bundleIdentifier: app?.bundleIdentifier
        )
    }
}

public protocol ScreenSnapshotProviding: Sendable {
    @MainActor
    func captureJPEGData(maxDimension: Int, quality: CGFloat) async throws -> Data
}

public enum ScreenSnapshotError: Error, Equatable {
    case permissionDenied
    case noDisplay
    case encodingFailed
}

public protocol ScreenCapturePermissionChecking: Sendable {
    @MainActor
    var hasScreenCapturePermission: Bool { get }
}

public struct SystemScreenCapturePermissionChecker: ScreenCapturePermissionChecking {
    public init() {}

    public var hasScreenCapturePermission: Bool {
        CGPreflightScreenCaptureAccess()
    }
}

public struct ScreenCapturePermissionDiagnostics: Equatable, Sendable {
    public var isGranted: Bool

    public init(isGranted: Bool) {
        self.isGranted = isGranted
    }

    @MainActor
    public static func current(
        checker: ScreenCapturePermissionChecking = SystemScreenCapturePermissionChecker()
    ) -> ScreenCapturePermissionDiagnostics {
        ScreenCapturePermissionDiagnostics(isGranted: checker.hasScreenCapturePermission)
    }
}

public enum ScreenCapturePermissionGuidance {
    public static func restartRequired(
        requestedAt: Date?,
        now: Date = Date(),
        delay: TimeInterval = 1.5
    ) -> Bool {
        guard let requestedAt else { return false }
        return now.timeIntervalSince(requestedAt) >= delay
    }
}

public struct ScreenCaptureKitSnapshotProvider: ScreenSnapshotProviding {
    private let permissionChecker: ScreenCapturePermissionChecking

    public init(permissionChecker: ScreenCapturePermissionChecking = SystemScreenCapturePermissionChecker()) {
        self.permissionChecker = permissionChecker
    }

    public func captureJPEGData(maxDimension: Int = 1280, quality: CGFloat = 0.55) async throws -> Data {
        guard permissionChecker.hasScreenCapturePermission else {
            throw ScreenSnapshotError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw ScreenSnapshotError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        let scale = min(1, Double(maxDimension) / Double(max(display.width, display.height)))
        configuration.width = max(1, Int(Double(display.width) * scale))
        configuration.height = max(1, Int(Double(display.height) * scale))
        configuration.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        ) else {
            throw ScreenSnapshotError.encodingFailed
        }
        return data
    }
}

public final class FrameDeduplicator {
    private var lastHash: UInt64?

    public init() {}

    public func shouldClassify(_ data: Data) -> Bool {
        let hash = Self.fnv1a64(data)
        defer { lastHash = hash }
        return hash != lastHash
    }

    private static func fnv1a64(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}

public enum SamplingPolicy {
    public static func nextInterval(
        configuredInterval: TimeInterval,
        idleSeconds: TimeInterval
    ) -> TimeInterval {
        let configuredInterval = max(15, configuredInterval)
        let idleBackoff: TimeInterval
        if idleSeconds < 60 {
            idleBackoff = configuredInterval
        } else if idleSeconds < 300 {
            idleBackoff = max(configuredInterval, 120)
        } else {
            idleBackoff = max(configuredInterval, 300)
        }
        return min(idleBackoff, 300)
    }

    public static func sampleDuration(
        lastSampleAt: Date?,
        now: Date,
        fallbackInterval: TimeInterval
    ) -> TimeInterval {
        guard let lastSampleAt else {
            return min(max(fallbackInterval, 1), 300)
        }
        return min(max(now.timeIntervalSince(lastSampleAt), 1), 300)
    }
}
