//
//  VocabularyStore.swift
//  Kanjiyomi
//

import Foundation
import SwiftData

/// Every scan feeds its words into the vocabulary list, so this is the single place that
/// decides what counts as the same word and what happens when it is already saved.
@MainActor
enum VocabularyStore {
    /// Files a finished scan into the vocabulary.
    ///
    /// Words the model never managed to explain are left out; an entry showing "뜻 없음"
    /// is nothing to study. Words already saved are only ever filled in, never rewritten,
    /// so a later scan can supply a missing reading without changing a meaning the user
    /// has been learning from.
    static func absorb(
        _ words: [RecognizedWord],
        from scanRecordID: UUID?,
        modelContext: ModelContext
    ) {
        let candidates = words.filter { !$0.meaningKO.isEmpty && !$0.displayHeadword.isEmpty }
        guard !candidates.isEmpty else { return }

        // One photo commonly shows the same word several times.
        var seen = Set<String>()
        let incoming = candidates.filter { seen.insert(key(for: $0)).inserted }

        // One fetch and an in-memory index, rather than a predicate per word.
        let saved = (try? modelContext.fetch(FetchDescriptor<VocabWord>())) ?? []
        var index = Dictionary(
            saved.map { (key(surface: $0.surface, lemma: $0.lemma), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for word in incoming {
            let key = key(for: word)
            if let existing = index[key] {
                fillGaps(in: existing, from: word)
                // Repointed rather than filled in, unlike the fields above: the newest photo
                // showing the word is the one worth going back to, and a scan that failed to
                // be stored has nothing better to offer than the link already there.
                if let scanRecordID { existing.scanRecordID = scanRecordID }
            } else {
                let entry = VocabWord(from: word, scanRecordID: scanRecordID)
                modelContext.insert(entry)
                index[key] = entry
            }
        }
        try? modelContext.save()
    }

    private static func key(for word: RecognizedWord) -> String {
        key(surface: word.surface, lemma: word.lemma)
    }

    private static func key(surface: String, lemma: String) -> String {
        WordCache.makeKey(surface: surface, lemma: lemma)
    }

    private static func fillGaps(in entry: VocabWord, from word: RecognizedWord) {
        if entry.meaningKO.isEmpty { entry.meaningKO = word.meaningKO }
        if entry.reading.isEmpty { entry.reading = word.reading }
        if entry.hangul.isEmpty { entry.hangul = word.hangul }
        if entry.meaningEN.isEmpty { entry.meaningEN = word.meaningEN }
        if entry.partOfSpeech.isEmpty { entry.partOfSpeech = word.partOfSpeech }

        // Examples are generated lazily when a word detail is opened, so a scan usually
        // arrives without them and must not blank out ones already stored.
        let examples = word.examples
        if entry.exampleJP1.isEmpty, examples.count > 0 {
            entry.exampleJP1 = examples[0].japanese
            entry.exampleKO1 = examples[0].korean
        }
        if entry.exampleJP2.isEmpty, examples.count > 1 {
            entry.exampleJP2 = examples[1].japanese
            entry.exampleKO2 = examples[1].korean
        }
    }
}
