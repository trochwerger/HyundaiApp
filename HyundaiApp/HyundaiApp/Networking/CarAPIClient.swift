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

public final class CarAPIClient {
    private let session: URLSession
    private let baseURLProvider: () -> URL?
    private let tokenProvider: () -> String?
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
        }
    ) {
        self.session = session
        self.baseURLProvider = baseURLProvider
        self.tokenProvider = tokenProvider
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
        shouldRetry: Bool = true
    ) async throws -> T {
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
