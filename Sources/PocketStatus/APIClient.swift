import Foundation

enum APIError: LocalizedError {
    case missingConfig
    case invalidURL
    case unauthorized
    case forbidden
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            "Configura la URL y el Bearer Token en Ajustes."
        case .invalidURL:
            "La URL del servidor no es válida."
        case .unauthorized:
            "Token inválido o rechazado (401)."
        case .forbidden:
            "Acceso bloqueado por red (403). Usa Tailscale o LAN."
        case let .httpStatus(code, message):
            "Error HTTP \(code): \(message)"
        }
    }
}

enum APIClient {
    static func fetchStatus(baseURL: String, token: String) async throws -> ServerStatusResponse {
        let request = try buildRequest(baseURL: baseURL, token: token, path: "/status", method: "GET", timeout: 8)
        let data = try await send(request)
        return try JSONDecoder().decode(ServerStatusResponse.self, from: data)
    }

    static func performDockerAction(
        baseURL: String,
        token: String,
        container: String,
        action: DockerAction
    ) async throws -> DockerActionResponse {
        let request = try buildRequest(
            baseURL: baseURL,
            token: token,
            path: "/docker/\(container)/\(action.rawValue)",
            method: "POST",
            timeout: 35
        )
        let data = try await send(request)
        return try JSONDecoder().decode(DockerActionResponse.self, from: data)
    }

    static func fetchDockerLogs(
        baseURL: String,
        token: String,
        container: String,
        tail: Int = 80
    ) async throws -> DockerLogsResponse {
        let request = try buildRequest(
            baseURL: baseURL,
            token: token,
            path: "/docker/\(container)/logs?tail=\(tail)",
            method: "GET",
            timeout: 10
        )
        let data = try await send(request)
        return try JSONDecoder().decode(DockerLogsResponse.self, from: data)
    }

    private static func buildRequest(
        baseURL: String,
        token: String,
        path: String,
        method: String,
        timeout: TimeInterval
    ) throws -> URLRequest {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedBase.isEmpty, !trimmedToken.isEmpty else {
            throw APIError.missingConfig
        }
        guard let url = URL(string: "\(trimmedBase)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.httpStatus(-1, "Respuesta inválida")
        }

        switch http.statusCode {
        case 200:
            return data
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpStatus(http.statusCode, body)
        }
    }
}

