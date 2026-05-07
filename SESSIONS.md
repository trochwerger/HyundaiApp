# Session Breakdown — Hyundai Companion App

Each session below is self-contained. Start a fresh Claude Code session, paste the prompt verbatim, and it will have enough context to proceed without seeing prior chats. The approved plan lives at `~/.claude/plans/i-want-to-build-sparkling-zebra.md` — every session prompt references it.

Sessions are ordered. Do not start a later one until the prior one's "Done when" checks pass.

## How sessions run now (orchestrator mode)

The global `~/.claude/CLAUDE.md` puts Claude Code in **orchestrator mode**: Claude does not author code directly — all code edits are delegated to Codex CLI via the `codex-orchestrator` skill. Each session prompt below is written for the orchestrator to read and act on; the orchestrator decides whether to invoke `session-splitter` (parallel sub-units) or delegate the whole session to Codex in one or more passes, then verifies and commits per the global git workflow.

To run sessions sequentially without supervision, use the `session-runner` skill — it consumes this file, picks the first **Pending** session, dispatches a subagent, and stops between sessions for review.

Status legend: **Done** ✅ / **Pending** ⏳ / **Blocked** 🚫

---

## Session 1 — Backend scaffold & Canada login ✅ Done

**Status:** Done — commit `207d1ef` ("Session 1 + 2: backend MVP with full command set and Cloudflare Tunnel"). Backend scaffolded under `backend/`, Bluelink Canada login flow documented in `backend/README.md`, pytest green.

---

## Session 2 — Remote commands + Cloudflare Tunnel ✅ Done

**Status:** Done — landed alongside Session 1 in commit `207d1ef`. Full command set, per-IP rate limiting, Cloudflare Tunnel walkthrough in `backend/README.md`.

---

## Session 3 — iOS project scaffold + pairing + dashboard ✅ Done

**Status:** Done — commit `efb2d84` ("Session 3: iOS MVP — Xcode project scaffold, pairing, dashboard, lock/unlock"). Xcode project under `HyundaiApp/`, Keychain-backed pairing, dashboard, lock/unlock all wired.

---

## Session 4 — Full remote controls + SwiftData snapshots ✅ Done

**Status:** Done — final commit `ad58eec` ("feat: SwiftData snapshots, trip builder, debug screen") plus `5fd240d` ("feat: full remote command set in iOS (climate, charging)") on `task/session-4-swiftdata-snapshots`, FF-merged to `main`. All 6 commands wired (lock, unlock, climate start/stop, charge start/stop). Snapshots persist to a shared App Group SwiftData container (`group.com.tomas.hyundaiapp`). Deterministic `TripBuilder` covers ignition + odometer fallback; 13 unit tests pass alongside the 7 networking tests (`xcodebuild test` green on iPhone 15 / iOS 17.5). Debug screen lives behind a Settings toggle.

**Goal:** All commands wired up in iOS; every `/status` read writes a `StatusSnapshot` to SwiftData. Trip detection stubbed.

