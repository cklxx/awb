---- MODULE AwbLoop ----
\* The main agent's dispatch/report loop with one Claude worker over the session socket
\* (SendMessage + notify_when_idle), as the skill describes it.
\* Fixed = FALSE: the 0.0.6 protocol. `awb now` per dispatch (the board keeps one current
\*   milestone), and `awb done` on the worker's reply or on the idle notice.
\* Fixed = TRUE: each dispatch carries a key the reply must echo; one open task per worker;
\*   a reply closes only the task with its key; an idle notice never closes a task, it makes
\*   the main ask once, and a second silent idle marks the task blocked (needs the user).
\* CanHold: the worker's session may hold incoming messages for its user's approval.
\* CanCrash: the worker may exit (at most MaxCrash times). Its session is gone with what it
\*   received and remembers; replies it already sent still arrive. The main sees the exit
\*   (an idle notice, a dead pane), runs `awb fail` and restarts it with `awb tui`.
\* RestartCloses = TRUE (0.0.9): the restart closes the open task as lost and the main sends it
\*   again with a new key. FALSE (0.0.8): the task stayed open, so no new task could be sent.
\* StageCloses = TRUE (0.0.8): the worker's own `awb now` (a stage report, no key) closed the
\*   task it was sent, and its reply was then refused as stale. FALSE (0.0.9): it does not.
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Tasks, Fixed, CanHold, CanCrash, MaxCrash, StageCloses, RestartCloses

\* a dispatch is <<task, key>>; an ask is <<"ask", task, key>>; a reply is <<task, key>>
VARIABLES todo, inbox, held, mem, wdone, toMain, sub, notice, cur, open, asked, closed,
          blocked, alive, crashes, n
vars == <<todo, inbox, held, mem, wdone, toMain, sub, notice, cur, open, asked, closed,
          blocked, alive, crashes, n>>

Init == /\ todo = Tasks /\ inbox = <<>> /\ held = FALSE /\ mem = {} /\ wdone = {}
        /\ toMain = <<>> /\ sub = FALSE /\ notice = FALSE /\ cur = <<>> /\ open = {}
        /\ asked = {} /\ closed = {} /\ blocked = {} /\ alive = TRUE /\ crashes = 0 /\ n = 0

\* deliver a message to the worker, or (CanHold) hold it and every later one
Deliver(m) == \E h \in (IF CanHold THEN {TRUE, FALSE} ELSE {FALSE}) :
                IF held \/ h THEN held' = TRUE /\ UNCHANGED inbox
                ELSE inbox' = Append(inbox, m) /\ UNCHANGED held

Dispatch(t) ==
  /\ alive /\ t \in todo /\ (Fixed => open = {})
  /\ todo' = todo \ {t} /\ n' = n + 1
  /\ cur' = <<t, n + 1>> /\ open' = open \cup {<<t, n + 1>>}   \* Old: overwrites the milestone
  /\ Deliver(<<t, n + 1>>)
  /\ sub' = TRUE
  /\ UNCHANGED <<mem, wdone, toMain, notice, asked, closed, blocked, alive, crashes>>

\* the worker does the next message: a task, or an ask to report a task it did
Work == /\ alive /\ inbox # <<>>
        /\ LET m == Head(inbox) IN
             IF m[1] \in Tasks
               THEN /\ mem' = mem \cup {m[1]} /\ wdone' = wdone \cup {m[1]}
                    /\ toMain' = Append(toMain, m)
               ELSE /\ toMain' = IF m[2] \in mem THEN Append(toMain, <<m[2], m[3]>>) ELSE toMain
                    /\ UNCHANGED <<mem, wdone>>
        /\ inbox' = Tail(inbox)
        /\ UNCHANGED <<todo, held, sub, notice, cur, open, asked, closed, blocked, alive, crashes, n>>

\* the worker reports a stage of the task in hand with its own `awb now` (no key)
Stage == /\ alive /\ inbox # <<>> /\ Head(inbox)[1] \in Tasks
         /\ open' = IF Fixed /\ StageCloses THEN open \ {Head(inbox)} ELSE open
         /\ UNCHANGED <<todo, inbox, held, mem, wdone, toMain, sub, notice, cur, asked, closed,
                        blocked, alive, crashes, n>>

