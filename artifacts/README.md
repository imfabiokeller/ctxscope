# Snapshots

`ctxscope-snapshots` writes its PNGs here by default. They are rendered
without a window server session and without screen capture permission, at two
device pixels per point, and are not committed.

```
swift run ctxscope-snapshots                # the views over synthetic sessions
swift run ctxscope-snapshots --samples      # sample screens, into samples/
swift run ctxscope-snapshots --out DIR      # anywhere else
```

Every picture comes in `-light` and `-dark`.

## The views

| File | What it shows |
|---|---|
| `window-200k`, `window-1m` | The window over a synthetic session at a 200k and a 1M window |
| `window-one-request`, `window-two-requests` | The two shortest sessions there are |
| `window-text-200k` | A block selected with its text |
| `window-replay-200k` | The playhead halfway, so the requests after it are dimmed |
| `lanes` | A session with thirteen lanes |
| `empty` | No session focused |
| `connect-*` | The Connect panel: off, on, moved to another port, a file changed while it was open, a file it will not touch |
| `popover-*` | The menu bar popover at both window sizes, the two shortest sessions, and nothing focused |
| `status-<state>-<bar>-bar-<scale>` | The menu bar item: `focused`, `idle` or `none`, on a `light` or `dark` bar, at `1x` or `2x`, magnified without smoothing |

## The samples

Made-up values chosen to read well, for pictures of ctxscope:
`components` (every component in its states), `context`, `timeline`,
`popover` and `popover-empty`. The same pages over the synthetic session are
`context-synthetic`, `timeline-synthetic` and `timeline-window-synthetic`,
with the magnifiers open in `context-magnifier`, `timeline-hover` and
`timeline-magnifier`.

## A real session

```
swift run ctxscope-snapshots --session <id prefix> [--page context|timeline] --out /somewhere/else
```

Never into the repository: a render of a real session is transcript text in a
picture.
