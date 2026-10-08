# Architect review prompt

Build the package first, then run the architect command from `config.local.md` with read-only tools, and post the output as a PR comment:

```bash
scripts/review-package.sh origin/main HEAD .pipeline/<slug>/review-pkg-1.md
<architect command> > .pipeline/<slug>/review-1.md
```

`review-brief.md`:

```
You are the architect reviewing PR #<N>. Read-only: don't change files,
the index, or HEAD. Don't spawn sub-agents.

Inputs (read each once):
- spec (binding): <SPEC_PATH>
- plan: <PLAN_PATH>
- review package (commits, stat, full diff with context): <PACKAGE_PATH>
- engineer report (claims, not facts): <REPORT_PATH>
- deferred nits and rulings so far: <LEDGER_PATH>
Also read the surrounding code the diff depends on: <KEY_FILES>.

Review in this order:
1. Security and data: permissions, secrets, injection, personal data,
   destructive paths, migrations.
2. Correctness against the spec, including what a reasonable user expects
   where the spec is silent: races, edge cases, error paths.
3. Claims vs code: docs, policy text, PR body, or report statements the
   code doesn't back.
4. Tests: do they check real behaviour? What's missing for the risky parts?
5. Performance where the spec cares about it.
6. Code quality, only where it matters.

Output, markdown, max ~70 lines, no praise:
- First line: **Verdict: Approve** or **Verdict: Request Changes**
- Numbered findings: severity (blocker / should-fix / nit), file:line,
  the problem, the concrete fix.
- "Set aside": one line per thing you considered out of scope, with why.
- "Checked and fine": one line per risky area you verified.
```
