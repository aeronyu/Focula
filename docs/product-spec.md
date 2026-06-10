# Focula Product and Implementation Spec

Last updated: 2026-06-10

This document describes what Focula should do, what appears to be implemented today, and what is suspected to be incomplete or still needed. It is intended to be a working goal document for future product and engineering passes.

Checklist markers:

- `✅` Present in the current app/code path.
- `🟡` Present, but likely needs polish, validation, or completion.
- `⚠️` Likely needed or inconsistent with the current product direction.
- `🧭` Useful later, but not required for the current local-first focus coach.

## Product Summary

Focula is a local-first macOS focus coach. The app should help a user define missions, observe activity during configured focus windows, classify screen activity with a local vision model, and gently nudge the user back when recent activity drifts away from active missions.

The product should feel like a useful focus dashboard first and a playful mission coach second. The dashboard should avoid raw technical internals, expose only evidence-backed claims, and use progressive disclosure for model, privacy, and monitoring details.

## Recent Git History Read

The recent branch history suggests the app has moved from the original Watch My Back naming into the Focula product direction:

- `f23f02b` renamed the app and added multi-mission tracking.
- `b6dd6cf` and `386102c` refined mission detail layout and text fields.
- `8a3a8aa` bounded retained activity samples.
- `872dc69` added comparison of screenshots against recent frames.

Older history shows work on sustained drift analysis, dashboard layout, mission scheduling, local activity summaries, model provider settings, built-in Gemma runtime setup, Screen Recording permission guidance, and Semble/RTK developer workflow.

## Core User Jobs

### Mission Setup

- `✅` Users can create, edit, duplicate, activate/pause, and delete missions.
- `✅` A mission has a title, description, schedule, allowed apps, blocked apps, on-goal examples, off-goal examples, daily target minutes, and tracking enabled state.
- `✅` If all missions become inactive, the app forces at least one fallback mission active.
- `✅` If no mission exists, a starter mission is seeded.
- `🟡` Mission editing exists in the dashboard and goal list surfaces, but the app still has older `Goal` naming in code while UI copy uses mission/quest language.
- `⚠️` Multi-mission attribution is currently heuristic. Samples are attributed to the selected eligible mission, while classifier context includes all active eligible missions. Future work should make attribution explainable and accurate when several active missions overlap.

### Focus Tracking

- `✅` Tracking is paused by default.
- `✅` Users can resume/pause tracking from the toolbar, menu commands, and menu bar extra.
- `✅` Automatic sampling respects mission schedules unless the sample is manually triggered.
- `✅` The app stops timer-based sampling while the Mac is sleeping and resumes after wake if tracking was active.
- `✅` Users can trigger a manual sample with Scout Now.
- `✅` Sampling strategies include Balanced, Responsive, Quiet, and Manual only.
- `✅` Balanced mode exposes a configurable base interval.
- `🟡` Responsive and Quiet strategies exist at the settings/model level, but their real-world behavior should be verified against battery, CPU, and notification expectations.
- `⚠️` The app does not yet appear to expose a clear per-mission timeline of why a sample was attributed to a given mission.

### Screen Capture and Context

- `✅` The app uses ScreenCaptureKit to capture JPEG screenshots for classification.
- `✅` Screen Recording permission is checked before capture.
- `✅` If permission is missing, the app shows a custom permission guide and records an unknown classification state instead of crashing.
- `✅` The focused app name, bundle identifier, and focused window frame are captured.
- `✅` The display containing the focused window is treated as the primary screen.
- `✅` Other visible displays are passed as context.
- `✅` Recent focused frames are kept in memory for continuity and sent as context.
- `✅` Recent screenshot context is bounded to six frames and five minutes.
- `✅` Duplicate recent frames are skipped to avoid repeated classifier work.
- `🟡` Context images are kept in memory only, which matches the privacy model, but memory pressure should be monitored with long app sessions.
- `⚠️` It is not clear whether context frames should be cleared on pause, mission switch, display changes, or permission revocation.

### Classification

- `✅` Classifier output schema includes focus state, activity category, safe activity summary, confidence, evidence codes, and nudge suggestion.
- `✅` Focus states are `on_goal`, `maybe`, `off_goal`, and `unknown`.
- `✅` Activity categories are sanitized into short snake-case strings.
- `✅` Confidence is clamped to `0...1`.
- `✅` Evidence codes are trimmed and capped.
- `✅` Activity summaries are redacted before storage.
- `✅` The prompt instructs the model not to quote visible text, URLs, emails, chat participants, private names, document titles, or message contents.
- `🟡` The `nudgeSuggested` field is parsed but the app currently bases nudges on its own sustained-drift analyzer instead.
- `⚠️` Model telemetry exists in settings but does not appear to be actively updated for latency, parse failures, or success counts.
- `⚠️` Runtime-failure notification preference exists, but runtime failures appear to surface mainly as status text/last error rather than user notifications.

### Built-In Local Model Runtime

