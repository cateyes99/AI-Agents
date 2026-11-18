---
name: Git Message Rewrite
description: 'Rewrite commit messages on a git branch (fix typos, replace branch names in merge messages) with git filter-branch --msg-filter, WITHOUT checking out the target branch. Use when: fixing typos in commit messages, renaming a branch name that appears in merge commit messages, correcting text across commit history, rewriting history locally. Covers investigation, backup, rewrite, and verification. NEVER pushes.'
---

# Git Commit Message Rewrite (filter-branch, no checkout)

Rewrite messages on a branch (typically `master`) without checking it out, using
`git filter-branch --msg-filter`. Battle-tested three times (Nividia→Nvidia Nov 9;
`cateyes99/cline+DS4.1Flash`→`cateyes99/DS4.1Flash` Nov 16; `on OpenCode`→`via
OpenCode` inside `OpenCodeCLI+DS4.1F …` subjects Nov 18 — first run with spaces in
the text and with the cwd inside a subdirectory of the repo).

## Arguments

The user may invoke this skill as `/git-message-rewrite <branch> <old-text> <new-text> [anchor-commit]`,
or by describing the rewrite in prose. Resolve the four inputs before Phase 1 and
ask for anything missing — never guess a branch name or a replacement text.

## Skill files

`scripts/investigate.ps1` and `scripts/verify.ps1` live beside this `SKILL.md`.
Resolve them against the skill base directory reported when this skill was loaded
(referred to below as `<skill-dir>`); they are not loaded into context
automatically — run them, don't read them.

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
6. **Run Phase 3 from the repo toplevel.** `git filter-branch` refuses to run from
   a subdirectory of the work tree — it aborts with the confusing
   `fatal: could not open '<subdir>/nul' for reading: No such file or directory`
   followed by `You need to run this command from the toplevel of the working
   tree`. If the cwd is a workspace folder nested inside the repo, `cd` to
   `git rev-parse --show-toplevel` first (investigate.ps1 prints it).

## Procedure

### Phase 1 — Investigate (read-only)

Invoke `scripts/investigate.ps1` through the shell tool:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/investigate.ps1 -Branch master -OldText 'cateyes99/cline+DS4.1Flash'
```

It reports: affected commits (subjects + parents), whether all are merges, the
earliest affected commit (the anchor), range size, GPG-signed commits inside the
range (will lose signatures) vs below it (preserved), stale `refs/original` refs
(blocking), work-tree cleanliness, and the repo toplevel (Phase 3 must run from
there). **Stop and present findings to the user before rewriting** — especially
the signature-loss list.

This is read-only and safe to run at any time; run it before asking for approval,
not after.

If the user supplied an anchor SHA as an argument, cross-check it against the
investigation: it must equal the earliest affected commit (or its parent). If it
disagrees, trust the investigation and say so — the user's SHA may be stale or
abbreviated from a different history.

### Phase 2 — Backup

```powershell
git branch <branch>_before_<fixname> <branch>
```

### Phase 3 — Rewrite (no checkout needed)

**Run from the repo toplevel** (`git rev-parse --show-toplevel`), not from a
subdirectory — see hard rule 6. From a subdirectory filter-branch aborts with
`fatal: could not open '<subdir>/nul' for reading` before touching anything
(harmless, but retry from the toplevel).

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

**Spaces in OLD/NEW (verified Nov 18):** `sed s,a b,c d,g` word-splits in sh —
the filter becomes `sed s,a` plus a stray `b,c` argument and silently matches
nothing (or errors). Backslash-escape every space: `sed s,a\ b,c\ d,g`. The
backslashes survive PowerShell → git → sh intact and sh un-escapes them inside
the sed script. Example from a real run:

```powershell
git filter-branch --msg-filter 'sed s,OpenCodeCLI+DS4\.1F\ on\ OpenCode,OpenCodeCLI+DS4.1F\ via\ OpenCode,g' -- 9fed2b7~1..DS4.1Flash-improvement
```

**Regex escaping in the sed pattern (BRE):** escape `.` as `\.` (it matches any
character otherwise — `DS4.1F` would also match `DS4x1F`). Do NOT escape `+` —
in POSIX BRE `+` is literal, while `\+` is a GNU quantifier ("one or more of
the previous atom") and would corrupt the match.

filter-branch updates the target ref directly; the checked-out branch and work
tree are untouched (it only requires a clean work tree).

### Phase 4 — Verify

Invoke `scripts/verify.ps1`:

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
  `GIT_SEQUENCE_EDITOR`/`GIT_EDITOR`) exists but cannot preserve committer identity
  (GitHub web-flow merges become the local user) and adds a trailing blank line
  to `merge -c` messages. Prefer filter-branch for pure message rewrites.
- Ground-truth signature check is `git cat-file commit <sha>` matching `^gpgsig `
  — `%G?` can report `N` for genuinely signed commits when the keyring is absent.
- **Workspace ≠ repo root:** editor workspaces are often a subdirectory of the
  git repo (here: workspace `Cline+DS4.1F`, repo root `E:\Source\Solar-System-Explorer`).
  Any command that must run at the toplevel (filter-branch, some hooks) needs an
  explicit `cd` — `git rev-parse --show-toplevel` / `--show-prefix` tell you where
  you are. investigate.ps1 now prints both.
- **The shell tool's cwd is per call.** OpenCode's shell tool starts each command
  in the session directory, so a `cd` does not persist — put the `cd` inside the
  same command as the `git filter-branch` invocation (use the tool's `workdir`
  option where available).
- **A failed filter-branch leaves nothing behind:** the toplevel abort happens
  before the `.git-rewrite` tempdir is created, so a failed run needs no cleanup —
  just fix the cause and re-run. (If a mid-rewrite failure ever leaves
  `.git-rewrite` behind, `git filter-branch` refuses to start until it is removed.)
- **msg-filter quoting workaround (script file):** If the inline `sed` form keeps
  failing because backslash-escaped spaces (`\ `) don't survive the PowerShell →
  git → sh shell layers (symptom: `sed: unterminated 's' command` or
  `fatal: bad revision 'encode\'`), write the sed command to a small shell script
  and point `--msg-filter` at it instead. This bypasses all quoting/escaping
  layers entirely:
  ```powershell
  # Create the filter script (spaces unescaped — no shell layers involved)
  Set-Content -Path .git-msgfilter.sh -Value @'
  #!/bin/sh
  sed 's,: encode 2026-11-18 rewrite lessons,: encode 2026-11-18 rewrite lessons for git-message-rewrite,g'
  '@
  # Run filter-branch using the script (run from repo toplevel)
  $env:FILTER_BRANCH_SQUELCH_WARNING = 1
  git filter-branch --msg-filter 'e:/Source/AI-Agents/.git-msgfilter.sh' -- <anchor>~1..<branch>
  # Clean up
  Remove-Item -Force .git-msgfilter.sh
  ```
  Use forward slashes in the script path (`e:/Source/...`), not backslashes.
  Delete the script after the rewrite succeeds.
