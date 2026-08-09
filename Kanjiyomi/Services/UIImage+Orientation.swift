//
//  UIImage+Orientation.swift
//  Kanjiyomi
//

import UIKit

extension UIImage {
    /// Redraws the image so its pixel buffer matches what the user sees.
    ///
    /// Vision reports coordinates relative to the raw `CGImage`, while SwiftUI renders
    /// with `imageOrientation` applied. Camera captures are usually `.right`, so without
    /// this the highlight boxes end up rotated 90 degrees.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
