# Preview builds of a flagged feature (Vercel)

Use when the owner asks for a "preview build" of a PR so he can try it. A preview isn't a production deploy, so the owner asking for it is the go-ahead. Never promote it (`--prod`) and never merge.

## Order
1. Wait for an architect **Approve** on the PR head, then deploy that exact head. A preview of a Request Changes head shows bugs that are already being fixed.
2. Flags stored in the DB are off in a preview, because previews read the same flag table as production. Turn the feature on for the preview only, using the build-time override the feature already honours (e.g. `VITE_FORCE_FLAGS=<key>`). Put "the override must work from a plain `vite build` with that env" in the engineer brief, so the preview needs no code change.
3. Deploy from the worktree's repo root, not from the app subfolder. The project's Root Directory setting (e.g. `web`) is applied relative to where you deploy from. Copy the link file in first, and don't commit it:
   ```
   mkdir -p .vercel && cp <main checkout>/<app>/.vercel/project.json .vercel/
   vercel deploy --yes --build-env VITE_FORCE_FLAGS=<key>
   ```
   This builds on Vercel with the project's Preview env vars, so no secrets are handled locally. The command prints JSON hints, not the URL: take the URL from `vercel ls <project> | head`.
4. Check the deployment yourself before sending the link:
   - **Status:** `vercel inspect <url>` shows `target preview` and `status Ready`.
   - **Protection:** a plain `curl` returns 302 to `vercel.com/sso-api` when Deployment Protection is on. That is expected, so tell the owner to sign in to Vercel in that browser first. Read through the protection with `vercel curl <path> --deployment <url>`.
   - **Flag:** prove the override is baked in. Fetch the home page, grep it for the route's asset names, fetch those chunks with `vercel curl`, and grep for the flag key. A forced build shows the inlined literal (`` `<key>`.split(`,`).includes(`<key>`) ``); an unforced one shows an empty string there.
5. Report the URL, what you verified (status, flag inlined), what you didn't (a real device), that production is untouched, and the owner step that turns it on for real (`/admin/flags`).

## Production deploy after a merge (only on the owner's explicit "deploy it")
1. Merging may not deploy anything: check `vercel ls <project> | head` and `gh run list --repo <o>/<r> --branch main --limit 3` right after the merge. A repo can run DB migrations from a GitHub Action on merge while Vercel's git integration is off, so tell the owner which of the two happened.
2. Deploy exactly `origin/main` from a fresh detached worktree, never from a feature worktree (its `.vercel`, local edits or forced-flag habits leak in):
   ```
   git fetch && git worktree add --detach /tmp/<app>-deploy origin/main
   cd /tmp/<app>-deploy && mkdir -p .vercel && cp <main checkout>/<app>/.vercel/project.json .vercel/
   vercel env ls production | grep -c FORCE   # must be 0: no forced flags in Production env
   vercel deploy --prod --yes                  # no --build-env
   ```
   Before deploying, also list the env var NAMES for every feature merged since the last deploy (`vercel env ls production | grep -i <feature>`). The owner may have added them already, which makes an env-gated feature (one with no DB flag, e.g. a sign-in provider) go live with this deploy. Say so in the report, and probe the live flow yourself (e.g. Playwright clicks the sign-in button and records the redirect chain up to the provider's own login page, with state/challenge params masked).
3. Verify: `vercel inspect <url>` shows `target production`, `Ready`, and the custom domains among its aliases; the live domain answers 200 on home and one deep page; the feature chunk is referenced but the override literal is empty (flag still governed by `/admin/flags`).
   Also read the migrations workflow result for every merged sha (`gh run list --branch main`). A failed run means a flag row or table is missing in production; read `gh run view <id> --log-failed` (grep, never print DB URLs). `Found local migration files to be inserted before the last migration on remote database` means a PR's migration timestamp sorts before one already applied: fix it with a small PR that only `git mv`s the file to a timestamp after the latest one (SQL unchanged, idempotent insert), and require every brief's migration name to sort after all existing files.
4. Remove the deploy worktree, then report: sha deployed, checks run, and the flag step left to the owner.
