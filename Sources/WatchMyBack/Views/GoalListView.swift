import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WatchMyBackCore

struct GoalListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingDraft: GoalDraft?
    @State private var missionsPendingDelete: [Goal] = []
    @State private var selectedMissionIDs: Set<UUID> = []

    var body: some View {
        List(selection: $selectedMissionIDs) {
            Section {
                ForEach(primaryGoals) { goal in
                    GoalRow(goal: goal)
                        .tag(goal.id)
                        .contextMenu { missionContextMenu(for: goal) }
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Missions")
                    TrackingStatusDot()
                }
            }

            if shouldShowNotTrackingToday {
                Section("Not Tracking Today") {
                    ForEach(notTrackingTodayGoals) { goal in
                        GoalRow(goal: goal)
                            .tag(goal.id)
                            .contextMenu { missionContextMenu(for: goal) }
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
            }
        }
        .onAppear {
            if let selectedGoalID = model.selectedGoalID {
                selectedMissionIDs = [selectedGoalID]
            }
        }
        .onChange(of: selectedMissionIDs) { _, ids in
            model.selectedGoalID = ids.first ?? model.selectedGoalID
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
                missionsPendingDelete = []
            }
            Button("Remove", role: .destructive) {
                if missionsPendingDelete.count == 1, let mission = missionsPendingDelete.first {
                    model.deleteMission(mission)
                } else {
                    model.deleteMissions(ids: Set(missionsPendingDelete.map(\.id)))
                }
                selectedMissionIDs.subtract(missionsPendingDelete.map(\.id))
                missionsPendingDelete = []
            }
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { !missionsPendingDelete.isEmpty },
            set: { isPresented in
                if !isPresented {
                    missionsPendingDelete = []
                }
            }
        )
    }

    private var deleteMessage: String {
        if missionsPendingDelete.count == 1, let mission = missionsPendingDelete.first {
            return "This removes \"\(mission.title)\" from your mission list. Past activity samples remain as history."
        }
        return "This removes \(missionsPendingDelete.count) missions from your mission list. Past activity samples remain as history."
    }

    private var todayWeekday: Int {
        Calendar.current.component(.weekday, from: Date())
    }

    private var primaryGoals: [Goal] {
        let scheduledToday = todayGoals
        return scheduledToday.isEmpty ? model.goals : scheduledToday
    }

    private var todayGoals: [Goal] {
        model.goals.filter { $0.schedule.weekdays.contains(todayWeekday) }
    }

    private var notTrackingTodayGoals: [Goal] {
        model.goals.filter { !$0.schedule.weekdays.contains(todayWeekday) }
    }

    private var shouldShowNotTrackingToday: Bool {
        model.goals.count > 1 && !todayGoals.isEmpty && !notTrackingTodayGoals.isEmpty
    }

    @ViewBuilder
    private func missionContextMenu(for goal: Goal) -> some View {
        let ids = contextIDs(for: goal)
        let selectedGoals = model.goals.filter { ids.contains($0.id) }
        let batch = ids.count > 1

        Button {
            editingDraft = GoalDraft(goal: goal)
        } label: {
            Label("Edit Mission", systemImage: "pencil")
        }
        .disabled(batch)

        Button {
            model.duplicateMission(goal)
        } label: {
            Label("Duplicate Mission", systemImage: "plus.square.on.square")
        }
        .disabled(batch)

        Button {
            model.setMissionsTracking(ids: ids, enabled: true)
        } label: {
            Label(batch ? "Turn On Tracking" : "Track Mission", systemImage: "scope")
        }
        .disabled(selectedGoals.allSatisfy(\.isActive))

        Button {
            model.setMissionsTracking(ids: ids, enabled: false)
        } label: {
            Label(batch ? "Turn Off Tracking" : "Stop Tracking", systemImage: "pause.circle")
        }
        .disabled(selectedGoals.allSatisfy { !$0.isActive })

        Button(role: .destructive) {
            missionsPendingDelete = selectedGoals
        } label: {
            Label(batch ? "Remove Missions" : "Remove Mission", systemImage: "trash")
        }
    }

    private func contextIDs(for goal: Goal) -> Set<UUID> {
        selectedMissionIDs.contains(goal.id) ? selectedMissionIDs : [goal.id]
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
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 340, alignment: .leading)
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
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())

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
                    GoalEditorMissionFields(draft: $draft)
                }

                Section("Quest Hours") {
                    WeekdayPicker(selection: $draft.weekdays)
                    TimeRangeFields(startMinute: $draft.startMinute, endMinute: $draft.endMinute)
                }

                Section("Scout Hints") {
                    AppHintCardList(
                        title: "Helpful apps",
                        systemImage: "checkmark.circle",
                        cards: $draft.helpfulAppCards,
                        fallbackBehavior: "Focused work in this app"
                    )
                    AppHintCardList(
                        title: "Distracting apps",
                        systemImage: "exclamationmark.triangle",
                        cards: $draft.distractingAppCards,
                        fallbackBehavior: "Side-tracked activity in this app"
                    )
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                quickButton("All") { selection = Set(GoalDraft.weekdays.map(\.value)) }
                quickButton("Weekdays") { selection = Set([2, 3, 4, 5, 6]) }
                quickButton("Weekend") { selection = Set([1, 7]) }
            }

            HStack(spacing: 8) {
                ForEach(GoalDraft.weekdays, id: \.value) { day in
                    Button {
                        toggle(day.value)
                    } label: {
                        Text(day.label)
                            .font(.caption.weight(.semibold))
                            .frame(width: 42, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .tint(selection.contains(day.value) ? .green : .secondary)
                }
            }
        }
    }

    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
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
                Text(draft.descriptionItems.count == 1 ? "Task" : "Tasks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    draft.descriptionItems.append("")
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Add task")
            }

            ForEach(draft.descriptionItems.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .foregroundStyle(.secondary)
                        .frame(width: 6, height: 6)
                    LeftAlignedPlainField(text: $draft.descriptionItems[index], placeholder: inspiration)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(role: .destructive) {
                        draft.descriptionItems.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete task")
                    .opacity(draft.descriptionItems.count > 1 ? 1 : 0)
                    .disabled(draft.descriptionItems.count <= 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu {
                    if index > 0 {
                        Button(role: .destructive) {
                            draft.descriptionItems.remove(at: index)
                        } label: {
                            Label("Delete Task", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inspiration: String {
        let goal = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return "Describe one focused task" }
        return "Work on \(goal)"
    }
}

private struct GoalEditorMissionFields: View {
    @Binding var draft: GoalDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Goal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LeadingPlainTextField(text: $draft.title, placeholder: "Enter your goal")
                    .frame(minHeight: 28)
            }

            Divider()

            DescriptionTaskList(draft: $draft)

            Divider()

            Toggle("Track mission", isOn: $draft.isActive)

            Divider()

            DailyTargetFields(minutes: $draft.dailyTargetMinutes)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DailyTargetFields: View {
    @Binding var minutes: Int

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 10, verticalSpacing: 0) {
            GridRow {
            Text("Daily target")
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextField("", value: hoursBinding, format: .number)
                    .frame(width: 64)
                    .textFieldStyle(.roundedBorder)
                Text("hours")
                TextField("", value: minuteRemainderBinding, format: .number)
                    .frame(width: 64)
                    .textFieldStyle(.roundedBorder)
                Text("mins")
            }
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
    @State private var selectedPreset: QuestHoursPreset = .custom

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            presets
            if selectedPreset == .custom {
                customFields
            }
        }
        .onAppear {
            selectedPreset = QuestHoursPreset.matching(start: startMinute, end: endMinute)
        }
        .onChange(of: startMinute) { _, _ in
            selectedPreset = QuestHoursPreset.matching(start: startMinute, end: endMinute)
        }
        .onChange(of: endMinute) { _, _ in
            selectedPreset = QuestHoursPreset.matching(start: startMinute, end: endMinute)
        }
    }

    private var presets: some View {
        HStack(spacing: 8) {
                ForEach(QuestHoursPreset.allCases) { preset in
                    Button(preset.label) {
                        selectedPreset = preset
                        if let range = preset.range {
                            startMinute = range.start
                            endMinute = range.end
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(selectedPreset == preset ? .green : .secondary)
                }
            }
    }

    private var customFields: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
            TextField("", text: startText)
                .multilineTextAlignment(.center)
                .frame(width: 108)
                .textFieldStyle(.roundedBorder)
            Text("-")
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            TextField("", text: endText)
                .multilineTextAlignment(.center)
                .frame(width: 108)
                .textFieldStyle(.roundedBorder)
        }
        .fixedSize(horizontal: true, vertical: false)
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

private enum QuestHoursPreset: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case night
    case allDay
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .night: "Night"
        case .allDay: "All day"
        case .custom: "Custom"
        }
    }

    var range: (start: Int, end: Int)? {
        switch self {
        case .morning: (6 * 60, 12 * 60)
        case .afternoon: (12 * 60, 17 * 60)
        case .night: (18 * 60, 23 * 60 + 45)
        case .allDay: (0, 23 * 60 + 59)
        case .custom: nil
        }
    }

    static func matching(start: Int, end: Int) -> QuestHoursPreset {
        allCases.first { $0.range?.start == start && $0.range?.end == end } ?? .custom
    }
}

private struct AppHintCardList: View {
    let title: String
    let systemImage: String
    @Binding var cards: [AppHintCardDraft]
    let fallbackBehavior: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Button {
                    chooseApps()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add apps")
            }

            if cards.isEmpty {
                Text("Add apps to teach Scout how this mission uses them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach($cards) { $card in
                AppHintCard(card: $card, fallbackBehavior: fallbackBehavior) {
                    cards.removeAll { $0.id == card.id }
                }
            }
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
            let existing = Set(cards.map(\.appName))
            cards.append(contentsOf: selected.filter { !existing.contains($0) }.map {
                AppHintCardDraft(appName: $0, behaviors: [""])
            })
        }
    }
}

private struct AppHintCard: View {
    @Binding var card: AppHintCardDraft
    let fallbackBehavior: String
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(card.appName, systemImage: "app")
                    .font(.headline)
                Spacer()
                Button {
                    card.behaviors.append("")
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add behavior")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove app")
            }

            ForEach(card.behaviors.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .foregroundStyle(.secondary)
                        .frame(width: 5, height: 5)
                    LeftAlignedPlainField(text: $card.behaviors[index], placeholder: fallbackBehavior)
                    if index > 0 {
                        Button(role: .destructive) {
                            card.behaviors.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove behavior")
                    }
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LeftAlignedPlainField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        LeadingPlainTextField(text: $text, placeholder: placeholder)
            .frame(minHeight: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    var helpfulAppCards: [AppHintCardDraft]
    var distractingAppCards: [AppHintCardDraft]

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
        helpfulAppCards = Self.cards(apps: goal.allowedApps, examples: goal.onGoalExamples)
        distractingAppCards = Self.cards(apps: goal.blockedApps, examples: goal.offGoalExamples)
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
            allowedApps: helpfulAppCards.map(\.appName).filter { !$0.isEmpty }.uniqued(),
            blockedApps: distractingAppCards.map(\.appName).filter { !$0.isEmpty }.uniqued(),
            onGoalExamples: Self.examples(from: helpfulAppCards),
            offGoalExamples: Self.examples(from: distractingAppCards),
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

    private static func cards(apps: [String], examples: [String]) -> [AppHintCardDraft] {
        apps.map { app in
            AppHintCardDraft(
                appName: app,
                behaviors: examplesForApp(app, examples: examples)
            )
        }
    }

    private static func examplesForApp(_ app: String, examples: [String]) -> [String] {
        let prefix = "\(app):"
        let matched = examples.compactMap { example -> String? in
            guard example.localizedCaseInsensitiveContains(prefix) else { return nil }
            return String(example.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return matched.isEmpty ? [""] : matched
    }

    private static func examples(from cards: [AppHintCardDraft]) -> [String] {
        cards.flatMap { card in
            card.behaviors
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { "\(card.appName): \($0)" }
        }
    }
}

private struct AppHintCardDraft: Identifiable, Equatable {
    var id = UUID()
    var appName: String
    var behaviors: [String]
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { value in
            seen.insert(value).inserted
        }
    }
}
