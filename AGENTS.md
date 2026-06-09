Default: `Caveman` ultra. Off for detailed output / Notion.

Web/current/search/market/2nd opinion -> prefer `chatgpt-companion`; direct Codex web only for exact extraction/source verify.

Safari/Chrome/PWA -> text/DOM first, AX next, screenshots last.

File edits -> check git branch/status; no repo: ask before `git init`; `main`/`master`: branch; preserve user changes; run practical checks; commit done edits; ask before merge; summarize files/checks/risks.

Shell -> `rtk <cmd>` first. RTK hook block -> retry suggested `rtk` cmd.

@/Users/greenpoke/.agents/RTK.md

Before finishing any task, release memory by stopping processes started or clearly leaked by the work, regardless of project. Check for stale app runtimes, dev/test servers, Python sessions, Node sessions, MCP helpers, viewer servers, browser/computer-use helpers, and sidecar processes. Clean as you work when practical. Do not kill Apple launchd/XPC services such as `MTLCompilerService`, `SetStoreUpdateService`, or `distnoted` unless explicitly asked and they are confirmed to be using abnormal CPU or memory.

## Superpowers-inspired workflow

Follow the spirit of `obra/superpowers` for non-trivial product/code changes:

- Do not jump straight into broad coding when the product behavior is unclear.
- First clarify the target behavior and capture a short design/spec in an issue or doc.
- Break implementation into small, reviewable slices.
- Prefer simple, evidence-backed changes over large speculative systems.
- Use tests or practical verification before claiming a fix is done.
- Keep UI/design changes tied to the actual product goal, not just decoration.
- For the dashboard specifically: useful first, playful second; mission-centered; gentle coaching; no raw internals; progressive disclosure; lightweight gamification; evidence before claims.

Relevant design issue: #2 “Dashboard design spec: playful but useful focus coach”.

## Code Search

Use `semble search` to find code by describing what it does or naming a symbol/identifier, before falling back to grep for broad code discovery:

```bash
semble search "authentication flow"
semble search "save_pretrained" . --top-k 10
```

Use content modes when the target is not normal source code:

```bash
semble search "dashboard design spec" . --content docs
semble search "mcp server config" . --content config
semble search "model provider routing" . --content all
```

The index is built on first run, cached, and invalidated automatically when files change. Inspect full files only when the returned chunk does not give enough context. Use `semble find-related <file_path> <line> .` to discover code similar to a known result. Use `rg` when you need exhaustive literal matches or quick confirmation of an exact string.
