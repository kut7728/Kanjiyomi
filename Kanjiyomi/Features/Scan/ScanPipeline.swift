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

    /// The remote model has a far larger context and is billed per request round trip.
    static let openAIMeaningBatchSize = 24

    /// OCR, tokenization and dictionary lookup. Nothing here touches the language model,
    /// so the word list can be shown as soon as this returns.
    /// Recognition is always re-run for a mode change rather than resplitting the stored
    /// words, because a highlight quad can only be measured against the Vision result the
    /// text came from.
    static func recognize(
        image: UIImage,
        mode: SegmentationMode,
        modelContext: ModelContext,
        onProgress: (String) -> Void = { _ in }
    ) async throws -> [RecognizedWord] {
        let mode = mode.resolved
        onProgress(mode.progressMessage)

        OpenAIService.shared.clearError()
        let segmenter: OCRService.LineSegmenter? = switch mode {
        case .dictionary: nil
        case .model: { lines in await MeaningService.shared.segment(lines: lines) }
        case .openAI: { lines in await OpenAIService.shared.segment(lines: lines) }
        }
        let spans = try await OCRService.recognizeTokens(in: image, segmenter: segmenter)

        onProgress("사전에서 뜻을 찾고 있어요")
        // An unlisted word arrives with no reading and no gloss, so keeping it only helps if
        // the meaning pass that follows can actually fill it in.
        let keepUnlisted = switch mode {
        case .dictionary: false
        case .model: MeaningService.shared.isGenerationAvailable
        case .openAI: true
        }
        return words(
            from: spans,
            modelContext: modelContext,
            keepUnlisted: keepUnlisted,
            requiredSource: mode == .openAI ? .openAI : nil
        )
    }

    /// - Parameter keepUnlisted: whether to keep words the dictionary knows nothing about.
    ///   They have no reading and no gloss, so only a model pass can give them a meaning.
    /// - Parameter requiredSource: which generator a cached meaning has to have come from
    ///   to be reused rather than generated again.
    private static func words(
        from spans: [TokenSpan],
        modelContext: ModelContext,
        keepUnlisted: Bool,
        requiredSource: WordCache.MeaningSource?
    ) -> [RecognizedWord] {
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
            let enriched = MeaningService.shared.resolve(
                surface: group.surface,
                lemma: group.lemma,
                modelContext: modelContext,
                requiredSource: requiredSource
            )
            let isUnlisted = enriched.meaningKO.isEmpty
                && enriched.meaningEN.isEmpty
                && enriched.reading.isEmpty
            if isUnlisted && !keepUnlisted { continue }

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
        mode: SegmentationMode,
        modelContext: ModelContext,
        onUpdate: ([RecognizedWord]) -> Void
    ) async {
        let usesOpenAI = mode == .openAI
        guard usesOpenAI || MeaningService.shared.isGenerationAvailable else { return }

        var current = words
        let pending = current.indices.filter { current[$0].needsGeneration }
        guard !pending.isEmpty else { return }

        // A round trip costs far more than a longer prompt, so the remote model is asked
        // for more words at once than the on-device one.
        let batchSize = usesOpenAI ? openAIMeaningBatchSize : meaningBatchSize
        let batches = pending.chunked(into: batchSize)

        guard usesOpenAI else {
            // One local model answers every request, so overlapping them only queues them.
            for batch in batches {
                if Task.isCancelled { return }
                let generated = await MeaningService.shared.generateMeanings(
                    for: batch.map { current[$0] },
                    modelContext: modelContext
                )
                guard !generated.isEmpty else { continue }
                apply(generated, to: batch, in: &current)
                onUpdate(current)
            }
            return
        }

        // Remote batches are independent round trips of similar length, so issuing them
        // together bills the same as issuing them one by one but finishes in the time of
        // the slowest rather than the sum.
        await withTaskGroup(
            of: (indices: [Int], generated: [String: MeaningResult]).self
        ) { group in
            for batch in batches {
                let payload = batch.map { current[$0] }
                group.addTask {
                    (batch, await OpenAIService.shared.generateMeanings(for: payload))
                }
            }

            for await batch in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                guard !batch.generated.isEmpty else { continue }
                apply(batch.generated, to: batch.indices, in: &current)
                onUpdate(current)
            }
        }
    }

    private static func apply(
        _ generated: [String: MeaningResult],
        to indices: [Int],
        in words: inout [RecognizedWord]
    ) {
        for index in indices {
            let key = WordCache.makeKey(surface: words[index].surface, lemma: words[index].lemma)
            guard let result = generated[key] else { continue }
            // A pass that recovered only the reading must leave the meaning alone.
            if !result.meaningKO.isEmpty {
                words[index].meaningKO = result.meaningKO
            }
            // Only words the dictionary could not place come back with a reading.
            if words[index].reading.isEmpty, !result.reading.isEmpty {
                words[index].reading = result.reading
                words[index].hangul = result.hangul
            }
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
