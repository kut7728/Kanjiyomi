# 아키텍처

[04 기술 설계](README.md)

## 구성도

```
┌──────────────── iPhone ────────────────┐
│ SwiftUI 화면 (Features/)                │
│   ScanViewModel (@Observable)           │
│        │                                │
│   ScanPipeline                          │
│    ├─ OCRService ── Vision              │
│    ├─ TokenizerService ── NaturalLanguage│
│    ├─ DictionaryService ── jmdict.sqlite + korean.sqlite│
│    ├─ MeaningService ── Foundation Models│
│    └─ OpenAIService ──────────────┐     │
│   KanjiPatternStore, VocabularyStore    │
│        │                          │     │
│   SwiftData (기기 저장소)          │     │
│   Keychain (API 키)               │     │
└───────────────────────────────────┼─────┘
                                    │ HTTPS (ChatGPT 모드만)
                         api.openai.com/v1/chat/completions
```

## 폴더 구조

```
Kanjiyomi/
├── KanjiyomiApp.swift      앱 진입점, SwiftData 컨테이너
├── ContentView.swift       탭, 저장 액세서리, 스캔 열기 라우팅
├── Features/
│   ├── Scan/               홈, 결과, 영역 선택, 파이프라인, 뷰모델, 라우터
│   ├── WordDetail/         상세, 한자 패턴 섹션
│   ├── Vocabulary/         단어장
│   ├── Search/             사전 검색
│   ├── Quiz/               퀴즈, 패턴 진행 카드
│   └── Settings/           API 키, 모델, 개인정보 안내
├── Services/               OCR, 토크나이저, 사전, 뜻 생성, OpenAI, Keychain, 가나→한글
│   └── Kanji/              한자 추출, 읽기 정렬, 음훈 분류, 예외, 한국 한자어, 패턴, 퀴즈
├── Models/                 SwiftData 모델, 인식 결과 구조체, 한자 학습 타입
├── DesignSystem/           색, 글자, 컴포넌트
└── Resources/jmdict.sqlite 번들 사전 (Git LFS)
tools/                      사전 DB를 만드는 Python 스크립트
KanjiyomiTests/             단위 테스트 (Swift Testing)
KanjiyomiUITests/           Xcode 기본 UI 테스트
.github/workflows/test.yml  CI
```

## 계층과 동시성

| 종류 | 타입 | 격리 |
|---|---|---|
| 화면 상태 | `ScanViewModel` | `@MainActor @Observable` |
| 싱글턴 | `OpenAIService.shared` | `@MainActor @Observable` |
| 싱글턴 | `MeaningService.shared` | `@MainActor` |
| 싱글턴 | `DictionaryService.shared` | `nonisolated`, `NSLock`으로 보호 |
| 상태 없는 enum | `OCRService`, `TokenizerService`, `KeychainStore` | `nonisolated` |
| 상태 없는 enum | `VocabularyStore`, `ScanPipeline`, `KanjiPatternStore` | 기본(MainActor) |

뜻 생성은 `ScanViewModel.meaningTask`의 `Task`에서 돌고, 새 스캔·초기화·다시 인식 때 취소합니다. ChatGPT 뜻 배치는 `withTaskGroup`으로 동시에, 기기 모델 배치는 차례로 돌립니다. (`Kanjiyomi/Features/Scan/ScanPipeline.swift`)

## 인식 파이프라인

`ScanViewModel.process` → `ScanPipeline.recognize`

1. **사진 준비**: 방향을 `.up`으로 다시 그린다 (`UIImage+Orientation.swift`). 기기 모델을 미리 띄운다(`prewarm`).
2. **모드 확인**: 쓸 수 없는 모드면 사전 모드로 바꾼다 (`SegmentationMode.resolved`).
3. **OCR**: 일본어만, 언어 보정 켬. 줄 단위로 글자와 위치(사각형 4점)를 얻는다.
4. **단어 나누기** (줄마다)
   - AI·ChatGPT 모드: 모델이 준 단어를 줄에서 순서대로 찾는다. 일본어가 아닌 것, 문장부호, 16자 넘는 것, 조사·어미 같은 불용어, 가나 한 글자는 버린다. 남는 게 없으면 사전 방식으로 돌아간다.
   - 사전 모드: `NLTokenizer`로 자르고 `NLTagger`로 기본형을 구한다. 이웃 조각을 최대 6개(12자)까지 붙여 사전에 있으면 합친다. 사전에 없는 조각은 버린다.
   - 단어 위치는 글자 범위의 박스, 실패하면 줄 전체 박스. 6% 넓힌다.
5. **단어 묶기**: 같은 `표기|기본형`을 한 단어로 묶고 위치를 모은다. 캐시에 한국어 뜻이 있으면 쓰고, 없으면 사전에서 읽기·한국어 뜻·영어 뜻을 찾는다. 번들 한국어 뜻이 없는 단어만 AI로 채운다.
6. **스캔 저장**: `ScanRecord`를 자동으로 넣는다.
7. **뜻 채우기**: 한국어 뜻이나 읽기가 빈 단어를 배치로 생성한다(기기 8개, ChatGPT 24개). 배치마다 화면에 반영한다.

## 빌드 설정

| 항목 | 값 |
|---|---|
| 배포 타깃 | iOS 18.0 |
| 기기 | iPhone (`TARGETED_DEVICE_FAMILY = 1`) |
| 방향 | 세로만 (DS-10) |
| Bundle ID | `my.kanji.app` (테스트 타깃은 `my.kanji.KanjiyomiTests`, `my.kanji.KanjiyomiUITests`) |
| 버전 | 1.0 (1) |
| 서명 | 자동, 팀 `S27R5C5NF6` (현재 프로젝트 설정 기준) |
| Info.plist | 자동 생성. 카메라·사진 권한 문구, `ITSAppUsesNonExemptEncryption = NO` |
| 개인정보 매니페스트 | `Kanjiyomi/PrivacyInfo.xcprivacy` |
| 공유 scheme·테스트 플랜 | 없음. scheme은 Xcode가 자동 생성 |

## 사전 DB 만들기

```sh
python3 tools/build_dict.py          # JMdict → entries. 끝나면 build_kanji_layer.py도 실행
python3 tools/build_kanji_layer.py   # KANJIDIC2 + Unihan → kanji_meta, kanji_index, irregular_words
```

내려받은 원본은 `tools/.cache/`에 둡니다(git 무시).

한국어 보조 DB는 `tools/build_korean_dict.py --krdict <JSON.zip> --wiktionary <JSONL.gz> --jmdict <JMdict.gz>`로 별도 생성한다. 원본 해시를 확인하고 임시 DB 검증 후 원자적으로 교체한다. 실패하면 기존 파일을 보존한다. 각 원본의 출처·해시·라이선스 및 검수 제외 목록은 데이터에 기록한다. 원본 다운로드는 빌드 시 개발자가 수행하며 앱 실행 중 다운로드하지 않는다.