- `✅` Default provider is the built-in Gemma runtime.
- `✅` The app can install and run a private local Python/MLX sidecar.
- `✅` Built-in sidecar endpoint is `127.0.0.1:8765`.
- `✅` Built-in model options include Gemma 4 E2B 4-bit, 8-bit, BF16, and a tracked but not installable QAT mobile checkpoint.
- `✅` The 4-bit MLX model is the recommended default.
- `✅` Users can install, reinstall, test, pause, open the model folder, and delete selected installed model folders.
- `✅` Legacy built-in model IDs are normalized to the current recommended model.
- `🟡` The QAT mobile checkpoint is listed but intentionally not installable until the sidecar supports LiteRT or Transformers mobile tensors.
- `⚠️` The sidecar lifecycle should be verified for all shutdown paths, app relaunches, sleep/wake transitions, and failed installs.

### Optional Model Providers

- `✅` Provider types exist for built-in Gemma, oMLX, LM Studio, OpenAI-compatible local endpoints, and cloud opt-in.
- `✅` Settings exposes endpoint/model fields for external providers.
- `✅` Cloud classification is blocked unless the explicit screenshot egress opt-in is enabled.
- `🟡` Provider test behavior is minimal for external providers; it mainly records that the provider is configured and classification will run on the next sample.
- `⚠️` The app should eventually provide a real connection test for OpenAI-compatible providers and clearer failure diagnostics for invalid endpoint/model responses.

## Dashboard Requirements

### Overview

- `✅` Dashboard has segmented tabs for Overview, Mission Details, and Alerts.
- `✅` Overview shows the selected mission, tracking status, focus time, comebacks, XP, and activity timeline.
- `✅` The hero card adapts its icon/color to the latest focus state.
- `✅` The dashboard surfaces permission and last-error banners.
- `🟡` XP and levels are simple derived values. This is suitable for lightweight gamification, but should not imply more precision than the underlying samples support.
- `⚠️` Dashboard metrics should be audited for multi-mission correctness. Current daily stats aggregate all samples for the day, not obviously scoped to the selected mission.

### Mission Details

- `✅` Mission Details supports mission fields, quest hours, and scout hints.
- `✅` Users can choose allowed/blocked apps from installed application bundles.
- `✅` Text-field layout was recently polished for mission detail editing.
- `🟡` Mission Details edits appear to use a draft/save flow, but autosave timing and error behavior should be verified.
- `⚠️` The user may need clearer handling for overlapping mission schedules and duplicated app hints.

### Alerts

- `✅` Alert settings include sustained drift and runtime failure preferences.
- `✅` Sustained-drift nudges are notification-backed when enabled.
- `🟡` The dashboard Alerts tab should be checked for whether it provides useful alert history or mainly settings/status today.
- `⚠️` Runtime-failure alerts are a declared preference but need end-to-end notification behavior if not already wired.

## Privacy and Data Policy

- `✅` Raw screenshots are not stored in SQLite.
- `✅` OCR text and visible text are not stored.
- `✅` Stored samples contain metadata: app name, bundle id, goal id, focus state, activity category, optional redacted summary, confidence, duration, and nudge flag.
- `✅` Activity summaries can be disabled.
- `✅` Activity log visibility can be set to all activity or focus-only.
- `✅` Cloud screenshots are blocked by default.
- `✅` SQLite schema includes an assertion helper to detect screenshot-like storage fields.
- `🟡` Recent screenshot context exists in memory during runtime; this should remain bounded and cleared on lifecycle boundaries.
- `⚠️` The product should expose a concise privacy explanation in the app, not only in README/settings helper text.

## Storage and Retention

- `✅` Goals, settings, and activity samples persist in SQLite.
- `✅` Activity samples are pruned after 14 days while keeping up to 240 recent samples per goal.
- `✅` Recent samples are fetched with a limit of 240 for dashboard/window analysis.
- `✅` Activity log blocks compact consecutive similar samples.
- `🟡` Built-in model/runtime storage has moved to `~/Library/Application Support/Focula/BuiltInRuntime`.
- `⚠️` The main SQLite store still appears to use `~/Library/Application Support/Watch My Back/watch-my-back.sqlite`. This may be intentional for migration safety, but it conflicts with the Focula rename and should be decided explicitly.
- `⚠️` If the main database moves to `~/Library/Application Support/Focula`, migration should preserve existing goals, settings, and activity samples from the legacy path.

## Drift, Nudges, and Coaching

- `✅` A rolling activity window summarizes recent samples.
- `✅` The default analysis window is 20 minutes.
- `✅` Sustained drift requires at least 20 minutes of off-goal time and at least two off-goal samples.
- `✅` Nudges respect mission schedule, paused state, and cooldown.
- `✅` Recovery count increments when on-goal activity follows a nudged off-goal period.
- `✅` XP is derived from focused minutes plus recovery bonuses.
- `🟡` The current drift threshold equals the whole window duration, so drift may require nearly continuous off-goal time. This may be appropriate, but should be validated against real usage.
- `⚠️` The app should distinguish “off goal but acceptable for another active mission” from “side tracked” more explicitly in the UI and storage model.
- `⚠️` Coaching language should stay gentle and actionable, avoiding raw classifier confidence or overly punitive framing.

