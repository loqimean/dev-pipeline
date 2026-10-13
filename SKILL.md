---
name: dev-pipeline
description: "Use when building a feature or fix in a repo. Spec, architect plan, engineer, review loop, tests, evidence report."
version: 1.1.0
metadata:
  tags: [workflow, code-review, planning, verification]
---

# Dev pipeline

One process for every change: requirements, architect plan, engineer, architect review, fixes until approved, tests, evidence report.
Roles stay separate. The architect runs on the most capable model, the engineer on a cheaper one, and the orchestrator only coordinates.

Diagram and rationale: [README.md](README.md). Prompt templates are in `templates/`, helper scripts in `scripts/`.
Local setup (which tools and models fill each role, commit identity) lives in `config.local.md` next to this file. It's git-ignored; copy [config.example.md](config.example.md) to create it.

## Roles

- **Owner:** the person the work is for. Approves big or risky plans, merges, approves deploys.
- **Orchestrator:** the agent session talking to the owner. Owns the ledger, writes dispatch briefs, routes findings, reports. Never writes product code and never fixes review findings itself (that skips review).
- **Architect:** the most capable model, run as a separate read-only session. Writes the plan, reviews diffs. May write only the plan file.
- **Engineer:** a cheaper model in its own session with the project's context. Implements, tests, commits, pushes. Never spawns its own reviewer.

## Stages

### 1. Requirements

- Restate the ask in one short list: scope, out of scope, constraints from the project's notes.
- Ask the owner only what blocks the plan. One message, max 3 questions, recommended option first.
- Write the spec to `docs/plans/<date>-<slug>.md` in the worktree (or a scratch folder). The spec is the binding authority for every later stage.

### 2. Architect plan

- Dispatch with [templates/architect-plan.md](templates/architect-plan.md). The architect reads the spec and the code, not the chat.
- The plan lists tasks, each with files, exact values, a verification command, and a `risky: yes|no` flag.
- **Approval gate:** send the plan summary to the owner and wait ONLY when the change is big or risky: auth, payments, personal data, DB migrations, deletes, infra, anything irreversible, or more than ~600 changed lines. Otherwise continue and mention the plan in the report.

### 3. Engineer

- One worktree per feature, branch off the main branch. Never work on main directly.
- Dispatch with [templates/engineer-brief.md](templates/engineer-brief.md): the plan path, the global constraints, the report-file path. No chat history, no prior-task summaries.
- Batch routine tasks into one dispatch. Risky tasks get their own dispatch and their own review (stage 4) before the next task starts.
- The engineer runs the task's verification command, commits, and appends to the report file: what changed, commands run, raw pass/fail counts.

### 4. Architect review

- Build the review package as a file: `scripts/review-package.sh <base> <head> <out>`. The diff never enters the orchestrator's context.
- Dispatch with [templates/review.md](templates/review.md): spec path, plan path, package path, report path.
- Verdict line first: `**Verdict: Approve**` or `**Verdict: Request Changes**`. Findings are `blocker`, `should-fix`, or `nit`, each with file:line and a concrete fix.
- Post the review on the PR as a comment. Self-authored PRs can't take a formal review state.

### 5. Fix loop

- Blockers and should-fix enter the loop. Nits go to the ledger as deferred; the final review decides which matter.
- ONE fix dispatch per round with the complete findings list, not one engineer per finding.
- The engineer may push back with technical reasons (see "Receiving review"). The orchestrator rules on each pushback, records `Ruling: <decision> — <why> — <cost if wrong>` in the ledger, and passes it to the re-review.
- Re-review is scoped: [templates/re-review.md](templates/re-review.md) gets only the open findings, the fix diff package (`<previous reviewed head>..<new head>`), and the report. Each finding is ADDRESSED or NOT ADDRESSED. New breakage counts only inside the fix diff. Anything else is an out-of-scope note for the ledger.
- **Cap: 3 rounds.** Still open after round 3 → stop and send the owner the open findings with both sides and a recommendation. Don't adjudicate early to end a loop.
- A "fixed it" commit message is never approval. Only a re-review verdict closes a finding.

### 6. Testing

