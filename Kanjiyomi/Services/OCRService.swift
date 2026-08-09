//
//  OCRService.swift
//  Kanjiyomi
//

import CoreGraphics
import Foundation
import UIKit
import Vision

enum OCRService {
    /// Recognizes Japanese text and returns word-level spans with tight quads.
    ///
    /// Boxes are queried for whole token ranges rather than per character, because
    /// Vision returns a tight quad for a range while unioning per-character boxes
    /// inflates the region for rotated or tightly spaced text.
    static func recognizeTokens(in image: UIImage) async throws -> [TokenSpan] {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                var spans: [TokenSpan] = []

                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let text = candidate.string
                    guard !text.isEmpty else { continue }

                    let lineQuad = TextQuad(
                        topLeft: observation.topLeft,
                        topRight: observation.topRight,
                        bottomRight: observation.bottomRight,
                        bottomLeft: observation.bottomLeft
                    )

                    for token in TokenizerService.tokenRanges(in: text) {
                        let quad = self.quad(for: token.range, in: candidate) ?? lineQuad
                        spans.append(
                            TokenSpan(
                                surface: token.surface,
                                lemma: token.lemma,
                                quad: quad.expanded(by: 0.06)
                            )
                        )
                    }
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

    private static func quad(
        for range: Range<String.Index>,
        in candidate: VNRecognizedText
    ) -> TextQuad? {
        guard let observation = try? candidate.boundingBox(for: range) else { return nil }
        return TextQuad(
            topLeft: observation.topLeft,
            topRight: observation.topRight,
            bottomRight: observation.bottomRight,
            bottomLeft: observation.bottomLeft
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