## Menu Bar and App Shell

- `✅` The app provides a normal dashboard window, Settings scene, app commands, and menu bar extra.
- `✅` Menu commands support pause/resume, sample now, Screen Recording guide, model testing, sidecar pause, built-in model selection, model folder opening, and provider switching.
- `✅` The menu bar icon changes with the current focus state.
- `🟡` The SwiftPM package, module, target, executable, resource bundle, app icon filenames, and app struct still use WatchMyBack naming internally.
- `⚠️` Internal naming may be acceptable short term, but a full product rename should decide whether module/executable/resource names should become Focula. Renaming these affects build scripts, tests, bundle internals, permissions, and existing user data.

## Build, Packaging, and Permissions

- `✅` `script/build_and_run.sh` builds, stages, signs, and opens `dist/Focula.app`.
- `✅` The bundle display name and bundle ID are Focula-oriented.
- `✅` The app includes `NSScreenCaptureUsageDescription`.
- `✅` The build script supports verify, debug, logs, and telemetry modes.
- `🟡` The staged app executable is still named `WatchMyBack`.
- `🟡` The temporary staging path still uses a `watch-my-back` prefix.
- `⚠️` The top-directory rename can leave stale SwiftPM module cache paths in `.build`; `swift package clean` fixes it. The README should mention this if renaming or moving the checkout remains common.

## Testing and Verification

- `✅` Test coverage exists for database persistence/migration/privacy, model providers, built-in runtime state, classifier parsing/redaction, activity services, display context selection, frame deduplication, sampling policy, focus schedule, rolling activity windows, nudges, and streak calculation.
- `✅` Current practical verification after the rename: `rtk ./script/build_and_run.sh --verify` and `rtk swift test`.
- `✅` Current UI verification: Computer Use confirmed toolbar controls, selected mission row text/icon contrast, and Activity Log text render in light mode.
- `✅` Current Scout Now verification: clicking Scout Now persisted a sample, reloaded the Activity Log, and showed a visible runtime-error setup row when the local model failed instead of hiding the row as resolved setup noise.
- `✅` Current log merge verification: repeated Scout Now runtime errors merge into one setup row with the latest timestamp; compactor tests cover split behavior for different activity summaries, apps, goals, and long gaps.
- `🟡` UI behavior is mostly verified by code review/manual run rather than automated UI tests.
- `⚠️` Add targeted tests for Focula data-path migration once the main database path decision is made.
- `⚠️` Add tests that prove runtime-failure notification preferences produce notifications or intentionally only affect status surfaces.

## Suggested Roadmap

### Slice 1: Finish Rename Consistency

- Decide whether internal names remain WatchMyBack or move fully to Focula.
- If moving fully, rename SwiftPM package/products/targets/modules, source folders, resource bundle names, executable name, icon names, build script variables, tests, and temp paths in one controlled branch.
- Resolve the main SQLite path: either document legacy path as intentional or migrate to `Application Support/Focula`.
- Add migration tests before changing stored data paths.

### Slice 2: Make Multi-Mission Tracking Explainable

- Add explicit sample attribution rules.
- Show which mission a sample counted toward in the activity timeline.
- Clarify how “any tracking goal can count as focused” affects classification and stats.
- Make selected-mission metrics scoped or clearly label them as all-mission daily metrics.

### Slice 3: Tighten Runtime and Provider Reliability

- Wire model telemetry updates for successes, parse failures, latency, and last verification time.
- Implement real external-provider test calls.
- Confirm runtime-failure notification behavior.
- Add clearer remediation text for sidecar install/test failures.

### Slice 4: Strengthen Privacy Lifecycle

- Clear in-memory screenshot context on pause, sleep, mission switch, provider switch, and permission revocation if that is the intended privacy contract.
- Add a concise in-app privacy summary that matches README language.
- Keep tests asserting no raw screenshots, OCR text, or visible text are persisted.

### Slice 5: Improve Coaching Quality

- Validate sustained-drift thresholds with real use.
- Refine status text and nudges so they are specific, gentle, and mission-centered.
- Avoid exposing raw classifier internals unless the user opens a diagnostic surface.
- Keep gamification lightweight and evidence-backed.

## Open Decisions

- Should the app’s internal executable/module names be renamed from WatchMyBack to Focula now, or deferred until after product behavior stabilizes?
- Should the main SQLite database move from `Application Support/Watch My Back` to `Application Support/Focula`?
- Should daily stats be global, selected-mission scoped, or both?
- Should recent screenshot context be retained across manual samples and mission changes, or cleared aggressively?
- Should classifier-provided `nudgeSuggested` influence nudges, or should nudges remain entirely deterministic from recent samples?
- Should runtime failure alerts be notifications, dashboard banners, menu bar indicators, or all three?
