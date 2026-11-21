#!/usr/bin/env bash
set -euo pipefail

# ---- Configuration ----
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_ROOT/_build/html"            # use "docs/_build/html" if your layout differs
PAGES_REPO="$HOME/Revs/Professional/GitHubProjects/revs-tech-handbook"   # adjust to your clone location
PAGES_BRANCH="main"
# -----------------------

MESSAGE="Update docs"
SKIP_SPHINX_COMMIT="false"

# Parse arguments: --message "text" --skipSphinxCommit true
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message)            MESSAGE="${2:?Missing value for $1}"; shift 2 ;;
    -s|--skipSphinxCommit)   SKIP_SPHINX_COMMIT="${2:?Missing value for $1}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--message \"text\"] [--skipSphinxCommit true|false]"
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Accepts: true / True / 1 / yes
case "$(echo "$SKIP_SPHINX_COMMIT" | tr '[:upper:]' '[:lower:]')" in
  true|1|yes) SKIP_SOURCE=true ;;
  *)          SKIP_SOURCE=false ;;
esac

commit_and_push() {
  local repo_path="$1" commit_message="$2" branch="${3:-}"

  git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "'$repo_path' is not a git repository." >&2; exit 1; }

  [[ -z "$branch" ]] && branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD)"

  git -C "$repo_path" add -A
  if git -C "$repo_path" diff --cached --quiet; then
    echo "[$repo_path] No changes to commit."
  else
    git -C "$repo_path" commit -m "$commit_message ($(date '+%Y-%m-%d %H:%M'))"
  fi

  # Push even if nothing new was committed, in case earlier commits are unpushed
  git -C "$repo_path" push origin "$branch"
  echo "[$repo_path] Pushed to origin/$branch."
}

# ---- 1. Build ----
echo "==> Building Sphinx docs..."
( cd "$PROJECT_ROOT" && make html )

# ---- 2. Copy HTML to the Pages repo ----
echo "==> Copying HTML to Pages repo..."
# --delete mirrors the build (removes stale files); excludes protect git data and hand-maintained files
rsync -a --delete \
  --exclude ".git" \
  --exclude "CNAME" \
  --exclude ".nojekyll" \
  --exclude "README.md" \
  "$BUILD_DIR"/ "$PAGES_REPO"/

# Stop GitHub Pages from running Jekyll (it would ignore _static, _sources, etc.)
touch "$PAGES_REPO/.nojekyll"

# ---- 3. Publish the site ----
echo "==> Publishing site..."
commit_and_push "$PAGES_REPO" "$MESSAGE" "$PAGES_BRANCH"

# ---- 4. Push Sphinx source (unless skipped) ----
if [[ "$SKIP_SOURCE" == "true" ]]; then
  echo "==> Skipping Sphinx source commit."
else
  echo "==> Pushing Sphinx source..."
  commit_and_push "$PROJECT_ROOT" "$MESSAGE"
fi

echo "Done."