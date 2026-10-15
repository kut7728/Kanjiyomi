# 준비 체크리스트

[05 구현](README.md)

실제 키·비밀번호는 채팅이나 문서에 쓰지 마세요.

## 빌드·실행

- [ ] Git LFS 설치: `git lfs install`
- [ ] 저장소 clone 후 `Kanjiyomi/Resources/jmdict.sqlite`가 실제 DB(약 119MB)인지 확인. 130바이트쯤이면 LFS 포인터이므로 `git lfs pull`
- [ ] Xcode 26 이상 (코드가 iOS 26 SDK의 API를 쓴다)
- [ ] Xcode → Kanjiyomi 타깃 → Signing & Capabilities에서 본인 Team 선택 (실기기 실행 시)

## 사전 DB를 다시 만들 때

- [ ] Python 3
- [ ] `python3 tools/build_dict.py` (EDRDG·Unicode에서 원본을 내려받는다)

## ChatGPT 모드를 쓸 때

- [ ] [platform.openai.com](https://platform.openai.com/api-keys)에서 API 키 발급 (요금은 본인 계정)
- [ ] OpenAI 콘솔에서 사용 한도 설정 (앱 안에는 한도가 없다)
- [ ] 앱 설정 탭 → "OpenAI API 키"에 직접 입력
- [ ] 키를 다른 곳에 붙여 넣었다면 폐기하고 새로 발급

## AI 모드를 쓸 때

- [ ] iOS 26 이상, Apple Intelligence를 지원하고 켠 실기기 (시뮬레이터에서는 쓸 수 없었다)

## App Store 제출

M10 작업입니다. 위치는 바뀔 수 있습니다 (미검증).

1. [ ] [developer.apple.com](https://developer.apple.com/programs/)에서 Apple Developer Program 가입 (유료). 현재 프로젝트 팀 `S27R5C5NF6`가 유료 팀인지 확인
2. [ ] GitHub 저장소 Settings → General → Danger Zone → Change visibility → Public
3. [ ] GitHub 저장소 Settings → Pages → Build and deployment → Source를 **GitHub Actions**로
4. [ ] Actions 탭에서 "Pages" 워크플로가 통과하고 처리방침·지원 URL이 열리는지 확인
5. [ ] App Store Connect → 앱 → 새로운 앱: 플랫폼 iOS, 이름 "Kanjiyomi - 일본어 사진 번역", 기본 언어 한국어, Bundle ID `my.kanji.app`
6. [ ] 가격 및 사용 가능 여부: 무료, 국가는 대한민국·일본
7. [ ] 앱 개인정보: [07 privacy.md](../07-release/privacy.md#app-store-개인정보-라벨)대로 입력, 처리방침 URL 입력
8. [ ] 앱 정보: [07 store-listing.md](../07-release/store-listing.md)의 문구 붙여 넣기
9. [ ] Xcode → Product → Archive → Distribute App → App Store Connect 업로드
10. [ ] TestFlight로 실기기 확인 ([launch-checklist.md](../07-release/launch-checklist.md))
11. [ ] 스크린샷 업로드, 심사 노트 입력, 심사 제출
