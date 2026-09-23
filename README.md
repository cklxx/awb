<p align="center"><img src="docs/logo.svg" width="200" alt="awb"></p>

# awb

tmux agent workbench. A milestone board for many agents (claude, codex, any CLI), with
an acceptance gate that decides when a milestone counts as done.

The name is also the logo: `a` and `b` are the two lenses of a pair of glasses and `w` is
the `ω` mouth, as in (・ω・). It watches your agents.

![awb board](docs/board.png)

The board above (`AWB_VIEW=full`, demo data) shows the task tree, the acceptance runs with
each step, and per-group agents with their milestones; `⊢` marks a milestone that passed
`awb check`.

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
curl -fsSL https://raw.githubusercontent.com/cklxx/awb/main/install.sh | sh
awb selftest
```

This installs `awb` (needs sh, tmux, jq) to `~/.local/bin` and the agent skill to
`~/.claude/skills/awb-workbench`, from the latest release. Run `./install.sh` in a clone to
symlink both instead. Agents without a skill mechanism (codex, ...) read the same manual
with `awb skill`; `awb` itself points agents there.

## Chat-driven (Claude only)

```sh
awb hooks        # once per project (or --global): Claude Code hooks feed the board
awb board        # board beside the current tmux pane
claude           # just talk; ask it to start parallel workers and it runs awb tui / awb run
```

Hooks register the session (and tell the model its board ID), turn each prompt into the
current milestone, close it when the turn ends, and put every subagent the model starts
with its Agent tool on the board, finished with its result. No main agent and no reporting
by the model are needed. Several boards coexist: a session uses `$AWB_DIR`, else the nearest
`.awb` above its cwd, else reports nowhere.

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
awb pr a1                                           # open a PR for a1's branch, only after a pass
awb render                                          # one-shot render, works outside tmux
awb reset                                           # clear all events
awb down                                            # kill the session
```

Board knobs: `AWB_VIEW=brief|full` (default brief), `AWB_STALE=SECS` lists agents silent
that long (default 600), `AWB_INTERVAL` refresh seconds (default 1).

Keep acceptance files outside the agent's working directory so the agent cannot edit them.

Each check shows on the board under 验收 as it runs: `build → sorry → types → axioms` for
Lean (one `cmd` step otherwise), with a timer on the running step and the reason under a
failed one. ACCEPT.lean must use top-level named `theorem`s; `example`, `lemma`,
`namespace` or any unrecognised theorem syntax fails the check rather than being skipped.
A warm Lean check of `model/` takes about 2s.

Status: ◔ running · ✓ done · ▲ blocked · ✗ failed · ■ dead (pane gone).
`tmux -S .awb/sock attach -t awb` attaches from another terminal (for a deep project path the
socket is `/tmp/awb-UID-HASH.sock`, since unix socket paths are limited to about 104 bytes).

## Notify agents

```sh
awb tell a1 "rebase on main, then re-run the check"   # typed into the agent's TUI pane + Enter
awb peers                                             # ID PANE CLAUDE-SESSION STATUS
awb stale                                             # agents silent >= AWB_STALE seconds
awb nudge                                             # loop: remind silent agents every AWB_NUDGE_EVERY
```

- `tell` works for any TUI agent (claude, codex, ...) and uses a named tmux buffer, so your
  own paste buffer is untouched. Claude queues it if a turn is running.
- A rejected `awb check` tells the agent the reason automatically, unless the agent ran the
  check from its own pane (`AWB_NOTIFY=0` turns this off).
- For Claude agents, `peers` maps each agent to its Claude Code session name via
  `~/.claude/sessions`. A main agent that is itself a Claude session can then message them with
  its `SendMessage` tool, which goes over Claude's own per-session socket and reaches the agent
  even mid-turn. awb does not speak that socket protocol itself: it is internal, versioned and
  authenticated. MCP channels, the documented push route, are unavailable with a custom
  `ANTHROPIC_BASE_URL`.
- Agents started outside awb (existing sessions) are mapped in `.awb/panes`, one
  `ID PANE` per line; it overrides panes from start events.

## Contributing and releases

Changes land by PR. Fix on a branch, then gate and open the PR with awb itself:

```sh
awb check fix1 -- ./awb selftest     # the acceptance gate
awb pr fix1                          # pushes the branch; refuses without a passing check
```

CI does not test; it only publishes: pushing a tag `vX.Y.Z` that matches `VERSION` in `awb`
creates a GitHub release with `awb` attached.

## Verification chain

Every link from the event log to a merged PR is either proven in Lean or tested against the
proven model:

| link | how | where |
|---|---|---|
| status fold (events → agent state) | proven: duration frozen iff ended, no `done` while a check is rejected, only known states, non-negative durations | `model/AwbModel.lean` |
| jq fold in `awb` = Lean fold | differential test on random logs (`awb selftest`, 200 logs; 1000 run clean) | `awb state` vs `awbmodel fold` |
| protocol audit | proven: the one-pass monitor reports nothing iff every event obeys the rules given its prefix (`audit_iff_clean`); corollary: every PR in a clean log followed a passing check | `model/Audit.lean` |
| deliverables | `awb check` (tests, or Lean with kernel-checked theorems and standard axioms only) | `awb check` |
| merge | `awb pr` refuses without a passing check or with audit violations, and logs the PR for the audit | `awb pr` |

Audit rules, per agent: a verified milestone must follow a passing check (forged `verified`
events are caught), a PR must follow a passing check, and `done` must not be claimed while a
check is rejected. Violations show on the board under 审计违规 and via `awb audit`.

`model/Main.lean` compiles the proven fold and monitor into `awbmodel`, which `awb` finds at
`model/.lake/build/bin/awbmodel` (or `AWB_MODEL`); `./install.sh` in a clone builds it when
Lean is installed. Without it, `awb audit` is unavailable and selftest skips the
differential test. Proofs are checked with:

```sh
awb check model --lean model model/Accept.lean
```

Limits: events are appended by agents, so the audit flags a forged `verified` event but
cannot stop an agent that also forges the check events; the jq fold is tested against the
model, not proven.
