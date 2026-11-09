workspace_mode: solo

# HyundaiApp — Project Guide

HyundaiApp is a personal Hyundai Tucson PHEV companion. The repository contains:

- `backend/`: a Python 3.11 FastAPI service wrapping the Hyundai Bluelink Canada API. It provides authenticated vehicle status and commands, stores periodic snapshots in SQLite, and runs with Docker Compose on an OCI VM, published over HTTPS via Tailscale Funnel (Cloudflare Tunnel + Access is a documented alternative).
- `HyundaiApp/`: an iOS 26+ SwiftUI app. It pairs with the backend, stores credentials in Keychain, persists vehicle history with SwiftData in App Group `group.com.tomas.hyundaiapp`, and exposes the dashboard and remote controls.
- `HyundaiApp/HyundaiAppTests/`: deterministic networking and trip-building tests.
- `SESSIONS.md`: the ordered implementation roadmap. Completed entries are historical records; pending entries are the source of truth for remaining feature scope.

## Working agreement

Codex and Claude Code are both supported. The active assistant authors changes directly and may use its native planning or delegation tools when the work genuinely benefits from them. Neither runtime is required to hand code authoring to the other. Keep `AGENTS.md` and `CLAUDE.md` functionally aligned when project guidance changes.

For each task:

1. Read this guide, `SESSIONS.md`, and the files in scope.
2. Check `git status` and keep user changes intact.
3. Work on a task branch and follow the repository's solo-mode Git workflow.
4. Implement only the requested session or task. Split independent work when useful, but do not make delegation a prerequisite.
5. Run the relevant checks below and inspect the diff before committing.
6. Commit verified logical units with conventional commit messages. Never push `main`, deploy, open a PR, or cross a destructive Git safety rail without the authorization required by the global workflow.
7. When a roadmap session lands, record its completion and commit SHA in `SESSIONS.md` without rewriting older completion records.

Never commit secrets. Track only `backend/.env.example`; real Bluelink credentials and API keys belong in `backend/.env` on the machine running the service. Do not paste credentials into prompts, logs, tests, or documentation.

## Verification

Backend checks, run from `backend/`:

```bash
pytest
docker compose config
docker compose up --build
```

Use `docker compose up --build` as a smoke test when Docker and local credentials are available; do not treat unavailable credentials or infrastructure as a reason to weaken unit coverage.

iOS checks, run from the repository root:

```bash
xcodebuild test \
  -project HyundaiApp/HyundaiApp.xcodeproj \
  -scheme HyundaiApp \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

For widget or extension work, also build every affected target/scheme for an iOS 26 simulator. Prefer an installed iOS 26 runtime if the exact example destination is unavailable. The deployment target is iOS 26.0.

Documentation-only changes require:

```bash
git diff --check
```

Always inspect `git diff` or `git diff --cached` for scope before committing.

## Vehicle and battery safety

These constraints are invariants, not optional product choices:

- Default status reads use cached Bluelink state (`force=false`). A forced refresh wakes the vehicle and must be an explicit user action protected by rate limiting.
- Background collection must call `CarService.get_status(force=False)` only. It must never force-refresh the vehicle.
- Widgets read the shared SwiftData store only. They must not make network requests and must never call `/status?force=true`.
- Cached status queries in App Intents and other background surfaces read local shared data; they do not force-refresh.
- Vehicle commands must not silently retry after failure. Retrying lock, climate, or charging commands can repeatedly wake or hammer the 12V system. Surface the structured failure and let the user decide whether to retry.
- Preserve backend command and force-refresh rate limits. Do not bypass them in clients, tests, background jobs, or operational scripts.
- Do not expand polling frequency or introduce a new wake-up path without explicitly evaluating 12V battery impact.
- Keep command execution authenticated with the Bearer API key, and keep Bluelink credentials on the backend host.

## Architecture boundaries

- UI and features live under `HyundaiApp/HyundaiApp/Features/`; networking belongs under `Networking/`; persistent domain models belong under `Models/`.
- Reuse `CarAPIClient` and the shared SwiftData container rather than duplicating transport or storage.
- Keep analytics, trip detection, and suggestion logic in deterministic pure types. Views fetch data, pass it to those types, and render results; computation should not be embedded in SwiftData queries or UI code.
- Backend routes stay thin. Vehicle integration belongs in the car service, snapshot persistence/collection belongs in the snapshot layer, and configuration comes from environment-backed settings.
- The backend is single-user and single-writer. SQLite remains the intended snapshot store unless a future task explicitly changes that architecture.
- Respect session scope boundaries in `SESSIONS.md`, especially backend-only versus iOS-only work and the stated out-of-scope items.
