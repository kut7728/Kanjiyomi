//
//  ScanPipeline.swift
//  Kanjiyomi
//

import Foundation
import SwiftData
import UIKit

enum ScanPipeline {
    static func process(image: UIImage, modelContext: ModelContext) async throws -> [RecognizedWord] {
        let spans = try await OCRService.recognizeTokens(in: image)

        // Merge repeats of the same word so every occurrence stays highlightable.
        var order: [String] = []
        var grouped: [String: (surface: String, lemma: String, quads: [TextQuad])] = [:]
        for span in spans {
            let key = "\(span.surface)|\(span.lemma)"
            if var existing = grouped[key] {
                existing.quads.append(span.quad)
                grouped[key] = existing
            } else {
                order.append(key)
                grouped[key] = (span.surface, span.lemma, [span.quad])
            }
        }

        var words: [RecognizedWord] = []
        for key in order {
            guard let group = grouped[key] else { continue }
            let enriched = await MeaningService.shared.enrich(
                surface: group.surface,
                lemma: group.lemma,
                modelContext: modelContext
            )
            // Skip tokens with no dictionary hit and no meaning
            if enriched.meaningKO.isEmpty && enriched.meaningEN.isEmpty && enriched.reading.isEmpty {
                continue
            }
            words.append(
                RecognizedWord(
                    surface: group.surface,
                    lemma: group.lemma,
                    reading: enriched.reading,
                    hangul: enriched.hangul,
                    meaningKO: enriched.meaningKO,
                    meaningEN: enriched.meaningEN,
                    partOfSpeech: enriched.partOfSpeech,
                    examples: enriched.examples,
                    quads: group.quads
                )
            )
        }
        return words
    }
}
