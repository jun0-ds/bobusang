# Spike D — transcrypt Merge Edge Cases

**Date**: 2026-04-15
**Purpose**: Verify transcrypt's merge driver handles the edge cases bobusang cares about: rename+modify, `.gitattributes` conflicts, stash pop through encrypted conflicts, and the "user forgot to unlock" corruption scenario. Spike A confirmed the happy path; Spike D tests the corners.
**Verdict**: **PASS with one critical finding that elevates Spike C's urgency.** transcrypt's merge driver works for the practical cases. Git's fundamental rename detection has limitations on encrypted files (tool-independent). And the "edit without unlock" footgun requires bobusang's pre-commit check as a mandatory defense — confirming rev 3's design call.

## Environment

Same as Spike A. transcrypt 2.3.1, git 2.43.0, Ubuntu 24.04 WSL2.

## Test 1 — Rename + Modify conflict

**Setup**: Device A renames `secrets/foo.md → secrets/bar.md`. Device B (concurrently) modifies line 2 of the old `secrets/foo.md`. Device B pulls.

**Expected**: rename-aware conflict ("foo.md renamed to bar.md on A, modified on B — please apply modification to bar.md").

**Actual**:

```
CONFLICT (modify/delete): secrets/foo.md deleted in 33dac2d... and modified in HEAD.
Version HEAD of secrets/foo.md left in tree.
Automatic merge failed; fix conflicts and then commit the result.

git status:
A  secrets/bar.md
UD secrets/foo.md

ls secrets/:
bar.md  foo.md
```

**Interpretation**: Git did NOT detect this as a rename. It reported "modify/delete": B's version of foo.md is "modified in HEAD", A's version appears as if foo.md was "deleted" and bar.md was "added" independently. The two operations are treated as unrelated changes on unrelated files.

### Why this happens (not transcrypt's fault)

Git's rename detection works by comparing blob similarity: if `foo.md` was deleted and a new file `bar.md` was added, git asks "is bar.md's content similar enough to foo.md's content to call it a rename?". For plaintext files, this works well — similar text produces high similarity scores.

