import SwiftUI
import SwiftData

/// Car-centric home screen: status card, quick actions, and live refresh.
///
/// Battery-safety rules: opening the screen and pull-to-refresh read the
/// backend's cached status (`force=false`). Only the labelled "Refresh from
/// car" button wakes the vehicle. Commands are sent once and never retried.
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext

    // The VMs start unbound so previews and tests can instantiate them without SwiftData.
    @StateObject private var vm: DashboardViewModel
    @StateObject private var controls: ControlsViewModel
    @StateObject private var remoteStart: RemoteStartController

    @State private var isPaired = DashboardView.hasPairing() || DashboardView.isSampleMode
    @State private var showClimate = false
    @State private var confirmUnlock = false
    @State private var showChargeOptions = false
    @State private var confirmStopFromLiveActivity = false
    @State private var dismissTask: Task<Void, Never>?

    init(client: CarAPIClient = CarAPIClient()) {
        _vm = StateObject(wrappedValue: DashboardViewModel(client: client))
        _controls = StateObject(wrappedValue: ControlsViewModel(client: client))
        _remoteStart = StateObject(wrappedValue: RemoteStartController(client: client))
    }

    var body: some View {
        // Re-render every minute so "Updated X min ago" stays current.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(presentation: VehicleStatusPresentation(
                status: vm.status,
                lastRefresh: vm.lastRefresh,
                now: context.date
            ))
        }
        .background(background)
        .overlay(alignment: .top) { banner }
        .animation(.easeInOut(duration: 0.2), value: controls.busy)
        .animation(.easeInOut(duration: 0.2), value: controls.lastResult)
        .sheet(isPresented: $showClimate) {
            ClimateSheet(controls: controls, send: send)
        }
        .confirmationDialog("Unlock your car?", isPresented: $confirmUnlock, titleVisibility: .visible) {
            Button("Unlock") { send(.unlock) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The doors will unlock remotely.")
        }
        .confirmationDialog("Charging", isPresented: $showChargeOptions, titleVisibility: .visible) {
            Button("Start charging") { send(.chargeStart) }
            Button("Stop charging", role: .destructive) { send(.chargeStop) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Stop remote start?", isPresented: $confirmStopFromLiveActivity, titleVisibility: .visible) {
            Button("Stop", role: .destructive) { send(.stopClimate) }
            Button("Keep running", role: .cancel) {}
        }
        .onChange(of: controls.lastResult) { _, newValue in
            scheduleBannerDismiss(newValue)
        }
        .onChange(of: vm.lastRefresh) { _, _ in
            remoteStart.statusUpdated(vm.status)
            remoteStart.vehicleName = VehicleStatusPresentation.title(for: vm.status)
        }
        .onOpenURL { url in
            // The Live Activity's Stop button opens the app here; the stop
            // itself still needs the user's confirmation.
            if url == RemoteStartActivityAttributes.stopURL, remoteStart.session?.isActive == true {
                confirmStopFromLiveActivity = true
            }
        }
        .onAppear {
            guard !Self.isSampleMode else { return }
            let pairedNow = Self.hasPairing()
            if pairedNow && !isPaired {
                Task { await vm.refresh(force: false) }
            }
            isPaired = pairedNow
        }
        .task {
            #if DEBUG
            if Self.isSampleMode {
                vm.status = Self.sampleStatus
                vm.lastRefresh = Date()
                return
            }
            #endif
            vm.configure(context: modelContext)
            remoteStart.refreshSavedStatus = { [vm] in await vm.refresh(force: false) }
            if isPaired {
                await vm.refresh(force: false)
            }
        }
    }

    // MARK: - States

    @ViewBuilder
    private func content(presentation p: VehicleStatusPresentation) -> some View {
        if !isPaired {
            unpairedView
        } else if vm.status == nil, case .error(let message) = vm.loadState {
            unreachableView(message: message)
        } else if vm.status == nil {
            ProgressView("Loading your car…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            statusScroll(p)
        }
    }

    private var unpairedView: some View {
        ContentUnavailableView {
            Label("Connect your backend", systemImage: "car.fill")
        } description: {
            Text("Add your backend URL and API key to see your car here.")
        } actions: {
            NavigationLink("Open Pairing") {
                PairingView()
            }
            .buttonStyle(.glassProminent)
        }
    }

    private func unreachableView(message: String) -> some View {
        ContentUnavailableView {
            Label("Can't reach your car", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") {
                Task { await vm.refresh(force: false) }
            }
            .buttonStyle(.glassProminent)
        }
    }

    private func statusScroll(_ p: VehicleStatusPresentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(p)
                if let session = remoteStart.session {
                    RemoteStartCard(
                        session: session,
                        isLocked: vm.status?.isLocked,
                        isStopping: controls.busy == .stopClimate,
                        onStop: { send(.stopClimate) },
                        onRetry: {
                            remoteStart.dismiss()
                            showClimate = true
                        },
                        onDismiss: { remoteStart.dismiss() }
                    )
                }

                heroCard(p)

                if case .error(let message) = vm.loadState {
                    inlineError(message)
                }

                Text("Quick actions")
                    .font(.headline)
                    .padding(.top, 4)
                actions(p)

                liveRefresh
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await vm.refresh(force: false)
        }
        .navigationTitle(p.title)
        .toolbar {
            if vm.loadState == .loading {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                }
            }
        }
    }

    // MARK: - Sections

    private func header(_ p: VehicleStatusPresentation) -> some View {
        HStack(spacing: 6) {
            if let subtitle = p.subtitle {
                Text(subtitle)
                Text("·")
            }
            Text(p.updatedText)
            if p.freshness == .stale {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Status may be out of date")
            }
            Spacer(minLength: 0)
            if let temperature = p.outsideTemperatureText {
                Label(temperature, systemImage: "thermometer.medium")
                    .accessibilityLabel("Outside \(temperature)")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func heroCard(_ p: VehicleStatusPresentation) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) {
                    batteryRing(p)
                    levels(p)
                }
                VStack(alignment: .center, spacing: 18) {
                    batteryRing(p)
                    levels(p)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { pills(p) }
                VStack(alignment: .leading, spacing: 8) { pills(p) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func batteryRing(_ p: VehicleStatusPresentation) -> some View {
        BatteryRing(
            fraction: p.batteryFraction,
            percentText: p.batteryText,
            rangeText: p.evRangeText,
            isCharging: p.chargeState == .charging
        )
    }

    private func levels(_ p: VehicleStatusPresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            LevelBar(
                title: "Fuel",
                symbol: "fuelpump.fill",
                fraction: p.fuelFraction,
                valueText: p.fuelText,
                detailText: "\(p.fuelRangeText) range",
                tint: .orange
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Total range")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(p.totalRangeText)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pills(_ p: VehicleStatusPresentation) -> some View {
        StatusPill(text: p.lockText, symbol: p.lockSymbol, tint: lockTint(p.lockState))
        StatusPill(text: p.chargeText, symbol: p.chargeSymbol, tint: chargeTint(p.chargeState))
    }

    private func actions(_ p: VehicleStatusPresentation) -> some View {
        GlassEffectContainer(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                QuickActionTile(title: "Lock", symbol: "lock.fill", tint: .blue, isBusy: controls.busy == .lock) {
                    send(.lock)
                }
                QuickActionTile(title: "Unlock", symbol: "lock.open.fill", tint: .orange, isBusy: controls.busy == .unlock) {
                    confirmUnlock = true
                }
                QuickActionTile(
                    title: "Climate",
                    symbol: "fan.fill",
                    tint: .green,
                    isBusy: controls.busy == .startClimate || controls.busy == .stopClimate
                ) {
                    showClimate = true
                }
                QuickActionTile(
                    title: "Charging",
                    symbol: "bolt.fill",
                    tint: .teal,
                    isBusy: controls.busy == .chargeStart || controls.busy == .chargeStop
                ) {
                    showChargeOptions = true
                }
            }
        }
        .disabled(controls.busy != nil)
    }

    private var liveRefresh: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await vm.refresh(force: true) }
            } label: {
                Label("Refresh from car", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(vm.loadState == .loading)

            Text("Pull down for the latest saved status. Refresh from car wakes the vehicle and is limited to once every 10 minutes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func inlineError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassEffect(.regular.tint(.red.opacity(0.12)), in: .rect(cornerRadius: 18))
    }

    // MARK: - Banner

    @ViewBuilder
    private var banner: some View {
        if controls.busy != nil || controls.lastResult != nil {
            CommandStatusBanner(busy: controls.busy, result: controls.lastResult) {
                dismissTask?.cancel()
                controls.clearResult()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func scheduleBannerDismiss(_ result: ControlsViewModel.Result?) {
        dismissTask?.cancel()
        guard let result else { return }
        // Failures stay a little longer so they can be read.
        let seconds: Double = if case .failure = result { 6 } else { 3 }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            controls.clearResult()
        }
    }

    // MARK: - Actions

    /// Sends a command once. On success, re-reads the cached status (no wake-up).
    private func send(_ command: ControlsViewModel.Command) {
        let batteryBefore = vm.status?.evBatteryPercentage
        Task {
            let response = await controls.perform(command)
            guard case .success = controls.lastResult else { return }

            switch command {
            case .startClimate:
                remoteStart.began(
                    response: response,
                    durationMinutes: controls.startDuration,
                    temperature: controls.startTemp,
                    defrost: controls.defrost,
                    batteryPercent: batteryBefore
                )
            case .stopClimate:
                remoteStart.stopped()
            default:
                break
            }
            await vm.refresh(force: false)
        }
    }

    // MARK: - Styling

    private var background: some View {
        LinearGradient(
            colors: [Color.teal.opacity(0.22), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    private func lockTint(_ state: VehicleStatusPresentation.LockState) -> Color {
        switch state {
        case .locked: return .green
        case .unlocked: return .orange
        case .unknown: return .secondary
        }
    }

    private func chargeTint(_ state: VehicleStatusPresentation.ChargeState) -> Color {
        switch state {
        case .charging: return .green
        case .pluggedIn: return .teal
        case .unplugged, .unknown: return .secondary
        }
    }

    /// Debug-only `-sampleData` launch argument: render a canned status with
    /// no network calls, for simulator screenshots without real credentials.
    static var isSampleMode: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-sampleData")
        #else
        return false
        #endif
    }

    static func hasPairing() -> Bool {
        let url = KeychainStore.getBackendURL()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = KeychainStore.getAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !url.isEmpty && !key.isEmpty
    }
}

#if DEBUG
extension DashboardView {
    static let sampleStatus: StatusDTO? = {
        let json = """
        {
          "name": "TUCSON", "model": "TUCSON PHEV", "year": 2025,
          "ev_battery_percentage": 81, "ev_driving_range": 48, "ev_driving_range_unit": "km",
          "fuel_level": 59, "fuel_driving_range": 402, "total_driving_range": 450,
          "total_driving_range_unit": "km", "is_locked": true,
          "ev_battery_is_charging": false, "ev_battery_is_plugged_in": 0,
          "outside_temperature": 5
        }
        """
        return try? JSONDecoder().decode(StatusDTO.self, from: Data(json.utf8))
    }()
}
#endif

#Preview {
    NavigationStack {
        DashboardView()
    }
}
