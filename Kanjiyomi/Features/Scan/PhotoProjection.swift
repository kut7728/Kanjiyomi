//
//  PhotoProjection.swift
//  Kanjiyomi
//

import SwiftUI

/// How the photo is drawn: fitted inside its frame, then magnified around a focus point.
///
/// Both directions live here because a highlight and a finger have to agree. Vision reports
/// text in normalized coordinates from the bottom-left, SwiftUI draws from the top-left, and
/// the magnification is applied to overlays by hand rather than being scaled with the pixels,
/// so each conversion written out separately is a chance for them to drift apart.
struct PhotoProjection {
    /// Where the fitted photo lands inside its frame, before any magnification.
    let fitted: CGRect
    let scale: CGFloat

    /// The point of `fitted` that sits at the middle of the frame. Always inside the photo, so
    /// no amount of panning or zooming can bring the letterboxing beside it into view.
    let focus: CGPoint

    private let displaySize: CGSize

    private var center: CGPoint {
        CGPoint(x: displaySize.width / 2, y: displaySize.height / 2)
    }

    init(imageSize: CGSize, displaySize: CGSize, scale: CGFloat = 1, focus: CGPoint? = nil) {
        self.displaySize = displaySize
        let magnification = max(scale, 1)
        self.scale = magnification

        let center = CGPoint(x: displaySize.width / 2, y: displaySize.height / 2)
        guard imageSize.width > 0, imageSize.height > 0 else {
            fitted = .zero
            self.focus = center
            return
        }
        let fit = min(displaySize.width / imageSize.width, displaySize.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * fit, height: imageSize.height * fit)
        let rect = CGRect(
            x: (displaySize.width - drawn.width) / 2,
            y: (displaySize.height - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        )
        fitted = rect
        self.focus = Self.clamped(
            focus ?? center,
            in: rect,
            displaySize: displaySize,
            scale: magnification
        )
    }

    private init(fitted: CGRect, displaySize: CGSize, scale: CGFloat, focus: CGPoint) {
        let magnification = max(scale, 1)
        self.fitted = fitted
        self.displaySize = displaySize
        self.scale = magnification
        self.focus = Self.clamped(
            focus,
            in: fitted,
            displaySize: displaySize,
            scale: magnification
        )
    }

    var isEmpty: Bool { fitted.width <= 0 || fitted.height <= 0 }

    /// The offset the photo has to be drawn with, alongside `scale`, for its pixels to land
    /// where this projection puts the overlays.
    var drawOffset: CGSize {
        CGSize(width: (center.x - focus.x) * scale, height: (center.y - focus.y) * scale)
    }

    func point(_ normalized: CGPoint) -> CGPoint {
        let onPhoto = CGPoint(
            x: fitted.minX + normalized.x * fitted.width,
            y: fitted.minY + (1 - normalized.y) * fitted.height
        )
        return CGPoint(
            x: center.x + (onPhoto.x - focus.x) * scale,
            y: center.y + (onPhoto.y - focus.y) * scale
        )
    }

    func points(_ normalized: [CGPoint]) -> [CGPoint] {
        isEmpty ? [] : normalized.map(point)
    }

    func corners(of quad: TextQuad) -> [CGPoint] {
        points(quad.corners)
    }

    /// A point on screen read back as a place on the photo. Clamped, because a drag that
    /// runs off the edge means the edge rather than somewhere outside the picture.
    func normalized(_ point: CGPoint) -> CGPoint {
        guard !isEmpty else { return .zero }
        let onPhoto = CGPoint(
            x: focus.x + (point.x - center.x) / scale,
            y: focus.y + (point.y - center.y) / scale
        )
        return CGPoint(
            x: min(max((onPhoto.x - fitted.minX) / fitted.width, 0), 1),
            y: min(max(1 - (onPhoto.y - fitted.minY) / fitted.height, 0), 1)
        )
    }

    /// Magnified about a point on screen, leaving whatever is under that point where it is.
    /// That is what a pinch means: the photo grows around the fingers rather than around the
    /// middle of the frame.
    func magnified(by factor: CGFloat, about anchor: CGPoint, limit: CGFloat) -> PhotoProjection {
        let next = min(max(scale * factor, 1), limit)
        let shift = 1 / scale - 1 / next
        return PhotoProjection(
            fitted: fitted,
            displaySize: displaySize,
            scale: next,
            focus: CGPoint(
                x: focus.x + (anchor.x - center.x) * shift,
                y: focus.y + (anchor.y - center.y) * shift
            )
        )
    }

    /// Moved by a drag on screen, which walks the focus the other way, and by less the further
    /// the photo is already magnified.
    func moved(by translation: CGSize) -> PhotoProjection {
        PhotoProjection(
            fitted: fitted,
            displaySize: displaySize,
            scale: scale,
            focus: CGPoint(
                x: focus.x - translation.width / scale,
                y: focus.y - translation.height / scale
            )
        )
    }

    /// A drawn outline, closed back onto itself.
    func closedPath(_ normalized: [CGPoint]) -> Path {
        path(normalized, closed: true)
    }

    /// A stroke still under the finger, left open.
    func openPath(_ normalized: [CGPoint]) -> Path {
        path(normalized, closed: false)
    }

    private func path(_ normalized: [CGPoint], closed: Bool) -> Path {
        var path = Path()
        let mapped = points(normalized)
        guard let start = mapped.first else { return path }
        path.move(to: start)
        for point in mapped.dropFirst() {
            path.addLine(to: point)
        }
        if closed { path.closeSubpath() }
        return path
    }

    /// Keeps the magnified window inside the photo. Without this, panning to a corner or
    /// zooming in on a word near an edge pulls the empty frame beside the photo into view.
    private static func clamped(
        _ focus: CGPoint,
        in fitted: CGRect,
        displaySize: CGSize,
        scale: CGFloat
    ) -> CGPoint {
        let window = CGSize(width: displaySize.width / scale, height: displaySize.height / scale)
        return CGPoint(
            x: clamped(
                focus.x,
                between: fitted.minX + window.width / 2,
                and: fitted.maxX - window.width / 2,
                otherwise: fitted.midX
            ),
            y: clamped(
                focus.y,
                between: fitted.minY + window.height / 2,
                and: fitted.maxY - window.height / 2,
                otherwise: fitted.midY
            )
        )
    }

    private static func clamped(
        _ value: CGFloat,
        between lower: CGFloat,
        and upper: CGFloat,
        otherwise fallback: CGFloat
    ) -> CGFloat {
        // The window is wider than the photo, so there is nothing to pan along this axis.
        guard lower <= upper else { return fallback }
        return min(max(value, lower), upper)
    }
}
