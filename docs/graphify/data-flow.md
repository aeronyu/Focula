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
  -> NudgeCoordinator.shouldNudge(...)
  -> ActivitySample
  -> DatabaseStore.saveActivitySample(...)
  -> reloadFromStore()
  -> Dashboard/MenuBar UI
```

## Built-in model data flow

```text
SettingsView install button
  -> confirmation dialog
  -> AppModel.installBuiltInModel()
  -> BuiltInRuntimeController.installModel(...)
  -> Python venv and model files under Application Support

Screen classification with built-in runtime
  -> BuiltInRuntimeController.ensureRunning(...)
  -> builtin_gemma_sidecar.py
  -> BuiltInGemmaClient.classify(...)
  -> JSON VisionClassifierResult
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

Only metadata should flow into SQLite.
