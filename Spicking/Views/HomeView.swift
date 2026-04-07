import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConversationSession.startedAt, order: .reverse) private var sessions: [ConversationSession]
    @ObservedObject var appViewModel: AppViewModel
    @State private var topic = "하루 일과와 가벼운 스몰토크"
    @State private var selectedSession: ConversationSession?
    @FocusState private var isTopicFieldFocused: Bool

    private let defaultTopicSuggestions = [
        "오늘 하루 어땠는지 말하기",
        "주말 계획 이야기하기",
        "일과 공부 습관 설명하기",
        "최근 본 콘텐츠 이야기하기",
    ]

    private var visibleSessions: [ConversationSession] {
        Array(sessions.prefix(6))
    }

    private var topicSuggestions: [String] {
        let personalized = TopicSuggestionEngine.makeSuggestions(from: sessions)
        return personalized.isEmpty ? defaultTopicSuggestions : personalized
    }

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

                topScrollFade
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedSession) { session in
                SessionHistoryView(session: session)
            }
        }
    }

    private var topScrollFade: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 42)
                .mask(
                    LinearGradient(
                        colors: [.black, .black.opacity(0.75), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var topicComposer: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("어떤 이야기로 시작할까요?")
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(SpickingPalette.ink)

            VStack(alignment: .leading, spacing: 8) {
							Text("직접 주제를 적어보세요")
									.font(.caption.weight(.semibold))
									.foregroundStyle(SpickingPalette.graphite.opacity(0.58))

							VStack(alignment: .leading, spacing: 10) {
									TextField("", text: $topic)
											.focused($isTopicFieldFocused)
											.submitLabel(.done)
											.onSubmit {
													isTopicFieldFocused = false
											}
											.textInputAutocapitalization(.never)
							}
							.padding(18)
							.background(
									RoundedRectangle(cornerRadius: 24, style: .continuous)
											.fill(Color.white.opacity(0.96))
											.overlay(
													RoundedRectangle(cornerRadius: 24, style: .continuous)
															.stroke(
																	isTopicFieldFocused ? SpickingPalette.graphite.opacity(0.75) : SpickingPalette.neutralOutline.opacity(0.95),
																	lineWidth: isTopicFieldFocused ? 1.8 : 1.2
															)
											)
							)
							.shadow(color: isTopicFieldFocused ? Color.black.opacity(0.06) : .clear, radius: 14, y: 8)
							
							Text("추천 주제")
									.font(.caption.weight(.semibold))
									.foregroundStyle(SpickingPalette.graphite.opacity(0.58))

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
            SectionHeader("최근 대화")

            if sessions.isEmpty {
                Text("아직 기록된 세션이 없어요. 첫 대화를 시작하면 여기에 표시됩니다.")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(visibleSessions) { session in
                        Button {
                            selectedSession = session
                        } label: {
                            RecentSessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(visibleSessions.count) * 112 + 8)
                .padding(.horizontal, -20)
            }
        }
    }
}

private enum TopicSuggestionEngine {
    private enum Category: CaseIterable {
        case routine
        case plans
        case workStudy
        case content
        case people
        case lifestyle
        case travel

        var keywords: [String] {
            switch self {
            case .routine:
                ["하루", "일과", "루틴", "아침", "저녁", "평일", "하루 일과"]
            case .plans:
                ["주말", "계획", "목표", "다음", "이번 주", "이번주", "이번 달", "이번달"]
            case .workStudy:
                ["공부", "업무", "일", "회사", "프로젝트", "습관", "시험", "학습"]
            case .content:
                ["콘텐츠", "영화", "드라마", "유튜브", "책", "시리즈", "음악", "게임"]
            case .people:
                ["친구", "가족", "동료", "사람", "관계", "만남"]
            case .lifestyle:
                ["운동", "건강", "음식", "카페", "요리", "취미", "생활"]
            case .travel:
                ["여행", "장소", "도시", "휴가", "숙소", "비행기"]
            }
        }

        var suggestions: [String] {
            switch self {
            case .routine:
                [
                    "요즘 하루 루틴 자세히 설명하기",
                    "오늘 있었던 일을 순서대로 이야기하기",
                ]
            case .plans:
                [
                    "다가오는 주말 계획 이야기하기",
                    "이번 달 목표와 실천 계획 말하기",
                ]
            case .workStudy:
                [
                    "일과 공부를 어떻게 병행하는지 말하기",
                    "요즘 가장 집중하는 일 설명하기",
                ]
            case .content:
                [
                    "최근 인상 깊었던 콘텐츠 추천하기",
                    "좋아하는 콘텐츠 취향 설명하기",
                ]
            case .people:
                [
                    "가까운 사람들과 보내는 시간 이야기하기",
                    "최근 기억에 남는 만남 말하기",
                ]
            case .lifestyle:
                [
                    "요즘 즐기는 취미와 생활 패턴 말하기",
                    "건강 관리나 운동 루틴 설명하기",
                ]
            case .travel:
                [
                    "가보고 싶은 곳과 여행 스타일 이야기하기",
                    "기억에 남는 장소 설명하기",
                ]
            }
        }
    }

    static func makeSuggestions(from sessions: [ConversationSession]) -> [String] {
        let recentTopics = sessions
            .map(\.topic)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard recentTopics.isEmpty == false else { return [] }

        var categoryScores: [Category: Int] = [:]
        for category in Category.allCases {
            categoryScores[category] = 0
        }

        for topic in recentTopics {
            for category in Category.allCases where category.keywords.contains(where: topic.contains) {
                categoryScores[category, default: 0] += 1
            }
        }

        var suggestions: [String] = []
        let latestTopic = recentTopics.first
        if let latestTopic,
           latestTopic.count <= 28 {
            suggestions.append(latestTopic)
        }

        let rankedCategories = categoryScores
            .filter { $0.value > 0 }
            .sorted {
                if $0.value == $1.value {
                    return String(describing: $0.key) < String(describing: $1.key)
                }
                return $0.value > $1.value
            }
            .map(\.key)

        for category in rankedCategories {
            suggestions.append(contentsOf: category.suggestions)
        }

        if suggestions.count < 4 {
            suggestions.append(contentsOf: [
                "요즘 자주 생각나는 일 이야기하기",
                "최근 가장 즐거웠던 순간 말하기",
                "이번 주에 가장 바빴던 일 설명하기",
                "요즘 관심 있는 주제 이야기하기",
            ])
        }

        var seen = Set<String>()
        return suggestions.filter { suggestion in
            let normalized = suggestion.replacingOccurrences(of: " ", with: "")
            if seen.contains(normalized) { return false }
            seen.insert(normalized)
            return true
        }
        .prefix(4)
        .map { $0 }
    }
}

private struct RecentSessionRow: View {
    let session: ConversationSession

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
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

                Text(
                    session.startedAt.formatted(
                        Date.FormatStyle(date: .long, time: .shortened)
                            .locale(Locale(identifier: "ko_KR"))
                    )
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if session.durationSeconds > 0 {
                    Text("\(session.durationSeconds / 60)분 \(session.durationSeconds % 60)초")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
