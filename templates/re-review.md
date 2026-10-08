# Scoped re-review prompt

```bash
scripts/review-package.sh <PREVIOUS_REVIEWED_HEAD> HEAD .pipeline/<slug>/review-pkg-<R>.md
<architect command, turn budget ~25> > .pipeline/<slug>/review-<R>.md
```

A cheaper reviewer model is fine when the fix diff is small and mechanical.

`rereview-brief.md`:

```
You are re-reviewing fix round <R> of PR #<N>. This isn't a fresh review.
Read-only. Don't spawn sub-agents. Don't re-run test suites; run one
focused test only if the code raises a specific doubt.

Findings under verification (verbatim from the previous review):
<OPEN_FINDINGS>

Orchestrator rulings on pushback: <RULINGS or "none">

Inputs:
- fix diff package (<PREVIOUS_HEAD>..<HEAD>): <PACKAGE_PATH>
- engineer report, fix section at the end (claims, not facts): <REPORT_PATH>
- spec: <SPEC_PATH>

Output, starting directly with the first verdict:
- Per finding, in order: ADDRESSED or NOT ADDRESSED, with file:line.
  "Attempted" is not addressed. For a pushback, say whether the reasoning
  holds.
- New breakage in the fix diff only: severity + file:line, or "None".
- Out-of-scope notes (outside the fix diff): one line each, non-blocking.
- Last line: **Verdict: Approve** (all addressed, no new blocker or
  should-fix) or **Verdict: Request Changes** listing what's open.
```
