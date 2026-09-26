import Audit
import Brief
import Probe
import Lean.Data.Json

/-!
`awbmodel` runs the proven model on a real `.awb/events.jsonl` (stdin):

* `awbmodel fold`  — per-agent state from `step`: `ID STATUS GATE END DUR ND`, sorted by id,
                     then the accepted probe reading per task from `prun`:
                     `probe ID STATE T0 EP` (`- - -` when none parsed);
                     `awb state` prints the same from awb's jq fold (differential test).
* `awbmodel audit` — protocol violations from the verified monitor `audit`; exit 1 if any.
* `awbmodel brief` — each agent's brief-view section (`Brief.sec`): `ID work|idle|need`.
* `awbmodel gen SEED N` — a random event log for the differential test.
-/

open Lean

def St.ofString : String → St
  | "running" => .running | "blocked" => .blocked | "failed" => .failed | "done" => .done
  | _ => .other

def St.name : St → String
  | .running => "running" | .blocked => "blocked" | .failed => "failed" | .done => "done"
  | .other => "other"

def str? (j : Json) (k : String) : Option String := (j.getObjValAs? String k).toOption
def int? (j : Json) (k : String) : Option Int := (j.getObjValAs? Int k).toOption
def isTrue (j : Json) (k : String) : Bool := (j.getObjValAs? Bool k).toOption == some true

/-- One log line as (agent id, observation), mirroring the jq fold's reading of it. -/
def parseLine (line : String) : Option (String × Ob) := do
  let j ← (Json.parse line).toOption
  let t ← str? j "t"
  let id ← str? j "id"
  let ep := (int? j "ep").getD 0
  match t with
  | "start" => pure (id, .ev .start)
  | "now" => pure (id, .ev (.now ep))
  | "done" =>
      let hasText := match j.getObjVal? "text" with | .ok .null => false | .ok _ => true | .error _ => false
      pure (id, .ev (.done ep (isTrue j "verified") hasText))
  | "status" =>
      let s := St.ofString ((str? j "status").getD "running")
      if s == .failed && isTrue j "gate" then pure (id, .ev (.reject ep)) else pure (id, .ev (.status s ep))
  | "chk" =>
      let ok := match str? j "state" with | some "ok" => some true | some "fail" => some false | _ => none
      pure (id, .chk ((str? j "run").getD "") ((str? j "step").getD "") ok)
  | "pr" => pure (id, .pr)
  | _ => none

def PSt.ofString : String → Option PSt
  | "todo" => some .todo | "wip" => some .wip | "review" => some .review
  | "blocked" => some .blocked | "done" => some .done | "drop" => some .drop | _ => none

def PSt.name : PSt → String
  | .todo => "todo" | .wip => "wip" | .review => "review" | .blocked => "blocked"
  | .done => "done" | .drop => "drop"

/-- A probe log line as (task id, reading): parsed only when rc = 0 and the state is valid. -/
def probeLine (line : String) : Option (String × PEv) := do
  let j ← (Json.parse line).toOption
  if str? j "t" != some "probe" then none
  let id ← str? j "id"
  let st := if int? j "rc" == some 0 then (str? j "st").bind PSt.ofString else none
  pure (id, ⟨(int? j "ep0").getD 0, (int? j "ep").getD 0, st⟩)

