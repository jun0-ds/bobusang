# Changelog — bobusang (보부상)

All notable changes to bobusang. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

**Versioning policy**: SemVer 태그는 *기록·마일스톤* 목적으로 단다 — 외부 사용자/트리거를 기다리지 않는다 (2026-05-26 stance 정정: sonmat도 사용자가 아닌 plugin 메커니즘·기록으로 태깅을 시작했다). 0.x는 API 안정 전 baseline 스냅샷. SHA 단위는 `git log`, 사람이 읽는 요약은 이 파일.

**Scope**: 디바이스 싱크 인프라 — 멀티 디바이스 메모리·설정 sync + marker block 도구 + 암호화 엔진 설계. CLI tool + setup script.

---

## [Unreleased]

_(다음 변경 누적)_

## [0.1.0] - 2026-05-26

첫 SemVer baseline — 기록·마일스톤 도장 (소비자 대기 X). marker block 도구(`setup.sh` `install_or_update_marker_block` + `templates/sync-section.md`)와 v2.2 transcrypt 암호화 설계·Spike 4건이 안정 표면.

### Added (2026-05-13~14)
- `install_or_update_marker_block` 함수 (`setup.sh`) — 외부 파일의 marker block (`<!-- bobusang:start --> ... <!-- bobusang:end -->`)을 idempotent install/update. dry test 통과
- `setup.sh` step 6.5 — `~/.claude/CLAUDE.md` §6 sync section 자동 install (marker block 패턴 첫 실증)
- `templates/sync-section.md` — marker block 안에 들어갈 본문 (sync 절차·커밋 컨벤션 등)
- `README.md` "Marker block pattern" 절 — 외부 사용자가 자기 도구에 같은 패턴 도입할 수 있는 reference

### Changed (2026-05-25)
- `templates/sync-section.md` — §6 sync 절 예시를 **env redirect 체계**로 갱신: sonmat state(scribe·memory)가 `.claude` 밖으로 이전되며 backward-compat symlink 2개(`~/.claude/sonmat/memory`, `~/control-tower/.claude/sonmat`) 은퇴 (sonmat v0.14.0 연계, 2026-05-23). maintainer instance(jun0-ds) 토폴로지 반영 — fork 시 교체 대상

### Changed (2026-05-22)
- `templates/sync-section.md` 를 CLAUDE.md §6 전체 수준으로 확장 (브랜치 전략·두 리포 구조·자동/수동 sync·커밋 컨벤션·attribution·새 세션 권장). CLAUDE.md 카드 보드 전환(A 트랙)에서 §6 통째를 marker block으로 대체하기 위함. 상단에 "maintainer instance 예시 — fork 시 교체" 주석 + attribution 절 generic화(특정 user 값 제거)로 OSS portability 유지. sandbox 함수 검증 완료(5/20)

### Changed (2026-05-13)
- License: MIT → BSD 3-Clause (sonmat·munteok 패턴 정합)

---

## [2026-04-14 ~ 2026-05-13 — v2.2 설계 + 검증]

### Added/Changed
- v2.1 (`<private>` 태그 + git clean filter) 폐기, v2.2 git-crypt 설계로 전환 (`7b6ddc9`)
- devil 8개 지적 반영 (`8d5c50f`)
- claude-mem prior art 크레딧 (`fce8f21`)
- v2.2 rev 3 — 엔진 git-crypt → **transcrypt 전환** + 생태계 감사 (`40502e5`)
- Spike 검증 4건:
  - Spike A: transcrypt full-stack + bash 감사 통과 (`280be8c`)
  - Spike B: git-crypt merge breakage 재현 (`cc4a07d`)
  - Spike C: pre-commit 훅 신뢰성 + 레퍼런스 구현 (`51a4b08`)
  - Spike D: transcrypt merge edge cases (critical 발견 1건) (`f2c75d5`)
- FAQ SEO/GEO 확장 (`95e90b3`)

### Notes
- 암호화 엔진 v2.2 rev 3 확정 — transcrypt 채택 후 production 운용은 후속 단위

---

## [2026-04-08 — initial]

### Added
- 초기 구조 (`d24c6cb`) — 3-tier 메모리 + 멀티디바이스 싱크 design
- 태그라인 확정 — 일상체감 한글 + 불편한진실 영문 (`f841b9a`)

---

## Conventions

- **setup.sh / CLI 동작 변화**는 *Added*/*Changed* 절 (외부 사용자에게 직접 영향)
- **암호화·sync 엔진 설계 변화**는 *Changed* 절 + Notes에 trade-off
- **devil·Spike·외부 감사 결과**는 누적 박음 (검증 흔적은 외부 신뢰의 자리)
- 작은 typo·문구 조정은 기록 안 함 (`git log`만)

## Related repos

- 문턱 framework: [`jun0-ds/munteok`](https://github.com/jun0-ds/munteok) (bobusang을 `bedrock/bobusang` submodule로 mount)
- 손맛 (thinking discipline): [`jun0-ds/sonmat`](https://github.com/jun0-ds/sonmat)
