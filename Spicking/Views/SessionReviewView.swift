import SwiftUI

struct SessionReviewView: View {
    @ObservedObject var viewModel: ConversationViewModel
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Session Review")
                    .font(.largeTitle.bold())

                Text("Save the rewrites you want to reuse later in your Phrasebook.")
                    .foregroundStyle(.secondary)

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
            .padding()
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: onDone)
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
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }

            Button(card.isSaved ? "Saved" : "Save to Phrasebook", action: onSave)
                .buttonStyle(.borderedProminent)
                .disabled(card.isSaved)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            Text("No review suggestions yet")
                .font(.headline)
            Text("This usually happens when the session was too short. Try speaking for a few more turns next time.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
