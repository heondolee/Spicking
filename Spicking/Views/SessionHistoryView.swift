import AVFoundation
import Combine
import CryptoKit
import SwiftData
import SwiftUI

struct SessionHistoryView: View {
    private enum TranscriptContainerStyle {
        static let topRadius: CGFloat = 24
        static let bottomRadius: CGFloat = 50
    }

    @Environment(\.modelContext) private var modelContext

    let session: ConversationSession
    let onDone: (() -> Void)?

    @Query private var entries: [TranscriptEntry]
    @Query private var suggestions: [ReviewSuggestion]
    @Query private var phraseCards: [PhraseCard]

    @StateObject private var speechPlayer = BubbleSpeechPlayer()

    init(session: ConversationSession, onDone: (() -> Void)? = nil) {
        self.session = session
        self.onDone = onDone
        let sessionID = session.id
        _entries = Query(
            filter: #Predicate<TranscriptEntry> { entry in
                entry.sessionID == sessionID
            },
            sort: [SortDescriptor(\TranscriptEntry.sequence, order: .forward)]
        )
        _suggestions = Query(
            filter: #Predicate<ReviewSuggestion> { suggestion in
                suggestion.sessionID == sessionID
            },
            sort: [SortDescriptor(\ReviewSuggestion.sourceSequence, order: .forward)]
        )
        _phraseCards = Query(
            filter: #Predicate<PhraseCard> { card in
                card.sourceSessionID == sessionID
            },
            sort: [SortDescriptor(\PhraseCard.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        ZStack {
            SpickingBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()

                    Text(
                        session.startedAt.formatted(
                            Date.FormatStyle(date: .long, time: .shortened)
                                .locale(Locale(identifier: "ko_KR"))
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                HStack {
                    PromptChip(title: session.topic, isSelected: true)
                    Spacer(minLength: 0)
                }

                historyTranscriptArea
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .navigationTitle("대화 다시 보기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료", action: onDone)
                }
            }
        }
    }

    private var historyTranscriptArea: some View {
        ZStack {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: TranscriptContainerStyle.topRadius,
                    bottomLeading: TranscriptContainerStyle.bottomRadius,
                    bottomTrailing: TranscriptContainerStyle.bottomRadius,
                    topTrailing: TranscriptContainerStyle.topRadius
                ),
                style: .continuous
            )
            .fill(Color.white.opacity(0.60))
            .overlay(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: TranscriptContainerStyle.topRadius,
                        bottomLeading: TranscriptContainerStyle.bottomRadius,
                        bottomTrailing: TranscriptContainerStyle.bottomRadius,
                        topTrailing: TranscriptContainerStyle.topRadius
                    ),
                    style: .continuous
                )
                .stroke(.white.opacity(0.86), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 22, y: 12)

            ScrollView {
                LazyVStack(spacing: 14) {
                    if entries.isEmpty {
                        Text("복기할 대화 내용이 아직 없어요.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(entries) { entry in
                            HistoryTranscriptBubble(
                                entry: entry,
                                suggestion: suggestion(for: entry),
                                savedBubbleKeys: savedBubbleKeys,
                                onSpeak: { bubbleID, text in
                                    speechPlayer.speak(bubbleID: bubbleID, text: text)
                                },
                                onToggleSave: { payload in
                                    toggleSavedBubble(payload)
                                },
                                activeBubbleID: speechPlayer.activeBubbleID,
                                loadingBubbleID: speechPlayer.loadingBubbleID
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: TranscriptContainerStyle.topRadius,
                        bottomLeading: TranscriptContainerStyle.bottomRadius,
                        bottomTrailing: TranscriptContainerStyle.bottomRadius,
                        topTrailing: TranscriptContainerStyle.topRadius
                    ),
                    style: .continuous
                )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var savedBubbleKeys: Set<String> {
        Set(phraseCards.map { bubbleSaveKey(sourceOriginalText: $0.sourceOriginalText, expressionEn: $0.expressionEn) })
    }

    private func suggestion(for entry: TranscriptEntry) -> ReviewSuggestion? {
        suggestions.first {
            $0.sourceRemoteItemID == entry.remoteItemID
                || ($0.sourceSequence == entry.sequence && $0.originalText == entry.text)
        }
    }

    private func bubbleSaveKey(sourceOriginalText: String, expressionEn: String) -> String {
        "\(sourceOriginalText)|\(expressionEn)"
    }

    private func toggleSavedBubble(_ payload: BubbleSavePayload) {
        let key = bubbleSaveKey(sourceOriginalText: payload.sourceOriginalText, expressionEn: payload.expressionEn)
        if let existing = phraseCards.first(where: {
            bubbleSaveKey(sourceOriginalText: $0.sourceOriginalText, expressionEn: $0.expressionEn) == key
        }) {
            modelContext.delete(existing)
            try? modelContext.save()
            return
        }

        let card = PhraseCard(
            intentKo: payload.intentKo,
            expressionEn: payload.expressionEn,
            sourceOriginalText: payload.sourceOriginalText,
            naturalRewrite: payload.naturalRewrite,
            usageNoteKo: payload.usageNoteKo,
            tags: [],
            sourceSessionID: session.id
        )
        modelContext.insert(card)
        try? modelContext.save()
    }
}

private struct BubbleSavePayload: Hashable {
    let sourceOriginalText: String
    let expressionEn: String
    let naturalRewrite: String
    let intentKo: String
    let usageNoteKo: String
}

private struct HistoryTranscriptBubble: View {
    let entry: TranscriptEntry
    let suggestion: ReviewSuggestion?
    let savedBubbleKeys: Set<String>
    let onSpeak: (String, String) -> Void
    let onToggleSave: (BubbleSavePayload) -> Void
    let activeBubbleID: String?
    let loadingBubbleID: String?

    private var bubbleTextMaxWidth: CGFloat {
        320
    }

    private var isAssistant: Bool {
        entry.role == .assistant
    }

    private var bubbleID: String {
        "entry-\(entry.id.uuidString)"
    }

    private var displayedText: String {
        if isAssistant {
            return entry.text
        }
        return suggestion?.naturalRewrite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? suggestion?.naturalRewrite ?? entry.text
            : entry.text
    }

    var body: some View {
        HStack {
            if isAssistant {
                bubbleColumn
                Spacer(minLength: 46)
            } else {
                Spacer(minLength: 46)
                bubbleColumn
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bubbleColumn: some View {
        VStack(alignment: isAssistant ? .leading : .trailing, spacing: 8) {
            bubbleRow

            if activeBubbleID == bubbleID || loadingBubbleID == bubbleID {
                playbackBadge(isLoading: loadingBubbleID == bubbleID)
                    .frame(maxWidth: bubbleTextMaxWidth + 32, alignment: .trailing)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }

            if !isAssistant, let suggestion, displayedText != entry.text {
                Text("원문 · \(entry.text)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: bubbleTextMaxWidth + 32, alignment: .trailing)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activeBubbleID == bubbleID || loadingBubbleID == bubbleID)
    }

    @ViewBuilder
    private var bubbleRow: some View {
        if isAssistant {
            bubble
        } else {
            HStack(alignment: .center, spacing: 10) {
                saveButton
                bubble
            }
            .frame(maxWidth: bubbleTextMaxWidth + 72, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var bubble: some View {
        if isAssistant {
            HistoryAssistantSentenceBubbleSequence(
                entryID: entry.id.uuidString,
                text: displayedText,
                bubbleTextMaxWidth: bubbleTextMaxWidth,
                onSpeak: onSpeak,
                onToggleSave: onToggleSave,
                savedBubbleKeys: savedBubbleKeys,
                activeBubbleID: activeBubbleID,
                loadingBubbleID: loadingBubbleID
            )
        } else {
            Button {
                onSpeak(bubbleID, displayedText)
            } label: {
                transcriptBubbleBody(text: displayedText)
            }
            .buttonStyle(.plain)
        }
    }

    private func transcriptBubbleBody(text: String) -> some View {
        let isSpeaking = activeBubbleID == bubbleID
        let isLoading = loadingBubbleID == bubbleID

        return HistoryBubbleTextBlock(
            text: text,
            maxWidth: bubbleTextMaxWidth,
            foregroundColor: isAssistant ? .white : SpickingPalette.ink
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(background(isSpeaking: isSpeaking || isLoading))
        .overlay(alignment: .bottomTrailing) {
            if entry.wasInterrupted && !isAssistant {
                Text("중간 종료")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 10)
                    .padding(.bottom, 8)
            }
        }
    }

    private var savePayload: BubbleSavePayload {
        if let suggestion, !isAssistant {
            return BubbleSavePayload(
                sourceOriginalText: suggestion.originalText,
                expressionEn: displayedText,
                naturalRewrite: suggestion.naturalRewrite,
                intentKo: suggestion.intentKo,
                usageNoteKo: suggestion.reasonKo.isEmpty ? "내 문장을 더 자연스럽게 다듬은 표현이에요." : suggestion.reasonKo
            )
        }

        return BubbleSavePayload(
            sourceOriginalText: entry.text,
            expressionEn: displayedText,
            naturalRewrite: displayedText,
            intentKo: isAssistant ? "코치가 실제로 사용한 표현" : "대화에서 남긴 내 표현",
            usageNoteKo: isAssistant ? "대화에서 바로 따라 써볼 수 있는 표현이에요." : "내가 실제로 사용한 표현이에요."
        )
    }

    private var isSaved: Bool {
        savedBubbleKeys.contains("\(savePayload.sourceOriginalText)|\(savePayload.expressionEn)")
    }

    private var saveButton: some View {
        Button {
            onToggleSave(savePayload)
        } label: {
            Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(isSaved ? SpickingPalette.ocean : SpickingPalette.teal)
        }
        .buttonStyle(.plain)
    }

    private func playbackBadge(isLoading: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isLoading ? "waveform" : "speaker.wave.2.fill")
            Text(isLoading ? "읽는 중…" : "재생 중")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(SpickingPalette.ocean)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(SpickingPalette.ocean.opacity(0.12))
        )
    }

    @ViewBuilder
    private func background(isSpeaking: Bool) -> some View {
        if isAssistant {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 24,
                    bottomLeading: 24,
                    bottomTrailing: 24,
                    topTrailing: 24
                ),
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [SpickingPalette.ocean, SpickingPalette.teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if isSpeaking {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 24,
                            bottomLeading: 24,
                            bottomTrailing: 24,
                            topTrailing: 24
                        ),
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(0.75), lineWidth: 0.9)
                    .overlay(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 24,
                                bottomLeading: 24,
                                bottomTrailing: 24,
                                topTrailing: 24
                            ),
                            style: .continuous
                        )
                        .stroke(Color.black.opacity(0.14), lineWidth: 1.2)
                    )
                }
            }
        } else {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 24,
                    bottomLeading: 24,
                    bottomTrailing: 24,
                    topTrailing: 24
                ),
                style: .continuous
            )
            .fill(Color.white.opacity(0.96))
            .overlay(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 24,
                        bottomLeading: 24,
                        bottomTrailing: 24,
                        topTrailing: 24
                    ),
                    style: .continuous
                )
                .stroke(isSpeaking ? SpickingPalette.ocean.opacity(0.92) : SpickingPalette.outline.opacity(0.9), lineWidth: isSpeaking ? 1.8 : 1.2)
            )
            .shadow(color: .black.opacity(0.03), radius: 10, y: 6)
        }
    }

}

