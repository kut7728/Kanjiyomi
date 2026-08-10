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
    /// Recognizes Japanese text and returns word-level spans with tight quads.
    ///
    /// Boxes are queried for whole token ranges rather than per character, because
    /// Vision returns a tight quad for a range while unioning per-character boxes
    /// inflates the region for rotated or tightly spaced text.
    static func recognizeTokens(in image: UIImage) async throws -> [TokenSpan] {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        if #available(iOS 26.0, *) {
            return try await recognizeDocument(cgImage)
        }
        return try await recognizeLines(cgImage)
    }

    /// Signage and flyers are often set vertically (縦書き), which `VNRecognizeTextRequest`
    /// either fragments or skips because its detector assumes horizontal rows. The document
    /// request groups columns into paragraphs and reports their direction, so vertical text
    /// comes back as ordinary lines that tokenize the same way horizontal ones do.
    @available(iOS 26.0, *)
    private static func recognizeDocument(_ cgImage: CGImage) async throws -> [TokenSpan] {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = [Locale.Language(identifier: "ja")]
        request.textRecognitionOptions.automaticallyDetectLanguage = false
        request.textRecognitionOptions.useLanguageCorrection = true

        let observations = try await request.perform(on: cgImage)

        var spans: [TokenSpan] = []
        for observation in observations {
            // `text` covers every line the container found, so paragraphs need no
            // separate pass and nothing gets counted twice.
            for line in observation.document.text.lines {
                guard let candidate = line.topCandidates(1).first else { continue }
                appendTokens(
                    in: candidate.string,
                    fallback: quad(of: line),
                    quadForRange: { range in
                        candidate.boundingBox(for: range).map(quad(of:))
                    },
                    into: &spans
                )
            }
        }
        return spans
    }

    private static func recognizeLines(_ cgImage: CGImage) async throws -> [TokenSpan] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                var spans: [TokenSpan] = []

                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let lineQuad = TextQuad(
                        topLeft: observation.topLeft,
                        topRight: observation.topRight,
                        bottomRight: observation.bottomRight,
                        bottomLeft: observation.bottomLeft
                    )
                    appendTokens(
                        in: candidate.string,
                        fallback: lineQuad,
                        quadForRange: { range in
                            guard let box = try? candidate.boundingBox(for: range) else { return nil }
                            return TextQuad(
                                topLeft: box.topLeft,
                                topRight: box.topRight,
                                bottomRight: box.bottomRight,
                                bottomLeft: box.bottomLeft
                            )
                        },
                        into: &spans
                    )
                }
                continuation.resume(returning: spans)
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

    private static func appendTokens(
        in text: String,
        fallback: TextQuad,
        quadForRange: (Range<String.Index>) -> TextQuad?,
        into spans: inout [TokenSpan]
    ) {
        guard !text.isEmpty else { return }
        for token in TokenizerService.tokenRanges(in: text) {
            let box = quadForRange(token.range) ?? fallback
            spans.append(
                TokenSpan(
                    surface: token.surface,
                    lemma: token.lemma,
                    quad: box.expanded(by: 0.06)
                )
            )
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
