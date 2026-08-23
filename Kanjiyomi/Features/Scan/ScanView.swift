//
//  ScanView.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI
import UIKit

struct ScanView: View {
    /// Owned by the tab view so the save prompt can live in the tab bar accessory, which
    /// is attached above this screen.
    @Bindable var viewModel: ScanViewModel

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var records: [ScanRecord]
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickedImage: UIImage?
    /// Carried over to the next photo. Only ever holds an on-device mode: ChatGPT bills the
    /// user, so it has to be asked for rather than quietly becoming the default.
    @AppStorage("wordSegmentation") private var defaultMode: SegmentationMode = .dictionary

    /// Read from the words on screen rather than from this view's own state. Switching tabs
    /// can rebuild this view, and a remembered selection here would reset while the results
    /// it described stayed put, leaving the menu describing a pass that never happened.
    private var activeMode: SegmentationMode {
        viewModel.activeMode
    }

    private var onDeviceModes: [SegmentationMode] {
        SegmentationMode.available.filter { $0 != .openAI }
    }

    var body: some View {
        NavigationStack {
            // The scroll view must be the direct content so the large title
            // collapses as the user scrolls.
            Group {
                if viewModel.image != nil {
                    ScanResultView(viewModel: viewModel)
                } else {
                    home
                }
            }
            .background(KYColor.background)
            .overlay {
                if viewModel.isProcessing {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        KYLoadingOverlay(message: viewModel.statusMessage)
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("스캔")
            // The result screen is a fixed image plus a floating panel, so a large
            // title would just eat space that the photo needs.
            .navigationBarTitleDisplayMode(viewModel.image == nil ? .large : .inline)
            .toolbar {
                if viewModel.image != nil && !viewModel.isProcessing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.reset()
                            pickedImage = nil
                        } label: {
                            Label("홈", systemImage: "chevron.left")
                        }
                        .font(KYFont.callout())
                        .foregroundStyle(KYColor.primary)
                    }
                }
                // In the toolbar rather than on the photo: the word list opens over the whole
                // screen, so at the moment the user wants to narrow it there is no photo on
                // screen to put a button on.
                if viewModel.canSelectRegion {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.isSelectingRegion = true
                        } label: {
                            Label(
                                "영역 선택",
                                systemImage: viewModel.region == nil ? "lasso" : "lasso.badge.sparkles"
                            )
                        }
                        .font(KYFont.callout())
                        .foregroundStyle(KYColor.primary)
                    }
                }
                if viewModel.canChooseSegmentation {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Section("이 기기에서 처리") {
                                ForEach(onDeviceModes) { mode in
                                    modeButton(mode)
                                }
                            }
                            // Kept in its own section so the paid option can never be
                            // mistaken for one of the free ones sitting next to it.
                            if OpenAIService.shared.isConfigured {
                                Section("내 API 키로 요청 · 요금 발생") {
                                    modeButton(.openAI)
                                }
                            } else {
                                Section {
                                    Button("설정에서 API 키를 넣으면 ChatGPT도 쓸 수 있어요") {}
                                        .disabled(true)
                                }
                            }
                        } label: {
                            Label("단어 나누기", systemImage: activeMode.systemImage)
                        }
                        .foregroundStyle(KYColor.primary)
                        .disabled(viewModel.isGeneratingMeanings)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(image: $pickedImage)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showLibrary) {
                LibraryPicker(image: $pickedImage)
            }
            .fullScreenCover(isPresented: $viewModel.isSelectingRegion) {
                if let image = viewModel.image {
                    // Every word, not just the ones on screen: a region has to be widened
                    // from inside the same editor that narrowed it.
                    RegionSelectView(
                        image: image,
                        words: viewModel.words,
                        region: viewModel.region
                    ) { region in
                        viewModel.applyRegion(region)
                    }
                }
            }
            .onChange(of: pickedImage) { _, newValue in
                guard let newValue else { return }
                viewModel.image = newValue
                Task {
                    await viewModel.process(mode: defaultMode, modelContext: modelContext)
                }
            }
            .navigationDestination(item: $viewModel.showDetailWord) { word in
                WordDetailView(word: word)
            }
        }
    }

    private func modeButton(_ mode: SegmentationMode) -> some View {
        Button {
            select(mode)
        } label: {
            Label(
                mode.label,
                systemImage: activeMode == mode ? "checkmark" : mode.systemImage
            )
        }
    }

    private func select(_ mode: SegmentationMode) {
        guard mode != activeMode else { return }
        // Remembering ChatGPT would mean the next photo silently costs money.
        if mode != .openAI {
            defaultMode = mode
        }
        Task {
            await viewModel.resegment(using: mode, modelContext: modelContext)
        }
    }

    private var home: some View {
        List {
            Section {
                actionCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                if records.isEmpty {
                    Text("아직 인식한 사진이 없어요.")
                        .font(KYFont.callout())
                        .foregroundStyle(KYColor.textSecondary)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(records) { record in
                        historyRow(record)
                            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(record)
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("인식 기록")
                        .font(KYFont.headline())
                        .foregroundStyle(KYColor.textPrimary)
                    Spacer()
                    if !records.isEmpty {
                        Text("\(records.count)개")
                            .font(KYFont.caption())
                            .foregroundStyle(KYColor.textSecondary)
                    }
                }
                .textCase(nil)
                .padding(.horizontal, 20)
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var actionCard: some View {
        KYCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("사진으로 인식", systemImage: "text.viewfinder")
                    .font(KYFont.headline())
                    .foregroundStyle(KYColor.textPrimary)
                Text("카메라로 찍거나 앨범에서 올리면 온디바이스로 일본어를 분석합니다.")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)

                KYPrimaryButton("카메라로 촬영", systemImage: "camera.fill") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        showLibrary = true
                    }
                }
                KYSecondaryButton("앨범에서 선택", systemImage: "photo.on.rectangle") {
                    showLibrary = true
                }
            }
        }
    }

    private func historyRow(_ record: ScanRecord) -> some View {
        Button {
            viewModel.load(record, modelContext: modelContext)
        } label: {
            KYCard {
                HStack(spacing: 14) {
                    if let thumbnail = record.image {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.previewText.isEmpty ? "단어 \(record.wordCount)개" : record.previewText)
                            .font(KYFont.body())
                            .foregroundStyle(KYColor.textPrimary)
                            .lineLimit(1)
                        Text(Self.dateFormatter.string(from: record.createdAt))
                            .font(KYFont.caption())
                            .foregroundStyle(KYColor.textSecondary)
                    }

                    Spacer(minLength: 8)

                    Text("\(record.wordCount)")
                        .font(KYFont.caption())
                        .foregroundStyle(KYColor.primary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 a h:mm"
        return formatter
    }()

    private func delete(_ record: ScanRecord) {
        modelContext.delete(record)
        try? modelContext.save()
    }
}
