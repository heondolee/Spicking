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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.topic)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(SpickingPalette.ink)

                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .glassCard(tint: Color.white.opacity(0.78))

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
        Text(entry.text)
            .font(.body)
            .foregroundStyle(isAssistant ? .white : SpickingPalette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(backgroundStyle)
            .overlay(alignment: .bottomTrailing) {
                if entry.wasInterrupted {
                    Text("중간 종료")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isAssistant ? .white.opacity(0.9) : .secondary)
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                }
            }
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        if isAssistant {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [SpickingPalette.ocean, SpickingPalette.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(SpickingPalette.outline.opacity(0.88), lineWidth: 1.2)
                )
        }
    }
}
