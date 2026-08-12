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

/// What one pass of generation produced for a word.
struct MeaningResult: Sendable {
    var meaningKO: String
    /// Kana supplied by the model, filled only for words the dictionary had no reading for.
    var reading: String
    var hangul: String
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
    ///
    /// - Parameter requiredSource: when set, a cached meaning from any other generator is
    ///   treated as missing so this pass produces its own. A ChatGPT scan asks for this so
    ///   it does not silently show meanings the on-device model wrote, while still reusing
    ///   its own earlier answers instead of billing for them twice.
    func resolve(
        surface: String,
        lemma: String,
        modelContext: ModelContext,
        requiredSource: WordCache.MeaningSource? = nil
    ) -> EnrichedWord {
        let key = WordCache.makeKey(surface: surface, lemma: lemma)
        let cached = cacheRow(key: key, context: modelContext)
        let cachedMeaningUsable = cached.map { row in
            Self.containsHangul(row.meaningKO)
                && (requiredSource == nil || row.isMeaning(from: requiredSource!))
        } ?? false

        // The whole point of the cache: a word seen in an earlier scan skips the model.
        if let cached, cachedMeaningUsable {
            return EnrichedWord(
                reading: cached.reading,
                hangul: cached.hangul,
                meaningKO: cached.meaningKO,
                meaningEN: cached.meaningEN,
                partOfSpeech: cached.partOfSpeech,
                examples: cached.examples
            )
        }

        let dict = DictionaryService.shared.lookup(surface: surface, lemma: lemma)
        let reading = dict?.reading.isEmpty == false ? dict!.reading : guessReading(surface: surface, lemma: lemma)
        let enriched = EnrichedWord(
            reading: reading,
            hangul: KanaRomanizer.toHangul(reading),
            meaningKO: "",
            meaningEN: dict?.glossEN ?? "",
            partOfSpeech: dict?.partOfSpeech ?? "",
            examples: cached?.examples ?? []
        )

        // Store the dictionary half now so generation only has to fill in the meaning.
        // Rows written while the model was unavailable hold no Korean meaning; refresh
        // them in place so any example sentences already generated survive.
        if let cached {
            cached.reading = enriched.reading
            cached.hangul = enriched.hangul
            // A meaning skipped only because it came from another generator is still a good
            // meaning. Leave it alone: this pass may end up discarded, and until the user
            // saves its results the stored one is what everything else should keep showing.
            if !Self.containsHangul(cached.meaningKO) {
                cached.meaningKO = ""
                cached.meaningSource = ""
            }
            cached.meaningEN = enriched.meaningEN
            cached.partOfSpeech = enriched.partOfSpeech
            cached.updatedAt = .now
        } else {
            modelContext.insert(
                WordCache(
                    key: key,
                    surface: surface,
                    lemma: lemma,
                    reading: enriched.reading,
                    hangul: enriched.hangul,
                    meaningKO: "",
                    meaningEN: enriched.meaningEN,
                    partOfSpeech: enriched.partOfSpeech
                )
            )
        }
        return enriched
    }

