//
//  VocabWord.swift
//  Kanjiyomi
//

import CoreGraphics
import Foundation
import SwiftData

@Model
final class VocabWord {
    @Attribute(.unique) var id: UUID
    var surface: String
    var lemma: String
    var reading: String
    var hangul: String
    var meaningKO: String
    var meaningEN: String
    var partOfSpeech: String
    var exampleJP1: String
    var exampleKO1: String
    var exampleJP2: String
    var exampleKO2: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        surface: String,
        lemma: String,
        reading: String,
        hangul: String,
        meaningKO: String,
        meaningEN: String = "",
        partOfSpeech: String = "",
        exampleJP1: String = "",
        exampleKO1: String = "",
        exampleJP2: String = "",
        exampleKO2: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.surface = surface
        self.lemma = lemma
        self.reading = reading
        self.hangul = hangul
        self.meaningKO = meaningKO
        self.meaningEN = meaningEN
        self.partOfSpeech = partOfSpeech
        self.exampleJP1 = exampleJP1
        self.exampleKO1 = exampleKO1
        self.exampleJP2 = exampleJP2
        self.exampleKO2 = exampleKO2
        self.createdAt = createdAt
    }

    var displayHeadword: String {
        surface.isEmpty ? lemma : surface
    }

    var displayMeaning: String {
        if !meaningKO.isEmpty { return meaningKO }
        if !meaningEN.isEmpty { return meaningEN }
        return "뜻 없음"
    }

    var examples: [WordExample] {
        var result: [WordExample] = []
        if !exampleJP1.isEmpty {
            result.append(WordExample(japanese: exampleJP1, korean: exampleKO1))
        }
        if !exampleJP2.isEmpty {
            result.append(WordExample(japanese: exampleJP2, korean: exampleKO2))
        }
        return result
    }

    convenience init(from word: RecognizedWord) {
        let ex = word.examples
        self.init(
            surface: word.surface,
            lemma: word.lemma,
            reading: word.reading,
            hangul: word.hangul,
            meaningKO: word.meaningKO,
            meaningEN: word.meaningEN,
            partOfSpeech: word.partOfSpeech,
            exampleJP1: ex.count > 0 ? ex[0].japanese : "",
            exampleKO1: ex.count > 0 ? ex[0].korean : "",
            exampleJP2: ex.count > 1 ? ex[1].japanese : "",
            exampleKO2: ex.count > 1 ? ex[1].korean : ""
        )
    }

    func toRecognizedWord() -> RecognizedWord {
        RecognizedWord(
            surface: surface,
            lemma: lemma,
            reading: reading,
            hangul: hangul,
            meaningKO: meaningKO,
            meaningEN: meaningEN,
            partOfSpeech: partOfSpeech,
            examples: examples,
            quads: []
        )
    }
}
