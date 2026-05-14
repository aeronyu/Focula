# Module Map

This is a lightweight Graphify-friendly map of the Watch My Back codebase. It should be refreshed after large architecture changes.

## Targets

- `WatchMyBackCore`: shared domain models, model runtime abstractions, persistence, classification clients, and activity services.
- `WatchMyBack`: macOS app shell, app state, SwiftUI views, menu bar UI, settings UI, built-in runtime controller, and permission presentation.
- `WatchMyBackCoreTests`: unit tests for core model/runtime/activity behavior.

## High-level modules

```text
Package.swift
├─ Sources/WatchMyBackCore
│  ├─ Models.swift
│  ├─ DatabaseStore.swift
│  ├─ ActivityServices.swift
│  ├─ LocalVisionClient.swift
│  ├─ BuiltInGemmaClient.swift
│  └─ ModelRuntime.swift
├─ Sources/WatchMyBack
│  ├─ App
│  ├─ Views
│  ├─ Services
│  └─ Resources/Runtime
└─ Tests/WatchMyBackCoreTests
```

## Important graph nodes

- `AppModel`: central app state and orchestration layer.
- `SettingsView`: runtime/model selection, install/delete/test controls, provider hookup, sampling settings.
- `BuiltInRuntimeController`: built-in Python sidecar lifecycle, model install/delete, health check.
- `ModelRuntimeDetector`: checks external runtime availability and summarizes statuses.
- `ModelRouter`: chooses the correct classifier for the selected provider.
- `LocalVisionClient`: OpenAI-compatible local/cloud endpoint client.
- `BuiltInGemmaClient`: client for the local built-in sidecar.
- `DatabaseStore`: SQLite persistence for goals, settings, and activity sample metadata.
- `ScreenCaptureKitSnapshotProvider`: captures ephemeral screenshot bytes for classification.
- `NotificationNudgePresenter`: sends local nudges.

## Graphify use

Useful first queries:

```text
Explain AppModel.
Show the path from AppModel.sampleNow to DatabaseStore.saveActivitySample.
Show the path from ScreenSnapshotProviding.captureJPEGData to ModelRouter.classifier.
Show all callers of BuiltInRuntimeController.installModel and deleteModel.
Show the blast radius of changing ActivitySample.
```