import AwbModel
import Audit
theorem acc_inv (es : List Ev) : Good (run es) := inv_run es
theorem acc_audit (tr : List Ob) : (audit tr).v = [] ↔ Clean tr := audit_iff_clean tr
theorem acc_pr (tr : List Ob) (h : (audit tr).v = []) (pre post : List Ob)
    (ht : tr = pre ++ .pr :: post) : passing (summary pre) = true := clean_pr tr h pre post ht
