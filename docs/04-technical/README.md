# 04 기술 설계

| 항목 | 내용 |
|---|---|
| 문서 상태 | 코드 기준 v1 (2026-10-12) |
| 작성일 | 2026-10-12 |
| 이전 문서 | [03 화면 설계](../03-design/README.md) |
| 다음 문서 | [05 구현](../05-implementation/README.md) |

## 문서 목록

| 문서 | 내용 |
|---|---|
| [architecture.md](architecture.md) | 계층, 폴더 구조, 인식 파이프라인, 빌드 설정 |
| [data-model.md](data-model.md) | SwiftData 모델, 번들 SQLite, 삭제 규칙 |
| [api-spec.md](api-spec.md) | OpenAI 요청·응답·오류, 내부 서비스 함수 |
| [security.md](security.md) | 위협과 대응, 비밀 정보, 기기 밖으로 나가는 데이터 |

앱 자체 서버와 외부 데이터 갱신이 없어서 `data-sync.md`는 만들지 않았습니다.

## 결정

| ID | 결정 | 근거 |
|---|---|---|
| TD-01 | SwiftUI + `@Observable`. 외부 패키지 없음 | `Kanjiyomi.xcodeproj/project.pbxproj` |
| TD-02 | 앱 타깃의 기본 액터 격리는 `MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION`), Swift 5.0 | `project.pbxproj` |
| TD-03 | 앱 데이터는 SwiftData로 기기에만 저장. 마이그레이션 계획(`VersionedSchema`)은 없다 | `Kanjiyomi/KanjiyomiApp.swift` |
| TD-04 | 사전은 번들 SQLite를 읽기 전용으로 연다. 저장소에서는 Git LFS로 관리 | `Kanjiyomi/Services/DictionaryService.swift`, `.gitattributes` |
| TD-05 | OCR은 iOS 26 이상 `RecognizeDocumentsRequest`(세로쓰기 대응), 그 이하 `VNRecognizeTextRequest`(.accurate) | `Kanjiyomi/Services/OCRService.swift` |
| TD-06 | 기기 안 생성은 Foundation Models의 guided generation(`@Generable`), greedy 샘플링. 쓸 수 있을 때만 | `Kanjiyomi/Services/MeaningService.swift` |
| TD-07 | ChatGPT는 Chat Completions + `json_schema`(strict) 응답. 사용자 키로 앱에서 직접 호출 | `Kanjiyomi/Services/OpenAIService.swift` |
| TD-08 | API 키는 Keychain(`WhenUnlockedThisDeviceOnly`, 동기화 끔)에만 둔다 | `Kanjiyomi/Services/KeychainStore.swift` |
| TD-09 | 한글 발음은 LLM 없이 정해진 가나→한글 표로 만든다 | `Kanjiyomi/Services/KanaRomanizer.swift` |
| TD-10 | 영역 선택은 사진을 자르지 않고, 인식 결과 중 영역이 단어 박스의 35% 이상을 덮는 것만 남긴다 | `Kanjiyomi/Features/Scan/SelectionRegion.swift` (`minimumCoverage = 0.35`), `ScanViewModel.swift` |
| TD-11 | 뜻은 `WordCache`에 캐시해 같은 단어를 다시 생성하지 않는다. ChatGPT 뜻은 단어장에 저장할 때만 캐시에 쓴다 | `MeaningService.swift`, `ScanViewModel.swift` |
| TD-12 | 한자 읽기 패턴은 단어 2개 이상이면 "발견", 4개 이상이면 "익숙함" | `Kanjiyomi/Services/Kanji/PatternDetector.swift` |
| TD-13 | 아래 알려진 문제 7건은 모두 고친다 (사용자 확정, 2026-10-12). 구현은 [05 구현 M8](../05-implementation/milestones.md#m8-알려진-문제-수정) | 이 문서 |
| TD-14 | 설정 화면 개인정보 문구는 실제 전송 내용에 맞게 고친다 (사용자 확정, 2026-10-12) | [07 privacy.md](../07-release/privacy.md) |
| TD-15 | `kanji_meta.is_irregular_prone`, `irregular_words.reason`은 DB에 남기고 앱 코드에서 읽지 않는다. DB는 다시 만들지 않는다 (사용자 확정, 2026-10-15) | `Kanjiyomi/Services/DictionaryService.swift` |
| TD-16 | 기기 모델 생성 호출은 배치마다 30초 제한. 넘으면 그 배치를 버리고 사전 결과를 유지한다. 기본값 (검토 필요) | `Kanjiyomi/Services/MeaningService.swift` |
| TD-17 | 스캔을 지우면 그 스캔을 가리키는 `VocabWord.scanRecordID`를 비운다. 기본값 (검토 필요) | `Kanjiyomi/Services/VocabularyStore.swift` |
| TD-18 | 발음 재생은 `AVSpeechSynthesizer`(`ja-JP`)로 기기 안에서 한다 | `Kanjiyomi/Services/Pronouncer.swift` |
| TD-19 | 수출 규정: HTTPS 외 암호화를 쓰지 않으므로 `ITSAppUsesNonExemptEncryption = NO`. 기본값 (검토 필요) | `project.pbxproj` |
| TD-20 | 개인정보 매니페스트: 추적 없음, 필수 사유 API는 UserDefaults(`CA92.1`), 수집 데이터는 "기타 사용자 콘텐츠"(앱 기능, 연결 안 됨) | `Kanjiyomi/PrivacyInfo.xcprivacy`, RL-10 |
| TD-21 | 한국어 뜻은 별도 읽기 전용 `korean.sqlite`의 표기+읽기 정확 일치로 조회한다. 기존 JMdict 구조·사용자 저장 데이터는 유지한다. 일반 모드는 저장된 AI 뜻 → 번들 한국어 뜻 → AI 생성 → 영어 순서이고, 명시적 ChatGPT 모드는 기존처럼 OpenAI 결과만 사용한다. 한국어 사전 조회 실패는 영어로 대체한다 | 한국어 사전 도입, 구현 완료 (2026-10-15) |

## 알려진 문제

코드를 읽다가 발견한 것입니다. **모두 고쳤습니다** (TD-13, 2026-10-15). 각 항목의 테스트는 [06 테스트](../06-testing/scenarios.md#출시-준비-수정-자동)에 있습니다.

| 문제 | 내용 | 위치 | 수정 |
|---|---|---|---|
| 패턴 상태 되돌아감 | 읽기 추론을 2번 맞혀 "익숙함"이 되어도, 다음 `sync`가 단어 수만으로 상태를 다시 매긴다 | `Kanjiyomi/Services/Kanji/KanjiPatternStore.swift` (`sync`, `recordQuiz`) | `sync`가 퀴즈로 얻은 상태를 유지 (`status(detected:inferenceCorrect:)`) |
| 지운 단어의 패턴이 남음 | `sync`는 행을 추가·갱신만 하고 지우지 않는다. 단어를 지워도 "익힌 읽기 패턴" 수에 남을 수 있다 | `KanjiPatternStore.swift` | `sync`가 저장 단어에 없는 패턴 행을 지움 |
| 끊긴 스캔 연결 | 스캔을 지워도 `VocabWord.scanRecordID`는 그대로다. 상세 화면은 스캔이 없으면 버튼을 숨긴다 | `Kanjiyomi/Models/VocabWord.swift`, `WordDetailView.swift` | 스캔 삭제 시 `VocabularyStore.forgetScan` (TD-17) |
| 같은 뜻 보기 중복 | 뜻 퀴즈 보기를 중복 제거 없이 뽑는다. 뜻이 같은 단어가 있으면 보기가 겹칠 수 있다 (미검증) | `Kanjiyomi/Features/Quiz/QuizView.swift` | `QuizViewModel.choices`가 서로 다른 보기 4개만 만듦 |
| 추론 오답 생성 | 패턴 한자가 첫 글자가 아니면 오답 읽기를 앞에 붙여 어색한 보기가 나올 수 있다 | `Kanjiyomi/Services/Kanji/InferenceQuizBuilder.swift` (`swapPrefix`) | 패턴 한자 자리의 읽기만 바꿈 (`readingOffset`, `swap`) |
| 쓰지 않는 데이터 | `kanji_meta.is_irregular_prone`을 메모리로 읽지만 쓰지 않는다. `irregular_words.reason`은 읽지도 않는다 (TD-15) | `DictionaryService.swift` | 앱이 `is_irregular_prone`을 읽지 않음, DB는 유지 (TD-15) |
| 기기 생성 시간 제한 없음 | Foundation Models 호출에 시간 제한이 없다. 실패는 로그만 남기고 사전 결과를 유지한다 (TD-16) | `MeaningService.swift` | 호출마다 30초 제한 (`withTimeout`, TD-16) |

## 구현 전 검증 항목

- OpenAI 기본 모델 `gpt-5.6-luna`가 실제 계정에서 동작하는지 (2026-10-04 시뮬레이터에서 동작 확인)
- Foundation Models를 지원하는 실기기에서 AI 모드와 예문 생성 동작 (시뮬레이터에서는 쓸 수 없음)
- 앱 타깃의 macOS용 설정(`ENABLE_APP_SANDBOX`, `ENABLE_HARDENED_RUNTIME`)이 iOS 빌드에 영향이 있는지 (미검증) → 2026-10-15에 앱 타깃에서 `ENABLE_APP_SANDBOX`, `ENABLE_HARDENED_RUNTIME`, `ENABLE_USER_SELECTED_FILES`, `REGISTER_APP_GROUPS`를 지움

## 온보딩 결정 (2026-10-16)

| ID | 결정 | 상태 |
|---|---|---|
| TD-22 | 완료 여부는 `@AppStorage("hasCompletedOnboarding")`에 저장하고 `ContentView`에서 최초 전체 화면을 제어한다. 재열기는 설정의 별도 표시 상태를 사용한다. AI 상태는 기존 가용성 확인만 재사용하며 네트워크·키 저장·모드 변경 없이 안내한다 | 구현 완료 (2026-10-16) |

## 결정 대기

- SwiftData 스키마가 바뀔 때의 마이그레이션 방식
