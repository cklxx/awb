# Probes: task status read from artifacts

## Problem

Most board rows are self-reported, and a self-report is stale as soon as the agent stops
writing. One day of running eight agents on one board produced these failures:

- A merge script read "no CI status found" as a pass.
- The GitHub API returned a CI record two days old for the current PR.
- An evaluation loop recorded itself done while one of its shards had failed.
- A `pgrep` matched the wrong process and a running evaluation was reported dead; a hung process still counts as present.
- A dropped pod connection stalled every read that went through it for several minutes.
- A watcher script wrote four wrong readings to the board.
- The stale section (久未更新, now the "没有更新" lines of 异常) listed agents that were waiting on review or CI, and each listing had to be checked by hand.

The one row that stayed correct all day was the training row, which a script read from the
training log every two minutes. A probe makes that pattern part of awb.

## Contract

A task can carry a probe: a shell command that the board runs to learn the task's state.

```sh
awb task t7 wip "merge #671" "" "" --probe 'awb probe pr 671'
awb task t1 wip "train" "" de --probe 'awb probe log runs/x.log "step ([0-9]+)/([0-9]+)"'
```

The probe prints one line, `STATE text`, and exits 0. STATE is one of `todo`, `wip`,
`review`, `blocked`, `done` or `drop`. A reading is failed when the exit code is not 0, the
command exceeds its timeout, or the first word is not a state. A failed reading carries no
state. The command runs in the directory where `awb task` was issued.

Each reading is logged as one event:
`{t:"probe", id, ep0, ep, rc, st, text}`. `ep0` is when the probe started and `ep` is when
the result was logged.

## States

A probed task shows the state of its accepted reading, where the self-reported state would
otherwise be. When no reading is usable it shows `?` in red, as unknown. Unknown is not
done and not failed. It counts as not done in every progress bar. Beside the text, the
board shows how old the reading is (`12s前`). When the reading has expired it shows how
long nothing has been read (`读不到 16:40`), or `未读到` when no reading has been accepted.

## Freshness

The fold keeps one accepted reading per task. A parsed reading is accepted when its start
time `ep0` is no earlier than that of the accepted one. A reading that started earlier and
arrived later is discarded, and a failed reading changes nothing. The board shows the
accepted reading while `now - ep <= AWB_PROBE_FRESH` (default 600 s). After that the task
shows unknown, so the value of the last good read is never displayed indefinitely.
`done` and `drop` do not expire, because a merged or closed PR stays that way, and the probe
loop stops running the probe once one of them is accepted.

## Anchors

A probe answers from an external source, so the reading must be checked against an
independent one. `awb probe pr N` reads `gh pr view N`, then compares the API's
`headRefOid` with `git ls-remote origin refs/pull/N/head`. If the two differ, the probe
exits 1 and the reading is failed. This rejects a stale API replica and CI results that
belong to another commit. For a log, the anchor is the file's modification time. If the log
has not been written for `AWB_PROBE_SILENT` seconds (default 1800) and its last match is not
complete, the probe reports `blocked log silent Nm`. A process that exists but writes
nothing is therefore not counted as running.

The built-in probes:

| probe | output |
|---|---|
| `awb probe pr N` | `done merged <sha8>`; `drop closed unmerged`; `blocked CI red: <checks>`; `review CI pending k/n`; `review CI green, not merged` |
| `awb probe log PATH REGEX` | last matching line in the last 2000 lines. Two numeric groups n/total: `done n/total` when n ≥ total, else `wip n/total p%`. Otherwise the first group or the match: `wip <text>`. No match exits 1 |

Completion comes from the artifact: `done` means the PR is merged or the log reached its
total. The probe command finishing does not mean the task is done.

## Loop

`awb probe run` runs every `AWB_PROBE_POLL` seconds (default 30) under a lock, so only one
loop per board is active. `--once` runs one round. A round runs each probed task whose last
reading is at least `AWB_PROBE_EVERY` seconds old (default 120), skipping tasks whose
accepted state is `done` or `drop`. Each probe gets `AWB_PROBE_TIMEOUT` seconds (default
30). It runs in its own process group, and on timeout the whole group is killed, so a probe
that hangs on a dropped connection leaves no child behind. The round records rc 124 for it.
Probes run one after another, so one round takes at most the sum of their timeouts.

The brief view's 异常 leaves out the "没有更新" line of an agent that owns (`OWNER` of the
task) a probed task whose state is `wip` or `review` and fresh. That agent is waiting on
something the board can see. An agent whose probed task is unknown or blocked keeps the line.

## What stays self-reported

Tasks without a probe keep their self-reported state, and a probed task keeps its text,
parent and owner. Intent, plans, judgement calls and the `ask` state stay self-reported.
The same applies to agent status (running, blocked, finished) and milestones; for
milestones, `⊢` still separates what a check verified from what an agent reported. `awb
nudge` still reminds silent agents regardless of their probed tasks.

## Verification

| property | how | result |
|---|---|---|
| no false done; shown readings are fresh or unknown; the newest reading wins; a waiting owner is not stale; a finished task eventually shows done | TLA+ `model/tla/AwbProbe.tla`, TLC | `AwbProbeOld.cfg` (last arrival wins, failures keep the old value, no anchor, no stale exclusion) violates each invariant: NoFalseDone in 3 states, FreshOrUnknown in 5, NewestOnly in 6, WaitNotStale in 5. `AwbProbeFixed.cfg` (MaxT 4, K 3) passes with 1,432,203 states, 282,223 distinct, depth 12, including the liveness property DoneShows |
| the accepted reading started no earlier than any parsed reading, and is one of them; a failed reading changes nothing; `done` is shown only if the newest parsed reading says done; a non-terminal reading past the bound shows unknown; a waiting owner is not stale | Lean, `model/Probe.lean`, re-stated in `model/Accept.lean` | `awb check model --lean model model/Accept.lean`: build, sorry, types and axioms all ok; axioms used are `propext` and `Quot.sound` only |
| jq fold in `awb` = Lean `prun` | `awb _state` prints `probe ID STATE T0 EP` per task; `awbmodel fold` prints the same from the model; `awbmodel gen` emits probe events with older starts, rc 1 and 124, and invalid or null states | 200 random logs agree in `awb selftest`. Mutating the jq rc test, the start-time test or the state set makes a log differ within the first 50 seeds |
| board behaviour | `awb selftest`: state mapping, rc ≠ 0, timeout (and its child killed), older reading discarded, expiry, age, stale-section exclusion, `probe pr` red and anchor mismatch and merged, `probe log` progress, done, no match, silent | 20 mutants in a throwaway copy, one per check, each fail `awb selftest` at the check aimed at them; this code passes |

## Limits

- The fold, the display rule and the stale exclusion are proven in the model. The jq
  implementation is only tested against it. The shell loop, the process-group kill and the
  two built-in probes are covered by selftest only.
- The PR anchor rejects an API head that differs from the remote ref. It cannot detect an
  API and a remote that are stale in the same way.
- Only `pr` and `log` are built in. A JSON result-file probe, meaning a file that exists,
  parses and has a sane field, is not yet built in. A task can use any command that follows
  the contract meanwhile.
- `awb nudge` does not yet skip owners of waiting probed tasks, and neither does the full
  view's per-agent `无更新` marker. Only the brief view's 异常 does.
- A probe cannot be removed from a task; re-issue the task under a new id.
- Probes run serially, so one slow probe delays the rest of its round by up to its timeout.
