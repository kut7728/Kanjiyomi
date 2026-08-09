//
//  KanaRomanizer.swift
//  Kanjiyomi
//
//  Deterministic kana → Hangul pronunciation mapping (not LLM).
//

import Foundation

enum KanaRomanizer {
    /// Convert hiragana/katakana reading to approximate Korean Hangul pronunciation.
    static func toHangul(_ kana: String) -> String {
        guard !kana.isEmpty else { return "" }
        let normalized = toHiragana(kana)
            .replacingOccurrences(of: "ー", with: "")
            .replacingOccurrences(of: "っ", with: "")
            .replacingOccurrences(of: "ッ", with: "")

        var result = ""
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let next = normalized.index(after: index)
            var matched: String?
            if next < normalized.endIndex {
                let digraph = String(normalized[index..<normalized.index(after: next)])
                matched = digraphMap[digraph]
                if matched != nil {
                    result += matched!
                    index = normalized.index(after: next)
                    continue
                }
                // Youon: きゃ etc. — already in digraphMap; also handle しゃ style via digraph
            }
            let mono = String(normalized[index])
            if let hangul = monoMap[mono] {
                result += hangul
            } else if isJapanesePunctuation(mono) {
                // skip
            } else {
                result += mono
            }
            index = next
        }

        // Soft cleanup: collapse leftover small ゃ-style if any slipped through
        return result
            .replacingOccurrences(of: "ゃ", with: "야")
            .replacingOccurrences(of: "ゅ", with: "유")
            .replacingOccurrences(of: "ょ", with: "요")
    }

    private static func toHiragana(_ text: String) -> String {
        String(text.unicodeScalars.map { scalar -> Character in
            let v = scalar.value
            // Katakana block → Hiragana
            if (0x30A1...0x30F6).contains(v) {
                return Character(UnicodeScalar(v - 0x60)!)
            }
            return Character(scalar)
        })
    }

    private static func isJapanesePunctuation(_ s: String) -> Bool {
        "・、。！？「」『』（）[]【】 ".contains(s)
    }

    private static let digraphMap: [String: String] = [
        "きゃ": "캬", "きゅ": "큐", "きょ": "쿄",
        "しゃ": "샤", "しゅ": "슈", "しょ": "쇼",
        "ちゃ": "챠", "ちゅ": "츄", "ちょ": "쵸",
        "にゃ": "냐", "にゅ": "뉴", "にょ": "뇨",
        "ひゃ": "햐", "ひゅ": "휴", "ひょ": "효",
        "みゃ": "먀", "みゅ": "뮤", "みょ": "묘",
        "りゃ": "랴", "りゅ": "류", "りょ": "료",
        "ぎゃ": "갸", "ぎゅ": "규", "ぎょ": "교",
        "じゃ": "자", "じゅ": "주", "じょ": "조",
        "びゃ": "뱌", "びゅ": "뷰", "びょ": "뵤",
        "ぴゃ": "퍄", "ぴゅ": "퓨", "ぴょ": "표",
        "ふぁ": "파", "ふぃ": "피", "ふぇ": "페", "ふぉ": "포",
        "てぃ": "티", "でぃ": "디", "とぅ": "투", "どぅ": "두",
        "うぃ": "위", "うぇ": "웨", "うぉ": "워",
        "ヴぁ": "바", "ヴぃ": "비", "ヴぇ": "베", "ヴぉ": "보",
    ]

    private static let monoMap: [String: String] = [
        "あ": "아", "い": "이", "う": "우", "え": "에", "お": "오",
        "か": "카", "き": "키", "く": "쿠", "け": "케", "こ": "코",
        "さ": "사", "し": "시", "す": "스", "せ": "세", "そ": "소",
        "た": "타", "ち": "치", "つ": "츠", "て": "테", "と": "토",
        "な": "나", "に": "니", "ぬ": "누", "ね": "네", "の": "노",
        "は": "하", "ひ": "히", "ふ": "후", "へ": "헤", "ほ": "호",
        "ま": "마", "み": "미", "む": "무", "め": "메", "も": "모",
        "や": "야", "ゆ": "유", "よ": "요",
        "ら": "라", "り": "리", "る": "루", "れ": "레", "ろ": "로",
        "わ": "와", "を": "오", "ん": "응",
        "が": "가", "ぎ": "기", "ぐ": "구", "げ": "게", "ご": "고",
        "ざ": "자", "じ": "지", "ず": "즈", "ぜ": "제", "ぞ": "조",
        "だ": "다", "ぢ": "지", "づ": "즈", "で": "데", "ど": "도",
        "ば": "바", "び": "비", "ぶ": "부", "べ": "베", "ぼ": "보",
        "ぱ": "파", "ぴ": "피", "ぷ": "푸", "ぺ": "페", "ぽ": "포",
        "ぁ": "아", "ぃ": "이", "ぅ": "우", "ぇ": "에", "ぉ": "오",
        "ゃ": "야", "ゅ": "유", "ょ": "요", "ゎ": "와",
        "ゐ": "이", "ゑ": "에", "ゔ": "부",
    ]
}
