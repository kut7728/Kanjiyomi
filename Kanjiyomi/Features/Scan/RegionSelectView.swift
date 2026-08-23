//
//  RegionSelectView.swift
//  Kanjiyomi
//

import SwiftUI
import UIKit

/// Draws freeform outlines over the photo and hands back the region they enclose.
///
/// Given its own screen rather than a mode on the result view: the photo there is a strip
/// beside the word list, which is too small to trace a paragraph in, and the panel already
/// owns the drag gesture that tracing needs.
struct RegionSelectView: View {
    let image: UIImage
    let words: [RecognizedWord]
    let onApply: (SelectionRegion?) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Finished outlines, in Vision normalized coordinates so they mean the same thing here
    /// and on the result screen, which draws the photo at a different size.
    @State private var outlines: [[CGPoint]]

    /// The stroke under the finger, kept apart so it can be drawn open and thrown away if it
    /// never grows into an area.
    @State private var stroke: [CGPoint] = []

    /// How far the photo is magnified, and which place on it sits in the middle of the frame.
    /// Kept normalized for the same reason the outlines are: the frame changes size, the photo
    /// does not.
    @State private var scale: CGFloat = 1
    @State private var focusPoint = CGPoint(x: 0.5, y: 0.5)

    /// How far the finger has to travel before another point is recorded, at the size the
    /// photo is shown whole. Every point is an edge that each word is tested against on every
    /// frame, and magnifying divides it so tracing stays as fine as the zoom promises.
    private static let minimumStep: CGFloat = 0.005

    /// Below this a stroke is a tap or a stray flick, with no area to hold words.
    private static let minimumPoints = 3

    /// Past this the stored photo has no detail left to reveal.
    private static let maxZoom: CGFloat = 6

    /// Close enough to trace a single word, without losing the sentence around it.
    private static let doubleTapZoom: CGFloat = 3

