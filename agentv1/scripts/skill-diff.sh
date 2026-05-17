#!/bin/bash
# =============================================================================
# skill-diff.sh — Show recent changes to SKILL.md files
# Version: 1.0.0 | Scrutexity Agent Governance Layer
# Usage: ./skill-diff.sh [--last N | --since DATE | --full]
# =============================================================================
set -euo pipefail

SKILLS_DIR="${HERMES_SKILLS_DIR:-$HOME/.hermes/skills}"
LAST_N="${LAST_N:-5}"

cd "$SKILLS_DIR" 2>/dev/null || { echo "❌ Skills directory not found: $SKILLS_DIR"; exit 1; }

show_help() {
    cat <<'HELP'
Usage: ./skill-diff.sh [OPTION]

Show recent changes to SKILL.md files using git history.

Options:
  --last N      Show last N commits (default: 5)
  --since DATE  Show changes since date (YYYY-MM-DD)
  --full        Show full diff for each changed file
  --help        Show this help message

Examples:
  ./skill-diff.sh              # Last 5 commits
  ./skill-diff.sh --last 10    # Last 10 commits
  ./skill-diff.sh --since 2026-05-01  # Changes since May 1
HELP
}

# Parse arguments
MODE="last"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --last)
            MODE="last"
            LAST_N="${2:-5}"
            shift 2 || shift
            ;;
        --since)
            MODE="since"
            SINCE_DATE="$2"
            shift 2
            ;;
        --full)    MODE="full" ;;
        --help)    show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
    shift
done

echo "=== Scrutexity Agent Skill Diff ==="
echo "Skills directory: $SKILLS_DIR"
echo "Mode: $MODE"
echo ""

# Check if git repo
if [ ! -d .git ]; then
    echo "⚠️  Skills directory is not a git repo. Initializing..."
    git init
    git add -A
    git commit -m "Baseline skill set" 2>/dev/null || true
fi

case "$MODE" in
    last)
        echo "Recent commits:"
        git log --oneline -n "$LAST_N"
        echo ""
        echo "Files changed in last $LAST_N commits:"
        git diff --name-only HEAD~$LAST_N..HEAD 2>/dev/null || git diff --name-only $(git rev-list --max-parents=0 HEAD)..HEAD
        echo ""
        echo "Skill version tracking:"
        for f in *.md; do
            [ -f "$f" ] || continue
            VERSION=$(grep -m1 "^version:" "$f" | sed 's/version: *//')
            LAST_MOD=$(git log -1 --format="%cd" --date=short -- "$f" 2>/dev/null || echo "N/A")
            COMMITS=$(git log --oneline -- "$f" 2>/dev/null | wc -l)
            printf "  %-30s | v%-8s | %s | %d commits\n" "$f" "$VERSION" "$LAST_MOD" "$COMMITS"
        done
        ;;

    since)
        echo "Changes since $SINCE_DATE:"
        git log --oneline --since="$SINCE_DATE"
        echo ""
        echo "Files changed:"
        git diff --name-only $(git rev-list -n 1 --before="$SINCE_DATE" HEAD)..HEAD 2>/dev/null || echo "  (no changes or date too old)"
        ;;

    full)
        echo "Full diff of last commit:"
        git diff HEAD~1 -- '*.md' || echo "  (only one commit in history)"
        ;;
esac

echo ""
echo "=== Skill Version Consistency Check ==="
INCONSISTENT=0
for f in *.md; do
    [ -f "$f" ] || continue
    FILE_VER=$(grep -m1 "^version:" "$f" | sed 's/version: *//')
    GIT_TAG=$(git tag -l "$(basename $f .md)-*" | tail -1 | sed 's/.*-//')
    if [ -n "$GIT_TAG" ] && [ "$FILE_VER" != "$GIT_TAG" ]; then
        echo "  ⚠️  $f: file version $FILE_VER != git tag $GIT_TAG"
        INCONSISTENT=$((INCONSISTENT + 1))
    fi
done

if [ "$INCONSISTENT" -eq 0 ]; then
    echo "  ✅ All skill versions consistent with git history"
else
    echo "  ❌ $INCONSISTENT skill version inconsistencies found"
fi

echo ""
echo "=== End Skill Diff ==="
