# Spike C — Pre-commit Hook Reliability

**Date**: 2026-04-15
**Purpose**: Implement and test a bobusang pre-commit hook that blocks the failure modes surfaced by Spike D — specifically the "edit without unlock" vulnerability and the "file-move across encryption boundary" trap. rev 3's design mandated this hook; Spike C verifies it can actually be built and blocks the cases it needs to block.
**Verdict**: **PASS.** A ~90-line bash hook catches all tested cases. One `--no-verify` structural limitation remains, defended via session-start check (deferred).

## Environment

transcrypt 2.3.1, git 2.43.0, Ubuntu 24.04 WSL2. Same setup as Spikes A/B/D.

## Hook implementation

Full script committed at `contrib/hooks/pre-commit-encrypted`. Summary:

1. Parse `.gitattributes` for lines containing `filter=crypt` → collect encrypted path patterns
2. For each staged file (from `git diff --cached --name-status`):
   - `A`/`M` status: verify `git show :path` starts with `U2FsdGVk` (base64 `Salted__`) if the path is encrypted
   - `R*` status (rename): check whether old or new path is encrypted. If encrypted→plaintext rename → refuse. Always verify destination content if destination is encrypted.
3. Exit 0 on all pass, exit 1 on any fail

The hook is strict mode (`set -euo pipefail`), no external deps beyond git and bash, ~90 lines.

## Test matrix

| # | Scenario | Expected | Result |
|---|----------|----------|--------|
| 1 | Normal encrypted commit (filter configured, content encrypted) | allow | ✅ allow |
| 2 | Normal plaintext commit (non-secrets path) | allow | ✅ allow |
| 3 | Plaintext added to `secrets/` with filter neutralized (simulates Spike D Test 4) | block | ✅ block |
| 4 | Rename `secrets/foo.md → public_dir/foo.md` (encrypted → plaintext boundary) | block | ✅ block |
| 5 | Rename `public.md → secrets/public.md` with filter broken (destination not ciphertext) | block | ✅ block (after v2 patch) |
| 6 | `--no-verify` bypass | bypassed (structural) | ✅ bypassed, documented |

## Test 3 — plaintext into secrets/ path (the main threat)

Reproduces Spike D's Test 4: user has the repo cloned but transcrypt was never run locally, so `filter.crypt.clean` is unset (or set to `cat`). User edits or adds a file under `secrets/` thinking it's just a text file.

```bash
git config filter.crypt.clean cat   # simulate no transcrypt
git config filter.crypt.smudge cat

echo "plaintext I forgot to encrypt" > secrets/bad.md
git add secrets/bad.md
git commit -m "TEST 3: should fail"
```

Hook output:

```
bobusang pre-commit: REFUSED — secrets/bad.md is at an encrypted path but staged content is plaintext
  Expected content to start with "U2FsdGVk" (base64 Salted__).
  Likely cause: transcrypt not unlocked on this device. Run: transcrypt --display
```

Exit 1. **Commit blocked.** The blob that would have been pushed never makes it past `git commit`.

## Test 4 — cross-boundary rename

```bash
git mv secrets/foo.md public_dir/foo.md
git commit -m "TEST 4: cross boundary"
```

Hook output:

```
bobusang pre-commit: REFUSED — secrets/foo.md → public_dir/foo.md crosses encryption boundary (encrypted → plaintext)
  Use `bobusang reclassify` to make this change explicit.
```

Exit 1. **Blocked.**

## Test 5 — rename INTO secrets/ (bug found, patched)

Initial version of the hook only checked the `A`/`M` status branch for content, and the `R*` branch only for boundary direction. I ran:

```bash
git config filter.crypt.clean cat   # filter broken
git mv public.md secrets/public.md
git commit -m "TEST 5"
```

**Initial hook allowed this**, because:
1. `R*` status → hook checks boundary (plaintext → encrypted is "allowed direction") → passes
2. No fall-through to content verification
3. Blob is plaintext (filter is `cat`), ends up in `secrets/public.md` as plaintext

**Gap**: rename into an encrypted path with a broken filter silently commits plaintext — the same failure class as Test 3, but via the rename path.

**Patch**: after the boundary direction check, always call `verify_encrypted_path_has_ciphertext "$new_path"`. Regardless of direction, the destination content must be ciphertext if the destination path is encrypted.

**After patch**:

```
bobusang pre-commit: REFUSED — secrets/public.md is at an encrypted path but staged content is plaintext
```

Exit 1. **Blocked.**

This patch is in the reference hook at `contrib/hooks/pre-commit-encrypted`.

