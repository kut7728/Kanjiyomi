//
//  OnKunClassifier.swift
//  Kanjiyomi
//

import Foundation

enum OnKunClassifier {
    static func classify(
        surface: String,
        partOfSpeech: String,
        occurrences: [KanjiOccurrence]
    ) -> ReadingKind {
        let tokens = KanjiExtractor.tokens(in: surface)
        let hasOkurigana = tokens.contains { token in
            if case .kana = token { return true }
            return false
        }
        let kanjiCount = tokens.filter {
            if case .kanji = $0 { return true }
            return false
        }.count
        let lowered = partOfSpeech.lowercased()
        let isVerbOrAdjective = lowered.contains("verb") || lowered.contains("adjective")
        let isNoun = lowered.contains("noun")

        if hasOkurigana && isVerbOrAdjective {
            return .kunyomi
        }
        if kanjiCount >= 2 && isNoun && !hasOkurigana {
            return .onyomi
        }
        if let first = occurrences.first, occurrences.allSatisfy({ $0.kind == first.kind }) {
            return first.kind
        }
        return .unknown
    }
}
