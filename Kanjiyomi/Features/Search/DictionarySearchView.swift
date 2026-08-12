//
//  DictionarySearchView.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI

/// Pushed from the vocabulary tab, so it draws into that tab's navigation stack rather than
/// owning one. That is what gives it a back button and lets the word detail push on top.
struct DictionarySearchView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var query = ""
    @State private var results: [DictionaryEntry] = []
    @State private var isLoadingWord = false
    @State private var detailWord: RecognizedWord?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            KYColor.background.ignoresSafeArea()

            if results.isEmpty {
                placeholder
            } else {
                List(Array(results.enumerated()), id: \.offset) { _, entry in
                    Button {
                        open(entry)
                    } label: {
                        row(for: entry)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(KYColor.card)
                }
                .scrollContentBackground(.hidden)
                .listRowSpacing(10)
            }

            if isLoadingWord {
                Color.black.opacity(0.2).ignoresSafeArea()
                KYLoadingOverlay(message: "단어를 불러오는 중")
            }
        }
        .navigationTitle("사전 검색")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "일본어 단어 또는 영어 뜻"
        )
        .onChange(of: query) { _, newValue in
            scheduleSearch(newValue)
        }
        .navigationDestination(item: $detailWord) { word in
            WordDetailView(word: word)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(KYColor.primary)
            Text(query.isEmpty ? "단어를 검색해 보세요" : "검색 결과가 없어요")
                .font(KYFont.headline())
                .foregroundStyle(KYColor.textPrimary)
            Text("한자·가나 또는 영어 뜻으로 찾을 수 있어요.")
                .font(KYFont.callout())
                .foregroundStyle(KYColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func row(for entry: DictionaryEntry) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.kanji.isEmpty ? entry.reading : entry.kanji)
                    .font(KYFont.headline())
                    .foregroundStyle(KYColor.textPrimary)
                if !entry.reading.isEmpty {
                    Text(KanaRomanizer.toHangul(entry.reading))
                        .font(KYFont.caption())
                        .foregroundStyle(KYColor.primary)
                }
            }
            Spacer(minLength: 8)
            Text(entry.glossEN)
                .font(KYFont.callout())
                .foregroundStyle(KYColor.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                DictionaryService.shared.search(trimmed)
            }.value
            guard !Task.isCancelled else { return }
            results = found
        }
    }

    private func open(_ entry: DictionaryEntry) {
        let headword = entry.kanji.isEmpty ? entry.reading : entry.kanji
        isLoadingWord = true
        Task {
            let enriched = MeaningService.shared.resolve(
                surface: headword,
                lemma: headword,
                modelContext: modelContext
            )
            // The search row already carries a reading, so falling back to it also means
            // deriving the Hangul from it rather than leaving the pronunciation blank.
            let reading = enriched.reading.isEmpty ? entry.reading : enriched.reading
            var word = RecognizedWord(
                surface: headword,
                lemma: headword,
                reading: reading,
                hangul: enriched.hangul.isEmpty ? KanaRomanizer.toHangul(reading) : enriched.hangul,
                meaningKO: enriched.meaningKO,
                meaningEN: enriched.meaningEN.isEmpty ? entry.glossEN : enriched.meaningEN,
                partOfSpeech: enriched.partOfSpeech,
                examples: enriched.examples
            )
            // Only the meaning is generated here; the detail screen writes the examples.
            if word.meaningKO.isEmpty {
                let generated = await MeaningService.shared.generateMeanings(
                    for: [word],
                    modelContext: modelContext
                )
                let key = WordCache.makeKey(surface: word.surface, lemma: word.lemma)
                if let result = generated[key] {
                    word.meaningKO = result.meaningKO
                    if word.reading.isEmpty, !result.reading.isEmpty {
                        word.reading = result.reading
                        word.hangul = result.hangul
                    }
                }
            }
            isLoadingWord = false
            detailWord = word
        }
    }
}
