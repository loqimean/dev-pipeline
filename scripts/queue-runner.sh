#!/bin/bash
# File-driven, one-at-a-time engineer queue. Run one instance per lane (max 2 lanes per agent profile).
# Jobs file: one line per job: "<name> <brief-file> [resume-session-id]". Add or insert lines at any time.
# Usage: queue-runner.sh <jobs-file> <log-file> [pid-to-wait-for name-of-that-job]
# Set AGENT_CMD to the engineer command; it receives the brief path and an optional session id, e.g.
#   AGENT_CMD='run_engineer'   where run_engineer() { mytool chat ${2:+--resume "$2"} --query-file "$1"; }
# Resumes the same session with CONTINUE_BRIEF (a short generic "continue from git state" brief) when
# the output shows a rate limit (after RL_WAIT seconds) or a turn/iteration cap (immediately).
# Max 4 attempts per job. Logs "started", "rate-limited", "finished <name>: EXIT <rc> session <id>".
F=$1; Q=$2; WAIT_PID=$3; WAIT_NAME=$4
RL_PATTERN=${RL_PATTERN:-'HTTP 429'}; RL_WAIT=${RL_WAIT:-600}; JOB_TIMEOUT=${JOB_TIMEOUT:-9000}
CAP_PATTERN=${CAP_PATTERN:-'Iteration budget (reached|exhausted)'}
SESSION_RE=${SESSION_RE:-'Session: +[0-9_a-f]+'}
log() { echo "$(date -u +%H:%M) $*" >> "$Q"; }
[ -n "$WAIT_PID" ] && { while kill -0 "$WAIT_PID" 2>/dev/null; do sleep 30; done; log "finished $WAIT_NAME"; }
while true; do
  line=$(grep -v '^\s*$' "$F" 2>/dev/null | head -1)
  [ -z "$line" ] && { log "QUEUE EMPTY"; exit 0; }
  sed -i.bak '0,/^\s*[^ ]/{/^\s*[^ ]/d}' "$F"   # GNU sed; on macOS use gsed
  set -- $line; name=$1; brief=$2; sid=$3
  log "started $name"
  for attempt in 1 2 3 4; do
    out="$(dirname "$Q")/queue-$name.log"
    timeout "$JOB_TIMEOUT" $AGENT_CMD "$brief" "$sid" > "$out" 2>&1; rc=$?
    s2=$(tr -d '\r' < "$out" | grep -aoE "$SESSION_RE" | tail -1 | awk '{print $NF}'); [ -n "$s2" ] && sid=$s2
    if tr -d '\r' < "$out" | grep -aqE "$RL_PATTERN"; then
      log "rate-limited $name (attempt $attempt), waiting $RL_WAIT s"; sleep "$RL_WAIT"
      brief=${CONTINUE_BRIEF:-$brief}; continue
    fi
    if [ -n "$sid" ] && [ $attempt -lt 3 ] && tr -d '\r' < "$out" | grep -aqE "$CAP_PATTERN"; then
      log "turn cap $name, resuming"; brief=${CONTINUE_BRIEF:-$brief}; continue
    fi
    log "finished $name: EXIT $rc session $sid"; break
  done
done
