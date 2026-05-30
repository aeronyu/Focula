import SwiftUI
import WatchMyBackCore

struct GoalListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingDraft: GoalDraft?
    @State private var missionPendingDelete: Goal?

    var body: some View {
        List(selection: $model.selectedGoalID) {
            Section("Missions") {
                ForEach(model.goals) { goal in
                    GoalRow(goal: goal)
                        .tag(goal.id as UUID?)
                        .contextMenu {
                            Button {
                                editingDraft = GoalDraft(goal: goal)
                            } label: {
                                Label("Edit Mission", systemImage: "pencil")
                            }

                            Button {
                                model.activateMission(goal)
                            } label: {
                                Label("Make Active", systemImage: "scope")
                            }
                            .disabled(goal.isActive)

                            Button(role: .destructive) {
                                missionPendingDelete = goal
                            } label: {
                                Label("Remove Mission", systemImage: "trash")
                            }
                            .disabled(model.goals.count <= 1)
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    editingDraft = GoalDraft.newMission()
                } label: {
                    Label("New Mission", systemImage: "plus")
                }

                Button {
                    if let goal = model.selectedGoal {
                        editingDraft = GoalDraft(goal: goal)
                    }
                } label: {
                    Label("Edit Mission", systemImage: "pencil")
                }
                .disabled(model.selectedGoal == nil)

                Button(role: .destructive) {
                    if let goal = model.selectedGoal {
                        missionPendingDelete = goal
                    }
                } label: {
                    Label("Remove Mission", systemImage: "trash")
                }
                .disabled(model.selectedGoal == nil || model.goals.count <= 1)
            }
        }
        .sheet(item: $editingDraft) { draft in
            GoalEditorSheet(
                draft: draft,
                onCancel: { editingDraft = nil },
                onSave: { goal in
                    model.saveMission(goal)
                    editingDraft = nil
                }
            )
        }
        .alert("Remove mission?", isPresented: deleteAlertBinding) {
            Button("Cancel", role: .cancel) {
                missionPendingDelete = nil
            }
            Button("Remove", role: .destructive) {
                if let missionPendingDelete {
                    model.deleteMission(missionPendingDelete)
                }
                missionPendingDelete = nil
            }
        } message: {
            Text(deleteMessage)
        }
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

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { missionPendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    missionPendingDelete = nil
                }
            }
        )
    }

    private var deleteMessage: String {
        guard let missionPendingDelete else {
            return ""
        }
        return "This removes \"\(missionPendingDelete.title)\" from your mission list. Past activity samples remain as history."
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
                Text(rowDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var rowDetail: String {
        "\(goal.dailyTargetMinutes)m target · \(GoalDraft.scheduleString(goal.schedule))"
    }
}

private struct GoalEditorSheet: View {
    @State private var draft: GoalDraft
    let onCancel: () -> Void
    let onSave: (Goal) -> Void

    init(draft: GoalDraft, onCancel: @escaping () -> Void, onSave: @escaping (Goal) -> Void) {
        _draft = State(initialValue: draft)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Mission") {
                    TextField("Title", text: $draft.title)
                    TextField("Intent", text: $draft.description, axis: .vertical)
                        .lineLimit(3...5)
                    Toggle("Active mission", isOn: $draft.isActive)
                    Stepper(value: $draft.dailyTargetMinutes, in: 15...720, step: 15) {
                        Text("\(draft.dailyTargetMinutes)m daily target")
                    }
                }

                Section("Quest Hours") {
                    WeekdayPicker(selection: $draft.weekdays)

                    Picker("Start", selection: $draft.startMinute) {
                        ForEach(GoalDraft.timeOptions, id: \.self) { minute in
                            Text(GoalDraft.timeString(minute)).tag(minute)
                        }
                    }

                    Picker("End", selection: $draft.endMinute) {
                        ForEach(GoalDraft.timeOptions, id: \.self) { minute in
                            Text(GoalDraft.timeString(minute)).tag(minute)
                        }
                    }
                }

                Section("Scout Hints") {
                    TextField("Helpful apps", text: $draft.allowedAppsText, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Distracting apps", text: $draft.blockedAppsText, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("On-quest examples", text: $draft.onGoalExamplesText, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Off-quest examples", text: $draft.offGoalExamplesText, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                Spacer()
                Button {
                    onSave(draft.goal)
                } label: {
                    Label("Save Mission", systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSave)
            }
            .padding()
            .background(.bar)
        }
        .frame(width: 560, height: 680)
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GoalDraft.weekdays, id: \.value) { day in
                Button {
                    toggle(day.value)
                } label: {
                    Text(day.label)
                        .font(.caption.weight(.semibold))
                        .frame(width: 34, height: 28)
                }
                .buttonStyle(.bordered)
                .tint(selection.contains(day.value) ? .green : .secondary)
            }
        }
    }

    private func toggle(_ weekday: Int) {
        if selection.contains(weekday) {
            selection.remove(weekday)
        } else {
            selection.insert(weekday)
        }
    }
}

