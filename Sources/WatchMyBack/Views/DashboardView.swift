import SwiftUI
import WatchMyBackCore

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MissionHeader()

                HStack(alignment: .top, spacing: 16) {
                    FocusRingCard()
                    MetricTile(title: "Focus", value: DisplayFormatters.minutes(model.stats.focusSeconds), icon: "bolt.fill", tint: .green)
                    MetricTile(title: "Recoveries", value: "\(model.stats.recoveryCount)", icon: "arrow.uturn.backward.circle.fill", tint: .orange)
                    MetricTile(title: "XP", value: "\(model.stats.xp)", icon: "sparkles", tint: .purple)
                }

                HStack(alignment: .top, spacing: 16) {
                    TimelinePanel()
                    MissionInsightPanel()
                }
            }
            .padding(24)
        }
        .background {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.green.opacity(0.05),
                    Color.orange.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.togglePaused()
                } label: {
                    Label(model.settings.paused ? "Resume" : "Pause", systemImage: model.settings.paused ? "play.fill" : "pause.fill")
                }

                Button {
                    Task { await model.sampleNow(manual: true) }
                } label: {
                    Label("Sample Now", systemImage: "camera.metering.matrix")
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
}

private struct MissionHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.selectedGoal?.title ?? "No mission selected")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(model.statusMessage)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.lastFocusState.label, systemImage: model.lastFocusState.symbolName)
                    .font(.headline)
                    .foregroundStyle(model.lastFocusState.tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }

            if let lastError = model.lastError {
                Label(lastError, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }

            if !model.screenRecordingPermission.isGranted {
                PermissionStatusBanner()
            }
        }
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
                Text("Screen Recording permission needed")
                    .font(.headline)
                Text("Watch My Back cannot classify screenshots until it is enabled for the signed app bundle.")
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
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FocusRingCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mission Sync")
                .font(.headline)
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.18), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: min(model.stats.focusRatio, 1))
                    .stroke(.green.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text(DisplayFormatters.percent(model.stats.focusRatio))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("aligned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 132, height: 132)
        }
        .padding(18)
        .frame(width: 190, alignment: .topLeading)
        .frame(minHeight: 190, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TimelinePanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent Activity")
                .font(.title3.bold())

            if model.recentSamples.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "waveform.path.ecg",
                    description: Text("Resume tracking or run a manual sample.")
                )
                .frame(minHeight: 240)
            } else {
                ForEach(Array(model.recentSamples.prefix(10))) { sample in
                    ActivityObservationRow(sample: sample)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ActivityObservationRow: View {
    let sample: ActivitySample

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sample.focusState.symbolName)
                .foregroundStyle(sample.focusState.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(activityTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(sample.appName) · \(Int(sample.confidence * 100))% confidence · \(DisplayFormatters.time(sample.timestamp))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            if sample.nudgeShown {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var activityTitle: String {
        DashboardCopy.activitySummary(for: sample)
    }
}

private struct MissionInsightPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Mission Insight")
                .font(.title3.bold())

            if let goal = model.selectedGoal {
                MissionIntentCard(goal: goal)
                FocusWindowCard(goal: goal)
                DriftStatusCard(samples: model.recentSamples)
                NextStepCard(goal: goal, samples: model.recentSamples)
            } else {
                ContentUnavailableView(
                    "No mission selected",
                    systemImage: "scope",
                    description: Text("Choose or create a mission to start tracking activity.")
                )
                .frame(minHeight: 240)
            }
        }
        .padding(18)
        .frame(width: 360, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MissionIntentCard: View {
    let goal: Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Current mission", systemImage: "scope")
                .font(.headline)
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
        VStack(alignment: .leading, spacing: 8) {
            Label("Focus window", systemImage: "calendar.badge.clock")
                .font(.headline)
            Text(DashboardCopy.scheduleSummary(for: goal.schedule))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DriftStatusCard: View {
    let samples: [ActivitySample]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent alignment", systemImage: statusIcon)
                .font(.headline)
                .foregroundStyle(statusTint)
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var recentSamples: [ActivitySample] {
        let cutoff = Date().addingTimeInterval(-20 * 60)
        return samples.filter { $0.timestamp >= cutoff }
    }

    private var offGoalCount: Int {
        recentSamples.filter { $0.focusState == .offGoal }.count
    }

    private var alignedCount: Int {
        recentSamples.filter { $0.focusState == .onGoal }.count
    }

    private var statusIcon: String {
        if recentSamples.isEmpty { return "waveform.path.ecg" }
        if offGoalCount >= 3 { return "exclamationmark.triangle.fill" }
        if alignedCount >= max(1, recentSamples.count / 2) { return "checkmark.seal.fill" }
        return "gauge.medium"
    }

    private var statusTint: Color {
        if offGoalCount >= 3 { return .orange }
        if alignedCount >= max(1, recentSamples.count / 2) { return .green }
        return .secondary
    }

    private var statusText: String {
        guard !recentSamples.isEmpty else {
            return "No recent samples yet. Watch My Back will build a picture over the next few check-ins."
        }
        if offGoalCount >= 3 {
            return "A few recent check-ins look off mission. If this continues, a gentle nudge should bring you back."
        }
        if alignedCount >= max(1, recentSamples.count / 2) {
            return "Recent activity mostly looks aligned with the mission."
        }
        return "Still gathering enough context to judge the recent work window."
    }
}

private struct NextStepCard: View {
    let goal: Goal
    let samples: [ActivitySample]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Suggested next step", systemImage: "arrow.forward.circle")
                .font(.headline)
            Text(nextStep)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nextStep: String {
        if samples.first?.focusState == .offGoal {
            return "Return to one concrete step for \(goal.title), then sample again after a few minutes."
        }
        if samples.first?.focusState == .unknown {
            return "Finish model and permission setup so activity can be interpreted locally."
        }
        return "Keep working in short focused blocks. Watch My Back will only nudge after sustained drift."
    }
}

private enum DashboardCopy {
    static func activitySummary(for sample: ActivitySample) -> String {
        switch sample.activityCategory {
        case "built_in_model_not_ready":
            return "Model is not ready yet"
        case "screen_recording_permission_missing":
            return "Screen Recording permission is missing"
        case "classifier_unavailable", "unknown":
            return "Could not interpret this check-in"
        case "unchanged_screen":
            return "Screen looked unchanged"
        case "cloud_blocked":
            return "Cloud classification is blocked until opt-in"
        default:
            switch sample.focusState {
            case .onGoal:
                return humanize(sample.activityCategory, fallback: "Activity looks aligned")
            case .maybe:
                return humanize(sample.activityCategory, fallback: "Activity may be related")
            case .offGoal:
                return humanize(sample.activityCategory, fallback: "Activity may be off mission")
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
