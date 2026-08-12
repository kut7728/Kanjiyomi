//
//  ContentView.swift
//  Kanjiyomi
//

import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    /// Held here rather than inside the scan screen so the tab bar accessory, which is
    /// attached to this tab view, can read and act on the pending save.
    @State private var scanViewModel = ScanViewModel()
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
            .confirmationDialog(
                "ChatGPT가 만든 뜻을 저장할까요?",
                isPresented: $confirmingSave,
                titleVisibility: .visible
            ) {
                Button("저장") {
                    scanViewModel.saveOpenAIMeanings(modelContext: modelContext)
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("이 단어들에 이미 저장된 뜻이 있으면 덮어씁니다.")
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
                    SaveMeaningsAccessory { confirmingSave = true }
                }
        } else if showsSavePrompt {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    SaveMeaningsAccessory { confirmingSave = true }
                }
        } else {
            content.tabBarMinimizeBehavior(.onScrollDown)
        }
    }

    /// Not restricted to the scan tab. An unsaved ChatGPT pass was paid for and is thrown
    /// away by the next scan, so the chance to keep it should follow the user rather than
    /// disappear the moment they look at something else.
    private var showsSavePrompt: Bool {
        scanViewModel.hasUnsavedOpenAIMeanings
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
}

@available(iOS 26.0, *)
private struct SaveMeaningsAccessory: View {
    let save: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KYColor.primary)
            Text("ChatGPT 결과 저장 전")
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