    /// Splits recognized lines into words, returning the words for each line in order.
    ///
    /// The dictionary tokenizer can only end a word where JMdict says one ends, so a shop
    /// name or an unlisted compound comes apart in the wrong place. The model reads the
    /// line instead, which is why this is offered as a second pass over the same photo.
    func segment(lines: [String]) async -> [[String]] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await generator.segment(lines: lines)
        }
        #endif
        return []
    }

    /// Korean meanings for a batch of words, keyed by cache key.
    ///
    /// Asking for many words in one request is what makes the scan fast: the schema and
    /// instructions are processed once instead of once per word.
    func generateMeanings(
        for words: [RecognizedWord],
        modelContext: ModelContext
    ) async -> [String: MeaningResult] {
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

            var results: [String: MeaningResult] = [:]
            for request in requests {
                guard let raw = produced[request.key] else { continue }

                // A word JMdict has never heard of has no reading to show, and the model is
                // the only source left.
                let reading = request.reading.isEmpty
                    ? Self.acceptedReading(raw.reading, for: request.word)
                    : ""
                results[request.key] = MeaningResult(
                    meaningKO: raw.meaning,
                    reading: reading,
                    hangul: reading.isEmpty ? "" : KanaRomanizer.toHangul(reading)
                )
            }

            await fillMissingReadings(for: requests, into: &results)
            guard !results.isEmpty else { return [:] }

            for (key, result) in results {
                guard let row = cacheRow(key: key, context: modelContext) else { continue }
                // A reading-only answer must not blank out a meaning already stored.
                if !result.meaningKO.isEmpty {
                    row.meaningKO = result.meaningKO
                    row.meaningSource = WordCache.MeaningSource.foundation.rawValue
                }
                if !result.reading.isEmpty {
                    row.reading = result.reading
                    row.hangul = result.hangul
                }
            }
            try? modelContext.save()
            return results
        }
        #endif
        return [:]
    }

    #if canImport(FoundationModels)
    /// Asks again, on its own, for the readings the combined pass failed to produce.
    ///
    /// Filling in a meaning and a reading in one answer is more than the on-device model
    /// reliably manages: it drops entries, and it answers with the word instead of its kana.
    /// A second pass that asks for nothing but readings recovers most of those.
    @available(iOS 26.0, *)
    private func fillMissingReadings(
        for requests: [MeaningRequest],
        into results: inout [String: MeaningResult]
    ) async {
        let missing = requests.filter { request in
            request.reading.isEmpty && (results[request.key]?.reading.isEmpty ?? true)
        }
        guard !missing.isEmpty else { return }

        let produced = await generator.readings(for: missing.map(\.word))
        guard !produced.isEmpty else { return }

        for request in missing {
            let reading = Self.acceptedReading(produced[request.word] ?? "", for: request.word)
            guard !reading.isEmpty else { continue }
            let hangul = KanaRomanizer.toHangul(reading)

            if var existing = results[request.key] {
                existing.reading = reading
                existing.hangul = hangul
                results[request.key] = existing
            } else {
                // The meaning pass lost this word entirely, but furigana is still worth
                // showing on its own.
                results[request.key] = MeaningResult(
                    meaningKO: "",
                    reading: reading,
                    hangul: hangul
                )
            }
        }
    }
    #endif

    /// Writes a ChatGPT pass into the cache, replacing whatever was stored before.
    ///
    /// ChatGPT results are held in memory until the user asks for this, because they cost
    /// money and are not automatically better than what is already saved. Committing them
    /// is the one place where an existing meaning is deliberately overwritten.
    func persistOpenAIMeanings(_ words: [RecognizedWord], modelContext: ModelContext) {
        for word in words where !word.meaningKO.isEmpty {
            let key = WordCache.makeKey(surface: word.surface, lemma: word.lemma)
            guard let row = cacheRow(key: key, context: modelContext) else {
                modelContext.insert(
                    WordCache(
                        key: key,
                        surface: word.surface,
                        lemma: word.lemma,
                        reading: word.reading,
                        hangul: word.hangul,
                        meaningKO: word.meaningKO,
                        meaningEN: word.meaningEN,
                        partOfSpeech: word.partOfSpeech,
                        meaningSource: .openAI
                    )
                )
                continue
            }
            if row.meaningKO != word.meaningKO {
                row.clearExamples()
            }
            row.reading = word.reading
            row.hangul = word.hangul
            row.meaningKO = word.meaningKO
            row.meaningEN = word.meaningEN
            row.partOfSpeech = word.partOfSpeech
            row.meaningSource = WordCache.MeaningSource.openAI.rawValue
            row.updatedAt = .now
        }
        try? modelContext.save()
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

    /// Kana already is its own reading. For anything else there is nothing to guess:
    /// echoing the kanji back would be shown as furigana and romanized into nonsense.
    private func guessReading(surface: String, lemma: String) -> String {
        if Self.isKanaOnly(surface) { return surface }
        if Self.isKanaOnly(lemma) { return lemma }
        return ""
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    }

    private nonisolated static func isKanaOnly(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy(isKana)
    }

    /// What a model offered as a reading, once salvaged and sanity-checked.
    ///
    /// Rejecting anything that is not already clean kana threw away usable answers: the
    /// on-device model often replies with the kana wrapped in the word it was asked about.
    nonisolated static func acceptedReading(_ raw: String, for word: String) -> String {
        // The earliest run that could actually be the reading. Order matters: when the model
        // lists alternatives it gives the intended one first, so the longest is the wrong
        // pick. Skipping runs that are merely part of the word is what leaves `ごりよう`
        // behind in an answer like `ご利用（ごりよう）`.
        kanaRuns(in: raw).first { isPlausibleReading($0, for: word) } ?? ""
    }

    private nonisolated static func kanaRuns(in text: String) -> [String] {
        var runs: [String] = []
        var run = ""
        for scalar in text.unicodeScalars {
            if isKana(scalar) {
                run.unicodeScalars.append(scalar)
                continue
            }
            if !run.isEmpty { runs.append(run) }
            run = ""
        }
        if !run.isEmpty { runs.append(run) }
        return runs
    }

    /// Catches the model echoing the word back, where extraction leaves only the kana that
    /// were already part of it: `ご` is not the reading of `ご利用`.
    private nonisolated static func isPlausibleReading(_ kana: String, for word: String) -> Bool {
        guard !kana.isEmpty, kana != word else { return false }
        return !word.contains(kana) || kana.count >= word.count
    }

    private nonisolated static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x3040...0x309F).contains(v)
            || (0x30A0...0x30FF).contains(v)
            || v == 0x30FC // prolonged sound mark
    }
}