- Scripts, not model calls: typecheck, unit tests, builds, browser end-to-end suites, real DB checks where data or auth changed. The model reads only pass/fail summaries and failure lines.
- Regression: every existing suite for the touched area, plus a production-like build.
- UI changes: screenshots in the light theme only, desktop and phone, unless the change is about the dark theme itself. One visual check per screen on the final version, not per iteration.
- Screenshots must be full-viewport captures (e.g. 1440x900 desktop, 390x844 phone), never element crops (`locator.screenshot()`, `clip`). A cropped dialog or a 64 px header strip proves nothing: the reader can't see where the element sits, what's around it, or whether it's cut off. Before attaching, check that every element the shot is meant to show is fully inside the frame (bounding box within the viewport, no ellipsis, no clipping).
- Screenshots go only in the PR description, never in comments.
- When checking a screenshot, also check placement, not just visibility: a dialog must be centred (or anchored to its trigger), not stuck to a viewport corner. "Fully inside the frame" isn't enough; assert the position in tests too.
- Speed-sensitive pages: performance audit before vs after.

### 7. Bugs found in testing

- A bug fix is a fix round: the engineer fixes with a failing test first where practical, then a scoped re-review of that diff. Counts against the same 3-round cap.

### 8. Report to the owner

Follow [templates/report.md](templates/report.md): PR link, what changed, evidence (exact pass counts, screenshots as attachments), review verdict history, every `Ruling:` line from the ledger, open points, and the next decision needed. No deploy or merge without the owner's explicit go-ahead unless the task said so.

## Ledger

`.pipeline/<slug>/ledger.md` in the worktree (git-ignored). First line `# Ledger — <spec path>`. Append one line per event:

```
plan: <path> (approved by owner | auto: routine)
task 3: done <base7>..<head7>, tests 24/24
review 1: Request Changes, 1 blocker, 6 should-fix, 7 nits (comment <url>)
fix round 1: 6 addressed, 1 open (<one-liner>) <a7>..<b7>
Ruling: kept local data on sign-out — user's own device — leaks on shared devices if wrong
deferred nit: <one-liner>
```

After a context compaction, trust the ledger and `git log`, not memory. Never re-dispatch work the ledger marks done.

## Token rules

- The most capable model only for the plan and reviews. A cheaper model for code and fixes. Always set the model explicitly; an omitted model inherits the most expensive one.
- Hand artifacts over as files (spec, plan, brief, diff package, report). Never paste diffs or history into prompts.
- One full review per PR. Per-task reviews only for tasks flagged risky.
- Re-reviews read only the fix diff and the open findings. Small mechanical fix diffs can use a cheaper reviewer.
- Background runs: wait in bounded stretches, check the log tail, don't poll every few seconds.
- Every detached run gets a watcher that notifies the orchestrator when it exits. Finished work must never sit idle waiting to be noticed.
- Fix rounds run only the tests covering the changed code. The full regression set and performance audits run once, right before the report to the owner.

## Receiving review (engineer and orchestrator)

- Verify each finding against the code before changing anything. Restate it, check it, then act or push back.
- Push back with evidence when the finding is wrong for this codebase, breaks existing behaviour, contradicts the owner's decisions, or adds unused features.
- No performative agreement. State the fix and where it is.
- If a finding conflicts with a decision the owner made, stop and ask; don't let the reviewer overrule them.

## Verification before claims

No "done", "passes", or "fixed" without a fresh command run and its output in the same report. Agent self-reports are claims: check the diff, the commits, and the test output before repeating them to the owner.

## Pitfalls

- Unattended agent sessions may refuse some tools. Briefs should name the tools the engineer can rely on.
- Large files get corrupted by read-modify-write through truncated tool output. Edit them with targeted patches only.
- Review sessions need a turn budget of 30-40, or they stop mid-read and return nothing useful.
- The reviewer must read surrounding files, not just the diff. Name the key files in the prompt.
- Hosting platforms usually won't let a PR author request changes on their own PR. Post verdicts as comments.
- A read-only reviewer still needs permission to write its own output file. Grant edit access to that one path (check how your CLI names file-write rules), or capture stdout and strip everything before the verdict line.
- Before and after any local test server, check that its ports are free. A stale server from an earlier build answers instead of the new one, and an agent can spend an hour "fixing" code that works.

## Credits

Adapted from [obra/superpowers](https://github.com/obra/superpowers) (MIT): ledger, review packages as files, scoped re-review, fix-round cap, rulings log, receiving-review and verification rules. Changed for cost: one review per PR instead of per task, a 3-round cap that escalates to the owner, and the architect and engineer split across separate sessions and models.
