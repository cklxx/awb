import AwbModel
import Audit
import Brief
theorem acc_inv (es : List Ev) : Good (run es) := inv_run es
theorem acc_audit (tr : List Ob) : (audit tr).v = [] ↔ Clean tr := audit_iff_clean tr
theorem acc_pr (tr : List Ob) (h : (audit tr).v = []) (pre post : List Ob)
    (ht : tr = pre ++ .pr :: post) : passing (summary pre) = true := clean_pr tr h pre post ht
theorem acc_brief_total (es : List Ev) : (sec (run es).st).isSome := every_agent_shown es
theorem acc_brief_rejected (es : List Ev) (h : (run es).gate = true) :
    sec (run es).st ≠ some .idle := rejected_not_idle es h
