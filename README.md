# bobusang (보부상)

> 마을과 마을 사이를 떠돌며 물건을 날랐던 행상인처럼,
> bobusang은 기기와 기기 사이에서 AI의 기억을 나릅니다.

Windows, WSL, Linux 서버를 넘나드는 Claude Code 멀티디바이스 메모리 시스템.

## What this is

A **multi-device memory system** for Claude Code that works across Windows, WSL2, and Linux servers.

Claude Code's built-in auto-memory is per-project and single-device. bobusang extends it with:

- **3-tier global memory** (core / domain / archive) — loaded by priority, not all at once
- **Automatic sync** — git-based, runs on every session start
- **Multi-device notes** — per-device inbox + shared notes
- **Structural change detection** — warns you when config changed on another device

## The problem

You use Claude Code on multiple machines. Your laptop at home, WSL2 at work, a GPU server for training. Each one starts every session blank — no memory of what you discussed on the other device, no shared context, no continuity.

You could copy files manually. You could write your own sync script. Or you could use bobusang.

## Quick start

```bash
git clone https://github.com/jun0-ds/bobusang.git
cd bobusang
bash setup.sh
```

`setup.sh` will:
1. Detect your current device (hostname, OS)
2. Initialize the memory directory structure in `~/.claude/`
3. Set up git remote for sync
4. Install session-start hooks

## Structure

```
~/.claude/
├── CLAUDE.md                    # Global instructions (your template)
├── settings.json                # Shared config (relative paths only)
├── settings.local.json          # Device-specific overrides
│
├── memory/
│   ├── MEMORY.md                # Index — loaded every session
│   ├── core/                    # Always loaded. Your identity + work style.
│   │   ├── identity.md          #   Who you are, how you think
│   │   └── work-style.md        #   How the AI should work with you
│   ├── domain/                  # Lazy-loaded. Active projects + references.
│   │   └── (your memories)
│   └── archive/                 # Cold storage. Completed work.
│       └── (graduated memories)
│
├── hooks/
│   ├── sync-memory.sh           # Auto-sync on session start
│   └── detect-changes.sh        # Warn if config changed on another device
│
└── notes/
    ├── {hostname}.md            # Per-device inbox
    └── shared.md                # Cross-device notes
```

### Why 3 tiers?

| Tier | When loaded | What goes here | Example |
|------|-------------|---------------|---------|
| **core** | Every session, fully | Your identity, preferences, work style | "I'm a backend engineer who prefers terse responses" |
| **domain** | On demand (index only) | Active projects, tools, references | "Project X uses FastAPI + PostgreSQL" |
| **archive** | Never (unless searched) | Completed projects, old feedback | "Project Y shipped in March" |

Claude Code loads `MEMORY.md` (the index) every session. Core files are small enough to always include. Domain files are referenced by title — Claude reads them only when relevant. Archive stays cold.

## Sync mechanism

Every session start triggers `sync-memory.sh`:

```
1. git fetch origin
2. git stash (if local changes)
3. git rebase origin/main
4. git stash pop
5. Auto-commit + push (if changes detected)
```

### Structural change detection

When config files (`CLAUDE.md`, `settings.json`, `hooks/`) change on another device, commits are tagged with `[구조변경]`. On your next session start, `detect-changes.sh` catches these and warns you:

```
⚠ 설정/구조 변경 감지 — 새 세션을 권장합니다
  • CLAUDE.md
  • settings.json
```

This matters because Claude Code loads config at session start. Mid-session changes don't take effect — you need a fresh session.

### Commit convention

```
sync: description (HOSTNAME YYYY-MM-DD HH:MM:SS)     # regular sync
sync: [구조변경] description (HOSTNAME YYYY-MM-DD)     # config changes
feat: description                                      # new capability
```

## Multi-device setup

### Device identification

bobusang uses `hostname` to identify devices. Add your machines to the device table in `CLAUDE.md`:

```markdown
| hostname | device | purpose | OS |
|----------|--------|---------|-----|
| MY-LAPTOP | Main laptop | Development | Windows (WSL2) |
| WORK-SERVER | GPU server | Training | Linux |
```

### Path rules

**Always use relative paths** (`~/.claude/...`) in `settings.json`. Absolute paths (`/home/user/...`) break across devices.

Shared config goes in `settings.json`. Device-specific config goes in `settings.local.json` (gitignored).

### Platform support

| Platform | Status | Notes |
|----------|--------|-------|
| WSL2 (Ubuntu) | Fully supported | Recommended for Windows users |
| Linux | Fully supported | Servers, desktops |
| Windows (native) | Partial | Git Bash required for hooks |
| macOS | Should work | Not tested — PRs welcome |

## Evolution

This system was built iteratively over a week of real daily use across 4 devices. See [docs/evolution.md](docs/evolution.md) for the full timeline — from a flat memory dump to a 3-tier architecture with automatic sync.

Key milestones:

```
Day 1  Initial commit — flat memory, manual sync
Day 2  Device identification, per-device settings
Day 3  Memory hierarchy (v1.0.0), conversation history sync
Day 4  Device branch strategy (v1.1.0) — and the merge hell that followed
Day 5  Abandon branches → single main + auto-sync (v2.0.0)
Day 6  3-tier memory (core/domain/archive), structural change detection
```

Every decision was earned through failure. The device branch strategy sounded elegant until three-way merges started eating sessions. Single-branch with auto-rebase turned out to be the right answer.

## Writing good memories

### Core memories (always loaded)

Keep these **small and stable**. They should rarely change. Think of them as your "onboarding doc" for a new AI session.

```markdown
---
name: identity
description: Who I am — role, thinking style, preferences
type: user
---

Backend engineer, 5 years Python. Prefer terse responses.
Value correctness over speed. Don't add features I didn't ask for.
```

### Domain memories (lazy-loaded)

These are your active working context. More detailed, more volatile.

```markdown
---
name: project-x-api
description: Project X API migration — FastAPI endpoints and auth flow
type: project
---

Migrating from Flask to FastAPI. Auth uses JWT + refresh tokens.
**Why:** Flask async support is painful, need WebSocket for real-time features.
**How to apply:** When touching API code, check if endpoint is migrated yet.
```

### When to archive

Move to `archive/` when:
- A project ships or is abandoned
- Feedback has been absorbed into `core/work-style.md`
- A reference is no longer actively needed

## FAQ

**Q: Why git and not a database?**
A: Memories are markdown files. Git gives you sync, conflict resolution, history, and diffs for free. No server needed.

**Q: Why not per-project memory?**
A: Claude Code already does per-project memory well. bobusang handles the *global* layer — your identity, cross-project preferences, and device sync. They complement each other.

**Q: Can I use this with other AI CLIs?**
A: The memory structure is plain markdown — it works with anything. The hooks are Claude Code-specific, but the concept applies anywhere.

## Related

- [Blog post: Building a multi-device memory system for Claude Code](#) *(coming soon)*
- [sonmat](https://github.com/jun0-ds/sonmat) — Claude Code verification plugin by the same author

## License

MIT — see `LICENSE`.
