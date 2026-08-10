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

/// One word queued for Korean meaning generation.
struct MeaningRequest: Sendable {
    var key: String
    var word: String
    var reading: String
    var glossEN: String

    var promptLine: String {
        var line = "- \(word)"
        if !reading.isEmpty, reading != word {
            line += " (\(reading))"
        }
        if !glossEN.isEmpty {
            line += " = \(glossEN)"
        }
        return line
    }
}

@MainActor
final class MeaningService {
    static let shared = MeaningService()

    private var generatorStorage: AnyObject?

    private init() {}

    var isGenerationAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Loads the model before the first request so the scan does not pay for a cold start.
    func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            generator.prewarm()
        }
        #endif
    }

    /// Dictionary and cache only, with no model call. The scan list is built from this
    /// so it can be shown before any Korean meaning has been generated.
    func resolve(surface: String, lemma: String, modelContext: ModelContext) -> EnrichedWord {
        let key = WordCache.makeKey(surface: surface, lemma: lemma)

        if let cached = cacheRow(key: key, context: modelContext) {
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
            // Rows written while the model was unavailable hold an English gloss;
            // drop them so the Korean meaning can be generated on a later run.
            modelContext.delete(cached)
        }

        let dict = DictionaryService.shared.lookup(surface: surface, lemma: lemma)
        let reading = dict?.reading.isEmpty == false ? dict!.reading : guessReading(surface: surface, lemma: lemma)
        let enriched = EnrichedWord(
            reading: reading,
            hangul: KanaRomanizer.toHangul(reading),
            meaningKO: "",
            meaningEN: dict?.glossEN ?? "",
            partOfSpeech: dict?.partOfSpeech ?? "",
            examples: []
        )

        // Tokens with no dictionary hit are dropped by the caller, so there is nothing
        // worth keeping a row for.
        guard !enriched.reading.isEmpty || !enriched.meaningEN.isEmpty else { return enriched }

        // Store the dictionary half now so generation only has to fill in the meaning.
        let row = WordCache(
            key: key,
            surface: surface,
            lemma: lemma,
            reading: enriched.reading,
            hangul: enriched.hangul,
            meaningKO: "",
            meaningEN: enriched.meaningEN,
            partOfSpeech: enriched.partOfSpeech
        )
        modelContext.insert(row)
        return enriched
    }

    /// Korean meanings for a batch of words, keyed by cache key.
    ///
    /// Asking for many words in one request is what makes the scan fast: the schema and
    /// instructions are processed once instead of once per word.
    func generateMeanings(
        for words: [RecognizedWord],
        modelContext: ModelContext
    ) async -> [String: String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let requests = words.map { word in
                MeaningRequest(
                    key: WordCache.makeKey(surface: word.surface, lemma: word.lemma),
                    word: word.displayHeadword,
                    reading: word.reading,
                    glossEN: word.meaningEN
                )
            }
            let produced = await generator.meanings(for: requests)
            guard !produced.isEmpty else { return [:] }

            for (key, meaning) in produced {
                cacheRow(key: key, context: modelContext)?.meaningKO = meaning
            }
            try? modelContext.save()
            return produced
        }
        #endif
        return [:]
    }

    /// Example sentences dominate the generated token count but only ever appear on the
    /// detail screen, so they are produced when that screen opens rather than during a scan.
    func examples(for word: RecognizedWord, modelContext: ModelContext) async -> [WordExample] {
        let key = WordCache.makeKey(surface: word.surface, lemma: word.lemma)
        if let cached = cacheRow(key: key, context: modelContext)?.examples, !cached.isEmpty {
            return cached
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let produced = await generator.examples(
                word: word.displayHeadword,
                reading: word.reading,
                meaning: word.displayMeaning
            )
            guard !produced.isEmpty else { return [] }

            let row = cacheRow(key: key, context: modelContext) ?? {
                let created = WordCache(
                    key: key,
                    surface: word.surface,
                    lemma: word.lemma,
                    reading: word.reading,
                    hangul: word.hangul,
                    meaningKO: word.meaningKO,
                    meaningEN: word.meaningEN,
                    partOfSpeech: word.partOfSpeech
                )
                modelContext.insert(created)
                return created
            }()
            row.exampleJP1 = produced.first?.japanese ?? ""
            row.exampleKO1 = produced.first?.korean ?? ""
            row.exampleJP2 = produced.count > 1 ? produced[1].japanese : ""
            row.exampleKO2 = produced.count > 1 ? produced[1].korean : ""
            try? modelContext.save()
            return produced
        }
        #endif
        return []
    }

    // MARK: - Helpers

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private var generator: MeaningGenerator {
        if let existing = generatorStorage as? MeaningGenerator { return existing }
        let created = MeaningGenerator()
        generatorStorage = created
        return created
    }
    #endif

    private func cacheRow(key: String, context: ModelContext) -> WordCache? {
        var descriptor = FetchDescriptor<WordCache>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

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
}

