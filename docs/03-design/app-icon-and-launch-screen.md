# 앱 아이콘과 런치스크린

## 결정

| ID | 결정 | 근거 |
|---|---|---|
| VD-04 | 기존 아이콘 구성을 확대하되 최초 확대안에서 약 10% 축소한다. 스캐너 프레임은 정중앙에 배치하며 상하좌우 여백은 각각 133px이다. | `Kanjiyomi/Assets.xcassets/AppIcon.appiconset/Kanjiyomi-AppIcon.png` |
| VD-05 | 런치스크린 전체를 아이콘 배경에서 추출한 파란색 `#0274FD`로 채우고, 동일한 아이콘을 160×160pt로 정중앙에 표시한다. | `Kanjiyomi/LaunchScreen.storyboard` |

## 구현과 유지 관리

- 앱 아이콘은 1024×1024 PNG이며 알파 채널이 없다.
- `LaunchIcon.imageset`은 앱 아이콘과 동일한 PNG를 사용한다. 아이콘을 변경하면 런치스크린 이미지와 배경색도 함께 갱신한다.
- Debug·Release 모두 `UILaunchStoryboardName = LaunchScreen`으로 iOS 기본 런치스크린을 사용한다.
- 런치스크린의 배경은 안전 영역 바깥까지 채우며, 중앙 이미지는 비율을 유지한다.

## 확인

- Xcode 시뮬레이터 빌드 및 에셋 컴파일 통과.
- iPhone 17 Pro 시뮬레이터에서 런치스크린과 앱 진입 확인. 실기기 확인은 하지 않았다.
