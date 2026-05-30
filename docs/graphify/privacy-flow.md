# Privacy Flow

Watch My Back is local-first. This page documents privacy-sensitive paths to check with Graphify before edits.

## Sensitive inputs

- screenshot JPEG bytes from `ScreenSnapshotProviding.captureJPEGData`
- image base64 sent to model clients
- visible screen text that may be present inside screenshots
- model prompt/request payloads
- app/window context

## Required privacy boundary

Do not persist or log:

- raw screenshots
- OCR text
- visible screen text
- image bytes/base64
- model prompt contents
- sensitive app/window content

Allowed persisted data:

- timestamp
- app name
- bundle identifier
- goal id
- focus state
- activity category
- confidence
- duration seconds
- nudge shown flag
- redacted activity summary, only when the user enables summary storage
- user model/settings metadata

## Primary path to audit

```text
ScreenCaptureKitSnapshotProvider.captureJPEGData
  -> AppModel.classifyCurrentScreen
  -> FrameDeduplicator.shouldClassify
  -> BuiltInGemmaClient or LocalVisionClient
  -> VisionClassifierResult
  -> ActivitySample metadata, with optional redacted summary gated by AppSettings.persistActivitySummaries
  -> DatabaseStore.saveActivitySample
```

## Built-in runtime privacy behavior

For built-in Gemma, screenshots are sent to `builtin_gemma_sidecar.py` on localhost. The sidecar should return only structured `VisionClassifierResult` JSON and should not write raw image content to disk. Short activity summaries must be generic and are redacted again in Swift before any persistence.

## Cloud opt-in guardrail

`cloudOptIn` must stay blocked unless `cloudClassificationAllowed` is true. Any future cloud provider work must preserve this explicit opt-in boundary.

## Graphify audit questions

```text
Show every path from captureJPEGData to DatabaseStore.
Show every path from imageData/base64 to file writes or logs.
Show every path from LocalVisionClient.makeRequestBody to persistence.
Show all code that can send screenshots outside localhost.
Show all code that writes to SQLite.
Show all code that opens external URLs or starts external processes.
```
