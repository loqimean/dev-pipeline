#!/bin/bash
# Unattended feature batch: for each slug, worktree -> engineer (cheap model) -> orchestrator checks ->
# architect review (strong model) -> up to MAX_FIX fix rounds with scoped re-review -> verdict comment.
# Sequential, each feature starts no earlier than SLOT seconds after the previous START (resource pacing).
# Layout: $D/context.md (binding rules), $D/<slug>/BRIEF.md (spec). Progress: $D/status.log (one line per event).
# Usage: D=/path/to/batch REPO=/path/to/checkout GH_REPO=owner/repo FEATURES="a b c" bash feature-driver.sh
# Optional: SLOT=3600 MAX_FIX=2 ENG_MODEL=sonnet ARCH_MODEL=<opus id> CHECK_CMD='bash verify.sh {slug} {branch}'
#           SETUP_CMD='cd web && bun install --frozen-lockfile'   (run inside each new worktree)
# Launch detached:  (nohup bash feature-driver.sh > $D/driver.out 2>&1 &)   then report from status.log.
set -u
: "${D:?}" "${REPO:?}" "${GH_REPO:?}" "${FEATURES:?}"
SLOT=${SLOT:-3600}; MAX_FIX=${MAX_FIX:-2}; ENG_MODEL=${ENG_MODEL:-sonnet}; ARCH_MODEL=${ARCH_MODEL:-opus}
RO_TOOLS="Read,Grep,Glob,Bash(git log:*),Bash(git show:*),Bash(git diff:*)"
STATUS=$D/status.log
log() { echo "$(date -u '+%Y-%m-%d %H:%M') $*" >> "$STATUS"; }

# claude -p with resume on usage limit / turn cap. Tools string has spaces: keep it in an array.
run_claude() { # dir out model turns promptfile [tools]
  local dir=$1 out=$2 model=$3 turns=$4 pf=$5 tools=${6:-} try=1
  test -s "$pf" || { log "empty prompt $pf"; return 1; }
  local perm=(--dangerously-skip-permissions); [ -n "$tools" ] && perm=(--allowedTools "$tools")
  while [ $try -le 4 ]; do
    if [ $try -eq 1 ]; then
      (cd "$dir" && timeout 10800 claude -p "$(cat "$pf")" --model "$model" "${perm[@]}" --max-turns "$turns" --output-format text > "$out" 2>&1)
    else
      (cd "$dir" && timeout 10800 claude -c -p "You were stopped mid-task. Run git status and git log first, then finish the same task without redoing finished work." --model "$model" "${perm[@]}" --max-turns "$turns" --output-format text >> "$out" 2>&1)
    fi
    if tail -c 3000 "$out" | grep -qiE "hit your [a-z ]*limit|usage limit reached|limit · resets"; then
      log "usage limit $(basename "$out") try $try, waiting 20 min"; sleep 1200; try=$((try+1)); continue
    fi
    if tail -c 2000 "$out" | grep -qiE "error_max_turns|Reached max turns"; then try=$((try+1)); continue; fi
    return 0
  done
  log "gave up: $out"; return 1
}
verdict_of() { grep -m1 -oE 'Verdict: (Approve|Request Changes)' "$1" | sed 's/Verdict: //'; }
post_verdict() { local c=$2.post.md; awk 'f||/\*\*Verdict:/{f=1;print}' "$2" > "$c"; [ -s "$c" ] || cp "$2" "$c"; gh pr comment "$1" --repo "$GH_REPO" --body-file "$c" >/dev/null 2>&1 && log "posted $(basename "$2") on #$1"; }
pkg() { (cd "$1" && { echo "## Commits"; git log --oneline "$2..$3"; echo; echo '```diff'; git diff -U10 "$2...$3"; echo '```'; } > "$4"); }

