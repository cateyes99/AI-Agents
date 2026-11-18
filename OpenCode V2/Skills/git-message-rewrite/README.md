# git-message-rewrite

An **OpenCode V2** skill for rewriting commit messages on a git branch — fixing
typos, renaming branch names quoted in merge commit messages, correcting text
across history — using `git filter-branch --msg-filter`, **without checking out
the target branch**.

Ported from the GitHub Copilot skill of the same name.

Distilled from three production rewrites in the
[Solar-System-Explorer](https://github.com/cateyes99/Solar-System-Explorer)
repository:

| Date | Rewrite | Scale |
|---|---|---|
| 2026-11-09 | `Nividia` → `Nvidia` (subjects + merge bodies) | 26 commits |
| 2026-11-16 | `cateyes99/cline+DS4.1Flash` → `cateyes99/DS4.1Flash` (merge subjects) | 26 merge commits |
| 2026-11-18 | `on OpenCode` → `via OpenCode` inside `OpenCodeCLI+DS4.1F …` subjects | 4 commits (2 merges) |

## Why this exists

History rewrites are high-stakes and investigation-heavy. The expensive part is
rarely the rewrite itself — it's re-deriving, every time:

- which commits are affected, and where the earliest one sits (the **anchor**)
- how big the blast radius is (everything below the anchor keeps its hashes)
- which GPG-signed commits will lose their signatures (any rewrite strips them)
- which platform traps will silently break the filter command

This skill encodes all of it so the investigation is one command, not a dozen
exploratory round-trips.

## Structure

```
~/.config/opencode/
├── skills/
│   └── git-message-rewrite/
│       ├── SKILL.md                # Agent-facing procedure (loaded on demand)
│       ├── README.md               # This file
│       └── scripts/
│           ├── investigate.ps1     # Phase 1: read-only blast-radius analysis
│           └── verify.ps1          # Phase 4: post-rewrite verification battery
└── commands/
    └── git-message-rewrite.md      # /git-message-rewrite <branch> <old> <new> [anchor]
```

The skill **ID** is derived from the directory name: `git-message-rewrite`. The
frontmatter `name` (`Git Message Rewrite`) is only the display label.

## Install

### Global (personal, all projects) — what this port uses

```powershell
~/.config/opencode/skills/git-message-rewrite/   # %USERPROFILE%\.config\opencode\skills\...
~/.config/opencode/commands/git-message-rewrite.md
```

### Project scope

Copy the directory to `.opencode/skills/git-message-rewrite/` (and the command to
`.opencode/commands/`) inside the repository. Project definitions take precedence
over global ones with the same ID.

OpenCode also discovers `~/.claude/skills`, `~/.agents/skills`, `.claude/skills`
and `.agents/skills`; a directory can alternatively be registered with the
`skills` array in `opencode.json(c)`. No configuration change is required for the
two locations above.

## Usage

### Slash command (the Copilot `/skill args` equivalent)

```
/git-message-rewrite master cateyes99/cline+DS4.1Flash cateyes99/DS4.1Flash f166049
```

The command expands `$1`–`$4` into a prompt that loads the skill. Missing
arguments are requested rather than guessed, and the run always stops after
Phase 1 for approval.

### Mention the skill directly

```
@git-message-rewrite fix the typo "Nividia" -> "Nvidia" on master
```

### Automatic

The `description` frontmatter advertises the skill, so OpenCode also selects it
for requests like "fix this typo in all commit messages" or "rename the branch
name in our merge commits". The agent loads `SKILL.md` with the `skill` tool and
follows the five phases, running the bundled scripts.

To make the skill available only when named explicitly, add:

```yaml
metadata:
  opencode/autoinvoke: false
```

### Running the scripts directly

```powershell
# Phase 1 — investigate (read-only, safe to run anytime)
./scripts/investigate.ps1 -Branch master -OldText 'cateyes99/cline+DS4.1Flash'

# Phase 3 — the rewrite itself (after backup, from the repo toplevel)
$env:FILTER_BRANCH_SQUELCH_WARNING = 1
git filter-branch --msg-filter 'sed s,cateyes99/cline+DS4.1Flash,cateyes99/DS4.1Flash,g' `
    -- f166049~1..master

# Phase 4 — verify
./scripts/verify.ps1 -Branch master -BackupBranch master_before_branchname_fix `
    -OldText 'cateyes99/cline+DS4.1Flash' -NewText 'cateyes99/DS4.1Flash' -Anchor 'f166049~1'

# Root case — earliest affected commit IS the root commit:
# investigate.ps1 detects this and tells you to drop the range entirely:
$env:FILTER_BRANCH_SQUELCH_WARNING = 1
git filter-branch --msg-filter 'sed s,OLD,NEW,g' master        # no range, no '~1'
# ...and verify with -Anchor NONE (merge-base / unchanged-hash / bottom-of-history
# checks are skipped or inverted: a full rewrite has NO common ancestor and 0
# unchanged hashes by design)
./scripts/verify.ps1 -Branch master -BackupBranch master_before_fix `
    -OldText 'OLD' -NewText 'NEW' -Anchor 'NONE'
```

## Safety model

Non-negotiable rules baked into the procedure:

1. **Never pushes.** The user reviews and force-pushes themselves
   (`git push --force-with-lease origin <branch>`).
2. **Touches only the named branch.** Other branches are never rewritten.
3. **Always creates a visible backup branch first**
   (`<branch>_before_<fixname>`), in addition to filter-branch's own
   `refs/original/` backup.
4. **Anchors the range at `<earliest-affected>~1`**, not at a merge-base guess —
   everything below the anchor keeps its hashes and signatures. **Root
   exception:** when the earliest affected commit *is* the root commit, no
   parent exists — the skill switches to a whole-history rewrite
   (`git filter-branch --msg-filter '...' <branch>`, no range) instead of the
   impossible `<root>~1`.
5. **Reports signature loss before rewriting**, so the user can decide with full
   information.

## The five phases

| Phase | Tool | What happens |
|---|---|---|
| 1. Investigate | `scripts/investigate.ps1` | Read-only: affected commits, anchor, range size, signature exposure, blockers (stale `refs/original`, dirty tree). **Stops for user approval.** |
| 2. Backup | plain git | `git branch <branch>_before_<fixname> <branch>` |
| 3. Rewrite | `git filter-branch` | `--msg-filter 'sed s,<OLD>,<NEW>,g' -- <anchor>~1..<branch>` — updates the ref directly; checked-out branch and work tree untouched. Root case (earliest affected = root commit): omit the range — `git filter-branch --msg-filter '...' <branch>` rewrites from the root inclusively, still touching only that branch |
| 4. Verify | `scripts/verify.ps1` | Full battery: old text gone, counts preserved, tree identical, merge-base, unchanged hashes, signature delta, bottom-of-history identity |
| 5. Report & stop | — | Findings table, rollback command, user-run push command |

## Platform traps encoded in the skill

These were each discovered the hard way; the skill exists partly so they are
never re-discovered:

- **filter-branch must run from the repo toplevel.** From a subdirectory of the
  work tree it aborts before touching anything with the baffling
  `fatal: could not open '<subdir>/nul' for reading: No such file or directory`
  followed by `You need to run this command from the toplevel of the working
  tree`. This bites whenever the editor workspace is a folder *nested inside*
  the repo (the 2026-11-18 run hit exactly this: workspace `Cline+DS4.1F`, repo
  root `E:\Source\Solar-System-Explorer`). **Fix:** `cd (git rev-parse
  --show-toplevel)` first; `investigate.ps1` prints the toplevel and warns when
  the cwd has a prefix. A toplevel abort leaves no `.git-rewrite` tempdir
  behind — just re-run from the right directory.
- **Each OpenCode shell call starts fresh in the session directory** — a `cd`
  does not carry over to the next command. Put the `cd` in the same command as
  the rewrite, or pass the toplevel as the shell tool's `workdir`.
- **PowerShell strips inner double quotes** from arguments passed to git, which
  routes filter commands through `sh`. So `--msg-filter 'sed "s|a|b|g"'` arrives
  as `sed s|a|b|g` — `sh` reads the pipes as **pipes** and fails with
  `g: command not found`. **Fix:** comma delimiters, no quotes — `sed s,a,b,g`.
  Commas are inert in both PowerShell and sh.
- **Spaces in OLD/NEW word-split in sh.** `sed s,a b,c d,g` becomes `sed s,a`
  plus stray arguments — the substitution silently matches nothing. **Fix:**
  backslash-escape every space (`sed s,a\ b,c\ d,g`); the backslashes survive
  PowerShell → git → sh and sh un-escapes them inside the sed script. Verified
  in the 2026-11-18 rewrite (first one with multi-word text).
- **BRE regex escaping in the sed pattern:** escape `.` as `\.` (unescaped it
  matches any character), but do NOT escape `+` — in POSIX BRE `+` is literal
  while `\+` is a GNU quantifier ("one or more of the previous atom") and
  corrupts the match. So `DS4\.1F` is right; `DS4\.1F\ on\ OpenCode` keeps `+`
  bare.
- **`--root` is NOT a filter-branch option.** It exists only as a *rev-list*
  option (filter-branch forwards everything after `--` to `git rev-list`), and
  the script's own option parser rejects a bare `--root` with a usage error.
  The correct way to rewrite from the very first commit is to omit the range
  and pass the branch name alone — a range is what *excludes* the root.
- **`<root>~1` is a fatal revision error** (`unknown revision or path not in the
  working tree`, exit 128) — there is no commit below the root. Any tooling that
  unconditionally computes `<earliest>~1` breaks when the earliest affected
  commit is the root itself.
- **filter-branch always strips `gpgsig`** from every commit inside the rewrite
  range. There is no way around it with filter-branch; the skill's job is to
  inventory the loss *before* it happens.
- **`%G?` is not ground truth** for signature checks — it can report `N` for
  genuinely signed commits when the keyring is unavailable. The scripts read raw
  commit objects (`git cat-file commit`) and match `^gpgsig ` instead.
- **`~N` walks first parents only.** Total commit count (which includes
  side-branch commits from merges) is not a valid `~N` depth.
- **Unchanged-hash counts can exceed the below-anchor count** — commits inside
  the range whose message *and* parent-mapping are unchanged keep their hashes.
- **`refs/original/refs/heads/<branch>`** is filter-branch's frozen one-shot
  backup: written once at rewrite time, never auto-updated by push/fetch, blocks
  the next filter-branch run until deleted, and pins old objects from GC.
- **A rebase alternative exists but is inferior for pure message rewrites:**
  `rebase -i --rebase-merges` (with scripted `GIT_SEQUENCE_EDITOR`/`GIT_EDITOR`)
  cannot preserve committer identity — GitHub web-flow merges
  (`noreply@github.com`) become the local user — and `merge -c` adds a trailing
  blank line to merge messages.

## Changes from the Copilot original

| Copilot | OpenCode V2 |
|---|---|
| `~/copilot/skills/…` or `.github/skills/…` | `~/.config/opencode/skills/…` or `.opencode/skills/…` |
| `frontmatter: argument-hint` | Removed — OpenCode skills take no arguments; the companion `commands/git-message-rewrite.md` supplies `$1`–`$4` |
| `frontmatter: user-invocable` | Removed — every permitted skill with a `description` is available to both the model and the user (`@git-message-rewrite`) |
| `frontmatter: disable-model-invocation: false` | Dropped as redundant; the V2 spellings are `disable-model-invocation: true` or `metadata.opencode/autoinvoke: false` |
| `/git-message-rewrite BRANCH OLD NEW [ANCHOR]` | Same slash form via the command file, plus `@git-message-rewrite` mention and automatic selection |
| `<skill-dir>` placeholder | The skill base directory OpenCode reports on load; scripts stay unmounted until executed |

## Validation

Both scripts were validated against the 2026-11-16 rewrite ground truth:

- `investigate.ps1` against the pre-rewrite branch reproduced the manual
  findings exactly: 26 affected commits (all merges), anchor `891e796`, range of
  126 commits, 4 signatures at risk, 9 preserved.
- `verify.ps1` against the rewritten branch reported **ALL CHECKS PASSED**:
  0 old-text occurrences, 158/158 commits, 39/39 merges, empty tree diff,
  13 → 9 signatures, bottom-of-history byte-identical.

Re-validated against the 2026-11-18 rewrite (first run with multi-word text and
a nested-workspace cwd):

- `investigate.ps1` reported 4 affected commits (2 merges), anchor `9fed2b7~1`
  = `4842848`, 2 signatures at risk, 11 preserved — and prints the repo
  toplevel with a subdirectory warning.
- The toplevel trap was hit live: filter-branch from the workspace subdirectory
  aborted with `could not open 'Cline+DS4.1F/nul'`; re-running from the repo
  root succeeded on the first try.
- `verify.ps1` reported **ALL CHECKS PASSED**: 0 old-text occurrences, 168/168
  commits, 43/43 merges, empty tree diff, 13 → 11 signatures, 164 unchanged
  hashes, bottom-of-history identical.

The root-commit edge case was validated empirically in scratch repositories:

- `investigate.ps1` correctly detects "earliest affected commit IS the root"
  (via `git rev-list --max-parents=0`) and emits the no-range rewrite command.
- A whole-history rewrite (`git filter-branch --msg-filter '...' <branch>`)
  rewrote the root inclusively, left sibling branches untouched, and produced
  the expected `refs/original` backup.
- `verify.ps1 -Anchor NONE` reported **ALL CHECKS PASSED**, correctly treating
  "no merge-base" and "0 unchanged hashes" as expected outcomes rather than
  failures; the normal anchor path was regression-tested in the same session.

The port itself was verified in OpenCode V2: the skill is advertised and loads
under the ID `git-message-rewrite` (base directory and all three supporting
files reported), and `scripts/investigate.ps1` runs unchanged from the installed
path against a real repository (read-only, 0-affected-commit path).

## Requirements

- Windows with Git for Windows (filter-branch + `sh`-routed filters)
- PowerShell 5.1 or later, or PowerShell 7+ (`pwsh`) on any platform — the
  scripts use no external modules
- A clean work tree (untracked files are fine; tracked modifications are not)
- Shell-tool permission for `powershell`/`git` in the agent that runs the phases

## Rollback

Every phase leaves an escape hatch:

```powershell
# restore the branch tip to its pre-rewrite state
git update-ref refs/heads/<branch> <backup-sha>

# or, after checking the branch out
git reset --hard <branch>_before_<fixname>
```

`refs/original/refs/heads/<branch>` (filter-branch's own backup) points at the
same pre-rewrite tip until deleted. Delete it once the rewrite is reviewed and
pushed — until then it blocks any future filter-branch run:

```powershell
git update-ref -d refs/original/refs/heads/<branch>
```
