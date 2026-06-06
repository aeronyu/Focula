import SwiftUI
import WatchMyBackCore

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: DashboardTab = .overview

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Picker("Dashboard section", selection: $selectedTab) {
                    ForEach(DashboardTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch selectedTab {
                case .overview:
                    MissionHeroCard()

                    LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
                        QuestSyncWaterCard()
                        MetricTile(title: "Focus Time", value: DisplayFormatters.minutes(model.stats.focusSeconds), subtitle: "aligned today", icon: "bolt.fill", tint: .mint)
                        MetricTile(title: "Comebacks", value: "\(model.stats.recoveryCount)", subtitle: "course corrections", icon: "arrow.uturn.backward.circle.fill", tint: .orange)
                        MetricTile(title: "XP", value: "\(model.stats.xp)", subtitle: "mission points", icon: "sparkles", tint: .pink)
                    }

                    TimelinePanel()
                case .missionDetails:
                    MissionDetailsPanel()
                case .alerts:
                    AlertsPanel()
                }
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
                .help(model.settings.paused ? "Resume tracking" : "Pause tracking")

                Button {
                    Task { await model.sampleNow(manual: true) }
                } label: {
                    Label("Scout Now", systemImage: "camera.metering.matrix")
                }
                .disabled(model.isSampling)
                .help("Run one screen check now")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open settings")
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

private enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case missionDetails
    case alerts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .missionDetails: "Mission Details"
        case .alerts: "Alerts"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .missionDetails: "square.and.pencil"
        case .alerts: "bell.badge"
        }
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
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(heroAccent.opacity(0.18), lineWidth: 1)
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
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .trailing, spacing: 8) {
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

private struct MissionDetailsPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft: DashboardMissionDraft?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Mission Details", systemImage: "square.and.pencil")
                    .font(.title3.bold())
                Spacer()
            }

            if draft != nil {
                Form {
                    Section("Mission") {
                        TextField("Goal", text: draftBinding(\.title))
                        DashboardDescriptionTaskList(draft: draftBinding())
                        Toggle("Active mission", isOn: draftBinding(\.isActive))
                        DashboardDailyTargetFields(minutes: draftBinding(\.dailyTargetMinutes))
                    }

                    Section("Quest Hours") {
                        DashboardWeekdayPicker(selection: draftBinding(\.weekdays))
                        DashboardTimeRangeFields(startMinute: draftBinding(\.startMinute), endMinute: draftBinding(\.endMinute))
                    }

                    Section("Scout Hints") {
                        DashboardHintField(title: "Helpful apps", text: draftBinding(\.allowedAppsText), lineLimit: 1...3)
                        DashboardHintField(title: "Distracting apps", text: draftBinding(\.blockedAppsText), lineLimit: 1...3)
                        DashboardHintField(title: "On-quest examples", text: draftBinding(\.onGoalExamplesText), lineLimit: 2...3)
                        DashboardHintField(title: "Off-quest examples", text: draftBinding(\.offGoalExamplesText), lineLimit: 2...3)
                    }
                }
                .formStyle(.grouped)
                .frame(minHeight: 540)
            } else {
                ContentUnavailableView(
                    "No mission selected",
                    systemImage: "scope",
                    description: Text("Select a mission from the sidebar to edit its details.")
                )
                .frame(minHeight: 360)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(0.14), lineWidth: 1)
        }
        .onAppear(perform: syncDraftFromSelection)
        .onChange(of: model.selectedGoal?.id) { _, _ in
            syncDraftFromSelection()
        }
        .onChange(of: model.selectedGoal) { _, goal in
            guard let goal, draft?.id != goal.id else { return }
            draft = DashboardMissionDraft(goal: goal)
        }
        .onChange(of: draft) { _, value in
            scheduleAutosave(value)
        }
        .onDisappear {
            saveTask?.cancel()
        }
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<DashboardMissionDraft, Value>) -> Binding<Value> {
        Binding(
            get: { draft![keyPath: keyPath] },
            set: { value in
                draft?[keyPath: keyPath] = value
            }
        )
    }

    private func draftBinding() -> Binding<DashboardMissionDraft> {
        Binding(
            get: { draft! },
            set: { value in draft = value }
        )
    }

    private func syncDraftFromSelection() {
        if let goal = model.selectedGoal {
            draft = DashboardMissionDraft(goal: goal)
        } else {
            draft = nil
        }
    }

    private func scheduleAutosave(_ draft: DashboardMissionDraft?) {
        saveTask?.cancel()
        guard let draft, draft.canSave else { return }
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            model.saveMission(draft.goal)
        }
    }
}

private struct DashboardHintField: View {
    let title: String
    @Binding var text: String
    let lineLimit: ClosedRange<Int>

