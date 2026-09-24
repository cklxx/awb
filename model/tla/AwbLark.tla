---- MODULE AwbLark ----
\* awb-lark syncs of one board: the board's watch loop starts a sync per tick (w1, then w2)
\* and a user may run `awb-lark sync` by hand (m). A sync takes the board lock, reads the
\* board and the mapping, then either creates the topic (send, then write the mapping) or
\* patches the card with what it read. The board changes meanwhile; a sync may die at any
\* step, keeping its lock.
\* Fixed = FALSE is awb 0.0.7's awb-lark: the lock is broken by age alone (a slow sync
\*   counts as dead), ticks overlap, and a send has no idempotency key.
\* Fixed = TRUE: the lock is broken only when its holder is dead, the watch loop starts a
\*   tick only after the previous one ended (it kills a hung one), and the topic is created
\*   with an idempotency key, so a send repeated after a crash returns the same topic.
EXTENDS Naturals

CONSTANTS Fixed, MaxVer, MaxCrash

Procs == {"w1", "w2", "m"}
VARIABLES ver, card, topics, sent, mapped, lock, pc, snap, saw, alive, crashes, back
vars == <<ver, card, topics, sent, mapped, lock, pc, snap, saw, alive, crashes, back>>

Init == /\ ver = 0 /\ card = 0 /\ topics = 0 /\ sent = FALSE /\ mapped = FALSE
        /\ lock = "none" /\ pc = [p \in Procs |-> "idle"] /\ snap = [p \in Procs |-> 0]
        /\ saw = [p \in Procs |-> FALSE] /\ alive = [p \in Procs |-> TRUE]
        /\ crashes = 0 /\ back = FALSE

Change == /\ ver < MaxVer /\ ver' = ver + 1
          /\ UNCHANGED <<card, topics, sent, mapped, lock, pc, snap, saw, alive, crashes, back>>

\* w2 is the tick after w1; Fixed: only once w1 has ended or was killed
Start(p) ==
  /\ pc[p] = "idle"
  /\ p = "w2" => (pc["w1"] /= "idle" /\ (Fixed => (pc["w1"] = "done" \/ ~alive["w1"])))
  /\ IF lock = "none" \/ (IF Fixed THEN ~alive[lock] ELSE TRUE)
       THEN lock' = p /\ pc' = [pc EXCEPT ![p] = "read"]
       ELSE pc' = [pc EXCEPT ![p] = "done"] /\ UNCHANGED lock
  /\ UNCHANGED <<ver, card, topics, sent, mapped, snap, saw, alive, crashes, back>>

Read(p) == /\ pc[p] = "read" /\ alive[p]
           /\ snap' = [snap EXCEPT ![p] = ver] /\ saw' = [saw EXCEPT ![p] = mapped]
           /\ pc' = [pc EXCEPT ![p] = IF mapped THEN "patch" ELSE "send"]
           /\ UNCHANGED <<ver, card, topics, sent, mapped, lock, alive, crashes, back>>

Send(p) == /\ pc[p] = "send" /\ alive[p]
           /\ topics' = IF Fixed /\ sent THEN topics ELSE topics + 1
           /\ sent' = TRUE
           /\ card' = IF card > snap[p] THEN card ELSE snap[p]
           /\ pc' = [pc EXCEPT ![p] = "map"]
           /\ UNCHANGED <<ver, mapped, lock, snap, saw, alive, crashes, back>>

Map(p) == /\ pc[p] = "map" /\ alive[p] /\ mapped' = TRUE
          /\ pc' = [pc EXCEPT ![p] = "release"]
          /\ UNCHANGED <<ver, card, topics, sent, lock, snap, saw, alive, crashes, back>>

Patch(p) == /\ pc[p] = "patch" /\ alive[p]
            /\ back' = (back \/ snap[p] < card) /\ card' = snap[p]
            /\ pc' = [pc EXCEPT ![p] = "release"]
            /\ UNCHANGED <<ver, topics, sent, mapped, lock, snap, saw, alive, crashes>>

Release(p) == /\ pc[p] = "release" /\ alive[p]
              /\ lock' = IF lock = p THEN "none" ELSE lock
              /\ pc' = [pc EXCEPT ![p] = "done"]
              /\ UNCHANGED <<ver, card, topics, sent, mapped, snap, saw, alive, crashes, back>>

\* killed (by the user, by the machine, or by the watch loop because it hung)
Crash(p) == /\ alive[p] /\ pc[p] \in {"read", "send", "map", "patch", "release"}
            /\ crashes < MaxCrash /\ crashes' = crashes + 1
            /\ alive' = [alive EXCEPT ![p] = FALSE]
            /\ UNCHANGED <<ver, card, topics, sent, mapped, lock, pc, snap, saw, back>>

Next == Change \/ \E p \in Procs : Start(p) \/ Read(p) \/ Send(p) \/ Map(p) \/ Patch(p)
                                 \/ Release(p) \/ Crash(p)
Spec == Init /\ [][Next]_vars

\* one board, one topic
OneTopic == topics <= 1
\* the card never goes back to an older state of the board
NoRegress == ~back
====
