//
//  VocabularyView.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI

struct VocabularyView: View {
    @Query(sort: \VocabWord.createdAt, order: .reverse) private var words: [VocabWord]
    @Environment(\.modelContext) private var modelContext

    @State private var selection = Set<VocabWord.ID>()
    @State private var editMode: EditMode = .inactive
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .background(KYColor.background)
            .navigationTitle(title)
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !words.isEmpty { selectButton }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isEditing {
                        selectAllButton
                        deleteButton
                    } else {
                        searchLink
                    }
                }
            }
            // Scanning in the background can empty the list out from under edit mode.
            .onChange(of: words.isEmpty) { _, isEmpty in
                if isEmpty { endEditing() }
            }
            .confirmationDialog(
                "\(selection.count)개 단어를 삭제할까요?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("삭제", role: .destructive, action: deleteSelected)
                Button("취소", role: .cancel) {}
            }
        }
    }

    private var isEditing: Bool { editMode.isEditing }

    private var title: String {
        guard isEditing else { return "단어장" }
        return selection.isEmpty ? "항목 선택" : "\(selection.count)개 선택됨"
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(words) { word in
                NavigationLink {
                    WordDetailView(word: word.toRecognizedWord())
                } label: {
                    row(for: word)
                }
                .listRowBackground(KYColor.card)
            }
            .onDelete(perform: delete)
        }
        .scrollContentBackground(.hidden)
        .listRowSpacing(10)
    }

    private func row(for word: VocabWord) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.displayHeadword)
                    .font(KYFont.headline())
                    .foregroundStyle(KYColor.textPrimary)
                if !word.hangul.isEmpty {
                    Text(word.hangul)
                        .font(KYFont.caption())
                        .foregroundStyle(KYColor.primary)
                }
            }
            Spacer()
            Text(word.displayMeaning)
                .font(KYFont.callout())
                .foregroundStyle(KYColor.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Toolbar

    /// Driven by hand rather than by `EditButton`, which reads the edit mode from the
    /// environment the toolbar does not share with the list.
    private var selectButton: some View {
        Button(isEditing ? "완료" : "선택") {
            withAnimation {
                if isEditing {
                    endEditing()
                } else {
                    editMode = .active
                }
            }
        }
        .foregroundStyle(KYColor.primary)
    }

    private var selectAllButton: some View {
        Button(selection.count == words.count ? "전체 해제" : "전체 선택") {
            selection = selection.count == words.count ? [] : Set(words.map(\.id))
        }
        .foregroundStyle(KYColor.primary)
    }

    private var deleteButton: some View {
        Button("삭제", role: .destructive) {
            confirmingDelete = true
        }
        .disabled(selection.isEmpty)
    }

    private var searchLink: some View {
        NavigationLink {
            DictionarySearchView()
        } label: {
            Label("사전 검색", systemImage: "magnifyingglass")
        }
        .foregroundStyle(KYColor.primary)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(KYColor.primary)
            Text("아직 저장한 단어가 없어요")
                .font(KYFont.headline())
                .foregroundStyle(KYColor.textPrimary)
            Text("사진을 스캔하면 인식된 단어가 여기에 담겨요.")
                .font(KYFont.callout())
                .foregroundStyle(KYColor.textSecondary)
        }
        .padding(40)
    }

    // MARK: - Actions

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(words[index])
        }
        try? modelContext.save()
    }

    private func deleteSelected() {
        for word in words where selection.contains(word.id) {
            modelContext.delete(word)
        }
        try? modelContext.save()
        endEditing()
    }

    private func endEditing() {
        selection.removeAll()
        editMode = .inactive
    }
}
