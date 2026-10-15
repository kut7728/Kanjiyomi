import Foundation
import SQLite3
import SwiftData
import Testing
@testable import Kanjiyomi

@MainActor
struct DictionaryTests {
    private struct Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dictionary: DictionaryService

        init() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let main = directory.appendingPathComponent("main.sqlite")
            let korean = directory.appendingPathComponent("korean.sqlite")
            try Self.write(main, sql: """
                CREATE TABLE entries(kanji TEXT, reading TEXT, pos TEXT, gloss TEXT);
                INSERT INTO entries VALUES
                    ('半額', 'はんがく', 'noun', 'half price'),
                    ('入口', 'いりぐち', 'noun', 'entrance'),
                    ('人気', 'にんき', 'noun', 'popularity'),
                    ('人気', 'ひとけ', 'noun', 'sign of people'),
                    ('利用', 'りよう', 'noun', 'use'),
                    ('買い物', 'かいもの', 'noun', 'shopping'),
                    ('', 'ありがとう', 'expression', 'thank you');
                CREATE TABLE kanji_index(kanji TEXT, surface TEXT, reading TEXT, pos TEXT, gloss TEXT);
                INSERT INTO kanji_index VALUES ('半', '半額', 'はんがく', 'noun', 'half price');
                """)
            try Self.write(korean, sql: """
                CREATE TABLE meanings(written TEXT, reading TEXT, meaning TEXT, PRIMARY KEY(written, reading));
                INSERT INTO meanings VALUES
                    ('半額', 'はんがく', '반값'),
                    ('人気', 'にんき', '인기'),
                    ('利用', 'りよう', '이용'),
                    ('買い物', 'かいもの', '쇼핑'),
                    ('ありがとう', 'ありがとう', '고마워');
                """)
            dictionary = DictionaryService(databaseURL: main, koreanURL: korean)
        }

        private static func write(_ url: URL, sql: String) throws {
            var db: OpaquePointer?
            #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
            defer { sqlite3_close(db) }
            let result = sqlite3_exec(db, sql, nil, nil, nil)
            #expect(result == SQLITE_OK)
            if result != SQLITE_OK { throw CocoaError(.fileWriteUnknown) }
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: WordCache.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func looksUpKoreanByWrittenFormAndReadingAcrossCallers() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(fixture.dictionary.lookup(surface: "半額", lemma: "半額")?.glossKO == "반값")
        #expect(fixture.dictionary.search("half").first?.displayMeaning == "반값")
        #expect(fixture.dictionary.wordsContaining("半", limit: 1).first?.glossKO == "반값")
        let readings = fixture.dictionary.search("人気")
        #expect(readings.first { $0.reading == "にんき" }?.glossKO == "인기")
        #expect(readings.first { $0.reading == "ひとけ" }?.glossKO == "")
        #expect(fixture.dictionary.lookup(surface: "ありがとう", lemma: "ありがとう")?.glossKO == "고마워")
        #expect(fixture.dictionary.lookup(surface: "お買い物", lemma: "お買い物")?.glossKO == "쇼핑")
    }

    @Test func keepsEnglishWhenKoreanIsMissingOrUnavailable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(fixture.dictionary.lookup(surface: "入口", lemma: "入口")?.displayMeaning == "entrance")
        let missing = fixture.directory.appendingPathComponent("missing.sqlite")
        let dictionary = DictionaryService(databaseURL: fixture.directory.appendingPathComponent("main.sqlite"), koreanURL: missing)
        #expect(dictionary.lookup(surface: "半額", lemma: "半額")?.displayMeaning == "half price")
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        let invalid = fixture.directory.appendingPathComponent("invalid.sqlite")
        try Data("invalid SQLite".utf8).write(to: invalid)
        let invalidDictionary = DictionaryService(databaseURL: fixture.directory.appendingPathComponent("main.sqlite"), koreanURL: invalid)
        #expect(invalidDictionary.lookup(surface: "半額", lemma: "半額")?.glossEN == "half price")
        #expect(invalidDictionary.lookup(surface: "半額", lemma: "半額")?.glossKO == "")
    }

    @Test func fillsOldEnglishOnlyCacheWithoutCallingAI() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let context = try context()
        let cached = WordCache(key: "半額|半額", surface: "半額", lemma: "半額", reading: "はんがく", hangul: "한가쿠", meaningKO: "", meaningEN: "half price")
        context.insert(cached)
        let result = MeaningService(dictionary: fixture.dictionary).resolve(surface: "半額", lemma: "半額", modelContext: context)
        #expect(result.meaningKO == "반값")
        #expect(result.meaningEN == "half price")
        #expect(cached.isMeaning(from: .dictionary))
        #expect(!RecognizedWord(surface: "半額", lemma: "半額", reading: result.reading, meaningKO: result.meaningKO).needsGeneration)
    }

    @Test func preservesExistingAIMeaning() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let context = try context()
        let cached = WordCache(key: "半額|半額", surface: "半額", lemma: "半額", reading: "はんがく", hangul: "한가쿠", meaningKO: "기존 AI 뜻", meaningSource: .foundation)
        context.insert(cached)
        #expect(MeaningService(dictionary: fixture.dictionary).resolve(surface: "半額", lemma: "半額", modelContext: context).meaningKO == "기존 AI 뜻")
        #expect(cached.isMeaning(from: .foundation))
    }

    @Test func refreshesDictionaryCacheAndDropsExamplesOfTheOldMeaning() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let context = try context()
        let cached = WordCache(key: "半額|半額", surface: "半額", lemma: "半額", reading: "はんがく", hangul: "", meaningKO: "예전 뜻", exampleJP1: "old", meaningSource: .dictionary)
        context.insert(cached)
        let service = MeaningService(dictionary: fixture.dictionary)
        #expect(service.resolve(surface: "半額", lemma: "半額", modelContext: context).meaningKO == "반값")
        #expect(cached.meaningKO == "반값")
        #expect(cached.examples.isEmpty)
    }

    @Test func explicitChatGPTPassDoesNotReuseTheBundledMeaning() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let context = try context()
        let service = MeaningService(dictionary: fixture.dictionary)
        _ = service.resolve(surface: "半額", lemma: "半額", modelContext: context)
        let result = service.resolve(surface: "半額", lemma: "半額", modelContext: context, requiredSource: .openAI)
        #expect(result.meaningKO.isEmpty)
        #expect(result.meaningEN == "half price")
        #expect(try context.fetch(FetchDescriptor<WordCache>()).first?.meaningKO == "반값")
    }

    @Test func selectedSearchReadingDoesNotReuseAnotherReadingsMeaning() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let context = try context()
        context.insert(WordCache(key: "人気|人気", surface: "人気", lemma: "人気", reading: "にんき", hangul: "", meaningKO: "인기", meaningSource: .foundation))
        let selected = try #require(fixture.dictionary.search("人気").first { $0.reading == "ひとけ" })
        let result = MeaningService(dictionary: fixture.dictionary).resolve(surface: "人気", lemma: "人気", modelContext: context, dictionaryEntry: selected)
        #expect(result.reading == "ひとけ")
        #expect(result.meaningKO.isEmpty)
        #expect(result.meaningEN == "sign of people")
    }
}
