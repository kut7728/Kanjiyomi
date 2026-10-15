# 03 화면 설계

| 항목 | 내용 |
|---|---|
| 문서 상태 | 코드 기준 v1 (2026-10-12) |
| 작성일 | 2026-10-12 |
| 이전 문서 | [02 조사](../02-research/README.md) |
| 다음 문서 | [04 기술 설계](../04-technical/README.md) |

## 문서 목록

| 문서 | 내용 |
|---|---|
| [screen-flow.md](screen-flow.md) | 화면 목록 S-xx, 탭 구조, 이동 흐름 |
| [screens.md](screens.md) | 화면별 구성, 동작, 상태별 화면과 실제 문구 |
| [display-rules.md](display-rules.md) | 여러 화면에 공통인 표시 규칙 |
| [visual-design.md](visual-design.md) | 색·글자·컴포넌트·아이콘 |
| [screenshots/](screenshots/) | 시뮬레이터 스크린샷 (2026-10-04, iPhone 17 Pro, ChatGPT 모드) |

알림·위젯·공유 확장은 없어서 `notifications.md`는 만들지 않았습니다. HTML 미리보기도 없습니다.

## 결정

| ID | 결정 | 근거 |
|---|---|---|
| DS-01 | 탭 4개: 스캔 / 단어장 / 퀴즈 / 설정. 탭마다 `NavigationStack` | `Kanjiyomi/ContentView.swift` |
| DS-02 | 사전 검색은 탭이 아니라 단어장 툴바에서 들어간다 | `Kanjiyomi/Features/Vocabulary/VocabularyView.swift` |
| DS-03 | 스캔 결과는 사진 위에 드래그 가능한 단어 패널(바텀시트)을 겹친다. 처음엔 펼친 상태 | `Kanjiyomi/Features/Scan/ScanResultView.swift` |
| DS-04 | 단어를 고르면 패널을 접고 사진을 그 단어로 확대한다(최대 6배) | `ScanResultView.swift` |
| DS-05 | 단어장 저장은 사용자가 요청할 때만 한다. iOS 26 이상은 탭 바 액세서리 + 확인 창, 그 이하는 패널 안 저장 바 + 토스트 | `ContentView.swift`, `ScanResultView.swift` |
| DS-06 | ChatGPT 모드는 기본 모드로 기억하지 않는다. 사전·AI 모드만 `@AppStorage("wordSegmentation")`에 남긴다 | `Kanjiyomi/Features/Scan/ScanView.swift`, `ScanViewModel.swift` |
| DS-07 | 스캔 화면 상태는 탭을 옮겨도 유지한다 (`ScanViewModel`을 `ContentView`가 보유) | `ContentView.swift` |
| DS-08 | 길게 누르거나 복사 버튼으로 표제어를 복사하고 토스트로 알린다 | `ScanResultView.swift`, `WordDetailView.swift` |
| VD-01 | 토스 스타일: 밝은 회색 배경, 흰 카드, 파란 포인트 색 | `Kanjiyomi/DesignSystem/Colors.swift` |
| VD-02 | 라이트 모드 고정. 영역 선택 화면만 다크 | `ContentView.swift`, `RegionSelectView.swift` |
| VD-03 | 글꼴은 시스템 글꼴만 쓴다 | `Kanjiyomi/DesignSystem/Typography.swift` |
| VD-04 | 앱 아이콘은 최초 확대안에서 약 10% 축소한다. 스캐너 프레임은 정중앙의 정사각형으로 배치하고, 상하좌우 바깥 여백을 동일하게 둔다 (사용자 수정, 2026-10-15) | `Kanjiyomi/Assets.xcassets/AppIcon.appiconset/Kanjiyomi-AppIcon.png` |
| VD-05 | 런치스크린은 아이콘 배경에서 추출한 파란색 `#0274FD`로 화면 전체를 채우고, 동일한 앱 아이콘을 160×160pt로 정중앙에 표시한다. iOS 기본 런치스크린을 사용한다 (사용자 수정, 2026-10-15) | `Kanjiyomi/LaunchScreen.storyboard`, `Assets.xcassets/LaunchIcon.imageset/` |
| DS-09 | 사전 데이터 출처는 설정에서 들어가는 별도 "오픈소스·라이선스" 화면(S-13)에 둔다 (사용자 확정, 2026-10-15) | `Kanjiyomi/Features/Settings/LicensesView.swift` |
| DS-10 | 화면 방향은 세로만 지원한다 (사용자 확정, 2026-10-15) | `project.pbxproj` (`UISupportedInterfaceOrientations_iPhone`) |
| DS-11 | 단어 상세의 스피커를 누르면 일본어 읽기를 기기 음성으로 들려준다 (사용자 확정, 2026-10-15) | `Kanjiyomi/Services/Pronouncer.swift` |
| DS-13 | 시스템 권한 요청 문구(카메라·사진)는 한국어·일본어로 현지화하고, 그 밖의 언어에는 영어로 보여 준다 (사용자 확정, 2026-10-15). 앱 화면은 한국어뿐이다 | `Kanjiyomi/InfoPlist.xcstrings` |
| DS-14 | 사전 모드·검색·관련 단어는 번들 한국어 뜻을 우선 표시한다. 한국어 미수록 단어는 기존 AI/영어 대체 표시를 유지하며, 기존 저장 단어·스캔 기록은 자동 덮어쓰지 않는다 | 한국어 사전 도입, 구현 완료 (2026-10-15) |
| DS-12 | 카메라 권한이 거부되면 설정 앱으로 가는 안내를 보여 준다. 앨범은 PHPicker라 권한이 필요 없다. 기본값 (검토 필요) | `Kanjiyomi/Features/Scan/ScanView.swift` (`openCamera`) |

