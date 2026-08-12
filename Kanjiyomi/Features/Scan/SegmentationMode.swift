//
//  SegmentationMode.swift
//  Kanjiyomi
//

import Foundation

/// How a recognized line is broken into words.
enum SegmentationMode: String, CaseIterable, Identifiable, Sendable {
    /// NLTokenizer pieces rejoined into the longest form JMdict confirms. Fast and offline,
    /// but it can only end a word where the dictionary already has an entry.
    case dictionary
    /// The on-device language model reads the line and decides. Slower, and the only way to
    /// surface a proper noun or a compound the dictionary has never listed.
    case model
    /// Splitting and meanings both sent to the user's own OpenAI account. The only mode that
    /// leaves the device, and the only one that costs the user money.
    case openAI

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dictionary: "사전으로 나누기"
        case .model: "AI로 나누기"
        case .openAI: "ChatGPT로 단어와 뜻 만들기"
        }
    }

    var systemImage: String {
        switch self {
        case .dictionary: "character.book.closed"
        case .model: "sparkles"
        case .openAI: "cloud"
        }
    }

    var progressMessage: String {
        switch self {
        case .dictionary: "사진에서 글자를 찾고 있어요"
        case .model: "AI가 단어를 나누고 있어요"
        case .openAI: "ChatGPT가 단어를 나누고 있어요"
        }
    }

    /// A mode the device cannot run is not offered, and a stored preference for one falls
    /// back rather than failing the scan.
    @MainActor
    var isAvailable: Bool {
        switch self {
        case .dictionary: true
        case .model: MeaningService.shared.isGenerationAvailable
        case .openAI: OpenAIService.shared.isConfigured
        }
    }

    @MainActor
    static var available: [SegmentationMode] {
        allCases.filter(\.isAvailable)
    }

    @MainActor
    var resolved: SegmentationMode {
        isAvailable ? self : .dictionary
    }
}
