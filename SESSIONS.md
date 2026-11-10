# Session Breakdown — Hyundai Companion App

Each pending session below is self-contained. Start a fresh Codex or Claude Code session from the repository root and use the prompt as the task brief. Read `AGENTS.md` (Codex) or `CLAUDE.md` (Claude Code) first; both carry the same architecture, workflow, verification, and vehicle-safety rules.

Sessions are ordered. Do not start a later one until the prior one's "Done when" checks pass.

## How to run sessions

The active assistant authors the work directly and may use its native planning or delegation tools when useful. Codex and Claude Code are both valid executors; neither is required to invoke the other. Before editing, check repository state and work on a task branch. Preserve session scope, run the stated checks, inspect the diff, and commit only verified work per the global Git workflow.

If the active runtime provides a compatible session runner, it may consume this file and select the first **Pending** session. Otherwise, run that session manually from its prompt. Stop between sessions for review unless the user explicitly requests uninterrupted execution.

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
Read AGENTS.md (Codex) or CLAUDE.md (Claude Code), then inspect the relevant implementation before starting. Author the requested changes directly; use native delegation only if it helps.

Pre-flight: run `git status` in /Users/tomaspc/Documents/Code/Car/HyundaiApp. There is in-progress Session 4 work uncommitted on `main` (SwiftData models, TripBuilder + tests, expanded controls, debug screen). Per the global git workflow: move that work onto a task branch (e.g. `task/session-4-swiftdata-snapshots`) before continuing — do not commit Session 4 work directly to `main`. Stash → branch → pop, or `git switch -c <branch>` if the working tree is unstaged.

Session 4 scope: full remote controls, SwiftData snapshots, and deterministic trip detection. Extend the existing iOS app under `HyundaiApp/`. Do not touch the backend.

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

If audit shows the in-progress work is mostly done, perform a focused finish-and-verify pass. If gaps are independent (e.g. command UI vs. trip-builder polishing), they may be split using the active runtime's native tools. Verify with `xcodebuild test` against the iOS 17 simulator before committing.

Done when: all commands work end-to-end, snapshots are persisting (visible in the debug screen), trip builder unit tests pass, and `xcodebuild test` is green.
```

**Done when:** debug screen shows growing snapshot list and correctly detected trips across a few real drives.

---

## Session 4.5 — Backend snapshot collector + Oracle Cloud migration ✅ Done

**Goal:** Backend polls Bluelink cached state every 15 min and stores snapshots to SQLite so data accumulates 24/7. Migrate hosting from local Mac to an Oracle Cloud Always Free ARM VM so the backend runs independently of the dev machine. Add a `/snapshots` endpoint so the iOS app can backfill its SwiftData store on launch.

**Prompt to paste:**
```
Read AGENTS.md (Codex) or CLAUDE.md (Claude Code), then inspect the backend before starting. Author the requested changes directly and branch per the global Git workflow.

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

## Session 4.6 — Remote access without the Tailscale VPN ✅ Done

**Status:** Code landed on `task/cloudflare-access` — `8ef3c29` (iOS 26.0 target), `702ed23` (iOS Access token + GET-only retries), `f18061d` (loopback bind + README). pytest (56) and `xcodebuild test` (27, iPhone 17 / iOS 26.5) green. Remaining: the manual Cloudflare setup and cutover below; mark Done after that.

**Outcome (2026-11-09):** Without a domain, the backend is published with **Tailscale Funnel** at `https://hyundai-oci.tail75a25a.ts.net` instead of Cloudflare (Cloudflare Tunnel + Access stays documented as an alternative). API bound to loopback; `/docs`/`/openapi.json` disabled; 256-bit API key verified. Verified from the public internet: `/health` 200, `/status` 401 without key and live data with it, port 8000 closed. Same day: fixed a months-long backend crash loop (login backoff `080662f`, pinned container device identity `a40336e`) and re-verified the Bluelink device via OTP. The `ts.net` ATS exception is removed. Remaining user step: set the app's backend URL to the HTTPS address.

