//
//  WordDetailView.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI

struct WordDetailView: View {
    let word: RecognizedWord
    @Query(sort: \VocabWord.createdAt, order: .reverse) private var savedWords: [VocabWord]
    @Environment(\.modelContext) private var modelContext
    /// Absent wherever this screen is shown outside the tab view, and then there is no scan
    /// tab to send the user to either.
    @Environment(ScanRouter.self) private var scanRouter: ScanRouter?
    @Environment(\.dismiss) private var dismiss
    @State private var isSaved = false
    @State private var originScan: ScanRecord?
    @State private var examples: [WordExample] = []
    @State private var isLoadingExamples = false
    @State private var didCopyJapanese = false
    @State private var copyToastMessage: String?
    @State private var copyToastTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            KYColor.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    KYCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 10) {
                                Text(word.displayHeadword)
                                    .font(KYFont.kanji())
                                    .foregroundStyle(KYColor.textPrimary)
                                Button {
                                    copyJapanese(word.displayHeadword)
                                } label: {
                                    Image(systemName: didCopyJapanese ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(KYColor.primary)
                                        .frame(width: 36, height: 36)
                                        .background(KYColor.primary.opacity(0.12))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("일본어 복사")
                                Spacer(minLength: 0)
                            }
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
                            if !partOfSpeech.isEmpty {
                                Text(partOfSpeech)
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
                        }
                    }

                    if !KanjiExtractor.kanjiCharacters(in: word.displayHeadword).isEmpty {
                        KanjiPatternSection(
                            word: word,
                            savedWords: savedWords,
                            catalog: DictionaryService.shared,
                            newlyDiscovered: newlyDiscoveredPatterns
                        )
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

                    if let originScan {
                        KYSecondaryButton("이 단어가 나온 스캔 보기", systemImage: "text.viewfinder") {
                            openScan(originScan)
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

            if let copyToastMessage {
                VStack {
                    Spacer()
                    KYCopyToast(message: copyToastMessage)
                        .padding(.bottom, 28)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: copyToastMessage)
        .navigationTitle("단어 상세")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshSavedState()
            KanjiPatternStore.sync(
                from: savedWords,
                modelContext: modelContext,
                catalog: DictionaryService.shared
            )
        }
        .task { await loadExamples() }
    }

    private func copyJapanese(_ text: String) {
        ClipboardCopy.copy(text)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            didCopyJapanese = true
            copyToastMessage = "「\(text)」 복사됨"
        }
        copyToastTask?.cancel()
        copyToastTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    didCopyJapanese = false
                    copyToastMessage = nil
                }
            }
        }
    }

    private var newlyDiscoveredPatterns: [PatternObservation] {
        PatternDetector.detect(
            from: savedWords.map { ($0.displayHeadword, $0.reading) },
            catalog: DictionaryService.shared
        )
        .filter {
            ($0.status == .discovered || $0.status == .familiar)
                && $0.sampleWords.contains(word.displayHeadword)
                && $0.wordCount == PatternDetector.discoverThreshold
        }
    }

    /// JMdict labels parts of speech in English prose, which has no place on a Korean screen.
    private var partOfSpeech: String {
        PartOfSpeechFormatter.korean(from: word.partOfSpeech)
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
        let saved = try? modelContext.fetch(descriptor).first
        isSaved = saved != nil
        guard let scanRecordID = saved?.scanRecordID else {
            originScan = nil
            return
        }
        originScan = scanRouter?.record(scanRecordID, modelContext: modelContext)
    }

    /// The scan sits on another tab, so switching to it is left to the tab view and this
    /// screen only names the scan and the word to point at. Popped first so the tab switch
    /// does not leave this page pushed behind it.
    private func openScan(_ record: ScanRecord) {
        dismiss()
        scanRouter?.reveal(
            recordID: record.id,
            wordKey: WordCache.makeKey(surface: word.surface, lemma: word.lemma)
        )
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
