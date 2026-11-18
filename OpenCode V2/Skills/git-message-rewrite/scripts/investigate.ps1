# Read-only investigation for a git message rewrite. Reports affected commits,
# anchor, blast radius, signature exposure, and blockers. Changes nothing.
param(
    [Parameter(Mandatory = $true)][string]$Branch,
    [Parameter(Mandatory = $true)][string]$OldText
)
$ErrorActionPreference = 'Stop'

function Assert-Repo { git rev-parse --is-inside-work-tree *> $null; if ($LASTEXITCODE -ne 0) { throw 'not a git repository' } }
Assert-Repo

git rev-parse --verify --quiet "refs/heads/$Branch" *> $null
if ($LASTEXITCODE -ne 0) { throw "branch '$Branch' not found" }

$dirty = git status --porcelain
$branchTip = git rev-parse --short $Branch
$current = git branch --show-current

Write-Output "=== Investigation: rewrite '$OldText' on '$Branch' (tip $branchTip) ==="
Write-Output "checked-out branch : $current (target does NOT need checkout; work tree must be clean)"
Write-Output "work tree          : $(if ($dirty) { "DIRTY: $($dirty -join '; ')" } else { 'clean' })"

# --- toplevel: the Phase 3 filter-branch MUST run from there ---
$toplevel = git rev-parse --show-toplevel
$prefix = git rev-parse --show-prefix
Write-Output "repo toplevel      : $toplevel"
if ($prefix) {
    Write-Output "  cwd is a SUBDIRECTORY of the repo (prefix '$prefix'). Phase 3 filter-branch"
    Write-Output "  MUST run from the toplevel (cd '$toplevel') or it aborts with:"
    Write-Output "    fatal: could not open '<prefix>nul' for reading ... run from the toplevel"
}

# --- affected commits ---
$affected = @(git rev-list "$Branch" | Where-Object { (git log -1 --format=%B $_) -match [regex]::Escape($OldText) })
Write-Output "`n=== Affected commits: $($affected.Count) ==="
foreach ($c in $affected) {
    $parents = (git log -1 --format=%P $c) -split '\s+'
    $kind = if ($parents.Count -ge 2) { 'MERGE' } else { 'plain' }
    Write-Output ("  {0} [{1}] {2}" -f ($c.Substring(0, 7)), $kind, (git log -1 --format=%s $c))
}
if ($affected.Count -eq 0) { Write-Output 'nothing to do - old text not found'; return }

# --- anchor: earliest affected commit ---
$earliest = $affected | ForEach-Object { [pscustomobject]@{ Sha = $_; Date = [long](git log -1 --format=%ct $_) } } |
    Sort-Object Date | Select-Object -First 1
$rootCommits = @(git rev-list --max-parents=0 $Branch)
$isRoot = $rootCommits -contains $earliest.Sha
Write-Output "`n=== Anchor (earliest affected commit's parent) ==="
Write-Output "  earliest affected : $($earliest.Sha.Substring(0,7)) $(git log -1 --format=%s $earliest.Sha)"
if ($isRoot) {
    Write-Output "  ROOT CASE         : earliest affected commit IS the root commit (no parent exists)"
    Write-Output "  rewrite command   : git filter-branch --msg-filter '...' $Branch   (NO range, NO '~1')"
    Write-Output "                      '<root>~1' would be a fatal revision error; omitting the range"
    Write-Output "                      rewrites from the root inclusively, still touching only '$Branch'"
    $rangeCommits = @(git rev-list $Branch)
    Write-Output "  rewrite scope     : ENTIRE history of '$Branch' = $($rangeCommits.Count) commits (0 hashes preserved)"
}
else {
    $anchor = "$($earliest.Sha)~1"
    Write-Output "  anchor            : $anchor = $(git rev-parse --short $anchor) $(git log -1 --format=%s $anchor)"
    $range = "$anchor..$Branch"
    $rangeCommits = @(git rev-list $range)
    Write-Output "  rewrite range     : $range = $($rangeCommits.Count) commits"
}

# --- signature exposure ---
$inRangeSigned = @($rangeCommits | Where-Object { (git cat-file commit $_) -match '^gpgsig ' })
$totalSigned = @(git rev-list $Branch | Where-Object { (git cat-file commit $_) -match '^gpgsig ' })
Write-Output "`n=== GPG signature exposure ==="
Write-Output "  signed commits in range (WILL LOSE signature): $($inRangeSigned.Count)"
foreach ($c in $inRangeSigned) { Write-Output ("    {0} {1}" -f ($c.Substring(0, 7)), (git log -1 --format=%s $c)) }
Write-Output "  signed commits below anchor (preserved)      : $($totalSigned.Count - $inRangeSigned.Count) (of $($totalSigned.Count) total)"

# --- blockers ---
$stale = git for-each-ref refs/original/ --format='%(refname)'
Write-Output "`n=== Blockers / state ==="
Write-Output "  refs/original: $(if ($stale) { $stale -join '; ' } else { 'empty (ok)' })"
Write-Output "`nNOTE: present findings to the user and get approval before rewriting."
