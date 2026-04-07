import SwiftData
import SwiftUI

struct PhrasebookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PhraseCard.createdAt, order: .reverse) private var phraseCards: [PhraseCard]
    @Query(sort: \ConversationSession.startedAt, order: .reverse) private var sessions: [ConversationSession]
    @AppStorage("phrasebook_intro_hidden") private var isIntroHidden = false
    @State private var searchText = ""
    @State private var selectedSession: ConversationSession?

    var body: some View {
        NavigationStack {
            ZStack {
                SpickingBackground()

                VStack(spacing: 14) {
                    if !isIntroHidden {
                        introCard
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    if filteredCards.isEmpty {
                        ContentUnavailableView(
                            "아직 저장한 표현이 없어요",
                            systemImage: "text.book.closed",
                            description: Text("세션 리뷰에서 마음에 드는 문장을 저장하면 여기에 모여요.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(filteredCards) { card in
                                Button {
                                    selectedSession = sessions.first(where: { $0.id == card.sourceSessionID })
                                } label: {
                                    PhraseCardRow(card: card)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .disabled(sessions.contains(where: { $0.id == card.sourceSessionID }) == false)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            delete(card)
                                        } label: {
                                            Label("삭제", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "표현 검색")
            .navigationTitle("표현장")
            .navigationDestination(item: $selectedSession) { session in
                SessionHistoryView(session: session)
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("표현장")
                        .font(.title3.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(SpickingPalette.ink)
                    Text("저장해둔 자연스러운 문장을 다시 찾아보고, 다음 대화에서 바로 꺼내 써보세요.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isIntroHidden = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.white.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard(tint: Color.white.opacity(0.82))
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

    private func delete(_ card: PhraseCard) {
        modelContext.delete(card)
        try? modelContext.save()
    }
}

private struct PhraseCardRow: View {
    let card: PhraseCard

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(card.expressionEn)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(SpickingPalette.ink)

                    Spacer()

                    Text(
                        card.createdAt.formatted(
                            Date.FormatStyle(date: .long, time: .shortened)
                                .locale(Locale(identifier: "ko_KR"))
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(card.intentKo)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("내가 했던 말: \(card.sourceOriginalText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(card.usageNoteKo)
                    .font(.footnote)
                    .foregroundStyle(SpickingPalette.ink)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .glassCard(tint: Color.white.opacity(0.86))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(SpickingPalette.outline.opacity(0.95), lineWidth: 1.2)
        )
    }
}
