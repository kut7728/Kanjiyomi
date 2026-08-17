//
//  ScanRecord.swift
//  Kanjiyomi
//

import Foundation
import SwiftData
import UIKit

@Model
final class ScanRecord {
    @Attribute(.unique) var id: UUID
    /// Kept out of the main store file so the database stays small.
    @Attribute(.externalStorage) var imageData: Data
    var wordsData: Data
    var wordCount: Int
    var previewText: String
    /// How these words were split, so reopening the scan describes what is on screen rather
    /// than whatever the picker happens to default to.
    var segmentationRaw: String = SegmentationMode.dictionary.rawValue
    /// Whether a ChatGPT pass in this scan was written to the word cache. Kept with the scan
    /// so the offer to save it survives leaving the screen.
    var meaningsSaved: Bool = false
    /// Whether the user has filed these words into the vocabulary. Kept with the scan so the
    /// offer to save survives leaving the screen, and so reopening a saved scan cannot bring
    /// back words the user has since deleted from their list.
    var vocabularyAdded: Bool = false
    var createdAt: Date

    init(
        id: UUID = UUID(),
        imageData: Data,
        wordsData: Data,
        wordCount: Int,
        previewText: String,
        segmentation: SegmentationMode = .dictionary,
        meaningsSaved: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.imageData = imageData
        self.wordsData = wordsData
        self.wordCount = wordCount
        self.previewText = previewText
        self.segmentationRaw = segmentation.rawValue
        self.meaningsSaved = meaningsSaved
        self.createdAt = createdAt
    }

    convenience init?(image: UIImage, words: [RecognizedWord], segmentation: SegmentationMode) {
        guard let imageData = image.storageJPEGData() else { return nil }
        let encoded = (try? JSONEncoder().encode(words)) ?? Data()
        self.init(
            imageData: imageData,
            wordsData: encoded,
            wordCount: words.count,
            previewText: Self.preview(for: words),
            segmentation: segmentation
        )
    }

    var segmentation: SegmentationMode {
        get { SegmentationMode(rawValue: segmentationRaw) ?? .dictionary }
        set { segmentationRaw = newValue.rawValue }
    }

    /// Meanings are generated after the record is first written, so the stored words
    /// are refreshed once generation finishes.
    func update(words: [RecognizedWord]) {
        guard let encoded = try? JSONEncoder().encode(words) else { return }
        wordsData = encoded
        wordCount = words.count
        previewText = Self.preview(for: words)
    }

    private static func preview(for words: [RecognizedWord]) -> String {
        words.prefix(4).map(\.displayHeadword).joined(separator: " · ")
    }

    var words: [RecognizedWord] {
        (try? JSONDecoder().decode([RecognizedWord].self, from: wordsData)) ?? []
    }

    var image: UIImage? {
        UIImage(data: imageData)
    }
}
