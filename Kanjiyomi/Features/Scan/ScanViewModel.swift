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

    /// The part of the photo the user drew around, or nil for the whole thing. A photo of a
    /// page turns up every word on it, most of which belong to a sentence the reader is not
    /// working on, so narrowing the picture is how they narrow the list.
    private(set) var region: SelectionRegion?
    var isSelectingRegion = false

    /// Which way the words on screen were produced. Drives both the meaning generator and
    /// what saving has to write.
    private(set) var activeMode: SegmentationMode = .dictionary

    /// The words the screen is showing. A region drops the words found outside it, and keeps
    /// the rest only through the places they were found inside it, so the list, the count and
    /// the highlights on the photo all describe the same selection.
    var displayWords: [RecognizedWord] {
        guard let region else { return words }
        return words.compactMap { word in
            let inside = word.quads.filter(region.covers)
            guard !inside.isEmpty else { return nil }
            var trimmed = word
            trimmed.quads = inside
            return trimmed
        }
    }

    /// Derived rather than stored. A stored flag has to be set by whichever code path
    /// happens to finish last, and a cancelled generation task never reaches that line,
    /// which left results on screen with no way to keep them.
    var hasUnsavedWords: Bool {
        !savedCurrentPass
            && !isProcessing
            && !isGeneratingMeanings
            && displayWords.contains { !$0.meaningKO.isEmpty }
    }

    /// What saving is about to do, beyond adding the words. A ChatGPT pass also replaces
    /// the meanings the cache already holds for these words.
    var saveHint: String {
        let base = activeMode == .openAI
            ? "ChatGPT가 만든 뜻으로 기존에 저장된 뜻을 덮어씁니다"
            : "이미 단어장에 있는 단어는 그대로 둡니다"
        // Saving what is on screen rather than everything the photo turned up is worth saying
        // outright, since the words a region hid are still there to be saved later.
        guard region != nil else { return base }
        return "선택한 영역의 \(displayWords.count)개만 저장합니다 · \(base)"
    }

    private var savedCurrentPass = false

    /// Where the save prompt is shown. The tab bar accessory keeps it visible no matter how
    /// far the word list is scrolled, but it only exists on iOS 26, so older systems fall
    /// back to a bar inside the panel.
    static var showsSaveInTabBar: Bool {
        if #available(iOS 26.0, *) { true } else { false }
    }

    @ObservationIgnored private var meaningTask: Task<Void, Never>?
    @ObservationIgnored private var currentRecord: ScanRecord?

    /// Read from the displayed words so a highlight only ever points at a place inside the
    /// region, even for a word that also appears outside it.
    var selectedWord: RecognizedWord? {
        guard let selectedWordID else { return nil }
        return displayWords.first { $0.id == selectedWordID }
    }

    /// Offered only once a scan is on screen, and only when there is another way to split.
    var canChooseSegmentation: Bool {
        image != nil && !isProcessing && SegmentationMode.available.count > 1
    }

    /// Nothing to narrow down until there are words on the photo.
    var canSelectRegion: Bool {
        image != nil && !isProcessing && !words.isEmpty
    }

    /// Narrows the screen to the part of the photo the user drew around, or reopens the whole
    /// photo when passed nil.
    func applyRegion(_ region: SelectionRegion?) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            self.region = region
            // The selected word may have been outside what was just drawn, which would leave
            // the photo magnified on a highlight no row in the list accounts for.
            if let selectedWordID, !displayWords.contains(where: { $0.id == selectedWordID }) {
                self.selectedWordID = nil
            }
        }
        // A different set of words on screen is a different thing to save, so the offer comes
        // back rather than being spent on whichever selection was saved first.
        savedCurrentPass = false
    }

    /// Reads the same photo again with a different way of deciding word boundaries.
    func resegment(using mode: SegmentationMode, modelContext: ModelContext) async {
        guard let image, !isProcessing else { return }

        meaningTask?.cancel()
        isProcessing = true
        errorMessage = nil
        selectedWordID = nil
        showDetailWord = nil
        // The region is deliberately left alone: it marks a place on the photo rather than a
        // set of words, and this reads the same photo again.
        activeMode = mode.resolved
        savedCurrentPass = false

        let rescanned: [RecognizedWord]
        do {
            rescanned = try await ScanPipeline.recognize(
                image: image,
                mode: mode,
                modelContext: modelContext
            ) { message in
                statusMessage = message
            }
        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
            return
        }
        isProcessing = false
        // A failed remote split still produces words from the dictionary fallback, so the
        // reason has to be shown separately or it looks like nothing happened.
        errorMessage = OpenAIService.shared.lastErrorMessage

        // Keeping the previous list beats replacing it with nothing.
        guard !rescanned.isEmpty else {
            errorMessage = "다시 인식한 단어가 없어요. 기존 결과를 그대로 둘게요."
            return
        }

        words = rescanned
        currentRecord?.update(words: words)
        currentRecord?.segmentation = activeMode
        currentRecord?.meaningsSaved = false
        // A different split finds different words, so this pass gets its own offer to be
        // saved.
        currentRecord?.vocabularyAdded = false
        try? modelContext.save()
        startMeaningGeneration(modelContext: modelContext)
    }

    func process(mode: SegmentationMode, modelContext: ModelContext) async {
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
        region = nil
        activeMode = mode.resolved
        savedCurrentPass = false

        // Loading the model now overlaps its cold start with OCR.
        MeaningService.shared.prewarm()

        do {
            words = try await ScanPipeline.recognize(
                image: image,
                mode: mode,
                modelContext: modelContext
            ) { message in
                statusMessage = message
            }
        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
            return
        }
        isProcessing = false
        errorMessage = OpenAIService.shared.lastErrorMessage

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
        region = nil
        errorMessage = nil
        showDetailWord = nil
        // The cancel above leaves this set if a previous scan was still generating, which
        // would suppress the save offer this scan is entitled to.
        isGeneratingMeanings = false
        activeMode = record.segmentation
        savedCurrentPass = record.vocabularyAdded

        // Reopening must never spend the user's money on its own. A ChatGPT scan is shown
        // exactly as it was stored, and its save offer comes back with it.
        guard activeMode != .openAI else { return }
        // A scan left before generation finished still has words without a Korean meaning.
        startMeaningGeneration(modelContext: modelContext)
    }

    /// Files the scan into the vocabulary, and returns how many words were new to the list.
    ///
    /// Nothing a scan reads reaches the vocabulary before this runs. A photo turns up plenty
    /// of words the user has no reason to study, so which scans are worth keeping is theirs
    /// to decide rather than a consequence of pointing the camera at something.
    @discardableResult
    func saveToVocabulary(modelContext: ModelContext) -> Int {
        // A ChatGPT pass lives only in memory until now, so keeping its words has to keep
        // the meanings they are being saved with. The cache takes the whole pass either way:
        // a region decides what to study, not which meanings were worth paying for.
        if activeMode == .openAI {
            MeaningService.shared.persistOpenAIMeanings(words, modelContext: modelContext)
            currentRecord?.meaningsSaved = true
        }
        let added = VocabularyStore.absorb(
            displayWords,
            from: currentRecord?.id,
            modelContext: modelContext
        )
        currentRecord?.update(words: words)
        currentRecord?.vocabularyAdded = true
        try? modelContext.save()
        savedCurrentPass = true
        return added
    }

    /// Runs alongside the visible list, replacing it batch by batch as meanings come back.
    private func startMeaningGeneration(modelContext: ModelContext) {
        let mode = activeMode
        let canGenerate = mode == .openAI
            ? OpenAIService.shared.isConfigured
            : MeaningService.shared.isGenerationAvailable
        // Nothing left to generate, so the dictionary pass is already the final answer and
        // the save offer stands as it is.
        guard canGenerate, words.contains(where: \.needsGeneration) else { return }

        let snapshot = words
        isGeneratingMeanings = true
        meaningTask = Task { [weak self] in
            await ScanPipeline.fillMeanings(
                snapshot,
                mode: mode,
                modelContext: modelContext
            ) { updated in
                self?.applyMeanings(updated)
            }
            guard let self, !Task.isCancelled else { return }
            self.isGeneratingMeanings = false
            // Generation runs after recognition has already reported its result, so a
            // failure here has no other way to reach the screen.
            if mode == .openAI, let message = OpenAIService.shared.lastErrorMessage {
                self.errorMessage = message
            }
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
        guard let record = ScanRecord(
            image: image,
            words: words,
            segmentation: activeMode
        ) else { return nil }
        modelContext.insert(record)
        try? modelContext.save()
        return record
    }

    /// Tapping the word already selected drops the selection, which is the only way back to
    /// the whole photo.
    func select(_ word: RecognizedWord) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            selectedWordID = selectedWordID == word.id ? nil : word.id
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
        region = nil
        isSelectingRegion = false
        errorMessage = nil
        showDetailWord = nil
        activeMode = .dictionary
        savedCurrentPass = false
    }
}
