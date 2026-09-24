import AwbModel
import Audit

/-!
The brief view and the Lark card sort every agent into one section: working (◔/▲), idle
(○) or needs-you (✗). This models that choice on the proven fold and shows that no agent
is dropped from the view and that a rejected check never reads as idle. `awbmodel brief`
prints the sections; selftest compares them with `awb snapshot` on random logs.
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
