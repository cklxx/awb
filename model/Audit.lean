import AwbModel

/-!
Audit of one agent's event trace against the acceptance protocol.

* `violAt pre o` states the rules for one event `o` given everything before it.
* `Clean tr`: no event of `tr` breaks a rule relative to its own prefix (the spec).
* `audit` is the one-pass monitor `awb audit` runs; `audit_iff_clean` proves it
  reports nothing exactly when the trace is `Clean`.
-/

/-- One observed event of a single agent. -/
inductive Ob
  | ev (e : Ev)                                      -- feeds the status fold
  | chk (run step : String) (ok : Option Bool)       -- `awb check` step: none = running
  | pr                                               -- `awb pr` opened a pull request
  deriving Repr

inductive Viol
  | forgedVerify        -- verified milestone without a passing check before it
  | prWithoutPass       -- PR opened without a passing check before it
  | doneWhileRejected   -- `done` claimed while a rejected check is pending
  deriving DecidableEq, Repr

/-- Steps of the latest check run: run id and each step's last state. -/
abbrev Run := Option (String × List (String × Option Bool))

def upd (l : List (String × Option Bool)) (s : String) (o : Option Bool) :
    List (String × Option Bool) :=
  if l.any (·.1 == s) then l.map (fun p => if p.1 == s then (s, o) else p) else l ++ [(s, o)]

def chkUpd (r : Run) : Ob → Run
  | .chk run s o =>
      match r with
      | some (run', l) => if run' == run then some (run, upd l s o) else some (run, [(s, o)])
      | none => some (run, [(s, o)])
  | _ => r

/-- The latest check run passed: it has steps and every step ended ok. -/
def passing : Run → Bool
  | some (_, l) => !l.isEmpty && l.all (·.2 == some true)
  | none => false

def toEv : Ob → Option Ev
  | .ev e => some e
  | _ => none

def summary (pre : List Ob) : Run := pre.foldl chkUpd none
def fold (pre : List Ob) : A := (pre.filterMap toEv).foldl step A.init

/-- Rule check for state `(a, r)` = (status fold, latest check run) of the prefix. -/
def violOf (a : A) (r : Run) : Ob → Option Viol
  | .ev (.done _ true _) => if passing r then none else some .forgedVerify
  | .pr => if passing r then none else some .prWithoutPass
  | .ev (.status .done _) => if a.gate then some .doneWhileRejected else none
  | _ => none

def violAt (pre : List Ob) (o : Ob) : Option Viol := violOf (fold pre) (summary pre) o

/-- Spec: every event is fine relative to everything before it. -/
def Clean (tr : List Ob) : Prop := ∀ pre o post, tr = pre ++ o :: post → violAt pre o = none

/-! ## Monitor -/

structure M where
  a : A
  r : Run
  v : List Viol

def M.init : M := ⟨A.init, none, []⟩

def mstep (m : M) (o : Ob) : M :=
  { a := match toEv o with | some e => step m.a e | none => m.a
    r := chkUpd m.r o
    v := m.v ++ (violOf m.a m.r o).toList }

def audit (tr : List Ob) : M := tr.foldl mstep M.init

/-! ## Monitor = spec -/

theorem snoc_induction {α} {P : List α → Prop} (h0 : P [])
    (hs : ∀ l x, P l → P (l ++ [x])) (l : List α) : P l := by
  rw [← List.reverse_reverse l]
  induction l.reverse with
  | nil => exact h0
  | cons x t ih => rw [List.reverse_cons]; exact hs _ _ ih

theorem fold_snoc (pre : List Ob) (o : Ob) :
    fold (pre ++ [o]) = match toEv o with | some e => step (fold pre) e | none => fold pre := by
  unfold fold
  cases h : toEv o <;> simp [List.filterMap_append, h, List.foldl_append]

theorem audit_state (tr : List Ob) : (audit tr).a = fold tr ∧ (audit tr).r = summary tr := by
  refine snoc_induction (P := fun tr => (audit tr).a = fold tr ∧ (audit tr).r = summary tr)
    ⟨rfl, rfl⟩ ?_ tr
  intro pre o ⟨ha, hr⟩
  refine ⟨?_, ?_⟩
  · simp only [audit, List.foldl_append, List.foldl_cons, List.foldl_nil] at ha ⊢
    rw [fold_snoc]; simp only [mstep, ha]
  · simp only [audit, List.foldl_append, List.foldl_cons, List.foldl_nil, summary] at hr ⊢
    simp only [mstep, hr]

theorem audit_v_snoc (pre : List Ob) (o : Ob) :
    (audit (pre ++ [o])).v = (audit pre).v ++ (violAt pre o).toList := by
  obtain ⟨ha, hr⟩ := audit_state pre
  simp only [audit, List.foldl_append, List.foldl_cons, List.foldl_nil] at ha hr ⊢
  simp only [mstep, violAt, ha, hr]

theorem clean_nil : Clean [] := by
  intro pre o post h; simp at h

theorem clean_snoc (pre : List Ob) (o : Ob) :
    Clean (pre ++ [o]) ↔ Clean pre ∧ violAt pre o = none := by
  constructor
  · intro h
    refine ⟨?_, h pre o [] rfl⟩
    intro p x q hp
    exact h p x (q ++ [o]) (by simp [hp])
  · rintro ⟨hc, hv⟩ p x q hq
    rcases List.eq_nil_or_concat q with rfl | ⟨q', y, rfl⟩
    · have := List.append_inj' hq rfl
      simp at this
      obtain ⟨rfl, rfl⟩ := this
      exact hv
    · have h2 : pre ++ [o] = (p ++ x :: q') ++ [y] := by simpa using hq
      have := List.append_inj' h2 rfl
      obtain ⟨hpre, -⟩ := this
      exact hc p x q' hpre

/-- The monitor reports no violation exactly when the trace follows the protocol. -/
theorem audit_iff_clean (tr : List Ob) : (audit tr).v = [] ↔ Clean tr := by
  refine snoc_induction (P := fun tr => (audit tr).v = [] ↔ Clean tr)
    ⟨fun _ => clean_nil, fun _ => rfl⟩ ?_ tr
  intro pre o ih
  rw [audit_v_snoc, clean_snoc, ← ih]
  cases violAt pre o <;> simp

/-- Consequence: in a clean trace every PR was preceded by a passing check. -/
theorem clean_pr (tr : List Ob) (h : (audit tr).v = []) (pre post : List Ob)
    (ht : tr = pre ++ .pr :: post) : passing (summary pre) = true := by
  have := (audit_iff_clean tr).1 h pre .pr post ht
  simp only [violAt, violOf] at this
  split at this <;> simp_all
