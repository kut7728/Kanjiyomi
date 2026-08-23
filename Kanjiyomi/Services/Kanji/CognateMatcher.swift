//
//  CognateMatcher.swift
//  Kanjiyomi
//

import Foundation

enum CognateMatcher {
    static func koreanCognate(from occurrences: [KanjiOccurrence]) -> String? {
        guard !occurrences.isEmpty,
              occurrences.allSatisfy({ $0.isAligned && $0.kind == .onyomi && !$0.hanjaKO.isEmpty })
        else { return nil }
        return occurrences.map(\.hanjaKO).joined()
    }
}
