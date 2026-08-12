//
//  ScanResultView.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI

struct ScanResultView: View {
    @Bindable var viewModel: ScanViewModel

    @Environment(\.modelContext) private var modelContext

    /// The list opens over the whole screen. The photo is only worth room once there is a
    /// word to point at, and by then it is magnified rather than shown whole.
    @State private var isExpanded = true
    @State private var dragTranslation: CGFloat = 0
    @State private var listOffset: CGFloat = 0
    @State private var isDraggingSheet = false
    @State private var copyToastMessage: String?
    @State private var copyToastTask: Task<Void, Never>?
    @State private var suppressNextRowTap = false

    /// The tab bar shrinks as you scroll, which moves the bottom safe area up and down.
    /// This screen anchors to the physical bottom edge instead and reserves a fixed strip
    /// for the bar, so neither the photo nor the sheet resizes mid-scroll.
    private static let tabBarClearance: CGFloat = 88
    private static let accessoryClearance: CGFloat = 60

    /// What the list keeps once a word is selected. The strip left over is narrow, which is
    /// why the photo is magnified into it instead of being shown whole.
    private static let selectedSheetFraction: CGFloat = 0.6

    /// Room left around the word inside the magnified strip.
    private static let zoomPadding: CGFloat = 28

    /// Past this the stored photo has no detail left to reveal.
    private static let maxZoom: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let clearance = Self.tabBarClearance
            let usableHeight = max(geo.size.height - clearance, 0)
            let collapsedHeight = usableHeight * Self.selectedSheetFraction + clearance
            let expandedHeight = geo.size.height
            let panelHeight = resolvedHeight(
                collapsed: collapsedHeight,
                expanded: expandedHeight
            )

            ZStack(alignment: .bottom) {
                imageLayer(height: geo.size.height - collapsedHeight)

                wordPanel(height: panelHeight, collapsed: collapsedHeight, expanded: expandedHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottom) {
                if let copyToastMessage {
                    KYCopyToast(message: copyToastMessage)
                        .padding(.bottom, clearance + 36)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: copyToastMessage)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        // Keyed on the scan rather than the selection: clearing the selection by tapping the
        // selected word again is how the user asks for the whole photo, so the list has to
        // stay out of the way then.
        .onChange(of: viewModel.words.first?.id) {
            guard !isExpanded else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                isExpanded = true
            }
        }
    }

    /// Rows have to clear the strip the tab bar sits in, plus the save accessory when it
    /// is up. Both are scroll content insets, so growing them never moves the sheet itself.
    private var listBottomInset: CGFloat {
        let accessory = ScanViewModel.showsSaveInTabBar && viewModel.hasUnsavedOpenAIMeanings
            ? Self.accessoryClearance
            : 0
        return Self.tabBarClearance + accessory + 24
    }

    private func resolvedHeight(collapsed: CGFloat, expanded: CGFloat) -> CGFloat {
        let base = isExpanded ? expanded : collapsed
        return min(max(base - dragTranslation, collapsed), expanded)
    }

    // MARK: - Image

