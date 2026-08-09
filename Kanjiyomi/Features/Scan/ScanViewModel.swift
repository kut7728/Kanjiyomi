//
//  ScanViewModel.swift
//  Kanjiyomi
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

@MainActor
@Observable
final class ScanViewModel {
    var image: UIImage?
    var words: [RecognizedWord] = []
    var isProcessing = false
    var statusMessage = "사진을 준비하고 있어요"
    var errorMessage: String?
    var selectedWordID: RecognizedWord.ID?
    var showDetailWord: RecognizedWord?

    var selectedWord: RecognizedWord? {
        guard let selectedWordID else { return nil }
        return words.first { $0.id == selectedWordID }
    }

    func process(modelContext: ModelContext) async {
        guard let original = image else { return }
        // OCR reads the raw pixel buffer, so bake EXIF orientation in before analyzing
        // and display the same image to keep highlight coordinates aligned.
        let image = original.normalizedUp()
        self.image = image
        isProcessing = true
        statusMessage = "사진을 준비하고 있어요"
        errorMessage = nil
        words = []
        selectedWordID = nil
        defer { isProcessing = false }

        do {
            words = try await ScanPipeline.process(image: image, modelContext: modelContext) { message in
                statusMessage = message
            }
            if words.isEmpty {
                errorMessage = "인식된 일본어 단어가 없습니다. 다른 사진을 시도해 보세요."
            } else {
                saveRecord(image: image, modelContext: modelContext)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func load(_ record: ScanRecord) {
        image = record.image
        words = record.words
        selectedWordID = nil
        errorMessage = nil
        showDetailWord = nil
    }

    private func saveRecord(image: UIImage, modelContext: ModelContext) {
        guard let record = ScanRecord(image: image, words: words) else { return }
        modelContext.insert(record)
        try? modelContext.save()
    }

    func select(_ word: RecognizedWord) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            selectedWordID = word.id
        }
    }

    func reset() {
        image = nil
        words = []
        selectedWordID = nil
        errorMessage = nil
        showDetailWord = nil
    }
}
