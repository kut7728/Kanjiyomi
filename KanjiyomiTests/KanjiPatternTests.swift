//
//  KanjiPatternTests.swift
//  KanjiyomiTests
//

import Testing
@testable import Kanjiyomi

struct StubKanjiCatalog: KanjiCatalog {
    var metas: [Character: KanjiMeta]
    var irregulars: Set<String>

    func meta(for kanji: Character) -> KanjiMeta? { metas[kanji] }

    func isIrregular(surface: String, reading: String) -> Bool {
        irregulars.contains("\(surface)|\(reading)")
    }

    func wordsContaining(_ kanji: Character, limit: Int) -> [DictionaryEntry] {
        []
    }

    static let learningFixture = StubKanjiCatalog(
        metas: [
            "経": KanjiMeta(kanji: "経", hanjaKO: "경", onReadings: ["けい", "きょう"], kunReadings: ["へる", "たつ"]),
            "済": KanjiMeta(kanji: "済", hanjaKO: "제", onReadings: ["さい", "せい"], kunReadings: ["すむ"]),
            "験": KanjiMeta(kanji: "験", hanjaKO: "험", onReadings: ["けん", "げん"], kunReadings: []),
            "営": KanjiMeta(kanji: "営", hanjaKO: "영", onReadings: ["えい"], kunReadings: ["いとなむ"]),
            "書": KanjiMeta(kanji: "書", hanjaKO: "서", onReadings: ["しょ"], kunReadings: ["か"]),
            "類": KanjiMeta(kanji: "類", hanjaKO: "류", onReadings: ["るい"], kunReadings: []),
            "今": KanjiMeta(kanji: "今", hanjaKO: "금", onReadings: ["こん", "きん"], kunReadings: ["いま"]),
            "日": KanjiMeta(kanji: "日", hanjaKO: "일", onReadings: ["にち", "じつ"], kunReadings: ["ひ", "か"]),
            "学": KanjiMeta(kanji: "学", hanjaKO: "학", onReadings: ["がく"], kunReadings: ["まなぶ"]),
            "国": KanjiMeta(kanji: "国", hanjaKO: "국", onReadings: ["こく"], kunReadings: ["くに"]),
            "新": KanjiMeta(kanji: "新", hanjaKO: "신", onReadings: ["しん"], kunReadings: ["あたらしい", "あらた"]),
            "安": KanjiMeta(kanji: "安", hanjaKO: "안", onReadings: ["あん"], kunReadings: ["やすい"])
        ],
        irregulars: ["今日|きょう", "大人|おとな", "一人|ひとり", "為替|かわせ", "梅雨|つゆ"]
    )
}

struct KanjiExtractorTests {
    @Test func extractsKanjiInOrder() {
        #expect(KanjiExtractor.kanjiCharacters(in: "経済") == ["経", "済"])
        #expect(KanjiExtractor.kanjiCharacters(in: "書く") == ["書"])
        #expect(KanjiExtractor.kanjiCharacters(in: "けいざい").isEmpty)
    }

    @Test func splitsKanjiAndOkurigana() {
        #expect(KanjiExtractor.tokens(in: "書く") == [.kanji("書"), .kana("く")])
        #expect(KanjiExtractor.tokens(in: "経済") == [.kanji("経"), .kanji("済")])
    }
}

struct ReadingAlignerTests {
    private let catalog = StubKanjiCatalog.learningFixture

    @Test func alignsSinoJapaneseCompound() {
        let parts = ReadingAligner.align(surface: "経済", reading: "けいざい", catalog: catalog)
        #expect(parts.map(\.kanji) == ["経", "済"])
        #expect(parts.map(\.reading) == ["けい", "ざい"])
        #expect(parts.allSatisfy { $0.isAligned })
        #expect(parts.map(\.kind) == [.onyomi, .onyomi])
    }

    @Test func alignsSharedKeiPattern() {
        let keiken = ReadingAligner.align(surface: "経験", reading: "けいけん", catalog: catalog)
        #expect(keiken.map(\.reading) == ["けい", "けん"])

        let keiei = ReadingAligner.align(surface: "経営", reading: "けいえい", catalog: catalog)
        #expect(keiei.map(\.reading) == ["けい", "えい"])
    }

    @Test func alignsKunyomiVerbStem() {
        let parts = ReadingAligner.align(surface: "書く", reading: "かく", catalog: catalog)
        #expect(parts.count == 1)
        #expect(parts[0].kanji == "書")
        #expect(parts[0].reading == "か")
        #expect(parts[0].kind == .kunyomi)
    }

    @Test func failsOnIrregularJukujikun() {
        let parts = ReadingAligner.align(surface: "今日", reading: "きょう", catalog: catalog)
        #expect(parts.allSatisfy { !$0.isAligned })
    }
}

struct ExceptionClassifierTests {
    private let catalog = StubKanjiCatalog.learningFixture

