#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== bobusang setup ==="
echo ""

# 1. Detect device
HOSTNAME=$(hostname)
OS=$(uname -s)
if grep -qi microsoft /proc/version 2>/dev/null; then
  PLATFORM="WSL2"
elif [[ "$OS" == "Linux" ]]; then
  PLATFORM="Linux"
elif [[ "$OS" == "Darwin" ]]; then
  PLATFORM="macOS"
else
  PLATFORM="$OS"
fi

echo "Device:   $HOSTNAME"
echo "Platform: $PLATFORM"
echo ""

# 2. Check if ~/.claude exists
if [[ ! -d "$CLAUDE_DIR" ]]; then
  echo "~/.claude/ not found. Is Claude Code installed?"
  exit 1
fi

# 3. Create memory structure
echo "Creating memory structure..."
mkdir -p "$CLAUDE_DIR/memory/core"
mkdir -p "$CLAUDE_DIR/memory/domain"
mkdir -p "$CLAUDE_DIR/memory/archive"
mkdir -p "$CLAUDE_DIR/notes"
mkdir -p "$CLAUDE_DIR/hooks"

# 4. Copy templates (skip if files already exist)
copy_if_missing() {
  local src="$1" dst="$2"
  if [[ -f "$dst" ]]; then
    echo "  skip: $(basename "$dst") (already exists)"
  else
    cp "$src" "$dst"
    echo "  created: $(basename "$dst")"
  fi
}

# Install or update a marker-block section in a target file.
# Usage: install_or_update_marker_block <file> <marker_id> <content_source_file>
# - If markers exist in <file>: replaces content between them.
# - If absent: appends the marker block to end of <file>.
# User edits OUTSIDE markers are preserved; edits INSIDE markers get overwritten on update.
install_or_update_marker_block() {
  local file="$1" marker_id="$2" content_file="$3"
  local start_marker="<!-- ${marker_id}:start -->"
  local end_marker="<!-- ${marker_id}:end -->"

  if [[ ! -f "$file" ]]; then
    echo "  skip: ${marker_id} block (target file ${file} not found)"
    return 0
  fi
  if [[ ! -f "$content_file" ]]; then
    echo "  skip: ${marker_id} block (content source ${content_file} not found)"
    return 0
  fi

  if grep -qF "$start_marker" "$file"; then
    local tmpfile
    tmpfile=$(mktemp)
    awk -v start="$start_marker" -v end="$end_marker" -v cf="$content_file" '
      $0 == start {
        print
        while ((getline line < cf) > 0) print line
        close(cf)
        in_block = 1
        next
      }
      $0 == end { in_block = 0; print; next }
      !in_block { print }
    ' "$file" > "$tmpfile"
    mv "$tmpfile" "$file"
    echo "  updated: ${marker_id} block in $(basename "$file")"
  else
    {
      printf '\n%s\n' "$start_marker"
      cat "$content_file"
      printf '%s\n' "$end_marker"
    } >> "$file"
    echo "  installed: ${marker_id} block appended to $(basename "$file")"
  fi
}

echo ""
echo "Installing templates..."
copy_if_missing "$SCRIPT_DIR/templates/MEMORY.md" "$CLAUDE_DIR/memory/MEMORY.md"
copy_if_missing "$SCRIPT_DIR/templates/identity.md" "$CLAUDE_DIR/memory/core/identity.md"
copy_if_missing "$SCRIPT_DIR/templates/work-style.md" "$CLAUDE_DIR/memory/core/work-style.md"
copy_if_missing "$SCRIPT_DIR/templates/shared-notes.md" "$CLAUDE_DIR/notes/shared.md"

# Create device-specific note
DEVICE_NOTE="$CLAUDE_DIR/notes/$HOSTNAME.md"
if [[ ! -f "$DEVICE_NOTE" ]]; then
  echo "# $HOSTNAME" > "$DEVICE_NOTE"
  echo "" >> "$DEVICE_NOTE"
  echo "Device inbox. Quick notes, TODOs, session handoffs." >> "$DEVICE_NOTE"
  echo "  created: $HOSTNAME.md"
else
  echo "  skip: $HOSTNAME.md (already exists)"
fi

# 5. Install hooks
echo ""
echo "Installing hooks..."
copy_if_missing "$SCRIPT_DIR/hooks/sync-memory.sh" "$CLAUDE_DIR/hooks/sync-memory.sh"
copy_if_missing "$SCRIPT_DIR/hooks/detect-changes.sh" "$CLAUDE_DIR/hooks/detect-changes.sh"
chmod +x "$CLAUDE_DIR/hooks/sync-memory.sh"
chmod +x "$CLAUDE_DIR/hooks/detect-changes.sh"

# 6. Initialize git if not already
if [[ ! -d "$CLAUDE_DIR/.git" ]]; then
  echo ""
  echo "Initializing git repository in ~/.claude/..."
  cd "$CLAUDE_DIR"
  git init
  cp "$SCRIPT_DIR/templates/.gitignore" "$CLAUDE_DIR/.gitignore"
  git add -A
  git commit -m "Initial commit: bobusang setup ($HOSTNAME)"
  echo ""
  echo "Git initialized. To enable sync, add a remote:"
  echo "  cd ~/.claude && git remote add origin <your-private-repo-url>"
else
  echo ""
  echo "Git already initialized in ~/.claude/"
fi

# 6.5. Install/update CLAUDE.md sync section (marker block)
echo ""
if [[ -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
  echo "Installing CLAUDE.md sync section..."
  install_or_update_marker_block "$CLAUDE_DIR/CLAUDE.md" "bobusang:sync" "$SCRIPT_DIR/templates/sync-section.md"
else
  echo "ℹ ~/.claude/CLAUDE.md not found — sync section install skipped."
  echo "  Create CLAUDE.md and re-run setup.sh to auto-install."
fi

# 7. Add device to table
echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit ~/.claude/memory/core/identity.md — describe yourself"
echo "  2. Edit ~/.claude/memory/core/work-style.md — how you want AI to work with you"
echo "  3. Add your device to the table in ~/.claude/CLAUDE.md"
echo "  4. Add hook to settings.json:"
echo ""
echo '  "hooks": {'
echo '    "SessionStart": [{'
echo '      "type": "command",'
echo '      "command": "bash ~/.claude/hooks/sync-memory.sh"'
echo '    }, {'
echo '      "type": "command",'
echo '      "command": "bash ~/.claude/hooks/detect-changes.sh"'
echo '    }]'
echo '  }'
echo ""
echo "See README.md for full documentation."