For encrypted files, **every re-encryption of the same plaintext produces different ciphertext** (because transcrypt uses a random-ish salt derived from HMAC of filename+password+content — specifically designed so that ciphertext doesn't leak "same content" info). So:

- `secrets/foo.md` (old blob) has ciphertext `U2FsdGVkX18A...`
- `secrets/bar.md` (new blob) has ciphertext `U2FsdGVkX1Xk...` (different, even for identical plaintext)

Similarity score: near zero. Git concludes they are unrelated files.

**This is a fundamental consequence of secure encryption**, not a transcrypt bug or a git-crypt advantage. Any encryption tool that uses randomized IVs (which they should, for security) will break git's rename detection. Deterministic encryption could fix it but would enable known-plaintext attacks — a worse tradeoff.

### Resolution path (tested and works)

```bash
# Manually apply B's content to the renamed file
cat secrets/foo.md > secrets/bar.md   # or edit bar.md directly
git rm secrets/foo.md
git add secrets/bar.md
git commit -m "merge: apply B's modify onto A's rename"
git push
```

Verified: after this resolution, the file remains encrypted at rest (checked via fresh inspector clone).

### Impact on bobusang

1. **Rename frequency should be low.** Users should not frequently rename encrypted files. bobusang's `bobusang reclassify` command (the supported rename path) should warn about this when invoked on cross-device scenarios.
2. **Git history follow is lost.** `git log --follow secrets/bar.md` won't see pre-rename history on encrypted files. Users lose "when was this content first written" queries.
3. **Not a blocker** for bobusang's workflow because renames are rare and the resolution path is straightforward — just a usability/documentation concern.

## Test 2 — `.gitattributes` conflict

**Setup**: Both devices add new encryption rules to `.gitattributes` on different lines. Device B pulls after device A pushes.

**Expected**: Normal text merge conflict (`.gitattributes` is plaintext).

**Actual**:

```
Auto-merging .gitattributes
CONFLICT (content): Merge conflict in .gitattributes

<<<<<<< HEAD
archive/confidential/** filter=crypt diff=crypt merge=crypt
=======
notes/private/** filter=crypt diff=crypt merge=crypt
>>>>>>> c258ac5...
```

**Interpretation**: Normal conflict, normal resolution (union of both rules), normal commit. No encryption weirdness.

### Impact on bobusang

**Cosmetic.** However: `.gitattributes` is the **source of truth for which files are encrypted**. A conflict in it means the repo is temporarily in an ambiguous state — some files might be governed by the pre-merge rules, some by the incoming rules, and the user has to resolve carefully.

**Documentation action**: merge-conflict runbook should call out that `.gitattributes` conflicts require extra care, because resolving them incorrectly (e.g., removing a line that was supposed to keep a file encrypted) could silently change encryption state of existing files.

## Test 3 — Stash pop through encrypted conflict

**Setup**: Device A has uncommitted local changes to `secrets/bar.md` (stashed). Device B pushes a conflicting change to the same file. Device A pulls, then `git stash pop`.

**Expected**: stash pop produces a normal conflict state with plaintext markers.

**Actual**:

```
git pull:
Fast-forward
 secrets/bar.md | Bin 90 -> 110 bytes

git stash pop:
Unmerged paths:
    both modified: secrets/bar.md
The stash entry is kept in case you need it again.

cat secrets/bar.md:
original line 1
<<<<<<< main
B PUSHED CHANGE
=======
A LOCAL UNCOMMITTED
>>>>>>> theirs
original line 3
```

**Interpretation**: **PASS.** transcrypt's merge driver is invoked during stash pop's apply step. Plaintext conflict markers appear. User resolves normally and the stash entry is retained (standard git behavior on conflict). File re-encrypts on commit.

### Impact on bobusang

None. This works correctly.

## Test 4 — User edits an encrypted file without running `transcrypt` (CRITICAL)

**Setup**: Device C clones the repo. Does NOT run `transcrypt -y -p <password>`. Device C user sees `secrets/bar.md` as ciphertext garbage and "helpfully fixes" it by overwriting with plaintext. Commits. Pushes.

**Expected**: Something should stop this. At minimum, git should refuse.

**Actual**:

```
# Device C, no transcrypt init
$ cat secrets/bar.md    # looks like garbage
U2FsdGVkX1/6M30/UpTKXAaxw2qeeF/7yYhEsQlGYvVBJ06In9GsDKZzJROpNiRo
naVQXirDhZ48SotsSUdJ2MabeNK0IngFQX6aEwlGmPA=

$ echo "I think this was corrupted so I'm fixing it" > secrets/bar.md
$ git commit -am "C: fix corrupted file"
[main 513d7c3] C: fix corrupted file

$ git push origin main
   4e9c75b..513d7c3  main -> main   # ✅ SUCCEEDS SILENTLY

# Inspector clone (no transcrypt)
$ cat secrets/bar.md
I think this was corrupted so I'm fixing it    # PLAINTEXT ON REMOTE
```

### What happened

1. Device C has no `filter.crypt.clean` configured in `.git/config` because transcrypt was never run.
2. `git add` stages the user's raw plaintext content directly into the index.
3. `git commit` and `git push` treat this as a normal file change. No filter runs. No warning.
4. The remote now has `secrets/bar.md` as a plaintext blob in the commit history.
5. Device A (which HAS transcrypt configured) pulls. A's smudge filter runs on the incoming blob, fails to decrypt (no `Salted__` prefix), and falls through to `cat "$tempfile"` (smudge's pass-through fallback). A's working tree now contains the plaintext.
6. `git ls-crypt` on device A still lists `secrets/bar.md` as "encrypted" (because `.gitattributes` still says so) but the underlying content is plaintext. **Silent state mismatch.**

### Impact on bobusang

**This is a live footgun.** Scenarios where it triggers:

- New device added to the user's rotation. User forgets to run `setup.sh`. User edits a file. Disaster.
- User clones the repo on a temporary machine for a quick edit. Doesn't install transcrypt. Edits. Disaster.
- User's `setup.sh` run fails silently. User proceeds anyway. Edits. Disaster.
- Anyone accessing the repo who doesn't have (or doesn't know about) the encryption layer.

The "disaster" is: **previously encrypted sensitive content now exists in the remote's git history as plaintext** and will exist there forever unless `git filter-repo` is used.

