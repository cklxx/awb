/-!
Model of awb's probe fold (the `probe` branch of the jq `reduce` in ../awb, docs/probe.md).
A task's probe readings arrive in any order; the board keeps one accepted reading and shows it
while it is fresh. Tasks are independent by id, so one task is modelled.
-/

inductive PSt | todo | wip | review | blocked | done | drop
  deriving DecidableEq, Repr

/-- One probe event. `st = none` when the probe failed: rc ≠ 0 (an anchor mismatch is reported
as rc ≠ 0), timeout, or output that is not `STATE text`. -/
structure PEv where
  t0 : Int            -- epoch the probe started
  ep : Int            -- epoch the reading was logged
  st : Option PSt
  deriving Repr

structure Reading where
  t0 : Int
  ep : Int
  st : PSt
  deriving DecidableEq, Repr

namespace Probe

/-- Accept a parsed reading unless it started before the accepted one; a failure changes nothing. -/
def pstep (acc : Option Reading) (e : PEv) : Option Reading :=
  match e.st with
  | none => acc
  | some s =>
      match acc with
      | none => some ⟨e.t0, e.ep, s⟩
      | some a => if a.t0 ≤ e.t0 then some ⟨e.t0, e.ep, s⟩ else acc

def prun (es : List PEv) : Option Reading := es.foldl pstep none

/-- Terminal readings (a merged or closed PR, a finished log) do not expire; the loop stops
probing them. -/
def terminal : PSt → Bool
  | .done | .drop => true
  | _ => false

/-- What the board shows at `now`: the accepted reading while fresh or terminal, else unknown
(`none`). -/
def shown (acc : Option Reading) (now fresh : Int) : Option PSt :=
  match acc with
  | some a => if terminal a.st ∨ now - a.ep ≤ fresh then some a.st else none
  | none => none

/-- The owner of a task that shows a fresh wait is left out of the stale section. -/
def waiting : Option PSt → Bool
  | some .wip | some .review => true
  | _ => false

def inStale (idle stale : Int) (w : Bool) : Bool := decide (stale ≤ idle) && !w

theorem pstep_fail (acc : Option Reading) (t0 ep : Int) : pstep acc ⟨t0, ep, none⟩ = acc := rfl

theorem pstep_mono (b a : Reading) (e : PEv) (h : pstep (some b) e = some a) : b.t0 ≤ a.t0 := by
  unfold pstep at h
  cases hs : e.st with
  | none => simp [hs] at h; subst h; exact Int.le_refl _
  | some s =>
      simp only [hs] at h
      split at h
      · simp at h; subst h; assumption
      · simp at h; subst h; exact Int.le_refl _

theorem pstep_some (acc : Option Reading) (e : PEv) (s : PSt) (hs : e.st = some s) :
    ∃ a, pstep acc e = some a ∧ e.t0 ≤ a.t0 := by
  unfold pstep; simp only [hs]
  cases acc with
  | none => exact ⟨_, rfl, Int.le_refl _⟩
  | some b =>
      simp only
      split
      · exact ⟨_, rfl, Int.le_refl _⟩
      · rename_i h; exact ⟨b, rfl, by omega⟩

/-- Folding never loses an accepted reading and never moves to an older one. -/
theorem foldl_mono (es : List PEv) (b a : Reading) (h : es.foldl pstep (some b) = some a) :
    b.t0 ≤ a.t0 := by
  induction es generalizing b with
  | nil => simp at h; subst h; exact Int.le_refl _
  | cons e es ih =>
      simp only [List.foldl_cons] at h
      cases hp : pstep (some b) e with
      | none =>
          unfold pstep at hp
          cases hs : e.st with
          | none => simp [hs] at hp
          | some s => simp only [hs] at hp; split at hp <;> simp at hp
      | some c => rw [hp] at h; exact Int.le_trans (pstep_mono b c e hp) (ih c h)

/-- (b) The accepted reading started no earlier than any parsed reading in the log. -/
theorem newest (es : List PEv) (acc : Option Reading) (a : Reading)
    (h : es.foldl pstep acc = some a) : ∀ e ∈ es, e.st.isSome → e.t0 ≤ a.t0 := by
  induction es generalizing acc with
  | nil => intro e he; simp at he
  | cons e es ih =>
      intro x hx hs
      simp only [List.foldl_cons] at h
      rcases List.mem_cons.mp hx with rfl | hx
      · obtain ⟨s, hs'⟩ := Option.isSome_iff_exists.mp hs
        obtain ⟨c, hc, hle⟩ := pstep_some acc x s hs'
        rw [hc] at h
        exact Int.le_trans hle (foldl_mono es c a h)
      · exact ih _ h x hx hs

/-- The accepted reading is one of the parsed readings in the log (or the starting one). -/
theorem source (es : List PEv) (acc : Option Reading) (a : Reading)
    (h : es.foldl pstep acc = some a) :
    acc = some a ∨ ∃ e ∈ es, e.st = some a.st ∧ e.t0 = a.t0 ∧ e.ep = a.ep := by
  induction es generalizing acc with
  | nil => simp at h; exact Or.inl h
  | cons e es ih =>
      simp only [List.foldl_cons] at h
      rcases ih _ h with h1 | ⟨x, hx, h2⟩
      · unfold pstep at h1
        cases hs : e.st with
        | none => simp [hs] at h1; exact Or.inl h1
        | some s =>
            simp only [hs] at h1
            cases acc with
            | none => simp at h1; subst h1; exact Or.inr ⟨e, by simp, hs, rfl, rfl⟩
            | some b =>
                simp only at h1
                split at h1
                · simp at h1; subst h1; exact Or.inr ⟨e, by simp, hs, rfl, rfl⟩
                · exact Or.inl h1
      · exact Or.inr ⟨x, List.mem_cons_of_mem _ hx, h2⟩

/-- (a) `done` is shown only if the newest parsed reading in the log says done. -/
theorem shown_done (es : List PEv) (now fresh : Int) (h : shown (prun es) now fresh = some .done) :
    ∃ a, prun es = some a ∧ a.st = .done ∧
      (∃ e ∈ es, e.st = some .done ∧ e.t0 = a.t0 ∧ e.ep = a.ep) ∧
      ∀ e ∈ es, e.st.isSome → e.t0 ≤ a.t0 := by
  cases hp : prun es with
  | none => simp [hp, shown] at h
  | some a =>
      simp only [hp, shown] at h
      split at h
      · simp at h
        refine ⟨a, rfl, h, ?_, newest es none a hp⟩
        rcases source es none a hp with h1 | ⟨e, he, h2⟩
        · simp at h1
        · exact ⟨e, he, h ▸ h2.1, h2.2⟩
      · simp at h

/-- (a) A failed read never makes the board show anything it did not already accept. -/
theorem fail_keeps (es : List PEv) (t0 ep : Int) :
    prun (es ++ [⟨t0, ep, none⟩]) = prun es := by
  simp [prun, List.foldl_append, pstep_fail]

/-- (a) A non-terminal reading past the freshness bound shows unknown. -/
theorem stale_unknown (acc : Option Reading) (now fresh : Int) (a : Reading)
    (h : acc = some a) (ht : terminal a.st = false) (hf : fresh < now - a.ep) :
    shown acc now fresh = none := by
  subst h; simp [shown, ht]; omega

/-- (c) An owner whose probed task shows a fresh wait is never in the stale section. -/
theorem waiting_not_stale (idle stale : Int) (s : Option PSt) (h : waiting s = true) :
    inStale idle stale (waiting s) = false := by
  simp [inStale, h]

end Probe
