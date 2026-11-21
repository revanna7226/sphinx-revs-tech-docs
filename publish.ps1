param(
    [string]$Message = "Update docs",
    [string]$skipSphinxCommit = "false"   # pass "true" to skip pushing the Sphinx source
)

$ErrorActionPreference = "Stop"

# ---- Configuration ----
$projectRoot = $PSScriptRoot
$buildDir    = Join-Path $projectRoot "_build\html"   # use "docs\_build\html" if your layout differs
$pagesRepo   = "D:\Revs\Professional\GitHubProjects\revs-tech-handbook"
$pagesBranch = "main"
# -----------------------

# Accepts: true / True / 1 / yes / $true
$skipSource = $skipSphinxCommit -in @("true", "1", "yes", "skip")

function Commit-AndPush {
    param([string]$RepoPath, [string]$CommitMessage, [string]$Branch)

    Push-Location $RepoPath
    try {
        git rev-parse --is-inside-work-tree 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "'$RepoPath' is not a git repository." }

        if (-not $Branch) { $Branch = (git rev-parse --abbrev-ref HEAD).Trim() }

        git add -A
        git diff --cached --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[$RepoPath] No changes to commit."
        } else {
            git commit -m "$CommitMessage ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
            if ($LASTEXITCODE -ne 0) { throw "git commit failed in '$RepoPath'." }
        }

        git push origin $Branch
        if ($LASTEXITCODE -ne 0) { throw "git push failed in '$RepoPath'." }
        Write-Host "[$RepoPath] Pushed to origin/$Branch."
    }
    finally {
        Pop-Location
    }
}

# ---- 1. Build ----
Write-Host "==> Building Sphinx docs..." -ForegroundColor Cyan
Push-Location $projectRoot
try {
    cmd /c make.bat html
    if ($LASTEXITCODE -ne 0) { throw "Sphinx build failed." }
}
finally {
    Pop-Location
}

# ---- 2. Copy HTML to the Pages repo ----
Write-Host "==> Copying HTML to Pages repo..." -ForegroundColor Cyan
robocopy $buildDir $pagesRepo /MIR /XD ".git" /XF "CNAME" ".nojekyll" "README.md" /NFL /NDL /NJH /NJS
if ($LASTEXITCODE -ge 8) { throw "Copy failed (robocopy exit code $LASTEXITCODE)." }

$nojekyll = Join-Path $pagesRepo ".nojekyll"
if (-not (Test-Path $nojekyll)) { New-Item $nojekyll -ItemType File | Out-Null }

# ---- 3. Publish the site ----
Write-Host "==> Publishing site..." -ForegroundColor Cyan
Commit-AndPush -RepoPath $pagesRepo -CommitMessage $Message -Branch $pagesBranch

# ---- 4. Push Sphinx source (unless skipped) ----
if ($skipSource) {
    Write-Host "==> Skipping Sphinx source commit." -ForegroundColor Yellow
} else {
    Write-Host "==> Pushing Sphinx source..." -ForegroundColor Cyan
    Commit-AndPush -RepoPath $projectRoot -CommitMessage $Message
}

Write-Host "Done." -ForegroundColor Green