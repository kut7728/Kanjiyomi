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
    @State private var examples: [WordExample] = []
    @State private var isLoadingExamples = false

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

                            if isLoadingExamples {
                                HStack(spacing: 12) {
                                    KYDotLoadingView()
                                    Text("예문을 만들고 있어요")
                                        .font(KYFont.callout())
                                        .foregroundStyle(KYColor.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            } else if examples.isEmpty {
                                Text("예문이 아직 없어요.")
                                    .font(KYFont.callout())
                                    .foregroundStyle(KYColor.textSecondary)
                            } else {
                                ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
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
        .task { await loadExamples() }
    }

    /// Examples are the bulk of what the model has to write, so they are generated here
    /// instead of during the scan where they would hold up every other word.
    private func loadExamples() async {
        guard examples.isEmpty, !isLoadingExamples else { return }

        if !word.examples.isEmpty {
            examples = word.examples
            return
        }
        guard MeaningService.shared.isGenerationAvailable else { return }

        isLoadingExamples = true
        examples = await MeaningService.shared.examples(for: word, modelContext: modelContext)
        isLoadingExamples = false
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
        var stored = word
        stored.examples = examples
        let vocab = VocabWord(from: stored)
        modelContext.insert(vocab)
        try? modelContext.save()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isSaved = true
        }
    }
}