private struct GoalDraft: Identifiable {
    var id: UUID
    var title: String
    var description: String
    var weekdays: Set<Int>
    var startMinute: Int
    var endMinute: Int
    var dailyTargetMinutes: Int
    var isActive: Bool
    var allowedAppsText: String
    var blockedAppsText: String
    var onGoalExamplesText: String
    var offGoalExamplesText: String

    init(goal: Goal) {
        id = goal.id
        title = goal.title
        description = goal.description
        weekdays = goal.schedule.weekdays
        startMinute = goal.schedule.startMinute
        endMinute = goal.schedule.endMinute
        dailyTargetMinutes = goal.dailyTargetMinutes
        isActive = goal.isActive
        allowedAppsText = goal.allowedApps.joined(separator: ", ")
        blockedAppsText = goal.blockedApps.joined(separator: ", ")
        onGoalExamplesText = goal.onGoalExamples.joined(separator: "\n")
        offGoalExamplesText = goal.offGoalExamples.joined(separator: "\n")
    }

    static func newMission() -> GoalDraft {
        GoalDraft(
            goal: Goal(
                title: "New Mission",
                description: "",
                schedule: .weekdaysNineToFive,
                allowedApps: [],
                blockedApps: [],
                onGoalExamples: [],
                offGoalExamples: [],
                dailyTargetMinutes: 60,
                isActive: true
            )
        )
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !weekdays.isEmpty && startMinute != endMinute
    }

    var goal: Goal {
        Goal(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: FocusSchedule(weekdays: weekdays, startMinute: startMinute, endMinute: endMinute),
            allowedApps: Self.list(from: allowedAppsText),
            blockedApps: Self.list(from: blockedAppsText),
            onGoalExamples: Self.list(from: onGoalExamplesText),
            offGoalExamples: Self.list(from: offGoalExamplesText),
            dailyTargetMinutes: dailyTargetMinutes,
            isActive: isActive
        )
    }

    static let weekdays: [(value: Int, label: String)] = [
        (1, "Sun"),
        (2, "Mon"),
        (3, "Tue"),
        (4, "Wed"),
        (5, "Thu"),
        (6, "Fri"),
        (7, "Sat")
    ]

    static let timeOptions: [Int] = stride(from: 0, through: 23 * 60 + 45, by: 15).map { $0 }

    static func timeString(_ minuteOfDay: Int) -> String {
        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func scheduleString(_ schedule: FocusSchedule) -> String {
        let days = schedule.weekdays.sorted().map { weekday in
            weekdays.first(where: { $0.value == weekday })?.label ?? "Day \(weekday)"
        }
        return "\(days.joined(separator: ", ")), \(timeString(schedule.startMinute))-\(timeString(schedule.endMinute))"
    }

    private static func list(from text: String) -> [String] {
        text
            .split { character in
                character == "," || character == "\n" || character == ";"
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