    init(
        image: UIImage,
        words: [RecognizedWord],
        region: SelectionRegion?,
        onApply: @escaping (SelectionRegion?) -> Void
    ) {
        self.image = image
        self.words = words
        self.onApply = onApply
        _outlines = State(initialValue: region?.polygons ?? [])
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                canvas
                footer
            }
        }
        .preferredColorScheme(.dark)
    }

    /// What the outlines drawn so far select, including the one still being drawn so the
    /// words light up under the finger.
    private var liveRegion: SelectionRegion {
        SelectionRegion(polygons: outlines + (stroke.count >= Self.minimumPoints ? [stroke] : []))
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let projection = projection(in: geo.size)
            let region = liveRegion

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(projection.scale, anchor: .center)
                    .offset(projection.drawOffset)

                // One canvas rather than a view per word: a page of text is hundreds of
                // quads, all of them redrawn on every point the finger adds.
                Canvas { context, size in
                    draw(region: region, projection: projection, in: context, size: size)
                }

                PhotoCanvasGestures(
                    onDraw: { extend(to: $0, in: geo.size) },
                    onDrawFinish: commitStroke,
                    onDrawCancel: { stroke = [] },
                    onMove: { move(by: $0, in: geo.size) },
                    onMagnify: { magnify(by: $0, about: $1, in: geo.size) },
                    onDoubleTap: { toggleZoom(about: $0, in: geo.size) }
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }
            // The photo grows past its frame once magnified, and the header and footer are
            // right up against it.
            .clipped()
        }
        .padding(.horizontal, 12)
    }

    /// Read from the state on every call rather than captured, so a gesture always builds on
    /// where the photo actually is.
    private func projection(in displaySize: CGSize) -> PhotoProjection {
        PhotoProjection(
            imageSize: image.size,
            displaySize: displaySize,
            scale: scale,
            focus: whole(displaySize).point(focusPoint)
        )
    }

    /// The photo shown whole, which is the space the focus is remembered in.
    private func whole(_ displaySize: CGSize) -> PhotoProjection {
        PhotoProjection(imageSize: image.size, displaySize: displaySize)
    }

    private func draw(
        region: SelectionRegion,
        projection: PhotoProjection,
        in context: GraphicsContext,
        size: CGSize
    ) {
        var context = context

        // Shading everything the outlines leave out says what is being dropped without
        // having to outline it.
        if !region.isEmpty {
            var mask = Path(CGRect(origin: .zero, size: size))
            for polygon in region.polygons {
                mask.addPath(projection.closedPath(polygon))
            }
            context.fill(mask, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
        }

        for word in words {
            for quad in word.quads {
                let corners = projection.corners(of: quad)
                guard corners.count == 4 else { continue }
                var path = Path()
                path.move(to: corners[0])
                for corner in corners.dropFirst() { path.addLine(to: corner) }
                path.closeSubpath()

                if region.covers(quad) {
                    context.fill(path, with: .color(KYColor.highlight))
                    context.stroke(path, with: .color(KYColor.highlightBorder), lineWidth: 1.5)
                } else {
                    context.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 1)
                }
            }
        }

        for polygon in outlines {
            context.stroke(
                projection.closedPath(polygon),
                with: .color(KYColor.highlightBorder),
                style: StrokeStyle(lineWidth: 2, lineJoin: .round)
            )
        }

        // Dashed and open while it is still being drawn, so it reads as unfinished.
        if stroke.count >= 2 {
            context.stroke(
                projection.openPath(stroke),
                with: .color(.white),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [7, 5])
            )
        }
    }

    // MARK: - Gestures

    private func extend(to location: CGPoint, in displaySize: CGSize) {
        let point = projection(in: displaySize).normalized(location)
        guard let last = stroke.last else {
            stroke = [point]
            return
        }
        guard hypot(point.x - last.x, point.y - last.y) >= Self.minimumStep / scale else { return }
        stroke.append(point)
    }

    private func commitStroke() {
        let drawn = stroke
        stroke = []
        guard drawn.count >= Self.minimumPoints else { return }
        outlines.append(drawn)
    }

    private func move(by translation: CGSize, in displaySize: CGSize) {
        focusPoint = remembered(projection(in: displaySize).moved(by: translation), in: displaySize)
    }

    private func magnify(by factor: CGFloat, about anchor: CGPoint, in displaySize: CGSize) {
        let magnified = projection(in: displaySize)
            .magnified(by: factor, about: anchor, limit: Self.maxZoom)
        scale = magnified.scale
        focusPoint = remembered(magnified, in: displaySize)
    }

    /// The projection clamps its own focus to keep the photo filling the frame, so what is
    /// remembered has to be read back off it rather than from what the fingers asked for.
    private func remembered(_ projection: PhotoProjection, in displaySize: CGSize) -> CGPoint {
        whole(displaySize).normalized(projection.focus)
    }

    /// A double tap is the way in and out of a magnified photo for anyone who does not think
    /// to pinch, so it does whichever of the two the photo is not already showing.
    private func toggleZoom(about anchor: CGPoint, in displaySize: CGSize) {
        guard scale == 1 else {
            resetZoom()
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            magnify(by: Self.doubleTapZoom, about: anchor, in: displaySize)
        }
    }

    private func resetZoom() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            scale = 1
            focusPoint = CGPoint(x: 0.5, y: 0.5)
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Button("취소") { dismiss() }
                .font(KYFont.callout())
                .foregroundStyle(.white.opacity(0.85))
                .frame(minWidth: 56, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text("영역 선택")
                    .font(KYFont.headline())
                    .foregroundStyle(.white)
                Text(summary)
                    .font(KYFont.caption())
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer(minLength: 0)

            Button("적용") { apply() }
                .font(KYFont.body())
                .foregroundStyle(KYColor.highlightBorder)
                .frame(minWidth: 56, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var summary: String {
        outlines.isEmpty
            ? "사진 전체"
            : "영역 \(outlines.count)개 · 단어 \(selectedCount)개"
    }

    private var selectedCount: Int {
        let region = SelectionRegion(polygons: outlines)
        guard !region.isEmpty else { return words.count }
        return words.filter { word in word.quads.contains { region.covers($0) } }.count
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Text("한 손가락으로 원하는 부분을 감싸듯 그려 주세요. 네모가 아니어도 되고, 여러 번 그려서 영역을 더할 수 있어요. 두 손가락으로는 사진을 확대하거나 움직입니다.")
                .font(KYFont.caption())
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            HStack(spacing: 10) {
                toolButton(
                    "되돌리기",
                    systemImage: "arrow.uturn.backward",
                    isEnabled: !outlines.isEmpty
                ) {
                    outlines.removeLast()
                }
                toolButton(
                    "전체 지우기",
                    systemImage: "trash",
                    isEnabled: !outlines.isEmpty
                ) {
                    outlines = []
                }
                toolButton(
                    "원래 크기",
                    systemImage: "minus.magnifyingglass",
                    isEnabled: scale > 1,
                    action: resetZoom
                )
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 28)
    }

    private func toolButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(KYFont.callout())
                .foregroundStyle(.white)
                // Three of these have to share the narrowest screen the app runs on.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }

    private func apply() {
        let region = SelectionRegion(polygons: outlines)
        onApply(region.isEmpty ? nil : region)
        dismiss()
    }
}