## Test 6 — `--no-verify` bypass

```bash
git config filter.crypt.clean cat
echo "bypass me" > secrets/bypass.md
git add secrets/bypass.md
git commit --no-verify -m "bypass"
```

**Commit succeeded.** The `--no-verify` flag instructs git to skip pre-commit hooks entirely. The hook never runs.

**This is a structural limitation of git hooks**, not a bug. Defenses:

1. **Document it**: users should be warned in bobusang docs that `--no-verify` bypasses all bobusang safety checks. Anyone doing this is opting out of the protection.
2. **Session-start ciphertext scan**: on every session start, bobusang scans all files under encrypted paths and verifies each starts with `U2FsdGVk`. If any don't, alert loudly:
   ```
   bobusang: WARNING — the following files are at encrypted paths but contain plaintext:
     memory/secrets/foo.md
     memory/secrets/bar.md
   This usually means the files were committed without transcrypt configured.
   Run `bobusang scan-encryption-state` to investigate.
   ```
3. **Post-commit hook** (not currently in scope but could be added): runs after every commit, does the same check, and rolls the commit back if violated. This is stronger but needs careful design around race conditions.

The **pre-commit hook + session-start scan** combination catches the realistic failure modes:
- "I forgot to unlock" → pre-commit blocks
- "I ran `git commit --no-verify` to get past a failing hook" → session-start scan catches on next session
- "I cloned the repo without transcrypt configured and committed directly" → pre-commit catches if the filter is unset, session-start scan catches if the filter somehow runs but produces plaintext

The only gap is: user runs `--no-verify`, then runs `git push` immediately, before the next session-start. The plaintext is already on the remote. Session-start scan on another device will catch it on next pull, but the leak has already happened.

**This is the residual risk.** Document it, accept it, and hope users don't explicitly bypass safety systems. It is a much smaller residual risk than the Spike D Test 4 situation (which was "silent by default") — this one requires active user circumvention with a flag, which is a significantly higher bar.

## Performance note

Each `git show :path` call forks a git subprocess. On commits with many staged files under encrypted paths, this could add latency. On bobusang's expected workload (one or two files per commit), it's fast.

For larger commits, optimization options:
- Cache encrypted-path detection
- Use `git cat-file --batch` for blob reads
- Parallelize with xargs

Not currently necessary.

## Edge cases not tested (flagged for implementation)

1. **Symlinks under encrypted paths**: `git diff --cached --name-status` reports symlinks as regular file changes. The content check on a symlink will read the target, not the link text. Unclear behavior. Should test in real implementation.
2. **Submodules**: bobusang doesn't use submodules (rev 3 explicitly drops them); not tested.
3. **Case-sensitivity on case-insensitive filesystems** (macOS APFS): not tested on this Linux setup. Flagged as Spike D2 material for a macOS pass.
4. **`.gitattributes` patterns beyond `path/**`**: The parser only handles simple suffix `**` globs. Real `.gitattributes` can use full glob syntax with `*`, `?`, `[...]`, negation with `!`, etc. Real implementation should shell out to `git check-attr filter -- "$path"` instead of parsing .gitattributes manually. This was deferred in Spike C to keep the reference hook readable.

## Real implementation to-do for v2.2

Move the reference hook to an integration path:

1. Replace the `.gitattributes` glob parser with `git check-attr filter -- "$path"` — git's own evaluator handles the full syntax correctly.
2. Install path: `setup.sh` copies the hook to `.git/hooks/pre-commit` if no pre-commit exists, or chains it if one does (rare case).
3. Upgrade path: when bobusang updates, also update any installed pre-commit hook.
4. Session-start companion: add `bobusang scan-encryption-state` as a command that does the broader check, and wire it into the session-start hook.

## Cleanup

```bash
rm -rf /tmp/spike-c-precommit
```

The tested hook script is preserved at `contrib/hooks/pre-commit-encrypted` in the bobusang repo for reference and future integration.

## Go/No-go

**GO on the pre-commit approach.** Spike C confirms the defense is feasible in ~90 lines of bash, covers the realistic failure modes from Spike D, and the one structural gap (`--no-verify`) is defended by a companion session-start check at a tolerable residual risk level.

All four Phase 0 spikes now green:
- ✅ Spike A — transcrypt full-stack works
- ✅ Spike B — git-crypt confirmed broken for our workflow (disconfirmation failed; switch stands)
- ✅ Spike C — pre-commit defense is buildable and tested
- ✅ Spike D — merge edge cases handled, Test 4 surfaced and now defended by Spike C

**Phase 0 is unblocked. v2.2 implementation can begin.**
