import SwiftUI
import WatchMyBackCore

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                MissionHeroCard()

                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
                    FocusRingCard()
                    MetricTile(title: "Focus Time", value: DisplayFormatters.minutes(model.stats.focusSeconds), subtitle: "aligned today", icon: "bolt.fill", tint: .mint)
                    MetricTile(title: "Comebacks", value: "\(model.stats.recoveryCount)", subtitle: "course corrections", icon: "arrow.uturn.backward.circle.fill", tint: .orange)
                    MetricTile(title: "XP", value: "\(model.stats.xp)", subtitle: "mission points", icon: "sparkles", tint: .pink)
                }

                TimelinePanel()
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(20)
        }
        .background {
            dashboardBackground
            .ignoresSafeArea()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.togglePaused()
                } label: {
                    Label(model.settings.paused ? "Begin Quest" : "Pause Quest", systemImage: model.settings.paused ? "play.fill" : "pause.fill")
                }

                Button {
                    Task { await model.sampleNow(manual: true) }
                } label: {
                    Label("Scout Now", systemImage: "camera.metering.matrix")
                }
                .disabled(model.isSampling)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onAppear {
            model.refreshScreenRecordingPermission()
        }
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 158, maximum: 240), spacing: 12, alignment: .top)]
    }

    private var dashboardBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}

private struct MissionHeroCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                heroContent
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock
                    statusBlock
                }
            }

            ProgressView(value: levelProgress)
                .progressViewStyle(.linear)
                .tint(.indigo)
                .controlSize(.small)

            if let lastError = model.lastError {
                Label(lastError, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if !model.screenRecordingPermission.isGranted {
                PermissionStatusBanner()
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(heroAccent)
                .frame(width: 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(heroAccent.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private var heroContent: some View {
        HStack(alignment: .center, spacing: 16) {
            titleBlock

            Spacer(minLength: 20)

            statusBlock
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(heroAccent.opacity(0.14))
                Image(systemName: heroSymbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(heroAccent)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text("Today’s Mission")
                    .font(.caption.bold())
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(model.selectedGoal?.title ?? "Choose your next mission")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(model.statusMessage)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Label(model.lastFocusState.label, systemImage: model.lastFocusState.symbolName)
                .font(.callout.bold())
                .foregroundStyle(heroAccent)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(heroAccent.opacity(0.12), in: Capsule())

            HStack(spacing: 8) {
                Text("Level \(missionLevel)")
                    .font(.title3.weight(.bold))
                Text("\(nextLevelXP) XP left")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 146, alignment: .trailing)
    }

    private var heroSymbol: String {
        switch model.lastFocusState {
        case .onGoal: return "checkmark.seal.fill"
        case .maybe: return "location.north.circle.fill"
        case .offGoal: return "arrow.uturn.backward.circle.fill"
        case .unknown: return "scope"
        }
    }

    private var heroAccent: Color {
        switch model.lastFocusState {
        case .onGoal: return .mint
        case .maybe: return .indigo
        case .offGoal: return .orange
        case .unknown: return .blue
        }
    }

    private var missionLevel: Int {
        max(1, model.stats.xp / 120 + 1)
    }

    private var nextLevelXP: Int {
        let nextThreshold = missionLevel * 120
        return max(0, nextThreshold - model.stats.xp)
    }

    private var levelProgress: Double {
        Double(model.stats.xp % 120) / 120.0
    }

}

private struct PermissionStatusBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text("Unlock screen scouting")
                    .font(.callout.bold())
                Text("Enable Screen Recording so Scout can judge activity locally. Screenshots are discarded after classification.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                model.openScreenRecordingGuide()
            } label: {
                Label("Open Guide", systemImage: "arrow.up.right.square")
            }

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FocusRingCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quest Sync")
                    .font(.callout.bold())
                Spacer()
                Text(syncBadge)
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.14), in: Capsule())
            }
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.45), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: min(model.stats.focusRatio, 1))
                    .stroke(.green, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text(DisplayFormatters.percent(model.stats.focusRatio))
                        .font(.title.bold())
                    Text("aligned")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 154, alignment: .topLeading)
        .background(Color.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.mint.opacity(0.18), lineWidth: 1)
        }
    }

    private var syncBadge: String {
        model.stats.focusRatio >= 0.7 ? "Steady" : "Building"
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.15))
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)

            Text(value)
                .font(.title.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 154, alignment: .topLeading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct TimelinePanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Activity Log", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text(model.settings.persistActivitySummaries ? "local summaries" : "summaries off")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            let entries = activityLogEntries
            if entries.isEmpty {
                EmptyActivityLogState(
                    title: model.recentSamples.isEmpty ? "No activity yet" : "No useful activity yet",
                    message: emptyActivityLogMessage
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(entries) { entry in
                        ActivityObservationRow(entry: entry)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(0.14), lineWidth: 1)
        }
    }

    private var activityLogEntries: [ActivityLogEntry] {
        DashboardCopy.activityLogEntries(
            from: model.recentSamples,
            setupState: .init(
                builtInModelReady: model.settings.builtInModelStatus.installState == .ready,
                screenRecordingGranted: model.screenRecordingPermission.isGranted,
                cloudOptInAllowed: model.settings.modelSelection.cloudClassificationAllowed
            )
        )
    }

    private var emptyActivityLogMessage: String {
        if model.recentSamples.isEmpty {
            return "Begin Quest or run Scout Now. Local summaries appear here after Scout checks your screen."
        }
        return "Recent setup-only check-ins were resolved or hidden. New local summaries will appear after Scout reads real activity."
    }
}

