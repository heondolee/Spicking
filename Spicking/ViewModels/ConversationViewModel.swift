import Combine
import Foundation
import NaturalLanguage
import QuartzCore
import SwiftData

private enum UserTranscriptSource {
    case local
    case remote
}

enum ConversationInputMode: String {
    case automatic
    case manual
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
    @Published var inputMode: ConversationInputMode = .automatic
    @Published var isPaused = false
    @Published var isSendingManualTurn = false

    private let modelContext: ModelContext
    private let reviewService = ReviewService()
    private var audioEngineService: AudioEngineService?
    private var realtimeSessionService: RealtimeSessionService?
    private var sessionRecord: ConversationSession?
    private var transcriptEntriesByRemoteID: [String: TranscriptEntry] = [:]
    private var locallyConfirmedUserItemIDs: Set<String> = []
    private var locallyFinalizedUserItemIDs: Set<String> = []
    private var stronglyConfirmedUserItemIDs: Set<String> = []
    private var visibleLocalUserItemIDs: Set<String> = []
    private var replyEligibleUserItemIDs: Set<String> = []
    private var nextSequence = 0
    private var hasStarted = false
    private var activeUserRemoteItemID: String?
    private var activeUserTranscriptSource: UserTranscriptSource?
    private var activeUserLocalTranscriptFinalized = false
    private var activeUserHadVisibleLocalTranscript = false
    private var activeUserTurnDetectedSpeech = false
    private var activeUserSpeechDetectionCount = 0
    private var initialCoachPlaybackStarted = false
    private var liveTranscriptSyncTask: Task<Void, Never>?
    private var pendingAssistantResponseTask: Task<Void, Never>?
    private var lastFinalizedUserRemoteItemID: String?
    private var lastAssistantResponseRequestedForUserItemID: String?
    private var englishRecoveryAttemptsByUserItemID: [String: Int] = [:]
    private var suppressNewUserTurnsUntil: CFTimeInterval = 0
    private var awaitingAssistantReplyStart = false

    var completedSession: ConversationSession? {
        sessionRecord
    }

    private func logTurnGate(_ message: String) {
#if DEBUG
        print("[TurnGate] \(message)")
#endif
    }

    var canSendCurrentTurnManually: Bool {
        guard inputMode == .manual else { return false }
        guard isPaused == false else { return false }
        guard assistantSpeaking == false else { return false }
        guard isPreparingInitialCoachTurn == false else { return false }
        guard isSendingManualTurn == false else { return false }
        guard let candidateItemID = manualSendCandidateItemID,
              let entry = transcriptEntriesByRemoteID[candidateItemID]
        else {
            return false
        }
        guard locallyFinalizedUserItemIDs.contains(candidateItemID) else { return false }

        return entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

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
            audioEngineService = audioEngine
            realtimeSessionService = realtimeService
            syncAudioInputPolicy()

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
        statusMessage = "대화를 정리하고 있어요…"

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
                statusMessage = "이번 대화는 짧아서 수정할 문장이 많지 않았어요."
                reviewCards = []
                sessionRecord.status = .completed
                try modelContext.save()
                phase = .review
                realtimeSessionService?.disconnect()
                isEndingSession = false
                return
            }

            let rawReview = try await requestConversationReviewWithRetry()
            let suggestions = try reviewService.parseBubbleReviews(from: rawReview)
            reviewCards = try persistBubbleReviews(suggestions, sessionID: sessionRecord.id)

            sessionRecord.status = .completed
            try modelContext.save()
            phase = .review
            statusMessage = "대화 다시보기가 준비됐어요."
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

    func toggleInputMode() {
        inputMode = inputMode == .automatic ? .manual : .automatic
        if inputMode == .manual {
            awaitingAssistantReplyStart = false
        }
        syncAudioInputPolicy()
        if inputMode == .automatic {
            scheduleAssistantReply()
        } else {
            pendingAssistantResponseTask?.cancel()
        }
    }

    func togglePause() async {
        isPaused.toggle()
        pendingAssistantResponseTask?.cancel()
        syncAudioInputPolicy()

        guard isPaused else { return }
        guard assistantSpeaking else { return }

        let playbackSnapshot = audioEngineService?.interruptPlayback()
        assistantSpeaking = false
        await realtimeSessionService?.interruptActiveResponse(playbackSnapshot: playbackSnapshot)
    }

