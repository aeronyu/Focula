import SwiftUI
import WatchMyBackCore

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MissionHeroCard()

                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
                    FocusRingCard()
                    MetricTile(title: "Focus Time", value: DisplayFormatters.minutes(model.stats.focusSeconds), subtitle: "aligned today", icon: "bolt.fill", tint: .green)
                    MetricTile(title: "Comebacks", value: "\(model.stats.recoveryCount)", subtitle: "course corrections", icon: "arrow.uturn.backward.circle.fill", tint: .orange)
                    MetricTile(title: "XP", value: "\(model.stats.xp)", subtitle: "mission points", icon: "sparkles", tint: .purple)
                }

                TimelinePanel()
            }
            .padding(24)
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
        Array(
            repeating: GridItem(.flexible(minimum: 150), spacing: 12, alignment: .top),
            count: 4
        )
    }

    private var dashboardBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}

private struct MissionHeroCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.26))
                    Text(heroEmoji)
                        .font(.system(size: 34))
                }
                .frame(width: 64, height: 64)
                .shadow(color: Color.purple.opacity(0.14), radius: 14, x: 0, y: 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Today’s Quest")
                        .font(.caption.bold())
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(model.selectedGoal?.title ?? "Choose your next quest")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(model.statusMessage)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Label(model.lastFocusState.label, systemImage: model.lastFocusState.symbolName)
                        .font(.callout.bold())
                        .foregroundStyle(model.lastFocusState.tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.32), in: Capsule())

                    HStack(spacing: 8) {
                        Text("Level \(missionLevel)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                        Text("\(nextLevelXP) XP left")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ProgressView(value: levelProgress)
                .progressViewStyle(.linear)
                .tint(.purple)
                .scaleEffect(x: 1, y: 1.4, anchor: .center)

            if let lastError = model.lastError {
                Label(lastError, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            if !model.screenRecordingPermission.isGranted {
                PermissionStatusBanner()
            }
        }
        .padding(20)
        .background(heroBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.purple.opacity(0.12), radius: 18, x: 0, y: 12)
    }

    private var heroEmoji: String {
        switch model.lastFocusState {
        case .onGoal: return "🚀"
        case .maybe: return "🧭"
        case .offGoal: return "🛟"
        case .unknown: return "🧭"
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

    private var heroBackground: Color {
        Color.purple.opacity(0.12)
    }
}

private struct PermissionStatusBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text("Unlock screen scouting")
                    .font(.headline)
                Text("Enable Screen Recording so Scout can judge activity locally. Screenshots are discarded after classification.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
        .padding(14)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct FocusRingCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quest Sync")
                    .font(.headline)
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
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                    Text("aligned")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 118, height: 118)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 170, alignment: .topLeading)
        .background(Color.green.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.green.opacity(0.18), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)

            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct TimelinePanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Activity Log")
                    .font(.title3.bold())
                Spacer()
                Text(model.settings.persistActivitySummaries ? "local summaries" : "summaries off")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            let entries = activityLogEntries
            if entries.isEmpty {
                ContentUnavailableView(
                    model.recentSamples.isEmpty ? "No activity yet" : "No useful activity yet",
                    systemImage: "map",
                    description: Text(emptyActivityLogMessage)
                )
                .frame(minHeight: 260)
            } else {
                ForEach(entries) { entry in
                    ActivityObservationRow(entry: entry)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
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
                    .font(.headline)
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
        .padding(12)
        .background(entry.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
