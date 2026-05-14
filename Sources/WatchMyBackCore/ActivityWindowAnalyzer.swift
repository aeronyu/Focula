import Foundation

public enum ActivityWindowState: String, Codable, Equatable, Sendable {
    case noSamples
    case onTrack
    case mixed
    case drifting
    case unknown
}

public struct ActivityWindowSummary: Equatable, Sendable {
    public var state: ActivityWindowState
    public var sampleCount: Int
    public var alignedCount: Int
    public var maybeCount: Int
    public var offGoalCount: Int
    public var unknownCount: Int
    public var alignedSeconds: TimeInterval
    public var maybeSeconds: TimeInterval
    public var offGoalSeconds: TimeInterval
    public var unknownSeconds: TimeInterval
    public var windowDuration: TimeInterval
    public var driftThreshold: TimeInterval

    public init(
        state: ActivityWindowState,
        sampleCount: Int,
        alignedCount: Int,
        maybeCount: Int,
        offGoalCount: Int,
        unknownCount: Int,
        alignedSeconds: TimeInterval,
        maybeSeconds: TimeInterval,
        offGoalSeconds: TimeInterval,
        unknownSeconds: TimeInterval,
        windowDuration: TimeInterval,
        driftThreshold: TimeInterval
    ) {
        self.state = state
        self.sampleCount = sampleCount
        self.alignedCount = alignedCount
        self.maybeCount = maybeCount
        self.offGoalCount = offGoalCount
        self.unknownCount = unknownCount
        self.alignedSeconds = alignedSeconds
        self.maybeSeconds = maybeSeconds
        self.offGoalSeconds = offGoalSeconds
        self.unknownSeconds = unknownSeconds
        self.windowDuration = windowDuration
        self.driftThreshold = driftThreshold
    }

    public var totalObservedSeconds: TimeInterval {
        alignedSeconds + maybeSeconds + offGoalSeconds + unknownSeconds
    }

    public var alignmentRatio: Double {
        guard totalObservedSeconds > 0 else { return 0 }
        return alignedSeconds / totalObservedSeconds
    }

    public var driftRatio: Double {
        guard totalObservedSeconds > 0 else { return 0 }
        return offGoalSeconds / totalObservedSeconds
    }

    public var isSustainedDrift: Bool {
        state == .drifting
    }
}

public struct ActivityWindowAnalyzer {
    public var windowDuration: TimeInterval
    public var driftThreshold: TimeInterval
    public var minimumSamplesForDrift: Int

    public init(
        windowDuration: TimeInterval = 20 * 60,
        driftThreshold: TimeInterval = 20 * 60,
        minimumSamplesForDrift: Int = 2
    ) {
        self.windowDuration = windowDuration
        self.driftThreshold = driftThreshold
        self.minimumSamplesForDrift = minimumSamplesForDrift
    }

    public func summarize(
        samples: [ActivitySample],
        now: Date = Date()
    ) -> ActivityWindowSummary {
        let cutoff = now.addingTimeInterval(-windowDuration)
        let recent = samples.filter { $0.timestamp >= cutoff && $0.timestamp <= now }

        guard !recent.isEmpty else {
            return ActivityWindowSummary(
                state: .noSamples,
                sampleCount: 0,
                alignedCount: 0,
                maybeCount: 0,
                offGoalCount: 0,
                unknownCount: 0,
                alignedSeconds: 0,
                maybeSeconds: 0,
                offGoalSeconds: 0,
                unknownSeconds: 0,
                windowDuration: windowDuration,
                driftThreshold: driftThreshold
            )
        }

        var alignedCount = 0
        var maybeCount = 0
        var offGoalCount = 0
        var unknownCount = 0
        var alignedSeconds: TimeInterval = 0
        var maybeSeconds: TimeInterval = 0
        var offGoalSeconds: TimeInterval = 0
        var unknownSeconds: TimeInterval = 0

        for sample in recent {
            let duration = max(0, min(sample.durationSeconds, windowDuration))
            switch sample.focusState {
            case .onGoal:
                alignedCount += 1
                alignedSeconds += duration
            case .maybe:
                maybeCount += 1
                maybeSeconds += duration
            case .offGoal:
                offGoalCount += 1
                offGoalSeconds += duration
            case .unknown:
                unknownCount += 1
                unknownSeconds += duration
            }
        }

        let state: ActivityWindowState
        if offGoalSeconds >= driftThreshold && offGoalCount >= minimumSamplesForDrift {
            state = .drifting
        } else if alignedSeconds >= max(maybeSeconds + offGoalSeconds, 1) {
            state = .onTrack
        } else if unknownCount == recent.count {
            state = .unknown
        } else {
            state = .mixed
        }

        return ActivityWindowSummary(
            state: state,
            sampleCount: recent.count,
            alignedCount: alignedCount,
            maybeCount: maybeCount,
            offGoalCount: offGoalCount,
            unknownCount: unknownCount,
            alignedSeconds: alignedSeconds,
            maybeSeconds: maybeSeconds,
            offGoalSeconds: offGoalSeconds,
            unknownSeconds: unknownSeconds,
            windowDuration: windowDuration,
            driftThreshold: driftThreshold
        )
    }
}
