//
//  KanjiPatternSection.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI

struct KanjiPatternSection: View {
    let word: RecognizedWord
    let savedWords: [VocabWord]
    let catalog: KanjiCatalog
    let newlyDiscovered: [PatternObservation]

    @State private var relatedDestination: RecognizedWord?

    private var analysis: WordAnalysis {
        WordAnalyzer.analyze(
            surface: word.displayHeadword,
            reading: word.reading,
            partOfSpeech: word.partOfSpeech,
            catalog: catalog
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            if analysis.isException {
                exceptionCard
            } else {
                if let cognate = analysis.cognateKO {
                    cognateCard(cognate)
                }
                if !analysis.occurrences.isEmpty {
                    breakdownCard
                }
                relatedCard
                if analysis.dominantKind == .kunyomi {
                    kunyomiNote
                }
            }
            if !newlyDiscovered.isEmpty {
                discoveryCard
            }
        }
        .navigationDestination(item: $relatedDestination) { related in
            WordDetailView(word: related)
        }
    }

    private var exceptionCard: some View {
        KYCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("통째로 기억하는 단어")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
                Text(analysis.exceptionReason ?? ExceptionClassifier.defaultMessage)
                    .font(KYFont.callout())
                    .foregroundStyle(KYColor.textPrimary)
            }
        }
    }

    private func cognateCard(_ cognate: String) -> some View {
        KYCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("한국 한자어")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    labeled("한국어", cognate)
                    labeled("일본어", word.displayHeadword)
                    labeled("읽기", word.reading)
                }
            }
        }
    }

    private var breakdownCard: some View {
        KYCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("구성 한자")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
                ForEach(analysis.occurrences, id: \.index) { item in
                    HStack(spacing: 8) {
                        Text(String(item.kanji))
                            .font(KYFont.headline())
                            .foregroundStyle(KYColor.textPrimary)
                        if item.kind == .onyomi, !item.hanjaKO.isEmpty {
                            Text("→ \(item.hanjaKO)")
                                .font(KYFont.callout())
                                .foregroundStyle(KYColor.textSecondary)
                        }
                        if item.isAligned, !item.reading.isEmpty {
                            Text("→ \(item.reading)")
                                .font(KYFont.callout())
                                .foregroundStyle(KYColor.primary)
                        }
                        Spacer(minLength: 0)
                        Text(kindLabel(item.kind))
                            .font(KYFont.caption())
                            .foregroundStyle(KYColor.textSecondary)
                    }
                }
            }
        }
    }

    private var relatedCard: some View {
        let kanjiList = analysis.occurrences.map(\.kanji)
        return Group {
            if !kanjiList.isEmpty {
                KYCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("같은 한자가 쓰인 단어")
                            .font(KYFont.caption())
                            .foregroundStyle(KYColor.textSecondary)
                        ForEach(kanjiList, id: \.self) { kanji in
                            relatedBlock(for: kanji)
                        }
                    }
                }
            }
        }
    }

    private func relatedBlock(for kanji: Character) -> some View {
        let saved = savedByKanji[kanji] ?? []
        let unseen = catalog.wordsContaining(kanji, limit: 8).filter { entry in
            entry.kanji != word.displayHeadword && !saved.contains(where: { $0.displayHeadword == entry.kanji })
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text(String(kanji))
                .font(KYFont.headline())
                .foregroundStyle(KYColor.textPrimary)
            ForEach(saved.prefix(4), id: \.id) { vocab in
                relatedRow(
                    surface: vocab.displayHeadword,
                    reading: vocab.reading,
                    meaning: vocab.displayMeaning,
                    learned: true
                )
            }
            ForEach(unseen.prefix(4), id: \.kanji) { entry in
                Button {
                    relatedDestination = RecognizedWord(
                        surface: entry.kanji,
                        lemma: entry.kanji,
                        reading: entry.reading,
                        hangul: KanaRomanizer.toHangul(entry.reading),
                        meaningKO: "",
                        meaningEN: entry.glossEN,
                        partOfSpeech: entry.partOfSpeech
                    )
                } label: {
                    relatedRow(
                        surface: entry.kanji,
                        reading: entry.reading,
                        meaning: "아직 안 배움",
                        learned: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func relatedRow(surface: String, reading: String, meaning: String, learned: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(surface)（\(reading)）")
                    .font(KYFont.callout())
                    .foregroundStyle(KYColor.textPrimary)
                Text(meaning)
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
            }
            Spacer(minLength: 0)
            Text(learned ? "학습함" : "새로 볼 단어")
                .font(KYFont.caption())
                .foregroundStyle(learned ? KYColor.success : KYColor.primary)
        }
    }

    private var kunyomiNote: some View {
        KYCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("훈독 단어")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
                Text("한자어 읽기와 달리, 이 단어는 일본어 고유어로 읽습니다. 한국 한자음에 기대지 말고 단어 단위로 익혀 보세요.")
                    .font(KYFont.callout())
                    .foregroundStyle(KYColor.textPrimary)
            }
        }
    }

    private var discoveryCard: some View {
        KYCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("새로운 패턴을 발견했습니다")
                    .font(KYFont.headline())
                    .foregroundStyle(KYColor.primary)
                ForEach(newlyDiscovered) { pattern in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(String(pattern.kanji))이 포함된 지금까지의 단어:")
                            .font(KYFont.callout())
                            .foregroundStyle(KYColor.textPrimary)
                        ForEach(pattern.sampleWords, id: \.self) { sample in
                            Text("· \(sample)")
                                .font(KYFont.caption())
                                .foregroundStyle(KYColor.textSecondary)
                        }
                        Text("지금까지 학습한 단어에서는 \(pattern.observedReading)로 읽히는 경우가 많습니다.")
                            .font(KYFont.callout())
                            .foregroundStyle(KYColor.textPrimary)
                    }
                }
            }
        }
    }

    private var savedByKanji: [Character: [VocabWord]] {
        var map: [Character: [VocabWord]] = [:]
        for vocab in savedWords {
            for character in KanjiExtractor.kanjiCharacters(in: vocab.displayHeadword) {
                map[character, default: []].append(vocab)
            }
        }
        return map
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(KYFont.caption())
                .foregroundStyle(KYColor.textSecondary)
            Text(value)
                .font(KYFont.headline())
                .foregroundStyle(KYColor.textPrimary)
        }
    }

    private func kindLabel(_ kind: ReadingKind) -> String {
        switch kind {
        case .onyomi: return "음독"
        case .kunyomi: return "훈독"
        case .unknown: return ""
        }
    }
}
