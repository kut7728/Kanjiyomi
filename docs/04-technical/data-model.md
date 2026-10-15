# 데이터 모델

[04 기술 설계](README.md)

## SwiftData

컨테이너: `Schema([VocabWord, WordCache, ScanRecord, UserKanjiPattern, QuizAttempt])`, 디스크 저장. 만들지 못하면 `fatalError`. (`Kanjiyomi/KanjiyomiApp.swift`)
`@Relationship`은 없습니다. 모델끼리는 키나 UUID로 이어집니다.

### WordCache — 단어별 뜻 캐시

`Kanjiyomi/Models/WordCache.swift`

| 필드 | 타입 | 설명 |
|---|---|---|
| `key` | String, unique | `"표기\|기본형"` |
| `surface`, `lemma` | String | 표기, 기본형 |
| `reading`, `hangul` | String | 읽기, 한글 발음 |
| `meaningKO`, `meaningEN` | String | 한국어 뜻, 영어 뜻(JMdict) |
| `partOfSpeech` | String | 품사 |
| `exampleJP1`, `exampleKO1`, `exampleJP2`, `exampleKO2` | String | 예문 2개 |
| `meaningSource` | String, 기본 `""` | `foundation`, `openai`, `dictionary`. 번들 뜻 캐시는 조회 때 새 DB와 다시 맞추며 뜻이 바뀌면 기존 예문을 지움 |
| `updatedAt` | Date | |

### ScanRecord — 스캔 기록

`Kanjiyomi/Models/ScanRecord.swift`

| 필드 | 타입 | 설명 |
|---|---|---|
| `id` | UUID, unique | |
| `imageData` | Data, external storage | JPEG, 긴 변 1600px, 품질 0.8 |
| `wordsData` | Data | `[RecognizedWord]` JSON (위치 포함) |
| `wordCount` | Int | |
| `previewText` | String | 앞 단어 4개를 " · "로 이음 |
| `segmentationRaw` | String, 기본 `"dictionary"` | 단어 나누기 모드 |
| `meaningsSaved`, `vocabularyAdded` | Bool | 뜻 저장, 단어장 저장 여부 |
| `createdAt` | Date | |

### VocabWord — 단어장

`Kanjiyomi/Models/VocabWord.swift`

| 필드 | 타입 | 설명 |
|---|---|---|
| `id` | UUID, unique | |
| (WordCache와 같은 문자열 필드) | String | 표기, 기본형, 읽기, 한글 발음, 뜻, 품사, 예문 |
| `scanRecordID` | UUID? | 단어가 나온 스캔. 관계가 아닌 수동 연결 |
| `createdAt` | Date | |

중복은 `표기|기본형`으로 판단합니다. 이미 있는 단어는 빈 필드만 채우고, 스캔 연결을 가장 최근 스캔으로 바꿉니다. 스캔 결과에서 저장할 때는 한국어 뜻이 있는 단어만 저장합니다. (`Kanjiyomi/Services/VocabularyStore.swift`) 단어 상세에서 저장할 때는 이 조건 없이 바로 넣고 스캔 연결도 없습니다. (`WordDetailView.swift`)

### UserKanjiPattern — 한자 읽기 패턴

`Kanjiyomi/Models/UserKanjiPattern.swift`

| 필드 | 타입 | 설명 |
|---|---|---|
| `key` | String, unique | `"한자\|읽기"` |
| `kanji`, `hanjaKO`, `observedReading` | String | 한자, 한국 한자음, 읽기 |
| `seenWordCount` | Int | 이 읽기로 저장한 단어 수 |
| `quizCorrect`, `quizTotal`, `inferenceCorrect` | Int | 퀴즈 기록 |
| `lastReviewedAt` | Date? | |
| `statusRaw` | String | `emerging`(1개) / `discovered`(2~3개) / `familiar`(4개 이상) |
| `sampleWords` | String | "、"로 이은 예시 단어 |
| `updatedAt` | Date | |

`KanjiPatternStore.sync`가 퀴즈 화면·단어 상세·단어장 화면이 나타날 때 저장한 단어 전체로 다시 계산합니다. 저장·삭제 시점에는 돌지 않습니다. 저장한 단어에 더 이상 없는 패턴의 행은 지우고, 읽기 추론을 2번 맞혀 얻은 "익숙함"은 단어 수와 상관없이 유지합니다.

### QuizAttempt — 퀴즈 기록

`Kanjiyomi/Models/QuizAttempt.swift`

| 필드 | 타입 | 설명 |
|---|---|---|
| `surface` | String | 문제 단어 |
| `modeRaw` | String | "단어 → 뜻" / "뜻 → 단어" / "읽기 추론" |
| `isCorrect` | Bool | |
| `createdAt` | Date | |

