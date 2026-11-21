param([string]$Message = "Update docs")

$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$buildDir    = Join-Path $projectRoot "_build\html"   # change to "docs\_build\html" if your layout differs
$repoDir     = "D:\Revs\Professional\GitHubProjects\revs-tech-handbook"
$branch      = "main"

# 1. Build
Push-Location $projectRoot
cmd /c make.bat html
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Sphinx build failed" }
Pop-Location

# 2. Mirror the build output into the repo
#    /MIR removes files in the repo that no longer exist in the build,
#    /XD .git and /XF protect git data and files you maintain by hand
robocopy $buildDir $repoDir /MIR /XD ".git" /XF "CNAME" ".nojekyll" "README.md" /NFL /NDL /NJH /NJS
if ($LASTEXITCODE -ge 8) { throw "Copy failed (robocopy exit code $LASTEXITCODE)" }

# 3. Make sure GitHub Pages doesn't run Jekyll (see note below)
$nojekyll = Join-Path $repoDir ".nojekyll"
if (-not (Test-Path $nojekyll)) { New-Item $nojekyll -ItemType File | Out-Null }

# 4. Commit and push only if something changed
Push-Location $repoDir
git add -A
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "No changes to publish."
} else {
    git commit -m "$Message ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
    git push origin $branch
    Write-Host "Published. GitHub Pages deployment will start shortly."
}
Pop-Location