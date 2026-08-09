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

    /// Downscaled JPEG for scan history. Highlight coordinates are normalized,
    /// so a smaller image still lines up with the recognized regions.
    func storageJPEGData(maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return jpegData(compressionQuality: quality) }

        let ratio = maxDimension / longest
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
