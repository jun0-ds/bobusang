#!/usr/bin/env bash
# bobusang — auto-sync on session start
# Runs as a Claude Code SessionStart hook.
# Syncs ~/.claude/ with remote, auto-commits local changes.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
cd "$CLAUDE_DIR"

# Skip if not a git repo
[[ -d .git ]] || exit 0

# Skip if no remote configured
git remote get-url origin &>/dev/null || exit 0

HOSTNAME=$(hostname)
TIMESTAMP=$(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')

# 1. Ensure we're on main
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
  git checkout main 2>/dev/null || exit 0
fi

# 2. Stash local changes
STASHED=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  git stash push -m "bobusang-auto-stash" --quiet
  STASHED=true
fi

# 3. Pull with rebase
if git fetch origin --quiet 2>/dev/null; then
  if ! git rebase origin/main --quiet 2>/dev/null; then
    echo "⚠ bobusang: rebase conflict — aborting rebase, manual resolution needed"
    git rebase --abort 2>/dev/null
    if [[ "$STASHED" == "true" ]]; then
      git stash pop --quiet 2>/dev/null || true
    fi
    exit 0
  fi
fi

# 4. Restore stashed changes
if [[ "$STASHED" == "true" ]]; then
  if ! git stash pop --quiet 2>/dev/null; then
    echo "⚠ bobusang: stash pop conflict — check git stash list"
    exit 0
  fi
fi

# 5. Auto-commit if there are changes
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  # Determine if structural change
  CHANGED_FILES=$(git diff --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
  STRUCTURAL=false
  if echo "$CHANGED_FILES" | grep -qE '^(CLAUDE\.md|settings\.json|hooks/|settings\.local\.d/)'; then
    STRUCTURAL=true
  fi

  # Stage sync-eligible files
  git add memory/ notes/ hooks/ settings.json CLAUDE.md 2>/dev/null || true

  if ! git diff --cached --quiet; then
    if [[ "$STRUCTURAL" == "true" ]]; then
      git commit -m "sync: [구조변경] auto-sync ($HOSTNAME $TIMESTAMP)" --quiet
    else
      git commit -m "sync: auto-sync ($HOSTNAME $TIMESTAMP)" --quiet
    fi
    git push origin main --quiet 2>/dev/null || echo "⚠ bobusang: push failed — will retry next session"
  fi
fi