    func sendCurrentTurnManually() async {
        guard inputMode == .manual else { return }
        guard isPaused == false else { return }
        guard assistantSpeaking == false else { return }
        guard isSendingManualTurn == false else { return }
        guard let realtimeSessionService else { return }
        guard let candidateItemID = manualSendCandidateItemID,
              let entry = transcriptEntriesByRemoteID[candidateItemID]
        else { return }

        isSendingManualTurn = true
        defer { isSendingManualTurn = false }

        let cleaned = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return }

        if entry.isFinal == false {
            guard shouldKeepFinalizedUserTurn(remoteItemID: candidateItemID, text: cleaned) else {
                discardUserTurn(remoteItemID: candidateItemID)
                return
            }

            upsertTranscript(remoteItemID: candidateItemID, role: .user, text: cleaned, isFinal: true)
            syncLiveTranscriptLines()
            guard hasVisibleUserBubble(for: candidateItemID) else {
                discardUserTurn(remoteItemID: candidateItemID)
                return
            }
            replyEligibleUserItemIDs.insert(candidateItemID)
            lastFinalizedUserRemoteItemID = candidateItemID
        }

        if lastAssistantResponseRequestedForUserItemID == candidateItemID {
            return
        }

        guard canRespond(to: candidateItemID) else { return }