**Goal:** Replace Tailscale-only access with a public HTTPS hostname behind Cloudflare Tunnel, gated by a Cloudflare Access service token in front of the Bearer API key, so the phone needs no VPN.

**Scope (code):**
- iOS: optional Access client ID/secret in Pairing (Keychain), sent as `CF-Access-Client-Id` / `CF-Access-Client-Secret` on every request; Access rejections surface as a clear error. Network-error retries limited to GET so commands are never re-sent.
- iOS: deployment target raised to iOS 26.0 (single-user app; device runs iOS 26.6).
- Backend: Compose publishes the API port on loopback by default (`BACKEND_BIND_ADDRESS` override for migration). README documents tunnel creation, the Access application + service-token policy, app pairing, and the Tailscale cutover.

**Manual steps (user):** domain on Cloudflare, tunnel + Access application per `backend/README.md`, deploy on the OCI VM, pair the app, then drop `BACKEND_BIND_ADDRESS`.

**Done when:** the app works over `https://car.<domain>` with Tailscale off, unauthenticated requests are refused by Access, and pytest + `xcodebuild test` are green. The `ts.net` ATS exception was removed with the Funnel switch.

---

## Session 4.7 — Car-centric dashboard redesign ✅ Done

**Status:** Done — commit `768fe63` on `task/session-4-7-dashboard`. One "Car" tab replaces Dashboard + Controls: glass status card (battery ring, fuel, ranges, lock/charge pills, freshness), quick-action tiles, climate bottom sheet, unlock confirmation, labelled "Refresh from car". Pure `VehicleStatusPresentation` + 8 tests; `xcodebuild test` 35/35 on iPhone 17 / iOS 26.5; light/dark screenshots checked with `-sampleData`. Climate sheet, unlock/charging confirmations and the command banner verified by the user on device (iPhone 14 Pro, iOS 26.6). Optional user car photo not done.

**Goal:** Replace the list-style Dashboard/Controls screens with a car-centric home screen using the iOS 26 design language.

**Prompt to paste:**
```
Read AGENTS.md (Codex) or CLAUDE.md (Claude Code), then inspect Features/Dashboard, Features/Controls, Features/Settings and the networking layer. Author the requested changes directly and branch per the global Git workflow.

Session 4.7 scope: iOS UI only, under `HyundaiApp/`. No backend or networking changes beyond what the views already call.

- Home screen: a hero status card (EV battery ring, fuel %, total/EV range, lock state, charging indicator, "updated Xm ago" from the server timestamp), with the car's name/model.
- Quick actions on the same screen: Lock, Unlock, Climate, Charge. Climate options (temp, duration, defrost) open in a bottom sheet. Unlock and other state-changing commands keep explicit confirmation where they have it today.
- Keep the existing command progress banner and structured error display. Commands never auto-retry.
- Pull-to-refresh stays cached (`force=false`); the live refresh stays an explicit, labelled action that surfaces the backend's rate-limit message.
- Use native SwiftUI and SF Symbols with iOS 26 materials (Liquid Glass); no third-party UI libraries and no copied vehicle artwork. Optional: a user-picked car photo stored locally.
- Polish empty, loading, unpaired and error states; support Dark Mode and Dynamic Type.

Keep formatting/derivation logic (percent, range, relative time, lock text) in a small pure type with unit tests; views render its output.

Verify with `xcodebuild test` and a screenshot pass on the iOS 26 simulator in light and dark mode.

Done when: the dashboard and controls render the redesigned layout against real data, tests pass, and commands behave exactly as before.
```

**Done when:** the new home screen is what you open the app for.

---

## Session 4.8 — Backend: never re-send vehicle commands at the transport layer ✅ Done

**Status:** Done — commit `ab1b551`. `cf_patch.py` now retries connection errors only for an allowlist of login and read-only Canada endpoints (`v2/login`, `mfa/selverifmeth`, `vhcllst`, `lstvhclsts`, `nxtsvc`, `rmtsts`, `evc/selsoc`, `alerts/maintenance/evTripDetails`); commands, force refresh, PIN, OTP and unknown endpoints are sent once. 20 new tests; pytest 85/85. Deployed to the OCI VM; the rebuild kept the trusted Bluelink device (no OTP) and `/status` over Funnel returned live data.

