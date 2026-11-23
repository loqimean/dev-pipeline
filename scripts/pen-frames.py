#!/usr/bin/env python3
"""Pencil .pen helpers (the file is plain JSON).

  pen-frames.py diff NEW.pen OLD.pen            # top-level frames added / changed since OLD
  pen-frames.py extract FILE.pen OUTDIR ID...   # per frame: frame-<id>.json (+variables) and frame-<id>.outline.txt

Run it as a script file, not a heredoc: .pen files are megabytes and some command guards refuse
to scan large inputs inline.
"""
import json, os, sys


def frames(d):
    return {t['id']: t for t in d['children']}


def strip(n):
    # drop designer annotation overlays (outlines, number badges)
    if isinstance(n, dict):
        nm = str(n.get('name', ''))
        if nm.startswith('Enhancements') or 'hide to see clean' in nm:
            return None
        n = dict(n)
        if 'children' in n:
            n['children'] = [c for c in (strip(x) for x in n['children']) if c is not None]
    return n


def text_of(n):
    c = n.get('content')
    if isinstance(c, list):
        return ''.join(r.get('content', '') if isinstance(r, dict) else str(r) for r in c)
    return c


def outline(n, depth, out):
    keys = ['type', 'width', 'height', 'x', 'y', 'fill', 'stroke', 'cornerRadius', 'padding', 'gap',
            'fontSize', 'fontWeight', 'layout', 'opacity']
    attrs = ' '.join(k + '=' + json.dumps(n[k], ensure_ascii=False) for k in keys if k in n)
    line = '  ' * depth + '- ' + str(n.get('name', '')) + ' [' + str(n.get('id')) + '] ' + attrs
    t = text_of(n)
    if t:
        line += ' TEXT=' + repr(t)
    out.append(line)
    for c in n.get('children', []) or []:
        outline(c, depth + 1, out)


def main():
    cmd = sys.argv[1]
    if cmd == 'diff':
        new, old = (frames(json.load(open(p))) for p in sys.argv[2:4])
        print('NEW frames:')
        for i, f in new.items():
            if i not in old:
                print(' ', i, f.get('name'), f.get('width'), f.get('height'))
        print('CHANGED frames:')
        for i, f in new.items():
            if i in old and json.dumps(f, sort_keys=True) != json.dumps(old[i], sort_keys=True):
                print(' ', i, f.get('name'))
    elif cmd == 'extract':
        src, outdir, ids = sys.argv[2], sys.argv[3], sys.argv[4:]
        d = json.load(open(src))
        by = frames(d)
        os.makedirs(outdir, exist_ok=True)
        for i in ids:
            f = strip(by[i])
            with open(f'{outdir}/frame-{i}.json', 'w') as fh:
                json.dump({'frame': f, 'variables': d.get('variables', {}), 'themes': d.get('themes')}, fh,
                          ensure_ascii=False, indent=1)
            out = []
            outline(f, 0, out)
            with open(f'{outdir}/frame-{i}.outline.txt', 'w') as fh:
                fh.write('\n'.join(out) + '\n')
            print(i, f.get('name'), len(out), 'nodes')
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
