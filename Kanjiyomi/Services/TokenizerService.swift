//
//  TokenizerService.swift
//  Kanjiyomi
//

import CoreGraphics
import Foundation
import NaturalLanguage

struct TokenRange: Sendable {
    let surface: String
    let lemma: String
    let range: Range<String.Index>
}

struct TokenSpan: Sendable {
    let surface: String
    let lemma: String
    let quad: TextQuad
}

nonisolated enum TokenizerService {
    /// Particle / function-word lemmas to drop from vocabulary lists.
    private static let stopLemmas: Set<String> = [
        "の", "に", "は", "を", "が", "と", "で", "も", "へ", "や",
        "から", "まで", "より", "ね", "よ", "な", "さ", "か", "だ",
        "です", "ます", "する", "いる", "ある", "れる", "られる",
        "て", "た", "ない", "ん", "って", "こと", "もの"
    ]

    /// How many adjacent tokenizer pieces may be joined back into one word.
    private static let maxMergeCount = 4
    private static let maxMergeLength = 8

    static func tokenRanges(in text: String) -> [TokenRange] {
        guard !text.isEmpty else { return [] }

        let pieces = rawPieces(in: text)
        var result: [TokenRange] = []
        var index = 0

        while index < pieces.count {
            let (token, consumed) = longestDictionaryMatch(from: index, in: pieces, text: text)
            if shouldKeep(token) {
                result.append(token)
            }
            index += consumed
        }
        return result
    }

    /// NLTokenizer splits compounds like 高校 into single characters on short OCR lines,
    /// so adjacent pieces are rejoined whenever the merged form is a real dictionary word.
    private static func longestDictionaryMatch(
        from start: Int,
        in pieces: [TokenRange],
        text: String
    ) -> (TokenRange, Int) {
        let maxEnd = min(pieces.count, start + maxMergeCount)
        var end = maxEnd

        while end > start + 1 {
            if isContiguous(pieces, from: start, to: end) {
                let range = pieces[start].range.lowerBound..<pieces[end - 1].range.upperBound
                let surface = String(text[range])
                if surface.count <= maxMergeLength, DictionaryService.shared.exists(surface) {
                    return (TokenRange(surface: surface, lemma: surface, range: range), end - start)
                }
            }
            end -= 1
        }
        return (pieces[start], 1)
    }

    private static func isContiguous(_ pieces: [TokenRange], from start: Int, to end: Int) -> Bool {
        var index = start
        while index < end - 1 {
            if pieces[index].range.upperBound != pieces[index + 1].range.lowerBound {
                return false
            }
            index += 1
        }
        return true
    }

    private static func rawPieces(in text: String) -> [TokenRange] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.japanese)

        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        tagger.setLanguage(.japanese, range: text.startIndex..<text.endIndex)

        var pieces: [TokenRange] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let surface = String(text[range])
            guard containsJapanese(surface), !isMostlyPunctuation(surface) else { return true }

            let lemmaTag = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0
            let lexical = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
            guard lexical != .particle else { return true }

            pieces.append(
                TokenRange(surface: surface, lemma: lemmaTag?.rawValue ?? surface, range: range)
            )
            return true
        }
        return pieces
    }

    private static func shouldKeep(_ token: TokenRange) -> Bool {
        if stopLemmas.contains(token.lemma) || stopLemmas.contains(token.surface) {
            return false
        }
        // Lone kana are almost always particles or leftovers from a split compound.
        if token.surface.count == 1, isKana(token.surface) {
            return false
        }
        // Everything shown must resolve to a real entry, which removes stray characters.
        return DictionaryService.shared.exists(token.surface)
            || DictionaryService.shared.exists(token.lemma)
    }

    private static func isKana(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            let v = scalar.value
            return (0x3040...0x309F).contains(v)
                || (0x30A0...0x30FF).contains(v)
                || (0xFF66...0xFF9D).contains(v)
        }
    }

    private static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x3040...0x309F).contains(v) // hiragana
                || (0x30A0...0x30FF).contains(v) // katakana
                || (0x4E00...0x9FFF).contains(v) // CJK
                || (0x3400...0x4DBF).contains(v)
                || (0xFF66...0xFF9D).contains(v) // halfwidth kana
        }
    }

    private static func isMostlyPunctuation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let punct = CharacterSet.punctuationCharacters.union(.symbols)
        return trimmed.unicodeScalars.allSatisfy { punct.contains($0) }
    }
}
