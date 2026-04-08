import Foundation

struct ReviewService {
    struct BubbleReviewEnvelope: Decodable {
        let items: [BubbleReview]
    }

    struct BubbleReview: Decodable {
        let sourceSequence: Int
        let originalText: String
        let naturalRewrite: String
        let reasonKo: String
        let intentKo: String
        let recommendedPhrases: [RecommendedPhrase]
    }

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

    func parseBubbleReviews(from rawText: String) throws -> [BubbleReview] {
        let jsonPayload = extractJSONObject(from: rawText)
        let data = Data(jsonPayload.utf8)
        let envelope = try JSONDecoder().decode(BubbleReviewEnvelope.self, from: data)
        return envelope.items.compactMap(normalize)
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

    private func normalize(_ review: BubbleReview) -> BubbleReview? {
        let originalText = review.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let naturalRewrite = review.naturalRewrite.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonKo = review.reasonKo.trimmingCharacters(in: .whitespacesAndNewlines)
        let intentKo = review.intentKo.trimmingCharacters(in: .whitespacesAndNewlines)
        let recommendedPhrases = review.recommendedPhrases.compactMap { phrase -> RecommendedPhrase? in
            let expression = phrase.expressionEn.trimmingCharacters(in: .whitespacesAndNewlines)
            let usage = phrase.usageNoteKo.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !expression.isEmpty, !usage.isEmpty else { return nil }
            return RecommendedPhrase(expressionEn: expression, usageNoteKo: usage)
        }

        guard review.sourceSequence > 0, !originalText.isEmpty else { return nil }

        return BubbleReview(
            sourceSequence: review.sourceSequence,
            originalText: originalText,
            naturalRewrite: naturalRewrite.isEmpty ? originalText : naturalRewrite,
            reasonKo: reasonKo,
            intentKo: intentKo,
            recommendedPhrases: Array(recommendedPhrases.prefix(2))
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
