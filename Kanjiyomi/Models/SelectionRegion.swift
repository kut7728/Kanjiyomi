//
//  SelectionRegion.swift
//  Kanjiyomi
//

import CoreGraphics
import Foundation

/// One or more freeform outlines the user drew over the photo, in Vision normalized
/// coordinates (0...1, origin at bottom-left) so they stay put however large the photo is
/// drawn. Words are kept or dropped by how much of them falls inside.
///
/// Outlines are stored as polygons rather than a rect because text worth isolating rarely
/// sits in one: a caption wraps around a picture, a sign leans, a column of vertical text
/// runs beside another. Several outlines together read as one selection.
nonisolated struct SelectionRegion: Hashable, Sendable {
    /// Each outline is a closed loop of at least three points.
    let polygons: [[CGPoint]]

    /// Cached so a quad far from the selection can be rejected without walking every edge.
    /// Hit testing runs for every quad on every frame while a stroke is being drawn.
    private let polygonBounds: [CGRect]
    private let bounds: CGRect

    /// How much of a word has to fall inside before it counts as selected. Grazing a word
    /// on the way past should not pull it in, but neither should the user have to enclose
    /// every last stroke of it.
    static let minimumCoverage: CGFloat = 0.35

    /// Samples per axis when measuring how much of a quad the region covers.
    private static let samplesPerAxis = 5

    /// A bounding box excludes its own far edge, which would reject the outline's outermost
    /// points before they ever reach the crossing count.
    private static let boundsSlack: CGFloat = 0.0005

    init(polygons: [[CGPoint]]) {
        let usable = polygons.filter { $0.count >= 3 }
        self.polygons = usable
        polygonBounds = usable.map {
            Self.bounds(of: $0).insetBy(dx: -Self.boundsSlack, dy: -Self.boundsSlack)
        }
        bounds = polygonBounds.dropFirst().reduce(polygonBounds.first ?? .null) { $0.union($1) }
    }

    var isEmpty: Bool { polygons.isEmpty }

    /// Whether the word found at this quad belongs to the selection.
    func covers(_ quad: TextQuad) -> Bool {
        guard !isEmpty, !quad.isEmpty else { return false }
        guard bounds.intersects(Self.bounds(of: quad.corners)) else { return false }
        // A stroke drawn through the middle of a long word reads as picking that word even
        // when most of its length hangs outside.
        if contains(quad.centroid) { return true }
        return coverage(of: quad) >= Self.minimumCoverage
    }

    /// The fraction of the quad that lies inside the selection, measured on an even grid
    /// laid over it. Quads are four arbitrary corners rather than rects, so the grid is
    /// interpolated between the edges instead of stepping over a bounding box.
    func coverage(of quad: TextQuad) -> CGFloat {
        let steps = Self.samplesPerAxis
        var hits = 0
        for row in 0..<steps {
            let v = (CGFloat(row) + 0.5) / CGFloat(steps)
            let left = Self.lerp(quad.topLeft, quad.bottomLeft, v)
            let right = Self.lerp(quad.topRight, quad.bottomRight, v)
            for column in 0..<steps {
                let u = (CGFloat(column) + 0.5) / CGFloat(steps)
                if contains(Self.lerp(left, right, u)) { hits += 1 }
            }
        }
        return CGFloat(hits) / CGFloat(steps * steps)
    }

    /// Overlapping outlines add up rather than cancelling out, so drawing over the same
    /// place twice keeps it selected.
    func contains(_ point: CGPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        for (index, polygon) in polygons.enumerated() {
            guard polygonBounds[index].contains(point) else { continue }
            if Self.polygon(polygon, contains: point) { return true }
        }
        return false
    }

    /// Crossing count along a ray to the left: an odd number of edges means inside.
    private static func polygon(_ points: [CGPoint], contains point: CGPoint) -> Bool {
        var inside = false
        var previous = points.count - 1
        for current in points.indices {
            let a = points[current]
            let b = points[previous]
            // Also rules out the horizontal edges that have no crossing to compute.
            if (a.y > point.y) != (b.y > point.y) {
                let t = (point.y - a.y) / (b.y - a.y)
                if point.x < a.x + t * (b.x - a.x) { inside.toggle() }
            }
            previous = current
        }
        return inside
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
    }

    // Derived from the outlines, so comparing them is comparing the whole region.
    static func == (lhs: SelectionRegion, rhs: SelectionRegion) -> Bool {
        lhs.polygons == rhs.polygons
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(polygons)
    }
}
