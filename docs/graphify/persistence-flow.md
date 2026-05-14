# Persistence Flow

`DatabaseStore` owns SQLite persistence for Watch My Back.

## Storage location

The SQLite database lives under the user Application Support folder:

```text
~/Library/Application Support/Watch My Back/watch-my-back.sqlite
```

Built-in model files live under:

```text
~/Library/Application Support/Watch My Back/BuiltInRuntime/Models/
```

## Tables

### `goals`

Stores user goal configuration:

- id
- title
- description
- schedule_json
- allowed_apps_json
- blocked_apps_json
- on_goal_examples_json
- off_goal_examples_json
- daily_target_minutes
- is_active

### `activity_samples`

Stores classification metadata only:

- id
- timestamp
- app_name
- bundle_identifier
- goal_id
- focus_state
- activity_category
- confidence
- duration_seconds
- nudge_shown

### `settings`

Stores encoded `AppSettings`, including model/runtime configuration.

## Important functions

- `DatabaseStore.applicationStoreURL()`
- `DatabaseStore.saveGoal(_:)`
- `DatabaseStore.fetchGoals()`
- `DatabaseStore.saveActivitySample(_:)`
- `DatabaseStore.fetchRecentSamples(limit:)`
- `DatabaseStore.dailyStats(for:calendar:)`
- `DatabaseStore.saveSettings(_:)`
- `DatabaseStore.fetchSettings()`
- `DatabaseStore.schemaContainsScreenshotStorage()`

## Privacy invariant

`schemaContainsScreenshotStorage()` should remain false. If a future migration adds columns related to `screenshot`, `image_bytes`, `ocr_text`, or `visible_text`, stop and review the privacy model.

## Graphify audit questions

```text
Show all callers of DatabaseStore.saveActivitySample.
Show all SQL CREATE TABLE statements.
Show all paths from VisionClassifierResult to SQLite.
Show all paths from screenshot image data to SQLite.
Show the blast radius of changing ActivitySample.
```
