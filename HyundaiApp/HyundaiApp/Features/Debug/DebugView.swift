import SwiftUI
import SwiftData

struct DebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StatusSnapshot.timestamp, order: .reverse) private var snapshots: [StatusSnapshot]

    var body: some View {
        let _ = modelContext

        List {
            Section("Snapshots (latest 100)") {
                ForEach(latestSnapshots, id: \.id) { snapshot in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(timestampText(for: snapshot.timestamp))
                            .font(.headline)

                        Text(snapshotSummary(for: snapshot))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Detected trips") {
                if detectedTrips.isEmpty {
                    Text("No trips detected.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(detectedTrips.enumerated()), id: \.offset) { _, trip in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(timestampText(for: trip.startAt)) – \(timeText(for: trip.endAt))")
                                .font(.headline)

                            Text("\(trip.distanceKm.formatted(.number.precision(.fractionLength(0...1)))) km, \(trip.mode.rawValue)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Stats") {
                statsRow(title: "Snapshots", value: "\(snapshots.count)")
                statsRow(title: "Trips", value: "\(detectedTrips.count)")
                statsRow(title: "Earliest", value: snapshots.last.map { timestampText(for: $0.timestamp) } ?? "—")
                statsRow(title: "Latest", value: snapshots.first.map { timestampText(for: $0.timestamp) } ?? "—")
            }
        }
        .navigationTitle("Debug")
    }

    private var latestSnapshots: [StatusSnapshot] {
        Array(snapshots.prefix(100))
    }

    private var detectedTrips: [DetectedTrip] {
        TripBuilder.buildTrips(from: snapshots.reversed().map(\.snapshotInput))
            .sorted { $0.startAt > $1.startAt }
    }

    private func snapshotSummary(for snapshot: StatusSnapshot) -> String {
        let lockText: String
        if let isLocked = snapshot.isLocked {
            lockText = isLocked ? "Locked" : "Unlocked"
        } else {
            lockText = "Lock unknown"
        }

        let odometerText = snapshot.odometerKm.map {
            $0.formatted(.number.precision(.fractionLength(0...1))) + " km"
        } ?? "—"
        let fuelText = snapshot.fuelPercent.map { "\($0)%" } ?? "—"
        let evText = snapshot.evBatteryPercent.map { "\($0)%" } ?? "—"

        return "Odometer \(odometerText) • Fuel \(fuelText) • EV \(evText) • \(lockText)"
    }

    private func statsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func timestampText(for date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    private func timeText(for date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
}
