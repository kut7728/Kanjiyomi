//
//  UserKanjiPattern.swift
//  Kanjiyomi
//

import Foundation
import SwiftData

@Model
final class UserKanjiPattern {
    @Attribute(.unique) var key: String
    var kanji: String
    var hanjaKO: String
    var observedReading: String
    var seenWordCount: Int
    var quizCorrect: Int
    var quizTotal: Int
    var inferenceCorrect: Int
    var lastReviewedAt: Date?
    var statusRaw: String
    var sampleWords: String
    var updatedAt: Date

    init(
        kanji: String,
        hanjaKO: String,
        observedReading: String,
        seenWordCount: Int = 1,
        quizCorrect: Int = 0,
        quizTotal: Int = 0,
        inferenceCorrect: Int = 0,
        lastReviewedAt: Date? = nil,
        status: PatternStatus = .emerging,
        sampleWords: [String] = [],
        updatedAt: Date = .now
    ) {
        self.key = "\(kanji)|\(observedReading)"
        self.kanji = kanji
        self.hanjaKO = hanjaKO
        self.observedReading = observedReading
        self.seenWordCount = seenWordCount
        self.quizCorrect = quizCorrect
        self.quizTotal = quizTotal
        self.inferenceCorrect = inferenceCorrect
        self.lastReviewedAt = lastReviewedAt
        self.statusRaw = status.rawValue
        self.sampleWords = sampleWords.joined(separator: "、")
        self.updatedAt = updatedAt
    }

    var status: PatternStatus {
        get { PatternStatus(rawValue: statusRaw) ?? .emerging }
        set { statusRaw = newValue.rawValue }
    }

    var sampleWordList: [String] {
        sampleWords.split(separator: "、").map(String.init)
    }

    var accuracy: Double {
        guard quizTotal > 0 else { return 0 }
        return Double(quizCorrect) / Double(quizTotal)
    }
}
