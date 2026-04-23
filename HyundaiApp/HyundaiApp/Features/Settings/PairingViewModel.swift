import SwiftUI

@MainActor
final class PairingViewModel: ObservableObject {
    enum TestState: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    @Published var backendURL: String
    @Published var apiKey: String
    @Published var testState: TestState

    init() {
        backendURL = KeychainStore.getBackendURL() ?? ""
        apiKey = KeychainStore.getAPIKey() ?? ""
        testState = .idle
    }

    func save() throws {
        let trimmedURL = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        backendURL = trimmedURL
        apiKey = trimmedKey

        try KeychainStore.setBackendURL(trimmedURL)
        try KeychainStore.setAPIKey(trimmedKey)
    }

    func testConnection() async {
        testState = .testing

        let client = CarAPIClient(
            baseURLProvider: { [weak self] in
                guard let self else { return nil }
                return CarAPIClient.normalizedBaseURL(from: self.backendURL)
            },
            tokenProvider: { [weak self] in
                self?.apiKey
            }
        )

        do {
            let health = try await client.health()
            testState = health.status == "ok" ? .success : .failure("unexpected response")
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}
