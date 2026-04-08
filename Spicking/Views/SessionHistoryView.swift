import AVFoundation
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

    @State private var speechPlayer = BubbleSpeechPlayer()

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
                                savedExpressions: savedExpressions,
                                onSpeak: { text in
                                    speechPlayer.speak(text: text)
                                },
                                onSavePhrase: { suggestion, phrase in
                                    savePhrase(from: suggestion, phrase: phrase)
                                }
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

    private var savedExpressions: Set<String> {
        Set(phraseCards.map(\.expressionEn))
    }

    private func suggestion(for entry: TranscriptEntry) -> ReviewSuggestion? {
        suggestions.first {
            $0.sourceRemoteItemID == entry.remoteItemID
                || ($0.sourceSequence == entry.sequence && $0.originalText == entry.text)
        }
    }

    private func savePhrase(from suggestion: ReviewSuggestion, phrase: RecommendedPhrase) {
        guard !savedExpressions.contains(phrase.expressionEn) else { return }

        let card = PhraseCard(
            intentKo: suggestion.intentKo,
            expressionEn: phrase.expressionEn,
            sourceOriginalText: suggestion.originalText,
            naturalRewrite: suggestion.naturalRewrite,
            usageNoteKo: phrase.usageNoteKo,
            tags: [],
            sourceSessionID: session.id
        )
        modelContext.insert(card)
        try? modelContext.save()
    }
}

private struct HistoryTranscriptBubble: View {
    let entry: TranscriptEntry
    let suggestion: ReviewSuggestion?
    let savedExpressions: Set<String>
    let onSpeak: (String) -> Void
    let onSavePhrase: (ReviewSuggestion, RecommendedPhrase) -> Void

    private var bubbleTextMaxWidth: CGFloat {
        320
    }

    private var isAssistant: Bool {
        entry.role == .assistant
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
            bubble

            if !isAssistant, let suggestion, displayedText != entry.text {
                Text("원문 · \(entry.text)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: bubbleTextMaxWidth + 32, alignment: .trailing)
            }

            if !isAssistant, let suggestion, !suggestion.recommendedPhrases.isEmpty {
                recommendedPhraseList(for: suggestion)
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        if isAssistant {
            HistoryAssistantSentenceBubbleSequence(
                text: displayedText,
                bubbleTextMaxWidth: bubbleTextMaxWidth,
                onSpeak: onSpeak
            )
        } else {
            Button {
                onSpeak(displayedText)
            } label: {
                transcriptBubbleBody(text: displayedText)
            }
            .buttonStyle(.plain)
        }
    }

    private func transcriptBubbleBody(text: String) -> some View {
        HistoryBubbleTextBlock(
            text: text,
            maxWidth: bubbleTextMaxWidth,
            foregroundColor: isAssistant ? .white : SpickingPalette.ink
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(background)
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

    @ViewBuilder
    private var background: some View {
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
                .stroke(SpickingPalette.outline.opacity(0.9), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.03), radius: 10, y: 6)
        }
    }

    private func recommendedPhraseList(for suggestion: ReviewSuggestion) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(suggestion.recommendedPhrases, id: \.expressionEn) { phrase in
                HStack(spacing: 10) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(phrase.expressionEn)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SpickingPalette.ink)
                            .multilineTextAlignment(.trailing)
                        Text(phrase.usageNoteKo)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    Button {
                        onSavePhrase(suggestion, phrase)
                    } label: {
                        Image(systemName: savedExpressions.contains(phrase.expressionEn) ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(savedExpressions.contains(phrase.expressionEn) ? SpickingPalette.ocean : SpickingPalette.teal)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.82))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(SpickingPalette.outline.opacity(0.72), lineWidth: 1)
                        )
                )
                .frame(maxWidth: bubbleTextMaxWidth + 52, alignment: .trailing)
            }
        }
    }
}

private struct HistoryAssistantSentenceBubbleSequence: View {
    let text: String
    let bubbleTextMaxWidth: CGFloat
    let onSpeak: (String) -> Void

    private var renderedSegments: [String] {
        sentenceSegments(from: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(renderedSegments.enumerated()), id: \.offset) { index, sentence in
                Button {
                    onSpeak(sentence)
                } label: {
                    assistantBubble(
                        text: sentence,
                        position: bubblePosition(for: index, totalCount: renderedSegments.count)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: bubbleTextMaxWidth + 32, alignment: .leading)
    }

    private func assistantBubble(text: String, position: HistoryBubbleStackPosition) -> some View {
        HistoryBubbleTextBlock(
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
private final class BubbleSpeechPlayer: NSObject {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }
}

extension BubbleSpeechPlayer: AVSpeechSynthesizerDelegate {}
