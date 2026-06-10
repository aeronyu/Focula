import Foundation

public struct ActivityLogBlock: Identifiable, Equatable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date
    public var appName: String
    public var bundleIdentifier: String?
    public var goalID: UUID
    public var focusState: FocusState
    public var activityCategory: String
    public var activitySummary: String?
    public var confidence: Double
    public var durationSeconds: TimeInterval
    public var sampleCount: Int
    public var nudgeShown: Bool
    public var latestSample: ActivitySample
}

public enum ActivityLogCompactor {
    public static func compact(
        samples: [ActivitySample],
        maxGap: TimeInterval = 10 * 60
    ) -> [ActivityLogBlock] {
        let ordered = samples.sorted { $0.timestamp < $1.timestamp }
        var blocks: [ActivityLogBlock] = []

        for sample in ordered {
            guard var last = blocks.popLast() else {
                blocks.append(block(for: sample))
                continue
            }

            if canMerge(sample, into: last, maxGap: maxGap) {
                last.end = max(last.end, sample.timestamp)
                last.durationSeconds += sample.durationSeconds
                last.sampleCount += 1
                last.confidence = max(last.confidence, sample.confidence)
                last.nudgeShown = last.nudgeShown || sample.nudgeShown
                last.latestSample = sample
                if last.activitySummary == nil, sample.activitySummary != nil {
                    last.activitySummary = sample.activitySummary
                }
                blocks.append(last)
            } else {
                blocks.append(last)
                blocks.append(block(for: sample))
            }
        }

        return blocks.sorted { $0.end > $1.end }
    }

    private static func block(for sample: ActivitySample) -> ActivityLogBlock {
        ActivityLogBlock(
            id: sample.id.uuidString,
            start: sample.timestamp,
            end: sample.timestamp,
            appName: sample.appName,
            bundleIdentifier: sample.bundleIdentifier,
            goalID: sample.goalID,
            focusState: sample.focusState,
            activityCategory: sample.activityCategory,
            activitySummary: sample.activitySummary,
            confidence: sample.confidence,
            durationSeconds: sample.durationSeconds,
            sampleCount: 1,
            nudgeShown: sample.nudgeShown,
            latestSample: sample
        )
    }

    private static func canMerge(
        _ sample: ActivitySample,
        into block: ActivityLogBlock,
        maxGap: TimeInterval
    ) -> Bool {
        guard sample.goalID == block.goalID,
              sample.focusState == block.focusState,
              sample.appName == block.appName,
              sample.bundleIdentifier == block.bundleIdentifier,
              sample.timestamp.timeIntervalSince(block.end) <= maxGap
        else { return false }

        return mergeKey(for: sample) == mergeKey(for: block)
    }

    private static func mergeKey(for sample: ActivitySample) -> String {
        if let summary = normalized(sample.activitySummary) {
            return "summary:\(summary)"
        }
        return "category:\(sample.activityCategory)"
    }

    private static func mergeKey(for block: ActivityLogBlock) -> String {
        if let summary = normalized(block.activitySummary) {
            return "summary:\(summary)"
        }
        return "category:\(block.activityCategory)"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return cleaned.isEmpty ? nil : cleaned
    }
}
