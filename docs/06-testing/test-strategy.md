# 테스트 전략

[06 테스트](README.md)

## 종류와 도구

| 종류 | 도구 | 위치 | 상태 |
|---|---|---|---|
| 단위 테스트 | Swift Testing | `KanjiyomiTests/` | 55개 (빈 `example()` 포함) |
| 데이터 빌드 테스트 | Python unittest | `tools/tests/` | 5개, 작은 원본 fixture 사용 |
| UI 테스트 | XCTest | `KanjiyomiUITests/` | 온보딩 회귀 2개: 완료·재실행·재열기·키 설정 이동·작은 화면의 전체 표시·가로 버튼. 기본 실행 성능·스크린샷 검증도 유지. CI 실행 대상에는 미포함 |
| 수동 확인 | 시뮬레이터, 실기기 | — | [scenarios.md](scenarios.md)의 수동 항목 |

## CI

`.github/workflows/test.yml`

| 항목 | 값 |
|---|---|
| 트리거 | `main` push, 모든 pull request |
| 러너 | `macos-26` |
| 체크아웃 | `actions/checkout@v5`, `lfs: false` (사전 DB는 LFS 포인터로 남는다) |
| 명령 | `xcodebuild test -scheme Kanjiyomi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:KanjiyomiTests CODE_SIGNING_ALLOWED=NO` |
| 데이터 테스트 | `python3 -m unittest discover -s tools/tests -p 'test_*.py'` |
| 결과 | 2026-10-04 첫 CI 실행 통과. 2026-10-15 한국어 사전 변경은 로컬 정상 사본과 LFS 포인터 사본에서 Swift 55개 통과 (원격 CI 미실행) |

사전 DB 없이도 통과하는 것은 단위 테스트가 DB를 쓰지 않기 때문입니다. 앱이 테스트 호스트로 뜰 때 DB를 열지 못하면 로그만 남깁니다.

## 자동화된 것

| 영역 | 파일 |
|---|---|
| 한자 추출, 읽기 정렬, 예외, 한국 한자어, 음훈 분류, 패턴 감지, 읽기 추론 문제, 보조 문제 | `KanjiPatternTests.swift` |
| 가나 → 한글 발음 | `KanaRomanizerTests.swift` |
| 사진 좌표 변환·확대·이동, 영역 선택, 영역 필터 | `RegionSelectionTests.swift` |
| 패턴 동기화, 스캔 연결 정리 (메모리 전용 SwiftData) | `StoreTests.swift` |
| 한국어 사전 정확 조회·누락·손상, 검색/관련 단어, 캐시 갱신·ChatGPT 분리 | `DictionaryTests.swift` (임시 SQLite와 메모리 SwiftData) |
| 한국어 데이터 원본 파싱·안전한 출력 교체 | `tools/tests/test_build_korean_dict.py` |
| 뜻 퀴즈 보기, 패턴 상태 | `KanjiPatternTests.swift` |
| 온보딩 완료 저장·페이지 이동·재열기·설정 이동·작은 화면 전체 표시·가로 탐색 | `KanjiyomiUITests.swift` (로컬 UI 회귀 2개) |

## 자동화되지 않은 것

| 영역 | 이유 / 비고 |
|---|---|
| OCR (Vision) | 테스트 없음 |
| 단어 나누기 (`TokenizerService`) | 사전 DB 필요 |
| 실제 전체 사전 데이터의 품질 (`DictionaryService`, 실제 `KanjiCatalog`) | 조회 동작은 작은 SQLite fixture로 테스트. 전체 원본은 빌드·표본 검수로 확인하며 단위 테스트에 넣지 않음 |
| 기기 모델, ChatGPT (`MeaningService`, `OpenAIService`) | 결과가 매번 다르고, 기기·키가 필요 |
| Keychain (`KeychainStore`) | 테스트 없음 |
| SwiftData 저장 중 `VocabularyStore.absorb` | 테스트 없음 (`KanjiPatternStore.sync`, `forgetScan`은 `StoreTests.swift`) |
| 퀴즈 출제·점수 (`QuizViewModel`) | 보기 만들기(`choices`)만 테스트 |
| `InferenceQuizBuilder.makeQuestions` | 가짜 카탈로그의 `wordsContaining`이 빈 배열이라 돌릴 수 없다 |
| 발음 재생, 카메라 권한 알림 | 수동 확인 (T-40~T-42) |
| 화면 | 테스트 없음 |

## 있어야 할 자동 테스트 (제안)

넣을지는 결정 대기입니다.

- `VocabularyStore.absorb`: 중복 저장 시 빈 필드만 채움, 한국어 뜻 없는 단어 제외
- `OpenAIService` 오류 코드 → 문구 매핑 (네트워크 없이 응답 본문으로)

## 테스트 데이터 규칙

- 가상 데이터만 씁니다. 실제 사용자 사진·단어장은 쓰지 않습니다.
- 테스트에 API 키를 넣지 않습니다. CI에도 시크릿이 없습니다.
- 스크린샷용 전단지 이미지는 직접 만든 가상 이미지를 씁니다.
