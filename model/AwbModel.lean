/-
Model of awb's per-agent event fold (the jq `reduce` in ../awb).
Agents are independent by id, so one agent is modelled. Epochs are Int.
`stepOld` is the fold before this model; `step` is the fixed fold.
-/

inductive St | running | blocked | failed | done | other
  deriving DecidableEq, Repr

inductive Ev
  | start
  | now (ep : Int)
  | done (ep : Int) (verified : Bool) (hasText : Bool := false)
  | status (s : St) (ep : Int)   -- block/unblock/fail/finish/_leave/`awb status`
  | reject (ep : Int)             -- `awb check` failed
  deriving Repr

structure A where
  st    : St
  cur   : Option Int   -- current milestone start epoch
  endEp : Option Int
  gate  : Bool         -- a rejected check is pending
  dur   : Int          -- duration of the last closed milestone
  nd    : Nat          -- closed milestones
  deriving Repr

def A.init : A := ⟨.running, none, none, false, 0, 0⟩

def terminal : St → Bool
  | .done | .failed => true
  | _ => false

def endOf (s : St) (ep : Int) (old : Option Int) : Option Int :=
  match s with
  | .done | .failed => some ep
  | .running | .blocked => none
  | .other => old

/-! ## Fold before the fix -/

def stepOld (a : A) : Ev → A
  | .start => a                                            -- re-start of a known id ignored
  | .now ep => { a with cur := some ep }
  | .done ep v _ =>
      let a := { a with dur := ep - a.cur.getD ep, cur := none }
      if v && a.st == .failed then { a with st := .running, endEp := none } else a
  | .status s ep => { a with st := s, endEp := endOf s ep a.endEp }
  | .reject ep => { a with st := .failed, endEp := some ep }  -- check wrote a plain `failed`

def runOld (es : List Ev) : A := es.foldl stepOld A.init

-- Bug 1: a rejected check is erased when the `awb run` process exits 0 (_leave writes done).
example : (runOld [.start, .now 0, .reject 5, .status .done 9]).st = .done := by decide
-- Bug 2: re-running an agent id that already finished keeps it `done`.
example : (runOld [.start, .status .done 3, .start, .now 4]).st = .done := by decide
-- Bug 3: after `fail`, starting a new milestone keeps it `failed`.
example : (runOld [.start, .status .failed 3, .now 4]).st = .failed := by decide
-- Bug 4: `awb status ID <anything>` leaves a frozen endEp on a non-terminal agent.
example : let a := runOld [.start, .status .done 3, .status .other 4]
          terminal a.st = false ∧ a.endEp.isSome := by decide
-- Bug 5: out-of-order epochs (concurrent appends, second resolution) give negative durations.
example : (runOld [.start, .now 10, .done 9 false false]).dur < 0 := by decide

/-! ## Fixed fold -/

def step (a : A) : Ev → A
  | .start => { a with st := .running, endEp := none }
  | .now ep => { a with cur := some ep, st := .running, endEp := none }
  | .done ep v t =>
      -- a passing check with no open milestone verifies the last closed one (no new entry)
      let a := if v && a.cur.isNone && 0 < a.nd && !t then a
               else { a with dur := max 0 (ep - a.cur.getD ep), cur := none, nd := a.nd + 1 }
      if v then
        if a.st == .failed then { a with gate := false, st := .running, endEp := none }
        else { a with gate := false }
      else a
  | .status s ep =>
      if s == .other then a                                  -- unknown states rejected
      else if s == .done && a.gate then { a with st := .failed, endEp := some ep }
      else { a with st := s, endEp := endOf s ep a.endEp }
  | .reject ep => { a with st := .failed, endEp := some ep, gate := true }

def run (es : List Ev) : A := es.foldl step A.init

def Good (a : A) : Prop :=
  (terminal a.st = true ↔ a.endEp.isSome) ∧   -- duration frozen iff agent ended
  (a.gate = true → a.st ≠ .done) ∧            -- no done while a check is rejected
  a.st ≠ .other ∧
  0 ≤ a.dur

theorem inv_init : Good A.init := by simp [Good, A.init, terminal]

theorem inv_step (a : A) (e : Ev) (h : Good a) : Good (step a e) := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  cases e with
  | start => exact ⟨by simp [step, terminal], by simp [step], by simp [step], h4⟩
  | now ep => exact ⟨by simp [step, terminal], by simp [step], by simp [step], h4⟩
  | done ep v t =>
      cases v <;> simp only [step] <;> (repeat' split) <;> cases hs : a.st <;>
        simp_all [terminal, Good, Int.le_max_left]
  | status s ep =>
      refine ⟨?_, ?_, ?_, ?_⟩ <;> cases s <;> cases hg : a.gate <;>
        simp_all [step, terminal, endOf]
  | reject ep => exact ⟨by simp [step, terminal], by simp [step], by simp [step], h4⟩

theorem inv_run (es : List Ev) : Good (run es) := by
  unfold run
  suffices ∀ a, Good a → Good (es.foldl step a) from this _ inv_init
  induction es with
  | nil => intro a h; exact h
  | cons e es ih => intro a h; exact ih _ (inv_step a e h)

-- Liveness facts of the fixed fold.
theorem start_runs (a : A) : (step a .start).st = .running := rfl
theorem now_runs (a : A) (ep : Int) : (step a (.now ep)).st = .running := rfl
