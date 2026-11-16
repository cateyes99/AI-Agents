---
name: git-message-rewrite
description: 'Rewrite commit messages on a git branch (fix typos, replace branch names in merge messages) using git filter-branch, WITHOUT checking out the target branch. Use when: fixing typos in commit messages, renaming a branch name that appears in merge commit messages, correcting text across commit history, rewriting history locally. Covers investigation, backup, rewrite, and verification. NEVER pushes.'
argument-hint: '<branch> <old-text> <new-text> [anchor-commit]'
user-invocable: true
disable-model-invocation: false
---

# Git Commit Message Rewrite (filter-branch, no checkout)

Rewrite messages on a branch (typically `master`) without checking it out, using
`git filter-branch --msg-filter`. Battle-tested twice on this repo (Nividia→Nvidia
Nov 9; `cateyes99/cline+DS4.1Flash`→`cateyes99/DS4.1Flash` Nov 16).

## Hard rules (non-negotiable)

1. **NEVER push.** The user pushes themselves after review. State this explicitly.
2. **Only touch the named branch.** Never other branches.
3. **Always create a visible backup branch first** (`<branch>_before_<fix>`).
4. **Anchor the range at the earliest affected commit's parent** (`<earliest>~1`),
   NOT at a merge-base guess. Everything below the anchor keeps its hashes.
   **Root exception:** if the earliest affected commit IS the root commit (no
   parent exists), do NOT use `<root>~1` — that is a fatal revision error. Omit
   the range entirely and pass the branch name as the sole rev-list argument:
   `git filter-branch --msg-filter '...' <branch>`. This rewrites from the root
   inclusively while still touching ONLY that branch. NEVER use `-- --all` for
   this: it rewrites EVERY local branch.
5. **Report signature loss honestly**: every commit inside the range loses its GPG
   signature (filter-branch strips `gpgsig`). Inventory them BEFORE the rewrite so
   the user can decide.

## Procedure

### Phase 1 — Investigate (read-only)

Run [scripts/investigate.ps1](./scripts/investigate.ps1):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/investigate.ps1 -Branch master -OldText 'cateyes99/cline+DS4.1Flash'
```

It reports: affected commits (subjects + parents), whether all are merges, the
earliest affected commit (the anchor), range size, GPG-signed commits inside the
range (will lose signatures) vs below it (preserved), stale `refs/original` refs
(blocking), and work-tree cleanliness. **Stop and present findings to the user
before rewriting** — especially the signature-loss list.

### Phase 2 — Backup

```powershell
git branch <branch>_before_<fixname> <branch>
```

### Phase 3 — Rewrite (no checkout needed)

Normal case (anchor has a parent):

```powershell
$env:FILTER_BRANCH_SQUELCH_WARNING = 1
git filter-branch --msg-filter 'sed s,<OLD>,<NEW>,g' -- <anchor>~1..<branch>
```

Root case (earliest affected commit IS the root — `<root>~1` is a fatal error):

```powershell
$env:FILTER_BRANCH_SQUELCH_WARNING = 1
git filter-branch --msg-filter 'sed s,<OLD>,<NEW>,g' <branch>
```

No range = rewrite ALL commits reachable from `<branch>`, root included, while
still touching only that branch. (Note: `--root` is NOT a filter-branch option —
the script's option parser rejects it with a usage error. Verified against the
shipped script's source.)

**CRITICAL quoting trap (PowerShell):** do NOT write `sed "s|a|b|g"`. PowerShell
strips the inner double quotes, so sh receives `s|a|b|g` and treats `|` as pipes
→ `g: command not found`, and the run aborts harmlessly. Use **comma delimiters,
no quotes**: `sed s,a,b,g` — commas are inert in both PowerShell and sh. If the
text itself contains commas, use another inert delimiter (e.g. `s@a@b@g`).

filter-branch updates the target ref directly; the checked-out branch and work
tree are untouched (it only requires a clean work tree).

### Phase 4 — Verify

Run [scripts/verify.ps1](./scripts/verify.ps1):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/verify.ps1 -Branch master -BackupBranch master_before_<fixname> -OldText 'cateyes99/cline+DS4.1Flash' -NewText 'cateyes99/DS4.1Flash' -Anchor 'f166049~1'
```

Checks: 0 occurrences of old text, N of new text, commit/merge counts preserved,
**empty tree diff** vs backup (code identical), merge-base, unchanged-hash count,
GPG-signature count before/after, bottom-of-history identity, and that other
branches are untouched. Pass `-Anchor 'NONE'` for root-case rewrites: the
merge-base and bottom-of-history checks are skipped (a full-history rewrite has
NO common ancestor between old and new — merge-base exits 1 — and 0 unchanged
hashes is the expected result, not a failure).

### Phase 5 — Report and stop

Present: what changed, verification table, which signatures were stripped,
rollback command (`git update-ref refs/heads/<branch> <backup-sha>`), and the
push command the USER must run (`git push --force-with-lease origin <branch>`).
Mention `refs/original/refs/heads/<branch>`: filter-branch's frozen backup —
never auto-updated, blocks the next filter-branch run until deleted — and give
the deletion command explicitly so the user isn't left guessing:

```powershell
git update-ref -d refs/original/refs/heads/<branch>
```

Advise deleting it only AFTER the user has reviewed and pushed (it is a free
second rollback path until then).

## Notes

- Merge-commit message *bodies* are rewritten too (msg-filter sees full `%B`).
- Commits in range whose message AND parent-mapping are unchanged keep their
  hashes — so unchanged-hash count can exceed the below-anchor count.
- `git range-diff <anchor>~1..<backup> <anchor>~1..<branch>` is the best human
  review artifact; quote the ranges in PowerShell. For root-case rewrites use
  `git range-diff <backup> <branch>` (whole-history comparison).
- Rebase alternative (`rebase -i --rebase-merges` with scripted
  GIT_SEQUENCE_EDITOR/GIT_EDITOR) exists but cannot preserve committer identity
  (GitHub web-flow merges become the local user) and adds a trailing blank line
  to `merge -c` messages. Prefer filter-branch for pure message rewrites.
- Ground-truth signature check is `git cat-file commit <sha>` matching `^gpgsig `
  — `%G?` can report `N` for genuinely signed commits when the keyring is absent.
