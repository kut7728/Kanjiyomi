//
//  ContentView.swift
//  Kanjiyomi
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        tabs
            .tint(KYColor.primary)
            // The palette is a fixed light theme, so dark mode would render titles white on light gray.
            .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26.0, *) {
            tabContent.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabContent
        }
    }

    private var tabContent: some View {
        TabView {
            Tab("스캔", systemImage: "text.viewfinder") {
                ScanView()
            }

            Tab("단어장", systemImage: "bookmark.fill") {
                VocabularyView()
            }

            Tab("퀴즈", systemImage: "checkmark.circle.fill") {
                QuizView()
            }

            // The search role pins this tab to the trailing edge of the tab bar.
            Tab(role: .search) {
                DictionarySearchView()
            }
        }
    }
}

#Preview {
    ContentView()
}
