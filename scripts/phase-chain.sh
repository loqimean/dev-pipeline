#!/bin/bash
# Stacked multi-phase build: runs plan-build-review.sh for phase 1..N in order, each phase's
# worktree cut from the previous phase's pushed branch (or its own PR_BASE). Stops at the first
# phase whose driver doesn't end with an Approve verdict, so a stuck phase never feeds the next one.
# Layout: $F/context.md (binding for all phases), $F/p<n>/spec.md, $F/p<n>/env.sh (D, WT, B,
# PR_BASE, BASE_REF, models, PR_TITLE, FOCUS, READ_FILES, RULES, APP_PORT, AI_PORT), plus fresh
# copies of plan-build-review.sh and resume-pipeline.sh in $F. Optional $F/e2e-recipe.md with
# placeholders __APP_PORT__ / __AI_PORT__ / __WT__ is rendered into each worktree.
# Launch: terminal(background=true, notify=true, persist_on_release=true):
#   cd $F && N=4 REPO=<main checkout> bash phase-chain.sh > chain.out 2>&1 < /dev/null
# Resume after a stopped phase: fix or resume that phase by hand, then START=<next n>.
set -u
F=${F:-$(cd "$(dirname "$0")" && pwd)}; REPO=${REPO:?main checkout path}; N=${N:?phase count}
log() { echo "$(date -u '+%Y-%m-%d %H:%M') $*" >> "$F/chain.log"; }
START=${START:-1}
for n in $(seq 1 "$N"); do
  [ "$n" -lt "$START" ] && continue
  run=$F/p$n
  ( source "$run/env.sh"; echo "$WT $B $PR_BASE ${APP_PORT:-0} ${AI_PORT:-0}" ) > "$run/.vars"
  read -r wt b base app ai < "$run/.vars"
  git -C "$REPO" fetch -q origin; git -C "$REPO" worktree prune
  if [ ! -d "$wt" ]; then
    git -C "$REPO" worktree add -q -B "$b" "$wt" "origin/$base" || { log "p$n worktree failed"; exit 1; }
  fi
  mkdir -p "$wt/.pipeline"; cp "$run/spec.md" "$wt/.pipeline/spec.md"
  [ -f "$F/e2e-recipe.md" ] && sed -e "s/__APP_PORT__/$app/g" -e "s/__AI_PORT__/$ai/g" -e "s#__WT__#$wt#g" \
    "$F/e2e-recipe.md" > "$wt/.pipeline/e2e-recipe.md"
  log "p$n start ($b from $base)"
  ( cd "$run" && source env.sh && bash "$F/plan-build-review.sh" > "$run/driver.out" 2>&1 < /dev/null )
  last=$(tail -1 "$wt/.pipeline/status.log" 2>/dev/null)
  case "$last" in
    *"DONE PR #"*"verdict Approve"*) log "p$n approved: $last" ;;
    *) log "p$n stopped: $last"; exit 1 ;;
  esac
done
log "ALL DONE"
