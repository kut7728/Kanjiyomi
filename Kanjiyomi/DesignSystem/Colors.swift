//
//  Colors.swift
//  Kanjiyomi
//

import SwiftUI

enum KYColor {
    static let background = Color(hex: 0xF2F4F6)
    static let card = Color.white
    static let primary = Color(hex: 0x3182F6)
    static let textPrimary = Color(hex: 0x191F28)
    static let textSecondary = Color(hex: 0x8B95A1)
    static let highlight = Color(hex: 0x3182F6).opacity(0.28)
    static let highlightBorder = Color(hex: 0x3182F6)
    static let danger = Color(hex: 0xF04452)
    static let success = Color(hex: 0x03B26C)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
