import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConversationSession.startedAt, order: .reverse) private var sessions: [ConversationSession]
    @Query(sort: \PhraseCard.createdAt, order: .reverse) private var phraseCards: [PhraseCard]
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
                        heroCard
                        SetupCard()
                        topicComposer
                        recentSessionsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("스피킹")
            .toolbarTitleDisplayMode(.large)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("말이 붙는 영어 회화")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(SpickingPalette.ink)

            Text("지금 떠오르는 생각을 영어로 말하고, 더 자연스러운 표현으로 바로 다듬어보세요.")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                MetricChip(title: "저장 표현", value: "\(phraseCards.count)개", tint: SpickingPalette.ocean)
                MetricChip(title: "누적 세션", value: "\(sessions.count)회", tint: SpickingPalette.teal)
            }
        }
        .glassCard(tint: Color.white.opacity(0.82))
    }

    private var topicComposer: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("오늘의 대화 주제", subtitle: "주제를 한국어로 적어도 대화는 영어로만 진행돼요.")

            TextField("예: 이번 주말 계획 이야기하기", text: $topic, axis: .vertical)
                .padding(16)
                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(SpickingPalette.ocean.opacity(0.12), lineWidth: 1)
                )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(topicSuggestions, id: \.self) { suggestion in
                        Button {
                            topic = suggestion
                        } label: {
                            Text(suggestion)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.72), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
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
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [SpickingPalette.ocean, SpickingPalette.teal],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
        .glassCard(tint: Color.white.opacity(0.78))
    }

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("최근 세션", subtitle: "최근 대화와 학습 흐름을 빠르게 확인해보세요.")

            if sessions.isEmpty {
                Text("아직 기록된 세션이 없어요. 첫 대화를 시작하면 여기에 표시됩니다.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(sessions.prefix(3))) { session in
                    RecentSessionRow(session: session)
                }
            }
        }
        .glassCard(tint: Color.white.opacity(0.74))
    }
}

private struct SetupCard: View {
    private var isConfigured: Bool {
        (try? AppConfigurationLoader.load()) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isConfigured ? "연결 준비 완료" : "설정 확인 필요", systemImage: isConfigured ? "checkmark.seal.fill" : "gearshape.2.fill")
                .font(.headline)
                .foregroundStyle(isConfigured ? .green : .primary)

            Text(
                isConfigured
                ? "Worker URL과 공유 시크릿을 확인했어요. 이제 바로 영어 대화를 시작할 수 있어요."
                : "실시간 대화를 시작하기 전에 SpickingConfig.plist에 Worker URL과 공유 시크릿을 먼저 입력해주세요."
            )
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: isConfigured ? SpickingPalette.teal.opacity(0.18) : Color.white.opacity(0.74))
    }
}

private struct RecentSessionRow: View {
    let session: ConversationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.topic)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SpickingPalette.ink)
                Spacer()
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.15), in: Capsule())
            }

            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if session.durationSeconds > 0 {
                Text("\(session.durationSeconds / 60)분 \(session.durationSeconds % 60)초")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var statusColor: Color {
        switch session.status {
        case .completed:
            return .green
        case .reviewing, .live:
            return .blue
        case .failed:
            return .red
        case .preparing:
            return .orange
        }
    }

    private var statusLabel: String {
        switch session.status {
        case .completed:
            return "완료"
        case .reviewing:
            return "리뷰 중"
        case .live:
            return "대화 중"
        case .failed:
            return "실패"
        case .preparing:
            return "준비 중"
        }
    }
}
