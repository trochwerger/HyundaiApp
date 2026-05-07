import SwiftUI
import SwiftData

@MainActor
final class DashboardViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case error(String)
    }

    @Published var status: StatusDTO?
    @Published var loadState: LoadState = .idle
    @Published var lastRefresh: Date?

    let client: CarAPIClient
    private var modelContext: ModelContext?
    private let onSnapshotInserted: ((StatusSnapshot) -> Void)?

    init(
        client: CarAPIClient = CarAPIClient(),
        modelContext: ModelContext? = nil,
        onSnapshotInserted: ((StatusSnapshot) -> Void)? = nil
    ) {
        self.client = client
        self.modelContext = modelContext
        self.onSnapshotInserted = onSnapshotInserted
    }

    func configure(context: ModelContext) {
        modelContext = context
    }

    func refresh(force: Bool) async {
        loadState = .loading

        do {
            let dto = try await client.status(force: force)
            let receivedAt = Date()

            status = dto
            lastRefresh = receivedAt
            persistSnapshot(from: dto, receivedAt: receivedAt)
            loadState = .idle
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    private func persistSnapshot(from dto: StatusDTO, receivedAt: Date) {
        let rawJSON = encodeSnapshotJSON(for: dto)
        let snapshot = StatusSnapshot.make(from: dto, rawJSON: rawJSON, receivedAt: receivedAt)

        guard let modelContext else {
            return
        }

        guard shouldInsert(snapshot: snapshot, into: modelContext) else {
            return
        }

        modelContext.insert(snapshot)
        try? modelContext.save()
        onSnapshotInserted?(snapshot)
    }

    private func encodeSnapshotJSON(for dto: StatusDTO) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(dto)
            return String(decoding: data, as: UTF8.self)
        } catch {
            var standardError = StandardErrorOutput()
            print("[snapshot] Failed to encode status JSON: \(error)", to: &standardError)
            return ""
        }
    }

    private func shouldInsert(snapshot: StatusSnapshot, into modelContext: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<StatusSnapshot>(
            sortBy: [SortDescriptor(\StatusSnapshot.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let existing = try? modelContext.fetch(descriptor).first else {
            return true
        }

        guard existing.timestamp == snapshot.timestamp else {
            return true
        }

        guard let existingOdometer = existing.odometerKm, let newOdometer = snapshot.odometerKm else {
            return true
        }

        return existingOdometer != newOdometer
    }
}

private struct StandardErrorOutput: TextOutputStream {
    mutating func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}
