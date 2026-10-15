//
//  LicensesView.swift
//  Kanjiyomi
//

import SwiftUI

/// Credits for the dictionary data bundled with the app. JMdict and KANJIDIC2 are licensed
/// CC BY-SA 4.0, which asks for attribution wherever the data is shipped.
struct LicensesView: View {
    private struct Credit: Identifiable {
        let name: String
        let holder: String
        let license: String
        let usage: String
        let url: URL

        var id: String { name }
    }

    private let credits = [
        Credit(
            name: "JMdict",
            holder: "© Electronic Dictionary Research and Development Group",
            license: "CC BY-SA 4.0",
            usage: "단어의 읽기, 품사, 영어 뜻",
            url: URL(string: "https://www.edrdg.org/edrdg/licence.html")!
        ),
        Credit(
            name: "KANJIDIC2",
            holder: "© Electronic Dictionary Research and Development Group",
            license: "CC BY-SA 4.0",
            usage: "한자의 음독·훈독",
            url: URL(string: "https://www.edrdg.org/edrdg/licence.html")!
        ),
        Credit(
            name: "한국어기초사전",
            holder: "© 국립국어원",
            license: "CC BY-SA 2.0 KR",
            usage: "일본어 대역어를 연결한 한국어 뜻 (일부 항목)",
            url: URL(string: "https://krdict.korean.go.kr/kor/kboardPolicy/copyRightTermsInfo")!
        ),
        Credit(
            name: "한국어 위키낱말사전 · Kaikki",
            holder: "© 위키낱말사전 기여자",
            license: "CC BY-SA 4.0",
            usage: "일본어 항목의 한국어 뜻 (일부 항목)",
            url: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
        ),
        Credit(
            name: "Unihan Database",
            holder: "© Unicode, Inc.",
            license: "Unicode License",
            usage: "한자의 한국 한자음",
            url: URL(string: "https://www.unicode.org/license.txt")!
        )
    ]

    var body: some View {
        List {
            Section {
                ForEach(credits) { credit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(credit.name)
                            .font(KYFont.callout())
                            .foregroundStyle(KYColor.textPrimary)
                        Text(credit.usage)
                            .font(KYFont.caption())
                            .foregroundStyle(KYColor.textSecondary)
                        Text(credit.holder)
                            .font(KYFont.caption())
                            .foregroundStyle(KYColor.textSecondary)
                        Link(credit.license, destination: credit.url)
                            .font(KYFont.caption())
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("사전 데이터")
            } footer: {
                Text("앱에 들어 있는 사전은 위 데이터를 가공해 만들었으며, 같은 라이선스를 따릅니다.")
            }
            .listRowBackground(KYColor.card)
            Section {
                Link("한국어 사전 데이터 · 항목별 원문 출처", destination: URL(string: "https://github.com/kut7728/Kanjiyomi/blob/main/Kanjiyomi/Resources/korean.sqlite")!)
                Text("일본어 표기와 읽기를 연결하고 중복·불확실한 뜻을 제외했습니다. 원본 항목의 주소, 출처별 라이선스와 가공 정보는 데이터 파일에 들어 있습니다.")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
            }
            .listRowBackground(KYColor.card)
        }
        .scrollContentBackground(.hidden)
        .background(KYColor.background)
        .navigationTitle("오픈소스·라이선스")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LicensesView()
    }
}