    var body: some View {
        TextField(title, text: $text, prompt: Text("Add \(title.lowercased())"), axis: .vertical)
            .lineLimit(lineLimit)
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 2)
    }
}

private struct AlertsPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Alerts", systemImage: "bell.badge")
                .font(.title3.bold())

            Toggle(
                "Alert on sustained drift",
                isOn: Binding(
                    get: { model.settings.notificationPreferences.notifyOnSustainedDrift },
                    set: { enabled in
                        var preferences = model.settings.notificationPreferences
                        preferences.notifyOnSustainedDrift = enabled
                        model.updateNotificationPreferences(preferences)
                    }
                )
            )

            Toggle(
                "Alert on model or runtime failures",
                isOn: Binding(
                    get: { model.settings.notificationPreferences.notifyOnRuntimeFailure },
                    set: { enabled in
                        var preferences = model.settings.notificationPreferences
                        preferences.notifyOnRuntimeFailure = enabled
                        model.updateNotificationPreferences(preferences)
                    }
                )
            )

            Divider()

            if let lastError = model.lastError {
                Label(lastError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("No current alerts", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Sampling")
                    .font(.headline)
                Text(model.settings.samplingStrategy.summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct DashboardWeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                quickButton("All") { selection = Set(DashboardMissionDraft.weekdays.map(\.value)) }
                quickButton("Weekdays") { selection = Set([2, 3, 4, 5, 6]) }
                quickButton("Weekend") { selection = Set([1, 7]) }
            }

            HStack(spacing: 8) {
                ForEach(DashboardMissionDraft.weekdays, id: \.value) { day in
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

private struct DashboardDescriptionTaskList: View {
    @Binding var draft: DashboardMissionDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(draft.descriptionItems.count == 1 ? "Task" : "Tasks")
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
                    Text("•")
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    TextField("", text: $draft.descriptionItems[index], prompt: Text(inspiration), axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.plain)

                    if index > 0 {
                        Button(role: .destructive) {
                            draft.descriptionItems.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove task")
                    }
                }
            }
        }
    }

    private var inspiration: String {
        let goal = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return "Describe one focused task" }
        return "Work on \(goal)"
    }
}

private struct DashboardDailyTargetFields: View {
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

private struct DashboardTimeRangeFields: View {
    @Binding var startMinute: Int
    @Binding var endMinute: Int
    @State private var selectedPreset: DashboardQuestHoursPreset = .custom

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(DashboardQuestHoursPreset.allCases) { preset in
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

            if selectedPreset == .custom {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    TextField("", text: startText)
                        .frame(width: 86)
                        .textFieldStyle(.roundedBorder)
                    Text("-")
                        .foregroundStyle(.secondary)
                    TextField("", text: endText)
                        .frame(width: 86)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .onAppear {
            selectedPreset = DashboardQuestHoursPreset.matching(start: startMinute, end: endMinute)
        }
        .onChange(of: startMinute) { _, _ in
            selectedPreset = DashboardQuestHoursPreset.matching(start: startMinute, end: endMinute)
        }
        .onChange(of: endMinute) { _, _ in
            selectedPreset = DashboardQuestHoursPreset.matching(start: startMinute, end: endMinute)
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

private enum DashboardQuestHoursPreset: String, CaseIterable, Identifiable {
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

    static func matching(start: Int, end: Int) -> DashboardQuestHoursPreset {
        allCases.first { $0.range?.start == start && $0.range?.end == end } ?? .custom
    }
}

private struct DashboardMissionDraft: Equatable {
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

    private static func list(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

private struct QuestSyncWaterCard: View {
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

            WaterLevelView(progress: model.stats.focusRatio)
                .frame(height: 92)
                .overlay(alignment: .center) {
                    VStack(spacing: 3) {
                        Text(DisplayFormatters.percent(model.stats.focusRatio))
                            .font(.title.bold())
                        Text("aligned")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

private struct WaterLevelView: View {
    let progress: Double
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(progress, 0), 1)
            let visibleLevel = max(0.06, clamped)
            let waterTop = proxy.size.height * (1 - visibleLevel)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.08))

                WaveShape(phase: phase, amplitude: 5, waterTop: waterTop)
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.55), Color.mint.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                WaveShape(phase: phase + .pi, amplitude: 3, waterTop: waterTop + 4)
                    .fill(Color.mint.opacity(0.28))
            }
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    phase = .pi * 2
                }
            }
        }
    }
}

private struct WaveShape: Shape {
    var phase: CGFloat
    var amplitude: CGFloat
    var waterTop: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: waterTop))

        let step: CGFloat = 6
        var x = rect.minX
        while x <= rect.maxX + step {
            let relative = x / max(rect.width, 1)
            let y = waterTop + sin(relative * .pi * 2 + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
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
            visibility: model.settings.activityLogVisibility,
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
        visibility: ActivityLogVisibility = .allActivity,
        setupState: ActivityLogSetupState = ActivityLogSetupState(
            builtInModelReady: false,
            screenRecordingGranted: false,
            cloudOptInAllowed: false
        )
    ) -> [ActivityLogEntry] {
        var entries: [ActivityLogEntry] = []
        var setupCounts: [String: (sample: ActivitySample, count: Int)] = [:]

        for block in ActivityLogCompactor.compact(samples: Array(samples.prefix(240))).prefix(80) {
            let sample = block.latestSample
            if isSetupNoise(sample) {
                guard shouldShowSetupNoise(sample, setupState: setupState) else {
                    continue
                }
                let key = sample.activityCategory
                if let current = setupCounts[key] {
                    setupCounts[key] = (current.sample, current.count + block.sampleCount)
                } else {
                    setupCounts[key] = (sample, block.sampleCount)
                }
                continue
            }

            if visibility == .focusOnly, sample.focusState == .offGoal {
                continue
            }
            entries.append(activityEntry(for: block))
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
        case "built_in_model_runtime_error":
            return "Local model needs a restart"
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

    private static func activityEntry(for block: ActivityLogBlock) -> ActivityLogEntry {
        let sample = block.latestSample
        return ActivityLogEntry(
            id: sample.id.uuidString,
            title: activitySummary(for: sample),
            detail: activityDetail(for: block),
            icon: sample.focusState.symbolName,
            tint: sample.focusState.tint,
            background: rowBackground(for: sample.focusState),
            nudgeShown: sample.nudgeShown
        )
    }

    private static func activityDetail(for block: ActivityLogBlock) -> String {
        let timeRange = block.sampleCount > 1
            ? "\(DisplayFormatters.time(block.start))-\(DisplayFormatters.time(block.end))"
            : DisplayFormatters.time(block.end)
        let duration = DisplayFormatters.minutes(block.durationSeconds)
        if block.sampleCount > 1 {
            return "\(duration) in \(block.appName) · \(block.sampleCount) check-ins · \(timeRange)"
        }
        return "Scout checked \(block.appName) at \(timeRange)"
    }

    private static func setupEntry(for sample: ActivitySample, count: Int) -> ActivityLogEntry {
        return ActivityLogEntry(
            id: "setup-\(sample.activityCategory)",
            title: setupTitle(for: sample),
            detail: setupDetail(for: sample, count: count),
            icon: setupIcon(for: sample),
            tint: setupTint(for: sample),
            background: setupTint(for: sample).opacity(0.08),
            nudgeShown: false
        )
    }

    private static func isSetupNoise(_ sample: ActivitySample) -> Bool {
        switch sample.activityCategory {
        case "built_in_model_not_ready",
             "built_in_model_runtime_error",
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
        case "built_in_model_runtime_error":
            return true
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
        case "built_in_model_runtime_error":
            return "Restart local model"
        case "screen_recording_permission_missing":
            return "Grant Screen Recording"
        case "cloud_blocked":
            return "Cloud scout needs opt-in"
        default:
            return "Scout setup needs attention"
        }
    }

    private static func setupDetail(for sample: ActivitySample, count: Int) -> String {
        let plural = count == 1 ? "check-in" : "check-ins"
        let action: String
        switch sample.activityCategory {
        case "built_in_model_runtime_error":
            action = count == 1 ? "needs model restart" : "need model restart"
        case "screen_recording_permission_missing":
            action = count == 1 ? "needs screen access" : "need screen access"
        case "cloud_blocked":
            action = count == 1 ? "needs cloud opt-in" : "need cloud opt-in"
        default:
            action = count == 1 ? "needs setup" : "need setup"
        }
        return "\(count) \(plural) \(action) · latest \(DisplayFormatters.time(sample.timestamp))"
    }

    private static func setupIcon(for sample: ActivitySample) -> String {
        switch sample.activityCategory {
        case "screen_recording_permission_missing":
            return "camera.viewfinder"
        case "built_in_model_not_ready":
            return "cpu"
        case "built_in_model_runtime_error":
            return "exclamationmark.triangle"
        case "cloud_blocked":
            return "lock.shield"
        default:
            return "wrench.and.screwdriver"
        }
    }

    private static func setupTint(for sample: ActivitySample) -> Color {
        switch sample.activityCategory {
        case "built_in_model_runtime_error":
            return .orange
        case "screen_recording_permission_missing":
            return .blue
        case "cloud_blocked":
            return .purple
        default:
            return .purple
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
