import SwiftData
import SwiftUI

struct SessionHistoryView: View {
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

    var body: some View {
        ZStack {
            SpickingBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if entries.isEmpty {
                        Text("복기할 대화 내용이 아직 없어요.")
                            .foregroundStyle(.secondary)
                            .glassCard(tint: Color.white.opacity(0.78))
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(entries) { entry in
                                HistoryBubble(entry: entry)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("대화 다시 보기")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HistoryBubble: View {
    let entry: TranscriptEntry

    private var isAssistant: Bool {
        entry.role == .assistant
    }

    var body: some View {
        HStack {
            if isAssistant {
                bubble
                Spacer(minLength: 44)
            } else {
                Spacer(minLength: 44)
                bubble
            }
        }
    }

    private var bubble: some View {
        HistoryBubbleText(
            text: entry.text,
            foregroundColor: isAssistant ? .white : SpickingPalette.ink
        )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(isAssistant ? .leading : .trailing, 10)
            .background(backgroundStyle)
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
    private var backgroundStyle: some View {
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
                .fill(Color.white.opacity(0.95))
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
                        .stroke(SpickingPalette.outline.opacity(0.88), lineWidth: 1.2)
                )
        }
    }
}

private struct HistoryBubbleText: View {
    let text: String
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
        }
    }
}