#if canImport(FoundationModels)

@available(iOS 26.0, *)
@MainActor
private final class MeaningGenerator {
    private static let meaningInstructions = """
    You translate Japanese words for Korean learners.
    For every word you are given, return its meaning in Korean.
    Always answer in Korean. Never answer in English.
    Keep each meaning under 20 Korean characters.
    """

    private static let exampleInstructions = """
    You write example sentences for Korean learners of Japanese.
    Write short natural Japanese sentences and translate each one into Korean.
    Always answer in Korean. Never answer in English.
    """

    /// Reusing a session keeps the model warm, but its transcript grows with every batch,
    /// so it is retired before it can overflow the context window.
    private static let maxBatchesPerSession = 3

    private var meaningSession: LanguageModelSession?
    private var batchesOnSession = 0

    func prewarm() {
        activeMeaningSession().prewarm()
    }

    func meanings(for requests: [MeaningRequest]) async -> [String: String] {
        guard !requests.isEmpty, SystemLanguageModel.default.isAvailable else { return [:] }

        // Matching on the echoed word rather than position survives the model dropping
        // or reordering an entry.
        let keysByWord = Dictionary(requests.map { ($0.word, $0.key) }) { first, _ in first }
        let prompt = """
        Give the Korean meaning of each of these \(requests.count) Japanese words.
        \(requests.map(\.promptLine).joined(separator: "\n"))
        """

        let session = activeMeaningSession()
        batchesOnSession += 1

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedMeaningList.self,
                options: GenerationOptions(
                    sampling: .greedy,
                    maximumResponseTokens: 100 * requests.count
                )
            )
            let items = response.content.items
            var result: [String: String] = [:]
            for item in items {
                let meaning = item.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !meaning.isEmpty, let key = keysByWord[item.word] else { continue }
                result[key] = meaning
            }

            // The model occasionally rewrites the word it echoes back. When it returned
            // the expected number of entries, position is a safe fallback for those.
            if result.count < requests.count, items.count == requests.count {
                for (request, item) in zip(requests, items) where result[request.key] == nil {
                    let meaning = item.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !meaning.isEmpty else { continue }
                    result[request.key] = meaning
                }
            }
            return result
        } catch {
            // A failed turn can leave the transcript unusable, so start from a clean session.
            meaningSession = nil
            print("[MeaningService] meaning batch failed: \(error)")
            return [:]
        }
    }

    func examples(word: String, reading: String, meaning: String) async -> [WordExample] {
        guard SystemLanguageModel.default.isAvailable else { return [] }

        let session = LanguageModelSession(instructions: Self.exampleInstructions)
        let prompt = """
        Japanese word: \(word)
        Reading (kana): \(reading.isEmpty ? "n/a" : reading)
        Meaning: \(meaning.isEmpty ? "n/a" : meaning)
        """

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedExamples.self,
                options: GenerationOptions(maximumResponseTokens: 400)
            )
            let content = response.content
            return [
                WordExample(japanese: content.japanese1, korean: content.korean1),
                WordExample(japanese: content.japanese2, korean: content.korean2)
            ]
            .filter { !$0.japanese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } catch {
            print("[MeaningService] examples failed for \(word): \(error)")
            return []
        }
    }

    private func activeMeaningSession() -> LanguageModelSession {
        if let session = meaningSession, batchesOnSession < Self.maxBatchesPerSession {
            return session
        }
        let session = LanguageModelSession(instructions: Self.meaningInstructions)
        meaningSession = session
        batchesOnSession = 0
        return session
    }
}

@available(iOS 26.0, *)
@Generable(description: "Korean meanings for a list of Japanese words")
private struct GeneratedMeaningList {
    @Guide(description: "One entry for every word that was given, in the same order")
    var items: [GeneratedMeaning]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedMeaning {
    @Guide(description: "The Japanese word, copied exactly as it was given")
    var word: String

    @Guide(description: "Korean meaning of that word, under 20 Korean characters")
    var meaning: String
}

@available(iOS 26.0, *)
@Generable(description: "Two Japanese example sentences with Korean translations")
private struct GeneratedExamples {
    @Guide(description: "Short Japanese sentence using the word")
    var japanese1: String

    @Guide(description: "Korean translation of the first sentence")
    var korean1: String

    @Guide(description: "Another short Japanese sentence using the word")
    var japanese2: String

    @Guide(description: "Korean translation of the second sentence")
    var korean2: String
}

#endif
