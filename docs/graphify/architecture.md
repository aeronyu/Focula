# Architecture

Watch My Back is a local-first macOS focus coach. The app samples the frontmost app and an ephemeral screenshot during focus windows, classifies the activity against the active goal, stores only metadata, and nudges when work drifts off mission.

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

It should not persist screenshot bytes, OCR text, visible text, model prompts, or image base64.

## UI surfaces

- `DashboardView`: mission status, metrics, recent samples, and goal rules.
- `GoalListView`: mission list and tracking status.
- `MenuBarContentView`: quick status and controls.
- `SettingsView`: model runtime, permissions, provider hookup, and sampling settings.
