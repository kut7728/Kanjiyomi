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
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
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
                if let toastMessage {
                    KYCopyToast(message: toastMessage)
                        .padding(.bottom, clearance + 36)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: toastMessage)
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
        let accessory = ScanViewModel.showsSaveInTabBar && viewModel.hasUnsavedWords
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
                    let projection = projection(imageSize: image.size, displaySize: geo.size)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(projection.scale, anchor: .center)
                        .offset(projection.drawOffset)
                        // Attached after the magnification so the outline and the bubble are
                        // placed by hand rather than blown up with the pixels.
                        .overlay {
                            highlightOverlay(projection: projection)
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
    private func projection(imageSize: CGSize, displaySize: CGSize) -> PhotoProjection {
        let flat = PhotoProjection(imageSize: imageSize, displaySize: displaySize)
        guard let word = viewModel.selectedWord else { return flat }

        let corners = word.quads.flatMap(flat.corners(of:))
        guard !corners.isEmpty else { return flat }

        let box = boundingRect(of: corners)
            .insetBy(dx: -Self.zoomPadding, dy: -Self.zoomPadding)
        guard box.width > 0, box.height > 0 else { return flat }

        let fit = min(displaySize.width / box.width, displaySize.height / box.height)
        let scale = min(fit, Self.maxZoom)
        guard scale > 1 else { return flat }

        return PhotoProjection(
            imageSize: imageSize,
            displaySize: displaySize,
            scale: scale,
            focus: CGPoint(x: box.midX, y: box.midY)
        )
    }

    @ViewBuilder
    private func highlightOverlay(projection: PhotoProjection) -> some View {
        ZStack(alignment: .topLeading) {
            // Only while the whole photo is on screen: once a word is picked the photo is
            // magnified onto it, and shading the rest of a close-up says nothing.
            if let region = viewModel.region, viewModel.selectedWordID == nil {
                Canvas { context, size in
                    var outside = Path(CGRect(origin: .zero, size: size))
                    for polygon in region.polygons {
                        outside.addPath(projection.closedPath(polygon))
                    }
                    context.fill(
                        outside,
                        with: .color(.black.opacity(0.35)),
                        style: FillStyle(eoFill: true)
                    )
                    for polygon in region.polygons {
                        context.stroke(
                            projection.closedPath(polygon),
                            with: .color(KYColor.highlightBorder),
                            style: StrokeStyle(lineWidth: 2, lineJoin: .round)
                        )
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            if let word = viewModel.selectedWord {
                let shapes = word.quads.map(projection.corners(of:))

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

            if viewModel.region != nil {
                regionBar
            }

            if viewModel.hasUnsavedWords, !ScanViewModel.showsSaveInTabBar {
                saveBar
            }

            if viewModel.displayWords.isEmpty && !viewModel.isProcessing {
                Text(
                    viewModel.region == nil
                        ? "아직 표시할 단어가 없어요."
                        : "선택한 영역 안에는 단어가 없어요."
                )
                .font(KYFont.callout())
                .foregroundStyle(KYColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.displayWords) { word in
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
                Text("\(viewModel.displayWords.count)개")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    /// A short list is otherwise indistinguishable from a photo that read badly, so the
    /// region says it is doing the hiding and offers the way back.
    private var regionBar: some View {
        HStack(spacing: 12) {
            Label("선택한 영역의 단어만 보고 있어요", systemImage: "lasso")
                .font(KYFont.caption())
                .foregroundStyle(KYColor.primary)
            Spacer(minLength: 0)
            Button("전체 보기") {
                viewModel.applyRegion(nil)
            }
            .font(KYFont.caption())
            .foregroundStyle(KYColor.primary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(KYColor.primary.opacity(0.08))
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    /// Recognition only puts words on screen, so keeping them is a deliberate step.
    private var saveBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("아직 단어장에 저장하지 않았어요")
                    .font(KYFont.callout())
                    .foregroundStyle(KYColor.textPrimary)
                Text(viewModel.saveHint)
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
            }
            Spacer(minLength: 0)
            Button("저장", action: save)
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

    /// The bar disappears once saved, which says the tap registered but not what it did, so
    /// the count of words that actually joined the list is reported separately.
    private func save() {
        let added = viewModel.saveToVocabulary(modelContext: modelContext)
        showToast(added > 0 ? "단어장에 \(added)개 저장됨" : "이미 단어장에 있는 단어예요")
    }

    private func copyJapanese(_ text: String) {
        ClipboardCopy.copy(text)
        showToast("「\(text)」 복사됨")
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            toastMessage = message
        }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    toastMessage = nil
                }
            }
        }
    }
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
