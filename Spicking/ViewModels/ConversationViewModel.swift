import Combine
import Foundation
import SwiftData

@MainActor
final class ConversationViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let topic: String

    @Published var phase: ConversationFlowPhase = .preparing
    @Published var connectionState: RealtimeConnectionState = .idle
    @Published var liveTranscriptLines: [LiveTranscriptLine] = []
    @Published var reviewCards: [ReviewCard] = []
    @Published var statusMessage: String = "Preparing your session..."
    @Published var errorMessage: String?
    @Published var assistantSpeaking = false
    @Published var isEndingSession = false

    private let modelContext: ModelContext
    private let reviewService = ReviewService()
    private var audioEngineService: AudioEngineService?
    private var realtimeSessionService: RealtimeSessionService?
    private var sessionRecord: ConversationSession?
    private var transcriptEntriesByRemoteID: [String: TranscriptEntry] = [:]
    private var nextSequence = 0
    private var hasStarted = false

    init(topic: String, modelContext: ModelContext) {
        self.topic = topic
        self.modelContext = modelContext
    }

    func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            let configuration = try AppConfigurationLoader.load()
            let audioEngine = AudioEngineService()
            let realtimeService = RealtimeSessionService(configuration: configuration)
            bind(audioEngine: audioEngine, realtimeService: realtimeService)

            let session = ConversationSession(topic: topic)
            session.status = .preparing
            modelContext.insert(session)
            try modelContext.save()
            sessionRecord = session

            statusMessage = "Connecting to your speaking coach..."
            connectionState = .connecting
            try await audioEngine.start()
            audioEngineService = audioEngine
            realtimeSessionService = realtimeService

            try await realtimeService.connect(topic: topic)
            session.status = .live
            try modelContext.save()
            phase = .live
            statusMessage = "Speak naturally. You can interrupt the assistant anytime."
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    func endSession() async {
        guard !isEndingSession else { return }
        isEndingSession = true
        phase = .generatingReview
        statusMessage = "Generating your review..."

        audioEngineService?.stop()
        assistantSpeaking = false

        guard let sessionRecord else {
            fail(with: "No session found.")
            isEndingSession = false
            return
        }

        do {
            sessionRecord.status = .reviewing
            sessionRecord.endedAt = .now
            sessionRecord.durationSeconds = Int((sessionRecord.endedAt ?? .now).timeIntervalSince(sessionRecord.startedAt))
            try modelContext.save()

            if liveTranscriptLines.filter({ $0.role == .user && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count <= 1 {
                statusMessage = "Not enough spoken English yet. Try a longer session next time."
                reviewCards = []
                sessionRecord.status = .completed
                try modelContext.save()
                phase = .review
                realtimeSessionService?.disconnect()
                isEndingSession = false
                return
            }

            let rawReview = try await requestReviewWithRetry()
            let suggestions = try reviewService.parseSuggestions(from: rawReview)
            reviewCards = try persistReviewSuggestions(suggestions, sessionID: sessionRecord.id)

            sessionRecord.status = .completed
            try modelContext.save()
            phase = .review
            statusMessage = "Review ready"
            realtimeSessionService?.disconnect()
        } catch {
            fail(with: error.localizedDescription)
        }

        isEndingSession = false
    }

    func savePhraseCard(for card: ReviewCard) {
        guard let suggestion = fetchSuggestion(id: card.id), let sessionID = sessionRecord?.id else { return }
        guard suggestion.isSaved == false else { return }

        let phraseCard = PhraseCard(
            intentKo: suggestion.intentKo,
            expressionEn: suggestion.naturalRewrite,
            sourceOriginalText: suggestion.originalText,
            naturalRewrite: suggestion.naturalRewrite,
            usageNoteKo: suggestion.reasonKo,
            tags: suggestion.tags,
            sourceSessionID: sessionID
        )
        modelContext.insert(phraseCard)
        suggestion.isSaved = true

        do {
            try modelContext.save()
            if let index = reviewCards.firstIndex(where: { $0.id == card.id }) {
                reviewCards[index].isSaved = true
            }
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    func close() {
        audioEngineService?.stop()
        realtimeSessionService?.disconnect()
    }

    private func bind(audioEngine: AudioEngineService, realtimeService: RealtimeSessionService) {
        audioEngine.onAudioPCMData = { [weak realtimeService] data in
            realtimeService?.appendInputAudio(data)
        }
        audioEngine.onSpeechDetected = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleLocalSpeechDetected()
            }
        }

        realtimeService.onConnectionStateChanged = { [weak self] state in
            self?.connectionState = state
        }
        realtimeService.onAssistantAudioChunk = { [weak self] itemID, base64 in
            self?.assistantSpeaking = true
            self?.audioEngineService?.enqueueAssistantAudio(base64: base64, itemID: itemID)
        }
        realtimeService.onAssistantSpeakingChanged = { [weak self] speaking in
            self?.assistantSpeaking = speaking
        }
        realtimeService.onAssistantTranscriptUpdated = { [weak self] itemID, text, isFinal in
            self?.upsertTranscript(remoteItemID: itemID, role: .assistant, text: text, isFinal: isFinal)
        }
        realtimeService.onUserTranscriptUpdated = { [weak self] itemID, text, isFinal in
            self?.upsertTranscript(remoteItemID: itemID, role: .user, text: text, isFinal: isFinal)
        }
        realtimeService.onServerSpeechStarted = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleLocalSpeechDetected()
            }
        }
        realtimeService.onError = { [weak self] message in
            self?.errorMessage = message
        }
    }

    private func handleLocalSpeechDetected() async {
        guard assistantSpeaking else { return }

        let playbackSnapshot = audioEngineService?.interruptPlayback()
        assistantSpeaking = false
        if let currentAssistantID = playbackSnapshot?.itemID,
           let entry = transcriptEntriesByRemoteID[currentAssistantID] {
            entry.wasInterrupted = true
            try? modelContext.save()
            syncLiveTranscriptLines()
        }
        await realtimeSessionService?.interruptActiveResponse(playbackSnapshot: playbackSnapshot)
    }

    private func upsertTranscript(remoteItemID: String, role: TranscriptRole, text: String, isFinal: Bool) {
        guard let sessionID = sessionRecord?.id else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let entry: TranscriptEntry
        if let existing = transcriptEntriesByRemoteID[remoteItemID] {
            entry = existing
            if isFinal {
                entry.text = cleaned
            } else {
                entry.text += cleaned
            }
        } else {
            nextSequence += 1
            entry = TranscriptEntry(
                sessionID: sessionID,
                remoteItemID: remoteItemID,
                role: role,
                sequence: nextSequence,
                text: cleaned,
                startedAt: .now
            )
            transcriptEntriesByRemoteID[remoteItemID] = entry
            modelContext.insert(entry)
        }

        entry.isFinal = isFinal
        if isFinal {
            entry.endedAt = .now
        }

        do {
            try modelContext.save()
        } catch {
            fail(with: error.localizedDescription)
        }

        syncLiveTranscriptLines()
    }

    private func syncLiveTranscriptLines() {
        let lines = transcriptEntriesByRemoteID.values
            .sorted { $0.sequence < $1.sequence }
            .map {
                LiveTranscriptLine(
                    id: $0.remoteItemID,
                    role: $0.role,
                    text: $0.text,
                    isFinal: $0.isFinal,
                    wasInterrupted: $0.wasInterrupted
                )
            }
        liveTranscriptLines = lines
    }

    private func requestReviewWithRetry() async throws -> String {
        guard let realtimeSessionService else {
            throw NSError(domain: "ConversationViewModel", code: 0, userInfo: [NSLocalizedDescriptionKey: "Realtime session missing."])
        }

        do {
            return try await realtimeSessionService.requestReviewJSON()
        } catch {
            return try await realtimeSessionService.requestReviewJSON()
        }
    }

    private func persistReviewSuggestions(_ suggestions: [ReviewService.Suggestion], sessionID: UUID) throws -> [ReviewCard] {
        let existing = try modelContext.fetch(FetchDescriptor<ReviewSuggestion>(predicate: #Predicate { $0.sessionID == sessionID }))
        for item in existing {
            modelContext.delete(item)
        }

        let models = suggestions.prefix(5).map {
            ReviewSuggestion(
                sessionID: sessionID,
                originalText: $0.originalText,
                minimalRewrite: $0.minimalRewrite,
                naturalRewrite: $0.naturalRewrite,
                reasonKo: $0.reasonKo,
                intentKo: $0.intentKo,
                tags: $0.tags
            )
        }
        for item in models {
            modelContext.insert(item)
        }
        try modelContext.save()

        return models.map {
            ReviewCard(
                id: $0.id,
                originalText: $0.originalText,
                minimalRewrite: $0.minimalRewrite,
                naturalRewrite: $0.naturalRewrite,
                reasonKo: $0.reasonKo,
                intentKo: $0.intentKo,
                tags: $0.tags,
                isSaved: $0.isSaved
            )
        }
    }

    private func fetchSuggestion(id: UUID) -> ReviewSuggestion? {
        let descriptor = FetchDescriptor<ReviewSuggestion>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func fail(with message: String) {
        errorMessage = message
        connectionState = .failed
        phase = .failed(message)
        statusMessage = message
        assistantSpeaking = false
        audioEngineService?.stop()
        realtimeSessionService?.disconnect()

        if let sessionRecord {
            sessionRecord.status = .failed
            sessionRecord.endedAt = .now
            sessionRecord.durationSeconds = Int((sessionRecord.endedAt ?? .now).timeIntervalSince(sessionRecord.startedAt))
            try? modelContext.save()
        }
    }
}
