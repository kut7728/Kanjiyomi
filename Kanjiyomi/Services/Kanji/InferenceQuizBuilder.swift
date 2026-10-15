//
//  InferenceQuizBuilder.swift
//  Kanjiyomi
//

import Foundation

enum InferenceQuizBuilder {
    static func makeQuestion(
        learned: [(surface: String, reading: String)],
        candidates: [DictionaryEntry],
        catalog: KanjiCatalog
    ) -> InferenceQuestion? {
        let learnedKeys = Set(learned.map(\.surface))
        let patterns = PatternDetector.detect(from: learned, catalog: catalog)
            .filter { $0.status == .discovered || $0.status == .familiar }
        guard !patterns.isEmpty else { return nil }

        let shuffled = candidates.shuffled()
        for candidate in shuffled {
            let surface = candidate.kanji
            guard !surface.isEmpty, !learnedKeys.contains(surface), !candidate.reading.isEmpty else { continue }
            let analysis = WordAnalyzer.analyze(
                surface: surface,
                reading: candidate.reading,
                partOfSpeech: candidate.partOfSpeech,
                catalog: catalog
            )
            guard !analysis.isException else { continue }
            var found: (pattern: PatternObservation, occurrence: KanjiOccurrence)?
            for pattern in patterns {
                if let occurrence = analysis.occurrences.first(where: {
                    $0.kanji == pattern.kanji && $0.reading == pattern.observedReading && $0.isAligned
                }) {
                    found = (pattern, occurrence)
                    break
                }
            }
            guard let (match, occurrence) = found,
                  let offset = readingOffset(of: occurrence, in: analysis, surface: surface) else { continue }

            let choices = makeChoices(
                answer: candidate.reading,
                pattern: match,
                offset: offset,
                catalog: catalog
            )
            guard choices.count == 4 else { continue }
            return InferenceQuestion(
                surface: surface,
                answer: candidate.reading,
                choices: choices,
                patternKanji: match.kanji,
                patternReading: match.observedReading
            )
        }
        return nil
    }

    static func makeQuestions(
        learned: [(surface: String, reading: String)],
        catalog: KanjiCatalog,
        limit: Int
    ) -> [InferenceQuestion] {
        let patterns = PatternDetector.detect(from: learned, catalog: catalog)
            .filter { $0.status == .discovered || $0.status == .familiar }
        var questions: [InferenceQuestion] = []
        var used = Set(learned.map(\.surface))

        for pattern in patterns.shuffled() {
            guard questions.count < limit else { break }
            let related = catalog.wordsContaining(pattern.kanji, limit: 24)
                .filter { !used.contains($0.kanji) }
            if let question = makeQuestion(
                learned: learned,
                candidates: related,
                catalog: catalog
            ) {
                questions.append(question)
                used.insert(question.surface)
            }
        }
        return questions
    }

    private static func makeChoices(
        answer: String,
        pattern: PatternObservation,
        offset: Int,
        catalog: KanjiCatalog
    ) -> [String] {
        var replacements = catalog.meta(for: pattern.kanji)?.onReadings ?? []
        replacements += ["きょう", "こう", "けい", "かん"]
        let pool = replacements
            .filter { $0 != pattern.observedReading }
            .compactMap { swap(in: answer, at: offset, from: pattern.observedReading, to: $0) }

        var choices = [answer]
        for item in pool where !choices.contains(item) && item != answer && !item.isEmpty {
            choices.append(item)
            if choices.count == 4 { break }
        }
        let fallback = ["あいう", "えお", "かきく", "さしす"]
        for item in fallback where !choices.contains(item) {
            if choices.count == 4 { break }
            choices.append(item)
        }
        return choices.shuffled()
    }

    /// Replaces the pattern kanji's own stretch of the reading, so a wrong choice differs from
    /// the answer only where the pattern applies (みんえい → みんこう, not こうみんえい).
    private static func swap(in reading: String, at offset: Int, from old: String, to new: String) -> String? {
        let characters = Array(reading)
        let end = offset + old.count
        guard end <= characters.count, String(characters[offset..<end]) == old else { return nil }
        return String(characters[..<offset]) + new + String(characters[end...])
    }

    /// Where the occurrence's reading starts in the whole reading: each earlier kanji
    /// contributes its aligned reading and each earlier kana itself. Occurrences are
    /// numbered by kanji, not by character, so kanji are counted separately.
    private static func readingOffset(
        of occurrence: KanjiOccurrence,
        in analysis: WordAnalysis,
        surface: String
    ) -> Int? {
        var offset = 0
        var kanjiIndex = 0
        for character in surface {
            if KanjiExtractor.isKanji(character) {
                if kanjiIndex == occurrence.index { return offset }
                guard let earlier = analysis.occurrences.first(where: { $0.index == kanjiIndex }),
                      earlier.isAligned else { return nil }
                offset += earlier.reading.count
                kanjiIndex += 1
            } else if KanjiExtractor.isKana(character) {
                offset += 1
            }
        }
        return nil
    }
}