feature() {
  local slug=$1 F=$D/$1 WT=/tmp/wt-$1 B=feat/$1 PR base head prev v r=1
  log "START $slug"; git -C "$REPO" fetch -q origin
  [ -d "$WT" ] || git -C "$REPO" worktree add -q -b "$B" "$WT" origin/main || { log "worktree failed $slug"; return; }
  [ -n "${SETUP_CMD:-}" ] && { (cd "$WT" && bash -c "$SETUP_CMD" > "$F/setup.log" 2>&1) || { log "setup failed $slug"; return; }; }
  base=$(git -C "$WT" rev-parse origin/main)
  printf 'You are the engineer. Worktree %s (branch %s). Read %s (binding rules) then %s (spec). Implement end to end: code, tests, build, screenshots, push, open the PR against main, write %s. Do not deploy or merge. Never spawn a reviewer. Commit after each step.\n' "$WT" "$B" "$D/context.md" "$F/BRIEF.md" "$F/report.md" > "$F/eng-prompt.md"
  run_claude "$WT" "$F/eng-1.log" "$ENG_MODEL" 400 "$F/eng-prompt.md"
  PR=$(gh pr list --repo "$GH_REPO" --head "$B" --state open --json number --jq '.[0].number')
  [ -z "$PR" ] && { log "NO PR $slug"; return; }
  log "PR #$PR opened for $slug"
  if [ -n "${CHECK_CMD:-}" ]; then  # shared ports/base worktree: serialize with a lock dir
    until mkdir "$D/.check.lock" 2>/dev/null; do sleep 20; done
    bash -c "${CHECK_CMD//\{slug\}/$slug}" > "$F/verify.log" 2>&1; rmdir "$D/.check.lock"
  fi
  head=$(git -C "$WT" rev-parse HEAD); pkg "$WT" "$base" "$head" "$F/review-pkg-1.md"
  gh pr view "$PR" --repo "$GH_REPO" --json body --jq .body > "$F/pr-body.md"
  printf 'Architect review of PR #%s. Read %s, %s, %s, %s (published body), %s, %s (orchestrator checks, do not re-run). Read the surrounding source files. First line exactly **Verdict: Approve** or **Verdict: Request Changes**, then findings blocker/should-fix/nit with file:line and a concrete fix.\n' "$PR" "$D/context.md" "$F/BRIEF.md" "$F/review-pkg-1.md" "$F/pr-body.md" "$F/report.md" "$F/verify.log" > "$F/review-prompt-1.md"
  run_claude "$WT" "$F/review-1.md" "$ARCH_MODEL" 60 "$F/review-prompt-1.md" "$RO_TOOLS"
  v=$(verdict_of "$F/review-1.md"); log "review 1 $slug: ${v:-none}"; post_verdict "$PR" "$F/review-1.md"
  while [ "$v" = "Request Changes" ] && [ $r -le "$MAX_FIX" ]; do
    printf 'Engineer on PR #%s (worktree %s). Fix every blocker and should-fix in %s (verify each first; push back with reasons in %s). One commit per item, plain push. Re-run tests for changed code. Replace PR-description screenshots if UI changed, never comments.\n' "$PR" "$WT" "$F/review-$r.md" "$F/report.md" > "$F/fix-prompt-$r.md"
    prev=$head; run_claude "$WT" "$F/eng-fix-$r.log" "$ENG_MODEL" 200 "$F/fix-prompt-$r.md"
    git -C "$WT" fetch -q origin "$B"; head=$(git -C "$WT" rev-parse "origin/$B")
    [ "$head" = "$prev" ] && { log "fix $r $slug: no new commits"; break; }
    r=$((r+1)); pkg "$WT" "$prev" "$head" "$F/review-pkg-$r.md"
    printf 'Scoped re-review of PR #%s. Previous review %s, fix diff %s, report %s. For each blocker/should-fix: ADDRESSED or NOT ADDRESSED with file:line. New breakage counts only inside the fix diff. First line exactly **Verdict: Approve** or **Verdict: Request Changes**.\n' "$PR" "$F/review-$((r-1)).md" "$F/review-pkg-$r.md" "$F/report.md" > "$F/review-prompt-$r.md"
    run_claude "$WT" "$F/review-$r.md" "$ARCH_MODEL" 60 "$F/review-prompt-$r.md" "$RO_TOOLS"
    v=$(verdict_of "$F/review-$r.md"); log "review $r $slug: ${v:-none}"; post_verdict "$PR" "$F/review-$r.md"
  done
  log "DONE $slug PR #$PR verdict ${v:-none}"
}

log "DRIVER START $FEATURES"; LAST=""
for slug in $FEATURES; do
  mkdir -p "$D/$slug"
  if [ -n "$LAST" ]; then w=$((LAST + SLOT - $(date +%s))); [ $w -gt 0 ] && { log "waiting $((w/60)) min before $slug"; sleep $w; }; fi
  LAST=$(date +%s); feature "$slug"
done
log "DRIVER DONE"
