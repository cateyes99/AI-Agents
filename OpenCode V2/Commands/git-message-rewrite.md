---
description: Rewrite commit messages on a branch (typos, branch names in merge messages) without checkout
---

Load the `git-message-rewrite` skill and follow its five phases.

Inputs — branch: `$1` · old text: `$2` · new text: `$3` · optional anchor commit: `$4`

If `$1`, `$2`, or `$3` is empty, ask for the missing value instead of guessing. Then run Phase 1 (read-only investigation), present the findings — especially which GPG-signed commits will lose their signatures — and stop for approval before rewriting. Never push.
