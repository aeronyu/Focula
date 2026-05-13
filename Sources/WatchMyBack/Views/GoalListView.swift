import SwiftUI
import WatchMyBackCore

struct GoalListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selectedGoalID) {
            Section("Missions") {
                ForEach(model.goals) { goal in
                    GoalRow(goal: goal)
                        .tag(goal.id as UUID?)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Label(model.settings.paused ? "Tracking paused" : "Tracking active", systemImage: model.settings.paused ? "pause.circle" : "scope")
                    .foregroundStyle(model.settings.paused ? Color.secondary : Color.green)
                Text("Screenshots are never stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }
}

private struct GoalRow: View {
    let goal: Goal

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: goal.isActive ? "scope" : "circle")
                .foregroundStyle(goal.isActive ? .green : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .lineLimit(1)
                Text("\(goal.dailyTargetMinutes)m target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
