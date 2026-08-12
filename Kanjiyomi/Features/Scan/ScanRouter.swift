//
//  ScanRouter.swift
//  Kanjiyomi
//

import Foundation
import SwiftData

/// Carries a request to reopen a stored scan from wherever a word detail happens to be open
/// to the tab view, which is the only place that can both switch tabs and reach the shared
/// scan view model.
@MainActor
@Observable
final class ScanRouter {
    /// The word is named by its cache key rather than by `RecognizedWord.id`, which is minted
    /// again every time the word is rebuilt and so never matches the one inside the scan.
    struct Request: Equatable {
        let recordID: UUID
        let wordKey: String
    }

    private(set) var request: Request?

    func reveal(recordID: UUID, wordKey: String) {
        request = Request(recordID: recordID, wordKey: wordKey)
    }

    func clear() {
        request = nil
    }

    /// Nil once the scan has been deleted from the history. A saved word keeps its link to a
    /// scan that no longer exists, so every use of that link has to look the record up.
    func record(_ id: UUID, modelContext: ModelContext) -> ScanRecord? {
        var descriptor = FetchDescriptor<ScanRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