**Goal:** Close a battery-safety gap: `backend/app/cf_patch.py` wraps the upstream session's `post()` with up to 3 retries on connection errors, and Bluelink commands are POSTs, so a dropped connection after the request left could re-send lock/climate/charge.

**Prompt to paste:**
```
Read AGENTS.md (Codex) or CLAUDE.md (Claude Code), especially the vehicle and battery safety rules, then inspect backend/app/cf_patch.py, backend/app/car.py and the upstream KiaUvoApiCA command paths. Author the requested changes directly and branch per the global Git workflow.

Session 4.8 scope: backend only. Make transport retries apply only to requests that cannot trigger a vehicle action (login/token, cached status reads). Command endpoints (lock, unlock, climate, charge, and anything that wakes the car, including force refresh) must be sent at most once per API call and surface failures as structured 502s. Keep the Cloudflare TLS impersonation.

Add pytest coverage proving a connection error on a command URL is raised without a second send, and that a status read still retries.

Done when: pytest passes and the diff shows no behaviour change for status reads.
```

---

## Session 4.9 — Remote start status: confirm, show running, Live Activity ⏳ Pending

**Goal:** After a remote start, show whether the car actually started, that the engine is on with time left, and when it ends, in the app and on the Lock Screen / Dynamic Island. The official Hyundai app shows none of this. Mockups: the "Remote Start Status Mockups" canvas (starting, running, Lock Screen + Dynamic Island, didn't start / finished).

**Scope:**
- Backend: command responses expose the Bluelink `action_id`; new authenticated `GET /actions/{action_id}` returns pending/success/failed/timeout via `check_action_status` (server-side read of `rmtsts`, no wake-up), rate-limited separately from commands.
- iOS: a pure `RemoteStartTracker` (sending → confirming → running → finished/failed, countdown from the confirmed start and chosen duration, early end when saved status reports the engine off) with unit tests; the active session persists across relaunch.
- iOS: Car screen cards for starting / running / didn't start / finished. Confirmation is polled every 10 s for at most 2 min; while running and the app is open, saved status (`force=false`) is re-read every 2 min. Stop sends one stop command.
- iOS: a widget extension with a Live Activity (Lock Screen + Dynamic Island) whose countdown runs on-device with no network; its Stop button opens the app to a confirmation instead of sending a command from the extension.

**Battery safety:** no forced refreshes, no command retries; confirmation polling reads Bluelink's server only. Push updates to the Live Activity (APNs) are out of scope.

**Done when:** pytest and `xcodebuild test` are green, the backend is deployed, and a real remote start on the device shows starting → engine on with countdown (app + Lock Screen) → finished, and a refused start shows the failure state.

---

## Session 5 — Analytics UI (Swift Charts) ⏳ Pending

**Goal:** Efficiency trends, gas savings, mode-usage breakdown. Pure read-only over existing SwiftData.

**Prompt to paste:**
```
Read AGENTS.md (Codex) or CLAUDE.md (Claude Code), then inspect the iOS models and persistence layer before starting. Author the requested changes directly and branch per the global Git workflow.

Session 5 scope: analytics UI and its pure computation engine. Extend the iOS app under `HyundaiApp/`. Read-only over the SwiftData store created in Session 4. Do not change the backend or the networking layer.

Add Features/Analytics/ with Swift Charts:
- EfficiencyTrendView — line chart of L/100km and kWh/100km per week over the last 90 days.
- GasSavingsView — bar chart of estimated $ saved by EV km per month. Gas price is a user setting (Settings > Analytics, default $1.60/L CAD, editable).
- ModeBreakdownView — stacked area or pie of total km split by Trip.mode over a selectable range (week/month/all-time).
- AnalyticsHomeView — entry point linking all three, plus a "key stats" header (lifetime km, lifetime $ saved, avg combined efficiency).
- A pure AnalyticsEngine type that takes [Trip] + gasPrice and returns the values needed by each view. Fully unit tested with deterministic inputs. No view should query SwiftData directly for computation — views fetch Trips, pass to AnalyticsEngine, render.

Out of scope: widgets, App Intents, mode-suggestion engine. Those are later sessions.

The AnalyticsEngine + tests are independent of the chart views and may be split with the active runtime's native tools if both can land safely in parallel. Verify with `xcodebuild test`.

Done when: analytics screens render against the real accumulated data, AnalyticsEngine unit tests pass, gas price edits in Settings update the charts live.
```

**Done when:** all three charts look right against your real driving data.

---

## Session 6 — Widgets (Lock Screen + Home Screen) ⏳ Pending

**Goal:** Widgets reading the shared SwiftData store — no network, no force-refresh.

**Prompt to paste:**
```
Read AGENTS.md (Codex) or CLAUDE.md (Claude Code), especially the vehicle and battery safety rules, then inspect the shared SwiftData setup. Author the requested changes directly and branch per the global Git workflow.

Session 6 scope: widgets. Add a HyundaiWidget extension target to the existing Xcode project under `HyundaiApp/`.

Widgets must read from the App Group shared SwiftData store written by the main app. Widgets MUST NOT call `/status?force=true` under the project battery-safety rules. They read the latest StatusSnapshot and display "updated Xm ago".

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
Read AGENTS.md (Codex) or CLAUDE.md (Claude Code), then inspect the existing networking and shared SwiftData code. Author the requested changes directly and branch per the global Git workflow.

Session 7 scope: App Intents and Siri Shortcuts. Extend the iOS app under `HyundaiApp/` with App Intents.

Add Intents/VehicleIntents.swift with:
- LockCarIntent, UnlockCarIntent — AppIntent performing the command via CarAPIClient; returns success/failure dialog.
- StartClimateIntent — takes parameters: temperature (Int, default 22), defrost (Bool, default false), duration (Int minutes, default 10).
- StopClimateIntent.
- StartChargingIntent, StopChargingIntent.
- CheckBatteryIntent — returns a spoken/written summary like "Battery 64 percent, range 42 kilometers, fuel 80 percent." Reads from the SwiftData store (cached, no force-refresh).
- AutoLockCheckIntent — returns true only when the latest cached status says the car is unlocked and climate is off (a running proxy). Never force-refreshes; treats missing or stale data (older than a configurable window) as "do not lock".
- AutoLockIntent — runs the same check, then sends a single lock command if it passes; returns "already locked", "car appears to be running", or the command result. No retries.
- Document a walk-away automation (Shortcuts: car Wi-Fi disconnect, or CarPlay disconnect + Wait, then AutoLockCheck → confirm → Lock) and its limits: the trigger fires when the car shuts off even if the phone stays inside, so the confirming variant is the default.

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
Read AGENTS.md (Codex) or CLAUDE.md (Claude Code), then inspect the analytics and Trip models produced by earlier sessions. Author the requested changes directly and branch per the global Git workflow.

Session 8 scope: the mode-suggestion engine and final polish. Extend the iOS app under `HyundaiApp/`. Requires weeks of Trip data accumulated from prior sessions.

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

The pure ModeSuggestionEngine + tests are an obvious split candidate from the InsightsHomeView UI; use the active runtime's native delegation tools if both can land safely in parallel.

Done when: insights render against real accumulated data, unit tests pass, and the app feels ready for daily use.
```

**Done when:** insights feel useful, not noise.

---

## Cross-session reminders

- **Never paste credentials in chat.** They go into `backend/.env` directly on your machine.
- **Keep SESSIONS.md and the project guides in sync** if scope shifts mid-project — update them before starting the next session so future-you is not misled by stale instructions.
- **Mark sessions Done with the commit SHA** as soon as they land, so `session-runner` skips them on the next sweep.
- **If a session balloons,** stop and split it. The whole point of this breakdown is protecting context. Better to add Session 4a/4b than blow past a reasonable scope.