**Prompt to paste:**
```
Read ~/.claude/plans/i-want-to-build-sparkling-zebra.md and /Users/tomaspc/Documents/Code/Car/HyundaiApp/CLAUDE.md before starting. The repo is in orchestrator mode — you (Claude) coordinate and verify; all code authoring is delegated to Codex via the `codex-orchestrator` skill.

Pre-flight: run `git status` in /Users/tomaspc/Documents/Code/Car/HyundaiApp. There is in-progress Session 4 work uncommitted on `main` (SwiftData models, TripBuilder + tests, expanded controls, debug screen). Per the global git workflow: move that work onto a task branch (e.g. `task/session-4-swiftdata-snapshots`) before continuing — do not commit Session 4 work directly to `main`. Stash → branch → pop, or `git switch -c <branch>` if the working tree is unstaged.

Session 4 scope: Phases 3 and 4 of the plan. Extend the existing iOS app at /Users/tomaspc/Documents/Code/Car/HyundaiApp/HyundaiApp/. Do not touch the backend.

Required deliverables (audit the in-progress work first; only fill gaps):
- Features/Controls: full command UI — remote start (with temp + duration + defrost toggle), remote stop, charge start, charge stop. Each shows loading state, success toast, and surfaces the backend's structured error on failure.
- Models/ (SwiftData):
  - StatusSnapshot (timestamp, odometer, fuelPercent, evBatteryPercent, evRangeKm, fuelRangeKm, isLocked, isCharging, latitude, longitude, rawJSON).
  - Trip (startAt, endAt, startOdometer, endOdometer, startFuel, endFuel, startSoc, endSoc, estimatedKwh, estimatedLiters, distanceKm, mode: enum evOnly/hybrid/iceOnly/mixed/unknown).
  - ChargeSession (startAt, endAt, startSoc, endSoc, estimatedKwh).
- Persistence wiring: every successful /status response is inserted as a StatusSnapshot in a shared SwiftData container (use the App Group so widgets can read it later).
- Trip detection: a deterministic, pure-function "trip builder" that takes an ordered array of StatusSnapshots and emits Trips. Detect trips by odometer deltas between consecutive snapshots when ignition state is not reliably exposed (check the upstream library for ignition fields first; if present, use them).
- Unit tests for the trip builder against canned snapshot sequences (no network, no SwiftData).
- A simple debug screen listing the last 100 snapshots and derived trips (dev-only, gated behind a build flag or Settings toggle).

Out of scope: charts/analytics UI, widgets, App Intents. Those are later sessions.

If audit shows the in-progress work is mostly done, delegate a "finish + verify" pass to Codex. If gaps are independent (e.g. command UI vs. trip-builder polishing), invoke `session-splitter`. Verify with `xcodebuild test` against the iOS 17 simulator before committing.

Done when: all commands work end-to-end, snapshots are persisting (visible in the debug screen), trip builder unit tests pass, and `xcodebuild test` is green.
```

**Done when:** debug screen shows growing snapshot list and correctly detected trips across a few real drives.

---

## Session 4.5 — Backend snapshot collector + Oracle Cloud migration ⏳ Pending

**Goal:** Backend polls Bluelink cached state every 15 min and stores snapshots to SQLite so data accumulates 24/7. Migrate hosting from local Mac to an Oracle Cloud Always Free ARM VM so the backend runs independently of the dev machine. Add a `/snapshots` endpoint so the iOS app can backfill its SwiftData store on launch.

