import Foundation

public enum CarAPIError: Error, Equatable, LocalizedError {
    case notPaired
    case invalidURL
    case network(message: String)
    case decoding(message: String)
    case http(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .notPaired:
            return "Backend URL and API key are required."
        case .invalidURL:
            return "The backend URL is invalid."
        case .network(let message):
            return message
        case .decoding(let message):
            return "Failed to decode the server response: \(message)"
        case .http(_, let message):
            return message
        }
    }
}

/// Cloudflare Access service-token credentials sent with every request when the
/// backend sits behind a Cloudflare Tunnel protected by an Access application.
public struct AccessServiceToken: Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String

    public init?(clientID: String?, clientSecret: String?) {
        let id = clientID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty, !secret.isEmpty else { return nil }
        self.clientID = id
        self.clientSecret = secret
    }
}

public final class CarAPIClient {
    private let session: URLSession
    private let baseURLProvider: () -> URL?
    private let tokenProvider: () -> String?
    private let accessTokenProvider: () -> AccessServiceToken?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(
        session: URLSession = .shared,
        baseURLProvider: @escaping () -> URL? = {
            KeychainStore.getBackendURL()
                .flatMap(CarAPIClient.normalizedBaseURL(from:))
        },
        tokenProvider: @escaping () -> String? = {
            KeychainStore.getAPIKey()
        },
        accessTokenProvider: @escaping () -> AccessServiceToken? = {
            AccessServiceToken(
                clientID: KeychainStore.getAccessClientID(),
                clientSecret: KeychainStore.getAccessClientSecret()
            )
        }
    ) {
        self.session = session
        self.baseURLProvider = baseURLProvider
        self.tokenProvider = tokenProvider
        self.accessTokenProvider = accessTokenProvider
    }

    public func health() async throws -> HealthDTO {
        let request = try makeRequest(path: "/health", method: "GET", requiresAuth: false)
        return try await send(request, decodeAs: HealthDTO.self)
    }

    public func vehicle() async throws -> VehicleDTO {
        let request = try makeRequest(path: "/vehicle", method: "GET", requiresAuth: true)
        return try await send(request, decodeAs: VehicleDTO.self)
    }

    public func status(force: Bool) async throws -> StatusDTO {
        let request = try makeRequest(
            path: "/status",
            method: "GET",
            queryItems: [URLQueryItem(name: "force", value: force ? "true" : "false")],
            requiresAuth: true
        )
        return try await send(request, decodeAs: StatusDTO.self)
    }

    public func lock() async throws -> CommandResponseDTO {
        let request = try makeRequest(path: "/command/lock", method: "POST", requiresAuth: true)
        return try await send(request, decodeAs: CommandResponseDTO.self)
    }

    public func unlock() async throws -> CommandResponseDTO {
        let request = try makeRequest(path: "/command/unlock", method: "POST", requiresAuth: true)
        return try await send(request, decodeAs: CommandResponseDTO.self)
    }

    public func startClimate(temp: Double?, defrost: Bool?, duration: Int?) async throws -> CommandResponseDTO {
        let body = try encoder.encode(ClimateStartRequestDTO(temp: temp, defrost: defrost, duration: duration))
        let request = try makeRequest(path: "/command/start", method: "POST", body: body, requiresAuth: true)
        return try await send(request, decodeAs: CommandResponseDTO.self)
    }

    public func stopClimate() async throws -> CommandResponseDTO {
        let request = try makeRequest(path: "/command/stop", method: "POST", requiresAuth: true)
        return try await send(request, decodeAs: CommandResponseDTO.self)
    }

    public func chargeStart() async throws -> CommandResponseDTO {
        let request = try makeRequest(path: "/command/charge-start", method: "POST", requiresAuth: true)
        return try await send(request, decodeAs: CommandResponseDTO.self)
    }

    public func chargeStop() async throws -> CommandResponseDTO {
        let request = try makeRequest(path: "/command/charge-stop", method: "POST", requiresAuth: true)
        return try await send(request, decodeAs: CommandResponseDTO.self)
    }

