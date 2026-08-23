//
//  ReadingAligner.swift
//  Kanjiyomi
//

import Foundation

enum ReadingAligner {
    static func align(surface: String, reading: String, catalog: KanjiCatalog) -> [KanjiOccurrence] {
        let tokens = KanjiExtractor.tokens(in: surface)
        let normalized = KanaNormalizer.toHiragana(reading)
        let kanjiTokens = tokens.compactMap { token -> Character? in
            if case .kanji(let character) = token { return character }
            return nil
        }

        guard !kanjiTokens.isEmpty else { return [] }

        if let matched = match(tokens: tokens, reading: normalized, catalog: catalog) {
            return matched
        }

        return kanjiTokens.enumerated().map { index, kanji in
            let meta = catalog.meta(for: kanji)
            return KanjiOccurrence(
                kanji: kanji,
                index: index,
                reading: "",
                kind: .unknown,
                hanjaKO: meta?.hanjaKO ?? "",
                isAligned: false
            )
        }
    }

    private static func match(
        tokens: [ScriptToken],
        reading: String,
        catalog: KanjiCatalog
    ) -> [KanjiOccurrence]? {
        var path: [(character: Character, reading: String, kind: ReadingKind, hanja: String)] = []

        func walk(tokenIndex: Int, readingIndex: String.Index) -> Bool {
            if tokenIndex == tokens.count {
                return readingIndex == reading.endIndex
            }

            switch tokens[tokenIndex] {
            case .kana(let kana):
                let expected = KanaNormalizer.toHiragana(kana)
                guard let end = reading.index(readingIndex, offsetBy: expected.count, limitedBy: reading.endIndex),
                      reading[readingIndex..<end] == expected[...]
                else { return false }
                return walk(tokenIndex: tokenIndex + 1, readingIndex: end)

            case .other:
                return walk(tokenIndex: tokenIndex + 1, readingIndex: readingIndex)

            case .kanji(let character):
                let meta = catalog.meta(for: character)
                let options = candidates(for: meta)
                let remaining = reading[readingIndex...]
                // Longer readings first so きょう wins over き.
                for option in options.sorted(by: { $0.reading.count > $1.reading.count }) {
                    guard remaining.hasPrefix(option.reading) else { continue }
                    let end = reading.index(readingIndex, offsetBy: option.reading.count)
                    path.append((character, option.reading, option.kind, meta?.hanjaKO ?? ""))
                    if walk(tokenIndex: tokenIndex + 1, readingIndex: end) {
                        return true
                    }
                    path.removeLast()
                }
                return false
            }
        }

        guard walk(tokenIndex: 0, readingIndex: reading.startIndex) else { return nil }
        return path.enumerated().map { index, item in
            KanjiOccurrence(
                kanji: item.character,
                index: index,
                reading: item.reading,
                kind: item.kind,
                hanjaKO: item.hanja,
                isAligned: true
            )
        }
    }

    private static func candidates(for meta: KanjiMeta?) -> [(reading: String, kind: ReadingKind)] {
        guard let meta else { return [] }
        var values: [(String, ReadingKind)] = []
        for reading in meta.onReadings {
            for variant in ReadingVariant.expand(reading) {
                values.append((variant, .onyomi))
            }
        }
        for reading in meta.kunReadings {
            let stem = reading.split(separator: ".").first.map(String.init) ?? reading
            for variant in ReadingVariant.expand(stem) {
                values.append((variant, .kunyomi))
            }
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0.0).inserted }
    }
}

enum KanaNormalizer {
    static func toHiragana(_ text: String) -> String {
        String(text.flatMap { character -> [Character] in
            var result: [Character] = []
            for scalar in character.unicodeScalars {
                let value = scalar.value
                if (0x30A1...0x30F6).contains(value) {
                    result.append(Character(UnicodeScalar(value - 0x60)!))
                } else {
                    result.append(Character(scalar))
                }
            }
            return result
        })
    }
}

enum ReadingVariant {
    static func expand(_ reading: String) -> [String] {
        let hiragana = KanaNormalizer.toHiragana(reading)
        var variants = [hiragana]
        if let voiced = rendaku(hiragana), voiced != hiragana {
            variants.append(voiced)
        }
        if let sokuon = sokuonStem(hiragana) {
            variants.append(sokuon)
        }
        return variants
    }

    private static func rendaku(_ reading: String) -> String? {
        guard let first = reading.first, let replacement = voicedMap[first] else { return nil }
        return String(replacement) + reading.dropFirst()
    }

    private static func sokuonStem(_ reading: String) -> String? {
        guard reading.count >= 2, let last = reading.last, ["く", "き", "ち", "つ"].contains(last) else {
            return nil
        }
        return String(reading.dropLast()) + "っ"
    }

    private static let voicedMap: [Character: Character] = [
        "か": "が", "き": "ぎ", "く": "ぐ", "け": "げ", "こ": "ご",
        "さ": "ざ", "し": "じ", "す": "ず", "せ": "ぜ", "そ": "ぞ",
        "た": "だ", "ち": "ぢ", "つ": "づ", "て": "で", "と": "ど",
        "は": "ば", "ひ": "び", "ふ": "ぶ", "へ": "べ", "ほ": "ぼ"
    ]
}