\* nothing left to do (or everything held): one idle notice to a subscribed main
Idle == /\ alive /\ inbox = <<>> /\ sub /\ ~notice
        /\ notice' = TRUE /\ sub' = FALSE
        /\ UNCHANGED <<todo, inbox, held, mem, wdone, toMain, cur, open, asked, closed, blocked,
                       alive, crashes, n>>

\* the worker exits; a subscribed main gets the notice (notify_when_idle fires on exit too)
Crash == /\ CanCrash /\ alive /\ crashes < MaxCrash
         /\ alive' = FALSE /\ crashes' = crashes + 1
         /\ inbox' = <<>> /\ held' = FALSE /\ mem' = {}
         /\ notice' = (notice \/ sub) /\ sub' = FALSE
         /\ UNCHANGED <<todo, wdone, toMain, cur, open, asked, closed, blocked, n>>

\* the main sees the exit: `awb fail`, then `awb tui` with the same id
OnExit == /\ ~alive /\ toMain = <<>>                            \* replies are read first
          /\ alive' = TRUE /\ notice' = FALSE /\ sub' = FALSE
          /\ IF Fixed /\ RestartCloses
               THEN /\ open' = {} /\ todo' = todo \cup {m[1] : m \in open}
               ELSE UNCHANGED <<open, todo>>
          /\ UNCHANGED <<inbox, held, mem, wdone, toMain, cur, asked, closed, blocked, crashes, n>>

OnReply == /\ toMain # <<>>
           /\ LET r == Head(toMain) IN
                IF Fixed
                  THEN IF r \in open
                         THEN closed' = closed \cup {r[1]} /\ open' = open \ {r}
                         ELSE UNCHANGED <<closed, open>>              \* stale or duplicate
                  ELSE /\ closed' = IF cur = <<>> THEN closed ELSE closed \cup {cur[1]}
                       /\ open' = open \ {cur}
           /\ cur' = IF Fixed THEN cur ELSE <<>>
           /\ toMain' = Tail(toMain)
           /\ UNCHANGED <<todo, inbox, held, mem, wdone, sub, notice, asked, blocked, alive,
                          crashes, n>>

OnIdle == /\ alive /\ notice /\ notice' = FALSE /\ toMain = <<>>
          /\ IF Fixed
               THEN IF open = {} THEN UNCHANGED <<inbox, held, sub, asked, open, blocked>>
                    ELSE LET m == CHOOSE x \in open : TRUE IN
                      IF m \notin asked
                        THEN /\ asked' = asked \cup {m} /\ sub' = TRUE
                             /\ Deliver(<<"ask", m[1], m[2]>>)
                             /\ UNCHANGED <<open, blocked>>
                        ELSE /\ blocked' = blocked \cup {m[1]} /\ open' = open \ {m}
                             /\ UNCHANGED <<inbox, held, sub, asked>>
               ELSE /\ closed' = IF cur = <<>> THEN closed ELSE closed \cup {cur[1]}
                    /\ open' = open \ {cur}
                    /\ UNCHANGED <<inbox, held, sub, asked, blocked>>
          /\ cur' = IF Fixed THEN cur ELSE <<>>
          /\ IF Fixed THEN UNCHANGED closed ELSE TRUE
          /\ UNCHANGED <<todo, mem, wdone, toMain, alive, crashes, n>>

Next == (\E t \in Tasks : Dispatch(t)) \/ Work \/ Stage \/ Idle \/ Crash \/ OnExit
        \/ OnReply \/ OnIdle
\* the main and the worker keep going; a crash and a stage report may or may not happen
Spec == Init /\ [][Next]_vars
        /\ (\A t \in Tasks : WF_vars(Dispatch(t))) /\ WF_vars(Work) /\ WF_vars(Idle)
        /\ WF_vars(OnExit) /\ WF_vars(OnReply) /\ WF_vars(OnIdle)

\* the board shows done only for work the worker did
NoFalseDone == closed \subseteq wdone
\* no task is lost: every task ends done or blocked (blocked = shown to the user)
AllSettled == <>[](\A t \in Tasks : t \in closed \cup blocked)
====
