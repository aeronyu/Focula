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

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        TimelinePanel()
                        MissionInsightPanel()
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        TimelinePanel()
                        MissionInsightPanel()
                    }
                }
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
        [
            GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14, alignment: .top)
        ]
    }

    private var dashboardBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}

private struct MissionHeroCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.26))
                    Text(heroEmoji)
                        .font(.system(size: 48))
                }
                .frame(width: 82, height: 82)
                .shadow(color: Color.purple.opacity(0.18), radius: 18, x: 0, y: 10)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Today’s Quest")
                        .font(.caption.bold())
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(model.selectedGoal?.title ?? "Choose your next quest")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .lineLimit(2)
                    Text(model.statusMessage)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    Label(model.lastFocusState.label, systemImage: model.lastFocusState.symbolName)
                        .font(.headline)
                        .foregroundStyle(model.lastFocusState.tint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.32), in: Capsule())

                    Text("Level \(missionLevel)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                    Text("\(nextLevelXP) XP to next level")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .padding(24)
        .background(heroBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.purple.opacity(0.18), radius: 24, x: 0, y: 16)
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
        VStack(alignment: .leading, spacing: 14) {
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
                    .stroke(.white.opacity(0.45), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: min(model.stats.focusRatio, 1))
                    .stroke(.green, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text(DisplayFormatters.percent(model.stats.focusRatio))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                    Text("aligned")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 138, height: 138)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 200, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)

            Text(value)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
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
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
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
                Text("Adventure Log")
                    .font(.title3.bold())
                Spacer()
                Text("last 10 scouts")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            if model.recentSamples.isEmpty {
                ContentUnavailableView(
                    "No discoveries yet",
                    systemImage: "map",
                    description: Text("Begin Quest or run Scout Now. The log stays quiet until there is real activity to show.")
                )
                .frame(minHeight: 260)
            } else {
                ForEach(Array(model.recentSamples.prefix(10))) { sample in
                    ActivityObservationRow(sample: sample)
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
}

private struct ActivityObservationRow: View {
    let sample: ActivitySample

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(sample.focusState.tint.opacity(0.14))
                Image(systemName: sample.focusState.symbolName)
                    .foregroundStyle(sample.focusState.tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(activityTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text("Scout checked \(sample.appName) at \(DisplayFormatters.time(sample.timestamp))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            if sample.nudgeShown {
                Text("Nudge")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
        .padding(12)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var activityTitle: String {
        DashboardCopy.activitySummary(for: sample)
    }

    private var rowBackground: Color {
        switch sample.focusState {
        case .onGoal: return Color.green.opacity(0.10)
        case .maybe: return Color.yellow.opacity(0.12)
        case .offGoal: return Color.orange.opacity(0.12)
        case .unknown: return Color.gray.opacity(0.10)
        }
    }
}

private struct MissionInsightPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Quest Board")
                    .font(.title3.bold())
                Spacer()
                Label("Compass", systemImage: "location.north.line.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            if let goal = model.selectedGoal {
                MissionIntentCard(goal: goal)
                FocusWindowCard(goal: goal)
                DriftStatusCard(summary: model.activityWindowSummary)
                QuestCard(goal: goal, summary: model.activityWindowSummary)
            } else {
                ContentUnavailableView(
                    "No quest selected",
                    systemImage: "scope",
                    description: Text("Choose or create a mission. Scout waits until there is a clear quest.")
                )
                .frame(minHeight: 260)
            }
        }
        .padding(18)
        .frame(width: 380, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct MissionIntentCard: View {
    let goal: Goal

    var body: some View {
        PlayfulInfoCard(icon: "scope", title: "Main Quest", tint: .purple) {
            Text(goal.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FocusWindowCard: View {
    let goal: Goal

    var body: some View {
        PlayfulInfoCard(icon: "calendar.badge.clock", title: "Quest Hours", tint: .blue) {
            Text(DashboardCopy.scheduleSummary(for: goal.schedule))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DriftStatusCard: View {
    let summary: ActivityWindowSummary

    var body: some View {
        PlayfulInfoCard(icon: statusIcon, title: "Compass", tint: statusTint) {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ProgressView(value: summary.alignmentRatio)
                    .tint(statusTint)
            }
        }
    }

    private var statusIcon: String {
        switch summary.state {
        case .noSamples: return "map"
        case .onTrack: return "checkmark.seal.fill"
        case .mixed: return "gauge.medium"
        case .drifting: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var statusTint: Color {
        switch summary.state {
        case .noSamples, .mixed, .unknown: return .purple
        case .onTrack: return .green
        case .drifting: return .orange
        }
    }

    private var statusText: String {
        switch summary.state {
        case .noSamples:
            return "No scouts yet. The compass wakes up after a few check-ins."
        case .onTrack:
            return "Nice! Your recent activity is mostly on quest."
        case .mixed:
            return "Gathering clues before judging this work window."
        case .drifting:
            return "Compass wobbling. Make one clear comeback move, then check again."
        case .unknown:
            return "Scout needs model or permission setup before it can judge this window."
        }
    }
}

private struct QuestCard: View {
    let goal: Goal
    let summary: ActivityWindowSummary

    var body: some View {
        PlayfulInfoCard(icon: "star.fill", title: "Mini Quest", tint: .yellow) {
            VStack(alignment: .leading, spacing: 10) {
                Text(nextStep)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: index < filledStars ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                    }
                    Text("streak sparks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var filledStars: Int {
        min(3, summary.alignedCount)
    }

    private var nextStep: String {
        switch summary.state {
        case .drifting:
            return "Comeback challenge: return to one concrete step for \(goal.title), then Scout Now."
        case .unknown:
            return "Setup quest: finish model and permission setup so Scout can read the board."
        case .noSamples:
            return "Start tiny: do one focused step, then let the scout check in."
        case .onTrack:
            return "Keep the combo alive: one focused block, one tiny win, then let the scout check in."
        case .mixed:
            return "Pick the next obvious action for \(goal.title) and keep the compass steady."
        }
    }
}

private struct PlayfulInfoCard<Content: View>: View {
    let icon: String
    let title: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                }
                .frame(width: 34, height: 34)
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        }
    }
}

private enum DashboardCopy {
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

    static func scheduleSummary(for schedule: FocusSchedule) -> String {
        let weekdays = schedule.weekdays.sorted().map(weekdayName).joined(separator: ", ")
        return "\(weekdays), \(timeString(schedule.startMinute))–\(timeString(schedule.endMinute))"
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

    private static func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return "Day \(weekday)"
        }
    }

    private static func timeString(_ minuteOfDay: Int) -> String {
        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let calendar = Calendar.current
        let date = calendar.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
