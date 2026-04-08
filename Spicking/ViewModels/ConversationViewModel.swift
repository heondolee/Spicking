import Combine
import Foundation
import SwiftData

private enum UserTranscriptSource {
    case local
    case remote
}

@MainActor
final class ConversationViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let topic: String

    @Published var phase: ConversationFlowPhase = .preparing
    @Published var connectionState: RealtimeConnectionState = .idle
    @Published var liveTranscriptLines: [LiveTranscriptLine] = []
    @Published var reviewCards: [ReviewCard] = []
    @Published var statusMessage: String = "세션을 준비하고 있어요…"
    @Published var errorMessage: String?
    @Published var assistantSpeaking = false
    @Published var isEndingSession = false
    @Published var isPreparingInitialCoachTurn = true
    @Published var isAwaitingInitialCoachResponse = true

    private let modelContext: ModelContext
    private let reviewService = ReviewService()
    private var audioEngineService: AudioEngineService?
    private var realtimeSessionService: RealtimeSessionService?
    private var sessionRecord: ConversationSession?
    private var transcriptEntriesByRemoteID: [String: TranscriptEntry] = [:]
    private var nextSequence = 0
    private var hasStarted = false
    private var activeUserRemoteItemID: String?
    private var activeUserTranscriptSource: UserTranscriptSource?
    private var activeUserLocalTranscriptFinalized = false
    private var initialCoachPlaybackStarted = false
    private var liveTranscriptSyncTask: Task<Void, Never>?
    private var pendingAssistantResponseTask: Task<Void, Never>?
    private var lastFinalizedUserRemoteItemID: String?
    private var lastAssistantResponseRequestedForUserItemID: String?

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

            statusMessage = "영어 코치와 연결 중이에요…"
            connectionState = .connecting
            try await audioEngine.start()
            audioEngine.inputEnabled = false
            audioEngineService = audioEngine
            realtimeSessionService = realtimeService

            try await realtimeService.connect(topic: topic)
            session.status = .live
            try modelContext.save()
            phase = .live
            statusMessage = "대화 준비가 끝났어요."
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    func endSession() async {
        guard !isEndingSession else { return }
        isEndingSession = true
        phase = .generatingReview
        statusMessage = "세션 리뷰를 생성하고 있어요…"

        audioEngineService?.stop()
        assistantSpeaking = false

        guard let sessionRecord else {
            fail(with: "세션 정보를 찾지 못했어요.")
            isEndingSession = false
            return
        }

        do {
            sessionRecord.status = .reviewing
            sessionRecord.endedAt = .now
            sessionRecord.durationSeconds = Int((sessionRecord.endedAt ?? .now).timeIntervalSince(sessionRecord.startedAt))
            try modelContext.save()

            if liveTranscriptLines.filter({ $0.role == .user && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count <= 1 {
                statusMessage = "이번 세션은 대화가 짧아서 리뷰를 만들기 어려웠어요. 다음에는 조금 더 길게 말해보세요."
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
            statusMessage = "리뷰가 준비됐어요."
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
            tags: [],
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
        pendingAssistantResponseTask?.cancel()
        audioEngineService?.stop()
        realtimeSessionService?.disconnect()
    }

    private func bind(audioEngine: AudioEngineService, realtimeService: RealtimeSessionService) {
        audioEngine.onAudioPCMData = { [weak realtimeService] data in
            realtimeService?.appendInputAudio(data)
        }
        audioEngine.onAssistantPlaybackChanged = { [weak self] isPlaying in
            self?.assistantSpeaking = isPlaying
        }
        audioEngine.onAssistantPlaybackFinished = { [weak self] itemID in
            Task { @MainActor [weak self] in
                self?.handleAssistantPlaybackFinished(itemID: itemID)
            }
        }
        audioEngine.onSpeechDetected = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleUserSpeechDetected()
            }
        }
        audioEngine.onLiveUserTranscription = { [weak self] text, isFinal in
            Task { @MainActor [weak self] in
                self?.handleLiveUserTranscription(text: text, isFinal: isFinal)
            }
        }

        realtimeService.onConnectionStateChanged = { [weak self] state in
            self?.connectionState = state
        }
        realtimeService.onAssistantAudioChunk = { [weak self] itemID, base64 in
            self?.handleAssistantOutputStarted()
            self?.audioEngineService?.enqueueAssistantAudio(base64: base64, itemID: itemID)
        }
        realtimeService.onAssistantSpeakingChanged = { [weak self] speaking in
            guard speaking == false else { return }
            self?.audioEngineService?.markAssistantStreamEnded()
        }
        realtimeService.onAssistantTranscriptUpdated = { [weak self] itemID, text, isFinal in
            self?.handleAssistantTranscript(itemID: itemID, text: text, isFinal: isFinal)
        }
        realtimeService.onUserTranscriptUpdated = { [weak self] itemID, text, isFinal in
            if isFinal {
                self?.finalizeUserTranscript(remoteItemID: itemID, text: text)
            } else {
                self?.handleRemoteUserTranscriptDelta(remoteItemID: itemID, text: text)
            }
        }
        realtimeService.onError = { [weak self] message in
            self?.errorMessage = message
        }
    }

    private func handleUserSpeechDetected() async {
        guard isPreparingInitialCoachTurn == false else { return }
        pendingAssistantResponseTask?.cancel()
        ensureUserTurnReserved()
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

    private func upsertTranscript(remoteItemID: String, role: TranscriptRole, text: String, isFinal: Bool, replaceStreamingText: Bool = false) {
        guard let sessionID = sessionRecord?.id else { return }
        let cleanedFinal = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let streamingText = text.trimmingCharacters(in: .newlines)
        guard !(isFinal ? cleanedFinal : streamingText).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let entry: TranscriptEntry
        if let existing = transcriptEntriesByRemoteID[remoteItemID] {
            entry = existing
            if isFinal {
                entry.text = cleanedFinal
            } else if replaceStreamingText {
                entry.text = streamingText
            } else {
                entry.text += streamingText
            }
        } else if role == .user, let activeUserRemoteItemID, let reservedEntry = transcriptEntriesByRemoteID[activeUserRemoteItemID] {
            transcriptEntriesByRemoteID.removeValue(forKey: activeUserRemoteItemID)
            reservedEntry.remoteItemID = remoteItemID
            entry = reservedEntry
            transcriptEntriesByRemoteID[remoteItemID] = entry
            if isFinal {
                entry.text = cleanedFinal
            } else if replaceStreamingText {
                entry.text = streamingText
            } else {
                entry.text += streamingText
            }
        } else {
            nextSequence += 1
            entry = TranscriptEntry(
                sessionID: sessionID,
                remoteItemID: remoteItemID,
                role: role,
                sequence: nextSequence,
                text: isFinal ? cleanedFinal : streamingText,
                startedAt: .now
            )
            transcriptEntriesByRemoteID[remoteItemID] = entry
            modelContext.insert(entry)
        }

        entry.isFinal = isFinal
        if isFinal {
            entry.endedAt = .now
            if role == .user {
                activeUserRemoteItemID = nil
                activeUserTranscriptSource = nil
                activeUserLocalTranscriptFinalized = false
            }
        }

        do {
            try modelContext.save()
        } catch {
            fail(with: error.localizedDescription)
        }

        scheduleLiveTranscriptSync()
    }

    private func handleLiveUserTranscription(text: String, isFinal: Bool) {
        guard isPreparingInitialCoachTurn == false else { return }
        guard activeUserTranscriptSource != .remote else { return }
        ensureUserTurnReserved()
        guard let activeUserRemoteItemID else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        activeUserTranscriptSource = .local
        activeUserLocalTranscriptFinalized = activeUserLocalTranscriptFinalized || isFinal

        upsertTranscript(
            remoteItemID: activeUserRemoteItemID,
            role: .user,
            text: cleaned,
            isFinal: false,
            replaceStreamingText: true
        )
    }

    private func ensureUserTurnReserved() {
        guard let sessionID = sessionRecord?.id else { return }
        guard activeUserRemoteItemID == nil else { return }

        nextSequence += 1
        let placeholderID = "pending_user_\(UUID().uuidString)"
        let entry = TranscriptEntry(
            sessionID: sessionID,
            remoteItemID: placeholderID,
            role: .user,
            sequence: nextSequence,
            text: "",
            startedAt: .now
        )
        transcriptEntriesByRemoteID[placeholderID] = entry
        activeUserRemoteItemID = placeholderID
        activeUserTranscriptSource = nil
        activeUserLocalTranscriptFinalized = false
        modelContext.insert(entry)
        try? modelContext.save()
    }

    private func handleRemoteUserTranscriptDelta(remoteItemID: String, text: String) {
        guard isPreparingInitialCoachTurn == false else { return }
        ensureUserTurnReserved()
        let shouldReplaceExistingText = activeUserTranscriptSource != .remote
        activeUserTranscriptSource = .remote
        upsertTranscript(
            remoteItemID: remoteItemID,
            role: .user,
            text: text,
            isFinal: false,
            replaceStreamingText: shouldReplaceExistingText
        )
    }

    private func finalizeUserTranscript(remoteItemID: String, text: String) {
        upsertTranscript(remoteItemID: remoteItemID, role: .user, text: text, isFinal: true)
        lastFinalizedUserRemoteItemID = remoteItemID
        scheduleAssistantReply()
    }

    private func handleAssistantTranscript(itemID: String, text: String, isFinal: Bool) {
        let transcript = isFinal
            ? text.trimmingCharacters(in: .whitespacesAndNewlines)
            : text.trimmingCharacters(in: .newlines)
        guard transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        handleAssistantOutputStarted()
        upsertTranscript(
            remoteItemID: itemID,
            role: .assistant,
            text: transcript,
            isFinal: isFinal,
            replaceStreamingText: isFinal
        )
    }

    private func handleAssistantOutputStarted() {
        pendingAssistantResponseTask?.cancel()
        finalizeActiveUserDraftIfNeeded()
        if let lastFinalizedUserRemoteItemID {
            lastAssistantResponseRequestedForUserItemID = lastFinalizedUserRemoteItemID
        }
        if isAwaitingInitialCoachResponse {
            isAwaitingInitialCoachResponse = false
        }
        initialCoachPlaybackStarted = true
    }

    private func finalizeActiveUserDraftIfNeeded() {
        guard let activeUserRemoteItemID,
              let entry = transcriptEntriesByRemoteID[activeUserRemoteItemID],
              entry.role == .user
        else { return }
        let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldKeepDraft = trimmed.isEmpty == false

        if shouldKeepDraft, trimmed.isEmpty == false {
            entry.text = trimmed
            entry.isFinal = true
            entry.endedAt = .now
        } else {
            transcriptEntriesByRemoteID.removeValue(forKey: activeUserRemoteItemID)
            modelContext.delete(entry)
        }

        self.activeUserRemoteItemID = nil
        activeUserTranscriptSource = nil
        activeUserLocalTranscriptFinalized = false
        try? modelContext.save()
        scheduleLiveTranscriptSync()
    }

    private func handleAssistantPlaybackFinished(itemID: String) {
        guard isPreparingInitialCoachTurn, initialCoachPlaybackStarted else { return }
        isPreparingInitialCoachTurn = false
        isAwaitingInitialCoachResponse = false
        audioEngineService?.inputEnabled = true
    }

    private func scheduleAssistantReply() {
        guard isPreparingInitialCoachTurn == false else { return }
        guard assistantSpeaking == false else { return }
        guard let realtimeSessionService else { return }
        guard let lastFinalizedUserRemoteItemID else { return }
        guard lastAssistantResponseRequestedForUserItemID != lastFinalizedUserRemoteItemID else { return }

        pendingAssistantResponseTask?.cancel()
        pendingAssistantResponseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            guard let self, Task.isCancelled == false else { return }
            guard self.assistantSpeaking == false else { return }
            guard self.activeUserRemoteItemID == nil else { return }
            guard self.lastFinalizedUserRemoteItemID == lastFinalizedUserRemoteItemID else { return }
            guard self.lastAssistantResponseRequestedForUserItemID != lastFinalizedUserRemoteItemID else { return }

            do {
                self.lastAssistantResponseRequestedForUserItemID = lastFinalizedUserRemoteItemID
                try await realtimeSessionService.requestAssistantReply()
            } catch {
                self.lastAssistantResponseRequestedForUserItemID = nil
                self.fail(with: error.localizedDescription)
            }
        }
    }

    private func scheduleLiveTranscriptSync() {
        liveTranscriptSyncTask?.cancel()
        liveTranscriptSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000)
            guard let self, Task.isCancelled == false else { return }
            self.syncLiveTranscriptLines()
        }
    }

    private func syncLiveTranscriptLines() {
        let lines = transcriptEntriesByRemoteID.values
            .sorted { $0.sequence < $1.sequence }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { entry in
                LiveTranscriptLine(
                    id: entry.remoteItemID,
                    role: entry.role,
                    text: entry.text.trimmingCharacters(in: .newlines),
                    isFinal: entry.isFinal,
                    wasInterrupted: entry.wasInterrupted
                )
            }
        liveTranscriptLines = lines
    }

    private func requestReviewWithRetry() async throws -> String {
        guard let realtimeSessionService else {
            throw NSError(domain: "ConversationViewModel", code: 0, userInfo: [NSLocalizedDescriptionKey: "실시간 세션 정보가 없어요."])
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
                tags: []
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
                isSaved: $0.isSaved
            )
        }
    }

    private func fetchSuggestion(id: UUID) -> ReviewSuggestion? {
        let descriptor = FetchDescriptor<ReviewSuggestion>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func fail(with message: String) {
        pendingAssistantResponseTask?.cancel()
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
