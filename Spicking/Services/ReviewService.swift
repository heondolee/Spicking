import Foundation

struct ReviewService {
    struct SuggestionEnvelope: Decodable {
        let suggestions: [Suggestion]
    }

    struct Suggestion: Decodable {
        let originalText: String
        let minimalRewrite: String
        let naturalRewrite: String
        let reasonKo: String
        let intentKo: String
    }

    func parseSuggestions(from rawText: String) throws -> [Suggestion] {
        let jsonPayload = extractJSONObject(from: rawText)
        let data = Data(jsonPayload.utf8)
        return try JSONDecoder().decode(SuggestionEnvelope.self, from: data).suggestions
    }

    private func extractJSONObject(from text: String) -> String {
        if let range = text.range(of: #"(?s)\{.*\}"#, options: .regularExpression) {
            return String(text[range])
        }
        return text
    }
}
