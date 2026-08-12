// Checks the reading salvage rules in MeaningService against the answers the on-device
// model actually gives back. Run with: swift tools/reading_probe.swift

import Foundation

func isKana(_ scalar: Unicode.Scalar) -> Bool {
    let v = scalar.value
    return (0x3040...0x309F).contains(v)
        || (0x30A0...0x30FF).contains(v)
        || v == 0x30FC
}

func kanaRuns(in text: String) -> [String] {
    var runs: [String] = []
    var run = ""
    for scalar in text.unicodeScalars {
        if isKana(scalar) {
            run.unicodeScalars.append(scalar)
            continue
        }
        if !run.isEmpty { runs.append(run) }
        run = ""
    }
    if !run.isEmpty { runs.append(run) }
    return runs
}

func isPlausibleReading(_ kana: String, for word: String) -> Bool {
    guard !kana.isEmpty, kana != word else { return false }
    return !word.contains(kana) || kana.count >= word.count
}

func acceptedReading(_ raw: String, for word: String) -> String {
    kanaRuns(in: raw).first { isPlausibleReading($0, for: word) } ?? ""
}

let cases: [(raw: String, word: String, expected: String)] = [
    ("ごりよう", "ご利用", "ごりよう"),
    ("ご利用（ごりよう）", "ご利用", "ごりよう"),
    ("ごりよう (goriyou)", "ご利用", "ごりよう"),
    ("ご利用", "ご利用", ""),
    ("ご", "ご利用", ""),
    ("goriyou", "ご利用", ""),
    ("", "ご利用", ""),
    ("   ", "ご利用", ""),
    ("たんご", "単語", "たんご"),
    ("タンゴ", "単語", "タンゴ"),
    ("おきゃくさま", "お客様", "おきゃくさま"),
    ("お客様（おきゃくさま）", "お客様", "おきゃくさま"),
    ("お", "お客様", ""),
    ("ひと", "人", "ひと"),
    ("き", "木", "き"),
    ("人", "人", ""),
    ("ラーメン", "拉麺", "ラーメン"),
    ("よやく、ちゅうもん", "予約", "よやく"),
    ("ちゅうもん / よやく", "注文", "ちゅうもん"),
    ("えいぎょうちゅう", "営業中", "えいぎょうちゅう"),
    ("営業中（えいぎょうちゅう）", "営業中", "えいぎょうちゅう")
]

var failures = 0
for test in cases {
    let got = acceptedReading(test.raw, for: test.word)
    let ok = got == test.expected
    if !ok { failures += 1 }
    let mark = ok ? "ok  " : "FAIL"
    print("\(mark) \(test.word.padding(toLength: 8, withPad: " ", startingAt: 0)) raw=\(test.raw.isEmpty ? "(empty)" : test.raw)  got=\(got.isEmpty ? "(none)" : got)  want=\(test.expected.isEmpty ? "(none)" : test.expected)")
}

print("\n\(cases.count - failures)/\(cases.count) passed")
if failures > 0 { exit(1) }