보조 문제(같은 한자 복습)는 기록하지 않습니다. 퀴즈 점수 자체는 저장하지 않습니다.

## 그 밖의 저장

| 위치 | 키 | 값 |
|---|---|---|
| `@AppStorage` | `wordSegmentation` | 기본 단어 나누기 모드 (사전 / AI) |
| `@AppStorage` | `openAIModel` | ChatGPT 모델 이름. 비면 `gpt-5.6-luna` |
| Keychain | service `my.kanji.Kanjiyomi.secrets`, account `openai.apiKey` | OpenAI API 키 |

## 번들 SQLite (`Kanjiyomi/Resources/jmdict.sqlite`)

읽기 전용(`SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX`)으로 엽니다.

| 테이블 | 열 | 만드는 스크립트 |
|---|---|---|
| `entries` | `id`, `kanji`, `reading`, `pos`, `gloss` (kanji·reading 색인) | `tools/build_dict.py`. 항목마다 첫 읽기, 뜻 3개까지, 뜻마다 영어 풀이 5개까지. 한자 표기가 있으면 읽기만 있는 행도 추가 |
| `kanji_meta` | `kanji`, `hanja_ko`, `on_readings`, `kun_readings`, `is_irregular_prone` (앱은 읽지 않음, TD-15) | `tools/build_kanji_layer.py` |
| `kanji_index` | `kanji`, `surface`, `reading`, `pos`, `gloss` | 같음 |
| `irregular_words` | `surface`, `reading`, `reason` (16개) | 같음 |

| 함수 | 쿼리 |
|---|---|
| `exists` | `kanji` 또는 `reading`이 같은 행. 결과를 메모리에 캐시 |
| `lookup` | 한자 일치 → 읽기 일치. 없고 4자 이상이면 앞의 お/ご를 떼고 다시 |
| `search` | 일본어면 일치·접두 LIKE, 그 밖은 `gloss LIKE %q%`. 40개까지 |
| `wordsContaining` | `kanji_index`, 짧은 단어 순 |
| `meta`, `isIrregular` | 처음 쓸 때 `kanji_meta`, `irregular_words` 전체를 메모리에 올림 |

## 한국어 보조 SQLite (`Kanjiyomi/Resources/korean.sqlite`)

별도 읽기 전용 연결로 조회하며, 일반 Git 파일로 배포한다. 기존 `jmdict.sqlite`와 SwiftData 스키마는 바꾸지 않는다.

| 테이블 | 열 | 용도 |
|---|---|---|
| `meanings` | `written`, `reading` (복합 기본키), `meaning`, `source`, `source_id`, `source_url`, `license` | 표기와 읽기가 모두 일치하는 한국어 뜻, 원문 식별자와 출처 고지 |
| `metadata` | `key`, `value` | 원본 날짜·해시·라이선스·가공 정보 |

`DictionaryEntry.glossKO`가 한국어 뜻을 전달한다. 검색 행의 뜻은 한국어 우선이며 검색 입력은 기존처럼 일본어/영어다. 한자 관련 단어 상세도 같은 보조 사전을 사용한다. 보조 DB가 없거나 깨졌거나 뜻이 없으면 빈 한국어 뜻을 돌려 기존 영어/AI 대체 경로를 유지한다.

`MeaningService.resolve`는 같은 읽기의 기존 AI 캐시를 먼저 사용한다. 일반 조회는 번들 한국어 뜻을 캐시에 `dictionary` 출처로 기록하고, 한국어 뜻이 있으면 생성 호출을 생략한다. 명시적 ChatGPT 모드에서는 번들 뜻을 사용하지 않아 기존 OpenAI 전용 뜻 생성 동작을 유지한다. 검색에서 선택한 항목의 읽기를 전달하여 다른 읽기의 캐시를 재사용하지 않는다.

사용자가 저장한 `VocabWord`와 `ScanRecord`의 뜻은 자동 변경하지 않는다.

## 삭제 규칙

| 대상 | 사용자가 지울 수 있나 | 방법 |
|---|---|---|
| 스캔 기록 | 예 | S-01 스와이프 |
| 단어장 단어 | 예 | S-07 스와이프·일괄 삭제 |
| API 키 | 예 | S-12 "키 삭제" |
| WordCache, UserKanjiPattern, QuizAttempt | 아니오 | 앱을 지워야 지워진다 |

스캔을 지우면 그 스캔을 가리키는 `VocabWord.scanRecordID`를 비웁니다 (`VocabularyStore.forgetScan`, TD-17).