def probeTraces (lines : List String) : List (String × List PEv) := Id.run do
  let mut tr : Std.HashMap String (Array PEv) := {}
  for l in lines do
    match probeLine l with
    | none => pure ()
    | some (id, e) => tr := tr.insert id ((tr.getD id #[]).push e)
  return tr.toList.map fun (id, es) => (id, es.toList)

/-- Per-agent traces in first-seen order. Like the jq fold, status events before an
agent's first `start` are dropped; check and PR events are kept for the audit. -/
def traces (lines : List String) : List (String × List Ob) := Id.run do
  let mut ids : Array String := #[]
  let mut tr : Std.HashMap String (Array Ob) := {}
  for l in lines do
    match parseLine l with
    | none => pure ()
    | some (id, o) =>
        let cur := tr.getD id #[]
        let started := cur.any (fun | .ev .start => true | _ => false)
        let keep := match o with | .ev .start => true | .ev _ => started | _ => true
        if keep then
          if !tr.contains id then ids := ids.push id
          tr := tr.insert id (cur.push o)
  return ids.toList.map fun id => (id, (tr.getD id #[]).toList)

def Viol.name : Viol → String
  | .forgedVerify => "verified-without-passing-check"
  | .prWithoutPass => "pr-without-passing-check"
  | .doneWhileRejected => "done-while-check-rejected"

/-- Tiny LCG, so a seed reproduces a trace. -/
def lcg (s : Nat) : Nat := (s * 6364136223846793005 + 1442695040888963407) % 2^64

def gen (seed n : Nat) : List String := Id.run do
  let mut s := lcg (seed + 1)
  let mut ep : Int := 1000
  let mut out : Array String := #[]
  for _ in [0:n] do
    s := lcg s; let r := s / 65536
    let id := #["a", "b", "c"][r % 3]!
    let k := (r / 3) % 18
    let d : Int := (((r / 48) % 7 : Nat) : Int) - 1          -- mostly forward, sometimes back
    ep := ep + d
    let base := s!"\"time\":\"x\",\"ep\":{ep},\"id\":\"{id}\""
    let run := s!"r{(r / 336) % 3}"
    let st := #["running", "blocked", "failed", "done", "bogus"][(r / 1008) % 5]!
    let step := #["build", "types"][(r / 5040) % 2]!
    let cs := #["run", "ok", "ok", "fail"][(r / 10080) % 4]!
    let line := match k with
      | 0 | 1 => s!"\{\"t\":\"start\",{base},\"name\":\"{id}\",\"kind\":\"agent\",\"pane\":\"\",\"group\":\"g\"}"
      | 2 | 3 => s!"\{\"t\":\"now\",{base},\"text\":\"m\"}"
      | 4 => s!"\{\"t\":\"done\",{base},\"text\":null}"
      | 5 => s!"\{\"t\":\"done\",{base},\"text\":\"x\"}"
      | 6 => s!"\{\"t\":\"done\",{base},\"text\":null,\"verified\":true}"
      | 7 | 8 => s!"\{\"t\":\"status\",{base},\"status\":\"{st}\",\"reason\":\"\"}"
      | 9 => s!"\{\"t\":\"status\",{base},\"status\":\"failed\",\"reason\":\"r\",\"gate\":true}"
      | 10 | 11 | 12 => s!"\{\"t\":\"chk\",{base},\"run\":\"{run}\",\"what\":\"w\",\"step\":\"{step}\",\"state\":\"{cs}\",\"note\":\"\"}"
      | 13 => s!"\{\"t\":\"pr\",{base},\"url\":\"u\"}"
      | 14 => s!"\{\"t\":\"goal\",\"time\":\"x\",\"ep\":{ep},\"text\":\"g\"}"
      | 16 | 17 =>                                          -- probe readings, some older, some failed
          let tid := #["t1", "t2"][(r / 20160) % 2]!
          let ep0 := ep - (((r / 40320) % 4 : Nat) : Int)
          let rc := #[0, 0, 0, 1, 124][(r / 161280) % 5]!
          let pst := #["\"wip\"", "\"done\"", "\"review\"", "\"bogus\"", "null"][(r / 806400) % 5]!
          s!"\{\"t\":\"probe\",\"time\":\"x\",\"ep\":{ep},\"id\":\"{tid}\",\"ep0\":{ep0},\"rc\":{rc},\"st\":{pst},\"text\":\"p\"}"
      | _ => "{\"t\":\"now\",\"id\":"                         -- a torn line
    out := out.push line
  return out.toList

def main (args : List String) : IO UInt32 := do
  match args with
  | ["gen", seed, n] =>
      for l in gen seed.toNat! n.toNat! do IO.println l
      return 0
  | [cmd] =>
      let input ← (← IO.getStdin).readToEnd
      let ts := traces (input.splitOn "\n")
      if cmd == "fold" then
        for (id, tr) in ts.toArray.qsort (fun x y => x.1 < y.1) do
          if tr.any (fun | .ev .start => true | _ => false) then
            let a := fold tr
            let e := match a.endEp with | some x => toString x | none => "-"
            IO.println s!"{id} {a.st.name} {a.gate} {e} {a.dur} {a.nd}"
        for (id, es) in (probeTraces (input.splitOn "\n")).toArray.qsort (fun x y => x.1 < y.1) do
          match Probe.prun es with
          | some a => IO.println s!"probe {id} {a.st.name} {a.t0} {a.ep}"
          | none => IO.println s!"probe {id} - - -"
        return 0
      else if cmd == "brief" then
        for (id, tr) in ts.toArray.qsort (fun x y => x.1 < y.1) do
          if tr.any (fun | .ev .start => true | _ => false) then
            let s := match sec (fold tr).st with
              | some .work => "work" | some .idle => "idle" | some .needYou => "need" | none => "none"
            IO.println s!"{id} {s}"
        return 0
      else if cmd == "audit" then
        let mut bad := false
        for (id, tr) in ts do
          for v in (audit tr).v do
            IO.println s!"{id} {v.name}"; bad := true
        return (if bad then 1 else 0)
      else
        IO.eprintln "usage: awbmodel fold|brief|audit < events.jsonl | awbmodel gen SEED N"; return 2
  | _ => IO.eprintln "usage: awbmodel fold|audit < events.jsonl | awbmodel gen SEED N"; return 2
