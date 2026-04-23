import SwiftUI

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

    init(client: CarAPIClient = CarAPIClient()) {
        self.client = client
    }

    func refresh(force: Bool) async {
        loadState = .loading

        do {
            status = try await client.status(force: force)
            lastRefresh = Date()
            loadState = .idle
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }
}
