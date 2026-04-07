import Combine
import SwiftData
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var activeConversation: ConversationViewModel?
    @Published var alertMessage: String?

    func startConversation(topic: String, modelContext: ModelContext) {
        let cleanedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTopic = cleanedTopic.isEmpty ? "daily life and small talk" : cleanedTopic
        activeConversation = ConversationViewModel(topic: finalTopic, modelContext: modelContext)
    }

    func finishConversationFlow() {
        activeConversation = nil
    }
}