**Prompt to paste:**
```
Read ~/.claude/plans/i-want-to-build-sparkling-zebra.md and /Users/tomaspc/Documents/Code/Car/HyundaiApp/CLAUDE.md before starting. Orchestrator mode — delegate code authoring to Codex via `codex-orchestrator`. Branch per the global git workflow.

Session 4.5 scope: extend the backend at /Users/tomaspc/Documents/Code/Car/HyundaiApp/backend/ with automated snapshot collection and prepare for Oracle Cloud deployment. Do not change the iOS app in this session.

Context: the backend currently holds vehicle state in memory only — no persistence. `force=false` calls `update_all_vehicles_with_cached_state()` which pulls Bluelink's server-side cache (does NOT wake the car — no 12V battery risk). `force=true` calls `force_refresh_all_vehicles_states()` which pings the car (battery risk, rate-limited). The collector must only use `force=false`.

## Deliverables

### 1. Snapshot collector (backend code)

Add an asyncio background task that runs during the FastAPI lifespan:
- Every N seconds (env var `SNAPSHOT_INTERVAL_SECONDS`, default 900 = 15 min), call `CarService.get_status(force=False)`.
- Persist the full serialized status dict as a JSON row in a local SQLite database at a configurable path (env var `SNAPSHOT_DB_PATH`, default `/data/snapshots.db`).
- Table schema: `id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT NOT NULL, vehicle_id TEXT, status_json TEXT NOT NULL, odometer_km REAL, fuel_percent INTEGER, ev_battery_percent INTEGER, is_locked INTEGER, is_charging INTEGER, engine_is_running INTEGER, latitude REAL, longitude REAL`.
- Extract the indexed columns from the status dict for efficient querying; store the full JSON blob for forward compatibility.
- Dedup: skip insert if the most recent row has the same `odometer_km` AND same `ev_battery_percent` AND same `fuel_percent` AND same `is_locked` — nothing changed, don't waste storage.
- Log each collection cycle: "snapshot collected" or "snapshot skipped (no change)".
- Graceful: if Bluelink is unreachable or token expired, log the error and retry next cycle. Never crash the collector loop.

### 2. `/snapshots` endpoint

- `GET /snapshots?from=<ISO datetime>&to=<ISO datetime>&limit=1000` — returns snapshots in ascending timestamp order. Requires Bearer auth (same API key as all other endpoints). Response: `{"snapshots": [{"timestamp": "...", "status": {...}, ...}]}` where each entry includes the indexed columns plus the full `status` object parsed from `status_json`.
- `GET /snapshots/latest` — returns the single most recent snapshot. Useful for quick widget-style checks.
- Pagination: respect `limit` (max 5000, default 1000). If more rows exist, include `"has_more": true` in the response.

### 3. New env vars + config

Add to `Settings` (pydantic-settings):
- `SNAPSHOT_INTERVAL_SECONDS: int = 900`
- `SNAPSHOT_DB_PATH: str = "/data/snapshots.db"` (Docker volume mount point)

Add to `.env.example`.

### 4. Docker changes

- Add a named volume in `docker-compose.yml` for SQLite persistence: `snapshot-data:/data`.
- Ensure the `appuser` in the Dockerfile has write access to `/data`.
- Verify `docker compose down && docker compose up` preserves the SQLite file across restarts.

### 5. Tests

- Unit test the snapshot collector logic: mock `CarService.get_status`, verify rows are inserted, verify dedup skips identical state.
- Unit test `/snapshots` endpoint: from/to filtering, limit, latest.
- All existing tests must keep passing.

### 6. Oracle Cloud migration guide

Add a section to `backend/README.md` titled "Deploy to Oracle Cloud Always Free":
- Step-by-step: create an OCI account, provision an ARM Ampere A1 instance (4 OCPU, 24GB RAM, Ubuntu), open port 22 in the security list.
- SSH in, install Docker + Docker Compose.
- Clone/copy the repo, set up `.env` with Bluelink credentials + API key.
- Run the OTP login helper (same as local — see existing README section).
- `docker compose up -d`.
- Repoint the existing Cloudflare Tunnel to the VM's internal IP (update `config.yml` `url` to point to the VM, or create a new tunnel on the VM and update the DNS record).
- Verify: `curl -H "Authorization: Bearer $API_KEY" https://<hostname>/status` returns data.
- Note: the VM is always on, so the snapshot collector runs 24/7 and data accumulates automatically.
- Note: the free tier is permanent (not a trial). 200GB boot volume, 4 ARM cores, 24GB RAM — massively overkill for this use case.

### 7. .env.example update

Add the two new env vars with comments explaining their purpose.

## Constraints

- The collector must ONLY call `force=false` — never `force=true`. This is the 12V battery safety rule.
- SQLite is the right choice: single-user, single-writer, no external DB dependency, trivial Docker volume mount.
- Do not add heavy dependencies. `aiosqlite` is acceptable if you want async SQLite; stdlib `sqlite3` in a `to_thread` wrapper is also fine.
- Do not change the iOS app. iOS will consume `/snapshots` in a future session.

Done when: `pytest` passes (including new snapshot collector + endpoint tests), `docker compose up` starts the collector loop (visible in logs), `/snapshots` returns data after a few cycles, README has the full OCI migration guide, and `.env.example` is updated.
```

**Done when:** backend is collecting snapshots every 15 min, `/snapshots` returns accumulated data, README documents the OCI migration path, all tests pass.

---

## Session 5 — Analytics UI (Swift Charts) ⏳ Pending

**Goal:** Efficiency trends, gas savings, mode-usage breakdown. Pure read-only over existing SwiftData.

**Prompt to paste:**
```
Read ~/.claude/plans/i-want-to-build-sparkling-zebra.md and /Users/tomaspc/Documents/Code/Car/HyundaiApp/CLAUDE.md before starting. Orchestrator mode — delegate code authoring to Codex via `codex-orchestrator`. Branch per the global git workflow.

