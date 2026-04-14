# Spike A — transcrypt Full-Stack Verification + Bash Audit

**Date**: 2026-04-15
**Purpose**: Verify transcrypt actually works end-to-end for bobusang's target workflow. Also manually audit the bash script for quoting/injection hygiene (the audit's "smaller trusted base" claim needed empirical backing). Also confirm "active maintenance" is quality, not churn.
**Verdict**: **PASS with notes.** GO for implementation against transcrypt. Spike D still required for merge edge cases.

## Environment

| Component | Version |
|-----------|---------|
| OS | Ubuntu 24.04 (WSL2) |
| git | 2.43.0 |
| OpenSSL | 3.x (via `/usr/bin/openssl`) |
| transcrypt | 2.3.1 (from GitHub release tarball) |
| Release SHA256 | `c5f5af35016474ffd1f8605be1eac2e2f17743737237065657e3759c8d8d1a66` |

## Part 1 — Install path

`apt install transcrypt` is not available on mainline Ubuntu 24.04 (confirmed). The install path bobusang's `setup.sh` will have to automate:

```bash
curl -sL -o transcrypt.tar.gz \
  "https://github.com/elasticdog/transcrypt/archive/refs/tags/v2.3.1.tar.gz"
sha256sum transcrypt.tar.gz   # verify against expected
tar -xzf transcrypt.tar.gz
cp transcrypt-2.3.1/transcrypt ~/.local/bin/
chmod +x ~/.local/bin/transcrypt
```

`transcrypt --version` → `transcrypt 2.3.1`. Single-file bash script (54125 bytes, 1631 lines).

**Finding**: the install is trivial but **does require network access during setup.sh**. If bobusang targets air-gapped environments (unlikely but worth noting), the tarball needs to be bundled with bobusang's repo or fetched via some other channel.

**Action for bobusang**: `setup.sh` should embed the expected SHA256 per pinned version and verify it after download. A rogue GitHub release replacement is the realistic threat — not that transcrypt maintainer goes evil, but that the tarball URL gets redirected at the CDN layer. SHA256 pin defends against that.

## Part 2 — Full-cycle test

Goal: simulate two devices syncing encrypted memory through a bare remote, confirm encryption at rest, and test the merge driver.

### Setup

```bash
git init --bare remote.git
git clone remote.git repo-a    # device A
cd repo-a
transcrypt -y -p 'test-password-12345' -c aes-256-cbc
echo "secrets/** filter=crypt diff=crypt merge=crypt" > .gitattributes
mkdir -p secrets
echo "sensitive content" > secrets/file.md
echo "public data" > public.md
git add -A && git commit -m "initial"
git push -u origin main
```

`git ls-crypt` (a new alias transcrypt installs) correctly showed `secrets/file.md`. Clone to a fresh directory without the key and inspect:

```
secrets/file.md: openssl enc'd data with salted password, base64 encoded
00000000: 5532 4673 6447 566b 5831 3874 6375 614d  U2FsdGVkX18tcuaM
```

**Confirmed**: `U2FsdGVk` is base64 for `Salted__`, transcrypt's encrypted file format. `public.md` on the same clone was visible as plaintext. `.gitattributes` had all three drivers as expected.

### Multi-device cycle

1. Clone the bare remote as `repo-b`, unlock with `transcrypt -y -p 'test-password-12345'`
2. Verify: `cat secrets/file.md` → plaintext visible
3. Device B edits and commits → pushes
4. Device A `git pull --ff-only` → fast-forward succeeds, file updated, plaintext correct

**Fast-forward pull works.** Ciphertext flows correctly through the bare remote.

### 3-way merge on encrypted file

