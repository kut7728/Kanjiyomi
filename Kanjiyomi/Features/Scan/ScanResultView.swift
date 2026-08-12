//
//  ScanResultView.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI

struct ScanResultView: View {
    @Bindable var viewModel: ScanViewModel

    @Environment(\.modelContext) private var modelContext

    @State private var isExpanded = false
    @State private var dragTranslation: CGFloat = 0
    @State private var listOffset: CGFloat = 0
    @State private var isDraggingSheet = false
    @State private var copyToastMessage: String?
    @State private var copyToastTask: Task<Void, Never>?
    @State private var suppressNextRowTap = false

    var body: some View {
        GeometryReader { geo in
            let collapsedHeight = geo.size.height * 0.42
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
                        .padding(.bottom, 36)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: copyToastMessage)
        }
    }

    private func resolvedHeight(collapsed: CGFloat, expanded: CGFloat) -> CGFloat {
        let base = isExpanded ? expanded : collapsed
        return min(max(base - dragTranslation, collapsed), expanded)
    }

    // MARK: - Image

    private func imageLayer(height: CGFloat) -> some View {
        Group {
            if let image = viewModel.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: max(height, 160))
                    .overlay {
                        highlightOverlay(imageSize: image.size)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func highlightOverlay(imageSize: CGSize) -> some View {
        GeometryReader { geo in
            let displaySize = geo.size
            ZStack(alignment: .topLeading) {
                if let word = viewModel.selectedWord {
                    let shapes = word.quads.map { quad in
                        mappedCorners(quad, imageSize: imageSize, displaySize: displaySize)
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
    }

    /// Vision normalizes to a bottom-left origin; SwiftUI draws from the top-left.
    private func mappedCorners(
        _ quad: TextQuad,
        imageSize: CGSize,
        displaySize: CGSize
    ) -> [CGPoint] {
        guard imageSize.width > 0, imageSize.height > 0 else { return [] }
        let scale = min(displaySize.width / imageSize.width, displaySize.height / imageSize.height)
        let drawnWidth = imageSize.width * scale
        let drawnHeight = imageSize.height * scale
        let offsetX = (displaySize.width - drawnWidth) / 2
        let offsetY = (displaySize.height - drawnHeight) / 2

        return quad.corners.map { point in
            CGPoint(
                x: offsetX + point.x * drawnWidth,
                y: offsetY + (1 - point.y) * drawnHeight
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
                    .padding(.bottom, 24)
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
