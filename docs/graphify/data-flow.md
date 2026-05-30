# Data Flow

This page summarizes runtime data flow for Graphify-assisted review.

## Sampling and classification

```text
Timer or manual Sample Now
  -> AppModel.sampleNow(manual:)
  -> active Goal lookup
  -> FocusSchedule.contains(Date)
  -> FrontmostAppProviding.currentApp()
  -> AppModel.classifyCurrentScreen(goal:app:)
  -> ScreenSnapshotProviding.captureJPEGData(...)
  -> FrameDeduplicator.shouldClassify(Data)
  -> ModelRouter.classifier(for:builtInClient:)
  -> VisionClassifying.classify(...)
  -> VisionClassifierResult
  -> ActivitySample
  -> ActivityWindowAnalyzer.summarize(samples:including:now:)
  -> ActivityWindowSummary.isSustainedDrift
  -> NudgeCoordinator.shouldNudge(...)
  -> DatabaseStore.saveActivitySample(...)
  -> reloadFromStore()
  -> Dashboard/MenuBar UI
```

Nudges should be based on sustained drift from `ActivityWindowAnalyzer`, not a single off-goal sample.

## Dashboard presentation flow

```text
ActivitySample.activitySummary / activityCategory / focusState
  -> DashboardCopy.activityLogEntries(from:)
  -> setup/unknown rows coalesced by category
  -> ActivityObservationRow
  -> Activity Log

Recent ActivitySample window
  -> Dashboard metric cards
```

`AppModel.reloadFromStore()` refreshes `activityWindowSummary` with `ActivityWindowAnalyzer`; SwiftUI views read that published summary instead of recomputing drift. The dashboard should present human-readable activity summaries and should not expose raw snake_case classifier categories as primary UI.

## Built-in model data flow

```text
SettingsView install button
  -> confirmation dialog
  -> AppModel.installBuiltInModel()
  -> BuiltInRuntimeController.installModel(...)
  -> Python venv and model files under Application Support

SettingsView delete button
  -> destructive confirmation dialog
  -> AppModel.deleteBuiltInModel()
  -> BuiltInRuntimeController.deleteModel(...)
  -> remove selected model directory when present

Screen classification with built-in runtime
  -> BuiltInRuntimeController.ensureRunning(...)
  -> builtin_gemma_sidecar.py
  -> BuiltInGemmaClient.classify(...)
  -> JSON VisionClassifierResult with short local activitySummary when context is clear
```

## External provider data flow

```text
SettingsView provider hookup
  -> AppSettings.modelSelection
  -> ModelRouter.classifier
  -> LocalVisionClient
  -> selected endpoint
```

For `cloudOptIn`, `ModelRouter` returns `CloudOptInBlockedClassifier` until the user explicitly enables screenshot egress.

## Persistence data flow

```text
GoalListView mission editor
  -> AppModel.saveMission(_:)
  -> DatabaseStore.saveGoal(_:)
  -> goals table

GoalListView remove mission
  -> confirmation alert
  -> AppModel.deleteMission(_:)
  -> DatabaseStore.deleteGoal(id:)
  -> goals table

ActivitySample
  -> DatabaseStore.saveActivitySample
  -> activity_samples table

AppSettings
  -> DatabaseStore.saveSettings
  -> settings table

Goal
  -> DatabaseStore.saveGoal
  -> goals table
```

Only metadata should flow into SQLite. Short activity summaries are enabled by default for local-first useful logs and can be disabled with `AppSettings.persistActivitySummaries`; `ActivitySummaryRedactor` removes obvious sensitive fragments before persistence.
