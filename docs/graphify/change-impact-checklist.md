# Change Impact Checklist

Use this checklist before non-trivial edits. Prefer running Graphify from a full local checkout when available.

## Before editing

- Identify the user-facing behavior being changed.
- Use Graphify to find the relevant entry points, call paths, and downstream dependencies.
- Check whether the change touches privacy-sensitive data, persistence, runtime processes, settings, or notification behavior.
- For model/runtime work, trace from `SettingsView` and `AppModel` to `BuiltInRuntimeController`, `ModelRouter`, and the selected classifier.
- For storage work, trace all paths into `DatabaseStore` and model file directories.

## During editing

- Keep the edit surface small.
- Do not introduce persistence/logging of raw screenshots, image bytes, OCR text, visible text, or model prompts.
- Preserve explicit cloud opt-in before screenshots can leave the Mac.
- Keep built-in local classification on localhost.
- Prefer clear user confirmation before large downloads, destructive cleanup, or cloud egress.

## After editing

- Run `swift test` when available.
- Run `./script/build_and_run.sh --verify` when build/run behavior changed.
- Re-run Graphify queries for changed call paths if the edit affects architecture, privacy, persistence, runtime, or public APIs.
- Update `docs/graphify/*` summaries if architecture or data flow changed.

## Required Graphify questions by change type

### Settings/model management

```text
Show all paths from SettingsView install/delete/test buttons to BuiltInRuntimeController.
Show all state read by SettingsView around builtInModelStatus.
Show the blast radius of changing ModelRuntimeStatus.
```

### Privacy-sensitive capture/classification

```text
Show every path from captureJPEGData to persistence.
Show every path from imageData/base64 to files, logs, network, or SQLite.
Show all code that can send screenshot data outside localhost.
```

### Persistence

```text
Show all callers of DatabaseStore.saveSettings and saveActivitySample.
Show all SQL schemas and writes.
Show whether screenshot/image/OCR/visible text fields are introduced.
```

### Runtime/process management

```text
Show all callers of BuiltInRuntimeController.installModel, deleteModel, ensureRunning, and stop.
Show all Process launches and external commands.
Show all paths that mutate model storage folders.
```

## User-facing release note template

```text
Changed:
- ...

Verified:
- ...

Risks / follow-up:
- ...
```
