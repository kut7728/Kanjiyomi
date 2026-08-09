//
//  KanaRomanizerTests.swift
//  KanjiyomiTests
//

import Testing
@testable import Kanjiyomi

struct KanaRomanizerTests {
    @Test func hiraganaBasic() {
        #expect(KanaRomanizer.toHangul("たべる") == "타베루")
        #expect(KanaRomanizer.toHangul("こんにちは") == "코응니치하")
    }

    @Test func katakanaAndDigraph() {
        #expect(KanaRomanizer.toHangul("コーヒー") == "코히")
        #expect(KanaRomanizer.toHangul("きゃく") == "캬쿠")
        #expect(KanaRomanizer.toHangul("しょうゆ") == "쇼우유")
    }
}
