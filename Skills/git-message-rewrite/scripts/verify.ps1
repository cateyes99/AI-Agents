# Post-rewrite verification battery. Read-only. Run after filter-branch.
param(
    [Parameter(Mandatory = $true)][string]$Branch,
    [Parameter(Mandatory = $true)][string]$BackupBranch,
    [Parameter(Mandatory = $true)][string]$OldText,
    [Parameter(Mandatory = $true)][string]$NewText,
    [Parameter(Mandatory = $true)][string]$Anchor   # e.g. 'f166049~1'; use 'NONE' for root-case (whole-history) rewrites
)
$ErrorActionPreference = 'Stop'
git rev-parse --verify --quiet "refs/heads/$Branch" *> $null
if ($LASTEXITCODE -ne 0) { throw "branch '$Branch' not found" }
git rev-parse --verify --quiet "refs/heads/$BackupBranch" *> $null
if ($LASTEXITCODE -ne 0) { throw "backup branch '$BackupBranch' not found" }

$fail = 0
function Check($name, $ok, $detail) {
    $script:fail += $(if (-not $ok) { 1 } else { 0 })
    Write-Output ("  [{0}] {1}{2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $(if ($detail) { " - $detail" } else { '' }))
}

Write-Output "=== Verification: $Branch (rewritten) vs $BackupBranch (pre-rewrite) ==="

$oldLeft = @(git log --grep=$OldText -F --format='%H' $Branch).Count
Check "old text eliminated" ($oldLeft -eq 0) "$oldLeft occurrences remain"
$newFound = @(git log --grep=$NewText -F --format='%H' $Branch).Count
Write-Output "  new text present in $newFound commits (informational)"

$cNew = git rev-list --count $Branch
$cOld = git rev-list --count $BackupBranch
Check "commit count preserved" ($cNew -eq $cOld) "$cOld -> $cNew"
$mNew = git rev-list --count --merges $Branch
$mOld = git rev-list --count --merges $BackupBranch
Check "merge count preserved" ($mNew -eq $mOld) "$mOld -> $mNew"

$treeDiff = git diff $BackupBranch $Branch --stat
Check "tree identical (code untouched)" (-not $treeDiff)

if ($Anchor -eq 'NONE') {
    Write-Output "  ROOT CASE (whole-history rewrite): merge-base and unchanged-hash checks skipped"
    $mb = git merge-base $BackupBranch $Branch 2>$null
    if ($LASTEXITCODE -eq 0) {
        Check "no common ancestor expected (full rewrite)" $false "unexpected merge-base $($mb.Substring(0,7)) - rewrite was NOT full-history?"
    } else {
        Write-Output "  merge-base old<->new : none (exit 1) - expected for a full-history rewrite"
    }
    $shared = @(Compare-Object (git rev-list $BackupBranch) (git rev-list $Branch) -IncludeEqual -ExcludeDifferent).Count
    Write-Output "  unchanged hashes     : $shared (0 is EXPECTED here - every commit was rewritten)"
}
else {
    $mb = git merge-base $BackupBranch $Branch
    Write-Output "  merge-base old<->new : $($mb.Substring(0,7)) $(git log -1 --format=%s $mb)"
    $shared = @(Compare-Object (git rev-list $BackupBranch) (git rev-list $Branch) -IncludeEqual -ExcludeDifferent).Count
    Write-Output "  unchanged hashes     : $shared (>= commits below anchor; may be higher if in-range ancestry unchanged)"
}

$sigNew = @(git rev-list $Branch | Where-Object { (git cat-file commit $_) -match '^gpgsig ' }).Count
$sigOld = @(git rev-list $BackupBranch | Where-Object { (git cat-file commit $_) -match '^gpgsig ' }).Count
Write-Output "  GPG-signed commits   : $sigOld -> $sigNew (loss = signatures stripped inside range)"

$bottomOld = git rev-list --reverse $BackupBranch | Select-Object -First 4
$bottomNew = git rev-list --reverse $Branch | Select-Object -First 4
if ($Anchor -eq 'NONE') {
    Write-Output "  bottom of history    : rewritten by design in a root case (old: $(($bottomOld | ForEach-Object { $_.Substring(0, 7) }) -join ' '))"
    Write-Output "                         (new: $(($bottomNew | ForEach-Object { $_.Substring(0, 7) }) -join ' '))"
}
else {
    Check "bottom of history identical" ((Compare-Object $bottomOld $bottomNew).Count -eq 0) (($bottomNew | ForEach-Object { $_.Substring(0, 7) }) -join ' ')
}

if ($Anchor -ne 'NONE') {
    git merge-base --is-ancestor $Anchor $Branch
    Check "anchor is ancestor of rewritten branch" ($LASTEXITCODE -eq 0)
}

$others = git for-each-ref refs/heads --format='%(refname:short)' | Where-Object { $_ -ne $Branch -and $_ -ne $BackupBranch }
$moved = @($others | Where-Object { $before = Get-Content ".git\refs\heads\$_" -ErrorAction SilentlyContinue; $false })
Write-Output "  other local branches : $($others -join ', ')"
Write-Output "  (verify manually they still point at expected tips: git for-each-ref refs/heads)"

Write-Output "`n=== Result: $(if ($fail -eq 0) { 'ALL CHECKS PASSED' } else { "$fail CHECK(S) FAILED - investigate before pushing" }) ==="
Write-Output "Rollback: git update-ref refs/heads/$Branch $(git rev-parse $BackupBranch)"
Write-Output "Publish (USER runs): git push --force-with-lease origin $Branch"
Write-Output "After review+push, delete filter-branch's frozen backup (it blocks future filter-branch runs):"
Write-Output "  git update-ref -d refs/original/refs/heads/$Branch"
