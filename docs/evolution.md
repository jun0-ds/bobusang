# Evolution

De-identified commit timeline from the private config repository.
Device names replaced: `DEVICE-A` (main laptop), `DEVICE-B` (sub laptop), `DEVICE-C` (GPU dev server), `DEVICE-D` (GPU prod server).

## Phase 0 — Bootstrap (Day 1)

```
be196ba Initial commit: Claude Code 설정 및 memory 싱크
dee6f24 Add git pull hook and update .gitignore
b22220c Sync desktop PC: merge local state with remote config
1e2cfb3 Clean up: remove session/todo artifacts, update .gitignore
```

Flat structure. Manual git push/pull. No device awareness.

## Phase 1 — Device awareness (Day 2)

```
7de098b Add device identification by hostname
9f3292b Update device table: add user column, WSL2 info
13cc8dd Standardize cross-device settings: split local config, add setup guide
326a898 Add per-device settings: hostname-based auto-apply on session start
686f9fe Update device setup guide: settings.local.d structure
```

Hostname detection. `settings.json` (shared) vs `settings.local.json` (device-specific) split.

## Phase 2 — Memory hierarchy (Day 3)

```
3c3c0cd Add thinking discipline, memory system, sync conversation history
9884aac feat: 버저닝 체계 도입 (VERSIONING.md)
a53e016 feat(v1.0.0): 메모리 계층화 + JSONL 싱크 제외
5fde472 cleanup: 중복 메모리 파일 21개 정리 + 리포 맵 추가
a31a8be cleanup: 레거시 글로벌 메모리 9개 삭제
```

First memory categorization. 30 duplicate/legacy files cleaned up. Versioning introduced.

## Phase 3 — Device branches (Day 4) *(the mistake)*

```
31ff104 feat(v1.1.0): 디바이스 브랜치 전략 도입 (RFC-001 완료)
87a0030 docs: 브랜치 플로우 다이어그램 추가
0869359 feat: settings.local.d WSL/Win 분리 + 디바이스명 통일
ad829a4 chore(gpu-dev): v1.1.0 체크리스트 완료 + 프로젝트 메모리 동기화
2b06645 docs: main 머지 권한을 메인 노트북 WSL로 한정
49c69bd Merge remote-tracking branch 'origin/device/gpu-dev'
85017e7 sync: 스크래치패드 머지 충돌 해결 (DESKTOP + gpu-dev 양쪽 체크 통합)
32c02ce Merge branch 'device/sub-wsl'
```

Each device got its own branch (`device/main-wsl`, `device/sub-wsl`, `device/gpu-dev`).
Sounded elegant. In practice: constant merge conflicts, session time wasted on resolution, merge权限 restricted to one device to avoid chaos.

**Lesson: device branches don't work for config repos.** The files are small, change often, and need instant visibility across all devices. Branches add friction without benefit.

## Phase 4 — Single branch + auto-sync (Day 5)

```
0ba48bf sync: v2.0.0 설계 메모 (DEVICE-A)
f3b50ae feat: device 브랜치 글로벌 메모리 통합 (v2.0.0 Step 1)
4a6262b feat: NOTES.md → notes/ 기기별 분리 (v2.0.0 Step 2)
2dd9396 feat: 프로젝트 메모리 졸업 + gitignore (v2.0.0 Step 3)
9af14b2 feat: v2.0.0 Step 4~7 — single branch 싱크 전환
82471aa feat: sync-memory.sh 도입 — SessionStart 자동 싱크
```

All branches merged back into `main`. Auto-sync hook: stash → rebase → pop → commit → push. Device-specific notes moved to `notes/{hostname}.md`.

## Phase 5 — 3-tier memory (Day 6)

```
eba8a96 feat: 메모리 계층화 — core/domain/archive 3tier 구조
3ed9b1e sync: [구조변경] settings.json 상대경로 통일 + 노트 생성 (DEVICE-A)
```

Memory split into core (always loaded), domain (lazy), archive (cold). `[구조변경]` commit tagging introduced for cross-device config change detection.

## Current state

```
~/.claude/
├── memory/
│   ├── core/      2 files   (~4KB total, loaded every session)
│   ├── domain/    25 files  (index only, read on demand)
│   └── archive/   20 files  (cold storage)
├── hooks/         2 scripts (sync + detect-changes)
├── notes/         3 files   (2 device-specific + 1 shared)
└── settings.json  1 file    (relative paths, no device-specific values)
```

Total elapsed time from first commit to current state: **7 days**.
