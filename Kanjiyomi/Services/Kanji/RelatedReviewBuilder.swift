//
//  RelatedReviewBuilder.swift
//  Kanjiyomi
//

import Foundation

enum RelatedReviewBuilder {
    static func boostQuestions(
        missedSurface: String,
        learned: [(surface: String, reading: String, meaning: String)],
        catalog: KanjiCatalog,
        limit: Int = 2
    ) -> [QuizQuestion] {
        guard let missed = learned.first(where: { $0.surface == missedSurface }) else { return [] }
        let missedKanji = Set(KanjiExtractor.kanjiCharacters(in: missed.surface))
        guard !missedKanji.isEmpty else { return [] }

        let relatives = learned.filter { word in
            word.surface != missedSurface
                && !Set(KanjiExtractor.kanjiCharacters(in: word.surface)).isDisjoint(with: missedKanji)
        }

        return relatives.prefix(limit).map { word in
            QuizQuestion(
                prompt: word.surface,
                answer: word.meaning,
                choices: makeMeaningChoices(answer: word.meaning, pool: learned.map(\.meaning)),
                caption: "같은 한자가 들어간 단어",
                successMessage: nil,
                isInference: false,
                isRelatedBoost: true
            )
        }
    }

    private static func makeMeaningChoices(answer: String, pool: [String]) -> [String] {
        var choices = [answer]
        for meaning in pool.shuffled() where meaning != answer && !choices.contains(meaning) {
            choices.append(meaning)
            if choices.count == 4 { break }
        }
        return choices.shuffled()
    }
}
