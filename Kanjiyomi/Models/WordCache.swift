//
//  WordCache.swift
//  Kanjiyomi
//

import Foundation
import SwiftData

@Model
final class WordCache {
    @Attribute(.unique) var key: String
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
    var updatedAt: Date

    init(
        key: String,
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
        updatedAt: Date = .now
    ) {
        self.key = key
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
        self.updatedAt = updatedAt
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

    static func makeKey(surface: String, lemma: String) -> String {
        "\(surface)|\(lemma)"
    }
}
