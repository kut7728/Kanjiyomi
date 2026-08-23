//
//  RegionSelectionTests.swift
//  KanjiyomiTests
//

import CoreGraphics
import Testing
@testable import Kanjiyomi

@MainActor
struct PhotoProjectionTests {
    /// A square photo in a wide frame is letterboxed left and right, and Vision's bottom-left
    /// origin has to land on SwiftUI's top-left.
    @Test func fitsAndFlipsVertically() {
        let projection = PhotoProjection(
            imageSize: CGSize(width: 100, height: 100),
            displaySize: CGSize(width: 200, height: 100)
        )

        #expect(projection.fitted == CGRect(x: 50, y: 0, width: 100, height: 100))
        #expect(projection.point(CGPoint(x: 0, y: 1)) == CGPoint(x: 50, y: 0))
        #expect(projection.point(CGPoint(x: 1, y: 0)) == CGPoint(x: 150, y: 100))
        #expect(projection.point(CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 100, y: 50))
    }

    @Test func readsTouchesBackToTheSamePlace() {
        let projection = PhotoProjection(
            imageSize: CGSize(width: 300, height: 400),
            displaySize: CGSize(width: 200, height: 500)
        )

        for original in [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0.23, y: 0.71)
        ] {
            let roundTripped = projection.normalized(projection.point(original))
            #expect(abs(roundTripped.x - original.x) < 0.0001)
            #expect(abs(roundTripped.y - original.y) < 0.0001)
        }
    }

    /// Magnified, a touch still has to name the place on the photo under it, or an outline
    /// drawn while zoomed in would land somewhere else once the zoom is dropped.
    @Test func readsTouchesBackWhileMagnified() {
        let projection = PhotoProjection(
            imageSize: CGSize(width: 100, height: 100),
            displaySize: CGSize(width: 200, height: 100),
            scale: 3,
            focus: CGPoint(x: 80, y: 40)
        )

        let original = CGPoint(x: 0.4, y: 0.65)
        let roundTripped = projection.normalized(projection.point(original))
        #expect(abs(roundTripped.x - original.x) < 0.0001)
        #expect(abs(roundTripped.y - original.y) < 0.0001)
    }

    /// Shown whole, the photo needs no offset and sits on the middle of its frame.
    @Test func sitsStillUntilMagnified() {
        let projection = PhotoProjection(
            imageSize: CGSize(width: 100, height: 100),
            displaySize: CGSize(width: 200, height: 100)
        )

        #expect(projection.focus == CGPoint(x: 100, y: 50))
        #expect(projection.drawOffset == .zero)
    }

    /// A pinch grows the photo around the fingers, so whatever they are over has to stay
    /// under them.
    @Test func magnifiesAroundTheFingers() {
        let projection = PhotoProjection(
            imageSize: CGSize(width: 100, height: 100),
            displaySize: CGSize(width: 200, height: 200)
        )
        let anchor = CGPoint(x: 120, y: 80)
        let before = projection.normalized(anchor)

        let magnified = projection.magnified(by: 2, about: anchor, limit: 6)
        let after = magnified.normalized(anchor)

        #expect(magnified.scale == 2)
        #expect(abs(after.x - before.x) < 0.0001)
        #expect(abs(after.y - before.y) < 0.0001)
    }

    @Test func magnifiesNoFurtherThanTheLimit() {
        let projection = PhotoProjection(
            imageSize: CGSize(width: 100, height: 100),
            displaySize: CGSize(width: 200, height: 200)
        )

        #expect(projection.magnified(by: 40, about: CGPoint(x: 100, y: 100), limit: 6).scale == 6)
        // Zooming out past the whole photo would only add letterboxing.
        #expect(projection.magnified(by: 0.2, about: CGPoint(x: 100, y: 100), limit: 6).scale == 1)
    }

    /// Dragging the photo right moves the window over it left, and by less the further in it
    /// is magnified.
    @Test func movesAgainstTheDrag() {
        let projection = PhotoProjection(
            imageSize: CGSize(width: 100, height: 100),
            displaySize: CGSize(width: 200, height: 200),
            scale: 2
        )
        #expect(projection.focus == CGPoint(x: 100, y: 100))

        let moved = projection.moved(by: CGSize(width: 30, height: -10))
        #expect(moved.focus == CGPoint(x: 85, y: 105))
    }

    /// However far the drag runs, the photo keeps filling the frame rather than sliding off
    /// it and showing the empty space beside it.
    @Test func neverMovesPastThePhoto() {
        let projection = PhotoProjection(
            imageSize: CGSize(width: 100, height: 100),
            displaySize: CGSize(width: 200, height: 200),
            scale: 2
        )

        let moved = projection.moved(by: CGSize(width: -4000, height: 4000))
        // Half the magnified window short of each edge.
        #expect(moved.focus == CGPoint(x: 150, y: 50))
    }

    @Test func hasNothingToMoveWhenShownWhole() {
        let projection = PhotoProjection(
            imageSize: CGSize(width: 100, height: 100),
            displaySize: CGSize(width: 200, height: 100)
        )

        #expect(projection.moved(by: CGSize(width: 80, height: 40)).focus == projection.focus)
    }

    /// A drag that runs past the photo means the edge of it, not a point outside the picture.
    @Test func clampsTouchesOutsideThePhoto() {
        let projection = PhotoProjection(
            imageSize: CGSize(width: 100, height: 100),
            displaySize: CGSize(width: 200, height: 100)
        )

        let offTopLeft = projection.normalized(CGPoint(x: -40, y: -40))
        #expect(offTopLeft == CGPoint(x: 0, y: 1))

        let offBottomRight = projection.normalized(CGPoint(x: 400, y: 400))
        #expect(offBottomRight == CGPoint(x: 1, y: 0))
    }
}

