//
//  MeaningService.swift
//  Kanjiyomi
//

import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

struct EnrichedWord: Sendable {
    var reading: String
    var hangul: String
    var meaningKO: String
    var meaningEN: String
    var partOfSpeech: String
    var examples: [WordExample]
}

@MainActor
final class MeaningService {
    static let shared = MeaningService()

    private init() {}

    func enrich(
        surface: String,
        lemma: String,
        modelContext: ModelContext
    ) async -> EnrichedWord {
        let cacheKey = WordCache.makeKey(surface: surface, lemma: lemma)
        if let cached = fetchCache(key: cacheKey, context: modelContext) {
            // Rows written while the model was unavailable hold an English gloss;
            // drop them so the Korean meaning can be generated on a later run.
            if Self.containsHangul(cached.meaningKO) {
                return EnrichedWord(
                    reading: cached.reading,
                    hangul: cached.hangul,
                    meaningKO: cached.meaningKO,
                    meaningEN: cached.meaningEN,
                    partOfSpeech: cached.partOfSpeech,
                    examples: cached.examples
                )
            }
            modelContext.delete(cached)
        }

        let dict = DictionaryService.shared.lookup(surface: surface, lemma: lemma)
        let reading = dict?.reading.isEmpty == false ? dict!.reading : guessReading(surface: surface, lemma: lemma)
        let hangul = KanaRomanizer.toHangul(reading)
        let meaningEN = dict?.glossEN ?? ""
        let pos = dict?.partOfSpeech ?? ""

        var meaningKO = ""
        var examples: [WordExample] = []

        if let generated = await generateWithFoundationModels(
            surface: surface,
            lemma: lemma,
            reading: reading,
            englishGloss: meaningEN
        ) {
            meaningKO = generated.koreanMeaning
            examples = [
                WordExample(japanese: generated.exampleJapanese1, korean: generated.exampleKorean1),
                WordExample(japanese: generated.exampleJapanese2, korean: generated.exampleKorean2)
            ]
        } else {
            meaningKO = meaningEN.isEmpty ? "" : meaningEN
        }

        let enriched = EnrichedWord(
            reading: reading,
            hangul: hangul,
            meaningKO: meaningKO,
            meaningEN: meaningEN,
            partOfSpeech: pos,
            examples: examples
        )
        saveCache(key: cacheKey, surface: surface, lemma: lemma, word: enriched, context: modelContext)
        return enriched
    }

    private struct GeneratedContent {
        var koreanMeaning: String
        var exampleJapanese1: String
        var exampleKorean1: String
        var exampleJapanese2: String
        var exampleKorean2: String
    }

    private func generateWithFoundationModels(
        surface: String,
        lemma: String,
        reading: String,
        englishGloss: String
    ) async -> GeneratedContent? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await generateWithFoundationModelsImpl(
                surface: surface,
                lemma: lemma,
                reading: reading,
                englishGloss: englishGloss
            )
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    private static let instructions = """
    You help Korean learners of Japanese.
    Given a Japanese word with optional English gloss, return a concise Korean meaning \
    and exactly two short natural example sentences with Korean translations.
    Always answer in Korean. Never answer in English.
    Keep meanings short (under 25 Korean characters when possible).
    """

    @available(iOS 26.0, *)
    private func generateWithFoundationModelsImpl(
        surface: String,
        lemma: String,
        reading: String,
        englishGloss: String
    ) async -> GeneratedContent? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            print("[MeaningService] Model unavailable: \(model.availability)")
            return nil
        }

        // A fresh session per word keeps the transcript from growing until it
        // overflows the context window, which previously made later words fall back to English.
        let session = LanguageModelSession(instructions: Self.instructions)
        let prompt = """
        Japanese word: \(surface)
        Lemma: \(lemma)
        Reading (kana): \(reading)
        English gloss (optional): \(englishGloss.isEmpty ? "n/a" : englishGloss)
        """
        do {
            let response = try await session.respond(to: prompt, generating: GeneratedWordContent.self)
            let content = response.content
            guard !content.koreanMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return GeneratedContent(
                koreanMeaning: content.koreanMeaning,
                exampleJapanese1: content.exampleJapanese1,
                exampleKorean1: content.exampleKorean1,
                exampleJapanese2: content.exampleJapanese2,
                exampleKorean2: content.exampleKorean2
            )
        } catch {
            print("[MeaningService] Foundation Models failed for \(surface): \(error)")
            return nil
        }
    }
    #endif

    private func guessReading(surface: String, lemma: String) -> String {
        if isKanaOnly(surface) { return surface }
        if isKanaOnly(lemma) { return lemma }
        return surface
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    }

    private func isKanaOnly(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            let v = scalar.value
            return (0x3040...0x309F).contains(v)
                || (0x30A0...0x30FF).contains(v)
                || v == 0x30FC // prolonged sound mark
        }
    }

    private func fetchCache(key: String, context: ModelContext) -> WordCache? {
        var descriptor = FetchDescriptor<WordCache>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func saveCache(
        key: String,
        surface: String,
        lemma: String,
        word: EnrichedWord,
        context: ModelContext
    ) {
        let ex = word.examples
        let cache = WordCache(
            key: key,
            surface: surface,
            lemma: lemma,
            reading: word.reading,
            hangul: word.hangul,
            meaningKO: word.meaningKO,
            meaningEN: word.meaningEN,
            partOfSpeech: word.partOfSpeech,
            exampleJP1: ex.count > 0 ? ex[0].japanese : "",
            exampleKO1: ex.count > 0 ? ex[0].korean : "",
            exampleJP2: ex.count > 1 ? ex[1].japanese : "",
            exampleKO2: ex.count > 1 ? ex[1].korean : ""
        )
        context.insert(cache)
        try? context.save()
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "Japanese word meaning and example sentences for Korean learners")
struct GeneratedWordContent {
    @Guide(description: "Concise Korean meaning of the Japanese word")
    var koreanMeaning: String

    @Guide(description: "First short Japanese example sentence using the word")
    var exampleJapanese1: String

    @Guide(description: "Korean translation of the first example")
    var exampleKorean1: String

    @Guide(description: "Second short Japanese example sentence using the word")
    var exampleJapanese2: String

    @Guide(description: "Korean translation of the second example")
    var exampleKorean2: String
}
#endif
