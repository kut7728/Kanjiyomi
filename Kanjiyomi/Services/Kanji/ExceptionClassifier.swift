//
//  ExceptionClassifier.swift
//  Kanjiyomi
//

import Foundation

enum ExceptionClassifier {
    static let defaultMessage = "패턴으로 읽기 어려운 단어입니다. 단어 전체를 하나의 표현으로 기억하는 것을 추천합니다."

    static func classify(
        surface: String,
        reading: String,
        occurrences: [KanjiOccurrence],
        catalog: KanjiCatalog
    ) -> (isException: Bool, reason: String?) {
        if catalog.isIrregular(surface: surface, reading: reading) {
            return (true, defaultMessage)
        }

        let kanjiCount = KanjiExtractor.kanjiCharacters(in: surface).count
        guard kanjiCount > 0 else { return (false, nil) }

        if !occurrences.isEmpty, occurrences.allSatisfy(\.isAligned) {
            return (false, nil)
        }

        if kanjiCount >= 2, reading.count <= kanjiCount {
            return (true, defaultMessage)
        }

        if !occurrences.isEmpty, occurrences.contains(where: { !$0.isAligned }) {
            return (true, defaultMessage)
        }

        return (false, nil)
    }
}
