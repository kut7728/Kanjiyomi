# 보안과 개인정보

[04 기술 설계](README.md)

## 위협과 대응

| 위협 | 대응 | 근거 |
|---|---|---|
| API 키가 저장소·앱에 섞여 퍼짐 | 앱과 저장소에 키가 없다. 사용자가 입력한 키만 쓴다 | `Kanjiyomi/Services/OpenAIService.swift` |
| 기기에 저장된 키 유출 | Keychain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`. 잠금 해제 상태에서만 읽히고 다른 기기로 옮겨지지 않는다 | `Kanjiyomi/Services/KeychainStore.swift` |
| 화면 상태에 키가 남음 | 저장 직후 입력값을 비운다. 화면에는 끝 4자리만 보인다 | `Kanjiyomi/Features/Settings/SettingsView.swift` |
| 로그·URL로 키 노출 | 키는 `Authorization` 헤더로만 보낸다. 로그에 키를 찍지 않는다 | `OpenAIService.swift` |
| 응답 캐시에 데이터가 남음 | ephemeral 세션, URL 캐시·쿠키 없음 | `OpenAIService.swift` |
| 통신 가로채기 | HTTPS만 쓴다. ATS 예외 없음 | `Kanjiyomi.xcodeproj/project.pbxproj` |
| 서버 오류 문장에 담긴 정보 노출 | 오류 응답의 메시지 문장은 쓰지 않고 코드만 읽는다 | `OpenAIService.swift` |

## 비밀 정보 보관 위치

| 비밀 | 위치 |
|---|---|
| OpenAI API 키 | 기기 Keychain만 |
| 서명 인증서 | 개발자 Mac (저장소에 없음). 팀 ID는 `project.pbxproj`에 있음 |
| CI 시크릿 | 없음 (CI는 서명하지 않음) |

## 기기 밖으로 나가는 데이터

| 데이터 | 언제 | 어디로 |
|---|---|---|
| OCR로 읽은 줄의 글자 | ChatGPT 모드로 단어를 나눌 때 | OpenAI |
| 단어의 표제어·읽기·영어 뜻 | ChatGPT 모드로 뜻을 만들 때 | OpenAI |
| API 키 | 위 요청마다 | OpenAI |

사진은 보내지 않습니다. 그 밖의 모드에서는 네트워크를 쓰지 않습니다. 분석·광고 SDK는 없습니다.

## 기기에 저장되는 데이터

| 데이터 | 위치 |
|---|---|
| 스캔한 사진(축소 JPEG)과 인식 결과 | SwiftData `ScanRecord` |
| 단어장, 뜻 캐시, 한자 패턴, 퀴즈 기록 | SwiftData |
| 기본 모드, 모델 이름 | UserDefaults |

삭제 방법은 [data-model.md 삭제 규칙](data-model.md#삭제-규칙)에 있습니다.

## 개인정보 매니페스트

`Kanjiyomi/PrivacyInfo.xcprivacy`: 추적 없음, 수집 데이터는 기타 사용자 콘텐츠(앱 기능, 연결 안 됨, 추적 안 함), 필수 사유 API는 UserDefaults `CA92.1` (TD-20).

## 로그

`print`만 씁니다. 사전 DB를 열지 못한 경우, 기기 모델 오류 객체, 예문 생성 실패 시 그 단어를 찍습니다. 키는 찍지 않습니다. (`DictionaryService.swift`, `MeaningService.swift`)

## 권한

권한 요청 문구는 `Kanjiyomi/InfoPlist.xcstrings`에서 현지화합니다 (DS-13). 기기 언어가 한국어·일본어면 해당 문구, 그 밖에는 영어입니다.

| 권한 | 한국어 | 日本語 | English (기본) |
|---|---|---|---|
| 카메라 | 일본어 전단지·간판을 촬영해 단어를 인식하기 위해 카메라 접근이 필요합니다. | 日本語のチラシや看板を撮影して単語を認識するために、カメラへのアクセスが必要です。 | Kanjiyomi uses the camera to photograph Japanese flyers and signs so it can recognize the words in them. |
| 사진 | 앨범에서 사진을 불러와 일본어 단어를 인식하기 위해 사진 접근이 필요합니다. | アルバムから写真を読み込んで日本語の単語を認識するために、写真へのアクセスが必要です。 | Kanjiyomi loads photos from your library so it can recognize Japanese words in them. |

앨범은 PHPicker로 사용자가 고른 사진만 받아 사진 권한이 필요 없습니다. 카메라가 거부되어 있으면 설정 앱으로 가는 알림을 띄웁니다 (DS-12).

## 결정 대기

- 뜻 캐시·패턴·퀴즈 기록을 지우는 기능 제공 여부
