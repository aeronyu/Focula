Default: `Caveman` ultra. Off for detailed output / Notion.

Web/current/search/market/2nd opinion -> prefer `chatgpt-companion`; direct Codex web only for exact extraction/source verify.

Safari/Chrome/PWA -> text/DOM first, AX next, screenshots last.

File edits -> check git branch/status; no repo: ask before `git init`; `main`/`master`: branch; preserve user changes; run practical checks; commit done edits; ask before merge; summarize files/checks/risks.

Shell -> `rtk <cmd>` first. RTK hook block -> retry suggested `rtk` cmd.

@/Users/greenpoke/.codex/RTK.md

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, invoke the `skill` tool with `skill: "graphify"` before doing anything else.

Rules:
- ALWAYS read graphify-out/GRAPH_REPORT.md before reading any source files, running grep/glob searches, or answering codebase questions. The graph is your primary map of the codebase.
- IF graphify-out/wiki/index.md EXISTS, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
