# awb

tmux agent workbench. A milestone board for many agents (claude, codex, any CLI), with
an acceptance gate that decides when a milestone counts as done.

## Model

- `.awb/events.jsonl` is the single source of truth: append-only events
  (goal/start/now/done/status/task/news).
- The board pane folds the events every second and redraws on change. It shows the goal,
  each agent's current and finished milestones, durations and idle time, never process output.
- Agents report with the same `awb` CLI. The main agent changes content by appending
  events and changes presentation by editing `awb` itself.
- An agent's own `done` is a claim. `awb check` runs a check the main agent chose; only a
  passing check marks the milestone verified (`⊢`), and a rejected check blocks `done`
  until a later check passes.

## Install

```sh
ln -sf "$PWD/awb" ~/.local/bin/awb      # needs sh, tmux, jq
awb selftest
```

Lean 4 is optional: only `awb check --lean` and `model/` need it. Install it with
[elan](https://github.com/leanprover/elan):

```sh
curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
```

Each Lean project pins its version in `lean-toolchain` (`model/` uses v4.34.0); elan
fetches it on the first `lake build`. `awb check --lean` looks for `lake` in `~/.elan/bin`
as well as on `PATH`.

## Use

```sh
awb up                                   # tmux session: board on top, work area below
awb goal "ship v1"
awb run -g build a1 builder -- claude    # pane per agent; exit 0 -> done, else failed
awb run -g docs  a2 writer  -- codex
awb tui -g main assistant helper "task"  # resident interactive claude TUI; command from
                                         # AWB_TUI_CMD (default: claude-db if on PATH, else claude)

# reported by the agent (or the main agent on its behalf)
awb now   a1 "event log"
awb done  a1
awb block a3 "waiting for review"; awb unblock a3
awb finish a1
awb fail  a2 "tests red"

# task tree and progress feed (brief view shows them)
awb task t1 wip "build API"                  # STATE todo|wip|review|blocked|done|drop|ask
awb task t2 todo "auth" t1 a1                # [TEXT] [PARENT] [OWNER]; re-issue to update
awb news "API merged"                        # board shows the last 5

# acceptance
awb check a1 -- pytest -q ~/accept/test_a1.py       # any command, exit 0 = accepted
awb check a1 --lean proj ~/accept/ACCEPT.lean       # Lean 4: build, no sorry, theorems typecheck
                                                    # with standard axioms only
awb render                                          # one-shot render, works outside tmux
awb reset                                           # clear all events
awb down                                            # kill the session
```

Board knobs: `AWB_VIEW=brief|full` (default brief), `AWB_STALE=SECS` lists agents silent
that long (default 600), `AWB_INTERVAL` refresh seconds (default 1).

Keep acceptance files outside the agent's working directory so the agent cannot edit them.

Status: ◔ running · ✓ done · ▲ blocked · ✗ failed · ■ dead (pane gone).
`tmux -S .awb/sock attach -t awb` attaches from another terminal.

## Formal model

`model/AwbModel.lean` models the per-agent fold. It reproduces five bugs of the earlier
fold as checked counterexamples (a rejected check overwritten by `done`, re-run id stuck
in `done`, `now` after `fail` stuck in `failed`, unknown status freezing duration, negative
durations) and proves that the current fold keeps these invariants for every event sequence:

- duration is frozen iff the agent is done or failed;
- no `done` while a rejected check is pending;
- only known states;
- durations are non-negative.

```sh
awb check model --lean model model/Accept.lean
```

The jq fold in `awb` is kept in step with `step` in the model by hand; `awb selftest`
covers the same regressions.
