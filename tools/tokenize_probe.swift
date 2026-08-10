// Offline check for the word boundaries TokenizerService produces.
//
// NLTokenizer over-splits Japanese compounds and NLTagger has no Japanese lemma or
// lexical-class model, so the bundled dictionary is the only signal for where a word
// ends. This mirrors TokenizerService so the merge limits can be retuned without a
// device build. Run from the repo root:
//
//   swift tools/tokenize_probe.swift

import Foundation
import NaturalLanguage
import SQLite3

let dbPath = "Kanjiyomi/Resources/jmdict.sqlite"

final class Dict {
    static let shared = Dict()
    private var db: OpaquePointer?
    private var cache: [String: Bool] = [:]
    private(set) var queryCount = 0

    init() {
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            fatalError("cannot open \(dbPath) — run tools/build_dict.py first")
        }
    }

    func exists(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        if let cached = cache[word] { return cached }
        queryCount += 1

        var stmt: OpaquePointer?
        let sql = "SELECT 1 FROM entries WHERE kanji = ?1 OR reading = ?1 LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        let ns = word as NSString
        sqlite3_bind_text(stmt, 1, ns.utf8String, -1, nil)
        let found = sqlite3_step(stmt) == SQLITE_ROW
        cache[word] = found
        return found
    }
}

// MARK: - Mirror of TokenizerService

struct TokenRange {
    let surface: String
    let lemma: String
    let range: Range<String.Index>
}

let stopLemmas: Set<String> = [
    "の", "に", "は", "を", "が", "と", "で", "も", "へ", "や",
    "から", "まで", "より", "ね", "よ", "な", "さ", "か", "だ",
    "です", "ます", "する", "いる", "ある", "れる", "られる",
    "て", "た", "ない", "ん", "って", "こと", "もの"
]

let conjugationTails: Set<String> = [
    "なり", "あり", "おり", "でき", "かけ", "つき", "いた", "てい", "して", "した",
    "しま", "います", "ます", "ました", "ません", "れて", "られ", "せて", "つつ",
    "とり", "なっ", "だっ", "よう", "そう", "ため"
]

let maxMergeCount = 6
let maxMergeLength = 12

func tokenRanges(in text: String) -> [TokenRange] {
    let pieces = rawPieces(in: text)
    var result: [TokenRange] = []
    var index = 0

    while index < pieces.count {
        guard canStartWord(pieces[index]) else {
            index += 1
            continue
        }
        let (token, consumed) = longestDictionaryMatch(from: index, in: pieces, text: text)
        if shouldKeep(token) { result.append(token) }
        index += consumed
    }
    return result
}

func rawPieces(in text: String) -> [TokenRange] {
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    tokenizer.setLanguage(.japanese)

    let tagger = NLTagger(tagSchemes: [.lemma])
    tagger.string = text
    tagger.setLanguage(.japanese, range: text.startIndex..<text.endIndex)

    var pieces: [TokenRange] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        let surface = String(text[range])
        let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
        pieces.append(TokenRange(surface: surface, lemma: lemma ?? surface, range: range))
        return true
    }
    return pieces
}

func canStartWord(_ piece: TokenRange) -> Bool {
    guard containsJapanese(piece.surface), !isMostlyPunctuation(piece.surface) else { return false }
    return !stopLemmas.contains(piece.surface)
}

func longestDictionaryMatch(
    from start: Int,
    in pieces: [TokenRange],
    text: String
) -> (TokenRange, Int) {
    var end = min(pieces.count, start + maxMergeCount)
    while end > start + 1 {
        if isContiguous(pieces, from: start, to: end) {
            let range = pieces[start].range.lowerBound..<pieces[end - 1].range.upperBound
            let surface = String(text[range])
            if surface.count <= maxMergeLength, Dict.shared.exists(surface) {
                return (TokenRange(surface: surface, lemma: surface, range: range), end - start)
            }
        }
        end -= 1
    }
    return (pieces[start], 1)
}

func isContiguous(_ pieces: [TokenRange], from start: Int, to end: Int) -> Bool {
    var index = start
    while index < end - 1 {
        if pieces[index].range.upperBound != pieces[index + 1].range.lowerBound { return false }
        index += 1
    }
    return true
}

func shouldKeep(_ token: TokenRange) -> Bool {
    if stopLemmas.contains(token.lemma) || stopLemmas.contains(token.surface) { return false }
    if conjugationTails.contains(token.surface) { return false }
    if token.surface.count == 1, isKana(token.surface) { return false }
    return Dict.shared.exists(token.surface) || Dict.shared.exists(token.lemma)
}

func isKana(_ text: String) -> Bool {
    text.unicodeScalars.allSatisfy { s in
        let v = s.value
        return (0x3040...0x309F).contains(v) || (0x30A0...0x30FF).contains(v) || (0xFF66...0xFF9D).contains(v)
    }
}

func containsJapanese(_ text: String) -> Bool {
    text.unicodeScalars.contains { s in
        let v = s.value
        return (0x3040...0x309F).contains(v) || (0x30A0...0x30FF).contains(v)
            || (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
            || (0xFF66...0xFF9D).contains(v)
    }
}

func isMostlyPunctuation(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    let punct = CharacterSet.punctuationCharacters.union(.symbols)
    return trimmed.unicodeScalars.allSatisfy { punct.contains($0) }
}

// MARK: - Signage and flyer lines, the kind the camera actually sees

let samples = [
    "本日限定セール開催中",
    "営業時間は午前9時から午後6時まで",
    "駐車場のご利用はお客様専用です",
    "関係者以外立入禁止",
    "お問い合わせは受付までお願いします",
    "全品半額の大特価",
    "定期券売り場はこちら",
    "新宿駅東口改札を出て右",
    "消費税込みの価格表示",
    "使用方法をよくお読みください",
    "年末年始休業のお知らせ",
    "自動販売機で予約受付中",
    "無料駐輪場を利用できます",
    "手荷物一時預かり所",
    "非常口はこちらです",
    "当店は年中無休で営業しております",
    "こちらの商品は数量限定販売となります",
    "改札口で切符を拝見いたします",
    "写真撮影は禁止されています",
    "係員の指示に従ってください",
    "本日は誠にありがとうございます",
    "階段は右手にございます",
    "お支払いは現金のみとなります",
    "工事中につきご迷惑をおかけします",
    "喫煙所は建物の外にあります",
    "宿泊予約はこちらの窓口へ",
    "取扱注意 割れ物在中",
    "特急券が必要です"
]

var total = 0
for line in samples {
    let tokens = tokenRanges(in: line).map(\.surface)
    total += tokens.count
    print(line)
    print("  → \(tokens.joined(separator: " / "))")
}
print("\n\(total) tokens from \(samples.count) lines, \(Dict.shared.queryCount) dictionary lookups")
