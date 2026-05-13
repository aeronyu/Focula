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
                    GoalDetailPanel()
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
                    Text("focus")
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
            Text("Recent Signals")
                .font(.title3.bold())

            if model.recentSamples.isEmpty {
                ContentUnavailableView(
                    "No samples yet",
                    systemImage: "waveform.path.ecg",
                    description: Text("Resume tracking or run a manual sample.")
                )
                .frame(minHeight: 240)
            } else {
                ForEach(Array(model.recentSamples.prefix(10))) { sample in
                    HStack(spacing: 12) {
                        Image(systemName: sample.focusState.symbolName)
                            .foregroundStyle(sample.focusState.tint)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(sample.appName)
                                .font(.headline)
                            Text("\(sample.activityCategory) · \(Int(sample.confidence * 100))% · \(DisplayFormatters.time(sample.timestamp))")
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
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct GoalDetailPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Goal Rules")
                .font(.title3.bold())

            if let goal = model.selectedGoal {
                RuleBlock(title: "Allowed apps", items: goal.allowedApps, tint: .green)
                RuleBlock(title: "Blocked apps", items: goal.blockedApps, tint: .pink)
                RuleBlock(title: "On-goal examples", items: goal.onGoalExamples, tint: .teal)
                RuleBlock(title: "Off-goal examples", items: goal.offGoalExamples, tint: .orange)
            }
        }
        .padding(18)
        .frame(width: 300, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RuleBlock: View {
    let title: String
    let items: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            FlowLayout(items: items, tint: tint)
        }
    }
}

private struct FlowLayout: View {
    let items: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