Session 5 scope: Phase 5 of the plan. Extend the iOS app at /Users/tomaspc/Documents/Code/Car/HyundaiApp/HyundaiApp/. Read-only over the SwiftData store created in Session 4. Do not change the backend or the networking layer.

Add Features/Analytics/ with Swift Charts:
- EfficiencyTrendView — line chart of L/100km and kWh/100km per week over the last 90 days.
- GasSavingsView — bar chart of estimated $ saved by EV km per month. Gas price is a user setting (Settings > Analytics, default $1.60/L CAD, editable).
- ModeBreakdownView — stacked area or pie of total km split by Trip.mode over a selectable range (week/month/all-time).
- AnalyticsHomeView — entry point linking all three, plus a "key stats" header (lifetime km, lifetime $ saved, avg combined efficiency).
- A pure AnalyticsEngine type that takes [Trip] + gasPrice and returns the values needed by each view. Fully unit tested with deterministic inputs. No view should query SwiftData directly for computation — views fetch Trips, pass to AnalyticsEngine, render.

Out of scope: widgets, App Intents, mode-suggestion engine. Those are later sessions.

The AnalyticsEngine + tests are independent of the chart views — consider `session-splitter` if both can land in parallel. Verify with `xcodebuild test`.

Done when: analytics screens render against the real accumulated data, AnalyticsEngine unit tests pass, gas price edits in Settings update the charts live.
```

**Done when:** all three charts look right against your real driving data.

---

## Session 6 — Widgets (Lock Screen + Home Screen) ⏳ Pending

**Goal:** Widgets reading the shared SwiftData store — no network, no force-refresh.

**Prompt to paste:**
```
Read ~/.claude/plans/i-want-to-build-sparkling-zebra.md, especially the "Widgets & Shortcuts" and "Polling strategy" sections, plus /Users/tomaspc/Documents/Code/Car/HyundaiApp/CLAUDE.md. Orchestrator mode — delegate code authoring to Codex via `codex-orchestrator`. Branch per the global git workflow.

Session 6 scope: Phase 6. Add a HyundaiWidget extension target to the existing Xcode project at /Users/tomaspc/Documents/Code/Car/HyundaiApp/HyundaiApp/.

Widgets must read from the App Group shared SwiftData store written by the main app. Widgets MUST NOT call /status?force=true — battery-safety rule from the plan. They read the latest StatusSnapshot and display "updated Xm ago".

Add widget families:
- accessoryCircular (Lock Screen): EV battery % ring.
- accessoryRectangular (Lock Screen): battery %, fuel %, lock state on one line.
- systemSmall: battery + fuel + range.
- systemMedium: small content + lock state + last-updated timestamp + charging indicator.

TimelineProvider refreshes every 15 minutes from the shared store (no network). Placeholder + snapshot entries handled.

Include snapshot previews for every size/family for App Store screenshots later.

Out of scope: App Intents, mode-suggestion engine. Next sessions.

Verify with `xcodebuild` for both the app and widget extension targets.

Done when: widgets install on a physical device, show correct data from the shared store, and do not trigger any network calls.
```

**Done when:** Lock Screen widget shows real car data on your phone.

---

## Session 7 — App Intents + Siri Shortcuts ⏳ Pending

**Goal:** Remote commands and status queries via Siri / Shortcuts app / Home Screen shortcut icons.

**Prompt to paste:**
```
Read ~/.claude/plans/i-want-to-build-sparkling-zebra.md and /Users/tomaspc/Documents/Code/Car/HyundaiApp/CLAUDE.md. Orchestrator mode — delegate code authoring to Codex via `codex-orchestrator`. Branch per the global git workflow.

Session 7 scope: Phase 7. Extend the iOS app at /Users/tomaspc/Documents/Code/Car/HyundaiApp/HyundaiApp/ with App Intents.

