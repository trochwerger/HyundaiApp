workspace_mode: solo

# HyundaiApp — Project Context

Personal Hyundai Tucson PHEV companion app. Backend (FastAPI, Python) under `backend/`, iOS app (SwiftUI, iOS 17+) under `HyundaiApp/`. Approved plan: `~/.claude/plans/i-want-to-build-sparkling-zebra.md`. Multi-session build broken down in [SESSIONS.md](SESSIONS.md).

## Workflow

This repo follows the global orchestrator-mode rules in `~/.claude/CLAUDE.md`:

- Claude Code is the orchestrator and does **not** author code directly. All code authoring/edits go through Codex CLI via the `codex-orchestrator` skill.
- Each session in `SESSIONS.md` is one independent unit. Sessions are run sequentially via the `session-runner` skill, or kicked off manually by pasting the session prompt into a fresh Claude Code session.
- Per-session: orchestrator reads files → plans → invokes `session-splitter` if the work is independently parallelizable, otherwise delegates the whole unit to Codex → verifies (tests, lint, build) → commits per the global git workflow → moves on.
- Solo-mode git rules apply: task branches, auto-push of task branch once upstream exists, FF-merge to `main` after green, but **never auto-push `main`** (deploy-trigger surface — needs explicit user ask).

## Verification expectations

- Backend: `pytest` in `backend/` must pass; `docker compose up` must start cleanly.
- iOS: build succeeds for iOS 17 simulator; unit tests pass under `HyundaiAppTests`.

## Out-of-scope reminders

- Never commit secrets. Only `.env.example` is tracked. Real credentials live in `backend/.env` on the user's machine.
- Commands to the car must not silently retry on failure (12V battery hammering risk — see plan).
- Widgets MUST NOT call `/status?force=true` (same battery rule).