#if canImport(FoundationModels)

@available(iOS 26.0, *)
@MainActor
private final class MeaningGenerator {
    private static let meaningInstructions = """
    You translate Japanese words for Korean learners.
    For every word you are given, return its meaning in Korean and how it is read.
    Write the reading in hiragana only, never in kanji or romaji.
    Always answer in Korean. Never answer in English.
    Keep each meaning under 20 Korean characters.
    """

    private static let readingInstructions = """
    You write how Japanese words are read.
    Answer in hiragana only. Never use kanji, katakana, romaji or any other script.
    Never give the word itself back as its reading.
    Return one entry for every word you are given, in the same order.
    """

    private static let segmentInstructions = """
    You split Japanese text into the words a dictionary would list.
    Copy characters exactly as they appear; never translate, respell, or invent text.
    Keep the words in the order they appear in the line.
    Leave out particles, inflectional endings, punctuation and bare numbers.
    """

    private static let exampleInstructions = """
    You write example sentences for Korean learners of Japanese.
    Write short natural Japanese sentences and translate each one into Korean.
    Always answer in Korean. Never answer in English.
    """

    /// Reusing a session keeps the model warm, but its transcript grows with every batch,
    /// so it is retired before it can overflow the context window.
    private static let maxBatchesPerSession = 3

    /// Lines carry far more text than single words, so fewer of them fit in one request.
    private static let segmentBatchSize = 6

    private var meaningSession: LanguageModelSession?
    private var batchesOnSession = 0

    func prewarm() {
        activeMeaningSession().prewarm()
    }

    func segment(lines: [String]) async -> [[String]] {
        guard !lines.isEmpty, SystemLanguageModel.default.isAvailable else { return [] }

        var result = [[String]](repeating: [], count: lines.count)
        var start = 0
        while start < lines.count {
            if Task.isCancelled { break }
            let end = min(start + Self.segmentBatchSize, lines.count)
            let produced = await segmentBatch(Array(lines[start..<end]))
            for (offset, words) in produced.enumerated() where start + offset < result.count {
                result[start + offset] = words
            }
            start = end
        }
        return result
    }

