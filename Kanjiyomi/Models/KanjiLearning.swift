//
//  KanjiLearning.swift
//  Kanjiyomi
//

import Foundation

enum ScriptToken: Equatable, Sendable {
    case kanji(Character)
    case kana(String)
    case other(String)
}

enum ReadingKind: String, Sendable {
    case onyomi
    case kunyomi
    case unknown
}

enum PatternStatus: String, Sendable {
    case emerging
    case discovered
    case familiar
}

struct KanjiMeta: Hashable, Sendable {
    var kanji: Character
    var hanjaKO: String
    var onReadings: [String]
    var kunReadings: [String]
    var isIrregularProne: Bool = false
}

struct KanjiOccurrence: Hashable, Sendable {
    var kanji: Character
    var index: Int
    var reading: String
    var kind: ReadingKind
    var hanjaKO: String
    var isAligned: Bool
}

struct WordAnalysis: Sendable {
    var surface: String
    var reading: String
    var occurrences: [KanjiOccurrence]
    var isException: Bool
    var exceptionReason: String?
    var cognateKO: String?
    var dominantKind: ReadingKind
}

struct PatternObservation: Hashable, Sendable, Identifiable {
    var kanji: Character
    var hanjaKO: String
    var observedReading: String
    var wordCount: Int
    var sampleWords: [String]
    var status: PatternStatus

    var id: String { "\(kanji)|\(observedReading)" }
}

struct InferenceQuestion: Equatable, Sendable {
    var surface: String
    var answer: String
    var choices: [String]
    var patternKanji: Character
    var patternReading: String
}

protocol KanjiCatalog: Sendable {
    func meta(for kanji: Character) -> KanjiMeta?
    func isIrregular(surface: String, reading: String) -> Bool
    func wordsContaining(_ kanji: Character, limit: Int) -> [DictionaryEntry]
}

enum WordAnalyzer {
    static func analyze(
        surface: String,
        reading: String,
        partOfSpeech: String = "",
        catalog: KanjiCatalog
    ) -> WordAnalysis {
        let occurrences = ReadingAligner.align(surface: surface, reading: reading, catalog: catalog)
        let exception = ExceptionClassifier.classify(
            surface: surface,
            reading: reading,
            occurrences: occurrences,
            catalog: catalog
        )
        let kind = OnKunClassifier.classify(
            surface: surface,
            partOfSpeech: partOfSpeech,
            occurrences: occurrences
        )
        let cognate = exception.isException ? nil : CognateMatcher.koreanCognate(from: occurrences)
        return WordAnalysis(
            surface: surface,
            reading: reading,
            occurrences: occurrences,
            isException: exception.isException,
            exceptionReason: exception.reason,
            cognateKO: cognate,
            dominantKind: kind
        )
    }
}