Divergent edits on adjacent lines (same file, non-overlapping in a strict sense but adjacent enough that git's diff algorithm treats them as conflicting):

- Device A: modifies line 2
- Device B: modifies line 3 (pushes first)
- Device A: `git pull` (with `pull.rebase=false`)

**Result**:

```
Auto-merging secrets/file.md
CONFLICT (content): Merge conflict in secrets/file.md
Automatic merge failed; fix conflicts and then commit the result.
```

Working tree `secrets/file.md` contains **plaintext conflict markers**:

```
device A initial content
<<<<<<< main
A-MODIFIED LINE 2
line three
=======
line two
B-MODIFIED LINE 3
>>>>>>> theirs
device B APPENDED
```

This is the critical difference from git-crypt (Spike B). Git-crypt produced "Cannot merge binary files" and left the working tree untouched. transcrypt's merge driver **decrypted all three sides (BASE, OURS, THEIRS), ran `git merge-file` on plaintext, and wrote plaintext conflict markers**. The user can resolve normally with any text editor.

Manual resolve + re-commit → transcrypt's clean filter re-encrypts on commit → a fresh clone without the key sees ciphertext again (verified with a second inspection clone: different `U2FsdGVk...` prefix, confirming new encryption).

**Pass**: full cycle works. Merge driver works. At-rest encryption holds through the cycle.

## Part 3 — Bash script hygiene audit

Manual reading of `transcrypt` (1631 lines), targeted at shell injection and quoting mistakes.

### Positive findings

- **`set -euo pipefail`** at top. Strict mode active from line 2.
- **No `eval`** anywhere in the script.
- **No unquoted `$var` in `rm`/`mv`/`cp` commands.** Grep confirmed.
- **File paths quoted** in all the I/O functions (`git_clean`, `git_smudge`, `git_merge`, `git_textconv`).
- **Password handling via env var** (`ENC_PASS=$password openssl enc -pass env:ENC_PASS ...`) — never on the command line where `ps` could capture it.
- **Openssl invocations are minimal and clean**: one real call in `git_clean` (line 271) and one in `git_smudge` (line 297). The path is pulled from `git config --get --local transcrypt.openssl-path`, quoted in use.
- **Filename used as HMAC salt input** (line 264: `salt=$("${openssl_path}" dgst -hmac "${filename}:${password}" -sha256 "$tempfile" ...`). Filename here is input to HMAC, not a shell argument — safe even with metacharacters.
- **Recent fix #204**: "Fix listing of file names with special characters to avoid crash and unrecognised names" was committed 2025-09-27, addressing exactly the kind of bash hygiene concern the audit raised.

### Real quirks found (not injection, but worth recording)

1. **`git_merge()` strips trailing newlines** via `echo "$(cat "$1" | ... smudge)" >"$1"`. Command substitution in bash strips trailing newlines. If the original file ended with `\n` (most text files do), the decrypted version written back during merge will be missing that newline. On re-encryption via the clean filter, the file's content hash changes vs a direct-clean of the same plaintext. **Impact on bobusang**: cosmetic diff noise after every merge on markdown files. Not data loss, just ugliness. Worth flagging in the merge-conflict runbook.

2. **`GIT_REFLOG_ACTION` dependency in `git_merge()`**. To determine the "theirs" branch label, the driver parses `GIT_REFLOG_ACTION` environment variable:
   ```bash
   if [[ "${GIT_REFLOG_ACTION:-}" = "merge "* ]]; then
       THEIRS_LABEL=$(echo "$GIT_REFLOG_ACTION" | awk '{print $2}')
   fi
   ```
   There's a `TODO` comment from the author: "*There must be a better way of doing this than relying on this reflog action environment variable, but I don't know what it is*". This is **fragile to future git internals changes** — if git ever removes or reformats that env var, the merge driver's labels degrade to generic "theirs". Not a security issue, not a data issue, just cosmetic and a future-maintenance risk.

3. **`TRANSCRYPT_PATH="$(dirname "$0")/transcrypt"`** in `git_merge()` recursively invokes the same script from its own directory. Works fine in practice (properly quoted), but means the script must remain in place after install — if a user moves the binary after running `setup.sh`, the merge driver breaks. bobusang's `setup.sh` installs to `~/.local/bin/transcrypt` and should document: "do not move or rename."

4. **OpenSSL deprecation warnings** spam stderr on every clean/smudge:
   ```
   *** WARNING : deprecated key derivation used.
   Using -iter or -pbkdf2 would be better.
   ```
   This is OpenSSL 3.x complaining about transcrypt's `-md MD5` key derivation without PBKDF2 iterations. **Not a compromise of the encrypted content** (the password's brute-force resistance against the ciphertext is still governed by password entropy, not the KDF), but it is a security smell and will produce verbose `setup.sh` output. The maintainer could fix this by switching to `-pbkdf2 -iter 100000` — a simple change that would modernize the KDF. That this hasn't been done in v2.3.1 is a mild maintenance signal.

5. **MD5 hash function** used in key derivation. Combined with the PBKDF2 absence, this means transcrypt uses AES-256-CBC with an MD5-derived key. MD5 is collision-broken but not preimage-broken for this use case, so it's not a direct vulnerability, but it's not what a new crypto design would pick in 2026.

### Non-findings (things that could have been bad but weren't)

- No `eval`
- No unquoted path expansions in destructive commands
- No `$@` without quotes when passing args
- No dangerous `find ... -exec` patterns
- No raw user input concatenated into shell commands
- openssl password via env var, not argv

### Audit conclusion

**transcrypt's bash hygiene is competent but not pristine.** The KDF choice (MD5 without PBKDF2 iterations) is the most significant concern — not because it enables an attack, but because it signals the crypto layer has not been modernized in a long time. The bash layer itself handles quoting correctly and does not have obvious injection paths.

