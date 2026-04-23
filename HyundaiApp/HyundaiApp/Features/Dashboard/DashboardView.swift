import SwiftUI

struct DashboardView: View {
    @StateObject private var vm: DashboardViewModel

    init(client: CarAPIClient = CarAPIClient()) {
        _vm = StateObject(wrappedValue: DashboardViewModel(client: client))
    }

    var body: some View {
        List {
            if case .error(let message) = vm.loadState {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.red)

                        Button("Retry") {
                            Task {
                                await vm.refresh(force: true)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Vehicle") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(headerTitle)
                        .font(.title3.weight(.semibold))
                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Status") {
                metricRow(title: "Fuel", value: percentageText(vm.status?.fuelLevel))
                metricRow(title: "EV battery", value: evBatteryText)
                metricRow(title: "Total range", value: distanceText(value: vm.status?.totalDrivingRange, unit: vm.status?.totalDrivingRangeUnit))
                metricRow(title: "Lock state", value: lockStateText)
                metricRow(title: "Last updated", value: lastUpdatedText)
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if vm.loadState == .loading {
                    Text("Requesting live refresh…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Refresh") {
                        Task {
                            await vm.refresh(force: true)
                        }
                    }
                }
            }
        }
        .refreshable {
            await vm.refresh(force: false)
        }
        .task {
            await vm.refresh(force: false)
        }
    }

    private var headerTitle: String {
        let parts = [vm.status?.year.map(String.init), vm.status?.model]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    private var headerSubtitle: String {
        let parts = [vm.status?.name, vm.status?.vin]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        return parts.isEmpty ? "—" : parts.joined(separator: " • ")
    }

    private var evBatteryText: String {
        let base = percentageText(vm.status?.evBatteryPercentage)
        if vm.status?.evBatteryIsCharging == true {
            return "\(base) charging"
        }
        return base
    }

    private var lockStateText: String {
        guard let isLocked = vm.status?.isLocked else {
            return "—"
        }
        return isLocked ? "Locked" : "Unlocked"
    }

    private var lastUpdatedText: String {
        if let serverTimestamp = vm.status?.lastUpdatedAt {
            return formatDateString(serverTimestamp)
        }

        if let lastRefresh = vm.lastRefresh {
            return DateFormatter.localizedString(from: lastRefresh, dateStyle: .medium, timeStyle: .short)
        }

        return "—"
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func percentageText(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)%"
    }

    private func distanceText(value: Double?, unit: String?) -> String {
        guard let value else { return "—" }
        let formattedValue = value.formatted(.number.precision(.fractionLength(0...1)))
        if let unit, !unit.isEmpty {
            return "\(formattedValue) \(unit)"
        }
        return formattedValue
    }

    private func formatDateString(_ rawValue: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: rawValue) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }

        let fallbackFormatter = ISO8601DateFormatter()
        if let date = fallbackFormatter.date(from: rawValue) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }

        return rawValue
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
}