        do {
            try await realtimeSessionService.submitUserTextTurn(cleaned)
            lastAssistantResponseRequestedForUserItemID = candidateItemID
            try await realtimeSessionService.requestAssistantReply()
        } catch {
            lastAssistantResponseRequestedForUserItemID = nil
            fail(with: error.localizedDescription)
        }
    }

    private var manualSendCandidateItemID: String? {
        if let activeUserRemoteItemID,
           let entry = transcriptEntriesByRemoteID[activeUserRemoteItemID],
           entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return activeUserRemoteItemID
        }

        if let lastFinalizedUserRemoteItemID,
           let entry = transcriptEntriesByRemoteID[lastFinalizedUserRemoteItemID],
           entry.role == .user,
           entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           lastAssistantResponseRequestedForUserItemID != lastFinalizedUserRemoteItemID {
            return lastFinalizedUserRemoteItemID
        }

        return nil
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
        let now = CACurrentMediaTime()
        if assistantSpeaking == false,
           activeUserRemoteItemID == nil,
           now < suppressNewUserTurnsUntil {
            logTurnGate("ignored speech detection during cooldown")
            return
        }
        if activeUserRemoteItemID != nil || assistantSpeaking {
            pendingAssistantResponseTask?.cancel()
        }
        activeUserTurnDetectedSpeech = true
        activeUserSpeechDetectionCount += 1
        if activeUserSpeechDetectionCount >= 3, let activeUserRemoteItemID {
            stronglyConfirmedUserItemIDs.insert(activeUserRemoteItemID)
        }
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
            if locallyConfirmedUserItemIDs.contains(activeUserRemoteItemID) {
                locallyConfirmedUserItemIDs.remove(activeUserRemoteItemID)
                locallyConfirmedUserItemIDs.insert(remoteItemID)
            }
            if locallyFinalizedUserItemIDs.contains(activeUserRemoteItemID) {
                locallyFinalizedUserItemIDs.remove(activeUserRemoteItemID)
                locallyFinalizedUserItemIDs.insert(remoteItemID)
            }
            if stronglyConfirmedUserItemIDs.contains(activeUserRemoteItemID) {
                stronglyConfirmedUserItemIDs.remove(activeUserRemoteItemID)
                stronglyConfirmedUserItemIDs.insert(remoteItemID)
            }
            if visibleLocalUserItemIDs.contains(activeUserRemoteItemID) {
                visibleLocalUserItemIDs.remove(activeUserRemoteItemID)
                visibleLocalUserItemIDs.insert(remoteItemID)
            }
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
                resetActiveUserTurnState()
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
        let now = CACurrentMediaTime()
        if activeUserRemoteItemID == nil, now < suppressNewUserTurnsUntil {
            logTurnGate("ignored local transcript during cooldown text=\(text)")
            return
        }
        pendingAssistantResponseTask?.cancel()
        ensureUserTurnReserved()
        guard let activeUserRemoteItemID else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        activeUserTranscriptSource = .local
        activeUserLocalTranscriptFinalized = activeUserLocalTranscriptFinalized || isFinal
        activeUserHadVisibleLocalTranscript = true
        locallyConfirmedUserItemIDs.insert(activeUserRemoteItemID)
        visibleLocalUserItemIDs.insert(activeUserRemoteItemID)
        if activeUserSpeechDetectionCount >= 3 {
            stronglyConfirmedUserItemIDs.insert(activeUserRemoteItemID)
        }
        if isFinal {
            locallyFinalizedUserItemIDs.insert(activeUserRemoteItemID)
            stronglyConfirmedUserItemIDs.insert(activeUserRemoteItemID)
            finalizeLocalUserTranscript(remoteItemID: activeUserRemoteItemID, text: cleaned)
        } else {
            upsertTranscript(
                remoteItemID: activeUserRemoteItemID,
                role: .user,
                text: cleaned,
                isFinal: false,
                replaceStreamingText: true
            )
        }
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
        resetActiveUserTurnState()
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
        guard shouldKeepFinalizedUserTurn(remoteItemID: remoteItemID, text: text) else {
            discardUserTurn(remoteItemID: remoteItemID)
            return
        }
        upsertTranscript(remoteItemID: remoteItemID, role: .user, text: text, isFinal: true)
        syncLiveTranscriptLines()
        guard hasVisibleUserBubble(for: remoteItemID) else {
            discardUserTurn(remoteItemID: remoteItemID)
            return
        }
        replyEligibleUserItemIDs.insert(remoteItemID)
        lastFinalizedUserRemoteItemID = remoteItemID
        scheduleAssistantReply()
    }

    private func handleAssistantTranscript(itemID: String, text: String, isFinal: Bool) {
        let transcript = isFinal
            ? text.trimmingCharacters(in: .whitespacesAndNewlines)
            : text.trimmingCharacters(in: .newlines)
        guard transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }

        if shouldRejectAssistantTranscript(transcript, isFinal: isFinal) {
            Task { @MainActor [weak self] in
                await self?.handleInvalidAssistantResponse(itemID: itemID)
            }
            return
        }

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
        suppressNewUserTurnsUntil = 0
        awaitingAssistantReplyStart = false
        syncAudioInputPolicy()
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
        resetActiveUserTurnState()
        try? modelContext.save()
        scheduleLiveTranscriptSync()
    }

    private func finalizeLocalUserTranscript(remoteItemID: String, text: String) {
        logTurnGate("local final candidate id=\(remoteItemID) text=\(text)")
        guard shouldKeepFinalizedUserTurn(remoteItemID: remoteItemID, text: text) else {
            logTurnGate("discard local final id=\(remoteItemID)")
            discardUserTurn(remoteItemID: remoteItemID)
            return
        }
        upsertTranscript(remoteItemID: remoteItemID, role: .user, text: text, isFinal: true)
        syncLiveTranscriptLines()
        guard hasVisibleUserBubble(for: remoteItemID) else {
            logTurnGate("discard invisible local final id=\(remoteItemID)")
            discardUserTurn(remoteItemID: remoteItemID)
            return
        }
        replyEligibleUserItemIDs.insert(remoteItemID)
        lastFinalizedUserRemoteItemID = remoteItemID
        suppressNewUserTurnsUntil = CACurrentMediaTime() + 0.9
        awaitingAssistantReplyStart = true
        syncAudioInputPolicy()
        logTurnGate("accepted local final id=\(remoteItemID)")
        scheduleAssistantReply()
    }

    private func shouldKeepFinalizedUserTurn(remoteItemID: String, text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return false }
        guard visibleLocalUserItemIDs.contains(remoteItemID) else { return false }
        guard locallyFinalizedUserItemIDs.contains(remoteItemID) else { return false }
        guard hasConfirmedUserSpeech(for: cleaned) else { return false }

        if hasSufficientSpokenContent(cleaned) {
            return true
        }

        return activeUserTranscriptSource == .local
            && activeUserLocalTranscriptFinalized
            && cleaned.count >= 6
    }

    private func hasConfirmedUserSpeech(for text: String) -> Bool {
        if let activeUserRemoteItemID, stronglyConfirmedUserItemIDs.contains(activeUserRemoteItemID) {
            return true
        }

        return activeUserHadVisibleLocalTranscript
            && activeUserTurnDetectedSpeech
            && activeUserSpeechDetectionCount >= 2
            && text.count >= 8
    }

    private func hasSufficientSpokenContent(_ text: String) -> Bool {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        return wordCount >= 2 || text.count >= 10
    }

    private func discardUserTurn(remoteItemID: String) {
        logTurnGate("discard turn id=\(remoteItemID)")
        pendingAssistantResponseTask?.cancel()
        awaitingAssistantReplyStart = false
        syncAudioInputPolicy()
        if let entry = transcriptEntriesByRemoteID.removeValue(forKey: remoteItemID) {
            modelContext.delete(entry)
        }
        locallyConfirmedUserItemIDs.remove(remoteItemID)
        locallyFinalizedUserItemIDs.remove(remoteItemID)
        stronglyConfirmedUserItemIDs.remove(remoteItemID)
        visibleLocalUserItemIDs.remove(remoteItemID)
        replyEligibleUserItemIDs.remove(remoteItemID)
        if activeUserRemoteItemID == remoteItemID {
            activeUserRemoteItemID = nil
        }
        resetActiveUserTurnState()
        try? modelContext.save()
        scheduleLiveTranscriptSync()
    }

    private func handleAssistantPlaybackFinished(itemID: String) {
        guard isPreparingInitialCoachTurn, initialCoachPlaybackStarted else { return }
        isPreparingInitialCoachTurn = false
        isAwaitingInitialCoachResponse = false
        syncAudioInputPolicy()
    }

    private func scheduleAssistantReply() {
        guard inputMode == .automatic else { return }
        guard isPaused == false else { return }
        guard isPreparingInitialCoachTurn == false else { return }
        guard assistantSpeaking == false else { return }
        guard let realtimeSessionService else { return }
        guard let lastFinalizedUserRemoteItemID else { return }
        guard lastAssistantResponseRequestedForUserItemID != lastFinalizedUserRemoteItemID else { return }
        guard canRespond(to: lastFinalizedUserRemoteItemID) else { return }

        pendingAssistantResponseTask?.cancel()
        pendingAssistantResponseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, Task.isCancelled == false else { return }
            guard self.assistantSpeaking == false else { return }
            guard self.activeUserRemoteItemID == nil else { return }
            guard self.lastFinalizedUserRemoteItemID == lastFinalizedUserRemoteItemID else { return }
            guard self.lastAssistantResponseRequestedForUserItemID != lastFinalizedUserRemoteItemID else { return }
            guard self.canRespond(to: lastFinalizedUserRemoteItemID) else { return }

            do {
                guard let entry = self.transcriptEntriesByRemoteID[lastFinalizedUserRemoteItemID] else { return }
                let cleaned = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleaned.isEmpty == false else { return }

                self.logTurnGate("replying to id=\(lastFinalizedUserRemoteItemID) text=\(cleaned)")
                self.lastAssistantResponseRequestedForUserItemID = lastFinalizedUserRemoteItemID
                try await realtimeSessionService.submitUserTextTurn(cleaned)
                try await realtimeSessionService.requestAssistantReply()
            } catch {
                self.awaitingAssistantReplyStart = false
                self.syncAudioInputPolicy()
                self.lastAssistantResponseRequestedForUserItemID = nil
                self.fail(with: error.localizedDescription)
            }
        }
    }

    private func canRespond(to remoteItemID: String) -> Bool {
        guard let entry = transcriptEntriesByRemoteID[remoteItemID], entry.role == .user, entry.isFinal else {
            return false
        }
        guard replyEligibleUserItemIDs.contains(remoteItemID) else { return false }
        guard hasVisibleUserBubble(for: remoteItemID) else { return false }
        let cleaned = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return false }
        return hasSufficientSpokenContent(cleaned)
    }

    private func scheduleLiveTranscriptSync() {
        liveTranscriptSyncTask?.cancel()
        liveTranscriptSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000)
            guard let self, Task.isCancelled == false else { return }
            self.syncLiveTranscriptLines()
        }
    }

    private func resetActiveUserTurnState() {
        activeUserTranscriptSource = nil
        activeUserLocalTranscriptFinalized = false
        activeUserHadVisibleLocalTranscript = false
        activeUserTurnDetectedSpeech = false
        activeUserSpeechDetectionCount = 0
    }

    private func hasVisibleUserBubble(for remoteItemID: String) -> Bool {
        liveTranscriptLines.contains {
            $0.id == remoteItemID
                && $0.role == .user
                && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private func shouldRejectAssistantTranscript(_ text: String, isFinal: Bool) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return false }

        if containsClearlyNonEnglishScript(cleaned) {
            return true
        }

        guard isFinal else { return false }
        guard cleaned.count >= 18 || cleaned.split(whereSeparator: \.isWhitespace).count >= 4 else { return false }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(cleaned)
        if let language = recognizer.dominantLanguage, language != .english {
            return true
        }

        return false
    }

    private func containsClearlyNonEnglishScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF, // Hangul
                 0x3040...0x30FF, // Japanese
                 0x4E00...0x9FFF, // CJK
                 0x0600...0x06FF, // Arabic
                 0x0400...0x04FF: // Cyrillic
                return true
            default:
                return false
            }
        }
    }

    private func handleInvalidAssistantResponse(itemID: String) async {
        let playbackSnapshot = audioEngineService?.interruptPlayback()
        assistantSpeaking = false
        await realtimeSessionService?.interruptActiveResponse(playbackSnapshot: playbackSnapshot)

        if let entry = transcriptEntriesByRemoteID.removeValue(forKey: itemID) {
            modelContext.delete(entry)
            try? modelContext.save()
            syncLiveTranscriptLines()
        }

        let retryKey = lastFinalizedUserRemoteItemID ?? "__kickoff__"
        let attempts = englishRecoveryAttemptsByUserItemID[retryKey, default: 0]
        guard attempts < 1 else { return }
        englishRecoveryAttemptsByUserItemID[retryKey] = attempts + 1

        do {
            try await realtimeSessionService?.requestAssistantReply(customInstructions: """
            Your previous reply was not acceptable because it was not fully in English.
            Restart your reply and answer in natural spoken English only.
            Do not use Korean, Spanish, Japanese, Chinese, or any other non-English language.
            If the user used a Korean word, explain it briefly in simple English only, then continue the conversation in English.
            Keep the reply short and ask exactly one follow-up question.
            """)
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    private func syncAudioInputPolicy() {
        let shouldCaptureInput = isPaused == false
            && isPreparingInitialCoachTurn == false
            && !(inputMode == .automatic && awaitingAssistantReplyStart)
        audioEngineService?.setInputEnabled(shouldCaptureInput)
        audioEngineService?.streamsInputAudioToServer = false
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

    private func requestConversationReviewWithRetry() async throws -> String {
        guard let realtimeSessionService else {
            throw NSError(domain: "ConversationViewModel", code: 0, userInfo: [NSLocalizedDescriptionKey: "실시간 세션 정보가 없어요."])
        }

        let transcript = makeConversationReviewTranscript()
        do {
            return try await realtimeSessionService.requestConversationReviewJSON(transcript: transcript)
        } catch {
            return try await realtimeSessionService.requestConversationReviewJSON(transcript: transcript)
        }
    }

    private func makeConversationReviewTranscript() -> String {
        transcriptEntriesByRemoteID.values
            .sorted { $0.sequence < $1.sequence }
            .filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .map { entry in
                "[\(entry.sequence)] [\(entry.role.rawValue)] \(entry.text.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            .joined(separator: "\n")
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

    private func persistBubbleReviews(_ suggestions: [ReviewService.BubbleReview], sessionID: UUID) throws -> [ReviewCard] {
        let existing = try modelContext.fetch(FetchDescriptor<ReviewSuggestion>(predicate: #Predicate { $0.sessionID == sessionID }))
        for item in existing {
            modelContext.delete(item)
        }

        let userEntriesBySequence = Dictionary(
            uniqueKeysWithValues: transcriptEntriesByRemoteID.values
                .filter { $0.role == .user }
                .map { ($0.sequence, $0) }
        )

        let models = suggestions.compactMap { suggestion -> ReviewSuggestion? in
            guard let sourceEntry = userEntriesBySequence[suggestion.sourceSequence] else { return nil }
            return ReviewSuggestion(
                sessionID: sessionID,
                sourceSequence: suggestion.sourceSequence,
                sourceRemoteItemID: sourceEntry.remoteItemID,
                originalText: suggestion.originalText,
                minimalRewrite: suggestion.naturalRewrite,
                naturalRewrite: suggestion.naturalRewrite,
                reasonKo: suggestion.reasonKo,
                intentKo: suggestion.intentKo,
                tags: [],
                recommendedPhrases: suggestion.recommendedPhrases
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
                minimalRewrite: $0.naturalRewrite,
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
