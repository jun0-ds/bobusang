#!/usr/bin/env bash
# bobusang — detect structural changes from other devices
# Warns if config files were modified by another device since last session.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
cd "$CLAUDE_DIR"

[[ -d .git ]] || exit 0

HOSTNAME=$(hostname)

# Find [구조변경] commits from OTHER devices in recent history
STRUCTURAL_COMMITS=$(git log --oneline -20 --grep='구조변경' | grep -v "$HOSTNAME" || true)

if [[ -n "$STRUCTURAL_COMMITS" ]]; then
  echo "⚠ 설정/구조 변경 감지 — 새 세션을 권장합니다"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Show which files changed
  CHANGED_CONFIG=$(git log -20 --grep='구조변경' --name-only --pretty=format: | grep -v "$HOSTNAME" | sort -u | grep -E '^(CLAUDE\.md|settings\.json|hooks/|settings\.local\.d/)' || true)
  if [[ -n "$CHANGED_CONFIG" ]]; then
    while IFS= read -r file; do
      [[ -n "$file" ]] && echo "  • $file"
    done <<< "$CHANGED_CONFIG"
  fi

  echo ""
  echo "  [구조변경] 커밋 감지:"
  while IFS= read -r commit; do
    [[ -n "$commit" ]] && echo "  • $commit"
  done <<< "$STRUCTURAL_COMMITS"

  echo ""
  echo "현재 세션은 시작 시점의 컨텍스트가 로드된 상태입니다."
  echo "변경사항을 반영하려면 새 세션을 시작하세요."
fi
