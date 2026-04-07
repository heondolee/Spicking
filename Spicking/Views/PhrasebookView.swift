import SwiftData
import SwiftUI

struct PhrasebookView: View {
    @Query(sort: \PhraseCard.createdAt, order: .reverse) private var phraseCards: [PhraseCard]
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List(filteredCards) { card in
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.expressionEn)
                        .font(.headline)
                    Text(card.intentKo)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("원래 내 말: \(card.sourceOriginalText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(card.usageNoteKo)
                        .font(.footnote)
                    if !card.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(card.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .overlay {
                if filteredCards.isEmpty {
                    ContentUnavailableView("No saved phrases yet", systemImage: "text.book.closed", description: Text("Save expressions from your session review and they will appear here."))
                }
            }
            .searchable(text: $searchText, prompt: "Search phrases or tags")
            .navigationTitle("Phrasebook")
        }
    }

    private var filteredCards: [PhraseCard] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return phraseCards }
        return phraseCards.filter {
            $0.expressionEn.localizedCaseInsensitiveContains(query)
                || $0.intentKo.localizedCaseInsensitiveContains(query)
                || $0.usageNoteKo.localizedCaseInsensitiveContains(query)
                || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }
}
