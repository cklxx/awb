import AwbModel
import Audit

/-!
`awb snapshot` sorts every agent into one section: working (◔/▲), idle (○) or needs-you
(✗). The brief view and the Lark card draw only needs-you (README: an agent shows only where
it needs the owner or is off). This models that choice on the proven fold: no agent is
dropped from the snapshot, a rejected check never reads as idle, and an agent that stopped
after a rejected check is always drawn, under 需要你. `awbmodel brief` prints the sections;
selftest compares them with `awb snapshot` on random logs.
(Permission dialogs and session mismatches come from the Claude registry, outside the log.)
-/

inductive Sec | work | idle | needYou
  deriving DecidableEq, Repr

def sec : St → Option Sec
  | .running | .blocked => some .work
  | .done => some .idle
  | .failed => some .needYou
  | .other => none

theorem sec_total (a : A) (h : Good a) : (sec a.st).isSome := by
  obtain ⟨_, _, h3, _⟩ := h
  cases hs : a.st <;> simp_all [sec]

/-- Every agent of any log is shown in some section of the brief view. -/
theorem every_agent_shown (es : List Ev) : (sec (run es).st).isSome :=
  sec_total _ (inv_run es)

/-- The same for the fold over a raw trace, the one `awbmodel brief` runs. -/
theorem every_traced_agent_shown (tr : List Ob) : (sec (fold tr).st).isSome :=
  every_agent_shown _

/-- An agent whose last check was rejected is never listed as idle. -/
theorem rejected_not_idle (es : List Ev) (h : (run es).gate = true) :
    sec (run es).st ≠ some .idle := by
  obtain ⟨_, h2, _, _⟩ := inv_run es
  have := h2 h
  cases hs : (run es).st <;> simp_all [sec]

/-- What the brief view draws of an agent: the needs-you section only. -/
def drawn (s : St) : Bool := sec s == some .needYou

/-- An agent that stopped (neither working nor waiting) after its last check was rejected is
always drawn: the view never hides a rejected result behind a finished or idle agent. -/
theorem rejected_stopped_drawn (es : List Ev) (h : (run es).gate = true)
    (hs : (run es).st ≠ .running ∧ (run es).st ≠ .blocked) : drawn (run es).st = true := by
  obtain ⟨_, h2, h3, _⟩ := inv_run es
  have := h2 h
  cases hr : (run es).st <;> simp_all [drawn, sec]
