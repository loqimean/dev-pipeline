# Local configuration (example)

Copy to `config.local.md` (git-ignored) and fill in. The pipeline reads this file to know which tool and model fill each role.

## Architect (plan, review, re-review)

- Command: `<cli> -p "$(cat brief.md)" --model <most-capable-model> --max-turns 40`
- Read-only tools: read, grep, glob, `git diff`, `git log`, `git show`. Plan runs may also write the plan file.

## Engineer

- Command: `<agent-cli> --profile <project> --query-file brief.md`
- Model: `<cheaper-model>`
- For long runs: start under `nohup` with a `timeout` and a log file, so a dropped connection can't kill it.

## Commit identity

- `git -c user.name="<name>" -c user.email="<email>"`
- Push policy: plain push, never force.

## Project notes

- Where each project's conventions live (skill files, CONTRIBUTING, etc.).
- Ports, services, or hosts that must never be touched.
