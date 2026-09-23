---- MODULE AwbProbe ----
\* Status from probes: the board runs a task's probe command and folds each reading into the
\* status it shows. One task, one owner agent.
\* truth: the artifact's real state, monotone wait -> done.
\* A reading is issued at t0 and arrives later, in any order. It is good (the truth at t0, anchor
\* matches), failed (rc != 0, timeout, unparseable output), or foreign: its anchor does not match
\* (a stale API replica, another commit's CI run) and it carries any value.
\* Fixed = FALSE: last arrival wins, a failure keeps the last value forever, no anchor check,
\*   and the stale section lists every silent owner.
\* Fixed = TRUE: accept a reading iff it parsed, its anchor matches and its t0 >= the accepted
\*   one's; show unknown once an accepted wait reading is older than Fresh (done is terminal: the
\*   loop stops probing it and it does not expire); an owner whose task shows a fresh wait is not
\*   stale.
EXTENDS Integers, FiniteSets

CONSTANTS Fixed, MaxT, Fresh, Silent, K

Vals == {"wait", "done"}
None == [t0 |-> 0, ep |-> 0, st |-> "none"]

VARIABLES truth, now, pend, acc, hiT0, quiet
vars == <<truth, now, pend, acc, hiT0, quiet>>

\* pend: readings in flight; acc: the accepted reading; hiT0: newest t0 of any acceptable reading
\* that has arrived (-1: none); quiet: time since the owner last reported by hand
Init == /\ truth = "wait" /\ now = 0 /\ pend = {} /\ acc = None /\ hiT0 = -1 /\ quiet = 0

Tick == /\ now < MaxT /\ now' = now + 1
        /\ quiet' = IF quiet < Silent THEN quiet + 1 ELSE Silent
        /\ UNCHANGED <<truth, pend, acc, hiT0>>
Finish == /\ truth = "wait" /\ truth' = "done" /\ UNCHANGED <<now, pend, acc, hiT0, quiet>>
Report == /\ quiet' = 0 /\ UNCHANGED <<truth, now, pend, acc, hiT0>>

Issue(r) == /\ Cardinality(pend) < K /\ r \notin pend /\ pend' = pend \cup {r}
            /\ UNCHANGED <<truth, now, acc, hiT0, quiet>>
IssueGood == Issue([t0 |-> now, v |-> truth, ok |-> TRUE])
IssueFail == Issue([t0 |-> now, v |-> "fail", ok |-> TRUE])
IssueForeign == \E v \in Vals : Issue([t0 |-> now, v |-> v, ok |-> FALSE])

Acceptable(r) == r.v # "fail" /\ r.ok
Take(r) == [t0 |-> r.t0, ep |-> now, st |-> r.v]
\* every reading arrives eventually (the probe loop bounds each run with a timeout)
ArriveR(r) ==
  /\ r \in pend
  /\ pend' = pend \ {r}
  /\ hiT0' = IF Acceptable(r) /\ r.t0 > hiT0 THEN r.t0 ELSE hiT0
  /\ acc' = IF Fixed
              THEN IF Acceptable(r) /\ (acc.st = "none" \/ r.t0 >= acc.t0) THEN Take(r) ELSE acc
              ELSE IF r.v # "fail" THEN Take(r) ELSE acc
  /\ UNCHANGED <<truth, now, quiet>>
Readings == [t0 : 0..MaxT, v : Vals \cup {"fail"}, ok : BOOLEAN]
Arrive == \E r \in pend : ArriveR(r)

Disp == IF acc.st = "none" \/ (Fixed /\ acc.st # "done" /\ now - acc.ep > Fresh) THEN "unknown" ELSE acc.st
InStale == quiet >= Silent /\ (Fixed => Disp # "wait")

Next == Tick \/ Finish \/ Report \/ IssueGood \/ IssueFail \/ IssueForeign \/ Arrive
Spec == Init /\ [][Next]_vars /\ (\A r \in Readings : WF_vars(ArriveR(r)))
        /\ SF_vars(IssueGood) /\ WF_vars(Finish)

\* (a) done is shown only when the artifact is done
NoFalseDone == Disp = "done" => truth = "done"
\* (a) a reading is shown only while fresh; after that the status is unknown
FreshOrUnknown == Disp \notin {"unknown", "done"} => now - acc.ep <= Fresh
\* (b) no acceptable reading newer (by t0) than the shown one has been ignored
NewestOnly == acc.st # "none" => acc.t0 >= hiT0
\* (c) an owner whose task shows a wait is not listed as stale
WaitNotStale == Disp = "wait" => ~InStale
\* liveness: once the artifact is done and good readings keep being issued, done is shown
DoneShows == truth = "done" ~> Disp = "done"
====
