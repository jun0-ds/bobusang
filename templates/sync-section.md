### claude-config 리포 sync

이 절은 bobusang setup.sh가 자동 install/update — 본문 수정은 marker 통째 cut/paste로 위치 변경 가능, 단 marker 내부 본문 직접 수정은 다음 setup.sh 실행 시 덮어쓰여짐.

**자동 sync** (SessionStart):
- `~/.claude/hooks/sync-memory.sh` 실행
- main checkout → stash → fetch → rebase → pop → auto commit + push (변경 있을 때만)

**수동 sync** ("싱크해줘", "푸시해줘"):
1. `cd ~/.claude && git status --short` — 변경 확인
2. main 아니면 `git checkout main`
3. `git fetch origin && git rebase origin/main`
4. 변경 있으면 stage + commit + push
   - 커밋 메시지 형식: `sync: 설명 ({hostname} {KST 시간})`
   - 시간/hostname을 *변수로 평가한 뒤* 메시지에 삽입:
     ```bash
     HOSTNAME_STR=$(hostname)
     KST=$(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S')
     git commit -m "sync: 설명 ($HOSTNAME_STR $KST)"
     ```
   - HEREDOC 사용 시 `'EOF'`(작은따옴표)는 `$()` 치환을 막으므로 주의

**커밋 attribution**:
- author + committer = 사용자 본인 (`~/.gitconfig`의 `user.name` / `user.email` = GitHub primary email)
- AI 보조는 trailer로: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` (사용 모델에 맞게)
- 확인: `git log -1 --format='%an <%ae>'` → 본인이어야 / `git log -1 --format='%(trailers)'` → Co-Authored-By 한 줄
