---
name: awb-workbench
description: tmux milestone board for many agents (awb). Use when running several agents in tmux (claude / codex / any CLI) and watching only each agent's goal and milestone progress, not its output; when gating deliverables with awb check (including Lean 4); when messaging agents; or when the user mentions an agent board, workbench, milestone board, multi-agent progress, 看板, 工作台, or awb.
---

# awb — tmux agent workbench

One POSIX sh file (needs `tmux`, `jq`; Lean checks also need elan). Repo: https://github.com/cklxx/awb.
`.awb/events.jsonl` is the single source of truth (append-only); the board folds it into state
and redraws every second. Print this manual any time with `awb skill` (agents without a skill
mechanism, such as codex, use that).

Install or update awb and this skill:

```sh
curl -fsSL https://raw.githubusercontent.com/cklxx/awb/main/install.sh | sh
```

## Chat-driven use: main agent + awb + session socket (recommended, Claude only is enough)

The user talks to one Claude, which is the main agent; the board is for watching. Nothing in
Claude's configuration changes (no hooks), and workers need not know awb.

When you are the Claude the user talks to, follow this protocol and do not ask the user to
type commands:

1. Board: `awb board` (opens right of your tmux pane; outside tmux, ask the user to run
   `awb watch` in another terminal), then `awb goal "<goal>"`. The goal holds only the goal.
   Every new measurement of the goal's number goes in `awb metric <name> <value> <target>
   "<one-line note>"`, never into the goal text: the board draws the metric's history, the
   change since the first reading and an estimated time to target from these events only.
2. Workers: for each parallel task, `awb tui -g <group> <id> <name>`. It waits until the
   worker's Claude is ready and prints `<id> session: <session name>`. If it prints "answer the
   folder-trust prompt", ask the user to confirm trust in that pane; neither awb nor you makes
   that decision for them.
3. Dispatch: `msg=$(awb send <id> "<task in one line>")`, then SendMessage(to: <session name>,
   message: <msg>, notify_when_idle: true). The message carries a key `[awb <id>#<key>]` the
   worker's reply must echo. awb allows one open task per worker; send the next one after the
   reply. The message travels over Claude's own session socket and arrives even mid-turn.
4. Results:
   - A reply starting with `[awb <id>#<key>]` → `awb reply <id> <key> "<result in one line>"`.
     A reply with another key is stale or duplicate; awb ignores it.
   - An idle notice → `awb idle <id>`. The first time it prints an ask; SendMessage it (again
     with notify_when_idle). The second time it marks the task blocked: tell the user, since the
     worker's session is probably holding your message for its user's approval.
   - The worker exited → `awb fail <id> "exited"`.
   - Gate deliverables with `awb check <id> -- <command>`, then `awb pr <id>`.
   - After a restart or compaction, `awb pending` lists open tasks with their keys and the
     workers' session status; continue with `awb idle` for each.
   Never mark a task done from an idle notice alone: TLC found that this marks undone work done
   (`model/tla/AwbLoop.tla`).
5. Subagents you start with your Agent tool can be on the board too: `awb start <id> <name>`
   and `awb now` before starting, `awb done` when the result comes back.

If `awb-lark` is set up (`awb-lark where` prints the group), the board's progress also appears
as one topic in the user's Lark topic group, synced every minute while the board runs; no
action is needed from you beyond keeping the board's events accurate.

`awb peers` shows each agent's Claude session name and busy/idle/waiting. The board reads the
same registry: `▲ 待批准` means the worker is on a permission dialog (tell the user; awb never
types into it), and 会话实况 lists self-reports the session contradicts. `awb stale` prints
`ID MINUTES waiting` for dialog-blocked workers. Several boards: one `.awb` per
project directory, or set `AWB_DIR`.

## Manual layout

```sh
awb up                                      # tmux session: board on top, work area below
awb goal "overall goal"
awb run -g build  a1 builder -- claude      # one-shot command in a pane; -g groups; exit 0 -> done, else failed
awb run -g review a2 critic  -- codex
awb tui -g main helper helper "first task"  # resident interactive Claude worker
awb down
```

Attach from another terminal: `tmux -S .awb/sock attach -t awb` (for a deep project path the
socket is `/tmp/awb-UID-HASH.sock`).

## Commands

| command | does |
|---|---|
| `awb goal TEXT` | set the overall goal |
| `awb task ID STATE [TEXT] [PARENT] [OWNER]` | task-tree node; STATE: todo/wip/review/blocked/done/drop/ask; re-issue the ID to update; ask = needs a human decision |
| `awb news TEXT` | one progress line; the board shows the last 5 |
| `awb run [-g G] ID NAME -- CMD...` | run a command in a pane; pane closed unexpectedly → ■ dead |
| `awb tui [-g G] ID NAME [TASK]` | resident Claude worker (command from `AWB_TUI_CMD`, default claude-db if on PATH, else claude); prints the session name when ready |
| `awb start ID NAME [KIND] [G]` | register a non-pane / remote agent |
| `awb now ID MILESTONE` / `awb done ID [TEXT]` | start / finish a milestone (timed) |
| `awb block ID REASON` / `awb unblock ID` | blocked / back to running |
| `awb fail ID REASON` / `awb finish ID [NOTE]` | failed / close the last milestone and mark done |
| `awb check ID -- CMD...` | acceptance gate: CMD exits 0 → milestone verified (`⊢`); else the agent turns ✗ with the reason on the board, log in `.awb/check-ID.log` |
| `awb check ID --lean DIR [ACCEPT.lean]` | Lean 4 gate: `lake build`, no sorry/admit in sources, ACCEPT.lean theorems typecheck against the build with standard axioms only |
| `awb send ID TASK` / `awb reply ID KEY [RESULT]` | open a keyed task and print the message to send / close it when the reply echoes the key |
| `awb idle ID` / `awb pending` | on an idle notice: print an ask once, then mark blocked / open tasks with keys and worker status |
| `awb pr ID [gh args]` | push the current branch and open a PR; refused unless the agent's latest check passed; the body lists milestones and check steps |
| `awb tell ID MSG` | type a message into the agent's TUI pane and press Enter (claude/codex; Claude queues it when busy) |
| `awb peers` | each agent's Claude session name and busy/idle |
| `awb stale` / `awb nudge` | list agents silent ≥ `AWB_STALE` seconds / remind them in a loop |
| `awb audit` / `awb state` | protocol violations from the Lean monitor (exit 1 if any) / per-agent state from the jq fold |
| `awb board` | board beside the current tmux pane, which becomes the split origin for tui/run |
| `awb render` / `awb reset` | one-shot render (works outside tmux) / clear all events |
| `awb skill` / `awb version` / `awb selftest` | this manual / version / end-to-end self-test |

Board settings: `AWB_VIEW=brief|full` (default brief), `AWB_STALE` (seconds, default 600),
`AWB_INTERVAL` (refresh seconds, default 1). IDs match `[A-Za-z0-9_-]`.
States: ◔ running · ✓ done · ▲ blocked · ✗ failed · ■ dead; group headers `◆ group`.

## Main agent protocol

1. State the goal with `awb goal`; start workers per role with `awb run -g` / `awb tui`.
2. A worker does not know its ID: put it in the prompt and ask for `awb now` / `awb done` at
   each stage (template below).
3. Read progress with `awb render` or `.awb/events.jsonl`.
4. An agent's own `done` is only a claim. You choose the acceptance command and `awb check`
   runs it; after a rejected check the agent cannot become done until a later check passes.
5. Keep acceptance files (tests, ACCEPT.lean) outside the worker's directory so it cannot edit them.

Worker prompt template:

```
You are on the awb board as agent <ID>. Before each stage run `awb now <ID> "<stage>"`,
after it `awb done <ID>`; if stuck `awb block <ID> "<reason>"`, then `awb unblock <ID>`;
when everything is done `awb finish <ID> "<result in one line>"`. Milestones state results,
not process, one per stage. Full rules: `awb skill`.
```

## Lean 4 acceptance

1. ACCEPT.lean contains only top-level named `theorem`s that refer to the worker's definitions:
   ```lean
   import Demo
   theorem acc_double (n : Nat) : double n = 2 * n := double_eq n
   ```
   `example`, `lemma`, `namespace` or any unrecognised form fails the check (fail-closed).
2. Rejected: `sorry`, custom `axiom`s, `native_decide`, a weaker restatement. About 2s warm; no Mathlib needed.
3. The board's 验收 section shows `build → sorry → types → axioms` live, with the reason under a failed step.
4. Limits: only Lean deliverables; a weak statement gives a weak check. Other languages:
   `awb check ID -- <test command>`.
5. The project needs a `lean-toolchain`; elan in `~/.elan/bin` is found too.

## Verification chain (Lean, TLA+)

- State fold: `model/AwbModel.lean` proves four invariants; the jq fold in awb is differentially
  tested against the compiled Lean model on random logs (200 per selftest).
- Audit: `awb audit` runs the proven Lean monitor (`audit_iff_clean`: no report ⇔ every event
  obeys the rules given its prefix). Rules: a `⊢` verified milestone must follow a passing
  check (catches forgery); a PR must follow a passing check; no `done` while a check is
  rejected. Violations show on the board under 审计违规.
- `awb pr` refuses on a failed check or audit violations and logs the PR for the audit.
- The model is built in a clone (`./install.sh` runs `lake build` when Lean is present);
  without it, audit is unavailable and selftest skips the differential test.
- Concurrency: TLA+ specs in `model/tla/`, checked with TLC. `check` / `pr` are serialized per
  agent; a check verifies only the milestone it started on (if the agent ran `awb now`
  meanwhile, the check is rejected as stale); concurrent `tell`s into one pane take a per-pane
  lock and separate buffers. `tell` re-reads the session registry before each keystroke and
  never types into a dialog already reported (`AwbWait.tla`); a dialog opening between the
  read and the key is not preventable, so message Claude workers with SendMessage.
- Limits: agents append events, so the audit catches a forged `verified` but not an agent that
  also forges the check events; jq and the model are equal by test, not by proof.

## Messaging agents

- A rejected check `tell`s the agent the reason and log path (not when the agent ran the check
  in its own pane; `AWB_NOTIFY=0` turns it off).
- Existing sessions not started by awb: add `ID PANE` lines to `.awb/panes`; tell / peers /
  nudge read it.
- When the main agent is Claude: find the session name with `awb peers` and use SendMessage,
  which goes over Claude's own session socket, arrives mid-turn, and can subscribe to the idle
  notice with `notify_when_idle`.

## Found a problem in awb itself: open a PR

When you hit a bug or gap in awb while using it, fix it and open a PR. Do not edit the
installed copy in use and do not push to main:

```sh
gh repo clone cklxx/awb /tmp/awb-fix-<slug> -- -q      # without write access: gh repo fork cklxx/awb --clone
cd /tmp/awb-fix-<slug> && git switch -c fix/<slug>
# fix it and add a selftest() assertion that fails on the bug; sync model/AwbModel.lean if the fold changes
export AWB_DIR=$PWD/.awb
./awb start fix-<slug> fixer && ./awb now fix-<slug> "<the problem in one line>"
git commit -am "<English summary>"              # no attribution trailers
./awb check fix-<slug> -- ./awb selftest
./awb pr fix-<slug>                              # refused unless the check passed
```

PR descriptions describe the change only, with no "Generated with ..." lines. Do not change
`VERSION` in a PR.

Releases: at most one per day. PRs accumulate on main; a release is one PR that only bumps
`VERSION`, then push the matching `vX.Y.Z` tag and CI publishes the release (CI only releases).
