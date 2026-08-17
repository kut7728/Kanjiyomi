//
//  ContentView.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    /// Held here rather than inside the scan screen so the tab bar accessory, which is
    /// attached to this tab view, can read and act on the pending save.
    @State private var scanViewModel = ScanViewModel()
    @State private var scanRouter = ScanRouter()
    @State private var selection: TabID = .scan
    @State private var confirmingSave = false

    private enum TabID: Hashable {
        case scan, vocabulary, quiz, settings
    }

    var body: some View {
        tabs
            .tint(KYColor.primary)
            // The palette is a fixed light theme, so dark mode would render titles white on
            // light gray.
            .preferredColorScheme(.light)
            .environment(scanRouter)
            .onChange(of: scanRouter.request) { _, request in
                if let request { reveal(request) }
            }
            // The accessory has room for a label and a button but not for what saving does,
            // unlike the bar inside the scan panel, so that explanation lands here.
            .confirmationDialog(
                "인식된 단어를 단어장에 저장할까요?",
                isPresented: $confirmingSave,
                titleVisibility: .visible
            ) {
                Button("저장") {
                    scanViewModel.saveToVocabulary(modelContext: modelContext)
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text(scanViewModel.saveHint)
            }
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26.0, *) {
            modernTabs(tabContent)
        } else {
            tabContent
        }
    }

    /// `isEnabled` keeps one tab view identity across the prompt appearing and disappearing.
    /// Attaching the modifier conditionally instead would rebuild the whole tab bar each
    /// time, taking the scan screen's scroll and sheet state with it, so that path is only
    /// used on 26.0, where the parameter does not exist yet.
    @available(iOS 26.0, *)
    @ViewBuilder
    private func modernTabs(_ content: some View) -> some View {
        if #available(iOS 26.1, *) {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory(isEnabled: showsSavePrompt) {
                    SaveVocabularyAccessory { confirmingSave = true }
                }
        } else if showsSavePrompt {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    SaveVocabularyAccessory { confirmingSave = true }
                }
        } else {
            content.tabBarMinimizeBehavior(.onScrollDown)
        }
    }

    /// Not restricted to the scan tab. An unsaved pass is thrown away by the next scan, and a
    /// ChatGPT one was paid for, so the chance to keep it should follow the user rather than
    /// disappear the moment they look at something else.
    private var showsSavePrompt: Bool {
        scanViewModel.hasUnsavedWords
    }

    private var tabContent: some View {
        TabView(selection: $selection) {
            Tab("스캔", systemImage: "text.viewfinder", value: TabID.scan) {
                ScanView(viewModel: scanViewModel)
            }

            Tab("단어장", systemImage: "bookmark.fill", value: TabID.vocabulary) {
                VocabularyView()
            }

            Tab("퀴즈", systemImage: "checkmark.circle.fill", value: TabID.quiz) {
                QuizView()
            }

            Tab("설정", systemImage: "gearshape.fill", value: TabID.settings) {
                SettingsView()
            }
        }
    }

    /// A word detail can be opened from any tab, so the way back to the photo it came from is
    /// walked here, where both the tab selection and the shared scan view model are in reach.
    private func reveal(_ request: ScanRouter.Request) {
        scanRouter.clear()
        guard let record = scanRouter.record(request.recordID, modelContext: modelContext) else {
            return
        }
        selection = .scan
        scanViewModel.load(record, modelContext: modelContext)
        guard let word = scanViewModel.words.first(where: {
            WordCache.makeKey(surface: $0.surface, lemma: $0.lemma) == request.wordKey
        }) else { return }
        scanViewModel.select(word)
    }
}

@available(iOS 26.0, *)
private struct SaveVocabularyAccessory: View {
    let save: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bookmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KYColor.primary)
            Text("단어장에 저장 전")
                .font(KYFont.callout())
                .foregroundStyle(KYColor.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("저장", action: save)
                .font(KYFont.callout())
                .buttonStyle(.borderedProminent)
                .tint(KYColor.primary)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    ContentView()
}
