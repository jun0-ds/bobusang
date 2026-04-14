# Spike B — git-crypt Merge Breakage Reproduction

**Date**: 2026-04-15
**Purpose**: Confirm or disconfirm that git-crypt's reported merge breakage (issues #20, #273) is reproducible against the current toolchain. If reproducible → v2.2 rev 3's switch to transcrypt is justified. If NOT reproducible → rev 4 may revert primitive choice to git-crypt.
**Verdict**: **REPRODUCED.** Switch to transcrypt confirmed.

## Environment

| Component | Version |
|-----------|---------|
| OS | Ubuntu 24.04 (WSL2) |
| git | 2.43.0 |
| git-crypt | 0.7.0 (apt, `git-crypt_0.7.0-0.1build3_amd64.deb`) |
| git-crypt master last commit | 2018-02-16 (per audit) |

The apt package on Ubuntu 24.04 LTS ships **git-crypt 0.7.0** — the same version the ecosystem audit flagged as the "stable" line. No newer version is available via mainline apt.

## Test setup

```bash
WORK=/tmp/spike-b-gitcrypt
mkdir -p "$WORK" && cd "$WORK"
git init -q -b main
git-crypt init
git-crypt export-key ./gitcrypt.key

echo "secret.md filter=git-crypt diff=git-crypt" > .gitattributes
printf 'initial content line A\ninitial content line B\n' > secret.md
git add .gitattributes secret.md && git commit -q -m "initial"
```

`git-crypt status` confirmed `secret.md` is tracked as encrypted.

## Test 1 — Branch merge on encrypted file

Two divergent, **non-overlapping** edits that a 3-way text merge should handle trivially:

```bash
git checkout -b other
# Insert a line in the middle
printf 'initial content line A\nOTHER BRANCH INSERT\ninitial content line B\n' > secret.md
git commit -qam "other branch edit"

git checkout main
# Append a line at the end
printf 'initial content line A\ninitial content line B\nMAIN BRANCH APPEND\n' > secret.md
git commit -qam "main branch edit"

git merge other
```

**Result**:

```
warning: Cannot merge binary files: secret.md (HEAD vs. other)
Auto-merging secret.md
CONFLICT (content): Merge conflict in secret.md
Automatic merge failed; fix conflicts and then commit the result.
```

Exit 1. Working tree is left with `main`'s version only. No three-way merge was attempted.

**This is the reproduction.** Git treats the encrypted blob as binary during merge and refuses to auto-merge. The `warning: Cannot merge binary files` line is the smoking gun — identical in spirit to reports in issues #20 and #273.

## Test 2 — Rebase on encrypted file

```bash
git merge --abort
git rebase other
```

**Result**:

```
warning: Cannot merge binary files: secret.md (HEAD vs. 7594314 (main branch edit))
Auto-merging secret.md
CONFLICT (content): Merge conflict in secret.md
error: could not apply 7594314... main branch edit
```

Exit 1. Status after: `UU secret.md`. Rebase stalls, same root cause.

**This is directly relevant to bobusang.** `sync-memory.sh` uses `git fetch origin && git rebase origin/main`. With encrypted files plus any divergent edit across devices, the sync hook would stall on every sync cycle and require manual intervention.

## Test 3 — `git merge --no-ff` (pull-style)

Same failure. Same error. `git pull` runs `git merge` by default and hits the identical wall.

## Test 4 — Does `git diff` work?

Yes. `git diff main other -- secret.md` produced a clean textual diff:

```diff
-MAIN BRANCH APPEND
+OTHER BRANCH INSERT
```

**This is critical for the root-cause analysis**: git-crypt's *diff* driver works because `.gitattributes` registers `diff=git-crypt`, and git invokes the driver to decrypt before diffing. **No equivalent `merge=git-crypt` driver is registered**, so merge falls through to git's default binary handling.

## Root cause (confirmed)

`.gitattributes` (as written by `git-crypt init`):

```
secret.md filter=git-crypt diff=git-crypt
```

`git config` after init:

```
filter.git-crypt.clean  = "git-crypt" clean
filter.git-crypt.smudge = "git-crypt" smudge
(no merge.git-crypt.* entries)
```

