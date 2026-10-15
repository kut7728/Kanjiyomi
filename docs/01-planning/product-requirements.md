# 01 기획서

| 항목 | 내용 |
|---|---|
| 문서 상태 | 코드 기준 v1 (2026-10-12) |
| 작성일 | 2026-10-12 |
| 이전 문서 | [docs/README.md](../README.md) |
| 다음 문서 | [02 조사](../02-research/README.md) |

## 한 줄 소개

일본 전단지·간판 사진에서 일본어를 단어 단위로 읽어, 한국어 뜻과 한글 발음을 사진 위에 짚어 주고 단어장·퀴즈로 복습하게 하는 iOS 앱.

## 해결할 문제

코드에서 드러나는 범위만 적습니다.

- 사진 속 일본어를 단어로 나누고, 각 단어의 읽기·뜻을 바로 보여 준다. (`Kanjiyomi/Features/Scan/ScanPipeline.swift`)
- 목록의 단어가 사진 어디에 있는지 짚어 준다. (`Kanjiyomi/Features/Scan/ScanResultView.swift`)
- 한자를 하나씩 외우는 대신, 저장한 단어에서 반복되는 읽기 패턴을 모아 처음 보는 단어의 읽기를 추론하게 한다. (`Kanjiyomi/Features/Quiz/PatternProgressCard.swift`의 안내 문구)

## 대상 사용자

결정 대기. UI 문구가 모두 한국어이고 뜻·발음을 한국어로 보여 주므로 한국어 사용자를 위한 앱으로 보입니다. 학습 수준, 거주 여부 같은 구체적인 대상은 코드로 알 수 없습니다.

## 사용 흐름

| 시점 | 사용자가 하는 일 | 화면 |
|---|---|---|
| 처음 실행했을 때 | 사전의 한계·현재 기기 AI 상태·모드 차이·선택적 API 키 설정을 확인한다 | S-14 온보딩 |
| 일본어를 마주쳤을 때 | 카메라로 찍거나 앨범에서 사진을 고른다 | [S-01 스캔 홈](../03-design/screen-flow.md) |
| 인식 직후 | 단어 목록을 보고, 단어를 탭해 사진 위 위치와 뜻을 본다 | S-02 스캔 결과 |
| 일부만 보고 싶을 때 | 손가락으로 영역을 그려 그 안의 단어만 남긴다 | S-05 영역 선택 |
| 더 알고 싶을 때 | 말풍선을 탭해 상세(한자 구성, 예문)를 본다 | S-06 단어 상세 |
| 기억하고 싶을 때 | 인식된 단어를 단어장에 저장한다 | S-02, S-06 |
| 복습할 때 | 단어장을 보거나 퀴즈를 푼다 | S-07, S-09~S-11 |

## 첫 출시 기능

모두 코드에 구현되어 있습니다. 출시는 하지 않았습니다([07 출시 준비](../07-release/README.md)).

| ID | 기능 | 근거 |
|---|---|---|
| F-01 | 사진 입력: 카메라 촬영, 앨범에서 1장 선택. 카메라가 없으면 앨범을 연다 | `Kanjiyomi/Features/Scan/ScanView.swift`, `ImagePickers.swift` |
| F-02 | 일본어 글자 인식(OCR). iOS 26 이상은 세로쓰기도 읽는다 | `Kanjiyomi/Services/OCRService.swift` |
| F-03 | 단어 나누기 3모드: 사전 / 온디바이스 AI / ChatGPT | `Kanjiyomi/Features/Scan/SegmentationMode.swift` |
| F-04 | 단어별 읽기, 한국어 뜻(없으면 영어 뜻), 한글 발음 표시 | `Kanjiyomi/Services/MeaningService.swift`, `KanaRomanizer.swift` |
| F-05 | 단어 탭 시 사진을 확대하고 위치에 박스·말풍선 표시, 말풍선 탭 시 상세로 이동 | `Kanjiyomi/Features/Scan/ScanResultView.swift` |
| F-06 | 영역 선택: 자유 곡선으로 그린 영역 안의 단어만 보기·저장 | `Kanjiyomi/Features/Scan/RegionSelectView.swift`, `SelectionRegion.swift` |
| F-07 | 스캔 기록: 자동 저장, 홈에서 다시 열기, 스와이프 삭제 | `Kanjiyomi/Models/ScanRecord.swift`, `ScanView.swift` |
| F-08 | 단어 상세: 표제어 복사, 뜻, 한자 구성·한국 한자어, 예문, 원본 스캔 보기, 단어장 저장 | `Kanjiyomi/Features/WordDetail/` |
| F-09 | 단어장: 목록, 스와이프 삭제, 일괄 선택 삭제 | `Kanjiyomi/Features/Vocabulary/VocabularyView.swift` |
| F-10 | 사전 검색: 한자·가나 또는 영어 뜻으로 검색 | `Kanjiyomi/Features/Search/DictionarySearchView.swift` |
| F-11 | 퀴즈 3모드: 단어 → 뜻, 뜻 → 단어, 읽기 추론. 최대 10문제, 4지선다 | `Kanjiyomi/Features/Quiz/QuizView.swift` |
| F-12 | 한자 읽기 패턴: 저장한 단어에서 같은 한자·같은 음독을 모아 상태(발견·익숙함)를 매긴다 | `Kanjiyomi/Services/Kanji/` |
| F-13 | 설정: OpenAI API 키 저장·삭제, 모델 이름, 개인정보 안내 | `Kanjiyomi/Features/Settings/SettingsView.swift` |
| F-14 | 단어 상세에서 일본어 발음 듣기 | `Kanjiyomi/Services/Pronouncer.swift`, `WordDetailView.swift` |
| F-15 | 오픈소스·라이선스 화면: 사전 데이터 출처 표기 | `Kanjiyomi/Features/Settings/LicensesView.swift` |