private struct HistoryAssistantSentenceBubbleSequence: View {
    let entryID: String
    let text: String
    let bubbleTextMaxWidth: CGFloat
    let onSpeak: (String, String) -> Void
    let onToggleSave: (BubbleSavePayload) -> Void
    let savedBubbleKeys: Set<String>
    let activeBubbleID: String?
    let loadingBubbleID: String?

    private var renderedSegments: [String] {
        sentenceSegments(from: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(renderedSegments.enumerated()), id: \.offset) { index, sentence in
                let bubbleID = "assistant-\(entryID)-\(index)"
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 10) {
                        Button {
                            onSpeak(bubbleID, sentence)
                        } label: {
                            assistantBubble(
                                text: sentence,
                                position: bubblePosition(for: index, totalCount: renderedSegments.count),
                                isSpeaking: activeBubbleID == bubbleID || loadingBubbleID == bubbleID
                            )
                        }
                        .buttonStyle(.plain)

                        assistantSaveButton(for: sentence)
                    }

                    if activeBubbleID == bubbleID || loadingBubbleID == bubbleID {
                        playbackBadge(isLoading: loadingBubbleID == bubbleID)
                            .padding(.leading, 2)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    }
                }
            }
        }
        .frame(maxWidth: bubbleTextMaxWidth + 32, alignment: .leading)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activeBubbleID)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: loadingBubbleID)
    }

    private func assistantSaveButton(for sentence: String) -> some View {
        let payload = BubbleSavePayload(
            sourceOriginalText: sentence,
            expressionEn: sentence,
            naturalRewrite: sentence,
            intentKo: "코치가 실제로 사용한 표현",
            usageNoteKo: "대화에서 바로 따라 써볼 수 있는 표현이에요."
        )
        let isSaved = savedBubbleKeys.contains("\(payload.sourceOriginalText)|\(payload.expressionEn)")

        return Button {
            onToggleSave(payload)
        } label: {
            Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(isSaved ? SpickingPalette.ocean : SpickingPalette.teal)
        }
        .buttonStyle(.plain)
    }

    private func assistantBubble(text: String, position: HistoryBubbleStackPosition, isSpeaking: Bool) -> some View {
        return HistoryBubbleTextBlock(
            text: text,
            maxWidth: bubbleTextMaxWidth,
            foregroundColor: .white
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: position.topRadius,
                    bottomLeading: position.bottomRadius,
                    bottomTrailing: 24,
                    topTrailing: 24
                ),
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [SpickingPalette.ocean, SpickingPalette.teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
            .overlay {
                if isSpeaking {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: position.topRadius,
                        bottomLeading: position.bottomRadius,
                        bottomTrailing: 24,
                            topTrailing: 24
                        ),
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(0.75), lineWidth: 0.9)
                    .overlay(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: position.topRadius,
                                bottomLeading: position.bottomRadius,
                                bottomTrailing: 24,
                                topTrailing: 24
                            ),
                            style: .continuous
                        )
                        .stroke(Color.black.opacity(0.14), lineWidth: 1.2)
                    )
                }
            }
    }

    private func playbackBadge(isLoading: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isLoading ? "waveform" : "speaker.wave.2.fill")
            Text(isLoading ? "읽는 중…" : "재생 중")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(SpickingPalette.ocean)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(SpickingPalette.ocean.opacity(0.12))
        )
    }

    private func bubblePosition(for index: Int, totalCount: Int) -> HistoryBubbleStackPosition {
        switch totalCount {
        case 0, 1:
            return .single
        default:
            if index == 0 { return .top }
            if index == totalCount - 1 { return .bottom }
            return .middle
        }
    }

    private func sentenceSegments(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        let pattern = #"[^.!?]+[.!?]+["')\]]*\s*|[^.!?]+$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [trimmed]
        }

        let nsText = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsText.length))
        let segments = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: trimmed) else { return nil }
            let segment = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return segment.isEmpty ? nil : segment
        }

        return segments.isEmpty ? [trimmed] : segments
    }
}

