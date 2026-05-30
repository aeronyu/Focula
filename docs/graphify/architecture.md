# Architecture

Watch My Back is a local-first macOS focus coach. The app samples the frontmost app and an ephemeral screenshot during focus windows, classifies the activity against the active goal, stores only safe metadata, and nudges when work drifts off mission.

## Runtime shape

```text
SwiftUI App / MenuBarExtra / Settings
        |
        v
AppModel
        |
        +-- DatabaseStore                SQLite metadata only
        +-- FrontmostAppProviding        active app snapshot
        +-- ScreenSnapshotProviding      ephemeral screenshot bytes
        +-- ModelRouter                  classifier selection
        +-- BuiltInRuntimeController     local Gemma sidecar lifecycle
        +-- NudgeCoordinator             cooldown and nudge decision
        +-- NotificationNudgePresenter   local notification
```

## Product model

The app should feel like a mission/activity coach, not an app allowlist/blocklist tool.

- Goals represent natural-language intent, such as interview prep or a project milestone.
- Each goal has its own focus schedule.
- The dashboard presents mission alignment, recent activity, drift/recovery status, and next steps.
- Raw model category strings and internal rules should not be primary UI.
- Allowed/blocked apps and examples can remain configuration hints, but the dashboard should focus on interpreted activity.

## Provider architecture

`ModelSelection` chooses one of:

- `builtInGemma`: default local sidecar path.
- `oMLX`: external local runtime when detected/configured.
- `lmStudio`: external local OpenAI-compatible runtime.
- `openAICompatible`: manual local endpoint.
- `cloudOptIn`: blocked until explicit screenshot opt-in.

`ModelRouter.classifier(for:builtInClient:)` creates the classifier used by `AppModel.classifyCurrentScreen`.

## Built-in Gemma lifecycle

```text
SettingsView
  -> install confirmation
  -> AppModel.installBuiltInModel
  -> BuiltInRuntimeController.installModel
  -> private Python venv
  -> huggingface_hub snapshot_download
  -> local model directory

SettingsView
  -> AppModel.testSelectedModel
  -> BuiltInRuntimeController.ensureRunning
  -> builtin_gemma_sidecar.py
  -> BuiltInGemmaClient
```

## Persistence boundary

`DatabaseStore` persists:

- goals
- settings
- activity sample metadata
- focus state/category/confidence/duration/nudge flags
- optional redacted activity summaries after explicit user opt-in

It should not persist screenshot bytes, OCR text, visible text, model prompts, or image base64.

## UI surfaces

- `DashboardView`: mission status, metrics, useful recent activity, coalesced setup/unknown log rows, focus window, recent alignment, and next-step guidance.
- `AppModel.activityWindowSummary`: shared rolling drift summary used by nudges and dashboard presentation.
- `GoalListView`: mission list, active mission selection, and focused mission editor for intent, schedule, target, and scout hints.
- `MenuBarContentView`: quick status and controls.
- `SettingsView`: model runtime, install/delete confirmations, permissions, provider hookup, and sampling settings.
