import AwbModel
import Audit
import Brief
import Probe
theorem acc_inv (es : List Ev) : Good (run es) := inv_run es
theorem acc_audit (tr : List Ob) : (audit tr).v = [] ↔ Clean tr := audit_iff_clean tr
theorem acc_pr (tr : List Ob) (h : (audit tr).v = []) (pre post : List Ob)
    (ht : tr = pre ++ .pr :: post) : passing (summary pre) = true := clean_pr tr h pre post ht
theorem acc_brief_total (es : List Ev) : (sec (run es).st).isSome := every_agent_shown es
theorem acc_brief_rejected (es : List Ev) (h : (run es).gate = true) :
    sec (run es).st ≠ some .idle := rejected_not_idle es h
theorem acc_brief_drawn (es : List Ev) (h : (run es).gate = true)
    (hs : (run es).st ≠ .running ∧ (run es).st ≠ .blocked) : drawn (run es).st = true :=
  rejected_stopped_drawn es h hs
theorem acc_probe_newest (es : List PEv) (a : Reading) (h : Probe.prun es = some a) :
    ∀ e ∈ es, e.st.isSome → e.t0 ≤ a.t0 := Probe.newest es none a h
theorem acc_probe_fail (es : List PEv) (t0 ep : Int) :
    Probe.prun (es ++ [⟨t0, ep, none⟩]) = Probe.prun es := Probe.fail_keeps es t0 ep
theorem acc_probe_done (es : List PEv) (now fresh : Int)
    (h : Probe.shown (Probe.prun es) now fresh = some .done) :
    ∃ a, Probe.prun es = some a ∧ a.st = .done ∧
      (∃ e ∈ es, e.st = some .done ∧ e.t0 = a.t0 ∧ e.ep = a.ep) ∧
      ∀ e ∈ es, e.st.isSome → e.t0 ≤ a.t0 := Probe.shown_done es now fresh h
theorem acc_probe_stale (acc : Option Reading) (now fresh : Int) (a : Reading)
    (h : acc = some a) (ht : Probe.terminal a.st = false) (hf : fresh < now - a.ep) :
    Probe.shown acc now fresh = none := Probe.stale_unknown acc now fresh a h ht hf
theorem acc_probe_wait (idle stale : Int) (s : Option PSt) (h : Probe.waiting s = true) :
    Probe.inStale idle stale (Probe.waiting s) = false := Probe.waiting_not_stale idle stale s h