    @Test func flagsCuratedIrregularWords() {
        let result = ExceptionClassifier.classify(
            surface: "今日",
            reading: "きょう",
            occurrences: ReadingAligner.align(surface: "今日", reading: "きょう", catalog: catalog),
            catalog: catalog
        )
        #expect(result.isException)
        #expect(result.reason != nil)
    }

    @Test func leavesRegularCompoundsAlone() {
        let result = ExceptionClassifier.classify(
            surface: "経済",
            reading: "けいざい",
            occurrences: ReadingAligner.align(surface: "経済", reading: "けいざい", catalog: catalog),
            catalog: catalog
        )
        #expect(!result.isException)
    }
}

struct CognateMatcherTests {
    private let catalog = StubKanjiCatalog.learningFixture

    @Test func joinsKoreanHanjaForOnyomiCompounds() {
        let parts = ReadingAligner.align(surface: "経験", reading: "けいけん", catalog: catalog)
        #expect(CognateMatcher.koreanCognate(from: parts) == "경험")
    }

    @Test func skipsKunyomiWords() {
        let parts = ReadingAligner.align(surface: "書く", reading: "かく", catalog: catalog)
        #expect(CognateMatcher.koreanCognate(from: parts) == nil)
    }
}

struct OnKunClassifierTests {
    @Test func treatsNounCompoundsAsOnyomi() {
        let kind = OnKunClassifier.classify(
            surface: "経済",
            partOfSpeech: "noun (common) (futsuumeishi)",
            occurrences: [
                KanjiOccurrence(kanji: "経", index: 0, reading: "けい", kind: .onyomi, hanjaKO: "경", isAligned: true),
                KanjiOccurrence(kanji: "済", index: 1, reading: "ざい", kind: .onyomi, hanjaKO: "제", isAligned: true)
            ]
        )
        #expect(kind == .onyomi)
    }

    @Test func treatsOkuriganaVerbsAsKunyomi() {
        let kind = OnKunClassifier.classify(
            surface: "書く",
            partOfSpeech: "Godan verb with 'ku' ending;transitive verb",
            occurrences: [
                KanjiOccurrence(kanji: "書", index: 0, reading: "か", kind: .kunyomi, hanjaKO: "서", isAligned: true)
            ]
        )
        #expect(kind == .kunyomi)
    }
}

struct PatternDetectorTests {
    private let catalog = StubKanjiCatalog.learningFixture

    @Test func discoversRepeatedOnyomi() {
        let observations = PatternDetector.detect(
            from: [
                ("経済", "けいざい"),
                ("経験", "けいけん"),
                ("経営", "けいえい")
            ],
            catalog: catalog
        )
        let kei = observations.first { $0.kanji == "経" && $0.observedReading == "けい" }
        #expect(kei?.wordCount == 3)
        #expect(kei?.status == .discovered)
    }

    @Test func keepsASingleExampleEmerging() {
        let observations = PatternDetector.detect(
            from: [("経済", "けいざい")],
            catalog: catalog
        )
        let kei = observations.first { $0.kanji == "経" }
        #expect(kei?.status == .emerging)
        #expect(kei?.wordCount == 1)
    }
}

struct InferenceQuizBuilderTests {
    private let catalog = StubKanjiCatalog.learningFixture

    @Test func asksReadingOfAnUnseenWord() {
        let question = InferenceQuizBuilder.makeQuestion(
            learned: [
                ("経済", "けいざい"),
                ("経験", "けいけん")
            ],
            candidates: [
                DictionaryEntry(kanji: "経営", reading: "けいえい", partOfSpeech: "noun", glossEN: "management")
            ],
            catalog: catalog
        )
        #expect(question?.surface == "経営")
        #expect(question?.answer == "けいえい")
        #expect(question?.choices.contains("けいえい") == true)
        #expect(question?.choices.count == 4)
        #expect(Set(question?.choices ?? []).count == 4)
    }

    @Test func skipsWordsAlreadyLearned() {
        let question = InferenceQuizBuilder.makeQuestion(
            learned: [("経営", "けいえい"), ("経済", "けいざい")],
            candidates: [
                DictionaryEntry(kanji: "経営", reading: "けいえい", partOfSpeech: "noun", glossEN: "management")
            ],
            catalog: catalog
        )
        #expect(question == nil)
    }
}

struct RelatedReviewBuilderTests {
    @Test func boostsALearnedRelativeAfterAMiss() {
        let extras = RelatedReviewBuilder.boostQuestions(
            missedSurface: "経済",
            learned: [
                ("経済", "けいざい", "경제"),
                ("経験", "けいけん", "경험"),
                ("経営", "けいえい", "경영")
            ],
            catalog: StubKanjiCatalog.learningFixture
        )
        #expect(extras.contains { $0.prompt == "経験" || $0.prompt == "経営" })
        #expect(extras.count <= 2)
    }
}
