//
//  StoreTests.swift
//  KanjiyomiTests
//

import Foundation
import SwiftData
import Testing
@testable import Kanjiyomi

@MainActor
struct KanjiPatternStoreTests {
    private let catalog = StubKanjiCatalog.learningFixture

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: VocabWord.self, UserKanjiPattern.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func word(_ surface: String, _ reading: String) -> VocabWord {
        VocabWord(surface: surface, lemma: surface, reading: reading, hangul: "", meaningKO: "뜻")
    }

    private func pattern(_ key: String, in context: ModelContext) throws -> UserKanjiPattern? {
        try context.fetch(FetchDescriptor<UserKanjiPattern>()).first { $0.key == key }
    }

    @Test func keepsFamiliarEarnedInTheQuizAcrossSyncs() throws {
        let context = try makeContext()
        let words = [word("経済", "けいざい"), word("経験", "けいけん")]
        KanjiPatternStore.sync(from: words, modelContext: context, catalog: catalog)
        for _ in 0..<2 {
            KanjiPatternStore.recordQuiz(kanji: "経", reading: "けい", isCorrect: true, isInference: true, modelContext: context)
        }
        #expect(try pattern("経|けい", in: context)?.status == .familiar)

        KanjiPatternStore.sync(from: words, modelContext: context, catalog: catalog)
        #expect(try pattern("経|けい", in: context)?.status == .familiar)
    }

    @Test func dropsPatternsNoSavedWordShows() throws {
        let context = try makeContext()
        KanjiPatternStore.sync(
            from: [word("経済", "けいざい"), word("経験", "けいけん")],
            modelContext: context,
            catalog: catalog
        )
        #expect(try pattern("経|けい", in: context)?.seenWordCount == 2)

        KanjiPatternStore.sync(from: [word("経済", "けいざい")], modelContext: context, catalog: catalog)
        #expect(try pattern("経|けい", in: context)?.seenWordCount == 1)
        #expect(try pattern("験|けん", in: context) == nil)

        KanjiPatternStore.sync(from: [], modelContext: context, catalog: catalog)
        #expect(try context.fetch(FetchDescriptor<UserKanjiPattern>()).isEmpty)
    }
}

@MainActor
struct VocabularyStoreTests {
    @Test func forgetsADeletedScan() throws {
        let container = try ModelContainer(
            for: VocabWord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let deleted = UUID()
        let kept = UUID()
        let linked = VocabWord(surface: "本日", lemma: "本日", reading: "ほんじつ", hangul: "", meaningKO: "오늘", scanRecordID: deleted)
        let other = VocabWord(surface: "限定", lemma: "限定", reading: "げんてい", hangul: "", meaningKO: "한정", scanRecordID: kept)
        context.insert(linked)
        context.insert(other)

        VocabularyStore.forgetScan(deleted, modelContext: context)

        #expect(linked.scanRecordID == nil)
        #expect(other.scanRecordID == kept)
    }
}