private struct EmptyActivityLogState: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
                Image(systemName: "map")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ActivityObservationRow: View {
    let entry: ActivityLogEntry

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(entry.tint.opacity(0.14))
                Image(systemName: entry.icon)
                    .foregroundStyle(entry.tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.callout.bold())
                    .lineLimit(1)
                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            if entry.nudgeShown {
                Text("Nudge")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
        .padding(10)
        .background(entry.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct ActivityLogEntry: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let background: Color
    let nudgeShown: Bool
}

private struct ActivityLogSetupState {
    let builtInModelReady: Bool
    let screenRecordingGranted: Bool
    let cloudOptInAllowed: Bool

    var coreSetupReady: Bool {
        builtInModelReady && screenRecordingGranted
    }
}

private enum DashboardCopy {
    static func activityLogEntries(
        from samples: [ActivitySample],
        setupState: ActivityLogSetupState = ActivityLogSetupState(
            builtInModelReady: false,
            screenRecordingGranted: false,
            cloudOptInAllowed: false
        )
    ) -> [ActivityLogEntry] {
        var entries: [ActivityLogEntry] = []
        var setupCounts: [String: (sample: ActivitySample, count: Int)] = [:]

        for sample in samples.prefix(30) {
            if isSetupNoise(sample) {
                guard shouldShowSetupNoise(sample, setupState: setupState) else {
                    continue
                }
                let key = sample.activityCategory
                if let current = setupCounts[key] {
                    setupCounts[key] = (current.sample, current.count + 1)
                } else {
                    setupCounts[key] = (sample, 1)
                }
                continue
            }

            entries.append(activityEntry(for: sample))
            if entries.count >= 10 {
                break
            }
        }

        let setupEntries = setupCounts.values
            .sorted { $0.sample.timestamp > $1.sample.timestamp }
            .map { setupEntry(for: $0.sample, count: $0.count) }

        return Array((setupEntries + entries).prefix(10))
    }

    static func activitySummary(for sample: ActivitySample) -> String {
        if let summary = sample.activitySummary, !summary.isEmpty {
            return summary
        }

        switch sample.activityCategory {
        case "built_in_model_not_ready":
            return "Scout is still gearing up"
        case "screen_recording_permission_missing":
            return "Scout needs screen access"
        case "classifier_unavailable", "unknown":
            return "Scout could not read this moment"
        case "unchanged_screen":
            return "Same scene, combo holding"
        case "cloud_blocked":
            return "Cloud scout is locked until opt-in"
        default:
            switch sample.focusState {
            case .onGoal:
                return "Quest progress: \(humanize(sample.activityCategory, fallback: "aligned work"))"
            case .maybe:
                return "Possible side quest: \(humanize(sample.activityCategory, fallback: "related work"))"
            case .offGoal:
                return "Drift spotted: \(humanize(sample.activityCategory, fallback: "off-mission activity"))"
            case .unknown:
                return humanize(sample.activityCategory, fallback: "Activity could not be interpreted")
            }
        }
    }

    private static func activityEntry(for sample: ActivitySample) -> ActivityLogEntry {
        ActivityLogEntry(
            id: sample.id.uuidString,
            title: activitySummary(for: sample),
            detail: "Scout checked \(sample.appName) at \(DisplayFormatters.time(sample.timestamp))",
            icon: sample.focusState.symbolName,
            tint: sample.focusState.tint,
            background: rowBackground(for: sample.focusState),
            nudgeShown: sample.nudgeShown
        )
    }

    private static func setupEntry(for sample: ActivitySample, count: Int) -> ActivityLogEntry {
        let plural = count == 1 ? "check-in" : "check-ins"
        return ActivityLogEntry(
            id: "setup-\(sample.activityCategory)",
            title: setupTitle(for: sample),
            detail: "\(count) \(plural) need setup · latest \(DisplayFormatters.time(sample.timestamp))",
            icon: setupIcon(for: sample),
            tint: .purple,
            background: Color.purple.opacity(0.08),
            nudgeShown: false
        )
    }

    private static func isSetupNoise(_ sample: ActivitySample) -> Bool {
        switch sample.activityCategory {
        case "built_in_model_not_ready",
             "screen_recording_permission_missing",
             "classifier_unavailable",
             "unknown",
             "cloud_blocked":
            return true
        default:
            return false
        }
    }

    private static func shouldShowSetupNoise(_ sample: ActivitySample, setupState: ActivityLogSetupState) -> Bool {
        switch sample.activityCategory {
        case "built_in_model_not_ready":
            return !setupState.builtInModelReady
        case "screen_recording_permission_missing":
            return !setupState.screenRecordingGranted
        case "cloud_blocked":
            return !setupState.cloudOptInAllowed
        case "classifier_unavailable", "unknown":
            return !setupState.coreSetupReady
        default:
            return true
        }
    }

    private static func setupTitle(for sample: ActivitySample) -> String {
        switch sample.activityCategory {
        case "built_in_model_not_ready":
            return "Finish local model setup"
        case "screen_recording_permission_missing":
            return "Grant Screen Recording"
        case "cloud_blocked":
            return "Cloud scout needs opt-in"
        default:
            return "Scout setup needs attention"
        }
    }

    private static func setupIcon(for sample: ActivitySample) -> String {
        switch sample.activityCategory {
        case "screen_recording_permission_missing":
            return "camera.viewfinder"
        case "built_in_model_not_ready":
            return "cpu"
        case "cloud_blocked":
            return "lock.shield"
        default:
            return "wrench.and.screwdriver"
        }
    }

    private static func rowBackground(for focusState: WatchMyBackCore.FocusState) -> Color {
        switch focusState {
        case .onGoal: return Color.green.opacity(0.10)
        case .maybe: return Color.yellow.opacity(0.12)
        case .offGoal: return Color.orange.opacity(0.12)
        case .unknown: return Color.gray.opacity(0.10)
        }
    }

    private static func humanize(_ raw: String, fallback: String) -> String {
        let cleaned = raw
            .split(separator: "_")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !cleaned.isEmpty else { return fallback }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

}
