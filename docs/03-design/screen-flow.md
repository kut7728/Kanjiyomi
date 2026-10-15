# 화면 목록과 이동 흐름

[03 화면 설계](README.md)

## 화면 목록

| ID | 화면 | 코드 | 들어가는 방법 | 기능 |
|---|---|---|---|---|
| S-01 | 스캔 홈 | `ScanView` (`Kanjiyomi/Features/Scan/ScanView.swift`) | 스캔 탭 | F-01, F-07 |
| S-02 | 스캔 결과 | `ScanResultView` | S-01에서 사진을 고르거나 기록을 탭하면 같은 자리에서 바뀜 | F-02~F-06 |
| S-03 | 카메라 | `CameraPicker` (`ImagePickers.swift`) | S-01 "카메라로 촬영" (전체 화면) | F-01 |
| S-04 | 앨범 선택 | `LibraryPicker` (PHPicker, 사진 1장) | S-01 "앨범에서 선택" (시트) | F-01 |
| S-05 | 영역 선택 | `RegionSelectView` | S-02 툴바 "영역 선택" (전체 화면) | F-06 |
| S-06 | 단어 상세 | `WordDetailView` (`Kanjiyomi/Features/WordDetail/`) | S-02 말풍선, S-07 행, S-08 결과, S-06 안의 "새로 볼 단어" (push) | F-08, F-12 |
| S-07 | 단어장 | `VocabularyView` | 단어장 탭 | F-09 |
| S-08 | 사전 검색 | `DictionarySearchView` | S-07 툴바 "사전 검색" (push) | F-10 |
| S-09 | 퀴즈 설정 | `QuizView` 설정 상태 | 퀴즈 탭 | F-11 |
| S-10 | 퀴즈 문제 | `QuizView` 진행 상태 | S-09 "퀴즈 시작" | F-11 |
| S-11 | 퀴즈 결과 | `QuizView` 결과 상태 | S-10 마지막 문제 "결과 보기" | F-11, F-12 |
| S-12 | 설정 | `SettingsView` | 설정 탭 | F-13 |
| S-13 | 오픈소스·라이선스 | `LicensesView` (`Kanjiyomi/Features/Settings/LicensesView.swift`) | S-12 "오픈소스·라이선스" (push) | F-15 |
| S-14 | 사용 안내 온보딩 | `OnboardingView` | 첫 실행 또는 S-12 "사용 방법·모드 안내" (전체 화면) | 기본 사용법·제한·모드·API 안내 |

확인 창: 단어장 저장 확인(iOS 26 이상), 단어 일괄 삭제, API 키 삭제, 카메라 접근 꺼짐.

## 탭 구조

```
TabView
├── 스캔      text.viewfinder        S-01 ⇄ S-02 → S-05 / S-06
├── 단어장    bookmark.fill          S-07 → S-06, S-08 → S-06
├── 퀴즈      checkmark.circle.fill  S-09 → S-10 → S-11
└── 설정      gearshape.fill         S-12 → S-13
```

iOS 26 이상에서는 아래로 스크롤하면 탭 바가 작아지고(`tabBarMinimizeBehavior(.onScrollDown)`), 저장하지 않은 스캔 결과가 있으면 어느 탭에서든 탭 바 위에 저장 액세서리가 뜹니다.

## 이동 흐름

첫 실행: S-14 (3단계) → "바로 시작하기" / "나중에 보기" → S-01. 마지막 단계의 "API 키 설정하기" → S-12. 완료 여부는 기기에 저장한다. S-12에서 S-14를 다시 열면 닫거나 API 설정으로 돌아올 수 있다. 표시 자체로 권한 요청이나 네트워크 요청을 하지 않는다.

```
S-01 스캔 홈
 ├─ 카메라로 촬영 → S-03 ─┐
 ├─ 앨범에서 선택 → S-04 ─┼→ 인식 → S-02 스캔 결과
 └─ 인식 기록 행 탭 ──────┘        ├─ 영역 선택 → S-05 → 적용 → S-02
                                   ├─ 단어 나누기 메뉴 → 다시 인식 → S-02
                                   ├─ 단어 탭 → 사진 확대 + 말풍선 → 말풍선 탭 → S-06
                                   └─ 홈 → S-01

S-06 단어 상세
 ├─ "새로 볼 단어" 탭 → S-06 (위에 쌓임)
 └─ "이 단어가 나온 스캔 보기" → 화면 닫기 → 스캔 탭 S-02 (그 단어 선택)
```

"이 단어가 나온 스캔 보기"는 `ScanRouter`(`Kanjiyomi/Features/Scan/ScanRouter.swift`)로 요청을 넘기고, `ContentView.reveal`이 스캔 탭으로 바꿔 기록을 엽니다. 기록이 지워졌으면 아무 일도 하지 않습니다.
