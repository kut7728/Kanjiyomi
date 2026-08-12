//
//  VocabularyView.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI

struct VocabularyView: View {
    @Query(sort: \VocabWord.createdAt, order: .reverse) private var words: [VocabWord]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(words) { word in
                            NavigationLink {
                                WordDetailView(word: word.toRecognizedWord())
                            } label: {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(word.displayHeadword)
                                            .font(KYFont.headline())
                                            .foregroundStyle(KYColor.textPrimary)
                                        if !word.hangul.isEmpty {
                                            Text(word.hangul)
                                                .font(KYFont.caption())
                                                .foregroundStyle(KYColor.primary)
                                        }
                                    }
                                    Spacer()
                                    Text(word.displayMeaning)
                                        .font(KYFont.callout())
                                        .foregroundStyle(KYColor.textSecondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding(.vertical, 6)
                            }
                            .listRowBackground(KYColor.card)
                        }
                        .onDelete(perform: delete)
                    }
                    .scrollContentBackground(.hidden)
                    .listRowSpacing(10)
                }
            }
            .background(KYColor.background)
            .navigationTitle("단어장")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DictionarySearchView()
                    } label: {
                        Label("사전 검색", systemImage: "magnifyingglass")
                    }
                    .foregroundStyle(KYColor.primary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(KYColor.primary)
            Text("아직 저장한 단어가 없어요")
                .font(KYFont.headline())
                .foregroundStyle(KYColor.textPrimary)
            Text("스캔한 단어 상세에서 저장해 보세요.")
                .font(KYFont.callout())
                .foregroundStyle(KYColor.textSecondary)
        }
        .padding(40)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(words[index])
        }
        try? modelContext.save()
    }
}
