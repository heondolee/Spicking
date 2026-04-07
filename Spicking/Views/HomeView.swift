import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConversationSession.startedAt, order: .reverse) private var sessions: [ConversationSession]
    @ObservedObject var appViewModel: AppViewModel
    @State private var topic = "하루 일과와 가벼운 스몰토크"

    private let topicSuggestions = [
        "오늘 하루 어땠는지 말하기",
        "주말 계획 이야기하기",
        "일과 공부 습관 설명하기",
        "최근 본 콘텐츠 이야기하기",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                SpickingBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        BrandMark()
                            .padding(.top, 8)

                        topicComposer
                        recentSessionsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var topicComposer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("지금 어떤 이야기로 시작할까요?")
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(SpickingPalette.ink)

            TextField("예: 이번 주말 계획 이야기하기", text: $topic, axis: .vertical)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.90))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(SpickingPalette.outline.opacity(0.95), lineWidth: 1.2)
                        )
                )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(topicSuggestions, id: \.self) { suggestion in
                        Button {
                            topic = suggestion
                        } label: {
                            PromptChip(title: suggestion, isSelected: topic == suggestion)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                appViewModel.startConversation(topic: topic, modelContext: modelContext)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title3)
                    Text("영어 대화 시작하기")
                        .font(.headline.weight(.semibold))
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
        .glassCard(tint: Color.white.opacity(0.74))
    }

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("최근 세션")

            if sessions.isEmpty {
                Text("아직 기록된 세션이 없어요. 첫 대화를 시작하면 여기에 표시됩니다.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(sessions.prefix(6))) { session in
                    NavigationLink {
                        SessionHistoryView(session: session)
                    } label: {
                        RecentSessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .glassCard(tint: Color.white.opacity(0.70))
    }
}

private struct RecentSessionRow: View {
    let session: ConversationSession

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [SpickingPalette.ocean, SpickingPalette.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "text.bubble.fill")
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(session.topic)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SpickingPalette.ink)
                    .lineLimit(2)

                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if session.durationSeconds > 0 {
                    Text("\(session.durationSeconds / 60)분 \(session.durationSeconds % 60)초")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.90))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(SpickingPalette.outline.opacity(0.88), lineWidth: 1)
                )
        )
    }
}
