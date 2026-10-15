# API

[04 기술 설계](README.md)

앱 자체 서버는 없습니다. 외부 API는 OpenAI 하나입니다. (`Kanjiyomi/Services/OpenAIService.swift`)

## 공통 규칙

| 항목 | 값 |
|---|---|
| 엔드포인트 | `POST https://api.openai.com/v1/chat/completions` |
| 인증 | `Authorization: Bearer <사용자 키>`. 요청마다 Keychain에서 읽는다 |
| 모델 | `@AppStorage("openAIModel")`, 비면 `gpt-5.6-luna` |
| `reasoning_effort` | `low` |
| 응답 형식 | `response_format: { type: json_schema, json_schema: { name, strict: true, schema } }` |
| 세션 | `URLSession(.ephemeral)`, 캐시·쿠키 없음, 요청 시간 제한 60초 |
| 호출 조건 | 키가 저장되어 있고, 사용자가 ChatGPT 모드를 골랐을 때만 |

## 단어 나누기

| 항목 | 내용 |
|---|---|
| 보내는 것 | OCR로 읽은 줄의 글자 |
| 배치 | 30줄씩 차례로. 오류가 나면 거기서 멈추고 받은 데까지 쓴다 |
| 스키마 `segmented_lines` | `{ "lines": [ { "line": string, "words": [string] } ] }` |

## 뜻 만들기

| 항목 | 내용 |
|---|---|
| 보내는 것 | 단어마다 표제어, 읽기, JMdict 영어 뜻 |
| 배치 | 24단어씩, 동시에 |
| 스키마 `word_meanings` | `{ "items": [ { "word": string, "meaning": string, "reading": string } ] }` |
| 캐시 | 받은 뜻은 단어장에 저장할 때 `WordCache`에 `meaningSource = openai`로 쓴다. 뜻이 바뀌면 예문을 지운다 |

두 스키마 모두 `additionalProperties: false`입니다. 응답은 `choices[0].message.content`를 JSON으로 해석합니다.

## 오류

오류 응답에서는 `error.code`와 `error.type`만 읽습니다. 서버의 메시지 문장은 쓰지 않습니다.

| 경우 | 사용자에게 보이는 문구 |
|---|---|
| 키 없음 | "설정에서 OpenAI API 키를 먼저 추가해 주세요." |
| `insufficient_quota`, `credit_balance_exhausted` | 크레딧 없음 안내 |
| `*_spend_limit_exceeded` | 지출 한도 도달 안내 |
| `organization_usage_limit_exceeded` | 사용 한도 도달 안내 |
| 401, 403 | "API 키가 거부됐어요…" |
| 404 | "모델을 찾을 수 없어요…" |
| 429 | "요청이 너무 빨라요…" |
| 연결 실패 | "ChatGPT에 연결하지 못했어요. 네트워크를 확인해 주세요." |
| 요청 실패 | "ChatGPT 요청에 실패했어요. 네트워크를 확인해 주세요." |
| 응답 해석 실패 | "ChatGPT 응답을 이해하지 못했어요." |
| 그 밖 | "ChatGPT 요청이 실패했어요. (코드)" |

문구는 S-02 패널에 빨간 글자로 보입니다. 앱 안에 사용량 한도는 없습니다.

## 기기 안 모델 (Foundation Models)

외부 API는 아니지만 같은 역할을 합니다. (`Kanjiyomi/Services/MeaningService.swift`)

| 작업 | 배치 | 세션 | 토큰 한도 |
|---|---|---|---|
| 단어 나누기 | 6줄 | 배치마다 새 세션, greedy | 120 × 줄 수 |
| 뜻 | 8단어 | 세션을 3배치까지 재사용, 오류 나면 새로 | 140 × 단어 수 |
| 빠진 읽기 | 단어 수만큼 | 별도 세션, greedy | 60 × 단어 수 |
| 예문 | 1단어 (상세 화면에서) | 기본 샘플링 | 400 |

결과는 `@Generable` 타입(`SegmentedLineList`, `GeneratedMeaningList`, `GeneratedReadingList`, `GeneratedExamples`)으로 받습니다. 실패하면 로그만 남기고 빈 결과를 돌려줍니다.

한국어 보조 사전(TD-21)은 번들 파일 조회만 사용하며 실행 중 원본 다운로드나 외부 사전 API 호출은 없다. 일반 모드에서 번들 한국어 뜻을 찾으면 해당 단어의 뜻 생성 호출을 생략한다. 명시적 ChatGPT 모드의 전송 내용과 호출 조건은 유지한다.
