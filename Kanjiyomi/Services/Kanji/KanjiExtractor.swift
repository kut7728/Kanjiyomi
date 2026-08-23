//
//  KanjiExtractor.swift
//  Kanjiyomi
//

import Foundation

enum KanjiExtractor {
    static func isKanji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || scalar.value == 0x3005
        }
    }

    static func isKana(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
        }
    }

    static func kanjiCharacters(in text: String) -> [Character] {
        text.filter(isKanji).map { $0 }
    }

    static func tokens(in text: String) -> [ScriptToken] {
        var tokens: [ScriptToken] = []
        var kanaBuffer = ""
        var otherBuffer = ""

        func flushKana() {
            if !kanaBuffer.isEmpty {
                tokens.append(.kana(kanaBuffer))
                kanaBuffer = ""
            }
        }

        func flushOther() {
            if !otherBuffer.isEmpty {
                tokens.append(.other(otherBuffer))
                otherBuffer = ""
            }
        }

        for character in text {
            if isKanji(character) {
                flushKana()
                flushOther()
                tokens.append(.kanji(character))
            } else if isKana(character) {
                flushOther()
                kanaBuffer.append(character)
            } else {
                flushKana()
                otherBuffer.append(character)
            }
        }
        flushKana()
        flushOther()
        return tokens
    }
}