## 온보딩 결정 (2026-10-16)

| ID | 결정 | 상태 |
|---|---|---|
| DS-15 | 첫 실행에 S-14 온보딩을 전체 화면으로 표시한다. 기본 사용·사전의 한계 / 세 모드 비교·현재 기기 AI 상태 / GPT의 장점·설정 방법·비용·전송 정보를 3단계로 안내한다. 설정에서 다시 볼 수 있고, 건너뛰거나 키 없이 시작할 수 있다 | 구현 완료 (2026-10-16) |
| DS-16 | 온보딩의 API 키 설정 버튼은 기존 설정 탭으로 이동한다. 키 등록이나 모드 전환·유료 요청은 자동 실행하지 않는다. GPT 예문 생성은 지원한다고 안내하지 않는다 | 구현 완료 (2026-10-16) |
| DS-17 | 하단 이전·다음을 같은 줄에 배치하고 마지막 단계는 이전·바로 시작하기로 표시한다. API 키 설정은 마지막 본문으로 옮긴다. 문구·예시·여백을 압축해 기본 글씨의 작은 iPhone에서도 스크롤 없이 읽는 것을 목표로 하며, 큰 글씨·더 작은 공간에서는 스크롤을 허용한다 | 반영 완료, SE 기본 글씨에서 세 단계 무스크롤 검증 (2026-10-16) |

## 온보딩 시각 개선 (2026-10-16)

| ID | 결정 | 상태 |
|---|---|---|
| DS-18 | 진행바 아래 본문 시작 여백을 32pt, 본문 묶음 간격을 20pt로 늘리고 설명 행의 제목·본문 간격과 줄 간격을 정돈한다. GPT 화면은 세 단계 아이콘 흐름과 요금·개인정보 아이콘 행으로 구성하며 키 등록 단계에서 기존 설정을 연다. 하단 가로 탐색과 큰 글씨 스크롤은 유지한다 | 반영 완료, SE 기본 글씨·UI 회귀 테스트 2개 통과 |
| DS-19 | GPT 본문도 2페이지와 같은 `KYCard` 한 장·16pt 행 간격·구분선·일반 SF Symbol 제목/설명 행으로 통일한다. 별도 원형 단계 아이콘은 없애고 사용 순서는 첫 행에 넣는다. 첫 행은 키 설정, 두 번째 행은 요금 안내 링크를 유지한다 | 반영 완료, SE 기본 글씨·UI 회귀 테스트 2개 통과 |

## 개인정보 처리방침 접근 (2026-10-16)

| ID | 결정 | 근거 |
|---|---|---|
| DS-20 | 설정 → 개인정보에 "개인정보 처리방침" 링크를 두고 게시된 전체 처리방침을 기본 브라우저에서 연다. 기존 요약 안내는 유지한다 | [Apple 심사 지침 5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/), 앱 안에서 쉽게 접근 가능한 처리방침 링크 요구 |

검증: 시뮬레이터 빌드 통과. iPhone 17 Pro(iOS 26.5)에서 설정 링크를 눌러 Safari에 전체 처리방침이 표시되는 것을 확인했다. 게시 URL HTTP 200 확인. 실기기는 미확인.

## 결정 대기

- 오프라인 안내 (지금은 ChatGPT 오류 문구로만 드러남)
- 다크 모드 지원
