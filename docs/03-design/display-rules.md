# 공통 표시 규칙

[03 화면 설계](README.md)

| 항목 | 규칙 | 근거 |
|---|---|---|
| 표제어 | 표기(surface). 비어 있으면 기본형(lemma) | `Kanjiyomi/Models/RecognizedWord.swift` |
| 뜻 | 한국어 뜻 → 없으면 영어 뜻(JMdict) → 없으면 "뜻 없음" | `RecognizedWord.swift`, `VocabWord.swift` (`displayMeaning`) |
| 읽기 | 히라가나. 비어 있으면 숨김 | 각 화면 |
| 한글 발음 | 가나를 정해진 표로 옮긴다. 장음(ー)과 촉음(っ)은 빼고, ん은 앞 글자의 받침 ㄴ으로 붙인다(붙일 글자가 없으면 "응"). 항상 파란 작은 글씨 | `Kanjiyomi/Services/KanaRomanizer.swift` |
| 품사 | JMdict 영어 품사를 한국어로 바꿔 보여 준다 | `Kanjiyomi/Services/PartOfSpeechFormatter.swift` |
| 개수 | "N개". 퀴즈는 "i / n", "점수 s" | 각 화면 |
| 날짜 | `ko_KR`, "yyyy년 M월 d일 a h:mm" | `ScanView.swift` |
| 줄 수 제한 | 1줄: 기록 미리보기, 저장 액세서리 문구, 영역 도구 버튼(최소 0.8배 축소). 2줄: 단어장 뜻, 검색 뜻(한국어 우선). 스캔 결과 행은 제한 없음 | 각 화면 |
| 복사 | 표제어만 복사. 토스트 "「…」 복사됨"이 1.4초 뒤 사라짐 | `Kanjiyomi/DesignSystem/Components.swift` (`KYCopyToast`) |
| 오류 | 빨간(`danger`) 글자로 패널 안에 표시 | `ScanResultView.swift` |

## 기기 모델을 쓸 수 없을 때

iOS 26 미만이거나 기기가 Foundation Models를 지원하지 않으면 다음과 같이 보입니다. (`Kanjiyomi/Services/MeaningService.swift`의 `isGenerationAvailable`)

- 단어 나누기 메뉴에 "AI로 나누기"가 없다.
- 사전에 없는 단어는 목록에서 빠진다. (ChatGPT 모드 제외)
- 번들 한국어 뜻이 있으면 보여 준다. 미수록 단어는 영어 뜻 또는 "뜻 없음"이 보인다.
- 예문을 만들지 않는다.