    private func imageLayer(height: CGFloat) -> some View {
        Group {
            if let image = viewModel.image {
                GeometryReader { geo in
                    let zoom = imageZoom(imageSize: image.size, displaySize: geo.size)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoom.scale, anchor: .center)
                        .offset(
                            x: (geo.size.width / 2 - zoom.focus.x) * zoom.scale,
                            y: (geo.size.height / 2 - zoom.focus.y) * zoom.scale
                        )
                        // Attached after the magnification so the outline and the bubble are
                        // placed by hand rather than blown up with the pixels.
                        .overlay {
                            highlightOverlay(
                                imageSize: image.size,
                                displaySize: geo.size,
                                zoom: zoom
                            )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .animation(
                            .spring(response: 0.42, dampingFraction: 0.86),
                            value: viewModel.selectedWordID
                        )
                }
                .frame(height: max(height, 160))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// How far to magnify the photo so the selected word is readable in the strip the list
    /// leaves behind. Showing the whole photo there would make every word too small, and
    /// giving the photo more room is what left the list cramped in the first place.
    private func imageZoom(imageSize: CGSize, displaySize: CGSize) -> ImageZoom {
        let center = CGPoint(x: displaySize.width / 2, y: displaySize.height / 2)
        let identity = ImageZoom(scale: 1, focus: center)
        guard let word = viewModel.selectedWord else { return identity }

        let corners = word.quads.flatMap {
            fittedCorners($0, imageSize: imageSize, displaySize: displaySize)
        }
        guard !corners.isEmpty else { return identity }

        let box = boundingRect(of: corners)
            .insetBy(dx: -Self.zoomPadding, dy: -Self.zoomPadding)
        guard box.width > 0, box.height > 0 else { return identity }

        let fit = min(displaySize.width / box.width, displaySize.height / box.height)
        let scale = min(fit, Self.maxZoom)
        guard scale > 1 else { return identity }

        // Words near an edge would otherwise pan the letterboxing into view.
        let photo = fittedRect(imageSize: imageSize, displaySize: displaySize)
        let window = CGSize(width: displaySize.width / scale, height: displaySize.height / scale)
        return ImageZoom(
            scale: scale,
            focus: CGPoint(
                x: clamped(
                    box.midX,
                    between: photo.minX + window.width / 2,
                    and: photo.maxX - window.width / 2,
                    otherwise: photo.midX
                ),
                y: clamped(
                    box.midY,
                    between: photo.minY + window.height / 2,
                    and: photo.maxY - window.height / 2,
                    otherwise: photo.midY
                )
            )
        )
    }

    private func clamped(
        _ value: CGFloat,
        between lower: CGFloat,
        and upper: CGFloat,
        otherwise fallback: CGFloat
    ) -> CGFloat {
        // The window is wider than the photo, so there is nothing to pan along this axis.
        guard lower <= upper else { return fallback }
        return min(max(value, lower), upper)
    }

    @ViewBuilder
    private func highlightOverlay(
        imageSize: CGSize,
        displaySize: CGSize,
        zoom: ImageZoom
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if let word = viewModel.selectedWord {
                let shapes = word.quads.map { quad in
                    mappedCorners(
                        quad,
                        imageSize: imageSize,
                        displaySize: displaySize,
                        zoom: zoom
                    )
                }

                ForEach(Array(shapes.enumerated()), id: \.offset) { _, corners in
                    QuadShape(corners: corners)
                        .fill(KYColor.highlight)
                        .overlay(
                            QuadShape(corners: corners)
                                .stroke(KYColor.highlightBorder, lineWidth: 2)
                        )
                        .transition(.opacity)
                }

                if let anchor = shapes.first {
                    let bounds = boundingRect(of: anchor)
                    SpeechBubble(text: word.displayMeaning) {
                        viewModel.showDetailWord = word
                    }
                    .position(x: bounds.midX, y: max(28, bounds.minY - 28))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: viewModel.selectedWordID)
    }

    /// Where the photo lands inside its frame once fitted, before any magnification.
    private func fittedRect(imageSize: CGSize, displaySize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(displaySize.width / imageSize.width, displaySize.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (displaySize.width - drawn.width) / 2,
            y: (displaySize.height - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        )
    }

    /// Vision normalizes to a bottom-left origin; SwiftUI draws from the top-left.
    private func fittedCorners(
        _ quad: TextQuad,
        imageSize: CGSize,
        displaySize: CGSize
    ) -> [CGPoint] {
        let photo = fittedRect(imageSize: imageSize, displaySize: displaySize)
        guard photo.width > 0, photo.height > 0 else { return [] }
        return quad.corners.map { point in
            CGPoint(
                x: photo.minX + point.x * photo.width,
                y: photo.minY + (1 - point.y) * photo.height
            )
        }
    }

    /// The same magnification the photo is drawn with, applied to a point by hand.
    private func mappedCorners(
        _ quad: TextQuad,
        imageSize: CGSize,
        displaySize: CGSize,
        zoom: ImageZoom
    ) -> [CGPoint] {
        let center = CGPoint(x: displaySize.width / 2, y: displaySize.height / 2)
        return fittedCorners(quad, imageSize: imageSize, displaySize: displaySize).map { point in
            CGPoint(
                x: center.x + (point.x - zoom.focus.x) * zoom.scale,
                y: center.y + (point.y - zoom.focus.y) * zoom.scale
            )
        }
    }

    private func boundingRect(of corners: [CGPoint]) -> CGRect {
        guard let first = corners.first else { return .zero }
        return corners.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
    }

    // MARK: - Word panel

    private func wordPanel(height: CGFloat, collapsed: CGFloat, expanded: CGFloat) -> some View {
        VStack(spacing: 0) {
            panelHeader
                .contentShape(Rectangle())
                .gesture(dragGesture(collapsed: collapsed, expanded: expanded, fromList: false))

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(KYFont.callout())
                    .foregroundStyle(KYColor.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            if viewModel.hasUnsavedOpenAIMeanings, !ScanViewModel.showsSaveInTabBar {
                saveBar
            }

            if viewModel.words.isEmpty && !viewModel.isProcessing {
                Text("아직 표시할 단어가 없어요.")
                    .font(KYFont.callout())
                    .foregroundStyle(KYColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.words) { word in
                            wordRow(word)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, listBottomInset)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in
                    listOffset = offset
                }
                // The list scrolls normally; only a pull past its top while expanded
                // hands the drag over to the sheet.
                .scrollDisabled(isDraggingSheet)
                .simultaneousGesture(
                    dragGesture(collapsed: collapsed, expanded: expanded, fromList: true)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(alignment: .top) {
            // Extended past the bottom edge so the drop shadow never lands
            // behind the translucent tab bar.
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24,
                style: .continuous
            )
            .fill(KYColor.card)
            .shadow(color: .black.opacity(0.10), radius: 16, y: -4)
            .frame(height: height + 240)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: isExpanded)
    }

    private var panelHeader: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(KYColor.textSecondary.opacity(0.35))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            HStack(spacing: 8) {
                Text("인식된 단어")
                    .font(KYFont.headline())
                    .foregroundStyle(KYColor.textPrimary)
                Spacer()
                if viewModel.isGeneratingMeanings {
                    ProgressView()
                        .controlSize(.mini)
                    Text("뜻 생성 중")
                        .font(KYFont.caption())
                        .foregroundStyle(KYColor.textSecondary)
                }
                Text("\(viewModel.words.count)개")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    /// A ChatGPT pass is shown before it is stored, so keeping it is a deliberate step.
    /// Saving replaces the meanings already in the cache for these words.
    private var saveBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ChatGPT 결과는 아직 저장 전이에요")
                    .font(KYFont.callout())
                    .foregroundStyle(KYColor.textPrimary)
                Text("저장하면 기존에 저장된 뜻을 덮어씁니다")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
            }
            Spacer(minLength: 0)
            Button("저장") {
                viewModel.saveOpenAIMeanings(modelContext: modelContext)
            }
            .font(KYFont.callout())
            .buttonStyle(.borderedProminent)
            .tint(KYColor.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(KYColor.primary.opacity(0.08))
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func dragGesture(collapsed: CGFloat, expanded: CGFloat, fromList: Bool) -> some Gesture {
        DragGesture(minimumDistance: fromList ? 6 : 0)
            .onChanged { value in
                if !isDraggingSheet {
                    guard canStartSheetDrag(translation: value.translation.height, fromList: fromList) else {
                        return
                    }
                    isDraggingSheet = true
                }
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                guard isDraggingSheet else { return }
                let threshold: CGFloat = 60
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                    if value.translation.height < -threshold {
                        isExpanded = true
                    } else if value.translation.height > threshold {
                        isExpanded = false
                    }
                    dragTranslation = 0
                }
                isDraggingSheet = false
            }
    }

    private func canStartSheetDrag(translation: CGFloat, fromList: Bool) -> Bool {
        guard fromList else { return true }
        // Only take over when the expanded list can no longer scroll up.
        return isExpanded && listOffset <= 0.5 && translation > 0
    }

    private func wordRow(_ word: RecognizedWord) -> some View {
        Button {
            // Long-press copy also ends with a touch-up; skip the tap that follows.
            if suppressNextRowTap {
                suppressNextRowTap = false
                return
            }
            viewModel.select(word)
            // Reveal the image instead of scrolling the page.
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                isExpanded = false
            }
        } label: {
            KYCard {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(word.displayHeadword)
                            .font(KYFont.headline())
                            .foregroundStyle(KYColor.textPrimary)
                        if !word.reading.isEmpty {
                            Text(word.reading)
                                .font(KYFont.caption())
                                .foregroundStyle(KYColor.textSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(word.displayMeaning)
                            .font(KYFont.body())
                            .foregroundStyle(KYColor.textPrimary)
                            .multilineTextAlignment(.trailing)
                        if !word.hangul.isEmpty {
                            Text(word.hangul)
                                .font(KYFont.caption())
                                .foregroundStyle(KYColor.primary)
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        viewModel.selectedWordID == word.id ? KYColor.primary : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    suppressNextRowTap = true
                    copyJapanese(word.displayHeadword)
                }
        )
        .accessibilityHint("길게 누르면 일본어를 복사합니다")
    }

    private func copyJapanese(_ text: String) {
        ClipboardCopy.copy(text)
        copyToastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            copyToastMessage = "「\(text)」 복사됨"
        }
        copyToastTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    copyToastMessage = nil
                }
            }
        }
    }
}

/// A magnification of the photo, expressed as the point it is centred on and how far it is
/// blown up around it.
private struct ImageZoom {
    var scale: CGFloat
    var focus: CGPoint
}

private struct QuadShape: Shape {
    let corners: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard corners.count == 4 else { return path }
        path.move(to: corners[0])
        for point in corners.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
