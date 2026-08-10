//
//  PartOfSpeechFormatter.swift
//  Kanjiyomi
//

import Foundation

/// JMdict stores part of speech as English prose such as
/// `noun (common) (futsuumeishi)|noun (common) (futsuumeishi);transitive verb`.
/// This turns that into a short Korean label like `명사 · 타동사`.
nonisolated enum PartOfSpeechFormatter {
    /// Matched in order, so the more specific rule for a family comes first.
    private static let rules: [(match: String, label: String)] = [
        ("adjectival noun", "な형용사"),
        ("na-adjective", "な형용사"),
        ("'taru' adjective", "な형용사"),
        ("pre-noun adjectival", "연체사"),
        ("acting prenominally", "연체사"),
        ("adjective", "い형용사"),
        ("adverb", "부사"),
        ("intransitive verb", "자동사"),
        ("transitive verb", "타동사"),
        ("auxiliary", "조동사"),
        ("verb", "동사"),
        ("used as a prefix", "접두사"),
        ("prefix", "접두사"),
        ("used as a suffix", "접미사"),
        ("suffix", "접미사"),
        ("pronoun", "대명사"),
        ("noun", "명사"),
        ("expressions", "표현"),
        ("interjection", "감탄사"),
        ("conjunction", "접속사"),
        ("counter", "조수사"),
        ("numeric", "수사"),
        ("particle", "조사"),
        ("copula", "계사")
    ]

    private static let maxLabels = 3

    static func korean(from raw: String) -> String {
        guard !raw.isEmpty else { return "" }

        var labels: [String] = []
        for tag in raw.split(whereSeparator: { $0 == "|" || $0 == ";" }) {
            let lowered = tag.lowercased()
            guard let label = rules.first(where: { lowered.contains($0.match) })?.label else { continue }
            if !labels.contains(label) {
                labels.append(label)
            }
        }

        // 타동사 / 자동사 already say it is a verb.
        if labels.contains("타동사") || labels.contains("자동사") {
            labels.removeAll { $0 == "동사" }
        }
        return labels.prefix(maxLabels).joined(separator: " · ")
    }
}
