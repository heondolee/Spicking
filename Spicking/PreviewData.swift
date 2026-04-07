import SwiftData

enum PreviewData {
    @MainActor
    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            ConversationSession.self,
            TranscriptEntry.self,
            ReviewSuggestion.self,
            PhraseCard.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])

        let context = container.mainContext
        let session = ConversationSession(topic: "weekend plans", status: .completed, durationSeconds: 780)
        context.insert(session)
        context.insert(
            PhraseCard(
                intentKo: "의견을 부드럽게 말하기",
                expressionEn: "I get what you mean, but I see it a little differently.",
                sourceOriginalText: "I understand but my think is different.",
                naturalRewrite: "I get what you mean, but I see it a little differently.",
                usageNoteKo: "상대 의견을 인정하면서 부드럽게 반대할 때 좋아요.",
                tags: [],
                sourceSessionID: session.id
            )
        )
        return container
    }
}
