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
    /// Recognition is done and the list is on screen while meanings are still arriving.
    var isGeneratingMeanings = false
    var statusMessage = "사진을 준비하고 있어요"
    var errorMessage: String?
    var selectedWordID: RecognizedWord.ID?
    var showDetailWord: RecognizedWord?

    @ObservationIgnored private var meaningTask: Task<Void, Never>?
    @ObservationIgnored private var currentRecord: ScanRecord?

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

        meaningTask?.cancel()
        currentRecord = nil
        isProcessing = true
        statusMessage = "사진을 준비하고 있어요"
        errorMessage = nil
        words = []
        selectedWordID = nil

        // Loading the model now overlaps its cold start with OCR.
        MeaningService.shared.prewarm()

        do {
            words = try await ScanPipeline.recognize(image: image, modelContext: modelContext) { message in
                statusMessage = message
            }
        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
            return
        }
        isProcessing = false

        guard !words.isEmpty else {
            errorMessage = "인식된 일본어 단어가 없습니다. 다른 사진을 시도해 보세요."
            return
        }

        currentRecord = saveRecord(image: image, modelContext: modelContext)
        startMeaningGeneration(modelContext: modelContext)
    }

    func load(_ record: ScanRecord, modelContext: ModelContext) {
        meaningTask?.cancel()
        image = record.image
        words = record.words
        currentRecord = record
        selectedWordID = nil
        errorMessage = nil
        showDetailWord = nil
        // A scan left before generation finished still has words without a Korean meaning.
        startMeaningGeneration(modelContext: modelContext)
    }

    /// Runs alongside the visible list, replacing it batch by batch as meanings come back.
    private func startMeaningGeneration(modelContext: ModelContext) {
        guard MeaningService.shared.isGenerationAvailable,
              words.contains(where: { $0.meaningKO.isEmpty }) else { return }

        let snapshot = words
        isGeneratingMeanings = true
        meaningTask = Task { [weak self] in
            await ScanPipeline.fillMeanings(snapshot, modelContext: modelContext) { updated in
                self?.applyMeanings(updated)
            }
            guard let self, !Task.isCancelled else { return }
            self.isGeneratingMeanings = false
            self.currentRecord?.update(words: self.words)
            try? modelContext.save()
        }
    }

    private func applyMeanings(_ updated: [RecognizedWord]) {
        // The scan may have been replaced while the model was working.
        guard updated.count == words.count, updated.first?.id == words.first?.id else { return }
        words = updated
    }

    private func saveRecord(image: UIImage, modelContext: ModelContext) -> ScanRecord? {
        guard let record = ScanRecord(image: image, words: words) else { return nil }
        modelContext.insert(record)
        try? modelContext.save()
        return record
    }

    func select(_ word: RecognizedWord) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            selectedWordID = word.id
        }
    }

    func reset() {
        meaningTask?.cancel()
        meaningTask = nil
        currentRecord = nil
        image = nil
        words = []
        isGeneratingMeanings = false
        selectedWordID = nil
        errorMessage = nil
        showDetailWord = nil
    }
}
