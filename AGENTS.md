# 작업 규칙

## 사양 문서

- 설계 문서는 `docs/`다. 시작점은 [docs/README.md](docs/README.md).
- 사양·동작·화면·API·데이터 모델이 바뀌면 코드를 더 쓰기 전에 `docs/`와 해당 단계 `README.md`의 결정 표를 고친다.
- 미구현을 완료로 쓰지 않는다. 정하지 않은 것은 '결정 대기'에 둔다.
- 이전 문서는 `legacy/`에 있다. 참고만 하고 고치지 않는다.

## 프로젝트

- iOS 앱(SwiftUI, iOS 18.0+, iPhone). 외부 패키지 없음.
- 사전 DB `Kanjiyomi/Resources/jmdict.sqlite`는 Git LFS다. CI는 LFS를 받지 않으므로 단위 테스트에서 이 DB를 쓰지 않는다.
- 단위 테스트: `xcodebuild test -project Kanjiyomi.xcodeproj -scheme Kanjiyomi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:KanjiyomiTests`
- API 키·토큰을 코드·문서·커밋에 쓰지 않는다.
