//
//  ScanView.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI
import UIKit

struct ScanView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ScanViewModel()
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickedImage: UIImage?

    var body: some View {
        NavigationStack {
            // The scroll view must be the direct content so the large title
            // collapses as the user scrolls.
            Group {
                if viewModel.image != nil {
                    ScanResultView(viewModel: viewModel)
                } else {
                    emptyState
                }
            }
            .background(KYColor.background)
            .overlay {
                if viewModel.isProcessing {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        KYLoadingOverlay(message: "일본어를 읽고 있어요")
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
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("다시") {
                            viewModel.reset()
                            pickedImage = nil
                        }
                        .font(KYFont.callout())
                        .foregroundStyle(KYColor.primary)
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
            .onChange(of: pickedImage) { _, newValue in
                guard let newValue else { return }
                viewModel.image = newValue
                Task {
                    await viewModel.process(modelContext: modelContext)
                }
            }
            .navigationDestination(item: $viewModel.showDetailWord) { word in
                WordDetailView(word: word)
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Kanjiyomi")
                        .font(KYFont.largeTitle())
                        .foregroundStyle(KYColor.textPrimary)
                    Text("전단지·간판 속 일본어를 단어로 나눠\n뜻과 한글 발음을 바로 보여줘요.")
                        .font(KYFont.callout())
                        .foregroundStyle(KYColor.textSecondary)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)

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
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}
