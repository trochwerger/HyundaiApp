# Session Breakdown — Hyundai Companion App

Each session below is self-contained. Start a fresh Claude Code session, paste the prompt verbatim, and it will have enough context to proceed without seeing prior chats. The approved plan lives at `C:\Users\TomasRochwerger\.claude\plans\i-want-to-build-sparkling-zebra.md` — every session prompt references it.

Sessions are ordered. Do not start a later one until the prior one's "Done when" checks pass.

---

## Session 1 — Backend scaffold & Canada login

**Goal:** FastAPI project that can log into Bluelink Canada (email + password + PIN + OTP) via `hyundai_kia_connect_api` and return `/status` for your real car. Dockerized. No iOS work.

**Prompt to paste:**
```
Read the approved plan at C:\Users\TomasRochwerger\.claude\plans\i-want-to-build-sparkling-zebra.md first — it has the full architecture and rationale.

We are in Session 1 of a multi-session build. Scope for this session only: the Backend MVP (Phase 1 of the plan).

Build under C:\Users\TomasRochwerger\Documents\Code\Personal Projects\HyundaiApp\backend\:
- FastAPI app (Python 3.11) with:
  - Bearer API-key auth middleware (constant-time compare, key from env).
  - GET /health
  - GET /vehicle — returns vehicle metadata from hyundai_kia_connect_api.
  - GET /status?force=false — cached status; force=true triggers a live refresh, rate-limited to 1/10min.
  - A startup routine that performs the Canada login (email + password + PIN, OTP handled per hyundai_kia_connect_api's CANADA_LOGIN_FLOW_WITH_OTP docs) and keeps a VehicleManager in memory.
- Dockerfile + docker-compose.yml.
- .env.example listing: BLUELINK_EMAIL, BLUELINK_PASSWORD, BLUELINK_PIN, API_KEY, REGION=canada, BRAND=hyundai.
- README.md with: setup, first-run OTP flow, how to run under docker compose, how to attach Cloudflare Tunnel later.
- pytest tests for: auth middleware (401 on missing/bad key), /health, and /status with a mocked VehicleManager.

Constraints:
- Credentials must never be logged.
- No secrets committed — only .env.example.
- Keep dependencies minimal: fastapi, uvicorn, pydantic, hyundai_kia_connect_api, python-dotenv.

Done when: `docker compose up` starts the app, pytest passes, and you've documented exactly how I do the first-run OTP step against my real account (I'll run that part myself; do not prompt me for credentials).
```

**Done when:** tests pass, docker image builds, README walks through OTP flow.

---

## Session 2 — Remote commands + Cloudflare Tunnel

**Goal:** Add all remote-control endpoints; expose backend via Cloudflare Tunnel with free HTTPS.

**Prompt to paste:**
```
Read C:\Users\TomasRochwerger\.claude\plans\i-want-to-build-sparkling-zebra.md and C:\Users\TomasRochwerger\Documents\Code\Personal Projects\HyundaiApp\backend\README.md for existing state.

Session 2 scope: extend the backend with the full command set and wire up Cloudflare Tunnel. No iOS work yet.

Add to the FastAPI backend:
- POST /command/lock, /command/unlock — simple actions.
- POST /command/start, /command/stop — climate/remote-start; body accepts temp, defrost, duration with pydantic validation.
- POST /command/charge-start, /command/charge-stop — PHEV charging.
- GET /trips?from=&to= — pass-through to upstream trip history.
- Per-IP rate limit on /command/* (e.g. slowapi or a small in-memory limiter).
- Pytest coverage for each command route with a mocked VehicleManager, including rate-limit behavior.

Cloudflare Tunnel integration:
- Add a cloudflared service to docker-compose.yml (using a named tunnel config mounted from ./cloudflared/).
- README.md section: step-by-step to create a free Cloudflare account, `cloudflared tunnel login`, create a named tunnel, point a free *.trycloudflare.com hostname (or a user-owned domain) at the backend.
- Document how to rotate API_KEY safely.

Honor the plan's bluelinky-derived warning: commands must not silently retry on failure (would hammer the 12V battery). Return the upstream error verbatim in a structured JSON error response.

Done when: all new pytest cases pass, `docker compose up` brings up both fastapi and cloudflared, README has a complete tunnel setup walkthrough, and I can curl the public HTTPS URL with my API key and get /status back.
```

