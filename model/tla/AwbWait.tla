---- MODULE AwbWait ----
\* `awb tell` (and nudge, which calls it) against a Claude permission dialog that opens
\* while the tell is in flight. tell pastes the text, then presses Enter; with a retry
\* (PR #18) it presses Enter again while the text is still in the input box. A keystroke
\* that reaches an open dialog answers it (Enter picks the highlighted "Yes").
\* Guard: "none"  = main before #21, no check;
\*        "once"  = check the registry once before the paste;
\*        "each"  = check before the paste and again before every Enter.
\* Lag = TRUE: the registry (~/.claude/sessions status) reports "waiting" in a later step
\* than the dialog opens; Lag = FALSE: in the same step.
EXTENDS Naturals

CONSTANTS Guard, MaxEnter, Lag

\* seen: tell took a step since the registry began reporting "waiting" (it could have
\* checked); bad: a keystroke reached a dialog the registry reported before that step
VARIABLES dialog, reg, pc, enters, inBox, hits, seen, bad
vars == <<dialog, reg, pc, enters, inBox, hits, seen, bad>>

Init == /\ dialog = FALSE /\ reg = "ok" /\ pc = "check" /\ enters = 0
        /\ inBox = FALSE /\ hits = 0 /\ seen = FALSE /\ bad = FALSE

\* the worker's turn needs a permission (any time: a busy turn, a woken background task)
Open == /\ ~dialog /\ dialog' = TRUE
        /\ reg' = IF Lag THEN reg ELSE "waiting"
        /\ seen' = IF reg' = "waiting" /\ reg = "ok" THEN FALSE ELSE seen
        /\ UNCHANGED <<pc, enters, inBox, hits, bad>>
Sync == /\ reg /= (IF dialog THEN "waiting" ELSE "ok")
        /\ reg' = IF dialog THEN "waiting" ELSE "ok"
        /\ seen' = FALSE
        /\ UNCHANGED <<dialog, pc, enters, inBox, hits, bad>>

\* every tell step is a chance to have read the registry
Step == seen' = (reg = "waiting")

\* one keystroke group: into the dialog (answers and closes it) or into the input box
Key(box) == IF dialog THEN /\ hits' = hits + 1 /\ dialog' = FALSE /\ inBox' = inBox
                          /\ bad' = (bad \/ (reg = "waiting" /\ seen))
            ELSE /\ inBox' = box /\ UNCHANGED <<dialog, hits, bad>>

Check(next) == IF reg = "waiting" THEN pc' = "refused" ELSE pc' = next

CheckPaste == /\ pc = "check"
              /\ IF Guard = "none" THEN pc' = "paste" ELSE Check("paste")
              /\ Step /\ UNCHANGED <<dialog, reg, enters, inBox, hits, bad>>
Paste == /\ pc = "paste" /\ Key(TRUE) /\ pc' = "preEnter"
         /\ Step /\ UNCHANGED <<reg, enters>>
PreEnter == /\ pc = "preEnter"
            /\ IF Guard = "each" THEN Check("enter") ELSE pc' = "enter"
            /\ Step /\ UNCHANGED <<dialog, reg, enters, inBox, hits, bad>>
Enter == /\ pc = "enter" /\ Key(FALSE) /\ Step
         /\ enters' = enters + 1
         \* still in the box (the Enter went to a dialog) and retries left: press again
         /\ pc' = IF inBox' /\ enters + 1 < MaxEnter THEN "preEnter" ELSE "done"
         /\ UNCHANGED reg

Next == Open \/ Sync \/ CheckPaste \/ Paste \/ PreEnter \/ Enter
Spec == Init /\ [][Next]_vars

\* What a guard can promise: no keystroke reaches a dialog the registry already reported
\* when tell last had the chance to check. "once" fails it (the Enter after a paste).
NoKeyIntoReportedDialog == ~bad
\* What no guard can promise: the check and the keystroke are separate steps, so a dialog
\* opening between them (or one the registry has not reported yet) takes the keystroke.
\* AwbWaitRace.cfg shows the counterexample for "each"; only not typing avoids it.
NeverAnswers == hits = 0
====
