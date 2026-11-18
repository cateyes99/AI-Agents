# Code reviewer agents (OpenCode V2)

Port of the GitHub Copilot custom agents in
`E:\Source\AI-Agents\GitHub Copilot\Agents\Code Reviewers`.

Seven read-only agents: six specialists plus a coordinator that dispatches them
in parallel and merges their findings.

| Source file | Agent ID | Mode |
|---|---|---|
| `general-code-reviewer.agent.md` | `general-code-reviewer` | `all` |
| `general-security-reviewer.agent.md` | `general-security-reviewer` | `all` |
| `general-test-quality-reviewer.agent.md` | `general-test-quality-reviewer` | `all` |
| `general-performance-reviewer.agent.md` | `general-performance-reviewer` | `all` |
| `general-architecture-reviewer.agent.md` | `general-architecture-reviewer` | `all` |
| `general-accessibility-reviewer.agent.md` | `general-accessibility-reviewer` | `all` |
| `general-review-board.agent.md` | `general-review-board` | `all` |

Agent files live in `~/.config/opencode/agents/<id>.md`, and the Markdown body of
each file is the agent's system prompt. `mode: all` keeps each one usable both as
a primary agent (select it in the TUI agent picker) and as a subagent (another
agent dispatches it), which matches how the Copilot agents could be selected in
chat *and* delegated to.

This file is documentation only. It deliberately lives in `docs/` rather than
`agents/`, because every Markdown file in `agents/` is registered as an agent.

## Changes from the Copilot originals

| Copilot | OpenCode V2 |
|---|---|
| `tools: [read, search, execute, todo]` | Removed — V1 `tools` is deprecated. Capability is expressed with `permissions` instead: read/search stay available by default, `edit` is denied, `shell` is allowed with mutating commands denied |
| `tools: [read, search, execute, web, todo]` (security) | Same; web tools (`webfetch`, `websearch`) are available by default, no extra rule needed |
| `tools: [..., open_browser_page, navigate_page, ...]` (accessibility) | Removed — V2 ships no browser tools. They exist only when an MCP server or plugin provides them, so the prompt now conditions live verification on such tooling being available |
| `agents: [<six display names>]` (board) | `permissions` on the `subagent` action: deny `*`, then allow each of the six agent IDs. The board can launch exactly its panel and nothing else |
| `argument-hint` | Dropped — no V2 equivalent. Scope is stated in the prompt, and each specialist already has a documented default scope |
| "switch to a coding agent" | "switch to the `build` agent" |
| "When Invoked by Another Agent" | "When Invoked as a Subagent", noting the child session and that only the final report reaches the parent |

## Read-only enforcement

The originals state their read-only contract in prose only. Here it is also
enforced by configuration. The six specialists share this block:

```yaml
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: shell
    resource: "*"
    effect: allow
  - action: shell
    resource: "*git commit*"
    effect: deny
  - action: shell
    resource: "*git push*"
    effect: deny
  - action: shell
    resource: "*git checkout*"
    effect: deny
  - action: shell
    resource: "*git reset*"
    effect: deny
  - action: shell
    resource: "*git stash*"
    effect: deny
  - action: shell
    resource: "*git rebase*"
    effect: deny
  - action: shell
    resource: "*install*"
    effect: deny
  - action: shell
    resource: "*--fix*"
    effect: deny
  - action: shell
    resource: "*--write*"
    effect: deny
  - action: shell
    resource: "*--update-snapshots*"
    effect: deny
```

Rules run in order and the last match wins, so the broad `shell` allow comes
first and the denials refine it. The specialists additionally deny the
`subagent` action, so a reviewer cannot recurse into more reviewers. The review
board reuses the same shell rules and `edit` denial, drops the write-back flag
denials it has no use for, and replaces the `subagent` denial with an allow list
naming its six specialists.

`edit: deny` covers the edit, write, and patch tools, so a reviewer cannot modify
files even if it decides to. The shell denials block the mutating commands the
prompts forbid — commit, push, checkout, reset, stash, rebase, package installs,
and write-back flags — and are substring matches, so they also catch commands
prefixed with `cd` or chained after `&&`.

They do not make a reviewer bulletproof: `git restore`, `dotnet format`, and
`prettier --write` reach the same effect through commands not listed here, and
the prompt remains the first line of defense. Extend the denial list if you want
tighter enforcement.

## Using them

- **Directly:** open the agent picker in the TUI and select one, then say what to
  review. Or name it in a prompt — "have `general-security-reviewer` review the
  auth flow".
- **As a subagent:** from any session, ask the main agent to use one, for example
  "use the general-test-quality-reviewer subagent on `src/payments`". The parent
  session is controlled by its own `subagent` permissions, so a project that
  wants to keep this tight can deny these IDs there.
- **Full board:** select `general-review-board`, or ask for it by name. It picks
  a panel, briefs each specialist with the same fixed scope, launches them
  concurrently, then merges. It is the expensive option by design; the prompt
  says so in its closing note.

Each specialist defaults to a sensible scope when the request is vague —
uncommitted changes, then the branch against its base — and states the scope it
settled on rather than asking.

## Accessibility and browser tooling

The accessibility reviewer is static-only unless browser tools exist. To enable
live verification, connect an MCP server that exposes browser automation (for
example a Playwright MCP server) and make sure the agent's permissions allow the
tools it provides. No rule is pre-written for them here, because the tool names
come from whichever server you configure.

## Verification

- All seven files parse with only V2-documented frontmatter fields
  (`description`, `mode`, `permissions`), checked with a YAML parser rather than
  by eye.
- Live smoke test: `general-code-reviewer` was dispatched as a subagent with a
  fixed single-file scope and an output cap. It resolved by ID, read the file
  plus its collaborator for contract context, and returned the report in the
  specified format with no closing offer — so discovery, system prompt, and
  read permissions all work.
- `general-review-board` is limited to its six specialist IDs by the `subagent`
  allow list, so a typo in a panel name fails the dispatch instead of silently
  starting an unrelated agent.
- Not yet exercised: the board's parallel panel run (expensive by design), and
  the negative case where a reviewer attempts an edit or a `git commit` and is
  refused by permissions.
