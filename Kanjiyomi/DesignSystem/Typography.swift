//
//  Typography.swift
//  Kanjiyomi
//

import SwiftUI

enum KYFont {
    static func largeTitle() -> Font { .system(size: 28, weight: .bold) }
    static func title() -> Font { .system(size: 22, weight: .bold) }
    static func headline() -> Font { .system(size: 18, weight: .bold) }
    static func body() -> Font { .system(size: 16, weight: .semibold) }
    static func callout() -> Font { .system(size: 15, weight: .medium) }
    static func caption() -> Font { .system(size: 13, weight: .medium) }
    static func kanji() -> Font { .system(size: 40, weight: .bold) }
}
