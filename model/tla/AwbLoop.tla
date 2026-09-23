---- MODULE AwbLoop ----
\* The main agent's dispatch/report loop with one Claude worker over the session socket
\* (SendMessage + notify_when_idle), as the skill describes it.
\* Fixed = FALSE: the 0.0.6 protocol. `awb now` per dispatch (the board keeps one current
\*   milestone), and `awb done` on the worker's reply or on the idle notice.
\* Fixed = TRUE: each dispatch carries a key the reply must echo; one open task per worker;
\*   a reply closes only the task with its key; an idle notice never closes a task, it makes
\*   the main ask once, and a second silent idle marks the task blocked (needs the user).
\* CanHold: the worker's session may hold incoming messages for its user's approval.
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Tasks, Fixed, CanHold

VARIABLES todo, inbox, held, wdone, toMain, sub, notice, cur, open, asked, closed, blocked
vars == <<todo, inbox, held, wdone, toMain, sub, notice, cur, open, asked, closed, blocked>>

Init == /\ todo = Tasks /\ inbox = <<>> /\ held = FALSE /\ wdone = {} /\ toMain = <<>>
        /\ sub = FALSE /\ notice = FALSE /\ cur = "none" /\ open = {} /\ asked = {}
        /\ closed = {} /\ blocked = {}

\* deliver a message to the worker, or (CanHold) hold it and every later one
Deliver(m) == IF held \/ (CanHold /\ m = "hold")
                THEN held' = TRUE /\ UNCHANGED inbox
                ELSE inbox' = Append(inbox, m) /\ UNCHANGED held

Dispatch(t) ==
  /\ t \in todo /\ (Fixed => open = {})
  /\ todo' = todo \ {t}
  /\ cur' = t /\ open' = open \cup {t}          \* awb now: Old overwrites the current milestone
  /\ \E m \in {t} \cup (IF CanHold THEN {"hold"} ELSE {}) : Deliver(m)
  /\ sub' = TRUE
  /\ UNCHANGED <<wdone, toMain, notice, asked, closed, blocked>>

\* the worker does the next message: a task, or an "ask" to report the last task
Work == /\ inbox # <<>>
        /\ LET m == Head(inbox) IN
             /\ wdone' = IF m \in Tasks THEN wdone \cup {m} ELSE wdone
             /\ toMain' = IF m \in Tasks THEN Append(toMain, m)
                          ELSE IF m[2] \in wdone THEN Append(toMain, m[2]) ELSE toMain
        /\ inbox' = Tail(inbox)
        /\ UNCHANGED <<todo, held, sub, notice, cur, open, asked, closed, blocked>>

\* nothing left to do (or everything held): one idle notice to a subscribed main
Idle == /\ inbox = <<>> /\ sub /\ ~notice
        /\ notice' = TRUE /\ sub' = FALSE
        /\ UNCHANGED <<todo, inbox, held, wdone, toMain, cur, open, asked, closed, blocked>>

OnReply == /\ toMain # <<>>
           /\ LET t == Head(toMain) IN
                IF Fixed
                  THEN IF t \in open
                         THEN closed' = closed \cup {t} /\ open' = open \ {t}
                         ELSE UNCHANGED <<closed, open>>              \* stale or duplicate
                  ELSE /\ closed' = IF cur = "none" THEN closed ELSE closed \cup {cur}
                       /\ open' = open \ {cur}
           /\ cur' = IF Fixed THEN cur ELSE "none"
           /\ toMain' = Tail(toMain)
           /\ UNCHANGED <<todo, inbox, held, wdone, sub, notice, asked, blocked>>

OnIdle == /\ notice /\ notice' = FALSE /\ toMain = <<>>          \* replies are read first
          /\ IF Fixed
               THEN IF open = {} THEN UNCHANGED <<inbox, held, sub, asked, open, blocked>>
                    ELSE LET t == CHOOSE x \in open : TRUE IN
                      IF t \notin asked
                        THEN /\ asked' = asked \cup {t} /\ sub' = TRUE
                             /\ Deliver(<<"ask", t>>)
                             /\ UNCHANGED <<open, blocked>>
                        ELSE /\ blocked' = blocked \cup {t} /\ open' = open \ {t}
                             /\ UNCHANGED <<inbox, held, sub, asked>>
               ELSE /\ closed' = IF cur = "none" THEN closed ELSE closed \cup {cur}
                    /\ open' = open \ {cur}
                    /\ UNCHANGED <<inbox, held, sub, asked, blocked>>
          /\ cur' = IF Fixed THEN cur ELSE "none"
          /\ IF Fixed THEN UNCHANGED closed ELSE TRUE
          /\ UNCHANGED <<todo, wdone, toMain>>

Next == (\E t \in Tasks : Dispatch(t)) \/ Work \/ Idle \/ OnReply \/ OnIdle
Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* the board shows done only for work the worker did
NoFalseDone == closed \subseteq wdone
\* no task is lost: every task ends done or blocked (blocked = shown to the user)
AllSettled == <>[](\A t \in Tasks : t \in closed \cup blocked)
====