    /// Each batch gets a fresh session: segmentation runs once per photo, so there is no
    /// warm transcript worth keeping and a clean one cannot overflow.
    private func segmentBatch(_ batch: [String]) async -> [[String]] {
        let session = LanguageModelSession(instructions: Self.segmentInstructions)
        let prompt = """
        Split each of these \(batch.count) Japanese lines into words.
        \(batch.map { "- \($0)" }.joined(separator: "\n"))
        """

        do {
            let response = try await session.respond(
                to: prompt,
                generating: SegmentedLineList.self,
                options: GenerationOptions(
                    sampling: .greedy,
                    maximumResponseTokens: 120 * batch.count
                )
            )
            let items = response.content.items
            let wordsByLine = Dictionary(items.map { ($0.line, $0.words) }) { first, _ in first }

            // Matching on the echoed line survives a dropped entry; position covers the
            // lines the model rewrote. Words that fit neither are discarded later anyway,
            // because they will not be found in the line they were meant for.
            return batch.enumerated().map { index, line in
                if let words = wordsByLine[line] { return words }
                return index < items.count ? items[index].words : []
            }
        } catch {
            print("[MeaningService] segmentation failed: \(error)")
            return []
        }
    }

    func meanings(for requests: [MeaningRequest]) async -> [String: RawMeaning] {
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
                    maximumResponseTokens: 140 * requests.count
                )
            )
            let items = response.content.items
            var result: [String: RawMeaning] = [:]
            for item in items {
                guard let key = keysByWord[item.word], let raw = Self.raw(from: item) else { continue }
                result[key] = raw
            }

            // The model occasionally rewrites the word it echoes back. When it returned
            // the expected number of entries, position is a safe fallback for those.
            if result.count < requests.count, items.count == requests.count {
                for (request, item) in zip(requests, items) where result[request.key] == nil {
                    guard let raw = Self.raw(from: item) else { continue }
                    result[request.key] = raw
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

    /// Readings alone, for the words the combined pass could not manage.
    func readings(for words: [String]) async -> [String: String] {
        guard !words.isEmpty, SystemLanguageModel.default.isAvailable else { return [:] }

        // A dedicated session: the meaning transcript pushes this toward answering in Korean.
        let session = LanguageModelSession(instructions: Self.readingInstructions)
        let prompt = """
        Write the hiragana reading of each of these \(words.count) Japanese words.
        \(words.map { "- \($0)" }.joined(separator: "\n"))
        """

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedReadingList.self,
                options: GenerationOptions(
                    sampling: .greedy,
                    maximumResponseTokens: 60 * words.count
                )
            )
            let items = response.content.items
            var byWord = Dictionary(
                items.map { ($0.word, $0.reading) },
                uniquingKeysWith: { first, _ in first }
            )

            // Position covers the entries the model rewrote instead of echoing back.
            if items.count == words.count {
                for (word, item) in zip(words, items) where byWord[word] == nil {
                    byWord[word] = item.reading
                }
            }
            return byWord
        } catch {
            print("[MeaningService] reading batch failed: \(error)")
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

    private static func raw(from item: GeneratedMeaning) -> RawMeaning? {
        let meaning = item.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !meaning.isEmpty else { return nil }
        return RawMeaning(
            meaning: meaning,
            reading: item.reading.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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
@Generable(description: "Japanese lines split into dictionary words")
private struct SegmentedLineList {
    @Guide(description: "One entry for every line that was given, in the same order")
    var items: [SegmentedLine]
}

@available(iOS 26.0, *)
@Generable
private struct SegmentedLine {
    @Guide(description: "The line, copied exactly as it was given")
    var line: String

    @Guide(description: "Dictionary words found in that line, in order, copied exactly")
    var words: [String]
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

    @Guide(description: "How the word is read, in hiragana only")
    var reading: String
}

@available(iOS 26.0, *)
@Generable(description: "Hiragana readings for a list of Japanese words")
private struct GeneratedReadingList {
    @Guide(description: "One entry for every word that was given, in the same order")
    var items: [GeneratedReading]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedReading {
    @Guide(description: "The Japanese word, copied exactly as it was given")
    var word: String

    @Guide(description: "How that word is read, in hiragana only")
    var reading: String
}

/// A generated entry before it has been checked against what the dictionary already knows.
@available(iOS 26.0, *)
private struct RawMeaning {
    var meaning: String
    var reading: String
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
