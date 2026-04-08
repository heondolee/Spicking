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
        let envelope = try JSONDecoder().decode(SuggestionEnvelope.self, from: data)
        return envelope.suggestions.compactMap(normalize)
    }

    private func extractJSONObject(from text: String) -> String {
        if let range = text.range(of: #"(?s)\{.*\}"#, options: .regularExpression) {
            return String(text[range])
        }
        return text
    }

    private func normalize(_ suggestion: Suggestion) -> Suggestion? {
        let originalText = suggestion.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let minimalRewrite = suggestion.minimalRewrite.trimmingCharacters(in: .whitespacesAndNewlines)
        let naturalRewriteCandidate = suggestion.naturalRewrite.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonKo = suggestion.reasonKo.trimmingCharacters(in: .whitespacesAndNewlines)
        let intentKo = suggestion.intentKo.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !originalText.isEmpty, !reasonKo.isEmpty, !intentKo.isEmpty else { return nil }

        let naturalRewrite: String
        if isMeaningfullyDifferent(naturalRewriteCandidate, from: originalText) {
            naturalRewrite = naturalRewriteCandidate
        } else if isMeaningfullyDifferent(minimalRewrite, from: originalText) {
            naturalRewrite = minimalRewrite
        } else {
            return nil
        }

        return Suggestion(
            originalText: originalText,
            minimalRewrite: minimalRewrite,
            naturalRewrite: naturalRewrite,
            reasonKo: reasonKo,
            intentKo: intentKo
        )
    }

    private func isMeaningfullyDifferent(_ candidate: String, from original: String) -> Bool {
        let normalizedCandidate = normalizedComparisonText(candidate)
        let normalizedOriginal = normalizedComparisonText(original)
        guard !normalizedCandidate.isEmpty, !normalizedOriginal.isEmpty else { return false }
        return normalizedCandidate != normalizedOriginal
    }

    private func normalizedComparisonText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[[:punct:]]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
