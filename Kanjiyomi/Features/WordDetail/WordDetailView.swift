//
//  WordDetailView.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI

struct WordDetailView: View {
    let word: RecognizedWord
    @Environment(\.modelContext) private var modelContext
    @State private var isSaved = false
    @State private var showSavedToast = false

    var body: some View {
        ZStack {
            KYColor.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    KYCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(word.displayHeadword)
                                .font(KYFont.kanji())
                                .foregroundStyle(KYColor.textPrimary)
                            if !word.reading.isEmpty {
                                Text(word.reading)
                                    .font(KYFont.title())
                                    .foregroundStyle(KYColor.textSecondary)
                            }
                            if !word.hangul.isEmpty {
                                Label(word.hangul, systemImage: "speaker.wave.2.fill")
                                    .font(KYFont.headline())
                                    .foregroundStyle(KYColor.primary)
                            }
                            if !word.partOfSpeech.isEmpty {
                                Text(word.partOfSpeech)
                                    .font(KYFont.caption())
                                    .foregroundStyle(KYColor.textSecondary)
                            }
                        }
                    }

                    KYCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("뜻")
                                .font(KYFont.caption())
                                .foregroundStyle(KYColor.textSecondary)
                            Text(word.displayMeaning)
                                .font(KYFont.headline())
                                .foregroundStyle(KYColor.textPrimary)
                            if !word.meaningEN.isEmpty && word.meaningKO != word.meaningEN {
                                Text(word.meaningEN)
                                    .font(KYFont.caption())
                                    .foregroundStyle(KYColor.textSecondary)
                            }
                        }
                    }

                    KYCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("예문")
                                .font(KYFont.caption())
                                .foregroundStyle(KYColor.textSecondary)

                            if word.examples.isEmpty {
                                Text("예문이 아직 없어요.")
                                    .font(KYFont.callout())
                                    .foregroundStyle(KYColor.textSecondary)
                            } else {
                                ForEach(Array(word.examples.enumerated()), id: \.offset) { _, example in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(example.japanese)
                                            .font(KYFont.body())
                                            .foregroundStyle(KYColor.textPrimary)
                                        Text(example.korean)
                                            .font(KYFont.callout())
                                            .foregroundStyle(KYColor.textSecondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }

                    if isSaved {
                        Text("단어장에 저장됨")
                            .font(KYFont.callout())
                            .foregroundStyle(KYColor.success)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    } else {
                        KYPrimaryButton("단어장에 저장", systemImage: "bookmark.fill") {
                            saveToVocabulary()
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("단어 상세")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshSavedState() }
    }

    private func refreshSavedState() {
        let lemma = word.lemma
        let surface = word.surface
        var descriptor = FetchDescriptor<VocabWord>(
            predicate: #Predicate { $0.lemma == lemma && $0.surface == surface }
        )
        descriptor.fetchLimit = 1
        isSaved = (try? modelContext.fetch(descriptor).first) != nil
    }

    private func saveToVocabulary() {
        let vocab = VocabWord(from: word)
        modelContext.insert(vocab)
        try? modelContext.save()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isSaved = true
        }
    }
}
