//
//  ScanPipeline.swift
//  Kanjiyomi
//

import Foundation
import SwiftData
import UIKit

enum ScanPipeline {
    /// Words per generation request. Small enough that one batch stays well inside the
    /// context window, large enough that a typical photo needs only one or two calls.
    static let meaningBatchSize = 8

    /// OCR, tokenization and dictionary lookup. Nothing here touches the language model,
    /// so the word list can be shown as soon as this returns.
    static func recognize(
        image: UIImage,
        modelContext: ModelContext,
        onProgress: (String) -> Void = { _ in }
    ) async throws -> [RecognizedWord] {
        onProgress("사진에서 글자를 찾고 있어요")
        let spans = try await OCRService.recognizeTokens(in: image)
        onProgress("단어를 나누고 있어요")

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

        onProgress("사전에서 뜻을 찾고 있어요")
        var words: [RecognizedWord] = []
        for key in order {
            guard let group = grouped[key] else { continue }
            let enriched = MeaningService.shared.resolve(
                surface: group.surface,
                lemma: group.lemma,
                modelContext: modelContext
            )
            // Skip tokens with no dictionary hit and no meaning.
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

    /// Fills in the Korean meanings the dictionary pass could not supply.
    ///
    /// Results are published after every batch so the list fills in progressively instead
    /// of holding the whole scan behind the language model.
    static func fillMeanings(
        _ words: [RecognizedWord],
        modelContext: ModelContext,
        onUpdate: ([RecognizedWord]) -> Void
    ) async {
        let service = MeaningService.shared
        guard service.isGenerationAvailable else { return }

        var current = words
        let pending = current.indices.filter { current[$0].meaningKO.isEmpty }
        guard !pending.isEmpty else { return }

        for batch in pending.chunked(into: meaningBatchSize) {
            if Task.isCancelled { return }

            let generated = await service.generateMeanings(
                for: batch.map { current[$0] },
                modelContext: modelContext
            )
            guard !generated.isEmpty else { continue }

            for index in batch {
                let key = WordCache.makeKey(
                    surface: current[index].surface,
                    lemma: current[index].lemma
                )
                if let meaning = generated[key] {
                    current[index].meaningKO = meaning
                }
            }
            onUpdate(current)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
