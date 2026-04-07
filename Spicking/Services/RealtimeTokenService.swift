import Foundation

struct RealtimeSessionToken: Decodable {
    let ephemeralKey: String
    let expiresAt: TimeInterval
    let model: String
    let voice: String
}

enum RealtimeTokenServiceError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Worker가 올바른 토큰 응답을 돌려주지 않았어요."
        }
    }
}

struct RealtimeTokenService {
    let configuration: AppConfiguration

    func fetchToken() async throws -> RealtimeSessionToken {
        var request = URLRequest(url: configuration.workerURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.appSharedSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": configuration.model,
            "voice": configuration.voice,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "알 수 없는 서버 오류"
            throw NSError(domain: "RealtimeTokenService", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
        }

        guard let token = try? JSONDecoder().decode(RealtimeSessionToken.self, from: data) else {
            throw RealtimeTokenServiceError.invalidResponse
        }
        return token
    }
}
