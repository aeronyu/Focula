import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

public struct FrontmostAppSnapshot: Equatable, Sendable {
    public var appName: String
    public var bundleIdentifier: String?
    public var windowFrame: CGRect?

    public init(appName: String, bundleIdentifier: String?, windowFrame: CGRect? = nil) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowFrame = windowFrame
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
            bundleIdentifier: app?.bundleIdentifier,
            windowFrame: Self.focusedWindowFrame(for: app?.processIdentifier)
        )
    }

    private static func focusedWindowFrame(for processIdentifier: pid_t?) -> CGRect? {
        guard let processIdentifier,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]]
        else { return nil }

        let window = windows.first {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == processIdentifier
                && (($0[kCGWindowLayer as String] as? Int) ?? 1) == 0
        }
        guard let bounds = window?[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"],
              let y = bounds["Y"],
              let width = bounds["Width"],
              let height = bounds["Height"]
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct ScreenSnapshotContext: Sendable {
    public var primaryImageData: Data
    public var contextImageData: [Data]

    public init(primaryImageData: Data, contextImageData: [Data] = []) {
        self.primaryImageData = primaryImageData
        self.contextImageData = contextImageData
    }
}

public protocol ScreenSnapshotProviding: Sendable {
    @MainActor
    func captureJPEGData(maxDimension: Int, quality: CGFloat) async throws -> Data

    @MainActor
    func captureContextJPEGData(
        focusedWindowFrame: CGRect?,
        maxDimension: Int,
        quality: CGFloat
    ) async throws -> ScreenSnapshotContext
}

public extension ScreenSnapshotProviding {
    @MainActor
    func captureContextJPEGData(
        focusedWindowFrame: CGRect? = nil,
        maxDimension: Int,
        quality: CGFloat
    ) async throws -> ScreenSnapshotContext {
        ScreenSnapshotContext(primaryImageData: try await captureJPEGData(maxDimension: maxDimension, quality: quality))
    }
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
        try await captureContextJPEGData(focusedWindowFrame: nil, maxDimension: maxDimension, quality: quality).primaryImageData
    }

    public func captureContextJPEGData(
        focusedWindowFrame: CGRect? = nil,
        maxDimension: Int = 1280,
        quality: CGFloat = 0.55
    ) async throws -> ScreenSnapshotContext {
        guard permissionChecker.hasScreenCapturePermission else {
            throw ScreenSnapshotError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let candidates = content.displays.map {
            DisplayCaptureCandidate(
                id: UInt32($0.displayID),
                frame: $0.frame,
                isOnScreen: true
            )
        }
        let selection = DisplayCaptureSelection.select(displays: candidates, focusedWindowFrame: focusedWindowFrame)
        guard let primaryDisplayID = selection.primary?.id,
              let display = content.displays.first(where: { UInt32($0.displayID) == primaryDisplayID }) ?? content.displays.first
        else {
            throw ScreenSnapshotError.noDisplay
        }

        let primary = try await capture(display: display, maxDimension: maxDimension, quality: quality)
        var context: [Data] = []
        for candidate in selection.context {
            guard let display = content.displays.first(where: { UInt32($0.displayID) == candidate.id }) else { continue }
            context.append(try await capture(display: display, maxDimension: maxDimension, quality: quality))
        }
        return ScreenSnapshotContext(primaryImageData: primary, contextImageData: context)
    }

    @MainActor
    private func capture(display: SCDisplay, maxDimension: Int, quality: CGFloat) async throws -> Data {
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

public struct DisplayCaptureCandidate: Equatable, Sendable {
    public var id: UInt32
    public var frame: CGRect
    public var isOnScreen: Bool

    public init(id: UInt32, frame: CGRect, isOnScreen: Bool) {
        self.id = id
        self.frame = frame
        self.isOnScreen = isOnScreen
    }
}

public struct DisplayCaptureSelection: Equatable, Sendable {
    public var primary: DisplayCaptureCandidate?
    public var context: [DisplayCaptureCandidate]

    public static func select(
        displays: [DisplayCaptureCandidate],
        focusedWindowFrame: CGRect?
    ) -> DisplayCaptureSelection {
        let visible = displays.filter(\.isOnScreen)
        let primary = focusedWindowFrame.flatMap { frame in
            visible.max { lhs, rhs in
                lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
            }
        } ?? visible.first
        let context = visible.filter { $0.id != primary?.id }
        return DisplayCaptureSelection(primary: primary, context: context)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull && !isEmpty else { return 0 }
        return width * height
    }
}

public final class FrameDeduplicator {
    private let recentLimit: Int
    private var recentHashes: [UInt64] = []

    public init(recentLimit: Int = 4) {
        self.recentLimit = max(1, recentLimit)
    }

    public func shouldClassify(_ data: Data) -> Bool {
        let hash = Self.fnv1a64(data)
        defer { remember(hash) }
        return !recentHashes.contains(hash)
    }

    private func remember(_ hash: UInt64) {
        recentHashes.append(hash)
        if recentHashes.count > recentLimit {
            recentHashes.removeFirst(recentHashes.count - recentLimit)
        }
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
        strategy: SamplingStrategy,
        configuredInterval: TimeInterval,
        idleSeconds: TimeInterval
    ) -> TimeInterval {
        switch strategy {
        case .manualOnly:
            return 0
        case .responsive:
            if idleSeconds < 60 { return 20 }
            if idleSeconds < 300 { return 60 }
            return 180
        case .quiet:
            if idleSeconds < 300 { return 120 }
            return 300
        case .balanced:
            break
        }

        let configuredInterval = min(max(60, configuredInterval), 300)
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
