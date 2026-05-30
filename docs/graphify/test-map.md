# Test Map

This page maps important production code paths to test coverage. Refresh it after adding or moving tests.

## Existing test areas

- `Tests/WatchMyBackCoreTests/ActivityServicesTests.swift`
  - frontmost app / screen capture support behavior
  - frame deduplication behavior
  - nudge timing/cooldown behavior
- `Tests/WatchMyBackCoreTests/BuiltInModelRuntimeTests.swift`
  - model catalog aliases and storage folder names
  - built-in runtime status transitions
- `Tests/WatchMyBackCoreTests/ModelProviderTests.swift`
  - provider selection and defaults
  - cloud opt-in blocking
  - runtime detector status behavior
- Other core tests should cover `Models.swift`, `DatabaseStore.swift`, and `LocalVisionClient.swift` parsing/serialization behavior.
- `Tests/WatchMyBackCoreTests/ActivityWindowAnalyzerTests.swift`
  - rolling alignment/drift summaries
  - candidate sample inclusion before persistence

## High-value test targets

### Focus schedule and stats

- `FocusSchedule.contains(_:calendar:)`
- `DailyStats.focusRatio`
- `StreakCalculator.dayCounts(stats:targetMinutes:)`
- `ActivityWindowAnalyzer.summarize(samples:including:now:)`

### Model routing

- `ModelRouter.classifier(for:builtInClient:)`
- `CloudOptInBlockedClassifier.classify(...)`
- `BuiltInGemmaClient.notReadyFallback()`
- `LocalVisionClient.parseChatCompletionResponse(_:)`

### Persistence

- `DatabaseStore.saveActivitySample(_:)`
- `DatabaseStore.fetchRecentSamples(limit:)`
- `DatabaseStore.dailyStats(for:calendar:)`
- `DatabaseStore.schemaContainsScreenshotStorage()`

### Settings/model management UI behavior

These are app-level behaviors and may need UI tests or targeted view-model tests:

- install button shows confirmation before download
- delete button remains available for cleanup of partial/missing installs
- delete button shows destructive confirmation
- delete action calls `AppModel.deleteBuiltInModel()`
- install action calls `AppModel.installBuiltInModel()` only after confirmation

## Graphify test queries

```text
Show all production symbols referenced by WatchMyBackCoreTests.
Show all public methods in WatchMyBackCore without test references.
Show test coverage around ModelRouter.classifier.
Show test coverage around DatabaseStore.schemaContainsScreenshotStorage.
Show all paths from SettingsView install/delete buttons to BuiltInRuntimeController.
```
