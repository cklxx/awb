---
name: awb-workbench
description: tmux milestone board for many agents (awb). Use when running several agents in tmux (claude / codex / any CLI) and watching only each agent's goal and milestone progress, not its output; when gating deliverables with awb check (including Lean 4); when messaging agents; or when the user mentions an agent board, workbench, milestone board, multi-agent progress, 看板, 工作台, or awb.
---

# awb — tmux agent workbench

One POSIX sh file (needs `tmux`, `jq`; Lean checks also need elan). Repo: https://github.com/cklxx/awb.
`.awb/events.jsonl` is the single source of truth (append-only); the board folds it into state
and redraws every second. Print this manual any time with `awb skill` (agents without a skill
mechanism, such as codex, use that). Install or update awb and this skill:

```sh
curl -fsSL https://raw.githubusercontent.com/cklxx/awb/main/install.sh | sh
```

## Main agent protocol

The user talks to one Claude, the main agent; the board is for watching. Nothing in Claude's
configuration changes (no hooks), and workers need not know awb. When you are that Claude,
follow this and do not ask the user to type commands:

1. Board: `awb up`. Inside tmux it opens right of your pane (reused if already open); outside
   tmux it makes a tmux session with the board and a work pane and prints the one command the
   user runs to watch it. Then `awb goal "<goal>"` (see Goal and metric).
2. Workers: for each parallel task, `awb tui -g <group> <id> <name>`. It waits until the
   worker's Claude is ready and prints `<id> session: <session name>`. If it prints "answer the
   folder-trust prompt", ask the user to confirm trust in that pane; neither awb nor you makes
   that decision for them.
3. Dispatch: `msg=$(awb send <id> "<task in one line>")`, then SendMessage(to: <session name>,
   message: <msg>, notify_when_idle: true). `awb send` only records the task and prints the
   message; nothing reaches the worker until you send it. The message carries a key
   `[awb <id>#<key>]` the reply must echo. One open task per worker; send the next after the
   reply. The worker's own `awb now` / `awb done` do not close it.
4. Results:
   - A reply starting with `[awb <id>#<key>]` → `awb reply <id> <key> "<result in one line>"`.
     Close tasks this way, not with `awb finish`: a task closed without a reply keeps no result,
     and `awb replay` counts it apart. A reply with another key is stale or duplicate.
   - An idle notice → `awb idle <id>`. The first time it prints an ask; SendMessage it (again
     with notify_when_idle). The second time it marks the task blocked: tell the user, since the
     worker's session is probably holding your message for its user's approval. Never mark a
     task done from an idle notice alone (`model/tla/AwbLoop.tla`: that marks undone work done).
   - The worker exited → `awb fail <id> "exited"`; `awb tui` with the same id restarts it; then
     send its lost task again with `awb send` (a new key: a late reply to the old one is stale).
   - After a restart or compaction, `awb peers` lists every agent with its session, status,
     open task key and silence; continue with `awb idle` for each open task.
5. Acceptance: a worker's claim is not a result. You choose the command and
   `awb check <id> -- <command>` runs it; after a rejected check the agent cannot become done
   until a later check passes. Keep acceptance files (tests, ACCEPT.lean) outside the worker's
   directory. Then `awb pr <id>`, and merge with `awb merge PR` (a retracted or conditional
   approve, an approve of an older head, or a check that never started is not a green light).
6. Read the board with `awb snapshot` (one JSON object: goal, metric, need, anomalies, agents,
   tasks, checks); `awb render` draws the same for a person.
7. Subagents you start with your Agent tool can be on the board too: `awb start <id> <name>`
   and `awb now` before starting, `awb done` when the result comes back.

The board reads each worker's session from Claude's registry: `▲ 待批准` means a permission
dialog (tell the user; awb never types into it), and 会话实况 lists self-reports the session
contradicts. An open board also nudges silent agents, and tells a Claude worker whose session
stopped with a tool call printed as text (`AWB_STUCK_RE`) to re-issue it.

Several boards: one `.awb` per project directory, or `AWB_DIR`. A worker's pane inherits its
board's `AWB_DIR`; a worker that experiments with awb sets its own `AWB_DIR` on every command.

