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
            guard let match = patterns.first(where: { pattern in
                analysis.occurrences.contains {
                    $0.kanji == pattern.kanji && $0.reading == pattern.observedReading && $0.isAligned
                }
            }) else { continue }

            let choices = makeChoices(
                answer: candidate.reading,
                pattern: match,
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
        catalog: KanjiCatalog
    ) -> [String] {
        var pool: [String] = []
        if let meta = catalog.meta(for: pattern.kanji) {
            for reading in meta.onReadings where reading != pattern.observedReading {
                let swapped = swapPrefix(of: answer, from: pattern.observedReading, to: reading)
                if swapped != answer {
                    pool.append(swapped)
                }
            }
        }
        pool.append(contentsOf: [
            swapPrefix(of: answer, from: pattern.observedReading, to: "きょう"),
            swapPrefix(of: answer, from: pattern.observedReading, to: "こう"),
            swapPrefix(of: answer, from: pattern.observedReading, to: "けい"),
            swapPrefix(of: answer, from: pattern.observedReading, to: "かん")
        ])

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

    private static func swapPrefix(of reading: String, from old: String, to new: String) -> String {
        if reading.hasPrefix(old) {
            return new + reading.dropFirst(old.count)
        }
        return new + reading
    }
}
