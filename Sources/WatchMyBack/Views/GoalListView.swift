import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WatchMyBackCore

struct GoalListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingDraft: GoalDraft?
    @State private var missionPendingDelete: Goal?

    var body: some View {
        List(selection: $model.selectedGoalID) {
            Section {
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
                                model.duplicateMission(goal)
                            } label: {
                                Label("Duplicate Mission", systemImage: "plus.square.on.square")
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
                        }
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Missions")
                    TrackingStatusDot()
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

                Button(role: .destructive) {
                    if let goal = model.selectedGoal {
                        missionPendingDelete = goal
                    }
                } label: {
                    Label("Remove Mission", systemImage: "trash")
                }
                .disabled(model.selectedGoal == nil)
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

private struct TrackingStatusDot: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsDetails = false

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .help(statusText)
            .onTapGesture {
                showsDetails.toggle()
            }
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                Text(statusText)
                    .font(.callout)
                    .padding(12)
                    .frame(width: 220, alignment: .leading)
            }
    }

    private var statusColor: Color {
        if model.lastError != nil {
            return .red
        }
        return model.settings.paused ? .secondary : .green
    }

    private var statusText: String {
        if let lastError = model.lastError {
            return "Tracking needs attention: \(lastError)"
        }
        if model.settings.paused {
            return "Tracking is paused."
        }
        return "Tracking is active. Screenshots are classified and discarded."
    }
}

private struct GoalRow: View {
    let goal: Goal

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(statusColor.opacity(goal.isActive ? 0.14 : 0.08))
                Image(systemName: goal.isActive ? "scope" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text("\(goal.dailyTargetMinutes)m")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12), in: Capsule())

                    Text(scheduleSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
    }

    private var statusColor: Color { goal.isActive ? .green : .secondary }

    private var scheduleSummary: String { GoalDraft.scheduleString(goal.schedule) }
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
                    TextField("Goal", text: $draft.title)
                    DescriptionTaskList(draft: $draft)
                    Toggle("Active mission", isOn: $draft.isActive)
                    DailyTargetFields(minutes: $draft.dailyTargetMinutes)
                }

                Section("Quest Hours") {
                    WeekdayPicker(selection: $draft.weekdays)
                    TimeRangeFields(startMinute: $draft.startMinute, endMinute: $draft.endMinute)
                }

                Section("Scout Hints") {
                    AppSelectionField(title: "Helpful apps", text: $draft.allowedAppsText)
                    AppSelectionField(title: "Distracting apps", text: $draft.blockedAppsText)
                    TextField("On-quest examples", text: $draft.onGoalExamplesText, axis: .vertical)
                        .lineLimit(2...3)
                    TextField("Off-quest examples", text: $draft.offGoalExamplesText, axis: .vertical)
                        .lineLimit(2...3)
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
        .frame(width: 640, height: 740)
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            Button("All") {
                selection = Set(GoalDraft.weekdays.map(\.value))
            }
            .buttonStyle(.bordered)

            Button("Weekdays") {
                selection = Set([2, 3, 4, 5, 6])
            }
            .buttonStyle(.bordered)

            Button("Weekend") {
                selection = Set([1, 7])
            }
            .buttonStyle(.bordered)

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

private struct DescriptionTaskList: View {
    @Binding var draft: GoalDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description / Task")
                Spacer()
                Button {
                    draft.descriptionItems.append("")
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add task")
            }

            ForEach(draft.descriptionItems.indices, id: \.self) { index in
                TextField(inspiration, text: $draft.descriptionItems[index], axis: .vertical)
                    .lineLimit(1...3)
            }
        }
    }

    private var inspiration: String {
        let goal = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return "Describe one focused task" }
        return "Work on \(goal)"
    }
}

private struct DailyTargetFields: View {
    @Binding var minutes: Int

    var body: some View {
        HStack {
            Text("Daily target")
            Spacer()
            TextField("0", value: hoursBinding, format: .number)
                .frame(width: 54)
                .textFieldStyle(.roundedBorder)
            Text("hours")
            TextField("60", value: minuteRemainderBinding, format: .number)
                .frame(width: 54)
                .textFieldStyle(.roundedBorder)
            Text("mins")
        }
    }

    private var hoursBinding: Binding<Int> {
        Binding(
            get: { minutes / 60 },
            set: { value in minutes = max(15, min(720, value * 60 + minutes % 60)) }
        )
    }

    private var minuteRemainderBinding: Binding<Int> {
        Binding(
            get: { minutes % 60 },
            set: { value in minutes = max(15, min(720, (minutes / 60) * 60 + max(0, min(59, value)))) }
        )
    }
}

private struct TimeRangeFields: View {
    @Binding var startMinute: Int
    @Binding var endMinute: Int

    var body: some View {
        HStack {
            Text("Start")
            TextField("09:00", text: startText)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
            Text("End")
            TextField("17:00", text: endText)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var startText: Binding<String> {
        Binding(
            get: { Self.string(from: startMinute) },
            set: { if let minute = Self.minute(from: $0) { startMinute = minute } }
        )
    }

    private var endText: Binding<String> {
        Binding(
            get: { Self.string(from: endMinute) },
            set: { if let minute = Self.minute(from: $0) { endMinute = minute } }
        )
    }

    private static func string(from minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private static func minute(from text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
            return nil
        }
        return parts[0] * 60 + parts[1]
    }
}

private struct AppSelectionField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Button {
                    chooseApps()
                } label: {
                    Label("Choose Apps", systemImage: "folder.badge.plus")
                }
                .help("Choose one or more apps")
            }
            TextField(title, text: $text, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose \(title)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK {
            let selected = panel.urls.map { $0.deletingPathExtension().lastPathComponent }
            let existing = GoalDraft.list(from: text)
            text = (existing + selected).uniqued().joined(separator: ", ")
        }
    }
}

private struct GoalDraft: Identifiable {
    var id: UUID
    var title: String
    var description: String
    var descriptionItems: [String]
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
        descriptionItems = Self.list(from: goal.description)
        if descriptionItems.isEmpty {
            descriptionItems = [""]
        }
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
                title: "",
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
            description: descriptionItems
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
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

    fileprivate static func list(from text: String) -> [String] {
        text
            .split { character in
                character == "," || character == "\n" || character == ";"
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { value in
            seen.insert(value).inserted
        }
    }
}
