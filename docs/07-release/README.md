# 07 출시 준비

| 항목 | 내용 |
|---|---|
| 문서 상태 | 코드 기준 v1 (2026-10-12), 출시 결정 반영 (2026-10-15) |
| 작성일 | 2026-10-12 |
| 이전 문서 | [06 테스트](../06-testing/README.md) |
| 다음 문서 | — |

목표는 **App Store 출시**입니다. 아직 출시하지 않았습니다. 저장소 안 작업은 [M9](../05-implementation/milestones.md#m9-출시-준비-코드문서), 사람이 할 제출 작업은 [M10](../05-implementation/milestones.md#m10-제출-사용자)입니다.

법률 자문 아님 · 확인 필요.

## 문서 목록

| 문서 | 내용 |
|---|---|
| [store-listing.md](store-listing.md) | 스토어 이름·부제·설명·키워드·심사 노트 (한국어·일본어) |
| [privacy.md](privacy.md) | 개인정보 처리 현황, App Store 개인정보 라벨, 처리방침 위치 |
| [launch-checklist.md](launch-checklist.md) | 제출 전 확인, 예상 반려와 대응, 출시 후 운영 |

## 결정

| ID | 결정 | 근거 |
|---|---|---|
| RL-01 | iPhone 전용, iOS 18.0 이상 | `Kanjiyomi.xcodeproj/project.pbxproj` |
| RL-02 | 소스는 GitHub `kut7728/Kanjiyomi`에서 관리하고, README에 데이터 라이선스를 적는다 | `README.md` |
| RL-03 | 출시 목표는 App Store (2026-10-12 확정) | [01 기획](../01-planning/product-requirements.md) |
| RL-04 | Bundle ID는 `my.kanji.app` (2026-10-15 확정) | `project.pbxproj` |
| RL-05 | 출시 국가는 대한민국·일본, 가격은 무료 (2026-10-15 확정) | — |
| RL-06 | 개인정보 처리방침·지원 페이지는 이 저장소 `site/`를 GitHub Pages로 게시한다 (2026-10-15 확정) | `site/`, `.github/workflows/pages.yml` |
| RL-07 | 소스 코드 라이선스는 두지 않는다 (All rights reserved). 사전 데이터는 원래 라이선스를 따른다 (2026-10-15 확정) | `README.md` |
| RL-08 | 문의 창구는 kut.support@gmail.com (2026-10-15 확정) | `site/` |
| RL-09 | 스토어 이름은 "Kanjiyomi - 일본어 사진 번역", 홈 화면 이름은 "Kanjiyomi" (2026-10-15 확정) | [store-listing.md](store-listing.md) |
| RL-10 | 개인정보 라벨은 "기타 사용자 콘텐츠 · 앱 기능 · 사용자와 연결 안 됨 · 추적 없음" (2026-10-15 확정) | [privacy.md](privacy.md#app-store-개인정보-라벨) |
| RL-11 | 첫 출시 버전은 1.0 (1) | `project.pbxproj` |
| RL-12 | 한국어 보조 사전 출처를 앱·README·스토어 설명에 추가하고, 미수록 단어의 영어 대체 표시와 데이터 공개 다운로드를 출시 전 확인한다 | TD-21, 한국어 사전 도입 |

## 게시 URL (GitHub Pages를 켠 뒤)

| 페이지 | URL |
|---|---|
| 개인정보 처리방침 | https://kut7728.github.io/Kanjiyomi/privacy/ |
| 지원 | https://kut7728.github.io/Kanjiyomi/support/ |

저장소가 공개이고 Pages가 켜져 있어야 열립니다 ([setup-checklist](../05-implementation/setup-checklist.md#app-store-제출)).

## 출시 전 빠진 것

| 항목 | 담당 | 상태 |
|---|---|---|
| `PrivacyInfo.xcprivacy` | Claude | 완료 (M9) |
| 처리방침·지원 페이지 파일 (`site/`), Pages 워크플로 | Claude | 완료 (M9). 게시는 Pages를 켠 뒤 |
| 앱 안 데이터 출처 표기 (S-13) | Claude | 완료 (M9) |
| 스토어 등록 정보 초안 | Claude | 완료 (M9) |
| Apple Developer Program 가입, App Store Connect 등록 | 사용자 | M10 |
| 저장소 공개, Pages 켜기 | 사용자 | M10 |
| 스토어 규격 스크린샷 | 사용자 | M10 |

## 결정 대기

- 목표 제출 시점