private enum HistoryBubbleStackPosition {
    case single
    case top
    case middle
    case bottom

    var topRadius: CGFloat {
        switch self {
        case .single, .top:
            return 24
        case .middle, .bottom:
            return 12
        }
    }

    var bottomRadius: CGFloat {
        switch self {
        case .single, .bottom:
            return 24
        case .top, .middle:
            return 12
        }
    }
}

private struct HistoryBubbleTextBlock: View {
    let text: String
    let maxWidth: CGFloat
    let foregroundColor: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text)
                .font(.body)
                .foregroundStyle(foregroundColor)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(text)
                .font(.body)
                .foregroundStyle(foregroundColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxWidth, alignment: .leading)
        }
    }
}

@MainActor
private final class BubbleSpeechPlayer: NSObject, ObservableObject {
    @Published private(set) var activeBubbleID: String?
    @Published private(set) var loadingBubbleID: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var playbackTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(bubbleID: String, text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if activeBubbleID == bubbleID || loadingBubbleID == bubbleID {
            stop()
            return
        }

        stop()
        loadingBubbleID = bubbleID
        playbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audioURL = try await self.fetchSpeechURL(for: cleaned)
                try await self.playRemoteAudio(url: audioURL, bubbleID: bubbleID)
            } catch {
                await self.playFallbackSpeech(text: cleaned, bubbleID: bubbleID)
            }
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
        activeBubbleID = nil
        loadingBubbleID = nil
    }

    private func fetchSpeechURL(for text: String) async throws -> URL {
        let configuration = try AppConfigurationLoader.load()
        guard var components = URLComponents(url: configuration.workerURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.path = "/audio/speech"
        guard let speechURL = components.url else {
            throw URLError(.badURL)
        }
        let cacheURL = cachedAudioURL(for: text)
        let ttsVoice = preferredTTSVoice(from: configuration.voice)
        let ttsInstructions = """
        Speak in warm, natural, conversational American English like a friendly speaking coach.
        Sound fluid and human, not like a narrator or assistant reading aloud.
        Keep the pacing relaxed and clear, with natural pauses and gentle emphasis.
        """

        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        var request = URLRequest(url: speechURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.appSharedSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "input": text,
            "voice": ttsVoice,
            "model": "gpt-4o-mini-tts",
            "response_format": "wav",
            "speed": 0.96,
            "instructions": ttsInstructions
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: cacheURL, options: .atomic)
        return cacheURL
    }

    private func playRemoteAudio(url: URL, bubbleID: String) async throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)

        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()
        audioPlayer = player
        loadingBubbleID = nil
        activeBubbleID = bubbleID
        player.play()
    }

    private func playFallbackSpeech(text: String, bubbleID: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        loadingBubbleID = nil
        activeBubbleID = bubbleID
        synthesizer.speak(utterance)
    }

    private func cachedAudioURL(for text: String) -> URL {
        let hash = text.sha256Hex
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory())
        return cachesDirectory
            .appending(path: "BubbleAudio", directoryHint: .isDirectory)
            .appending(path: "\(hash).wav")
    }

    private func preferredTTSVoice(from configuredVoice: String) -> String {
        switch configuredVoice {
        case "marin", "cedar":
            return configuredVoice
        default:
            return "cedar"
        }
    }
}

extension BubbleSpeechPlayer: AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.activeBubbleID = nil
            self?.loadingBubbleID = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.activeBubbleID = nil
            self?.loadingBubbleID = nil
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.audioPlayer = nil
            self?.activeBubbleID = nil
            self?.loadingBubbleID = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            self?.audioPlayer = nil
            self?.activeBubbleID = nil
            self?.loadingBubbleID = nil
        }
    }
}

private extension String {
    var sha256Hex: String {
        let digest = SHA256.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
