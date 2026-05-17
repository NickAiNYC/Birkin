---
name: code-governance
description: |
  Use when the user asks to review code changes, check governance on a git push, validate
  Directora patterns in a PR, or run code review. Triggers: "code review", "governance check",
  "PR summary", "git push check", "test weaker", "contract version", "snapshot regeneration",
  "dependency lock", "governance script executable", "Birkin repo check".
version: 1.0.0
created_date: 2026-05-17
platforms: [linux]
metadata:
  hermes:
    tags: [code-review, governance, git, directora, testing, ci-cd]
    category: devops
    requires_toolsets: [terminal, file, web_research]
    fallback_for_toolsets: []
    config:
      - key: governance.repos
        description: "Comma-separated list of Birkin repo paths"
        default: "~/Directora,~/LabBrief"
        prompt: "Enter paths to Birkin repos to monitor"
---

# Code Review & Governance Watch Skill

## When to Use
- Triggered on every git push to main on any Birkin repo (via webhook or cron poll)
- User asks: "review this PR", "check governance", "did tests get weaker", "contract version bump"
- Any request about code quality, governance compliance, or repo health in Birkin projects

## Checks to Perform

### 1. Test Weakening Detection
```bash
cd REPO && git diff HEAD~1 --stat | grep -E "test.*\.(py|ts|js)" > /tmp/test_changes.txt
```
- If any test file was DELETED or significantly shrunk (>30% lines removed), flag as WEAKENED
- If new tests were added, flag as STRENGTHENED
- Check test count: `pytest --collect-only 2>/dev/null | grep "test session"` or `npm test --listTests 2>/dev/null | wc -l`

### 2. Contract Version Bump + Snapshot Regeneration
```bash
cd REPO && git diff HEAD~1 --name-only | grep -E "contract|snapshot|schema"
```
- If contract/schema file changed but no snapshot regeneration commit exists, flag MISSING_SNAPSHOT
- Look for files matching `*snapshot*`, `*generated*`, `*contract*.json` in diff

### 3. Dependency Lock File Updates
```bash
cd REPO && git diff HEAD~1 --name-only | grep -E "package-lock|yarn.lock|poetry.lock|Cargo.lock|requirements.*\.txt"
```
- If `package.json`, `Cargo.toml`, `pyproject.toml`, etc. changed but lock file did NOT, flag MISSING_LOCK_UPDATE
- If lock file changed without manifest change, flag SUSPICIOUS (possible supply chain)

### 4. Governance Script Executable
```bash
cd REPO && test -x scripts/governance-check.sh && echo "OK" || echo "FAIL: not executable"
```
- If `scripts/governance-check.sh` exists but is not executable, flag GOVERNANCE_SCRIPT_BROKEN
- If script does not exist, flag MISSING_GOVERNANCE_SCRIPT

### 5. PHI Guard Whitelist Integrity
```bash
cd REPO && grep -r "PHI_GUARD" . --include="*.py" --include="*.ts" | head -5
```
- If PHI guard references exist but whitelist file is missing or empty, flag PHI_GUARD_BROKEN

### 6. CI/CD Pipeline Status
- Use web_search or curl to check GitHub Actions / CI status for latest commit
- If CI failed, flag CI_FAILURE and extract failure reason

## Output Format
```markdown
# Code Governance Report — REPO_NAME @ COMMIT_SHORT

## Summary
- Commit: `abc1234` by Author — "feat: add ledger batching"
- Overall: ✅ CLEAN / ⚠️ ISSUES_FOUND / ❌ GOVERNANCE_BREACH

## Findings
| Check | Status | Detail |
|-------|--------|--------|
| Tests | ⚠️ WEAKENED | 3 tests removed from `test_ledger.py` (no replacement) |
| Contract Snapshots | ✅ OK | Version bumped + snapshot regenerated |
| Lock Files | ✅ OK | `poetry.lock` updated with `pyproject.toml` |
| Gov Script | ✅ OK | `scripts/governance-check.sh` executable |
| PHI Guard | ✅ OK | Whitelist intact, 47 allowed fields |
| CI Status | ✅ PASS | All 284 tests passing |

## Recommended Actions
- [ ] Review test removals in `test_ledger.py` — ensure coverage maintained
- [ ] No blocking issues — safe to merge

## PR Summary Draft
> This PR adds ledger batching support. Tests were reduced by 3 cases (needs review). 
> Contract version bumped with snapshot regen. All CI passing. Governance: minor concern on test coverage.
```

## Failure Recovery Steps
1. If repo path is invalid, search for `~/Directora` and `~/LabBrief` as fallbacks
2. If git command fails (not a git repo), skip git-based checks and do file-system checks only
3. If CI status cannot be fetched (private repo, no token), note "CI status unknown — manual check required"
4. If any check throws an exception, log the traceback and continue with remaining checks
5. On total failure: save report as `~/briefs/governance-failed-YYYY-MM-DD.md` and alert
