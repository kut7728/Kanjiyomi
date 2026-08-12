//
//  OCRService.swift
//  Kanjiyomi
//

import CoreGraphics
import Foundation
import UIKit
import Vision

/// Recognition and tokenization are pure computation and must stay off the main actor,
/// which the project otherwise isolates types to by default.
nonisolated enum OCRService {
    /// Splits every recognized line into words. Given the lines in order, it returns the
    /// words for each one, so an implementation can answer for the whole page at once.
    typealias LineSegmenter = @Sendable ([String]) async -> [[String]]

    /// Recognizes Japanese text and returns word-level spans with tight quads.
    ///
    /// Boxes are queried for whole token ranges rather than per character, because
    /// Vision returns a tight quad for a range while unioning per-character boxes
    /// inflates the region for rotated or tightly spaced text.
    ///
    /// Word boundaries come from the bundled dictionary unless a `segmenter` is given.
    static func recognizeTokens(
        in image: UIImage,
        segmenter: LineSegmenter? = nil
    ) async throws -> [TokenSpan] {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        let lines: [RecognizedLine]
        if #available(iOS 26.0, *) {
            lines = try await documentLines(cgImage)
        } else {
            lines = try await textLines(cgImage)
        }
        guard !lines.isEmpty else { return [] }

        let segmented = await segmenter?(lines.map(\.text))

        var spans: [TokenSpan] = []
        for (index, line) in lines.enumerated() {
            var tokens: [TokenRange] = []
            if let segmented, index < segmented.count {
                tokens = TokenizerService.ranges(ofModelWords: segmented[index], in: line.text)
            }
            // The model can come back with nothing usable for a line, and the dictionary
            // pass may still find words in it.
            if tokens.isEmpty {
                tokens = TokenizerService.tokenRanges(in: line.text)
            }
            for token in tokens {
                let box = line.quadForRange(token.range) ?? line.fallbackQuad
                spans.append(
                    TokenSpan(
                        surface: token.surface,
                        lemma: token.lemma,
                        quad: box.expanded(by: 0.06)
                    )
                )
            }
        }
        return spans
    }

    /// A line held together with its Vision candidate, so a quad can still be queried for
    /// any character range after something else has decided where the words are.
    ///
    /// Unchecked because the retained candidate is not `Sendable`; every instance stays
    /// inside the single call to `recognizeTokens` that produced it.
    private struct RecognizedLine: @unchecked Sendable {
        let text: String
        let fallbackQuad: TextQuad
        let quadForRange: (Range<String.Index>) -> TextQuad?
    }

    /// Signage and flyers are often set vertically (縦書き), which `VNRecognizeTextRequest`
    /// either fragments or skips because its detector assumes horizontal rows. The document
    /// request groups columns into paragraphs and reports their direction, so vertical text
    /// comes back as ordinary lines that tokenize the same way horizontal ones do.
    @available(iOS 26.0, *)
    private static func documentLines(_ cgImage: CGImage) async throws -> [RecognizedLine] {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = [Locale.Language(identifier: "ja")]
        request.textRecognitionOptions.automaticallyDetectLanguage = false
        request.textRecognitionOptions.useLanguageCorrection = true

        let observations = try await request.perform(on: cgImage)

        var lines: [RecognizedLine] = []
        for observation in observations {
            // `text` covers every line the container found, so paragraphs need no
            // separate pass and nothing gets counted twice.
            for line in observation.document.text.lines {
                guard let candidate = line.topCandidates(1).first else { continue }
                lines.append(
                    RecognizedLine(
                        text: candidate.string,
                        fallbackQuad: quad(of: line),
                        quadForRange: { range in
                            candidate.boundingBox(for: range).map(quad(of:))
                        }
                    )
                )
            }
        }
        return lines
    }

    private static func textLines(_ cgImage: CGImage) async throws -> [RecognizedLine] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                var lines: [RecognizedLine] = []

                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let lineQuad = TextQuad(
                        topLeft: observation.topLeft,
                        topRight: observation.topRight,
                        bottomRight: observation.bottomRight,
                        bottomLeft: observation.bottomLeft
                    )
                    lines.append(
                        RecognizedLine(
                            text: candidate.string,
                            fallbackQuad: lineQuad,
                            quadForRange: { range in
                                guard let box = try? candidate.boundingBox(for: range) else { return nil }
                                return TextQuad(
                                    topLeft: box.topLeft,
                                    topRight: box.topRight,
                                    bottomRight: box.bottomRight,
                                    bottomLeft: box.bottomLeft
                                )
                            }
                        )
                    )
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func quad(of provider: some QuadrilateralProviding) -> TextQuad {
        TextQuad(
            topLeft: provider.topLeft.cgPoint,
            topRight: provider.topRight.cgPoint,
            bottomRight: provider.bottomRight.cgPoint,
            bottomLeft: provider.bottomLeft.cgPoint
        )
    }
}

enum OCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "이미지를 처리할 수 없습니다."
        }
    }
}
