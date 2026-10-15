//
//  KanjiPatternStore.swift
//  Kanjiyomi
//

import Foundation
import SwiftData

@MainActor
enum KanjiPatternStore {
    static func sync(from words: [VocabWord], modelContext: ModelContext, catalog: KanjiCatalog) {
        let observations = PatternDetector.detect(
            from: words.map { ($0.displayHeadword, $0.reading) },
            catalog: catalog
        )
        let existing = (try? modelContext.fetch(FetchDescriptor<UserKanjiPattern>())) ?? []
        var index = Dictionary(uniqueKeysWithValues: existing.map { ($0.key, $0) })

        // A pattern no saved word shows any more has nothing left to count; dropping the row
        // keeps deleted words out of the learned-pattern total.
        let observedKeys = Set(observations.map { "\($0.kanji)|\($0.observedReading)" })
        for row in existing where !observedKeys.contains(row.key) {
            modelContext.delete(row)
            index[row.key] = nil
        }

        for observation in observations {
            let key = "\(observation.kanji)|\(observation.observedReading)"
            if let row = index[key] {
                row.seenWordCount = observation.wordCount
                row.hanjaKO = observation.hanjaKO
                row.status = status(detected: observation.status, inferenceCorrect: row.inferenceCorrect)
                row.sampleWords = observation.sampleWords.joined(separator: "、")
                row.updatedAt = .now
            } else {
                let row = UserKanjiPattern(
                    kanji: String(observation.kanji),
                    hanjaKO: observation.hanjaKO,
                    observedReading: observation.observedReading,
                    seenWordCount: observation.wordCount,
                    status: observation.status,
                    sampleWords: observation.sampleWords
                )
                modelContext.insert(row)
                index[key] = row
            }
        }
        try? modelContext.save()
    }

    static func recordQuiz(
        kanji: String,
        reading: String,
        isCorrect: Bool,
        isInference: Bool,
        modelContext: ModelContext
    ) {
        let key = "\(kanji)|\(reading)"
        var descriptor = FetchDescriptor<UserKanjiPattern>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        row.quizTotal += 1
        if isCorrect { row.quizCorrect += 1 }
        if isCorrect && isInference { row.inferenceCorrect += 1 }
        row.lastReviewedAt = .now
        row.updatedAt = .now
        row.status = status(detected: row.status, inferenceCorrect: row.inferenceCorrect)
        try? modelContext.save()
    }

    /// Inferring a pattern's reading twice shows it is known, however few saved words carry it,
    /// so that earns familiar on top of whatever the word count alone gives.
    nonisolated static func status(detected: PatternStatus, inferenceCorrect: Int) -> PatternStatus {
        inferenceCorrect >= familiarInferenceCount ? .familiar : detected
    }

    nonisolated static let familiarInferenceCount = 2

    static func recordAttempt(
        surface: String,
        mode: QuizMode,
        isCorrect: Bool,
        modelContext: ModelContext
    ) {
        modelContext.insert(QuizAttempt(surface: surface, mode: mode, isCorrect: isCorrect))
        try? modelContext.save()
    }

    static func recentMisses(modelContext: ModelContext, limit: Int = 8) -> [QuizAttempt] {
        var descriptor = FetchDescriptor<QuizAttempt>(
            predicate: #Predicate { !$0.isCorrect },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    static func discoveredCount(in patterns: [UserKanjiPattern]) -> Int {
        patterns.filter { $0.status == .discovered || $0.status == .familiar }.count
    }
}
