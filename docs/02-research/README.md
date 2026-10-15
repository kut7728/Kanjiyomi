# 02 조사

| 항목 | 내용 |
|---|---|
| 문서 상태 | 코드 기준 v1 (2026-10-12), 한국어 사전 조사 추가 (2026-10-15) |
| 작성일 | 2026-10-12 |
| 이전 문서 | [01 기획](../01-planning/product-requirements.md) |
| 다음 문서 | [03 화면 설계](../03-design/README.md) |

코드에 연결된 외부 서비스·SDK·데이터를 정리합니다. 한국어 사전 후보는 아래 조사에서 공식 배포처와 약관을 확인했습니다. 그 밖의 가격과 약관은 "(미검증)"으로 둡니다.

## 코드에 연결된 외부 요소

| 요소 | 쓰는 곳 | 기기 밖으로 나가는가 | 비고 |
|---|---|---|---|
| Vision (`RecognizeDocumentsRequest`, `VNRecognizeTextRequest`) | `Kanjiyomi/Services/OCRService.swift` | 아니오 | iOS 26 이상은 문서 인식 요청, 그 이하는 텍스트 인식 요청 |
| NaturalLanguage (`NLTokenizer`, `NLTagger` lemma) | `Kanjiyomi/Services/TokenizerService.swift` | 아니오 | 사전 모드의 단어 조각 |
| Foundation Models (`SystemLanguageModel`) | `Kanjiyomi/Services/MeaningService.swift` | 아니오 | iOS 26 이상, 기기가 지원할 때만. 시뮬레이터에서는 쓸 수 없는 것을 확인함 (2026-10-04) |
| OpenAI Chat Completions | `Kanjiyomi/Services/OpenAIService.swift` | 예 | 사용자 본인 키. 요금은 사용자 계정에 청구 |
| JMdict (영어판) | `tools/build_dict.py` → `Kanjiyomi/Resources/jmdict.sqlite` | 아니오 | 빌드 시 내려받아 SQLite로 번들 |
| KANJIDIC2, Unihan | `tools/build_kanji_layer.py` | 아니오 | 한자 음훈·한국 한자음 |
| Git LFS | `.gitattributes` | 해당 없음 | 사전 DB(약 119MB) 저장 |

## 결정

| ID | 결정 | 근거 |
|---|---|---|
| D-01 | 인식·단어 나누기·사전·생성은 Apple 프레임워크와 번들 데이터로 기기 안에서 한다. 외부 패키지는 없다 | `Kanjiyomi.xcodeproj/project.pbxproj` (`packageProductDependencies` 비어 있음) |
| D-02 | 기기 밖 AI는 OpenAI 하나이고, 앱이 키를 갖지 않고 사용자 키를 쓴다 | `Kanjiyomi/Services/OpenAIService.swift`, `KeychainStore.swift` |
| D-03 | 사전 데이터는 EDRDG의 JMdict·KANJIDIC2와 Unicode Unihan을 쓴다 | `tools/build_dict.py`, `tools/build_kanji_layer.py` |
| D-04 | 오프라인 한국어 뜻을 위한 후보를 조사했다. 한국어기초사전과 한국어 위키낱말사전으로 한국어 뜻 보조 DB를 번들한다. 아래 D-05의 보수적 연결 규칙을 적용한다 (사용자 확정, 2026-10-15) | 아래 한국어 사전 조사 (2026-10-15) |

| D-05 | 한국어기초사전은 일본어 표기·읽기와 JMdict 영어 뜻의 일치를 함께 확인하고 비유적 정의를 제외한다. Wiktionary는 명시된 읽기 또는 JMdict에서 유일한 읽기로만 연결한다. 불확실한 항목은 제외하고 모델 표본 검수와 제외 목록을 둔다. 미수록 단어는 기존 AI/영어 대체 표시를 유지한다 | 한국어 사전 도입 (2026-10-15) |

## 라이선스

