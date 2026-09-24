---- MODULE AwbTell ----
\* Concurrent `awb tell` into one pane (auto-notify on a rejected check, nudge, the main
\* agent): load a tmux buffer, paste it (-d deletes it), press Enter.
\* Fixed = FALSE is awb 0.0.5 (one shared buffer name, no lock); Fixed = TRUE uses a buffer
\* per call and a per-pane lock around load..Enter.
\* A teller that finished runs its EXIT trap, which removes the locks it still lists.
\* ExitKeepsList = TRUE is awb 0.0.7: unlock did not drop the lock from that list, so the
\* trap removed a lock another teller had taken since.
EXTENDS Naturals, Sequences

CONSTANTS Tellers, Fixed, ExitKeepsList

VARIABLES pc, bufs, input, submitted, lock, lost
vars == <<pc, bufs, input, submitted, lock, lost>>

Buf(t) == IF Fixed THEN t ELSE "shared"
Names  == Tellers \cup {"shared"}

Init == /\ pc = [t \in Tellers |-> "load"] /\ bufs = [b \in Names |-> "empty"]
        /\ input = <<>> /\ submitted = <<>> /\ lock = "free" /\ lost = {}

Load(t)  == /\ pc[t] = "load" /\ (~Fixed \/ lock = "free")
            /\ lock' = IF Fixed THEN t ELSE lock
            /\ bufs' = [bufs EXCEPT ![Buf(t)] = t]
            /\ pc' = [pc EXCEPT ![t] = "paste"]
            /\ UNCHANGED <<input, submitted, lost>>
Paste(t) == /\ pc[t] = "paste"
            /\ IF bufs[Buf(t)] = "empty"
                 THEN /\ lost' = lost \cup {t} /\ UNCHANGED input      \* "no buffer"
                 ELSE /\ input' = Append(input, bufs[Buf(t)]) /\ UNCHANGED lost
            /\ bufs' = [bufs EXCEPT ![Buf(t)] = "empty"]
            /\ pc' = [pc EXCEPT ![t] = "enter"]
            /\ UNCHANGED <<submitted, lock>>
Enter(t) == /\ pc[t] = "enter"
            /\ submitted' = IF input = <<>> THEN submitted ELSE Append(submitted, input)
            /\ input' = <<>>
            /\ pc' = [pc EXCEPT ![t] = "exit"]
            /\ lock' = IF Fixed THEN "free" ELSE lock
            /\ UNCHANGED <<bufs, lost>>
\* the EXIT trap: with the stale list it frees the lock whoever holds it now
Exit(t) == /\ pc[t] = "exit"
           /\ pc' = [pc EXCEPT ![t] = "end"]
           /\ lock' = IF Fixed /\ ExitKeepsList THEN "free" ELSE lock
           /\ UNCHANGED <<bufs, input, submitted, lost>>

Next == \E t \in Tellers : Load(t) \/ Paste(t) \/ Enter(t) \/ Exit(t)
Spec == Init /\ [][Next]_vars

\* every submitted prompt is exactly one message, and no message is lost or sent twice
OneMessagePerPrompt == \A i \in 1..Len(submitted) : Len(submitted[i]) = 1
NothingLost         == lost = {}
EachOwnMessage      == \A i, j \in 1..Len(submitted) : i # j => submitted[i] # submitted[j]
====
