# 시각 디자인

[03 화면 설계](README.md) · 근거: `Kanjiyomi/DesignSystem/`

## 색

모두 고정 sRGB 값입니다. 다크 모드용 값은 없습니다. (`Colors.swift`)

| 이름 | 값 | 쓰임 |
|---|---|---|
| `background` | #F2F4F6 | 화면 배경 |
| `card` | #FFFFFF | 카드 |
| `primary` | #3182F6 | 버튼, 한글 발음, 선택 테두리, 말풍선 |
| `textPrimary` | #191F28 | 본문 |
| `textSecondary` | #8B95A1 | 보조 글자 |
| `highlight` | #3182F6, 불투명도 0.28 | 사진 위 단어 박스 채움 |
| `highlightBorder` | #3182F6 | 사진 위 단어 박스 테두리 |
| `danger` | #F04452 | 오류, 오답 |
| `success` | #03B26C | 정답, "학습함", "단어장에 저장됨" |

`Assets.xcassets/AccentColor.colorset`은 값이 비어 있습니다.

## 글자

시스템 글꼴만 씁니다. (`Typography.swift`)

| 이름 | 크기 / 굵기 |
|---|---|
| `largeTitle` | 28 / bold |
| `title` | 22 / bold |
| `headline` | 18 / bold |
| `body` | 16 / semibold |
| `callout` | 15 / medium |
| `caption` | 13 / medium |
| `kanji` | 40 / bold |

## 컴포넌트

(`Components.swift`)

| 이름 | 모양 |
|---|---|
| `KYCard` | 안쪽 여백 20, 모서리 20(continuous), 그림자 검정 0.06 / 반경 12 / y 4 |
| `KYPrimaryButton` | 파란 바탕 흰 글자, 위아래 여백 16, 모서리 16. 비활성은 `textSecondary` 0.4 |
| `KYSecondaryButton` | 파랑 0.12 바탕 파란 글자, 모서리 16 |
| `KYDotLoadingView` | 10pt 점 3개, 0.28초마다 차례로 커짐 |
| `KYLoadingOverlay` | 모서리 24, 최소 폭 240, 문구가 위아래로 바뀜 |
| `SpeechBubble` | 파란 바탕, 모서리 14, 아래쪽 꼬리 |
| `KYCopyToast` | 캡슐, `textPrimary` 0.88, 아래에서 올라옴 |

그 밖의 모서리: 기록 썸네일 12, 영역·저장 바 14, 퀴즈 보기 16, 단어 패널 위쪽 24.

## 움직임

스프링 애니메이션을 씁니다. 선택 0.4/0.85, 확대 0.42/0.86, 패널 0.38/0.85 (response/damping).

## 앱 아이콘

`Assets.xcassets/AppIcon.appiconset/Kanjiyomi-AppIcon.png` 1장(1024×1024, 알파 없음). 다크·틴트 아이콘은 비어 있습니다.

VD-04: 파란 배경・한자 카드・흰 스캐너 프레임의 구성을 유지하며 최초 확대안에서 약 10% 축소한다. 스캐너 프레임은 아이콘 정중앙에 정사각형으로 배치하고, 프레임 바깥 경계와 아이콘 가장자리 사이의 상하좌우 여백을 동일하게 둔다. 여백은 아이콘 한 변의 약 13%로 둔다.

## 런치스크린

VD-05: `LaunchScreen.storyboard`를 iOS 기본 런치스크린으로 사용한다. 아이콘 배경에서 추출한 파란색 `#0274FD`로 안전 영역 바깥까지 화면 전체를 채워 중앙 이미지와 자연스럽게 이어지게 한다. 아이콘은 가로·세로 160pt로 표시하며 화면 전체의 정중앙에 고정하고 비율을 유지한다. `Assets.xcassets/LaunchIcon.imageset/`에는 현재 앱 아이콘과 동일한 PNG를 사용하며, 아이콘 변경 시 배경색과 함께 갱신한다.

## 결정 대기

- 다크 모드 색
- 명도 대비 검사 (`textSecondary` #8B95A1 on #FFFFFF 등은 계산하지 않음)
- 다크·틴트 앱 아이콘
