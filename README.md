# Watch My Back

Watch My Back is a local-first macOS focus coach. It lets you define a few goals, watches frontmost app activity during focus hours, classifies ephemeral screenshots with a local OpenAI-compatible vision model, and nudges you when your work drifts off mission.

## Privacy model

- Screenshot frames are captured only for local classification.
- Raw screenshots, OCR text, and visible text are not stored in SQLite.
- Persisted records contain only metadata: app name, bundle id, goal id, focus state, category, confidence, duration, and whether a nudge was shown.
- Tracking is paused by default. Resume it from the dashboard or menu bar extra.

## Local model endpoint

Default endpoint:

```text
http://127.0.0.1:1234/v1/chat/completions
```

Use any local OpenAI-compatible vision server, such as LM Studio or another local runtime that accepts image messages.

## Build and run

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

Run tests:

```bash
swift test
```

The app may request Notification permission and Screen & System Audio Recording permission when you resume tracking or manually sample.
