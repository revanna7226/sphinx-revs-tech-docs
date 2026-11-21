param([string]$Message = "Update docs source")

$ErrorActionPreference = "Stop"

Push-Location $PSScriptRoot
try {
    # Confirm this folder is a git repo with a remote
    git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "This folder is not a git repository. Run 'git init' and add a remote first." }

    $branch = git rev-parse --abbrev-ref HEAD

    # Stage everything (respects .gitignore, so _build is skipped)
    git add -A

    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host "No source changes to commit."
    } else {
        git commit -m "$Message ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
    }

    # Push even if nothing new was committed, in case earlier commits are unpushed
    git push origin $branch
    Write-Host "Source pushed to origin/$branch."
}
finally {
    Pop-Location
}