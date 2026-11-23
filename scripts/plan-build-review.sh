#!/bin/bash
# One feature, unattended: architect plan -> engineer (opens the PR) -> architect review -> up to
# MAX_FIX fix rounds with scoped re-review. Verdicts are posted as PR comments. Progress: $D/status.log.
# Inputs: $D/spec.md (binding spec), an existing worktree $WT on branch $B with deps installed.
# Usage: D=/path/qa/<slug> WT=/tmp/<repo>-<slug> B=feat/<slug> GH_REPO=owner/repo BASE_REF=origin/main \
#        ARCH_MODEL=<opus id> ENG_MODEL=sonnet PR_TITLE="..." FOCUS="review focus sentence" \
#        READ_FILES="files the architect must read" bash plan-build-review.sh
# Launch from Hermes: terminal(background=true, notify=true, persist_on_release=true) running
#   cd <run dir> && source env.sh && bash plan-build-review.sh > driver.out 2>&1 < /dev/null
# A run that stopped midway (usage limit gave up, fix round with no commits): scripts/resume-pipeline.sh.
# BASE_REF = the branch the review diff starts from (origin/main, or an approved PR's branch it stacks on).
# PR_BASE  = the branch the engineer opens the PR against (default main; set it for stacked/feature-branch PRs).
set -u
: "${D:?}" "${WT:?}" "${B:?}" "${GH_REPO:?}"
BASE_REF=${BASE_REF:-origin/main}; PR_BASE=${PR_BASE:-main}; ARCH_MODEL=${ARCH_MODEL:-opus}; ENG_MODEL=${ENG_MODEL:-sonnet}
MAX_FIX=${MAX_FIX:-2}; PR_TITLE=${PR_TITLE:-$B}; FOCUS=${FOCUS:-}; READ_FILES=${READ_FILES:-}
RO_TOOLS="Read,Grep,Glob,Bash(git log:*),Bash(git show:*),Bash(git diff:*)"
STATUS=$D/status.log
log() { echo "$(date -u '+%Y-%m-%d %H:%M') $*" >> "$STATUS"; }
RULES=${RULES:-"English only. No people's names, no other companies' sites."}
MAX_TRIES=${MAX_TRIES:-12} # 12 x 20 min: a subscription session limit can take hours to reset

run_claude() { # out model turns promptfile [tools]
  local out=$1 model=$2 turns=$3 pf=$4 tools=${5:-} try=1
  test -s "$pf" || { log "empty prompt $pf"; return 1; }
  local perm=(--dangerously-skip-permissions); [ -n "$tools" ] && perm=(--allowedTools "$tools")
  while [ $try -le $MAX_TRIES ]; do
    if [ $try -eq 1 ]; then
      (cd "$WT" && timeout 14400 claude -p "$(cat "$pf")" --model "$model" "${perm[@]}" --max-turns "$turns" --output-format text > "$out" 2>&1)
    else
      (cd "$WT" && timeout 14400 claude -c -p "You were stopped mid-task. Run git status and git log first, then finish the same task without redoing finished work." --model "$model" "${perm[@]}" --max-turns "$turns" --output-format text >> "$out" 2>&1)
    fi
    if tail -c 3000 "$out" | grep -qiE "hit your [a-z ]*limit|usage limit reached|limit · resets"; then
      log "usage limit $(basename "$out") try $try, waiting 20 min"; sleep 1200; try=$((try+1)); continue
    fi
    if tail -c 2000 "$out" | grep -qiE "error_max_turns|Reached max turns"; then log "turn cap $(basename "$out") try $try"; try=$((try+1)); continue; fi
    return 0
  done
  log "gave up: $out"; return 1
}
verdict_of() { grep -m1 -oE 'Verdict: (Approve|Request Changes)' "$1" | sed 's/Verdict: //'; }
post_verdict() { # never post a file without a verdict line (a usage-limit stop leaves only the limit text)
  local c=$2.post.md
  [ -n "$(verdict_of "$2")" ] || { log "no verdict in $(basename "$2"), not posted"; return 1; }
  awk 'f||/\*\*Verdict:/{f=1;print}' "$2" > "$c"; [ -s "$c" ] || cp "$2" "$c"
  gh pr comment "$1" --repo "$GH_REPO" --body-file "$c" >/dev/null 2>&1 && log "posted $(basename "$2") on #$1"
}
pkg() { (cd "$WT" && { echo "## Commits"; git log --oneline "$1..$2"; echo; echo '```diff'; git diff -U10 "$1...$2"; echo '```'; } > "$3"); }

log "PIPELINE START"
BASE=$(git -C "$WT" rev-parse "$BASE_REF")

# 1. Plan: the architect can't create files, so it prints the plan after a marker line.
printf 'You are the architect. Repo at %s (branch %s). Read the binding spec %s and the files it names, then the code: %s. Write an implementation plan for a cheaper engineer model: target structure (new files and what each owns), then numbered tasks with files, exact values, a verification command and risky: yes|no. Resolve the points the spec leaves open by reading the code and state each decision. Print the plan to stdout starting with a line that is exactly "# PLAN". %s\n' "$WT" "$B" "$D/spec.md" "$READ_FILES" "$RULES" > "$D/plan-prompt.md"
run_claude "$D/plan-raw.md" "$ARCH_MODEL" 60 "$D/plan-prompt.md" "$RO_TOOLS"
awk 'f||/^# PLAN/{f=1;print}' "$D/plan-raw.md" > "$D/plan.md"
[ -s "$D/plan.md" ] || { log "NO PLAN"; exit 1; }
log "plan written ($(wc -l < "$D/plan.md") lines)"

