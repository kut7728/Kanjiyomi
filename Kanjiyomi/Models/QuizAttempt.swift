//
//  QuizAttempt.swift
//  Kanjiyomi
//

import Foundation
import SwiftData

@Model
final class QuizAttempt {
    var surface: String
    var modeRaw: String
    var isCorrect: Bool
    var createdAt: Date

    init(surface: String, mode: QuizMode, isCorrect: Bool, createdAt: Date = .now) {
        self.surface = surface
        self.modeRaw = mode.rawValue
        self.isCorrect = isCorrect
        self.createdAt = createdAt
    }

    var mode: QuizMode {
        QuizMode(rawValue: modeRaw) ?? .wordToMeaning
    }
}
