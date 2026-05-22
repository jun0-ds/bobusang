> 이 절은 bobusang setup.sh가 marker block(`<!-- bobusang:sync:start/end -->`)으로 install/update — marker 밖 본문(절 헤더·owner 주석)은 보존, marker 안은 다음 setup.sh 실행 시 덮어쓰여짐. 위치 이동은 marker 통째 cut/paste. **본 template은 maintainer instance(jun0-ds, 두 리포 구조) 기준 예시 — fork 시 자기 sync topology로 교체.**

### 브랜치 전략

모든 기기가 `main` 브랜치에서 직접 작업한다. device 브랜치 없음.

```
main ← 모든 기기가 직접 push/pull
```

### 두 리포 구조

| 리포 | 위치 | 내용 | 자동 싱크 훅 |
|------|------|------|-------------|
| claude-config | `~/.claude/` | settings·hooks·CLAUDE.md·docs (+ sonmat 범용 ops 메모리·scribe 로그는 munteok로 이관됨 — `.gitignore`) | `hooks/sync-memory.sh` |
| munteok-anchae | `~/control-tower/munteok-anchae/` | 글로벌 메모리·노트(`desk/{memory,notes}/`) + sonmat ops 메모리(`bedrock/sonmat-memory/`)·scribe 로그(`desk/sonmat/`) + hearth·bedrock·madang·devlog·docs | `hooks/sync-munteok.sh` |

(`~/.claude/memory`·`~/.claude/notes`·`~/.claude/sonmat/memory`·`~/control-tower/.claude/sonmat`는 munteok-anchae 안을 가리키는 backward-compat symlink. claude-config `.gitignore`에서 제외 — 로컬 전용.)

### 자동 싱크 (SessionStart)

세션 시작 시 두 훅이 자동 실행, 둘 다 동일 절차:
1. (sync-munteok.sh만) 리포 없으면 `git clone` + symlink 보장(`~/.claude/{memory,notes}`, `~/.claude/sonmat/memory`, `~/control-tower/.claude/sonmat`) — 새 기기 self-healing. 기존 기기에 옛 실디렉토리가 남아있으면 경고 + `hooks/migrate-to-munteok.sh` 안내(§device-setup-guide).
2. main checkout (다른 브랜치에 있으면 전환)
3. 로컬 변경 stash
4. `git fetch origin && git rebase origin/main`
5. stash pop
6. 변경 있으면 auto commit + push

### 수동 싱크 절차

"싱크해줘", "푸시해줘", "메모리 올려줘" 등 요청 시 — **두 리포 다** 확인:

**claude-config (`~/.claude/`):**
1. 브랜치 확인: main이 아니면 `git checkout main`
2. 최신화: `git fetch origin && git rebase origin/main`
3. 상태 확인: `git status --short` → 변경 없으면 다음 리포로
4. 스테이징: `git add settings.json CLAUDE.md hooks/ settings.local.d/ docs/ .gitignore`
   - `projects/*/memory/`, `projects/**/*.jsonl`, `/memory`·`/notes`·`/sonmat/memory` symlink, `/sonmat/control-tower`는 .gitignore 대상 — 커밋하지 않음. sonmat ops 메모리·scribe 로그 변경은 munteok-anchae에서.

**munteok-anchae (`~/control-tower/munteok-anchae/`) — 메모리·노트 변경은 여기:**
1. `cd ~/control-tower/munteok-anchae && git fetch origin && git rebase origin/main`
2. `git add desk/ hearth/ bedrock/ madang/ devlog/ docs/` (또는 `git add -A`)
   - `**/secrets/`는 .gitignore 대상 — 커밋하지 않음 (로컬 전용)
3. 커밋·푸시는 아래 공통 절차

**공통 — 커밋:** `sync: 설명 ({hostname} {KST 날짜 HH:MM:SS})`
   - **시간/hostname을 먼저 변수로 평가한 뒤** 커밋 메시지에 삽입:
     ```bash
     HOSTNAME=$(hostname)
     KST=$(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S')
     git commit -m "sync: 설명 ($HOSTNAME $KST)"
     ```
   - HEREDOC 사용 시 `'EOF'`(작은따옴표)는 `$()` 치환을 막으므로 주의
**공통 — 푸시:** `git push origin main` (각 리포에서)

### 커밋 컨벤션

- 일반 동기화: `sync: 설명 ({hostname} {날짜})`
- 구조변경 포함: `sync: [구조변경] 설명 ({hostname} {날짜})`
  - 구조변경 = CLAUDE.md, settings.json, hooks/, settings.local.d/ 변경
  - 다른 기기 세션 시작 시 `detect-changes.sh`가 `[구조변경]` 커밋을 감지하여 경고
- 기능 추가/변경: `feat: 설명`

### 커밋 attribution (모든 repo 공통)

모든 git commit은 **사용자 본인이 author + committer**, **Claude는 `Co-Authored-By:` trailer**로 표시한다. 이렇게 해야 GitHub Contributors / contribution graph / `git log --author` 모두에 본인이 잡히고, Claude는 보조 attribution으로만 잡힌다.

기준:
- `~/.gitconfig`의 `user.name` / `user.email` = GitHub primary email
- 새 디바이스 셋업 시 같은 값으로 설정. 다른 email로 commit하면 GitHub이 "anonymous"로 잡아 contribution 통계에서 누락
- commit 메시지 마지막 줄: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` (또는 사용 모델에 맞게)

확인 명령:
```bash
git log -1 --format='%an <%ae>'   # 본인이어야
git log -1 --format='%(trailers)'  # Co-Authored-By: Claude... 한 줄 있어야
```

만약 author가 잘못 박힌 history가 있으면 (예: 글로벌 config가 wrong email이었던 시기), `git filter-repo --mailmap`으로 일괄 rewrite + force push로 정정한다. public repo에 잘못된 author가 박혀있는 상태로 두면 Contributors widget에 본인이 안 보인다.

### 새 세션 권장

대화 중 아래 항목에 변경이 발생하면 사용자에게 새 세션 권장을 안내한다:
- settings.json, settings.local.d/, CLAUDE.md 등 설정 파일 수정
- 글로벌/프로젝트 메모리 구조 변경 (파일 이동, 삭제, 대규모 정리)
- sonmat 등 플러그인 업데이트 (git pull, 재설치)
- hooks/ 수정

기존 세션은 시작 시점의 컨텍스트가 로드된 상태라 변경사항이 반영되지 않는다.
안내 예시: "설정이 변경됐으니 새 세션에서 진행하는 게 좋겠습니다."
