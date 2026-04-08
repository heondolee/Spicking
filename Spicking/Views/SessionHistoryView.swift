import SwiftData
import SwiftUI

struct SessionHistoryView: View {
    private enum TranscriptContainerStyle {
        static let topRadius: CGFloat = 24
        static let bottomRadius: CGFloat = 50
    }

    let session: ConversationSession
    @Query private var entries: [TranscriptEntry]

    init(session: ConversationSession) {
        self.session = session
        let sessionID = session.id
        _entries = Query(
            filter: #Predicate<TranscriptEntry> { entry in
                entry.sessionID == sessionID
            },
            sort: [SortDescriptor(\TranscriptEntry.sequence, order: .forward)]
        )
    }

    private var historyLines: [LiveTranscriptLine] {
        entries.map {
            LiveTranscriptLine(
                id: $0.remoteItemID.isEmpty ? $0.id.uuidString : $0.remoteItemID,
                role: $0.role,
                text: $0.text,
                isFinal: $0.isFinal,
                wasInterrupted: $0.wasInterrupted
            )
        }
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
                    if historyLines.isEmpty {
                        Text("복기할 대화 내용이 아직 없어요.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(historyLines) { line in
                            HistoryTranscriptBubble(line: line)
                        }
                    }

                    Color.clear
                        .frame(height: 180)
                        .allowsHitTesting(false)
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
}

private struct HistoryTranscriptBubble: View {
    let line: LiveTranscriptLine

    private var bubbleTextMaxWidth: CGFloat {
        320
    }

    private var isAssistant: Bool {
        line.role == .assistant
    }

    var body: some View {
        HStack {
            if isAssistant {
                bubble
                Spacer(minLength: 46)
            } else {
                Spacer(minLength: 46)
                bubble
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bubble: some View {
        Group {
            if isAssistant {
                HistoryAssistantSentenceBubbleSequence(line: line, bubbleTextMaxWidth: bubbleTextMaxWidth)
            } else {
                transcriptBubbleBody(text: line.text)
            }
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
            if line.wasInterrupted && !isAssistant {
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
}

private struct HistoryAssistantSentenceBubbleSequence: View {
    let line: LiveTranscriptLine
    let bubbleTextMaxWidth: CGFloat

    private var renderedSegments: [String] {
        sentenceSegments(from: line.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(renderedSegments.enumerated()), id: \.offset) { index, sentence in
                assistantBubble(
                    text: sentence,
                    position: bubblePosition(for: index, totalCount: renderedSegments.count)
                )
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
