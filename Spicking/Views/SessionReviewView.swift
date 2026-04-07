import SwiftUI

struct SessionReviewView: View {
    @ObservedObject var viewModel: ConversationViewModel
    let onDone: () -> Void

    var body: some View {
        ZStack {
            SpickingBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("세션 리뷰")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(SpickingPalette.ink)
                        Text("오늘 말한 문장을 더 자연스럽게 다듬어봤어요. 마음에 드는 표현만 저장해두세요.")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            MetricChip(title: "추천 표현", value: "\(viewModel.reviewCards.count)개", tint: SpickingPalette.ocean)
                            MetricChip(title: "저장 완료", value: "\(viewModel.reviewCards.filter(\.isSaved).count)개", tint: SpickingPalette.teal)
                        }
                    }
                    .glassCard(tint: Color.white.opacity(0.8))

                    if viewModel.reviewCards.isEmpty {
                        EmptyReviewState()
                    } else {
                        ForEach(viewModel.reviewCards) { card in
                            ReviewCardView(card: card) {
                                viewModel.savePhraseCard(for: card)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("완료", action: onDone)
            }
        }
    }
}

private struct ReviewCardView: View {
    let card: ReviewCard
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section(title: "내 문장", body: card.originalText)
            section(title: "최소 수정", body: card.minimalRewrite)
            section(title: "자연스러운 표현", body: card.naturalRewrite)
            section(title: "의도", body: card.intentKo)
            section(title: "왜 바꾸면 좋은지", body: card.reasonKo)

            if !card.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(card.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(SpickingPalette.ocean.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }

            Button(card.isSaved ? "저장됨" : "표현장에 저장", action: onSave)
                .buttonStyle(.borderedProminent)
                .tint(SpickingPalette.ink)
                .disabled(card.isSaved)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Color.white.opacity(0.82))
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.body)
        }
    }
}

private struct EmptyReviewState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("아직 리뷰가 없어요")
                .font(.headline.weight(.bold))
            Text("이번 세션이 너무 짧아서 분석할 문장이 부족했어요. 다음에는 조금 더 길게 이야기해보세요.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Color.white.opacity(0.8))
    }
}
