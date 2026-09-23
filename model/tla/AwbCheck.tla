---- MODULE AwbCheck ----
\* Concurrency of `awb check` and `awb pr` for one agent, against the agent's own `awb now`.
\* The event log is abstracted to what the fold and the Lean audit read from it:
\*   cur      - the agent's current milestone (0 = none), set by `now`, closed by `done`
\*   lastRun  - check run of the latest chk event; runOk - that run's step ended ok
\* Fixed = FALSE is awb 0.0.5; Fixed = TRUE adds a per-agent lock around check and pr, and a
\* check that passes only if the milestone it started on is still current.
EXTENDS Naturals

CONSTANTS Checkers, MaxNow, Fixed

VARIABLES cur, nows, pc, snap, lastRun, runOk, lock, prpc, bad
vars == <<cur, nows, pc, snap, lastRun, runOk, lock, prpc, bad>>

Init == /\ cur = 0 /\ nows = 0
        /\ pc = [c \in Checkers |-> "idle"] /\ snap = [c \in Checkers |-> 0]
        /\ lastRun = "none" /\ runOk = FALSE
        /\ lock = "free" /\ prpc = "idle" /\ bad = {}

Free(p)  == ~Fixed \/ lock = "free"
Take(p)  == lock' = IF Fixed THEN p ELSE lock
Release  == lock' = IF Fixed THEN "free" ELSE lock

\* the agent starts its next milestone at any time: `awb now`
AgentNow == /\ nows < MaxNow
            /\ nows' = nows + 1 /\ cur' = nows + 1
            /\ UNCHANGED <<pc, snap, lastRun, runOk, lock, prpc, bad>>

\* `awb check`: step events "run" then "ok"/"fail", then the verdict event
CheckStart(c) == /\ pc[c] = "idle" /\ cur # 0 /\ Free(c) /\ Take(c)
                 /\ pc' = [pc EXCEPT ![c] = "running"] /\ snap' = [snap EXCEPT ![c] = cur]
                 /\ lastRun' = c /\ runOk' = FALSE
                 /\ UNCHANGED <<cur, nows, prpc, bad>>

CheckStep(c) == /\ pc[c] = "running"
                /\ \E ok \in BOOLEAN :
                     /\ pc' = [pc EXCEPT ![c] = IF ok THEN "passed" ELSE "failed"]
                     /\ lastRun' = c /\ runOk' = ok
                /\ UNCHANGED <<cur, nows, snap, lock, prpc, bad>>

\* pass: append `done verified`, which closes whatever milestone is current.
\* The audit then flags it unless the latest run in the log is a passing one.
CheckPass(c) ==
  /\ pc[c] = "passed"
  /\ pc' = [pc EXCEPT ![c] = "end"]
  /\ IF Fixed /\ cur # snap[c]
       THEN /\ UNCHANGED <<cur, bad>>                          \* stale: rejected instead
       ELSE /\ cur' = 0
            /\ bad' = bad \cup (IF cur # snap[c] THEN {"verified-a-milestone-it-did-not-check"} ELSE {})
                          \cup (IF lastRun = c /\ runOk THEN {} ELSE {"audit-flags-an-honest-pass"})
  /\ Release
  /\ UNCHANGED <<nows, snap, lastRun, runOk, prpc>>

CheckFail(c) == /\ pc[c] = "failed" /\ pc' = [pc EXCEPT ![c] = "end"] /\ Release
                /\ UNCHANGED <<cur, nows, snap, lastRun, runOk, prpc, bad>>

\* `awb pr`: gate on the latest run, then `gh pr create` (seconds), then the pr event
PRGate   == /\ prpc = "idle" /\ Free("pr") /\ lastRun # "none" /\ runOk /\ Take("pr")
            /\ prpc' = "creating"
            /\ UNCHANGED <<cur, nows, pc, snap, lastRun, runOk, bad>>
PRCreate == /\ prpc = "creating" /\ prpc' = "end" /\ Release
            /\ bad' = bad \cup (IF runOk THEN {} ELSE {"pr-opened-after-a-failed-check"})
            /\ UNCHANGED <<cur, nows, pc, snap, lastRun, runOk>>

Next == \/ AgentNow
        \/ \E c \in Checkers : CheckStart(c) \/ CheckStep(c) \/ CheckPass(c) \/ CheckFail(c)
        \/ PRGate \/ PRCreate

Spec == Init /\ [][Next]_vars

NoBad == bad = {}
NoWrongMilestone  == "verified-a-milestone-it-did-not-check" \notin bad
NoFalseAuditFlag  == "audit-flags-an-honest-pass" \notin bad
NoPrAfterFail     == "pr-opened-after-a-failed-check" \notin bad
====