**git-crypt registers clean, smudge, and diff drivers but NOT a merge driver.** Git 2.39.1+ (and earlier — this is not a git regression, it's a git-crypt omission) runs merge on the index-level ciphertext blobs, detects null bytes / high-entropy binary, and refuses auto-merge.

This is a fundamental design gap in git-crypt, not a transient bug. Fixing it would require git-crypt to implement a custom merge driver, which it has never shipped. The open issues (#20, #273) have been known for years without resolution, matching the audit's "master dormant since 2018" finding.

## Test 5 — Post-conflict file integrity check (informational)

After triggering the conflict, I manually resolved with `git checkout --ours secret.md` and committed. Then:

```bash
git-crypt lock     # re-encrypts working tree
xxd secret.md | head  # binary ciphertext — good
git-crypt unlock ./gitcrypt.key
cat secret.md     # plaintext restored — good
```

**Finding**: Manual conflict resolution does NOT corrupt encrypted files. The file stays valid ciphertext, round-trips lock/unlock cleanly. So git-crypt's behavior is "fail loudly with merge conflict" — not "silent corruption." This is slightly better than the worst-case fear, but:

- **Auto-merge is impossible.** User loses one side's changes every time (resolver picks ours or theirs).
- **Every divergent edit blocks the auto-sync loop.**
- **Manual intervention is required on every sync cycle** that involves cross-device edits to any encrypted file.

## Impact on bobusang

`sync-memory.sh` runs on session start and typically more often. It does `fetch + rebase`. With git-crypt + encrypted memory files + any cross-device activity, **every sync cycle that involves an edit conflict stalls with an error the user must manually resolve**, and the resolution always loses one side's content.

This breaks bobusang's core value proposition: "memory is written on any device, transparently synced everywhere." With git-crypt, the synced path for encrypted files is not transparent — it is manual, lossy, and interrupts flow.

**Author discipline workaround** ("never edit encrypted files on two devices simultaneously") would avoid the conflicts but:
1. It's exactly the kind of unreliable author-discipline defense that v2.1 devil rejected.
2. bobusang users include the maintainer running on 4 devices including GPU servers. The workaround would force per-device file compartmentalization, which was already rejected (option C: "all devices write freely").

## Comparison to transcrypt (what's different)

transcrypt's `.gitattributes` line registers THREE drivers:

```
memory/secrets/** filter=crypt diff=crypt merge=crypt
```

The `merge=crypt` entry points to a custom merge driver that **decrypts both sides plus the common ancestor, runs the normal three-way merge on plaintext, then re-encrypts the result**. This is the fix git-crypt never shipped. It was added to transcrypt in response to issue #69.

Spike B has **not verified** that transcrypt's merge driver actually works for bobusang's scenarios — that is Spike D's job. But Spike B confirms that git-crypt lacks the facility entirely, which is the root of bobusang's unavoidable breakage on git-crypt.

## Verdict

| Question | Answer |
|----------|--------|
| Does git-crypt's merge breakage reproduce on current toolchain? | **YES** |
| Is the cause transient/fixable? | **NO** (missing merge driver, unreleased for years) |
| Does it impact bobusang's daily workflow? | **YES** (every sync with cross-device edits stalls) |
| Is there an author-discipline workaround? | **YES in theory, NO in practice** (matches rejected v2.1 pattern) |
| Does rev 3's switch to transcrypt remain justified? | **YES** |

## Go/No-go

**GO on transcrypt**. The rev 3 primitive choice stands. Spike B is the only hands-on confirmation of rev 3's single load-bearing justification (per devil round 2): "git-crypt is broken for our workflow."

No rev 4 reversal of primitive choice is warranted by this spike.

## What this spike does NOT cover

Spike B confirms git-crypt is broken. It does NOT confirm transcrypt works. That's Spike A (full-stack) and Spike D (merge edge cases). If A or D fails, rev 4 is needed — but the failure would be "transcrypt also broken" rather than "git-crypt was fine."

## Cleanup

```bash
rm -rf /tmp/spike-b-gitcrypt
```

No persistent state from this spike.