If `awb-lark` is set up (`awb-lark where` prints the group), a board the user wants in the
Lark topic group is linked once with `awb-lark sync` in its directory; from then on it syncs
every minute while the board runs. Never link a scratch or test board.

## Goal and metric

The goal's first line is the title of the board and the Lark card, short; further lines say
what it is (definition, how it is measured, scope). Status never goes into the goal; it goes
into `awb news` or tasks. Each new measurement of the goal's number is
`awb metric <name> <value> <target> "<one-line note>"`: the board draws its history, the change
since the first reading and an estimated time to target from these events only.

- `--by <epoch>`: the work's end (a training run, a deadline); an estimate past it shows as
  "按当前趋势截止前达不到".
- `--at <epoch>`: the real time of an older reading, never an invented one.
- `--ref --step <step>`: a comparison run (an earlier baseline) under its own name, drawn by
  step beside the metric and never in its trend. One `--ref` reading marks the whole name.

`awb replay [STEP]` replays the log: the board's anomalies as episodes, then 核心指标 — tasks
sent and how each ended (reply, `finish` without a reply, lost, open), how long each 需要你
item stayed on the board, and worker restarts.

## Workers that are not Claude sessions

```sh
awb run -g build  a1 builder -- ./train.sh  # a command in a pane; exit 0 -> done, else failed
awb run -g review a2 critic  -- codex
awb down                                    # end this board's session (refused from an agent's pane)
```

Attach from another terminal: `tmux -S .awb/sock attach -t awb` (for a deep project path the
socket is `/tmp/awb-UID-HASH.sock`). A window with no room left gets a new window. Put the ID
in such a worker's prompt:

```
You are on the awb board as agent <ID>. Before each stage run `awb now <ID> "<stage>"`,
after it `awb done <ID>`; if stuck `awb block <ID> "<reason>"`, then `awb now` again when unstuck;
when everything is done `awb finish <ID> "<result in one line>"`. Milestones state results,
not process, one per stage. Full rules: `awb skill`.
```

## Commands

| command | does |
|---|---|
| `awb up` / `awb down` | the board (see protocol step 1) / end this board's session |
| `awb goal TEXT` | set the overall goal |
| `awb metric [--at E] [--step N] [--by E] [--ref] NAME VALUE TARGET [NOTE]` | one reading of a goal number |
| `awb task ID STATE [TEXT] [PARENT] [OWNER] [--probe CMD]` | task-tree node; STATE todo/wip/review/blocked/done/drop/ask; re-issue the ID to update; ask = needs a human decision; `--probe`: the state comes from CMD (`docs/probe.md`) |
| `awb news [--key KEY] TEXT` | one progress line; the board shows the last 3. Lines with one key are one fact, the latest shows (`val@15000`) |
| `awb tui [-g G] ID NAME [TASK]` | resident Claude worker (`AWB_TUI_CMD`, default claude-db if on PATH, else claude) |
| `awb run [-g G] ID NAME -- CMD...` | a command in a pane; a pane closed unexpectedly → ■ dead |
| `awb start ID NAME [KIND] [G]` | register a non-pane / remote agent |
| `awb now ID MILESTONE` / `awb done ID [TEXT]` | start / finish a milestone (timed) |
| `awb block ID REASON` | blocked; the next `awb now` clears it |
| `awb fail ID REASON` / `awb finish ID [NOTE]` | failed / close the last milestone and mark done |
| `awb send ID TASK` / `awb reply ID KEY [RESULT]` / `awb idle ID` | protocol steps 3 and 4 |
| `awb peers` | every agent: `ID PANE SESSION STATUS [#KEY] [silent MINm]` — the Claude session to SendMessage, busy/idle/waiting, its open task, silent ≥ `AWB_STALE` seconds. Sessions not started by awb: add `ID PANE` lines to `.awb/panes` |
| `awb tell ID MSG` | type a message into the agent's pane and press Enter (claude/codex; Claude queues it when busy). For Claude workers prefer SendMessage |
| `awb check ID -- CMD...` | acceptance gate: CMD exits 0 → milestone verified (`⊢`); else ✗ with the reason, log in `.awb/check-ID.log`, and the agent is told (`AWB_NOTIFY=0` turns that off) |
| `awb check ID --lean DIR [ACCEPT.lean]` | Lean 4 gate (see below) |
| `awb pr ID [gh args]` | push the current branch and open a PR; refused unless the agent's latest check passed |
| `awb merge PR [--watch]` | merge only when the newest verdict on the current head approves (a review, or a comment whose first line names the head sha and matches `AWB_APPROVE_RE`) and `AWB_MIN_CHECKS` checks named by `AWB_REQUIRE_CHECKS` ran green |
| `awb hold RES OWNER [NOTE]` / `awb release RES [OWNER]` / `awb holder RES` | one holder per shared resource (a GPU, a host); scripts that must not disturb it check `awb holder` first |
| `awb snapshot` / `awb render` / `awb replay [STEP]` | the board as JSON / drawn / over the log's history |
| `awb audit` | protocol violations from the Lean monitor (exit 1 if any) |
| `awb reset` | clear all events (keeps a `.bak` copy) |
| `awb skill` / `awb version` / `awb selftest` | this manual / version / end-to-end self-test |

