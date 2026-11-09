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
    @Published var accessClientID: String
    @Published var accessClientSecret: String
    @Published var testState: TestState

    init() {
        backendURL = KeychainStore.getBackendURL() ?? ""
        apiKey = KeychainStore.getAPIKey() ?? ""
        accessClientID = KeychainStore.getAccessClientID() ?? ""
        accessClientSecret = KeychainStore.getAccessClientSecret() ?? ""
        testState = .idle
    }

    func save() throws {
        let trimmedURL = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedAccessID = accessClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccessSecret = accessClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        backendURL = trimmedURL
        apiKey = trimmedKey
        accessClientID = trimmedAccessID
        accessClientSecret = trimmedAccessSecret

        try KeychainStore.setBackendURL(trimmedURL)
        try KeychainStore.setAPIKey(trimmedKey)
        try KeychainStore.setAccessClientID(trimmedAccessID)
        try KeychainStore.setAccessClientSecret(trimmedAccessSecret)
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
            },
            accessTokenProvider: { [weak self] in
                guard let self else { return nil }
                return AccessServiceToken(clientID: self.accessClientID, clientSecret: self.accessClientSecret)
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