| 데이터 | 라이선스 | 출처 |
|---|---|---|
| JMdict, KANJIDIC2 | CC BY-SA 4.0 | [EDRDG 라이선스](https://www.edrdg.org/edrdg/licence.html) |
| Unihan | Unicode License | [unicode.org/license.txt](https://www.unicode.org/license.txt) |

README와 앱 설정의 오픈소스·라이선스 화면에 출처를 적었습니다 (`Kanjiyomi/Features/Settings/LicensesView.swift`). 한국어기초사전·한국어 위키낱말사전의 일부 항목은 `korean.sqlite`로 앱에 포함했습니다. 아래 표는 조사 당시의 후보 비교이며 최종 수록 범위는 마지막 구현 결과를 따릅니다.

## 알려진 위험

| 위험 | 내용 |
|---|---|
| OpenAI 모델 이름 | 기본값 `gpt-5.6-luna`가 계속 유효한지 (미검증). 없어지면 404 → "모델을 찾을 수 없어요" 안내 |
| OpenAI 요금 | 단가 (미검증). 앱 안에 사용량 한도·경고가 없다 |
| Foundation Models 가용성 | 지원 기기·지역·설정 조건 (미검증). 쓸 수 없으면 AI 모드가 숨겨지고 한국어 뜻이 생성되지 않는다 |
| LFS 대역폭 | GitHub 무료 LFS 대역폭 한도 (미검증). CI는 LFS를 받지 않는다 ([06 테스트](../06-testing/test-strategy.md)) |
| 사전 원본 주소 | 빌드 스크립트가 `http://`로 EDRDG에서 내려받는다. 앱 실행에는 영향 없음 |

## 결정 대기

- OpenAI 단가와 사용 한도 정책
- 전체 어휘의 의미 대응 전수 검수와 미수록 단어 확대 범위

## 한국어 사전 조사 (2026-10-15)

### 목적과 결론

현재 `tools/build_dict.py`는 JMdict 영어 뜻만 번들하고, `MeaningService.enrichFromDictionary`는 한국어 뜻을 빈 값으로 시작한다. AI를 쓸 수 없는 기기에서도 한국어 뜻을 보여 주기 위한 조사다. 이 조사에서는 앱 코드·DB를 바꾸지 않았다.

가장 먼저 검증할 후보는 **한국어기초사전의 일본어 번역을 역색인한 데이터**다. 위키낱말사전은 보조 후보로 쓸 수 있지만, 아래 실측에서 생활 단어의 누락과 읽기 정보 부족이 확인됐다. 기존 JMdict는 일본어 읽기·품사·영어 뜻을 위해 유지하는 방향을 권고한다. 이후 사용자 요청에 따라 D-04·D-05 기준으로 보조 DB 도입을 확정했다.

### 후보 비교

| 후보 | 확인한 내용 | 판단과 한계 |
|---|---|---|
| [한국어기초사전](https://krdict.korean.go.kr/kor/openApi/openApiInfo) | 한국어 뜻과 일본어 번역 표제어·뜻풀이가 함께 있다. [전체 다운로드](https://krdict.korean.go.kr/download/downloadPopup)는 Excel/XML/JSON, 2026-09 게시본을 제공한다. [공식 통계](https://krdict.korean.go.kr/statistic/dicStat)는 한국어 표제어 53,671개, 의미 73,636개다 | 우선 검증 후보. 이 수는 일본어 표제어 수가 아니다. `き〖木・樹〗。じゅもく〖樹木〗` 같은 번역 표기를 일본어 표기·읽기로 분리해야 한다. 한국어 단어의 의미 범위가 일본어 단어의 모든 의미와 같지는 않다 |
| [한국어 위키낱말사전 → 일본어](https://kaikki.org/kowiktionary/) | 2026-10-01 덤프의 일본어 15,260개 의미. [원시 JSONL](https://kaikki.org/kowiktionary/rawdata.html)을 내려받아 아래에서 직접 집계했다 | 한국어로 쓰인 일본어 정의라 방향이 맞다. 다만 규모가 작고 표제어와 가나 읽기의 대응이 불완전하다 |
| [JMdict 다국어판](https://www.edrdg.org/jmdict/j_jmdict.html) | 전체 `JMdict.gz`를 직접 확인했으며 218,914개 entry 중 한국어 `gloss`는 0개다 | 영어판 대신 다국어판을 받아도 한국어 뜻 문제를 해결하지 못한다. 한자 한국어 음을 제공하는 Unihan·KANJIDIC 정보와는 구분해야 한다 |
| [우리말샘](https://opendict.korean.go.kr/service/openApiInfo) | API에 언어별 대역어(`translation_info`) 필드가 있다 | 일본어 대역어의 수량·읽기·범위를 실측하지 않았다. 한국어기초사전과 같은 학습용 일본어 번역 사전이라고 간주하지 않는다. 보류 |
| [OMW](https://omwn.org/omw1.html) | 기본 OMW v1 재배포 목록에는 일본어가 있지만 한국어 WordNet은 없다. 확장판은 Wiktionary 기반 자동 연결 자료도 제공한다 | 기본판으로 바로 일한 사전을 만들 수 없다. 확장판 한국어 데이터의 범위·품질은 미검증. 우선순위 낮음 |
| [Tatoeba](https://en.wiki.tatoeba.org/articles/show/using-the-tatoeba-corpus) | 단어 정의가 아닌 대역 문장. 텍스트는 CC BY 2.0 FR, 오디오는 별도 조건이다 | 예문용 후보이며 사전 뜻을 대신하지 못한다. 일한 문장 쌍 수량은 미검증 |
| [Yomitan 사전 목록](https://github.com/MarvNC/yomitan-dictionaries#korean) | KRDICT의 일본어판 등은 한국어 표제어를 일본어로 설명하는 자료다 | 변환 파일의 존재만으로 일한 방향이나 재배포 권리가 확인되지는 않는다. 원본 한국어기초사전을 우선 검토한다 |

### 라이선스 확인

- 한국어기초사전의 [공식 저작권 정책](https://krdict.korean.go.kr/kor/kboardPolicy/copyRightTermsInfo)은 별도 표시가 없는 자료에 **CC BY-SA 2.0 KR**을 적용하며 상업적 이용을 허용한다. 텍스트의 복제·가공·배포가 가능하므로 API 사용 신청과 번들 재배포 허용은 별개다. 출처·저작자·라이선스·변경 사실을 보존해야 한다. 이미지·음성은 개별 조건이므로 이번 후보 범위에서 제외한다.
- [CC BY-SA 2.0 KR 규약](https://creativecommons.org/licenses/by-sa/2.0/kr/legalcode) 4조는 동일조건 배포와 후속 이용을 제한하지 않을 것을 요구한다. 기존 JMdict와 버전이 다르므로 데이터를 무조건 하나의 라이선스로 다시 표시하지 않는다. 원출처별 고지와 재배포 가능한 데이터 사본을 제공하는 방안을 채택 시 정한다.
- Wiktionary 텍스트는 [CC BY-SA 4.0](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use#7._Licensing_of_Content)에 따라 재사용할 수 있다. 원문 페이지 URL을 통한 저작자 표시, 라이선스 고지, 가공 표시가 필요하며 외부 인용·멀티미디어의 별도 조건은 확인해야 한다. Kaikki는 CC BY-SA/GFDL을 안내한다. 두 라이선스의 모든 의무가 항상 동시에 적용된다고 단정하지 않는다.
- [EDRDG 정책](https://www.edrdg.org/edrdg/licence.html)은 데이터와 이를 사용하는 소프트웨어의 라이선스를 구분한다. 앱 소스의 All rights reserved 표시는 사전 원문·파생 데이터까지 적용하면 안 된다.

### 위키낱말사전 실측

자료: [한국어판 원시 JSONL gzip](https://kaikki.org/kowiktionary/raw-wiktextract-data.jsonl.gz), 2026-10-01 덤프, Kaikki 추출일 2026-10-15. 전체 파일을 스트리밍하며 `lang_code == "ja"`인 레코드만 집계했다.

| 지표 | 결과 |
|---|---|
| 일본어 JSON 레코드 / 서로 다른 `word` / 의미 | 13,633 / 12,724 / 15,260 |
| `senses[].glosses[]`에 한글 음절이 있는 서로 다른 `word` | 12,242 (정의 품질 검수 수량은 아님) |
| canonical form에 ruby가 있는 레코드 | 435 |
| `sounds[].other`에 가나 문자열이 있는 레코드 | 221 (위 435개와 중복 가능) |
| 현재 DB의 비어 있지 않은 표기와 한국어 정의 표제어의 정확 일치 | 228,474개 표기 중 7,331개. 읽기·의미 일치나 실제 사용 빈도별 커버리지를 뜻하지 않음 |
| 존재 확인 | 本日, 野菜, 果物 |
| 누락 확인 | 半額, 全品, 駐車場, 営業時間, 特売, 割引 |

표기만으로 합치면 `人気` 같은 여러 읽기의 의미를 잘못 연결할 수 있다. IPA를 가나 읽기와 동일시하거나 한국어 번역만 보고 의미 대응을 확정하지 않는다.

### 한국어기초사전 실측

공식 [전체 다운로드 화면](https://krdict.korean.go.kr/download/downloadPopup)의 JSON 버튼이 연결하는 [2026-09-19 배포 ZIP](https://krdict.korean.go.kr/dicBatchDownload?seq=217)을 가입·API 키 없이 내려받았다. ZIP은 84,486,309바이트이며 JSON 11개를 포함한다. `LexicalResource.Lexicon.LexicalEntry`와 `Sense.Equivalent`를 집계했다.

| 지표 | 결과 |
|---|---|
| LexicalEntry / Sense | 56,555 / 76,833 (부표제어 포함, 공식 표제어 수와 구분) |
| 일본어 Equivalent 중 비어 있지 않은 lemma | 75,144개 |
| 위 일본어 lemma가 하나 이상 있는 LexicalEntry | 54,869개 |
| 서로 다른 일본어 lemma 문자열 | 54,929개. 여러 동의어·복수 읽기가 한 문자열에 들어가므로 일본어 단어 수가 아님 |
| 원본 식별자 | LexicalEntry의 `val`과 Sense의 `val`을 보존해 원출처 의미를 구분할 수 있음. JMdict ID와 직접 연결되지는 않음 |

샘플의 일본어 번역 표기에서 괄호 안 표기를 분리해 확인한 대응:

| 일본어 | 연결된 한국어 표제어 | 주의점 |
|---|---|---|
| 半額 | 반값, 반액 | 같은 일본어 표기·읽기에 한국어 항목 두 개가 연결됨 |
| 駐車場 | 주차장 | 일본어 동의어 パーキング도 함께 있음 |
| 営業時間 | 영업시간 | 복합어 전체가 번역 표제어에 있음 |
| 割引 | 할인 | 부분 문자열 검색으로는 早朝割引 등도 잡히므로 정확 표기 구분 필요 |
| 野菜 | 야채, 채소 | 한국어 동의어 중복 처리 필요 |
| 入口 | 문턱 | **이 배포본의 대응 항목은 비유적 뜻이다. 간판에 ‘문턱’으로 표시하면 잘못된 결과가 됨** |
| 全品 | 발견 못 함 | 원본의 일본어 lemma 전체에서 문자열이 없었음 |

출처의 한국어→일본어 번역이 정확해도, 역방향의 대표 뜻까지 보장하지 않는다. 특히 `入口`는 읽기도 일치하므로 표기+읽기 일치만으로 자동 채택하면 안 된다. 위키낱말사전에는 이 표기의 ‘입구’ 정의가 있지만, 두 자료를 합친 전체 품질은 아직 검수하지 않았다.

재현용 원본 SHA-256:

- 한국어 Wiktionary 원시 gzip: `911d2d956669703efd1f5fc459e9733c7359c340c7344e80f012a7b8eaac308b`
- JMdict 다국어 gzip: `d1da7185e4cb331c08bdef9c89d3651a078de9583c8c13ba41353c04b9d30cc4`
- 한국어기초사전 JSON ZIP: `f9c1b9309afe66429a92cca1b2c426db25ec809d04103aca74c3a23859280df6`

다운로드 주소는 내용이 바뀌는 최신본이다. 채택할 때에는 원본 날짜·해시를 고정해야 한다. 조사용 다운로드는 저장소 밖 `/tmp/`에만 두었다.

### 적용 전 검증과 변경 범위

1. 한국어기초사전의 일본어 번역 표기·읽기를 분리해 JMdict 표기+읽기와 연결하고, 충돌·누락·자주 쓰는 생활 단어를 검수한다. 문장 번역을 단어 뜻으로 자동 대체하지 않는다.
2. 채택하면 `tools/build_dict.py`와 번들 SQLite에 한국어 뜻·원본 의미 식별자·출처를 추가한다. 기존 영어 뜻과 원출처 구분을 보존한다.
3. `DictionaryEntry`, `DictionaryService`의 조회·검색, `MeaningService`의 한국어 초기값·AI 대체 순서, 캐시의 출처 구분을 함께 반영해야 한다. 저장 단어와 기존 캐시의 갱신 범위도 정한다.
4. 출처 화면·README·개인정보/스토어 설명·기술/화면 문서를 맞추고, 동음이의어·미수록 단어·오프라인 표시를 작은 fixture로 테스트한다. CI가 대용량 실제 DB를 받지 않는 규칙은 유지한다.

## 한국어 사전 구현 결과 (2026-10-15)

- `Kanjiyomi/Resources/korean.sqlite`: 23,236개 표기·읽기 조합, 4,579,328바이트. KRDICT 15,717개, Wiktionary 7,519개. 현재 번들 JMdict의 정확한 표기·읽기 키 22,277개와 연결된다 (실제 사용 빈도에 따른 커버리지는 아님).
- `tools/build_korean_dict.py`: 원본 해시 검증, 읽기·표기/뜻 제한, 중복 제거, 최대 3개 뜻, Wiktionary 우선, 제외 후 다음 출처 사용. 원본/검수 파일 오류나 빈 결과일 때 기존 DB를 보존한다.
- `tools/korean_reviews.json`: `gpt-6-luna`의 무작위 100건·생활어 8건 확인과 명시적 제외 2건. 전체 23,236건의 전수 검수는 아니다. 상위 에이전트가 파서·조회 계약을 리뷰하고 복수 읽기·원문 링크·제외 목록 검증 등을 보완했다.
- `入口 → 문턱` 및 의미 없는 지명 참조 `福` 항목은 제외했다. `人気`처럼 canonical 읽기와 발음 필드가 충돌하는 Wiktionary 레코드는 제외하고, 다른 출처의 검증된 뜻만 남긴다.
- 일본어→한국어 정의를 새로 생성하지 않았다. 원본별 권리자·라이선스·원문 URL과 식별자, 가공 고지, 원본 및 검수 파일 해시는 DB에 포함했다.
- 뜻 미수록 단어는 기존 AI 생성/영어 대체 경로로 처리한다. 기존 저장 단어·스캔 기록은 자동 수정하지 않는다.
- 단위 테스트: Swift 55개와 Python fixture 5개. LFS 포인터 상태의 사본에서도 Swift 55개 통과. 원격 CI는 이번 작업에서 실행하지 않았다.
- iOS 26.5 시뮬레이터에서 사전 모드로 테스트 사진을 읽어 本日·半額·野菜·果物·駐車場·無料·割引·営業時間의 한국어 뜻을 확인했다. 실기기 확인은 미실시.

최종 한국어 DB를 포함한 앱에서 사전 검색 `駐車場`의 행이 영어 대신 `주차장`으로 표시되는 것도 sim-use로 확인했다.
