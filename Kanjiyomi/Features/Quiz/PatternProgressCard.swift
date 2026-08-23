//
//  PatternProgressCard.swift
//  Kanjiyomi
//

import SwiftUI

struct PatternProgressCard: View {
    let count: Int

    var body: some View {
        KYCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("익힌 읽기 패턴")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
                Text("\(count)개")
                    .font(KYFont.title())
                    .foregroundStyle(KYColor.primary)
                Text("한자를 하나씩 외우기보다, 단어에서 반복되는 읽기를 모으고 있습니다.")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
            }
        }
    }
}
