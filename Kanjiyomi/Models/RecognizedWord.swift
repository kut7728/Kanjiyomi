//
//  RecognizedWord.swift
//  Kanjiyomi
//

import CoreGraphics
import Foundation

struct RecognizedWord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var surface: String
    var lemma: String
    var reading: String
    var hangul: String
    var meaningKO: String
    var meaningEN: String
    var partOfSpeech: String
    var examples: [WordExample]
    /// Every place this word was found, in Vision normalized coordinates.
    var quads: [TextQuad]

    init(
        id: UUID = UUID(),
        surface: String,
        lemma: String,
        reading: String = "",
        hangul: String = "",
        meaningKO: String = "",
        meaningEN: String = "",
        partOfSpeech: String = "",
        examples: [WordExample] = [],
        quads: [TextQuad] = []
    ) {
        self.id = id
        self.surface = surface
        self.lemma = lemma
        self.reading = reading
        self.hangul = hangul
        self.meaningKO = meaningKO
        self.meaningEN = meaningEN
        self.partOfSpeech = partOfSpeech
        self.examples = examples
        self.quads = quads
    }

    var displayHeadword: String {
        surface.isEmpty ? lemma : surface
    }

    /// Still missing something only the model can supply. A word the dictionary does not
    /// list has no reading either, so a meaning on its own does not mean it is finished.
    var needsGeneration: Bool {
        meaningKO.isEmpty || reading.isEmpty
    }

    var displayMeaning: String {
        if !meaningKO.isEmpty { return meaningKO }
        if !meaningEN.isEmpty { return meaningEN }
        return "뜻 없음"
    }
}

struct WordExample: Hashable, Codable, Sendable {
    var japanese: String
    var korean: String
}

struct DictionaryEntry: Hashable, Sendable {
    var kanji: String
    var reading: String
    var partOfSpeech: String
    var glossEN: String
}
