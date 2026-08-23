//
//  PhotoCanvasGestures.swift
//  Kanjiyomi
//

import SwiftUI
import UIKit

/// Splits touches on the photo by how many fingers are down: one draws, two magnify and move.
///
/// Built on UIKit recognizers because SwiftUI's DragGesture cannot say how many fingers it is
/// following, and the alternatives are both worse. A mode switch would make the user declare
/// which one they meant before every stroke, and leaving out panning would put anything the
/// user zoomed past out of reach.
struct PhotoCanvasGestures: UIViewRepresentable {
    /// Where the drawing finger is now, in the view's own coordinates.
    let onDraw: (CGPoint) -> Void
    let onDrawFinish: () -> Void

    /// A second finger landed, so what was being drawn was never a stroke.
    let onDrawCancel: () -> Void

    /// How far two fingers travelled since the last report.
    let onMove: (CGSize) -> Void

    /// How much further apart two fingers got since the last report, and the point between
    /// them that has to stay put.
    let onMagnify: (CGFloat, CGPoint) -> Void

    /// Where a double tap landed, which is the shortcut for magnifying without a pinch.
    let onDoubleTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let draw = OneFingerPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.draw)
        )
        let move = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.move)
        )
        move.minimumNumberOfTouches = 2
        let magnify = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.magnify)
        )
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.doubleTap)
        )
        doubleTap.numberOfTapsRequired = 2

        for recognizer in [draw, move, magnify, doubleTap] as [UIGestureRecognizer] {
            recognizer.delegate = context.coordinator
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.owner = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(owner: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: PhotoCanvasGestures

        init(owner: PhotoCanvasGestures) {
            self.owner = owner
        }

        @objc func draw(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                owner.onDraw(recognizer.location(in: recognizer.view))
            case .ended:
                owner.onDrawFinish()
            case .cancelled, .failed:
                owner.onDrawCancel()
            default:
                break
            }
        }

        /// Reported as the change since the last call, so magnifying and moving at the same
        /// time needs no bookkeeping between the two recognizers.
        @objc func move(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .changed else { return }
            let translation = recognizer.translation(in: recognizer.view)
            owner.onMove(CGSize(width: translation.x, height: translation.y))
            recognizer.setTranslation(.zero, in: recognizer.view)
        }

        @objc func magnify(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .changed else { return }
            owner.onMagnify(recognizer.scale, recognizer.location(in: recognizer.view))
            recognizer.scale = 1
        }

        @objc func doubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            owner.onDoubleTap(recognizer.location(in: recognizer.view))
        }

        /// Magnifying and moving are one two-fingered gesture as far as the user is concerned.
        /// Drawing cannot join in: it gives up the moment a second finger lands.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// Gives up as soon as a second finger lands, so spreading two fingers is never mistaken for
/// the beginning of a stroke. A plain pan recognizer capped at one touch keeps following the
/// first finger instead, which draws a line across the photo every time the user zooms.
private final class OneFingerPanGestureRecognizer: UIPanGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard numberOfTouches > 1 else { return }
        state = state == .possible ? .failed : .cancelled
    }
}
