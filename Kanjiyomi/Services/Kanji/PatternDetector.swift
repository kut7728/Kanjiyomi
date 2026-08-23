//
//  PatternDetector.swift
//  Kanjiyomi
//

import Foundation

enum PatternDetector {
    static let discoverThreshold = 2
    static let familiarThreshold = 4

    static func detect(
        from words: [(surface: String, reading: String)],
        catalog: KanjiCatalog
    ) -> [PatternObservation] {
        var buckets: [String: (hanja: String, samples: [String])] = [:]

        for word in words {
            let analysis = WordAnalyzer.analyze(
                surface: word.surface,
                reading: word.reading,
                catalog: catalog
            )
            guard !analysis.isException else { continue }
            for occurrence in analysis.occurrences where occurrence.isAligned && occurrence.kind == .onyomi {
                let key = "\(occurrence.kanji)|\(occurrence.reading)"
                var bucket = buckets[key] ?? (occurrence.hanjaKO, [])
                if !bucket.samples.contains(word.surface) {
                    bucket.samples.append(word.surface)
                }
                buckets[key] = bucket
            }
        }

        return buckets.map { key, value in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let kanji = parts.first?.first ?? "?"
            let reading = parts.count > 1 ? parts[1] : ""
            let count = value.samples.count
            let status: PatternStatus
            if count >= familiarThreshold {
                status = .familiar
            } else if count >= discoverThreshold {
                status = .discovered
            } else {
                status = .emerging
            }
            return PatternObservation(
                kanji: kanji,
                hanjaKO: value.hanja,
                observedReading: reading,
                wordCount: count,
                sampleWords: value.samples,
                status: status
            )
        }
        .sorted { lhs, rhs in
            if lhs.wordCount != rhs.wordCount { return lhs.wordCount > rhs.wordCount }
            return String(lhs.kanji) < String(rhs.kanji)
        }
    }
}
