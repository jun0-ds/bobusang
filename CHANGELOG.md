# Changelog — bobusang (보부상)

All notable changes to bobusang. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

**Versioning policy**: SemVer tag held back until external fork·breaking change·sustained API surface triggers it. Until then, changes accumulate under *Unreleased*.

**Scope**: 디바이스 싱크 인프라 — 멀티 디바이스 메모리·설정 sync + marker block 도구 + 암호화 엔진 설계. CLI tool + setup script.

---

## [Unreleased]

### Added (2026-05-13~14)
- `install_or_update_marker_block` 함수 (`setup.sh`) — 외부 파일의 marker block (`<!-- bobusang:start --> ... <!-- bobusang:end -->`)을 idempotent install/update. dry test 통과
- `setup.sh` step 6.5 — `~/.claude/CLAUDE.md` §6 sync section 자동 install (marker block 패턴 첫 실증)
- `templates/sync-section.md` — marker block 안에 들어갈 본문 (sync 절차·커밋 컨벤션 등)
- `README.md` "Marker block pattern" 절 — 외부 사용자가 자기 도구에 같은 패턴 도입할 수 있는 reference

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