For bobusang's threat model (remote repo leak), the KDF matters only to the extent that an attacker with the ciphertext runs offline brute force against the repo password. Brute-force resistance is governed by password entropy × KDF cost. With MD5 single-pass derivation, the attacker's cost per guess is very low (microseconds). **Recommendation for bobusang**: when running `setup.sh`, generate the transcrypt password via `openssl rand -base64 32` (256 bits of entropy), not a user-typed password. That makes the KDF weakness irrelevant — at 256 bits, brute force is impossible regardless of KDF strength.

Document this in the setup flow: the password is **machine-generated and user-backed-up**, never user-typed.

## Part 4 — Recent commit quality check

Audit's claim: "active maintenance, last commit 2026-04-06". Devil round 2 concern: "active" might mean "churn".

Pulled the 10 most recent commits from GitHub API:

| Date | Commit |
|------|--------|
| 2026-04-06 | "Fix badly formatted maintainer email address in README" (trivial) |
| 2026-04-06 | "Apply work-around... fix `unbound variable` error in Bash < 4.4 (e.g. on macOS)" (compatibility fix) |
| 2026-04-06 | "Fix linting errors found by shellcheck on Linux run in GitHub" (CI hygiene) |
| 2026-04-06 | "Find context definitions across all attributes config files" (feature + fix) |
| 2026-04-06 | "Tidy up `git worktree` fix" (fix polish) |
| 2026-04-06 | "Improve git worktree support using `--git-common-dir`" (real fix) |
| 2026-04-06 | "Update GitHub Action test runners: macos-15" (CI) |
| 2025-09-27 | "Fix --list to work with strict context checks" (bug fix) |
| 2025-09-27 | "Add unit test for --list working with encrypted files with special characters in file name" (**relevant: bash hygiene test**) |
| 2025-09-27 | "Try to improve performance using awk instead of loop" (perf) |

**All 10 are bug fixes, compatibility patches, or real improvements.** No experimental rewrites, no churn. The **special-character-filename test** (#204 fix, added 2025-09) is directly relevant to the bash injection concern we raised — the maintainer has been tending to exactly the hygiene class we care about.

"Active maintenance" claim from audit is validated. Qualitative rating: **aware, responsive, conservative**.

## Summary of findings

| Test | Result |
|------|--------|
| Install via release tarball + SHA256 | ✅ (setup.sh automation is straightforward) |
| Single-device init + encrypt + commit | ✅ |
| At-rest ciphertext on remote | ✅ (`U2FsdGVk` base64 Salted__) |
| Multi-device clone + unlock | ✅ |
| Fast-forward pull on encrypted file | ✅ |
| 3-way merge with conflict | ✅ (plaintext conflict markers, normal resolve) |
| Manual resolve + re-encrypt cycle | ✅ |
| Bash script audit: eval, injection, quoting | ✅ (no findings in the bad categories) |
| Bash script audit: KDF quality | ⚠ MD5, no PBKDF2 — mitigate with high-entropy password |
| Bash script audit: merge driver trailing newline | ⚠ cosmetic diff noise after merge |
| Bash script audit: `GIT_REFLOG_ACTION` fragility | ⚠ cosmetic label degradation, no functional break |
| OpenSSL deprecation warnings on every op | ⚠ noise, not compromise |
| Recent commit quality (10 most recent) | ✅ all fixes/improvements, no churn |

## Go/No-go

**GO on transcrypt as the primary engine.**

The warnings above are real but all either (a) cosmetic or (b) mitigable in bobusang's `setup.sh` configuration. None are blockers.

Action items carried forward to implementation:

1. `setup.sh` downloads transcrypt 2.3.1 tarball, verifies SHA256 `c5f5af35...`, installs to `~/.local/bin/transcrypt`
2. `setup.sh` generates the repo password via `openssl rand -base64 32` rather than prompting the user to type one — makes the MD5-KDF concern irrelevant
3. Merge-conflict runbook (`docs/guides/merge-conflicts.md`) notes the trailing-newline quirk
4. `setup.sh` suppresses OpenSSL deprecation warnings from final output (or logs to a file instead of showing)
5. v2.2 design doc rev 4 (if needed) notes the `GIT_REFLOG_ACTION` fragility for future awareness

## What this spike does NOT verify

Spike A confirms the basic cycle and one merge conflict case. It does NOT verify:

- **Rename + modify conflicts** on encrypted files (Spike D)
- **`.gitattributes` conflict during pull** (Spike D)
- **`stash pop` through encrypted conflicts** (Spike D)
- **Octopus merge** on encrypted files (Spike D)
- **File-move detection** by a pre-commit check (Spike C)
- **Case-insensitive filesystem behavior** (macOS, Spike D)

Proceeding to Spike D next.

## Cleanup

```bash
rm -rf /tmp/spike-a-transcrypt
rm -f ~/.local/bin/transcrypt   # OPTIONAL — keeping for Spike D
```

For this spike I am **keeping `~/.local/bin/transcrypt` installed** to run Spike D against the same version.
