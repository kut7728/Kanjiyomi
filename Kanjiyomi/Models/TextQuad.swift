//
//  TextQuad.swift
//  Kanjiyomi
//

import CoreGraphics
import Foundation

/// Four corners of a recognized text region in Vision normalized coordinates
/// (0...1, origin at bottom-left). Keeping the quad instead of an axis-aligned
/// rect preserves rotation and perspective of signage text.
struct TextQuad: Hashable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    static let zero = TextQuad(
        topLeft: .zero,
        topRight: .zero,
        bottomRight: .zero,
        bottomLeft: .zero
    )

    var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    var isEmpty: Bool {
        corners.allSatisfy { $0 == .zero }
    }

    var centroid: CGPoint {
        let sum = corners.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / 4, y: sum.y / 4)
    }

    /// Grows the quad outward from its centroid so the highlight does not clip glyph edges.
    func expanded(by ratio: CGFloat) -> TextQuad {
        guard ratio != 0 else { return self }
        let c = centroid
        func grow(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: c.x + (p.x - c.x) * (1 + ratio),
                y: c.y + (p.y - c.y) * (1 + ratio)
            )
        }
        return TextQuad(
            topLeft: grow(topLeft),
            topRight: grow(topRight),
            bottomRight: grow(bottomRight),
            bottomLeft: grow(bottomLeft)
        )
    }

    /// Smallest quad covering both, used when merging adjacent character boxes.
    func union(_ other: TextQuad) -> TextQuad {
        if isEmpty { return other }
        if other.isEmpty { return self }
        return TextQuad(
            topLeft: CGPoint(
                x: min(topLeft.x, other.topLeft.x),
                y: max(topLeft.y, other.topLeft.y)
            ),
            topRight: CGPoint(
                x: max(topRight.x, other.topRight.x),
                y: max(topRight.y, other.topRight.y)
            ),
            bottomRight: CGPoint(
                x: max(bottomRight.x, other.bottomRight.x),
                y: min(bottomRight.y, other.bottomRight.y)
            ),
            bottomLeft: CGPoint(
                x: min(bottomLeft.x, other.bottomLeft.x),
                y: min(bottomLeft.y, other.bottomLeft.y)
            )
        )
    }

    init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    init(rect: CGRect) {
        self.init(
            topLeft: CGPoint(x: rect.minX, y: rect.maxY),
            topRight: CGPoint(x: rect.maxX, y: rect.maxY),
            bottomRight: CGPoint(x: rect.maxX, y: rect.minY),
            bottomLeft: CGPoint(x: rect.minX, y: rect.minY)
        )
    }
}
