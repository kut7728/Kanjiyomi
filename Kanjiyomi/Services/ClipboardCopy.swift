//
//  ClipboardCopy.swift
//  Kanjiyomi
//

import UIKit

enum ClipboardCopy {
    static func copy(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIPasteboard.general.string = trimmed
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