# 2. Engineer
printf 'You are the engineer. Worktree %s (branch %s, checked out, deps installed). Read the spec %s (binding) and the plan %s, then implement it end to end: code, tests, build, browser checks, screenshots, push, and open the PR against %s with gh (title: "%s"). The PR body must end with an "## Evidence" section: raw test counts, e2e measurements, and every screenshot uploaded into the body with gh pr edit --attach (never left only on disk, never committed to a side branch and linked by blob/raw URL: those do not render for a private repo). Commit after each task. Use the terminal and file tools. Do not deploy, do not merge, never spawn a reviewer. Write %s: per task what changed, commands with raw pass/fail counts, the PR URL, screenshot paths, and every decision you made on your own. Keep QA scripts under %s/qa/. %s\n' "$WT" "$B" "$D/spec.md" "$D/plan.md" "$PR_BASE" "$PR_TITLE" "$D/report.md" "$D" "$RULES" > "$D/eng-prompt.md"
run_claude "$D/eng-1.log" "$ENG_MODEL" 500 "$D/eng-prompt.md"
PR=$(gh pr list --repo "$GH_REPO" --head "$B" --state open --json number --jq '.[0].number')
[ -z "$PR" ] && { log "NO PR (engineer log $D/eng-1.log)"; exit 1; }
log "PR #$PR opened"

# 3. Review loop
git -C "$WT" fetch -q origin "$B"; head=$(git -C "$WT" rev-parse "origin/$B")
pkg "$BASE" "$head" "$D/review-pkg-1.md"
gh pr view "$PR" --repo "$GH_REPO" --json body --jq .body > "$D/pr-body.md"
printf 'Architect review of PR #%s (repo at %s, head %s). Read %s (binding), %s, the diff package %s, the published PR body %s and the engineer report %s (claims; do not re-run tests). Read the surrounding source files in full: %s. Focus: spec conformance; the published body has an Evidence section with counts and, for UI work, uploaded screenshots (missing = should-fix); %s First line exactly **Verdict: Approve** or **Verdict: Request Changes**, then numbered findings blocker/should-fix/nit with file:line and a concrete fix. %s\n' "$PR" "$WT" "$head" "$D/spec.md" "$D/plan.md" "$D/review-pkg-1.md" "$D/pr-body.md" "$D/report.md" "$READ_FILES" "$FOCUS" "$RULES" > "$D/review-prompt-1.md"
run_claude "$D/review-1.md" "$ARCH_MODEL" 60 "$D/review-prompt-1.md" "$RO_TOOLS"
v=$(verdict_of "$D/review-1.md"); log "review 1: ${v:-none}"; post_verdict "$PR" "$D/review-1.md"
r=1
while [ "$v" = "Request Changes" ] && [ $r -le $MAX_FIX ]; do
  printf 'Engineer on PR #%s (worktree %s, branch %s). Fix every blocker and should-fix in %s; verify each against the code first and push back with reasons in %s where it is wrong. Spec %s stays binding. One commit per item, plain push, no force. Re-run the tests for changed code. If the UI changed, re-shoot and REPLACE the screenshots in the PR description, never in comments. Append what you changed per finding to %s. %s\n' "$PR" "$WT" "$B" "$D/review-$r.md" "$D/report.md" "$D/spec.md" "$D/report.md" "$RULES" > "$D/fix-prompt-$r.md"
  prev=$head; run_claude "$D/eng-fix-$r.log" "$ENG_MODEL" 250 "$D/fix-prompt-$r.md"
  git -C "$WT" fetch -q origin "$B"; head=$(git -C "$WT" rev-parse "origin/$B")
  [ "$head" = "$prev" ] && { log "fix $r: no new commits"; break; }
  r=$((r+1)); pkg "$prev" "$head" "$D/review-pkg-$r.md"
  gh pr view "$PR" --repo "$GH_REPO" --json body --jq .body > "$D/pr-body.md"
  printf 'Scoped re-review of PR #%s (repo at %s, head %s). Previous review %s, fix diff %s, report %s, spec %s, published body %s. For each previous blocker/should-fix: ADDRESSED or NOT ADDRESSED with file:line, checked in the code, not the commit message. New breakage counts only inside the fix diff. Print the review to stdout; do not try to write files. First line exactly **Verdict: Approve** or **Verdict: Request Changes**. %s\n' "$PR" "$WT" "$head" "$D/review-$((r-1)).md" "$D/review-pkg-$r.md" "$D/report.md" "$D/spec.md" "$D/pr-body.md" "$RULES" > "$D/review-prompt-$r.md"
  run_claude "$D/review-$r.md" "$ARCH_MODEL" 45 "$D/review-prompt-$r.md" "$RO_TOOLS"
  v=$(verdict_of "$D/review-$r.md"); log "review $r: ${v:-none}"; post_verdict "$PR" "$D/review-$r.md"
done
log "DONE PR #$PR verdict ${v:-none} head $head"
