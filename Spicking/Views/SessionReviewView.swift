import SwiftUI

struct SessionReviewView: View {
    @ObservedObject var viewModel: ConversationViewModel
    let onDone: () -> Void

    var body: some View {
        ZStack {
            SpickingBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("이번 대화에서 바로 가져다 쓸 수 있는 표현만 골라 정리했어요.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)

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
        .navigationTitle("대화 리뷰")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                savedCountBadge
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("완료", action: onDone)
            }
        }
    }

    private var savedCountBadge: some View {
        Text("저장 \(viewModel.reviewCards.filter(\.isSaved).count)개")
            .font(.caption.weight(.semibold))
            .foregroundStyle(SpickingPalette.ocean)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(SpickingPalette.ocean.opacity(0.10))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(SpickingPalette.ocean.opacity(0.18), lineWidth: 1)
                    )
            )
    }
}

private struct ReviewCardView: View {
    let card: ReviewCard
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section(title: "내 문장", body: card.originalText)
            section(title: "자연스러운 표현", body: card.naturalRewrite)
            section(title: "해석", body: card.intentKo)
            section(title: "왜 이 표현이 더 자연스러운지", body: card.reasonKo)

            Button(action: onSave) {
                HStack(spacing: 8) {
                    Image(systemName: card.isSaved ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                    Text(card.isSaved ? "표현장에 저장됨" : "표현장에 저장")
                        .font(.headline.weight(.semibold))
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
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