@MainActor
struct SelectionRegionTests {
    /// The upper-left quarter of the photo, in Vision coordinates where y grows upward.
    private let upperLeft = SelectionRegion(polygons: [[
        CGPoint(x: 0, y: 0.5),
        CGPoint(x: 0.5, y: 0.5),
        CGPoint(x: 0.5, y: 1),
        CGPoint(x: 0, y: 1)
    ]])

    private func quad(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> TextQuad {
        TextQuad(rect: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func keepsWordsInsideAndDropsWordsOutside() {
        #expect(upperLeft.covers(quad(x: 0.1, y: 0.6, width: 0.2, height: 0.08)))
        #expect(!upperLeft.covers(quad(x: 0.6, y: 0.1, width: 0.2, height: 0.08)))
    }

    @Test func keepsWordsMostlyInside() {
        // Three quarters of its width falls inside.
        #expect(upperLeft.covers(quad(x: 0.35, y: 0.6, width: 0.2, height: 0.08)))
    }

    /// Passing an outline by the end of a word is not asking for that word.
    @Test func dropsWordsOnlyGrazed() {
        let grazed = quad(x: 0.45, y: 0.6, width: 0.2, height: 0.08)
        #expect(upperLeft.coverage(of: grazed) < SelectionRegion.minimumCoverage)
        #expect(!upperLeft.covers(grazed))
    }

    /// A short stroke through the middle of a long word is how that one word gets picked, so
    /// enclosing most of its length cannot be the only way in.
    @Test func keepsWordsStruckThroughTheMiddle() {
        let diamond = SelectionRegion(polygons: [[
            CGPoint(x: 0.44, y: 0.525),
            CGPoint(x: 0.5, y: 0.585),
            CGPoint(x: 0.56, y: 0.525),
            CGPoint(x: 0.5, y: 0.465)
        ]])
        let long = quad(x: 0.1, y: 0.5, width: 0.8, height: 0.05)

        #expect(diamond.coverage(of: long) < SelectionRegion.minimumCoverage)
        #expect(diamond.covers(long))
    }

    /// Outlines add up, so two paragraphs can be picked without one stroke.
    @Test func addsUpSeveralOutlines() {
        let both = SelectionRegion(polygons: [
            [CGPoint(x: 0, y: 0.8), CGPoint(x: 0.3, y: 0.8), CGPoint(x: 0.3, y: 1), CGPoint(x: 0, y: 1)],
            [CGPoint(x: 0.7, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 0.2), CGPoint(x: 0.7, y: 0.2)]
        ])

        #expect(both.covers(quad(x: 0.05, y: 0.85, width: 0.2, height: 0.08)))
        #expect(both.covers(quad(x: 0.75, y: 0.05, width: 0.2, height: 0.08)))
        #expect(!both.covers(quad(x: 0.4, y: 0.45, width: 0.2, height: 0.08)))
    }

    @Test func ignoresOutlinesWithoutArea() {
        let region = SelectionRegion(polygons: [
            [],
            [CGPoint(x: 0.2, y: 0.2)],
            [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.4, y: 0.4)]
        ])

        #expect(region.isEmpty)
        #expect(!region.covers(quad(x: 0.2, y: 0.2, width: 0.2, height: 0.08)))
    }
}

@MainActor
struct ScanRegionFilterTests {
    private func word(_ surface: String, at rects: [CGRect]) -> RecognizedWord {
        RecognizedWord(
            surface: surface,
            lemma: surface,
            meaningKO: "뜻",
            quads: rects.map(TextQuad.init(rect:))
        )
    }

    private let upperLeft = SelectionRegion(polygons: [[
        CGPoint(x: 0, y: 0.5),
        CGPoint(x: 0.5, y: 0.5),
        CGPoint(x: 0.5, y: 1),
        CGPoint(x: 0, y: 1)
    ]])

    @Test func showsEveryWordWithoutARegion() {
        let model = ScanViewModel()
        model.words = [
            word("天気", at: [CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.08)]),
            word("公園", at: [CGRect(x: 0.7, y: 0.1, width: 0.2, height: 0.08)])
        ]

        #expect(model.displayWords.map(\.surface) == ["天気", "公園"])
    }

    @Test func showsOnlyWordsInsideTheRegion() {
        let model = ScanViewModel()
        model.words = [
            word("天気", at: [CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.08)]),
            word("公園", at: [CGRect(x: 0.7, y: 0.1, width: 0.2, height: 0.08)])
        ]

        model.applyRegion(upperLeft)
        #expect(model.displayWords.map(\.surface) == ["天気"])

        model.applyRegion(nil)
        #expect(model.displayWords.count == 2)
    }

    /// A word found in two places keeps only the place inside the region, so the photo never
    /// highlights something the region is hiding.
    @Test func keepsOnlyTheOccurrencesInsideTheRegion() {
        let model = ScanViewModel()
        model.words = [
            word("天気", at: [
                CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.08),
                CGRect(x: 0.7, y: 0.1, width: 0.2, height: 0.08)
            ])
        ]

        model.applyRegion(upperLeft)
        #expect(model.displayWords.first?.quads.count == 1)
        #expect(model.displayWords.first?.quads.first?.centroid.x ?? 1 < 0.5)
    }

    /// Magnifying onto a highlight the region just hid would leave the photo pointing at a
    /// word with no row in the list.
    @Test func dropsASelectionTheRegionHides() {
        let model = ScanViewModel()
        let outside = word("公園", at: [CGRect(x: 0.7, y: 0.1, width: 0.2, height: 0.08)])
        model.words = [
            word("天気", at: [CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.08)]),
            outside
        ]
        model.select(outside)
        #expect(model.selectedWord != nil)

        model.applyRegion(upperLeft)
        #expect(model.selectedWordID == nil)
    }
}