    /// Asks whether the car confirmed a command. Reads Bluelink's server only.
    public func actionStatus(id: String) async throws -> ActionStatusDTO {
        let request = try makeRequest(path: "/actions/\(id)", method: "GET", requiresAuth: true)
        return try await send(request, decodeAs: ActionStatusDTO.self)
    }

    public static func normalizedBaseURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            return nil
        }

        guard let scheme = url.scheme, !scheme.isEmpty else {
            return nil
        }

        return url
    }

    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        requiresAuth: Bool
    ) throws -> URLRequest {
        guard let baseURL = baseURLProvider() else {
            throw CarAPIError.notPaired
        }

        guard let scheme = baseURL.scheme, !scheme.isEmpty else {
            throw CarAPIError.notPaired
        }

        let endpointURL = baseURL.appending(path: path)
        guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
            throw CarAPIError.invalidURL
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let finalURL = components.url else {
            throw CarAPIError.invalidURL
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        request.httpBody = body

        // Cloudflare Access gates every path, including /health, so the
        // service token goes on all requests when configured.
        if let accessToken = accessTokenProvider() {
            request.setValue(accessToken.clientID, forHTTPHeaderField: "CF-Access-Client-Id")
            request.setValue(accessToken.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }

        if requiresAuth {
            let token = tokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !token.isEmpty else {
                throw CarAPIError.notPaired
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func send<T: Decodable>(
        _ request: URLRequest,
        decodeAs type: T.Type,
        shouldRetry: Bool? = nil
    ) async throws -> T {
        // Only idempotent reads are retried. A vehicle command may have reached
        // the backend before the connection dropped, and re-sending it could
        // wake the car twice (see the project's battery-safety rules).
        let shouldRetry = shouldRetry ?? (request.httpMethod == "GET")
        do {
            let (data, response) = try await session.data(for: request)
            return try decodeResponse(data: data, response: response, as: type)
        } catch let error as URLError {
            if shouldRetry {
                return try await send(request, decodeAs: type, shouldRetry: false)
            }
            throw CarAPIError.network(message: error.localizedDescription)
        } catch let error as CarAPIError {
            throw error
        } catch let error as DecodingError {
            throw CarAPIError.decoding(message: error.localizedDescription)
        } catch {
            throw CarAPIError.network(message: error.localizedDescription)
        }
    }

    private func decodeResponse<T: Decodable>(
        data: Data,
        response: URLResponse,
        as type: T.Type
    ) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CarAPIError.network(message: "Invalid server response.")
        }

        // Without a valid service token, Cloudflare Access either redirects to
        // its sign-in page (which URLSession follows) or answers 403 itself.
        if Self.isCloudflareAccessRejection(httpResponse) {
            throw CarAPIError.http(status: 403, message: Self.accessRejectedMessage)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CarAPIError.http(status: httpResponse.statusCode, message: decodeHTTPError(from: data))
        }

        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            throw CarAPIError.decoding(message: error.localizedDescription)
        } catch {
            throw CarAPIError.decoding(message: error.localizedDescription)
        }
    }

    public static let accessRejectedMessage =
        "Cloudflare Access blocked the request. Check the Access client ID and secret in Pairing."

    static func isCloudflareAccessRejection(_ response: HTTPURLResponse) -> Bool {
        if let host = response.url?.host?.lowercased(), host.hasSuffix("cloudflareaccess.com") {
            return true
        }
        guard response.statusCode == 401 || response.statusCode == 403 else { return false }
        let contentType = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        return contentType.contains("text/html")
    }

    private func decodeHTTPError(from data: Data) -> String {
        if let apiError = try? decoder.decode(APIErrorDTO.self, from: data) {
            return apiError.detail.message
        }

        let fallback = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if fallback.isEmpty {
            return "The server returned an error."
        }

        return String(fallback.prefix(500))
    }
}
