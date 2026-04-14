# Ecosystem Audit — Memory Encryption Primitive for v2.2

**Date**: 2026-04-14
**Author**: bobusang ecosystem audit (conducted via research agent)
**Purpose**: Confirm or replace git-crypt as the encryption primitive for bobusang v2.2.

## Summary verdict

**Switch to transcrypt (with caveats), or stay on git-crypt only if the symmetric-key path is acceptable and the team accepts the dormant-master risk.**

git-crypt's master branch has not received a commit since **2018-02-16**; the 0.8.0 tag (Sept 2025) was cut from a side branch and amounts to a compatibility hotfix, not active development. transcrypt is genuinely active (last commit 2026-04-06, v2.3.1 in Feb 2025) and shipped a custom merge driver in response to the very failure mode bobusang cares about. git-agecrypt is the most architecturally elegant option but carries an explicit "not audited, use at your own risk" disclaimer from a single maintainer with no tagged releases — too immature for a tool guarding cross-device secrets.

## Comparison table

| # | Dimension | git-crypt | transcrypt | git-agecrypt (vlaci) |
|---|---|---|---|---|
| 1 | Last release | 0.8.0 — 2025-09-24 (off side branch) | v2.3.1 — 2025-02-24 | None (no GitHub releases) |
| 2 | Last commit (default branch) | **2018-02-16** on `master` (0.8.0 branch active 2025-09-24) | 2026-04-06 on `main` | 2024-03-11 on `main` |
| 3 | Open issues / staleness | 124 open / many multi-year ("rename", "Windows", "merge"); high stale ratio | 31 open; most recent issues triaged or closed | 3 open; tiny issue tracker |
| 4 | Bus factor | **1** (Andrew Ayer / AGWA) | Effectively 1 (elasticdog) but with steady contributor PRs | **1** (vlaci) |
| 5 | Stated status | README: "not yet mature"; no abandonment notice but master is dormant | Active; regular tagged releases | README: "not audited… use at your own risk" |
| 6 | Known CVEs | None found in NVD or GitHub advisories as of audit date | None found | None found |
| 7 | Dependencies | C++; OpenSSL (3.x as of 0.8.0); optional GnuPG for asymmetric mode | Bash; OpenSSL CLI (AES-256-CBC); optional GnuPG | Rust; `age` library; blake3; libgit2 |
| 8 | Platform support | Linux, macOS, Windows (Windows support is open issue #22 — partial/painful) | Linux, macOS; Windows works under WSL/Git Bash; native Windows is messy | Linux, macOS via Cargo; Windows unverified |
| 9 | Install story | apt (`git-crypt` in Debian/Ubuntu), brew, pacman, source build; binary releases sporadic | brew, AUR, NixOS, Heroku buildpack; "clone + symlink" supported; **no apt package in mainline Ubuntu** | `cargo install` from source or Nix flake; no distro packages |
| 10 | Multi-device key UX | `git-crypt export-key file` → out-of-band copy; OR `add-gpg-user` to ship encrypted keyfiles in repo | `--display`/`--export-gpg`/`--import-gpg`; symmetric password+cipher; team docs treat as pre-shared secret | age recipients in `.gitattributes`-like config; identity files live outside repo per device; **no key material in repo** — most natural multi-device story |
| 11 | Merge conflict behavior | No custom merge driver. Issues #20, #273 report broken merges (esp. with newer git ≥2.39); known sharp edge | **Has** a custom merge driver (registered via `.gitattributes`); historically buggy (#69, closed) but fixed; merges decrypt before three-way | Custom smudge/clean via age; no documented merge driver; merge behavior unverified |
| 12 | File-rename (encrypted ↔ plaintext path) behavior | Path matched by `.gitattributes`; renaming out of an encrypted glob silently changes filter applied; no built-in safeguard | Same model — driven by `.gitattributes`; same risk; #192 hints at filter-state confusion | Same `.gitattributes` model; even less guidance |

## Failure mode search

### git-crypt
- **Merge conflict**: #20 ("Merge and Rebase with remote repo fail") and #273 ("After git 2.39.1 git-crypt not working merge command") — both **OPEN**, multi-year, no fix. Suggests routine `git merge` against an updated git client can break unlock state.
- **Corruption**: #230 ("malformed key file… may be corrupted") and #300 ("git-crypt unlock fails") open. #78 (closed): running `git-crypt init` on an already-initialized repo "renders the data unreadable" — a foot-gun rather than silent corruption, but a real loss path.
- **Rename**: No issue specifically about plaintext↔encrypted path moves causing corruption; closest is #170 (how to undo git-crypt cleanly), still open.
- **Windows**: #22 ("Windows support") still open after years — first-class Windows is not a thing.
- **Shallow clone, autocrlf, submodules**: #155 (sparse checkouts broken, open); #261 (submodule unlock issues, closed). No clean autocrlf story.
- **Direct answer to "has anyone reported a routine git op silently corrupting encrypted files?"**: No clear "silent corruption" report, but #20/#273 (merge breakage) and #229 (unlock with dirty tree) put users one wrong move away from manual recovery.

### git-agecrypt (vlaci)
- Issue tracker is essentially empty for all the failure-mode keywords — but that reflects **low usage**, not robustness. With ~110 stars and no releases, absence of bug reports is not evidence of absence of bugs.
- README explicitly disclaims security review.

### transcrypt
- **Merge conflict**: #69 (closed) is exactly the bobusang failure case — three-way merge running on ciphertext, producing garbage. Resolved by adding a custom merge driver. This is the most reassuring single data point in the entire audit: the maintainer recognized the failure mode and fixed it.
- **Corruption**: #146 (closed) — "git reports files as modified" — clean-filter idempotence bug, fixed.
- **Windows**: #78 (closed) catalogs Windows quirks and workarounds; clearly not a first-class platform but documented.
- **Rename**: #192 (closed) — `transcrypt --list` not finding files after init, suggests filter-state edge cases exist but get fixed.
- **Submodules**: #88 still open — submodules are unsupported.
- **No reports of silent corruption from routine pull/merge** found in the issue tracker.

## Concerns raised

Regardless of which tool is picked, the bobusang v2.2 design should explicitly address:

1. **`.gitattributes` is the single source of truth for which files are encrypted.** A typo, an accidental delete, or a rebase that drops `.gitattributes` will commit plaintext to the remote. v2.2 needs a pre-commit hook (or wrapper around `git commit`) that double-checks every file under `memory/secrets/**` is going out as ciphertext.
2. **Rename across the encryption boundary is dangerous in all three tools.** Moving a file out of `memory/secrets/` should require an explicit unlock step, not happen as a silent side effect of `git mv`.
3. **Merge conflicts on encrypted files are a known sharp edge industry-wide.** Even transcrypt's merge driver can only do a three-way merge on the *plaintext*; conflicts still need a human. Document the recovery procedure now, not after the first incident.
4. **Key recovery on a wiped device.** All three tools assume the user has the key elsewhere. bobusang's threat model says "not defending against device compromise," but it should say what happens if a device dies and the only key copy died with it. A documented backup location (1Password, hardware token, paper) is a v2.2 deliverable, not an afterthought.
5. **`git-crypt init` re-run footgun (#78)** generalises: any of these tools can be broken by re-initializing on top of an existing setup. The bobusang installer must detect "already initialized" and refuse.
6. **Auto-unlock ergonomics widen the blast radius.** If the key is in a keychain that unlocks at login, "device compromise is out of scope" effectively means "we have no defense in depth." Consider an explicit unlock-on-demand mode for the most sensitive subdirectory.
7. **Encrypted blobs do not delta-compress.** git-crypt README calls this out; it applies to all three. Memory files that change frequently will balloon repo size. Either keep `secrets/` small or plan periodic history rewrites.

## Recommendation

**Switch the v2.2 design to transcrypt as the primary candidate, and run the planned spikes against it.**

Rationale:

- **Activity**: transcrypt has commits in the last week of the audit window; git-crypt's master is dormant for 8+ years and only ships off side branches.
- **The single most important failure mode (merge conflict on encrypted files) has been addressed in transcrypt with a custom merge driver, and was fixed in response to a user report — exactly the kind of maintainer engagement bobusang needs.** git-crypt has the same failure mode open as #20 and #273 with no fix.
- **Bash + openssl CLI is a smaller, more inspectable trusted base** than C++ + OpenSSL linkage for a tool that lives on four devices including production.
- **Multi-device key distribution** is comparable: both expect the user to ferry a symmetric key out-of-band, which matches bobusang's existing `P:/ssh-keys/` + `ops-config` pattern.

Reasons **not** to pick git-agecrypt despite its nicer architecture (age, identity files outside repo, no key in repo):

- No tagged releases, single maintainer, explicit "not audited" disclaimer.
- Zero distro packaging — every device needs a Rust toolchain or Nix.
- No track record on Windows/WSL, and bobusang runs on two WSL2 boxes.
- It is the right tool to revisit in v2.3 if it grows up.

Reasons to **stay** on git-crypt anyway (if the team disagrees):

- It is already in `apt` on every target device, install is one command.
- The symmetric-key flow (`export-key` → copy via `P:/ssh-keys/`) maps 1:1 onto bobusang's existing key sync.
- The merge-conflict failure mode can be mitigated by **never editing `memory/secrets/**` on two devices simultaneously** — a discipline rule, not a code change. If the team accepts that constraint, git-crypt's dormancy is tolerable.

If the team wants a single-line answer: **transcrypt for safety, git-crypt for install convenience, git-agecrypt for nobody yet.**

## Next steps for v2.2

1. **Update `v2.2-git-crypt.md`**: rename to `v2.2-encryption.md` (or similar) and rewrite the "encryption primitive" section to present transcrypt as the primary, git-crypt as the fallback, git-agecrypt as a noted alternative.
2. **Run two parallel spikes** instead of the planned git-crypt-only spike:
   - Spike A: transcrypt + `memory/secrets/**` glob, exercise clean/smudge, simulate a three-way merge conflict, verify the merge driver behaves.
   - Spike B: git-crypt with the same scenarios; specifically reproduce issue #273 against the current git version on a target device.
3. **Write the seven "Concerns raised" items above into the v2.2 design as explicit acceptance criteria.** Especially: pre-commit ciphertext check, rename-across-boundary guard, key backup procedure, re-init detection.
4. **Document the merge-conflict recovery runbook** before shipping, not after the first incident. Include: how to identify a corrupted-on-merge encrypted file, how to roll back, how to re-encrypt cleanly.
5. **Decide on auto-unlock policy.** If auto-unlock is the default on all four devices, the threat model section should be updated to acknowledge that device compromise == full memory disclosure.
6. **Re-audit in 6 months.** git-agecrypt may mature; git-crypt may or may not see another tag; transcrypt may stagnate. The audit cadence should match the criticality of what is being encrypted.