**Done when:** public HTTPS URL works end-to-end, all commands tested against real car once, rate limiter verified.

---

## Session 3 — iOS project scaffold + pairing + dashboard

**Goal:** Xcode project with SwiftUI app that pairs with the backend and shows live car status. One working command (lock/unlock). Nothing else.

**Prompt to paste:**
```
Read C:\Users\TomasRochwerger\.claude\plans\i-want-to-build-sparkling-zebra.md for the iOS stack and module layout.

Session 3 scope: iOS MVP (Phase 2 of the plan). The backend already works (see C:\Users\TomasRochwerger\Documents\Code\Personal Projects\HyundaiApp\backend\). Do not change the backend in this session.

Create the Xcode project at C:\Users\TomasRochwerger\Documents\Code\Personal Projects\HyundaiApp\HyundaiApp\:
- iOS 17+, SwiftUI, Swift 5.9+, no third-party deps.
- Targets: HyundaiApp (main), HyundaiAppTests (unit), HyundaiAppUITests (skip for now).
- App Group configured (will be used by widgets later): group.com.tomas.hyundaiapp.
- Folder structure per the plan: App/, Networking/, Models/, Features/{Dashboard,Controls,Settings}/.

Implement:
- Settings > Pairing screen: text fields for backend URL + API key, stored in Keychain (not UserDefaults). Include a "Test connection" button that hits GET /health.
- Networking/CarAPIClient.swift: async/await URLSession client with typed DTOs matching the backend JSON for /vehicle, /status, /command/lock, /command/unlock. Injects Bearer token from Keychain. Retries network errors once; never retries on 4xx.
- Features/Dashboard/DashboardView.swift: fuel %, EV battery %, range, lock state, last-updated timestamp. "Refresh" button calls /status?force=true; pull-to-refresh calls /status?force=false.
- Features/Controls: lock + unlock buttons with loading + error states.
- Unit tests for CarAPIClient using URLProtocol stubs (no live network).

Out of scope: SwiftData persistence, widgets, App Intents, analytics, other commands. Those are later sessions — do not add them.

Done when: build succeeds for iOS 17 simulator, unit tests pass, and the dashboard + lock/unlock work against a local backend.
```

**Done when:** app runs on your device, paired with backend, lock/unlock works on real car.

---

## Session 4 — Full remote controls + SwiftData snapshots

**Goal:** All commands wired up in iOS; every `/status` read writes a `StatusSnapshot` to SwiftData. Trip detection stubbed.

**Prompt to paste:**
```
Read C:\Users\TomasRochwerger\.claude\plans\i-want-to-build-sparkling-zebra.md.

Session 4 scope: Phases 3 and 4 of the plan. Extend the existing iOS app at C:\Users\TomasRochwerger\Documents\Code\Personal Projects\HyundaiApp\HyundaiApp\. Do not touch the backend.

Add:
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

Done when: all commands work end-to-end, snapshots are persisting (visible in the debug screen), trip builder unit tests pass.
```

**Done when:** debug screen shows growing snapshot list and correctly detected trips across a few real drives.

---

## Session 5 — Analytics UI (Swift Charts)

**Goal:** Efficiency trends, gas savings, mode-usage breakdown. Pure read-only over existing SwiftData.

**Prompt to paste:**
```
Read C:\Users\TomasRochwerger\.claude\plans\i-want-to-build-sparkling-zebra.md.

Session 5 scope: Phase 5 of the plan. Extend the iOS app at C:\Users\TomasRochwerger\Documents\Code\Personal Projects\HyundaiApp\HyundaiApp\. Read-only over the SwiftData store created in Session 4. Do not change the backend or the networking layer.

Add Features/Analytics/ with Swift Charts:
- EfficiencyTrendView — line chart of L/100km and kWh/100km per week over the last 90 days.
- GasSavingsView — bar chart of estimated $ saved by EV km per month. Gas price is a user setting (Settings > Analytics, default $1.60/L CAD, editable).
- ModeBreakdownView — stacked area or pie of total km split by Trip.mode over a selectable range (week/month/all-time).
- AnalyticsHomeView — entry point linking all three, plus a "key stats" header (lifetime km, lifetime $ saved, avg combined efficiency).
- A pure AnalyticsEngine type that takes [Trip] + gasPrice and returns the values needed by each view. Fully unit tested with deterministic inputs. No view should query SwiftData directly for computation — views fetch Trips, pass to AnalyticsEngine, render.

Out of scope: widgets, App Intents, mode-suggestion engine. Those are later sessions.

Done when: analytics screens render against the real accumulated data, AnalyticsEngine unit tests pass, gas price edits in Settings update the charts live.
```

