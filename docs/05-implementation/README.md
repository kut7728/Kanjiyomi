# 05 구현

| 항목 | 내용 |
|---|---|
| 문서 상태 | 코드 기준 v1 (2026-10-12) |
| 작성일 | 2026-10-12 |
| 이전 문서 | [04 기술 설계](../04-technical/README.md) |
| 다음 문서 | [06 테스트](../06-testing/README.md) |

## 문서 목록

| 문서 | 내용 |
|---|---|
| [milestones.md](milestones.md) | 완료한 마일스톤(git 이력 기준)과 M8~M10 출시 작업 |
| [setup-checklist.md](setup-checklist.md) | 빌드·실행과 App Store 제출에서 사람이 직접 할 일 |

## 준비 상태

- F-01~F-15는 모두 코드에 있습니다. M8·M9(Claude 작업)를 마쳤고, M11(오프라인 한국어 뜻)·M12(사용 안내 온보딩)도 마쳤으며, 남은 것은 M10(사용자 제출 작업)입니다. 아직 출시 전입니다.
- 2026-08-09 ~ 2026-08-23에 기능을 만들었고, 2026-10-04에 README·CI·한글 발음 수정을 더했습니다.
- `main`에 바로 커밋합니다. PR은 1개(#1)뿐입니다.

## 결정

| ID | 결정 | 근거 |
|---|---|---|
| IM-01 | 배포 타깃을 iOS 26에서 18로 낮추고, iOS 26 기능은 `#available`과 `#if canImport(FoundationModels)`로 나눈다 | 커밋 `70156b5`, `MeaningService.swift`, `OCRService.swift` |
| IM-02 | 사전 DB는 Git LFS로 저장소에 넣는다 | 커밋 `5725966`, `.gitattributes` |
| IM-03 | `main`에 push하거나 PR을 올리면 GitHub Actions가 단위 테스트를 돌린다 | `.github/workflows/test.yml` |
| IM-04 | 사양이 바뀌면 `docs/`를 먼저 고친다. 턴 끝 훅이 이를 확인한다 | `AGENTS.md`, `.cursor/hooks/spec-docs.py` |
| IM-05 | 목표는 App Store 출시. 출시 전 필수 작업을 M8·M9로 잡는다 (사용자 확정, 2026-10-12) | [01 기획](../01-planning/product-requirements.md) |
| IM-06 | 알려진 문제 7건을 모두 고치고, 고친 항목마다 테스트를 추가한다 (TD-13) | [04 기술](../04-technical/README.md#알려진-문제) |
| IM-07 | 순서는 M8 → M9(Claude) → M10(사용자) (사용자 확정, 2026-10-15) | [milestones.md](milestones.md) |
| IM-08 | 한국어 보조 DB·재현 가능한 빌드 스크립트·출처 메타데이터·표본 검수를 추가한다. 보조 DB는 일반 Git으로 배포해 LFS 없는 CI에서도 작은 fixture로 검증한다 | 한국어 사전 도입, 구현 완료 (2026-10-15) |
| IM-09 | 공용 사전 백엔드는 보류하고, 로컬 기능과 선택적 GPT 사용을 설명하는 3단계 온보딩을 추가한다. 기존 키 입력·모드 선택·과금 흐름을 재사용한다 | M12 구현 완료, UI 회귀 테스트 2개 통과 (2026-10-16) |

## 결정 대기

- 목표 제출 시점
