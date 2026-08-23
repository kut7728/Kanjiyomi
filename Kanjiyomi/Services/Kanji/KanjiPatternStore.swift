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

        for observation in observations {
            let key = "\(observation.kanji)|\(observation.observedReading)"
            if let row = index[key] {
                row.seenWordCount = observation.wordCount
                row.hanjaKO = observation.hanjaKO
                row.status = observation.status
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
        if row.inferenceCorrect >= 2, row.status != .familiar {
            row.status = .familiar
        }
        try? modelContext.save()
    }

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
