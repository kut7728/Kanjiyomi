//
//  KanaRomanizerTests.swift
//  KanjiyomiTests
//

import Testing
@testable import Kanjiyomi

struct KanaRomanizerTests {
    @Test func hiraganaBasic() {
        #expect(KanaRomanizer.toHangul("たべる") == "타베루")
        #expect(KanaRomanizer.toHangul("こんにちは") == "콘니치하")
    }

    @Test func nAsFinalConsonant() {
        #expect(KanaRomanizer.toHangul("ほんじつ") == "혼지츠")
        #expect(KanaRomanizer.toHangul("ぜんぴん") == "젠핀")
        #expect(KanaRomanizer.toHangul("セール") == "세루")
        #expect(KanaRomanizer.toHangul("ん") == "응")
    }

    @Test func katakanaAndDigraph() {
        #expect(KanaRomanizer.toHangul("コーヒー") == "코히")
        #expect(KanaRomanizer.toHangul("きゃく") == "캬쿠")
        #expect(KanaRomanizer.toHangul("しょうゆ") == "쇼우유")
    }
}