**Done when:** all three charts look right against your real driving data.

---

## Session 6 — Widgets (Lock Screen + Home Screen)

**Goal:** Widgets reading the shared SwiftData store — no network, no force-refresh.

**Prompt to paste:**
```
Read C:\Users\TomasRochwerger\.claude\plans\i-want-to-build-sparkling-zebra.md, especially the "Widgets & Shortcuts" and "Polling strategy" sections.

Session 6 scope: Phase 6. Add a HyundaiWidget extension target to the existing Xcode project at C:\Users\TomasRochwerger\Documents\Code\Personal Projects\HyundaiApp\HyundaiApp\.

Widgets must read from the App Group shared SwiftData store written by the main app. Widgets MUST NOT call /status?force=true — battery-safety rule from the plan. They read the latest StatusSnapshot and display "updated Xm ago".

Add widget families:
- accessoryCircular (Lock Screen): EV battery % ring.
- accessoryRectangular (Lock Screen): battery %, fuel %, lock state on one line.
- systemSmall: battery + fuel + range.
- systemMedium: small content + lock state + last-updated timestamp + charging indicator.

TimelineProvider refreshes every 15 minutes from the shared store (no network). Placeholder + snapshot entries handled.

Include snapshot previews for every size/family for App Store screenshots later.

Out of scope: App Intents, mode-suggestion engine. Next sessions.

Done when: widgets install on a physical device, show correct data from the shared store, and do not trigger any network calls.
```

**Done when:** Lock Screen widget shows real car data on your phone.

---

## Session 7 — App Intents + Siri Shortcuts

**Goal:** Remote commands and status queries via Siri / Shortcuts app / Home Screen shortcut icons.

**Prompt to paste:**
```
Read C:\Users\TomasRochwerger\.claude\plans\i-want-to-build-sparkling-zebra.md.

Session 7 scope: Phase 7. Extend the iOS app at C:\Users\TomasRochwerger\Documents\Code\Personal Projects\HyundaiApp\HyundaiApp\ with App Intents.

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

Unit-test intent bodies by mocking CarAPIClient.

Out of scope: mode-suggestion engine.

Done when: "Hey Siri, lock the Tucson" (or your chosen phrase) works end-to-end against the real car, and all intents are usable from the Shortcuts app as Home Screen icons.
```

**Done when:** Siri executes each intent on your phone.

---

## Session 8 — Mode-suggestion engine

**Goal:** Weekly insight card: "you'd have saved ~$12 driving trip X in EV mode." Final polish.

**Prompt to paste:**
```
Read C:\Users\TomasRochwerger\.claude\plans\i-want-to-build-sparkling-zebra.md, especially the "Analytics engine" section.

Session 8 scope: Phase 8. Extend the iOS app at C:\Users\TomasRochwerger\Documents\Code\Personal Projects\HyundaiApp\HyundaiApp\. Requires weeks of Trip data accumulated from prior sessions.

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

Done when: insights render against real accumulated data, unit tests pass, and the app feels ready for daily use.
```

**Done when:** insights feel useful, not noise.

---

## Cross-session reminders

- **Never paste credentials in chat.** They go into `backend/.env` directly on your machine.
- **Keep SESSIONS.md and the plan file in sync** if scope shifts mid-project — update them before starting the next session so future-you isn't misled by stale instructions.
- **If a session balloons,** stop and split it. The whole point of this breakdown is protecting context. Better to add Session 4a/4b than blow past a reasonable scope.