### This is NOT transcrypt's fault

git-crypt has the same vulnerability. `<private>`-tag v2.1 had the same vulnerability. Any tool that relies on `.gitattributes` + clean/smudge filters is vulnerable to "user bypasses the filter by not registering it locally." Git is designed to allow filters to be absent — `.gitattributes` filter references silently degrade to no-op if the filter isn't defined.

**The defense must live in bobusang's layer**, not in the encryption primitive's layer.

### Defenses (partially in rev 3, now mandatory)

1. **Pre-commit hook** (rev 3 Spike C territory): check that every staged file under `secrets/**` **actually starts with `U2FsdGVk`** (base64 `Salted__`). If not, refuse commit. This blocks Test 4 at the commit step.
2. **Setup-time guard**: `setup.sh` detects when the repo has encrypted-path `.gitattributes` entries AND no `filter.crypt` configured locally. If mismatch → refuse to proceed until user explicitly runs the transcrypt init or explicitly opts out with a dangerous flag.
3. **Session-start warning**: bobusang's session-start hook checks the same mismatch every session. Loud warning if the repo is in an inconsistent state ("this repo has encrypted paths but transcrypt is not configured on this device — any edits you make to those paths will be silent plaintext commits").

**All three defenses are needed.** Any single one can be bypassed:
- Pre-commit hook: user bypasses with `--no-verify`
- Setup-time guard: user clones and skips setup.sh
- Session-start warning: user ignores warnings

In combination, they catch most realistic failure modes. The design principle is "fail loud early, and again at commit time, and then refuse the commit itself."

### Spike D → Spike C urgency

Spike C (pre-commit check reliability) is now **the single most important remaining spike**. Without it, Test 4 is a live vulnerability with no defense. Rev 3's "pre-commit mandatory" call is validated by this finding.

## What Spike D did NOT cover

- **Octopus merge** (3+ branches merged at once): bobusang doesn't use this; skipped.
- **macOS APFS case-insensitivity**: cannot test on ext4. Flagged as Spike D2 for a future macOS-equipped session or a volunteer tester.
- **Windows native filesystem quirks**: bobusang v2.2 dropped Windows native from the support matrix (rev 3). Not tested.
- **Deeply nested rename-across-boundaries**: e.g., renaming `secrets/foo.md → notes/secrets/foo.md`. This is a "change which encryption rule applies" case that `bobusang reclassify` is supposed to own. Not tested in this spike — deferred to Spike C where the pre-commit check's move detection is the primary subject.

## Summary

| Test | Result | Severity |
|------|--------|----------|
| 1: rename + modify | Git rename detection fails on encrypted blobs (fundamental) | **Low** (rare, resolvable) |
| 2: `.gitattributes` conflict | Normal text merge, works | **Cosmetic** |
| 3: stash pop through encrypted conflict | merge driver handles it correctly | **Pass** |
| 4: edit without transcrypt unlock | **Silent plaintext leak to remote** | **CRITICAL** |

## Go/No-go

**GO on transcrypt.** The critical finding is Test 4, which is **tool-independent** — it affects any `.gitattributes`-based encryption approach, including the rev 3 transcrypt choice and the rejected git-crypt fallback. The defense is **bobusang's own pre-commit check + setup-time guard + session-start warning**, which rev 3 already specifies as mandatory.

**Spike D reinforces, does not invalidate, rev 3.** No rev 4 required from Spike D alone.

## Action items carried forward

1. **Spike C is now top priority.** It must verify that a pre-commit check can detect Test 4's "plaintext where ciphertext expected" state.
2. **`setup.sh` guard logic**: detect `.gitattributes`-vs-filter-config mismatch and refuse to proceed.
3. **Session-start hook**: add a fast check for the same mismatch.
4. **Merge-conflict runbook**: document `.gitattributes` conflict caution + rename+modify resolution path.
5. **`bobusang reclassify` design**: must not rely on git rename detection for encrypted files.
6. **Documentation**: warn users explicitly that "cloning the repo on a new device and editing without running setup.sh is dangerous" — but treat this as defense in depth, not the primary defense.

## Cleanup

```bash
rm -rf /tmp/spike-d-transcrypt
# ~/.local/bin/transcrypt kept for Spike C
```
