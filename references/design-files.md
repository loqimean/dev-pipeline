# Building UI from a design file (Pencil `.pen`)

Use when the owner says "implement frame X from the design" or "we updated the design of Y".

## Read the file
- A Pencil `.pen` file is plain JSON. You don't need the Pencil app to read it, and don't install it to answer "can you see it?". Top-level keys: `version`, `children` (the frames), `themes`, `variables`, `fileToken`.
- Each top-level frame has `id`, `name`, `width` and `height`. Nodes carry `type`, `name`, `content` for text (a string or a list of runs), `fill`, `fontSize`, padding, gaps and radii. Fills use `$token` references.
- `variables` hold the colour tokens. Each has a value per theme, `{"value": "#059669", "theme": {"mode": "light"}}` and the same for dark, so one file gives you both themes.
- To list frames: `for t in d['children']: print(t['id'], t.get('name'), t.get('width'), t.get('height'))`. Frame names say platform, width, screen and theme (e.g. `Web · Mobile 390 · Пошук · light`). Frames named `… · ключ` are legends that number what the design changes. Read them: they are the designer's change list.
- Child groups named like `Enhancements (hide to see clean)` are annotation overlays (outlines and number badges), not UI. Strip them before handing the frame over.
- Find the file by name: `mdfind -name .pen`. Designs often live in the notes vault, not the repo. Read the file's mtime too, so you can tell the owner how fresh it is.
- **"We updated the design of X": find out WHAT changed before planning.** Older copies of the `.pen` usually sit in earlier QA folders (`find ~/qa -name '*.pen'`). Run `scripts/pen-frames.py diff NEW.pen OLD.pen` to list frames added and changed since that copy, and compare with the last commits that implemented the screen (`git log -3 --format='%h %ad %s' -- <files>`): a previous session may already have built part of the update. Then ask the architect for a gap list (design vs current app, each item matches / gap) and implement only the gaps.
- `scripts/pen-frames.py extract FILE.pen OUTDIR <id>...` writes the hand-off files below (`frame-<id>.json` with the `variables` block, `frame-<id>.outline.txt`). Run it from a script file, not an inline heredoc: the file is megabytes.
- When the owner's newer design disagrees with an older shipped behaviour (e.g. colours taken from the web version), the newer design wins for looks; tell the engineer so explicitly and list the change in the PR body.

- To get a picture without the design app, re-draw the in-scope nodes as absolutely positioned HTML with the resolved values, screenshot it at the frame size and put it side by side with the current build (ffmpeg `hstack`). Say it is a re-draw, and measure overflow in it with `getBoundingClientRect` (e.g. a chip row wider than the screen), not by eye.

## Before building
- Check that it isn't built already. Open PRs whose title says "redesign to the design" may cover only one platform: read the PR's file list (`gh pr view N --json files`). The `mobile/` app and the `web/` app are different targets.
- Map each "legend" item to built, in an open PR, or missing. Scope the PR to the one frame the owner named. Put the header or map parts of a sibling frame in a separate PR.

## Hand-off to the engineer
The engineer can't render the file either. Give it (`scripts/pen-frames.py extract` makes 1 and 2):
1. `frame-<id>.json`: the frame without the annotation overlay, plus the `variables` block.
2. A readable outline: the indented tree of node names, sizes and fills, with text contents.
3. Any shared component the frame uses (bottom nav etc.) as its own JSON, marked reference-only.
4. Copy the source `.pen` into the QA folder. iCloud paths with spaces and `-rw-------` modes break engineer shells.

Tell it to take exact numbers from the JSON. Map design colours onto the site's existing theme tokens, and add any missing token for light AND dark in the theme CSS, never as a hex in a component. List every deviation from the design in the PR body.

## Checking the result
Vision misreads exact glyph counts in masks and placeholders (e.g. `___:____` read as `____:_____`). Before reporting such a mismatch, run the pure helper (`bun run` a one-line script calling it) and compare its output with the design text.