## 지원 범위

| 항목 | 코드 기준 |
|---|---|
| 기기 | iPhone만 (`TARGETED_DEVICE_FAMILY = 1`). 세로 화면만 (사용자 확정, 2026-10-15) |
| OS | iOS 18.0 이상. 온디바이스 AI·세로쓰기 인식·탭 바 저장 액세서리는 iOS 26 이상 |
| UI 언어 | 한국어만. 현지화 파일 없음 |
| 인식 언어 | 일본어 |
| 화면 모드 | 라이트 모드 고정 (영역 선택 화면만 다크) |
| 로그인 | 없음 |
| 네트워크 | ChatGPT 모드에서만 사용 |

## 하지 않을 것

현재는 로컬 기능에 집중한다. 사용자들이 AI 생성 결과를 공유하는 통합 사전 백엔드는 다음 단계로 미룬다 (사용자 확정, 2026-10-16). 로그인·동기화·알림·위젯의 장기 지원 여부는 결정 대기다.

## 온보딩 결정 (2026-10-16)

| ID | 결정 | 근거 |
|---|---|---|
| F-16 | 첫 실행과 설정 재열기로 사전 미수록·Apple Intelligence 불가 시 한계, 모드 차이, GPT 키의 장점·요금·전송 정보를 안내한다. 키 등록은 선택이며 새 GPT 예문 생성은 현재 지원하지 않는다 | 사용자 요청, [S-14](../03-design/screens.md#s-14-사용-안내-온보딩-ds-15-ds-16) |

## 다음 버전 후보

코드와 이전 문서에서 보이는 후보입니다. 확정된 것은 아닙니다.

- 알려진 문제 수정 ([05 구현 남은 작업](../05-implementation/milestones.md#남은-작업))

## 제약 조건

| 항목 | 내용 |
|---|---|
| 비용 | 앱 운영 서버 없음. ChatGPT 요금은 사용자 본인 계정에 청구 (`SettingsView.swift` 개인정보 안내). 비용 한도는 결정 대기 |
| 플랫폼 | Apple 프레임워크만 사용. 외부 패키지 없음 |
| 데이터 | 번들 사전은 JMdict·KANJIDIC2 기반 (CC BY-SA 4.0). [02 조사](../02-research/README.md) 참고 |
| 공개 여부 | GitHub 저장소 `kut7728/Kanjiyomi`. 공개 전환은 사용자가 직접 진행 |
| 출시 목표 | **App Store 출시** (사용자 확정, 2026-10-12). 출시 준비 항목은 [07 출시 준비](../07-release/README.md) |
| 출시 국가·가격 | 한국·일본, 무료 (사용자 확정, 2026-10-15) |

## 결정 대기

- 대상 사용자, 하지 않을 것
- ChatGPT 사용 비용 한도 (앱 안에 한도·경고 없음)
- 다크 모드, iPad, 다국어 지원 여부 (첫 출시는 한국어 UI·세로·iPhone만)

## 용어 정리

| 용어 | 뜻 |
|---|---|
| 스캔 | 사진 한 장을 인식한 결과. `ScanRecord`로 저장 |
| 단어 나누기 | 인식한 줄을 단어 단위로 자르는 일. 사전·AI·ChatGPT 중 하나로 한다 |
| 한글 발음 | 가나 읽기를 한글로 옮긴 표기. 예: ほんじつ → 혼지츠 |
| 음독 / 훈독 | 한자를 중국식 음으로 읽기 / 일본 고유어로 읽기 |
| 숙자훈 | 今日(きょう)처럼 글자별로 나눌 수 없는 읽기. 앱은 "통째로 기억하는 단어"로 보여 준다 |
| 읽기 패턴 | 같은 한자가 같은 음독으로 읽히는 단어 묶음. 예: 経(けい) → 経済·経験·経営 |
| 한국 한자어 | 일본어 단어를 한국 한자음으로 읽은 것. 예: 経験 → 경험 |
