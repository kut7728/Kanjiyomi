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
    var createdAt: Date

    init(
        id: UUID = UUID(),
        imageData: Data,
        wordsData: Data,
        wordCount: Int,
        previewText: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.imageData = imageData
        self.wordsData = wordsData
        self.wordCount = wordCount
        self.previewText = previewText
        self.createdAt = createdAt
    }

    convenience init?(image: UIImage, words: [RecognizedWord]) {
        guard let imageData = image.storageJPEGData() else { return nil }
        let encoded = (try? JSONEncoder().encode(words)) ?? Data()
        self.init(
            imageData: imageData,
            wordsData: encoded,
            wordCount: words.count,
            previewText: Self.preview(for: words)
        )
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