Settings: `AWB_VIEW=brief|full` (default brief), `AWB_STALE` (seconds, default 600),
`AWB_INTERVAL` (refresh seconds, default 1). IDs match `[A-Za-z0-9_-]`; an id must be started
before other commands use it. States: ◔ running · ✓ done · ▲ blocked · ✗ failed · ■ dead.

## Lean 4 acceptance

1. ACCEPT.lean contains only top-level named `theorem`s that refer to the worker's definitions:
   ```lean
   import Demo
   theorem acc_double (n : Nat) : double n = 2 * n := double_eq n
   ```
   `example`, `lemma`, `namespace` or any unrecognised form fails the check (fail-closed).
2. Rejected: `sorry`, custom `axiom`s, `native_decide`, a weaker restatement. About 2s warm; no Mathlib needed.
3. The board's 验收 section shows `build → sorry → types → axioms` live, with the reason under a failed step.
4. Only Lean deliverables; a weak statement gives a weak check. The project needs a
   `lean-toolchain`; elan in `~/.elan/bin` is found too.

## Verification chain (Lean, TLA+)

- State fold: `model/AwbModel.lean` proves four invariants; the jq fold in awb is differentially
  tested against the compiled Lean model on random logs (200 per selftest).
- Audit: `awb audit` runs the proven Lean monitor (`audit_iff_clean`: no report ⇔ every event
  obeys the rules given its prefix). A `⊢` verified milestone and a PR must follow a passing
  check; no `done` while a check is rejected. Violations show on the board under 审计违规.
- The model is built in a clone (`./install.sh` runs `lake build` when Lean is present);
  without it, audit is unavailable and selftest skips the differential test.
- Concurrency: TLA+ specs in `model/tla/`, checked with TLC. `check` / `pr` are serialized per
  agent; a check verifies only the milestone it started on; concurrent `tell`s into one pane
  take a per-pane lock; `tell` re-reads the session registry before each keystroke and never
  types into a dialog already reported (`AwbWait.tla`).
- Limits: agents append events, so the audit catches a forged `verified` but not an agent that
  also forges the check events; jq and the model are equal by test, not by proof.

## Found a problem in awb itself: open a PR

Fix it and open a PR. Do not edit the installed copy in use and do not push to main:

```sh
gh repo clone cklxx/awb /tmp/awb-fix-<slug> -- -q      # without write access: gh repo fork cklxx/awb --clone
cd /tmp/awb-fix-<slug> && git switch -c fix/<slug>
# fix it and add a selftest() assertion that fails on the bug; sync model/AwbModel.lean if the fold changes
# and model/tla/ if a protocol changes (model/tla/tlc.sh checks every spec)
export AWB_DIR=$PWD/.awb                         # this board, never the one your pane belongs to
./awb start fix-<slug> fixer && ./awb now fix-<slug> "<the problem in one line>"
git commit -am "<English summary>"              # no attribution trailers
./awb check fix-<slug> -- ./awb selftest
./awb pr fix-<slug>                              # refused unless the check passed
```

PR descriptions describe the change only, with no "Generated with ..." lines. Do not change
`VERSION` in a PR. Releases: at most one per day, as one PR that only bumps `VERSION`, then the
matching `vX.Y.Z` tag; CI publishes the release.
