# Engineer brief

Send with the engineer command from `config.local.md`. For long runs, start it under `nohup` with a `timeout` and a log file, so a dropped connection can't kill it.

`brief.md`:

```
You are the engineer for <PROJECT>. Load the project's notes first.
Work in the worktree <WORKTREE> on branch <BRANCH>. Never work on main.

Read first, they are your requirements:
- spec: <SPEC_PATH>
- plan: <PLAN_PATH> (do tasks <N..M>; exact values are in the plan)

Global constraints (binding):
<CONSTRAINTS copied from the plan, verbatim>

Rules:
- Don't spawn reviewers or sub-agents. Review comes from the architect.
- Edit with targeted patches. Large files: patch only, never rewrite them
  from truncated output.
- For each task: implement, run its verification command, commit with the
  identity from config.local.md, plain push, never force.
- Append to <REPORT_PATH> per task: files changed, commands run, raw
  pass/fail counts, and any decision you made as
  "Ruling: <what> — <why> — <cost if wrong>".
- If the plan is wrong or blocks you, write BLOCKED with the reason in the
  report and stop that task; don't guess at scope.
- Open the PR at the end and attach screenshots for UI changes.
- Don't deploy, don't merge.

Final reply (short): status DONE | DONE_WITH_CONCERNS | BLOCKED, commit
shas, PR URL, one-line test summary, concerns. Details stay in the report.
```

## Fix-round brief

```
Review round <R> on PR #<N> came back Request Changes. Findings (verbatim):
<FINDINGS: blockers and should-fix only>

Rulings from the orchestrator: <RULINGS or "none">

For each finding: check it against the code first. Fix it, or push back
with evidence (file:line, test output) if it's wrong for this codebase or
conflicts with a decision the owner made. Run the tests covering each change.
Append to <REPORT_PATH>: per finding, FIXED <sha> or PUSHBACK <reason>,
plus the commands and raw counts. Plain push. Don't post a verdict yourself.
```
