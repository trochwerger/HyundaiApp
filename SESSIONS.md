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