Add Intents/VehicleIntents.swift with:
- LockCarIntent, UnlockCarIntent — AppIntent performing the command via CarAPIClient; returns success/failure dialog.
- StartClimateIntent — takes parameters: temperature (Int, default 22), defrost (Bool, default false), duration (Int minutes, default 10).
- StopClimateIntent.
- StartChargingIntent, StopChargingIntent.
- CheckBatteryIntent — returns a spoken/written summary like "Battery 64 percent, range 42 kilometers, fuel 80 percent." Reads from the SwiftData store (cached, no force-refresh).

All intents:
- Implement AppShortcutsProvider so they appear in Spotlight and the Shortcuts app without user setup.
- Conform to ProvidesDialog for Siri responses.
- Include short, natural-sounding invocation phrases.
- Reuse the existing CarAPIClient and SwiftData store; do not duplicate networking.

Unit-test intent bodies by mocking CarAPIClient. Verify with `xcodebuild test`.

Out of scope: mode-suggestion engine.

Done when: "Hey Siri, lock the Tucson" (or your chosen phrase) works end-to-end against the real car, and all intents are usable from the Shortcuts app as Home Screen icons.
```

**Done when:** Siri executes each intent on your phone.

---

## Session 8 — Mode-suggestion engine ⏳ Pending

**Goal:** Weekly insight card: "you'd have saved ~$12 driving trip X in EV mode." Final polish.

**Prompt to paste:**
```
Read ~/.claude/plans/i-want-to-build-sparkling-zebra.md, especially the "Analytics engine" section, plus /Users/tomaspc/Documents/Code/Car/HyundaiApp/CLAUDE.md. Orchestrator mode — delegate code authoring to Codex via `codex-orchestrator`. Branch per the global git workflow.

Session 8 scope: Phase 8. Extend the iOS app at /Users/tomaspc/Documents/Code/Car/HyundaiApp/HyundaiApp/. Requires weeks of Trip data accumulated from prior sessions.

Add Features/Insights/:
- A ModeSuggestionEngine (pure type, heavily unit-tested) that takes [Trip] and produces weekly insights:
  - Per recent trip, estimate what it would have cost / emitted / saved in each mode (EV-only, Hybrid, Auto) given observed distance, avg speed bucket, and battery state at trip start. Use simple heuristics documented inline: EV-only feasible when tripKm <= 0.9 * observed EV range and avg speed <= 100 km/h, etc.
  - Cluster trips by (time-of-day bucket, day-of-week, distance bucket, avg-speed bucket) using a simple k-means or bucket-count approach — no ML dependencies.
  - Emit 1-3 Insight objects per week: "Your Tuesday morning commute (avg 18 km, city speeds) would save ~$X/week in EV-only mode."
- InsightsHomeView showing the current week's insights + a history list.
- Insights are recomputed on app launch and after each new Trip is finalized. Cache the week's result in SwiftData so the UI is instant.
- Unit tests with canned Trip fixtures covering: all-EV-feasible week, mixed week, highway-heavy week, insufficient-data week.

Final polish passes:
- App icon + launch screen (ask me for assets; use a placeholder if I don't provide).
- Review all error messages for the non-technical reader.
- Verify no Info.plist permission strings are missing (Location if we use it, Siri, etc.).

The pure ModeSuggestionEngine + tests are an obvious split candidate vs. the InsightsHomeView UI — invoke `session-splitter` if both can land in parallel.

Done when: insights render against real accumulated data, unit tests pass, and the app feels ready for daily use.
```

**Done when:** insights feel useful, not noise.

---

## Cross-session reminders

- **Never paste credentials in chat.** They go into `backend/.env` directly on your machine.
- **Keep SESSIONS.md and the plan file in sync** if scope shifts mid-project — update them before starting the next session so future-you isn't misled by stale instructions.
- **Mark sessions Done with the commit SHA** as soon as they land, so `session-runner` skips them on the next sweep.
- **If a session balloons,** stop and split it. The whole point of this breakdown is protecting context. Better to add Session 4a/4b than blow past a reasonable scope.
