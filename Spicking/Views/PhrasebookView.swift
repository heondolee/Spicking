import SwiftData
import SwiftUI

struct PhrasebookView: View {
    @Query(sort: \PhraseCard.createdAt, order: .reverse) private var phraseCards: [PhraseCard]
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                SpickingBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            BrandMark()
                            Text("저장해둔 자연스러운 문장을 다시 찾아보고, 다음 대화에서 바로 꺼내 써보세요.")
                                .foregroundStyle(.secondary)
                        }
                        .glassCard(tint: Color.white.opacity(0.8))

                        if filteredCards.isEmpty {
                            ContentUnavailableView("아직 저장한 표현이 없어요", systemImage: "text.book.closed", description: Text("세션 리뷰에서 마음에 드는 문장을 저장하면 여기에 모여요."))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            ForEach(filteredCards) { card in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(card.expressionEn)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(SpickingPalette.ink)
                                    Text(card.intentKo)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("내가 했던 말: \(card.sourceOriginalText)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Text(card.usageNoteKo)
                                        .font(.footnote)
                                }
                                .glassCard(tint: Color.white.opacity(0.82))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .searchable(text: $searchText, prompt: "표현 검색")
            .navigationTitle("표현장")
        }
    }

    private var filteredCards: [PhraseCard] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return phraseCards }
        return phraseCards.filter {
            $0.expressionEn.localizedCaseInsensitiveContains(query)
                || $0.intentKo.localizedCaseInsensitiveContains(query)
                || $0.usageNoteKo.localizedCaseInsensitiveContains(query)
        }
    }
}
