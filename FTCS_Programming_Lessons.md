# FTCS - Programming Lessons Learned (Base de Conocimiento TÃ©cnica)

<!--
    PURPOSE:
    This file is the project's LIVING TECHNICAL KNOWLEDGE BASE. It records two
    kinds of entries, both numbered sequentially and dated (newest at the BOTTOM):

    1. PROGRAMMING LESSONS - every non-obvious programming finding, root-cause
       analysis, engine quirk or debugging lesson discovered while developing
       FTCS (Arma 3 SQF today, Enforce Script / Arma 4 tomorrow).
    2. ARCHITECTURE / DESIGN NOTES - whenever a structural change to the software
       is made, or a mechanism crucial to understanding how FTCS works is added
       (e.g. the data structure lifecycle, the central registry/hash model, the
       order-propagation chain), an entry written as a DIRECT GUIDE FOR AN AI:
       oriented to automatic consumption - invariants that must not be broken,
       module contracts, what to read and in which order to understand the
       system, and how NOT to break it when programming on top of it.
       This is DISTINCT from and complementary to the human-oriented design
       documentation: that explains the WHAT and WHY for the programmer; these
       notes explain HOW IT WORKS and HOW NOT TO BREAK IT for the AI coding on it.

    RULES FOR THE AI (and the human programmer):
    - READ THIS FILE COMPLETELY before writing or debugging any code in this project.
    - Every entry must describe a REAL problem that actually occurred in this
      project, its verified root cause, and the fix that was proven to work.
    - Entries are numbered sequentially and dated (newest at the BOTTOM).
    - When a new lesson is learned during any task, ADD IT HERE as the next entry.
    - Do not delete entries; if a lesson becomes obsolete, mark it as such but
      keep the historical record.
    - Language: English (technical reference for AI consumption), per the
      project's Point 0 rules for all code/documentation meant for the engine.
-->

## Index

| # | Date | Type | Topic | Module / File |
|---|------|------|-------|---------------|
| 1 | 2026-11-13 | Lesson | `continue` keyword is NOT supported inside `forEach` loops (SQF) | `Functions/Targeting/fn_targetPersistentMarker.sqf` |
| 2 | 2026-11-13 | Arch/Design | Mission-folder linker: NTFS Junctions + hardlinks, one versioned repo for all terrains | `LinkMission.bat`, `tools/LinkMission.ps1` |
| 3 | 2026-11-14 | Lesson + Arch/Design | HashMap key order is NOT deterministic: "first team found" as squad anchor misclassifies fireteams as squads (HALT/REJOIN) | `Functions/Core/fn_registryInit.sqf`, `Functions/Formations/fn_platoonHaltRejoin.sqf` |
| 4 | 2026-11-14 | Lesson | `leader _group` is NOT the doctrine commander: Arma 3 rules pick the group leader (HQ resolved to its RTO) | `Functions/Core/fn_registryInit.sqf` (`roleKey`) |
| 5 | 2026-11-14 | Lesson + Arch/Design | The platoon leader lives in a DIFFERENT group than the doctrinal Command Element: group identity cannot answer "who commands the platoon" (`leaderUnit`/`leaderGroup`/`peerOnly`) | `Functions/Core/fn_registryInit.sqf`, `FTCS_Platoons_Registry` |
| 6 | 2026-11-14 | Arch/Design | Phase 2: platoon STATE in the registry (`movementTechnique`, `roadPath`, anchors, `formationSlots`) with a temporary doctrine MIRROR until Phase 3 | `Functions/Core/fn_registryInit.sqf` (`registrySetPlatoon` / `registryGetPlatoon`) |
| 7 | 2026-11-14 | Lesson | `!A isEqualTo B` parses as `(!A) isEqualTo B` -> "Error !: Type String, expected Bool" (runtime only) | `Functions/Movement/fn_movementBoundTeams.sqf` |
| 8 | 2026-11-14 | Arch/Design | Doctrine is a SEED: `doctrineFormationSlots` (immutable template) vs `formationSlots` (live state); future re-order/casualties go to the registry, never the doctrine | `Functions/Core/fn_applyDoctrine.sqf`, `fn_formationsApplyPlatoonOrder.sqf` |
| 9 | 2026-11-14 | Lesson | Migrating a consumer: REMOVE every use of the replaced variable (`getOrDefault` on an undefined variable fails SILENTLY). Scout detachment lost its team list | `Functions/Interactions/fn_applyCommandToTarget.sqf` |
| 10 | 2026-11-14 | Lesson | Recalling a detached scout must reset its FULL squad state (`allocationSlot`, `parentSquadGroup`, `teamAttachment`, `movingMode`), not just the attachment - otherwise the next REJOIN anchors it to the lieutenant | `fn_applyCommandToTarget.sqf`, `fn_platoonHaltRejoin.sqf` |
| 11 | 2026-11-14 | Lesson + Arch/Design | "Pick the first matching group" is a HashMap-order bug: doctrine must DECLARE the scout team via `teamRoles = SCOUT`; registry carries `tacticalRole`, selection is deterministic | `Doctrines/Data/*.sqf`, `fn_registryInit.sqf`, `fn_applyCommandToTarget.sqf` |
| 12 | 2026-11-14 | Lesson | `parsedSquads` is built AFTER `fn_applyDoctrine`: fields stamped on the doctrine template never reach the runtime teams. Project roles as an INDEX array (`doctrineTeamRoles`) and resolve by `TEAM_<N>` ordinal | `fn_applyDoctrine.sqf`, `fn_parseEditorGroups.sqf`, `fn_registryInit.sqf` |
| **PENDING-1** | 2026-11-14 | **OPEN Arch/Design** | **Company scale: each AI platoon needs its own follow loop + formation management. Registry data exists, no consumer uses it per platoon yet. Decide BEFORE new features** | every movement/formation function |
| **PENDING-2** | 2026-11-14 | **CLOSED Verification** | Long-cycle scout verification (3 deploys, REJOIN after recall, road/trail with scouts, mixed squads) - **verified in game**. Kept as regression baseline | `fn_applyCommandToTarget.sqf`, `fn_platoonHaltRejoin.sqf` |
| 13 | 2026-11-14 | Lesson + Arch/Design | Debug sentinel policy (Rule 19) + `surfaceIsWater` is TRUE on a bridge deck (height-aware test required) | project-wide, `fn_trailAdvanceAnchor.sqf` |
| 14 | 2026-11-14 | Lesson | `nil` inside an array COLLAPSES it (`[a,b,nil]` -> `[a,b]`); `nil` in `registrySet` DELETES the key and leaves a stale read. Use `[]` as the explicit sentinel | `fn_formationsTrailQueueSync.sqf`, `fn_formationsGroupFollowTrail.sqf` |
| **SESSION** | 2026-11-14 | **CLOSED Session log** | HALT/REJOIN fix + full RULE 16 migration (phases 1-9). Read this first when resuming | whole project |
| **PENDING-3** | 2026-11-14 | **OPEN** | Sentinel audit: ~38 diagnostic traces in 12 files still log unconditionally; add `FTCS_Debug_Trace` gating where verbose | see Rule 19 |
| **PENDING-4** | 2026-11-14 | **CLOSED** | Bridge crossing: `surfaceIsWater` is true on a bridge deck. Applied height-aware test (Z - terrainZ < 1.2 m) in trail record, trail follow and road follow | `fn_trailAdvanceAnchor.sqf`, `fn_formationsGroupFollowTrail.sqf`, `fn_formationsGroupFollowRoad.sqf` |
| 15 | 2026-11-15 | Arch/Design | Trail column crossing a cut (bridge / gap / clearance): the RECORD freeze IS the barrier. Queue = first car whose natural index exceeds `maxIdx`; everyone behind is re-chained by DOCTRINAL gap, not by copying the car ahead | `Functions/Movement/fn_formationsTrailQueueSync.sqf`, `fn_trailAdvanceAnchor.sqf` |
| 16 | 2026-11-15 | Lesson | `private _x = <nil>` does NOT create the variable, so `isEqualType` cannot guard a `nil`-returning getter (`FTCS_fnc_registryGet`). Materialise with `isNil` first | `Functions/Formations/fn_formationsGroupFollowTrail.sqf`, `fn_registryInit.sqf` |
| 17 | 2026-11-15 | Lesson | `allocationSlot` ascending is NOT the march order: road and trail columns must walk the SAME explicit list `[9,0,4,1,2,3,10,5]` (RTO first, scouts excluded) | `Functions/Formations/fn_trailColumnSet.sqf`, `fn_formationsRoadColumnSet.sqf` |
| **PENDING-5** | 2026-11-15 | **OPEN Refactor** | `_slotOrder = [9,0,4,1,2,3,10,5]` is DUPLICATED in road and trail column functions. Extract to a shared `FTCS_fnc_columnSlotOrder` so the two cannot diverge. Do it when the road column is next touched | `fn_formationsRoadColumnSet.sqf`, `fn_trailColumnSet.sqf` |
| 18 | 2026-11-15 | Lesson | A trail seat must be measured FROM THE FRONT: `maxIdx - round(offset/step)`, the index form of the road rule `headDist - offsetDist`. Measuring from index 0 mirrored the whole column | `Functions/Movement/fn_formationsTrailQueueSync.sqf`, `fn_formationsGroupFollowTrail.sqf` |
| 19 | 2026-11-15 | Lesson + Arch/Design | Waking a group for a march is ONE function (`FTCS_fnc_groupAwakenForMarch`), not an inline `enableAI` block in 5 places (Rule 15). Missing in the trail loop = stragglers left at the start point | `Functions/Formations/fn_groupAwakenForMarch.sqf` (new) + 6 call sites |
| 20 | 2026-11-15 | Lesson | `trailPath` indexes are NOT a uniform 2 m grid: a bridge crossing records ONE point spanning ~100 m. Resolve the seat BY ARC (`fn_trailIndexAtArc`), never by `offset / recordStep` | `Functions/Roads/fn_trailIndexAtArc.sqf` (new), `fn_formationsTrailQueueSync.sqf`, `fn_formationsGroupFollowTrail.sqf` |
| 21 | 2026-11-15 | Lesson | A queue enforces ORDER, never SPACING: forcing `frontIdx - 1` collapsed the column to consecutive points. Round arc->index to the NEAREST point, keep the arc-derived seat, use `-1` only as a collision guard | `fn_trailIndexAtArc.sqf`, `fn_formationsTrailQueueSync.sqf` |
| 22 | 2026-11-15 | Arch/Design | A trail column walks the trail POINT BY POINT: `trailCursorIdx` advances +1 on arrival, the seat is a CEILING not a destination. Fixes corner-cutting and makes the bridge crossing a consequence, not a special case | `fn_formationsGroupFollowTrail.sqf`, `fn_trailColumnSet.sqf` |
| 23 | 2026-11-15 | Lesson | A 1-index lane stutters (target = `cursor+1` + 1 s tick makes the AI brake every 2 m) and a doctrinal seat does not stop overtaking. Fix: cursor = POSITION (while loop over reached points), LOOK-AHEAD target, 0.35 s tick, catch-up scan, and `seat(k) = min(seat(k-1), doctrinal(k))` | `fn_formationsGroupFollowTrail.sqf`, `fn_formationsTrailQueueSync.sqf` |
| 24 | 2026-11-16 | Lesson | Two groups may NEVER share the same `trailOffsetDist`: the queue's `_gapIdx` floor (>= 1) turns a tie into a forced 2 m step. Trail compact gives each pair member its own arclength (+1 m) and reseeds `trailLaneTargetIdx` | `fn_formationsTrailCompactColumn.sqf`, `fn_formationsTrailQueueSync.sqf` |
| 25 | 2026-11-16 | Lesson | A stuck-group timeout must release to the SEAT (`min(_slotIndex, _maxIdx)`), never to `target+1` (retries the same failure) and never past the seat (breaks the queue's single-writer rule) | `fn_formationsGroupFollowTrail.sqf` |
| **PENDING-6** | 2026-11-16 | **OPEN Audit (PRIORIDAD)** | Globals used as receivers (`getOrDefault` / `forEach` / `select`) without `missionNamespace getVariable`. Tercera vez que aparece (Lecciones 26, 35): `fn_openSubordinateMenu` y `fn_commandMenusRefresh` corregidos, pero un grep inicial encontrÃ³ ~72 coincidencias en el proyecto. **Auditar fichero a fichero**: solo rompen en posiciÃ³n de RECEPTOR; el resto se deja con comentario. Grep: `FTCS_(Groups_Registry_Table|Company_Data|Platoons_Registry|Config)\s*(getOrDefault|select|forEach)` | todo `Functions/` |
| 27 | 2026-11-16 | Lesson + Arch/Design | The trail TRIM must cut against the OLDEST ARC THE COLUMN OCCUPIES (`trailMinSeatArc`, published by the queue), never against the doctrinal `maxTrailOffset`, and only in BATCHES (>=10 pts). A per-tick trim renumbers every persisted index continuously | `fn_trailTrimToArc.sqf` (new), `fn_trailAdvanceAnchor.sqf`, `fn_formationsTrailQueueSync.sqf`, `fn_trailColumnSet.sqf` |
| 29 | 2026-11-16 | Lesson | A column resolver must filter participants with the SAME predicate as the queue (`platoonId` + `movingMode == FOLLOWING_TRAIL` + `offset > 0`). `trailOffsetDist` survives a road march, so `offset > 0` alone let ghosts steal a pair and left the last two real teams uncompacted | `fn_formationsTrailCompactColumn.sqf` |
| 30 | 2026-11-16 | Lesson | The TRIM floor must protect the DEEPEST offset of the column INCLUDING WAITING groups (no seat yet), not only seated ones. A seated-only floor trimmed the trail to 83-99 pts (~170-200 m) while the column needs 217 m: the tail held 32 min and got a bogus seat | `fn_formationsTrailQueueSync.sqf`, `fn_trailTrimToArc.sqf`, `fn_trailColumnSet.sqf` |
| 31 | 2026-11-16 | Lesson | A stuck-group escape must skip ONE index, never jump to the seat: `move <seat>` is a pathfinding request, so Arma takes the shortest route and the group cuts across the track ("they overtake the whole file") | `fn_formationsGroupFollowTrail.sqf` |
| 32 | 2026-11-16 | Lesson | A memory bound may not depend on data published by a thread that runs AFTER it: the trim/record equilibrium capped the path at ~95 pts and starved the tail. Fix: registry-side guard + batch 20 + cushion 150 (seeded value must match the default) | `fn_trailTrimToArc.sqf`, `fn_trailColumnSet.sqf`, `fn_formationsGroupFollowTrail.sqf` |
| 33 | 2026-11-16 | Lesson | In a column compressed against the trail tip, SPACING must yield to ORDER: `frontSeat - gapIdx < 0` dropped the last group out of the column forever. Fallback = 1 index behind the car in front (logged), never HOLD | `fn_formationsTrailQueueSync.sqf` |
| 39 | 2026-11-20 | Lesson + Arch/Design | A platoon ORDER (follow mode REL/ABS + axis) is a registry fact per platoon, not a company-wide global; platoon = ORDER, group = EXCEPTION (`movingMode`) | `fn_registryInit.sqf`, `fn_applyCommandToTarget.sqf`, `fn_formationsGroupDoFollowCommander.sqf`, `fn_platoonAdvanceAxis.sqf`, `fn_platoonHaltRejoin.sqf`, `fn_menuGetState.sqf` |

---

## Lesson 1 â€” `continue` inside `forEach` breaks SQF compilation with "Error in expression / 0 elements provided, 3 expected"

**Date:** 2026-11-13
**Module:** `Functions/Targeting/fn_targetPersistentMarker.sqf` (Draw3D mission event handler)
**Symptom:**

- Recurring RPT error `Error in expression <...> / 0 elements provided, 3 expected`, always pointing at or near the `drawIcon3D` call that draws the squad-name caption (reported around "line 109" / "l109" in the RPT).
- The error **moved to different line numbers** (66 â†’ 73 â†’ 109) as guards and code were added/removed, which made it look like a data problem.
- The crash happened every frame, deterministically, ONLY when the Draw3D handler was re-spawned (e.g. after `targetClearAllSquads` wiped targets and a new capture re-created the handler). Moving/re-marking a target while the old handler was still alive worked fine.

**Wrong hypotheses we chased (and why they failed):**

1. "The marker position array is nil/partially cleared mid-frame" â†’ added `typeName`/SCALAR guards everywhere. Did NOT fix it: the failure happens at COMPILE time of the handler closure, before any guard can run.
2. "The engine is running an old version of the file" â†’ false; the RPT error line moved with our edits, proving the new file was loaded.
3. "`drawIcon3D` receives a 0-element array" â†’ the array literal was correct; the real problem was upstream in the same expression.

**Verified root cause (researched against the BI wiki, [continue - BI Community Wiki](https://community.bistudio.com/wiki/continue)):**

- The SQF keyword `continue` (introduced in Arma 3 v1.92) is **only supported in `while do`, `for do` and `do..while` loops**. It is **NOT supported inside `forEach` loops** â€” the [forEach](https://community.bistudio.com/wiki/forEach) wiki page documents no `continue` support either.
- When the SQF parser finds `continue` in a `forEach` body, it treats it as an orphan binary operator and **consumes the following expression** (in our case the `drawIcon3D [...]` array literal, whose parameters come in 3 groups â€” hence "3 expected") as its operands. The closure **fails to compile**, and because a `Draw3D` handler is recompiled/evaluated every frame, the error repeats every frame.
- This explains why the "fix" never worked regardless of runtime guards: **the guards were in code that never got to run**, because the enclosing closure could not even be compiled.

**The fix that worked (applied and verified in-game):**

- Rewrote the `forEach` body of the Draw3D handler as a cascade of **nested positive `if/then` blocks with NO `continue` at all**:

  ```sqf
  {
      // ...
      if (count _tgt >= 8
          && { typeName (_tgt select 1) == "STRING" }
          && { !((_tgt select 1) in ["any", "", "OBJECT"]) }) then {
          // ... field-level validations ...
          if (_impactOk && { _labelOk } && { _distanceOk }) then {
              // ... markerPos computation + final gate ...
              if (typeName _markerPos == "ARRAY"
                  && { count _markerPos == 3 }
                  && { typeName (_markerPos select 0) == "SCALAR" /* etc. */ }) then {
                  drawIcon3D [...];
              } else {
                  diag_log "REFUSED ...";  // instead of 'continue'
              };
          };
      };
  } forEach FTCS_Groups_Registry_Table;
  ```

- Rule of thumb: **inside `forEach`, use nested `if/then` (or an `if (...) then { ... } else { ... };` structure) to skip iterations â€” never `continue`.** `continue` is legal only in `while do` / `for do` / `do..while` loops (existing valid uses in this project: `fn_formationsGroupFollowTrail.sqf`, `fn_marchStuckWatchdog.sqf` â€” both `while` loops).

**Debugging meta-lesson:** when an SQF error keeps appearing at "the line of a big array literal" and moves around as unrelated code is edited, suspect a **parse/compile-level problem in the same expression or an earlier statement in the same closure** (orphan keyword, unbalanced brackets, binary operator misparse) â€” not a runtime data problem. Adding more runtime guards cannot fix a closure that never compiles.

---

## Lesson 2 â€” Mission-folder linker (`tools/LinkMission.ps1` + `LinkMission.bat`): NTFS Junctions + hardlinks keep ONE versioned codebase for every terrain

**Date:** 2026-11-13
**Type:** Architecture / Design Note (direct guide for an AI)
**Module:** `LinkMission.bat` (repo root) â†’ `tools/LinkMission.ps1`

**Problem it solves:**

- Arma 3 identifies each mission by `<MissionName>.<Terrain>` folder name, so testing the same FTCS codebase on a new terrain requires a NEW mission folder â€” and a NEW, terrain-specific `mission.sqm` that Eden refuses to share.
- Copying `Functions/`, `Doctrines/`, `init.sqf`, etc. into every mission folder would fork the codebase and pollute the GitHub history.

**Architecture ("repo without mission.sqm"):**

- The repo lives in ONE mission folder (currently `FTCS_Dev_Mission.Colleville`) and is the GitHub-versioned source of truth.
- `LinkMission.bat` (repo root) runs `tools/LinkMission.ps1`, which asks for the destination mission folder name and that mission's Eden-generated `mission.sqm`, then:
  1. Creates an NTFS **Junction** (no admin rights needed, unlike symbolic links) inside the destination mission folder for every SHARED item: `Functions`, `Doctrines`, `tools`, and hardlinks for shared files `description.ext`, `init.sqf`, `LinkMission.bat`. Editing code in EITHER folder edits the SAME files.
  2. Copies as REAL local files the per-mission exclusives: `mission.sqm` (each terrain keeps its own world).
- Existing destinations are handled safely: previous junctions are repositioned with `.Delete()` on the reparse point only (NEVER `Remove-Item -Recurse` through a junction â€” on PowerShell 5.1 it can traverse INTO the repo and delete the real codebase); real files/folders are only replaced after explicit user confirmation.

**Invariants an AI must NOT break:**

- NEVER delete a junction with recursive filesystem tools; delete only the link itself.
- `mission.sqm` must NEVER be linked/hardlinked into the repo â€” it stays a per-mission local copy (a generic mission.sqm breaks Eden loading on other terrains).
- Shared-item lists live in the `$SharedItems` / `$LocalFiles` arrays at the top of `LinkMission.ps1`; any new top-level shared folder or file of the project must be added there, or new missions will silently miss it.
- Workflow for a new terrain: 1) create+save the empty mission in Eden (generates its mission.sqm), 2) run `LinkMission.bat` from the repo, pointing at that mission.sqm.

---

## RULE 0 (POINT ZERO â€” ABSOLUTE DIRECTIVE) â€” Doctrine display names are FORBIDDEN as code identifiers

**Date:** 2026-11-14
**Status:** PERMANENT DIRECTIVE â€” every AI working on FTCS must follow this to the letter.
**Scope:** ALL functions, ALL modules, without exception.

**The directive:**

- Doctrine/display names ("1st Rifle Squad", "HQ - 1st Platoon (Support Element)",
  "2nd Rifle Squad - Rifle Team A", etc.) exist ONLY as historical/human-facing
  representation of the unit organization, for the player's benefit.
- They are **NEVER, UNDER ANY CIRCUMSTANCE, to be used as code identifiers**:
  no key lookups, no string prefix matching (`find`, `findIf`, `splitString`),
  no `in` checks, no tag comparisons against registry keys, group ids or
  namespace variable names. EVER.
- **Why:** registry keys built from `groupId` ARE doctrine display names in this
  project (`FTCS_Groups_Registry_Table` keys are `"2nd Rifle Squad - Rifle Team A"`).
  Matching them against synthetic prefixes such as `format ["SQD_%1_", _pltId]`
  NEVER matches (it silently yields zero results â€” no error, just missing
  participants, exactly the class of bug seen in `fn_platoonHaltRejoin.sqf`).
- **What to use instead (internal references ONLY):**
  - Group OBJECTS (`_grp`, `grpNull`-checked) resolved from the seeded registries
    (`FTCS_Platoons_Registry > pltId > "squads"`), never re-derived from names.
  - Registry-stamped LINK FIELDS written by `fn_registryInit`: `parentSquadGroup`
    (fireteam â†’ its squad group object) and equivalent hierarchy stamps. Family
    membership is resolved by OBJECT REFERENCE equality (`_grp in _squadList`,
    `_entry get "parentSquadGroup" == _sqdGrp`), never by name.
  - Numeric platoon IDs (`FTCS_Player_Platoon_ID`) for platoon-level state.
- **Hierarchy invariant (mandatory for EVERY movement/order function â€” platoon,
  squad, HALT, REJOIN, marches, formations):**
  1. The lieutenant is the platoon anchor; squads' LEADER groups occupy the
     lieutenant-assigned slots (0â€“12) and follow the lieutenant (REL/ABS).
  2. ALL other groups inside a squad follow their OWN SQUAD LEADER â€” never the
     lieutenant â€” with formation geometry preserved.
  3. Sole exception: groups explicitly re-assigned to a lieutenant-directed slot
     (e.g. scouts to slots 5/6/7/8/11/12) are temporarily anchored to the
     lieutenant, until re-anchored back to their squad leader.
  Any new function must be verified against this invariant before integration;
  a violation is a bug by definition.

**Enforcement:** before submitting any change, grep it for doctrine-name string
matching. If found, redesign using object references from the registry. There
are no exceptions.

---

## Lesson 3 â€” HashMap key order is NOT deterministic: "first team found" as the squad anchor silently misclassified squads as fireteams

**Date:** 2026-11-14
**Module:** `Functions/Core/fn_registryInit.sqf` (platoon registry seeding), `Functions/Formations/fn_platoonHaltRejoin.sqf` (HALT/REJOIN)
**Type:** Lesson + Architecture note

**Symptom (observed in-game, RPT 18:22:39 / 18:22:52):**

- `[FTCS][HALT] squad '<X>' : N fireteams collected` printed, as "squads", groups that are in fact FIREteams and HQ sub-teams:
  `1st Rifle Squad - BAR Support Team`, `HQ - 1st Platoon (Support Element)`, `3rd Rifle Squad - Rifle Team A`.
- After REJOIN, the slot that should sit behind the platoon leader appeared **in front of him**, and slots 9/10 ended up bunched behind the leader out of order, while slots 1/2/4 looked fine.
- The shift and rejoin bearings for the same group differed by a constant **+45Â°** (e.g. shift 247Â° vs rejoin 293Â°), and one group changed distance (38.8 m -> 18 m).

**Verified root cause:**

1. `fn_registryInit` resolved the squad-level anchor as **"the FIRST team yielded by iterating the squad's `tacticalTeams` HashMap"**:
   ```sqf
   { private _g = (_y) getOrDefault ["group", grpNull];
     if (!isNull _g) exitWith { _first = _g; }; } forEach _teams2;
   ```
   **SQF HashMap iteration order is NOT insertion order and is not guaranteed stable.** The "first" team is arbitrary â€” sometimes `TEAM_2` (a BAR support element), sometimes the HQ `Support Element`. That arbitrary group then became:
   - the entry in `FTCS_Platoons_Registry > pltId > "squads"`, i.e. what the platoon treats as a squad, **and**
   - the `parentSquadGroup` stamped on every team of that squad, i.e. what fireteams treat as their squad leader.
2. Consequence: HALT/REJOIN classified fireteams as squads. The real squad leader group appeared nowhere, so a fireteam received a platoon-slot re-anchor (`mvFormationShift`) while its siblings followed it as if it were the leader â†’ geometry collapsed around the leader.
3. The +45Â° discrepancy was a **second, independent bug**: the shift projected the anchor with `platoonAdvanceAxis`, and the rejoin re-projected it with `_rejoinFacing` computed from a value that had been rewritten in between. Two projections of the same offset with different axes.

**The fix (applied):**

- `fn_registryInit` now resolves the anchor **deterministically**, using the doctrinal `"type"` field that `fn_parseEditorGroups` already stamps on each team (`TEAM_1`/`TEAM_2`/`TEAM_3`/`COMMAND`):
  1. unified squad â†’ its `"group"`;
  2. multi-team â†’ the team whose type is `TEAM_1` (or `COMMAND`);
  3. the team whose `leader` is the squad's `"leader"` (name-free);
  4. HQ squads â†’ the `TEAM_3`/`GUIDE`/`SECURITY` element;
  5. parser's squad-level `"group"`;
  6. first resolved group (malformed doctrines only).
- Two new registry fields, seeded by the same pass and documented in `FTCS_Data_Structure_Reference.md`:
  - `"squadId"` â€” the doctrinal squad key (`"SQD_1_1"`), so teams can be grouped without reading the doctrine;
  - `"isSquadLeaderGroup"` â€” `true` **only** on the squad anchor.
- `fn_platoonHaltRejoin` now splits squad vs fireteam using those fields (`parentSquadGroup` + `isSquadLeaderGroup`), and a fireteam with no valid anchor is logged and skipped instead of being re-anchored to the lieutenant (Point 18 invariant).
- `continue` inside `forEach` was removed (Lesson 1) and replaced by a positive `if`.
- A `[FTCS][REGISTRY] plt N squads: ...` line now prints the resolved anchors at seed time, so this class of bug is visible in one glance.

**Meta-lesson for future code:**

- **Never** derive hierarchy membership from the iteration order of a HashMap, from "first element", or from `groupId` strings (Point 18). Derive it from an explicit field (`type`, `isSquadLeaderGroup`, `squadId`) seeded once at init.
- If a consumer needs identity data the registry does not carry, the fix is to **add the field in `fn_registryInit`** and document it â€” never to re-read `FTCS_Company_Data` at runtime (RULE 16).
- When two functions project the same geometry, they must use the **same** axis source (`fn_platoonAdvanceAxis`); otherwise the difference shows up as a constant angular offset.

---

## Lesson 4 â€” `leader _group` is NOT the doctrine commander: Arma 3 picks the group leader by its own rules

**Date:** 2026-11-14
**Module:** `Functions/Core/fn_registryInit.sqf` (`roleKey` seeding)
**Type:** Lesson

**Symptom (observed in RPT, registry identity dump):**

```
[FTCS][REGISTRY] anchor 'HQ - 1st Platoon (Command Element)' plt=1 squad=SQD_1_0 role='PLT_1_RADIO_OPERATOR'
```

The Command Element of the platoon HQ was registered with the **Radio Operator** as its doctrine role, while the platoon leader (`PLT_1_LEADER`) was the actual commander.

**Verified root cause:**

- The first implementation resolved `roleKey` by inverting the squad's `assignedRoles` map (`roleVar -> unit`) and matching against `leader _group`.
- **Arma 3 decides `leader _group` on its own** (leadership skill, seniority, insertion order). When a command group contains several doctrinal roles â€” the classic case is the platoon leader together with his RTO inside the same `Command Element` group â€” the engine may resolve the group leader to the RTO.
- Consequence: "the role of the group leader" â‰  "the role of command present in the group". They are two different questions and only the second one is what FTCS needs.

**The fix (applied):**

- `roleKey` is now the **highest-ranked doctrine role present in `units _group`**, resolved by iterating `assignedRoles` and keeping the role whose unit belongs to the group. Explicit priority:
  1. `PLT_<N>_LEADER` â†’ 100
  2. any `*_LEADER` (`SQD_<N>_<M>_LEADER`, ...) â†’ 80
  3. any `*SERGEANT` â†’ 60
  4. any other doctrine role â†’ 40
- Result: the Command Element now reports `role='PLT_1_LEADER'` even when the RTO is the engine-selected group leader.

**Why the player-driven platoon was never affected:**

- When the player IS the platoon leader, the code moves him out of the HQ group, and the follow pipeline identifies the commander through `isPlayer _leader` / `FTCS_Platoon_Leader_Unit â€” never through `roleKey`.
- The bug only becomes visible with an **AI platoon leader** (autonomous platoons) or at **company scale** (several platoons with their own AI lieutenants), which is exactly Etapa B of the project roadmap.

**Rules derived:**

1. Never infer a doctrinal rank from `leader _group`, `vehicleVarName`, or group membership order. Doctrine ranks come from `assignedRoles` and must be ranked explicitly.
2. When a field must answer "who commands here?", make sure the consumer also asks the right question: **current UI-driven platoon** â†’ `isPlayer` / `FTCS_Platoon_Leader_Unit`; **AI / company scale** â†’ `roleKey`.
3. Any registry field whose value can differ from the engine's own notion of leadership must say so in `FTCS_Data_Structure_Reference.md` â€” done for `roleKey`.

---

## Lesson 5 â€” The platoon leader lives in a DIFFERENT group than the doctrinal Command Element: group-level identity cannot answer "who commands the platoon"

**Date:** 2026-11-14
**Module:** `Functions/Core/fn_registryInit.sqf` (platoon registry), `roleKey` semantics
**Type:** Lesson + Architecture note

**Symptom:**

- After adding the rank-priority ranking to `roleKey` (Lesson 4) and re-testing, the log still showed:
  ```
  [FTCS][REGISTRY] anchor 'HQ - 1st Platoon (Command Element)' plt=1 squad=SQD_1_0 role='PLT_1_RADIO_OPERATOR'
  ```
- File timestamp (19:17:48) predated the session (19:20:48), so the new code WAS loaded. The fix was correct but had nothing to rank.

**Verified root cause (corrected by the 19:26:56 registry dump):**

The first hypothesis was "the player is detached from every group". The log disproved it:

```
[FTCS][REGISTRY] plt 1 leaderVar='PLT_1_LEADER' leaderName='' leaderGroup='Alpha 3-6' peerOnly=false
[FTCS][REGISTRY]   anchor 'HQ - 1st Platoon (Command Element)' plt=1 squad=SQD_1_0 role='PLT_1_RADIO_OPERATOR'
```

- The platoon leader IS inside a group (`peerOnly=false`), but that group is **`Alpha 3-6`, NOT the doctrinal `HQ - 1st Platoon (Command Element)`**.
- Root cause: in the composition the lieutenant is placed as a **standalone unit** (no `SQUAD_1_0_TEAM_x` editor group variable), so Arma 3 gives him an engine-generated group name (`Alpha 3-6`). `fn_parseEditorGroups` only links groups whose editor variable matches the doctrinal naming convention, so this group is **not** attached to the `SQD_1_0` element.
- Consequently `units (group of the Command Element)` contains only the RTO and the other HQ personnel, and the highest doctrine rank inside it is legitimately `PLT_1_RADIO_OPERATOR`.
- `roleKey` is therefore **correct by definition** ("highest doctrine role inside this group") but **cannot answer "who commands the platoon"** â€” that is a different question, asked at a different level.

**Why this does not break the current single-platoon build:**

- Consumers identify the commander through `isPlayer _leader` / `FTCS_Platoon_Leader_Unit`, never through `roleKey`.
- The registry now records the truth explicitly, so the anomaly is visible instead of silent.

**Open item (does NOT require a composition change now):**

- Whether the same split happens with AI lieutenants (and at company scale) is still unverified. The planned company-scale deployment test will show it in the `[FTCS][REGISTRY] plt N leaderVar=...` lines of every platoon: a lieutenant landing in an engine-named group (e.g. `Alpha 3-6`) instead of the Command Element means the composition places him outside his doctrinal element.

**The fix (applied):**

- Three new fields on the PLATOON entry (`FTCS_Platoons_Registry > pltId`), seeded by `fn_registryInit`:
  - `"leaderUnit"` â€” the `PLT_<N>_LEADER` unit (player or AI). Valid regardless of which group he belongs to. Falls back to the `PLT_<N>_LEADER` missionNamespace variable.
  - `"leaderGroup"` â€” `group leaderUnit`, or `grpNull` when he has no group at all.
  - `"peerOnly"` â€” `true` ONLY when `leaderUnit` is not inside `leaderGroup` (truly groupless). It does NOT mark "leader is in a non-doctrinal group": check `leaderGroup` against the platoon's `platoonGroup` for that.
- A `[FTCS][REGISTRY] plt N leaderVar=... leaderGroup=... peerOnly=...` log line makes the whole state visible at seed time.

**Rules derived (IMPORTANT for every future consumer):**

1. **"Who commands the platoon?"** â†’ read the PLATOON entry (`leaderUnit` / `leaderGroup` / `peerOnly`). Never `roleKey`, never `leader _group`.
2. **"Which doctrine role lives in this group?"** â†’ `roleKey` (group entry). Useful for squads/teams, NOT for the HQ command element in player mode.
3. **While `peerOnly == true`** consumers must keep using `isPlayer _leader` / `FTCS_Platoon_Leader_Unit` (today's working behaviour). `roleKey == "PLT_<N>_LEADER"` will also be true then, but the registry field is the stable source.
3b. `peerOnly == false` does NOT mean "the leader is in the doctrinal Command Element". Always compare `leaderGroup` with `platoonGroup` when the distinction matters.
4. Group-level identity and platoon-level identity are **different levels of the same model**. Mixing them is exactly how the HQ ended up reporting its RTO as commander.

---

## Lesson 6 â€” Phase 2 pattern: registry is the source of truth, the doctrine tree keeps a MIRROR until consumers are migrated

**Date:** 2026-11-14
**Module:** `Functions/Core/fn_registryInit.sqf` (`FTCS_Platoons_Registry`, `FTCS_fnc_registrySetPlatoon` / `registryGetPlatoon`)
**Type:** Architecture / Design Note (direct guide for an AI)

**What changed:**

Platoon STATE that used to live only in `FTCS_Company_Data > platoons > PLT_x` is now seeded into `FTCS_Platoons_Registry > pltId`:
`movementTechnique`, `roadPath`, `roadAnchor`, `trailAnchor`, `formationSlots`.

**The migration pattern (do NOT deviate from it):**

1. **Seed once, preserve runtime.** Each field is written in `fn_registryInit` only when the registry does not already carry it (`if (isNil { _existing get "field" })`). That keeps re-init non-destructive for runtime state written by the menus.
2. **Copy, do not reference.** `formationSlots` is copied (`+_slotsSrc`) because detached scouts mutate it at runtime. A shared reference would silently rewrite the doctrine map.
3. **Write through with the accessor.** New/edited writers must call:
   `[pltId, "movementTechnique", _v] call FTCS_fnc_registrySetPlatoon;`
   It writes the registry first and then mirrors into `FTCS_Company_Data` so consumers still reading the tree observe the same value.
4. **Read through the accessor.** New readers use `[pltId, "field", _default] call FTCS_fnc_registryGetPlatoon;` â€” registry first, doctrine fallback (safety net for fields not yet seeded).
5. **Never write the tree directly** for these fields from now on. The mirror exists only so Phase 3 can be done consumer-by-consumer with zero-downtime ordering.

**Architecture invariants an AI must NOT break:**

- `FTCS_Platoons_Registry` is keyed by the NUMERIC platoon id (1, 2, 3...), same key as HALT/REJOIN uses. Never mix STRING keys (`"PLT_1"`) into it.
- The doctrine mirror is TEMPORARY. When Phase 3 completes, `FTCS_fnc_registrySetPlatoon` must lose its mirror block and `registryGetPlatoon` its fallback (one edit, clearly marked `---- Doctrine mirror (temporary, removed in Phase 3)`).
- Any new platoon-level state field must be added to BOTH: this document (`FTCS_Data_Structure_Reference.md` Â§1) and the `[FTCS][REGISTRY] plt N state:` diagnostic line, so seeding problems are visible from the log.
- `roleKey` (group level) and the platoon `leaderUnit`/`leaderGroup`/`peerOnly` triple (platoon level) answer DIFFERENT questions â€” see Lessons 4 and 5.

---

## Lesson 7 â€” `!expr isEqualTo value` parses as `(!expr) isEqualTo value` â†’ "Error !: Type String, expected Bool"

**Date:** 2026-11-14
**Module:** `Functions/Movement/fn_movementBoundTeams.sqf` (Phase 3 rewrite)
**Type:** Lesson

**Symptom (RPT).** During the Phase 3 self-test the script aborted with a runtime type error pointing at the comparison inside `fn_movementBoundTeams`, and the `F3 BOUND` lines never appeared:

```
Error !: Type String, expected Bool
```

**Verified root cause.** SQF's unary `!` binds BEFORE the binary operator, so this line:

```sqf
if (!(_anchorEntry getOrDefault ["squadId", ""]) isEqualTo _sqdKey) then { ... };
```

is parsed as `((! (<string>)) isEqualTo <string>)`. `!` is the logical NOT and requires a BOOLEAN: applying it to the STRING returned by `getOrDefault` raises the type error at runtime. Note that the parenthesised call does NOT help: the parens wrap the call, not the comparison.

**The fix (applied).** Parenthesise the WHOLE comparison, never just the left operand:

```sqf
private _anchorSquad = _anchorEntry getOrDefault ["squadId", ""];
if (!(_anchorSquad isEqualTo _sqdKey)) then { _anchorRef = _squadRef; };
```

**Rules derived.**

1. `!A isEqualTo B` is ALWAYS a bug in SQF. Write `!(A isEqualTo B)`.
2. The same trap exists with `!=`: `A != B` is a numeric comparison and coerces; prefer `!(A isEqualTo B)` for strings, hashmaps and objects.
3. Guard against it structurally: when a negated comparison sits on a value read with `getOrDefault`, materialise the value into a `private` first (as above). It reads better and removes the ambiguity entirely.
4. A syntax-only checker (`verify_syntax.ps1` balances braces/brackets/parens) CANNOT catch this: the file is syntactically valid, it fails at RUNTIME on the first evaluation. Only an in-game self-test or the RPT reveals it â€” which is why every migration step needs a runtime self-test that executes the new code paths.

---

## Lesson 8 â€” Doctrine is a SEED, not a contract: separate the immutable template from the live state

**Date:** 2026-11-14
**Module:** `Functions/Core/fn_applyDoctrine.sqf`, `Functions/Formations/fn_formationsApplyPlatoonOrder.sqf`
**Type:** Architecture / Design Note (direct guide for an AI)

**The problem this settles.**

Platoon formation slots come from the doctrine composition (`platoonFormationSlots` in the active doctrine data). Two very different things were being conflated:

1. **What the doctrine says the platoon SHOULD look like** â€” the slot -> squad mapping authored in 3DEN.
2. **What the platoon ACTUALLY looks like right now** â€” the same mapping after scouts detached, after a squad was wiped, or (future) after the player re-ordered squads.

Reading (1) at runtime makes (2) impossible: every runtime mutation would have to rewrite the doctrine, which must never happen.

**The model now in force (two fields, two lifecycles):**

| Field | Location | Written by | Mutability | Purpose |
|---|---|---|---|---|
| `doctrineFormationSlots` | `FTCS_Platoons_Registry > pltId` | `fn_applyDoctrine` ONLY (at seed time) | **Immutable** | The template. Reset target. |
| `formationSlots` | `FTCS_Platoons_Registry > pltId` | `fn_registryInit` (seed) + runtime writers (`fn_applyCommandToTarget` scouts, future re-order) | **Live / mutable** | What consumers read. |

- Both are **copied** (`+_hash`), never referenced, so mutating the live map can never leak into the template.
- `fn_formationsApplyPlatoonOrder` falls back to `doctrineFormationSlots` when the live map is empty (e.g. after a scout sweep) â€” still a registry read, never the doctrine tree.
- **No runtime function reads `activeDoctrineData` any more.** Verified by grep across `Functions/`.

**Why the doctrine tree still exists (do NOT delete it):**

1. **Seed**: `fn_applyDoctrine` + `fn_parseEditorGroups` build it once and project it into the registry.
2. **UI captions**: doctrinal names ("2nd Rifle Squad") are shown to the player. Point 18 forbids them as IDENTIFIERS, not as labels.
3. **Reset source of truth**: `doctrineFormationSlots` originates there.

It is the **blueprint**, not the building. `FTCS_Company_Data` answers *"what was planned"*; the registry answers *"what exists and what it is doing now"*.

**How to implement the future features (do NOT touch the doctrine):**

| Feature | Where it goes |
|---|---|
| "2nd squad goes in the lead slot" | write `formationSlots` (registry) |
| "Reset to doctrinal layout" | `formationSlots = +doctrineFormationSlots` |
| "A fireteam was wiped out" | mark its registry entry (e.g. `combatEffective = false`); do NOT remove it from the doctrine |
| "Reassign a team to another squad" | write `squadId` + `parentSquadGroup` in the group entry |

**Invariants an AI must not break:**

- Never write `doctrineFormationSlots` outside `fn_applyDoctrine`.
- Never make a runtime consumer read `doctrineFormationSlots` as the CURRENT layout â€” it is the template.
- Never mutate the doctrine tree in runtime; if a value must change during the mission, it belongs in the registry.
- When adding a new doctrine-derived field, seed BOTH: the template (immutable) and the live value (mutable), and document both here.

---

## Lesson 9 â€” Migrating a consumer: REMOVE every use of the old variable, or it becomes an undefined reference

**Date:** 2026-11-14
**Module:** `Functions/Interactions/fn_applyCommandToTarget.sqf` (scout detachment)
**Type:** Lesson

**Symptom (in game).** Every scout option reported:

```
[SCOUT DETACHMENT] Warning: <role> has no separate scout fireteam to detach.
```

even though the squads clearly had fireteams.

**Verified root cause.**

During Phase 8b the block that located the squad was migrated from

```sqf
private _targetSquadData = <doctrine squad hashmap>;   // REMOVED
```

to

```sqf
private _targetSquadId = <registry "squadId">;         // NEW
```

but **downstream code still used `_targetSquadData`**:

```sqf
private _tacticalTeams = _targetSquadData getOrDefault ["tacticalTeams", createHashMap];
```

`_targetSquadData` no longer existed, so `_tacticalTeams` silently became an **empty HashMap** (SQF does not error on an undefined variable inside `getOrDefault`, it just yields the default). The team list was empty â†’ no scout team found â†’ the warning. The same stale variable existed in a second block (trail march scout reset).

**Why the syntax checker did not catch it.** The file was perfectly balanced; an undefined LOCAL variable is a runtime concern, not a syntax one.

**The fix (applied).**

Both scout blocks now resolve the squad from the registry:
- the squad's groups = every entry whose `"squadId"` matches;
- the scout element = the first of those that is NOT `"isSquadLeaderGroup"`;
- the parent re-compaction list = the ANCHOR first, then the remaining fireteams (anchor order matters: `fn_formationsTypeSquadSet` treats element 0 as the leader).

**Rules derived.**

1. When migrating a block, **grep the whole function for the removed variable name immediately after the edit** (`_targetSquadData|_tacticalTeams|_teamKeys`). Do it before running, not after the bug report.
2. `getOrDefault` on an undefined variable **fails silently** â€” it hides the mistake. Prefer materialising shared lookups (squad groups, team lists) in ONE place and passing them down.
3. Any list where element 0 must be the Squad Leader must be built as **anchor first, then teams**, never from an unordered HashMap iteration.
4. `isNotEqualTo` does not exist in SQF (see Lesson 7): write `!(A isEqualTo B)`.

---

## Lesson 10 â€” Recalling a detached scout must restore its FULL squad state, not just the attachment

**Date:** 2026-11-14
**Module:** `Functions/Interactions/fn_applyCommandToTarget.sqf` (scout recall), `Functions/Formations/fn_platoonHaltRejoin.sqf` (fireteam self-heal)
**Type:** Lesson

**Symptom (in game, reproducible sequence):**

1. Detach a scout to slot 11 â†’ OK.
2. HALT â†’ move â†’ REJOIN â†’ the scout returns to its scout slot â†’ OK.
3. **Recall the scout** (`PLT_SCOUT_REJOIN_ALL` / "Rejoin all scouts") â†’ it goes back into its squad â†’ OK.
4. Move a little â†’ HALT â†’ move â†’ REJOIN â†’ **the recalled scout jumps in FRONT of the platoon leader** instead of following its squad.

**Verified root cause.**

The recall path only rewrote part of the scout's registry state:

| Field | After recall (old code) | Consequence |
|---|---|---|
| `movingMode` | set to follow mode | OK |
| `teamAttachment` | `SQUAD_BOUND` (only in the trail branch) | OK |
| `allocationSlot` | **still 5/6/7/8/11/12** | HALT/REJOIN gather still sees a platoon slot |
| `parentSquadGroup` | possibly `grpNull` (cleared while adopted by the slot) | fireteam branch cannot find its squad |

With a stale `allocationSlot` and a null parent, the next HALT/REJOIN falls into the squad/detached branch and re-anchors the team relative to the **lieutenant**, which is exactly the "in front of the leader" symptom.

**The fix (applied).**

1. **Recall (`PLT_SCOUT_REJOIN_ALL` and the per-squad trail recall)** now performs a **full state reset** on every recalled team:
   - `movingMode` â†’ follow mode
   - `teamAttachment` â†’ `"SQUAD_BOUND"`
   - `allocationSlot` â†’ `-1`
   - `parentSquadGroup` â†’ the squad anchor (self-reference for the anchor, its own anchor for fireteams)
   The anchor is resolved from `squadId` + `isSquadLeaderGroup`, never from names.
2. **`fn_platoonHaltRejoin` self-heals**: if a fireteam reaches the REJOIN with a null `parentSquadGroup` but a valid `squadId`, it rebuilds the link from the registry before deciding how to re-anchor, and logs `anchor self-healed`.

**Rules derived.**

1. A lifecycle transition must reset **every** field that describes the OLD state. "Detached" is not one flag: it is a combination (`movingMode` + `teamAttachment` + `allocationSlot` + `parentSquadGroup`). Reset them together, in one place.
2. Any consumer that branches on `allocationSlot in [5,6,7,8,11,12]` will misfire while a stale slot lingers. Clearing it is part of leaving the detached state.
3. Defensive self-healing at the consumer (`squadId` -> anchor) is cheap and makes the system recover from lost links instead of silently anchoring to the wrong leader.
4. Test the FULL cycle, not a single transition: detach â†’ HALT/REJOIN â†’ recall â†’ move â†’ HALT/REJOIN. The bug only appears on the second REJOIN.

---

## Lesson 11 â€” "Pick the first matching group" is a bug: doctrine must DECLARE the scout team (`tacticalRole = "SCOUT"`)

**Date:** 2026-11-14
**Module:** `Doctrines/Data/*.sqf`, `Functions/Core/fn_registryInit.sqf`, `Functions/Interactions/fn_applyCommandToTarget.sqf`
**Type:** Lesson + Architecture note

**Symptom (in game).**

Detach a scout â†’ OK. Recall it â†’ OK. Detach **again** â†’ a **different fireteam** gets sent to the scout slot.

**Verified root cause.**

The Phase 8b migration replaced

```sqf
private _teamKeys = keys _tacticalTeams;  _teamKeys sort true;
_scoutTeamKey = _teamKeys select 1;        // deterministic: TEAM_2
```

with

```sqf
{ ... _squadFireteams pushBack [_key, _g]; ... } forEach FTCS_Groups_Registry_Table;
_scoutGroup = (_squadFireteams select 0) select 1;   // HashMap order = NOT stable
```

`FTCS_Groups_Registry_Table` is a HashMap, so `select 0` returned a different fireteam on different runs. The doctrine *did* name the team (`"Scout Team"` in `teamStructure`), but that name is a DISPLAY name and Point 18 forbids using it as an identifier â€” and `teamRoles` only had `ASSAULT`/`SUPPORT`, so the information was not machine-readable.

**The fix (applied, option 1).**

1. **Doctrine declares the role.** `teamRoles` now marks the scout team:
   ```sqf
   ["teamStructure", ["Rifle Team A", "Scout Team", "Rifle Team B", "BAR Support Team"]],
   ["teamRoles",     ["ASSAULT",     "SCOUT",     "ASSAULT",    "SUPPORT"]],
   ```
   This is a semantic value, not a composition change (no units, groups or slots move). It turns an implicit convention into an explicit datum.
2. **Registry carries it.** `fn_registryInit` projects each team's `"tacticalRole"` into its group entry.
3. **Selection is deterministic.** `fn_applyCommandToTarget` picks the scout by `tacticalRole == "SCOUT"`, with two deterministic fallbacks:
   - the team whose key is `<squadId>_TEAM_2` (doctrine order), then
   - the only fireteam, when a squad has exactly one.
4. **Self-test** prints, per squad, how many fireteams exist and which one carries `SCOUT`, so a doctrine that forgot the role is visible in the log immediately.

**Rules derived.**

1. Any "pick one of N" over a HashMap is a latent non-determinism bug (this is Lesson 3 applied to selection, not to anchors).
2. When a doctrine concept exists only as a display name, **promote it to an enum value** in the data template (here `teamRoles`) rather than reading the name at runtime.
3. Always provide a deterministic fallback, so an un-updated doctrine degrades predictably instead of randomly.
4. Self-test the selection, not just the data: report "how many candidates" and "which one won".

---

## Lesson 12 â€” `parsedSquads` is built AFTER the doctrine: a field stamped in `fn_applyDoctrine` never reaches the runtime team objects

**Date:** 2026-11-14
**Module:** `fn_applyDoctrine.sqf`, `fn_parseEditorGroups.sqf`, `fn_registryInit.sqf`
**Type:** Lesson + Architecture note

**Symptom.** After adding `["teamRoles", ["ASSAULT","SCOUT","ASSAULT","SUPPORT"]]` to the doctrine and projecting `"tacticalRole"` in `fn_registryInit`, the scout detachment STILL reported "no separate scout fireteam".

**Verified root cause â€” the pipeline order matters:**

```
fn_applyDoctrine      â†’ builds FTCS_Company_Data > platoons > PLT_x > squads
                        (+ doctrine template teams with "tacticalRole")
fn_parseEditorGroups   â†’ CREATES "parsedSquads" FROM SCRATCH, one entry per
                        editor group, each team hash built as a NEW HashMap
                        WITHOUT "tacticalRole"
fn_registryInit        â†’ reads parsedSquads > team > "tacticalRole"   â† EMPTY
```

1. `fn_applyDoctrine` **never creates `parsedSquads`** (grep: 0 hits). It only creates `squads` and `squadsRegistry`.
2. `fn_parseEditorGroups` builds `parsedSquads` later and **overwrites** every team hash, so any field the doctrine put there is lost.
3. Therefore every attempt to read `"tacticalRole"` from `parsedSquads` returns `""`, and the selector falls back â€” or, before the fallback existed, found nothing at all.

**The fix (applied).**

- `fn_applyDoctrine` now stores the resolved doctrine roles as a plain INDEX â†’ ROLE array:
  `FTCS_Company_Data set ["doctrineTeamRoles", _teamRoles];`
  (an array, not a name lookup: `["ASSAULT","SCOUT","ASSAULT","SUPPORT"]`).
- `fn_registryInit` resolves each team's role by its **ordinal in the `TEAM_<N>` type**:
  `parseNumber ((_teamType splitString "_") select 1)` â†’ `doctrineTeamRoles select (_ordinal - 1)`.
  No display names, no HashMap iteration order (Point 18 compliant).
- `fn_parseEditorGroups` keeps writing `"tacticalRole", ""` with a comment explaining that the role is resolved later, so the field exists in the team hash but is never mistaken for the source of truth.

**Rules derived.**

1. **Check the pipeline order before adding a field.** `parsedSquads` is a RUNTIME structure built by the parser; the doctrine template lives in `squads`. A value written to one is not visible in the other.
2. When two functions build overlapping structures, the LAST writer wins. Add the field where the *last* writer can compute it, or pass it through a parallel, stable structure (here: an index array on `FTCS_Company_Data`).
3. Index-based projection (`teamRoles[i]` â†” `TEAM_(i+1)`) is deterministic and name-free â€” prefer it over matching team display names.
4. Always log the raw source (`doctrineTeamRoles=...`) in the self-test: it distinguishes "the doctrine has no SCOUT" from "the projection lost it".

---

## PENDING-1 â€” Company scale: each AI platoon needs its own follow loop and formation management

**Date:** 2026-11-14
**Status:** OPEN â€” decision required BEFORE writing any new company-scale feature.
**Type:** Architecture / Design Note (direct guide for an AI)
**Scope:** every movement / formation / order function.

**The open question.**

Migration phases 1â€“8 put `"platoonId"` on every group entry and `leaderUnit` / `leaderGroup` / `peerOnly` / `squads` on every platoon entry, so the data for multiple platoons already EXISTS. **No consumer uses it per platoon yet.** Almost everything still resolves the platoon with:

```sqf
private _pltId = missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1];
```

**To decide (when company scale starts):**

1. Does EVERY AI platoon run its own `fn_formationsGroupDoFollowCommander` threads and its own `fn_formationsApplyPlatoonOrder` pipeline? (Yes is the natural answer: the loops are already per-group, only the reference leader and the axis are global.)
2. Do the platoon-scoped globals become per-platoon entries in `FTCS_Platoons_Registry`?
   - `FTCS_Platoon_Follow_Mode` â†’ `registrySetPlatoon [pltId, "followMode", ...]`
   - `FTCS_Platoon_Advance_Direction` / `FTCS_Platoon_Fixed_Abs_Dir` / `FTCS_Last_Commander_Dir` â†’ per-platoon axis fields
   - `FTCS_Platoon_Phase_<N>` (already per platoon) â†’ plus registry mirror
3. What is the company-level anchor? The captain orders a platoon to a position; the platoon then runs its own local formation around its own lieutenant.

**Hard rule for any new code written before this is decided:**

- Accept the platoon id as a PARAMETER when it is available, and only fall back to `FTCS_Player_Platoon_ID` when it is not.
- Never bake `FTCS_Player_Platoon_ID` into a new function's core logic.
- Never read a per-platoon global directly if a registry field can carry it.

---

## PENDING-2 â€” Long-cycle verification of the scout state machine (VERIFIED / CLOSED)

**Date:** 2026-11-14
**Status:** âœ” CLOSED â€” verified in game. The scout state machine is correct over the full lifecycle.
**Type:** Verification checklist (kept as a regression baseline)

**What was verified:** a single scout deployment works, the scout menu finds the correct team (Lesson 12 fix), AND the full long-cycle below was exercised successfully in game.

**Lifecycle checks (all PASSED in game):**

1. **Three consecutive deploy cycles** â†’ the SAME team detached each time (Lesson 11 non-determinism regression).
2. **HALT â†’ move â†’ REJOIN after a recall** â†’ the recalled team rejoins its OWN squad, never in front of the lieutenant (Lesson 10 regression).
3. **Road march with detached scouts** â†’ column forms correctly, scouts re-chain.
4. **Trail march with detached scouts** â†’ trail chain forms correctly.
5. **Recall (`PLT_SCOUT_REJOIN_ALL`) then HALT/REJOIN** â†’ full state reset holds (`allocationSlot = -1`, `parentSquadGroup` intact).
6. **Mixed case:** squad A with scouts detached + squad B without â†’ only A's scout slots affected.

**Keep this list as a REGRESSION BASELINE:** re-run it after any future change to
`fn_applyCommandToTarget` (scout branch), `fn_platoonHaltRejoin`, `fn_registryInit`
(hierarchy fields) or the doctrine `teamRoles`.

**What to look for in the RPT if a future regression appears:**

- `[FTCS][SELFTEST] SCOUT ... scoutRole=... -> PASS` in every combat squad
- `[FTCS][REJOIN] <grp> anchor self-healed from squadId ...` (means the parent was lost and recovered)
- `[FTCS][REJOIN] <grp> (fireteam) SKIPPED: no parentSquadGroup anchor ...` (means the self-heal failed â€” this is a BUG, not a valid state).

---

## SESSION LOG 2026-11-14 â€” HALT/REJOIN fix + full RULE 16 migration

**Status:** CLOSED. All work below is applied, verified in game and documented.
**Purpose:** resume context for the next session WITHOUT re-reading the whole chat.
**Read this first. Then read Lessons 1â€“12.**

### 1. Why this session started

`fn_platoonHaltRejoin` produced wrong positions: slot 0 appeared in front of the
platoon leader, slots 9/10 bunched behind him, while slots 1/2/4 were fine.

### 2. The THREE real root causes (all fixed)

| # | Cause | Lesson |
|---|---|---|
| 1 | `fn_registryInit` picked the squad anchor as "the first team found" iterating a HashMap. HashMap order is NOT stable, so fireteams (BAR support, HQ support) became "squads" and received platoon-slot re-anchors. | 3 |
| 2 | KEEP wrote the frozen axis to `Advance_Direction` / `Last_Commander_Dir` but NOT to `Fixed_Abs_Dir`, so REJOIN-KEEP was a **no-op in ABS mode**. | (documented in fn header) |
| 3 | Scout detachment / recall left STALE state (`allocationSlot` still 5/6/7/8/11/12, `parentSquadGroup` null) so the next REJOIN classified a recalled team as a platoon element and anchored it to the lieutenant. | 10 |

### 3. What was built (migration phases)

| Phase | Result |
|---|---|
| 1 Identity | `squadId`, `isSquadLeaderGroup`, `platoonId`, `roleKey`, and platoon-level `leaderUnit`/`leaderGroup`/`peerOnly` |
| 2 Platoon state | `movementTechnique`, `roadPath`, `roadAnchor`, `trailAnchor`, `formationSlots`, `currentPhase` in `FTCS_Platoons_Registry`; accessors `FTCS_fnc_registrySetPlatoon` / `registryGetPlatoon` |
| 3 Consumers | debug worker, subordinate menu, `movementBoundTeams`, `formationsApplyPlatoonOrder`, `applyCommandToTarget` (writes) |
| 4 Readers | `targetMark`, `platoonSetOperationalPhase` |
| 5 Order helpers | `_fnc_getPlatoonSquadInfo`, `_fnc_getAllPlatoonSquads` |
| 6 Geometry | `formationsCurrentPositionSet` (two-tier capture from registry) |
| 7 Doctrine template | `doctrineFormationSlots` (immutable) vs `formationSlots` (live) |
| 8 Runtime complete | all 12 runtime reads of `parsedSquads` migrated; mirror removed for mutable fields |
| 9 Team roles | `teamRoles` declares `"SCOUT"`; `doctrineTeamRoles` index array; `tacticalRole` in registry |

**14 files migrated. No runtime function reads mutable doctrine data any more.**
The doctrine tree remains as: seed, UI captions, and the reset template.

### 4. Rules established this session (quick reference)

- `continue` is illegal inside `forEach` (Lesson 1).
- Never derive hierarchy from HashMap order (Lesson 3).
- `leader _group` is NOT the doctrine commander (Lesson 4/5).
- `!A isEqualTo B` is a syntax-and-runtime trap â†’ `!(A isEqualTo B)` (Lesson 7).
- Doctrine is a SEED, not a contract; mutations go to the registry (Lesson 8).
- Migrating code: grep the removed variable â€” `getOrDefault` on an undefined var fails SILENTLY (Lesson 9).
- Recalling a detached group must reset its FULL state (Lesson 10).
- "Pick the first matching group" is a bug; declare the role in doctrine (Lesson 11).
- `parsedSquads` is built AFTER `fn_applyDoctrine` (Lesson 12).

### 5. Self-tests written (run automatically at mission start)

Search the RPT for `[FTCS][SELFTEST]`:
`PHASE 2..7 ACCEPTANCE`, `SCOUT ROLE ACCEPTANCE`. Every check prints PASS/FAIL/SKIP.
These are the fastest way to confirm the registry seeded correctly in a new mission.

### 6. OPEN ITEM â€” read PENDING-1 before any new feature

**PENDING-1**: company scale. Each AI platoon needs its own follow loop and
formation management. The registry data already exists (`platoonId`,
`leaderUnit`, per-platoon state), but NO consumer uses it per platoon yet â€”
everything still resolves `FTCS_Player_Platoon_ID`. Rule for new code: accept
the platoon id as a parameter whenever available.

`PENDING-2` (scout long-cycle verification) is CLOSED and kept as a regression baseline.

### 7. Still to build (nothing started)

Dynamic cover (Fn 1), heavy-weapons/SBF (Fn 2), auto-ammunition (Fn 3),
tactical messengers (Fn 4), tactical map/OPORD, map position degradation,
company mode.

---

## Lesson 13 â€” Diagnostics go behind a sentinel; only real failures log always. Plus: `surfaceIsWater` is TRUE on a bridge deck

**Date:** 2026-11-14
**Module:** project-wide (Rule 19 of the design notes), `fn_trailAdvanceAnchor.sqf`, `fn_formationsGroupFollowTrail.sqf`
**Type:** Lesson + Architecture note

### Part A â€” Debug Sentinel Policy (now Rule 19 in the design notes)

**Problem.** During the bridge investigation the RPT was flooded with per-frame and per-tick traces (`[TGT-MARKER] Drawing marker ...`, `[ROAD][FOLLOW] ...` every 5 s per group). The single line that mattered was buried among thousands.

**Policy (normative, applies to every future change):**

| Level | Sentinel | Used for | Prefix |
|---|---|---|---|
| **ALWAYS** | none | aborts, failed validations, impossible states, recovered errors | `***` in the message |
| **DEBUG** | `FTCS_Debug_Mode` (default `true`) | state telemetry: who participates, what values are read, what was decided | none |
| **TRACE** | `FTCS_Debug_Mode` **and** `FTCS_Debug_Trace` (default `false`) | per loop step / per tick / per group / per frame | none |

Boot traces (`init.sqf`, `fn_executeDeployment`, `fn_loadDoctrineData`, `fn_spawnDoctrine`, `fn_parseEditorGroups`, `fn_applyDoctrine`, `fn_initCompanyCommand`) may stay unconditional: few, once per session, and they prove the system started.

**Why a conditional is fine.** A boolean check costs nothing next to the `diag_log` it protects. Production software keeps its logging code and turns the level down; deleting diagnostics just forces someone to rewrite them next time.

**Rule of thumb:** if the trace would be read while debugging a normal (working) system, it is DEBUG/TRACE. If it can only mean "something is wrong", it is ALWAYS.

### Part B â€” `surfaceIsWater` reports the TERRAIN cell, not what stands on it

**Symptom.** In trail march, followers piled up at both ends of a bridge. Traces showed:

```
[FTCS][TRAIL][RECORD] leader recorded a point ON WATER: [3428.58,5826.5,9.51]
[FTCS][TRAIL][FOLLOW] *** 'Mortar Section' trail slot is ON WATER - AI cannot path there (bridge gap).
```

Yet the player confirms he walked **on the bridge deck**, never into the water, and the trail points rise from Zâ‰ˆ3.6 to Zâ‰ˆ12 across the crossing.

**Verified cause.** `surfaceIsWater` samples the water cell of the **terrain** below the position. A bridge deck is an object placed ABOVE the water cell, so `surfaceIsWater` returns **`true`** for a unit standing on the bridge. Using it alone to reject "unwalkable" trail points therefore rejects every bridge crossing.

**Correct test â€” height-aware:**

```sqf
// "really in the water" = surface is water AND the unit is at water level.
// On a bridge the Z is several metres above the water cell -> NOT in water.
private _onWater = surfaceIsWater _pos
    && { ((_pos select 2) - (getTerrainHeightASL [_pos select 0, _pos select 1])) < 1.5 };
```

**Rules derived.**

1. `surfaceIsWater` alone is NOT a walkability test. Always pair it with a height comparison when bridges, piers, fords or elevated roads are possible.
2. A trail/anchor that records points it will later be followed into must record only **traversable** points, and "traversable" must be defined by the same rule the AI will apply.
3. When followers pile up on BOTH sides of a feature, suspect the anchor/path rather than the followers: they are being sent somewhere unreachable.
4. Long-offset groups can look healthy while short-offset ones fail (their sample lands on land). Always compare short vs long offsets before blaming the geometry.

---

## Lesson 14 â€” `nil` inside an array COLLAPSES the array (and deleting a registry key leaves a stale read)

**Date:** 2026-11-14
**Module:** `Functions/Movement/fn_formationsTrailQueueSync.sqf`, `fn_formationsGroupFollowTrail.sqf`
**Type:** Lesson

**Symptom (RPT, two errors around lines 60 and 99).** The trail queue sync raised
`Error Undefined variable` / index-out-of-range at

```sqf
private _myPos = _x select 2;
```

even though every entry had been pushed with three elements.

**Verified root cause.**

```sqf
private _pos = _entry getOrDefault ["trailTargetPosPrevious", nil];
_entries pushBack [_x, _off, _pos];
```

Arma **collapses `nil` inside an array literal**: `[a, b, nil]` becomes `[a, b]`.
The entry therefore had TWO elements whenever the group had no previous slot, and the
later `select 2` failed. This is the same engine rule already documented inside
`fn_registryInit.sqf` (the `FTCS_fnc_registrySet` comment about the 2-argument form) â€”
it was simply not applied to this new code.

**Second, silent bug in the same design.** `FTCS_fnc_registrySet` treats `nil` as
"DELETE the key". Publishing `nil` for "nothing to inherit" therefore left the PREVIOUS
tick's value in place, so a consumer could read a stale slot.

**The fix (applied).**

- Store "no slot" as an explicit EMPTY ARRAY, never `nil`:
  ```sqf
  private _pos = _entry getOrDefault ["trailTargetPosPrevious", []];
  if (!(_pos isEqualType []) || { count _pos < 3 }) then { _pos = []; };
  _entries pushBack [_x, _off, _pos];        // always 3 elements
  ```
- Publish the same G2 shape to the registry:
  ```sqf
  [_grpId, "trailQueueInheritPos", []] call FTCS_fnc_registrySet;   // not nil
  ```
- Consumer test becomes type-based instead of nil-based:
  ```sqf
  private _hasInherit = (_inheritedPos isEqualType [] && { count _inheritedPos >= 3 });
  ```

**Rules derived.**

1. **Never let `nil` reach an array literal.** Use `[]`, `grpNull`, `objNull`, `-1` or a
   sentinel â€” whatever keeps the element count stable. A collapsed array is invisible
   until a `select` on a later index blows up far from the cause.
2. **Never use `nil` as a registry value when the key must survive.** The setter deletes
   on `nil`; the reader then returns the value written in a previous tick, which looks
   like a working system that is simply out of date.
3. When an array element can be "absent", define the absent representation explicitly in
   the function header (here: `[]` = no previous slot / nothing to inherit).
4. This is the third `nil`-related trap in this session (Lesson 7 `!A isEqualTo B`,
   Lesson 9 undefined variable via `getOrDefault`, and this one). Treat every
   `getOrDefault [_k, nil]` in new code as a bug until proven otherwise.

---

## Lesson 15 â€” Trail column crossing a CUT (bridge / gap / clearance): the record freeze IS the barrier, and the queue must chain by DOCTRINAL gap

**Date:** 2026-11-15
**Module:** `Functions/Movement/fn_formationsTrailQueueSync.sqf`, `Functions/Roads/fn_trailAdvanceAnchor.sqf`, `Functions/Formations/fn_formationsGroupFollowTrail.sqf`
**Type:** Architecture / Design Note (direct guide for an AI)

### The mechanism (do NOT "fix" it)

Arma 3 cannot reliably produce a pathable point on a bridge deck: a group sent
there ends up swimming underneath. FTCS therefore treats a crossing as a **cut in
the walked trail**:

```
fn_trailAdvanceAnchor  ->  [_leaderPos, 0.5] call FTCS_fnc_navIsValidGround
                           dz > 0.5 m  ->  DO NOT RECORD, trailHalted = true
```

While the leader is on the deck (`trailPath`) simply **stops growing**, and it
resumes only when he reaches walkable ground on the far bank. This is DELIBERATE:
`trailPath` must contain ONLY points the leader really walked on walkable ground,
so `trailPath[i]` is always a valid AI destination. **The freeze is the barrier.**
Any change that interpolates points across the cut (or that records elevated
points) reinstates the swimming bug for the whole column.

### The queue (fn_formationsTrailQueueSync)

```
maxIdx = (count trailPath) - 1                    // last recorded point = near bank

front to back, ordered by trailOffsetDist ASCENDING (never allocationSlot):

  natural_k = round(trailOffsetDist_k / recordStep)

  * natural_k <= maxIdx and no car is waiting yet  -> ALREADY ACROSS (population A)
    This pass writes nothing for it; the normal follower loop owns its seat.

  * otherwise                                      -> IN QUEUE (latch: once one car
    waits, everything behind it waits)
        first car  : seat = maxIdx              (near bank - valid ground)
        every next : seat = seat(front) + round((d_k - d_front) / recordStep)
        if seat > maxIdx -> seat = maxIdx       (wait at the bank, never over the cut)
```

Published fields: `trailQueueIndex` (seat, `-1` = none), `trailQueueHasSeat`
(boolean), `trailQueueTipIdx` (`maxIdx`). `trailSlotIndex` is **not** written
here (single-writer rule).

### Why "copy the seat of the car ahead" is WRONG

Two cars with different footprints (a 2-man HQ cell in front of an 8-man squad)
lose their spacing: the squad inherits the cell's seat and its front overlaps the
cell's rear, so the engine compresses the column. The correct rule is to chain by
the **doctrinal distance between the two offsets** (`trailOffsetDist`), which was
fixed once by `fn_trailColumnSet`. That is why a car's advance is NOT a constant
for the column: a big squad advances further than a small cell, and that is what
keeps the spacing intact. Recomputing the gap from live `units` counts during a
crossing is wrong for the same reason (casualties must not compact the column).

### PROGRESSIVE RELEASE: each group waits for ITS OWN depth (do not break this)

The anchor is seeded with **one** point (`[[leaderPos, 0]]`) and grows as the
leader walks. A march ordered close to a bottleneck can reach it with only a few
points recorded, so the groups deeper than the trail have no place to go.

That state is NOT "the cut is open". Dragging those groups to the last recorded
point (`maxIdx`) makes the WHOLE platoon walk to the leader and leave its slots
empty - observed twice in game, first with `maxIdx = 0` (everyone onto the seeded
point) and then with `maxIdx = 4` (everyone onto the leader's fresh track).

**The rule (chosen by the designer): progressive release.**

```
can_move(k)  <=>  seat(k) <= maxIdx        # its own depth has been walked
```

- `fn_formationsTrailQueueSync` publishes `trailQueueHasSeat = false` and `-1` for
  any car whose computed seat exceeds `maxIdx`, and does NOT advance the chain for
  it: the next car chains from the last car that really holds a seat, so a waiting
  car can never be overtaken.
- `fn_formationsGroupFollowTrail` **holds** such a group with `doStop` where it was
  placed - no move, no path, no speed change - and only starts walking once the
  trail reaches it.

The column therefore forms in cascade behind the leader, exactly like the original
`headDist < trailOffsetDist + 2` waiting state, and NO group is ever sent to a
point that is merely "the newest one".

> Attempted and REJECTED: gating the whole column on `headNatural` ("nobody moves
> until car 1 fits"). It looks equivalent but is not: car 1 is often the nearest
group, so it fits almost immediately and the condition never fires while every car
behind is still dragged onto `maxIdx`. The gate must be PER CAR.

### Invariants an AI must not break

1. `trailPath` is written ONLY by `fn_trailAdvanceAnchor`, and only with points
   that pass `fn_navIsValidGround` (dz <= 0.5 m).
2. `fn_formationsTrailQueueSync` reads the trail from the ANCHOR
   (`FTCS_Trail_Anchor_PLT_<id> > "trailPath"`). A global `FTCS_Trail_Path` does
   not exist; reading one silently yields `maxIdx = -1` and "no seat" forever.
3. Column order for the queue is `trailOffsetDist` ascending. `allocationSlot`
   belongs to the platoon formation (rewritten by the road column and by scout
   detachment) and does not follow the trail order.
4. The queue is a LATCH: the waiting population is always a contiguous tail of the
   column. Never release a rear car while a car in front of it waits.
5. "Nothing to inherit" is `-1` in a numeric field, never `nil` (Lesson 14) and
   never a removed key (removing a hashmap key shifts every later key).

### Still to do (known, open)

- `fn_formationsGroupFollowTrail` does not consume `trailQueueHasSeat` /
  `trailQueueIndex` yet: it still resolves every group by its own natural index,
  so the queue is published but not obeyed. Consuming it is the next step.
- `fn_formationsTrailCompactColumn` rewrites `trailOffsetDist` without telling the
  queue; it must re-derive the chain (or be ordered between crossings).

---

## Lesson 16 â€” `private _x = <nil>` does NOT create the variable: `isEqualType` cannot guard a `nil`-returning getter

**Date:** 2026-11-15
**Module:** `Functions/Formations/fn_formationsGroupFollowTrail.sqf`, `Functions/Core/fn_registryInit.sqf` (`FTCS_fnc_registryGet`)
**Type:** Lesson

### Symptom (RPT)

```
Error in expression <_registryGet;
    private _inQueueEarly = ((_queueFlagEarly isEqualType true) && { _queueFlagEarl...>
  Error position: <_queueFlagEarly isEqualType true>
Error Undefined variable in expression: _queueflagearly
```

reported at the *declaration* line, i.e. one line ABOVE the reported one, and only
on the first tick of a trail march (3 groups = 3 errors, then silence).

### Verified root cause

`FTCS_fnc_registryGet` ends with:

```sqf
_entry getOrDefault [_key, nil];
```

so an ABSENT key returns **nil**. In SQF,

```sqf
private _queueFlagEarly = <nil>;      // the variable is NOT created
private _inQueueEarly = (_queueFlagEarly isEqualType true);   // Undefined variable
```

Assigning `nil` leaves the variable **undeclared**. Any guard placed on the next
line â€” including `isEqualType`, which is the usual idiom â€” never runs, because the
read of the variable itself is what fails. The error is deterministic: the trail
queue thread starts AFTER the follow threads, so on the first tick the key does
not exist yet.

### The fix (applied)

Materialise every `nil`-capable read with `isNil` before use:

```sqf
private _queueHasSeat = [_groupID, "trailQueueHasSeat"] call FTCS_fnc_registryGet;
if (isNil "_queueHasSeat") then { _queueHasSeat = false; };
```

Applied to `trailQueueHasSeat` (false), `trailQueueIndex` (-1) and
`trailSlotIndex` (-1) in `fn_formationsGroupFollowTrail`.

### Rules derived

1. `isEqualType` / `typeName` guards are USELESS against `nil`: they are evaluated
   on a variable that does not exist. Guard with `isNil` FIRST, then type-check.
2. Every `call FTCS_fnc_registryGet` whose result is stored must be paired with an
   `isNil` default. Reads placed directly inside a comparison (`(... call X) == "Y"`)
   are safe; stored reads are not.
3. This is Lesson 9 (a getter that silently yields a default) escalated: there the
   default was an empty HashMap, here it is `nil`, and `nil` breaks the scope itself.
4. Prefer `getOrDefault [_key, <default>]` at the CONSUMER (reach into the entry
   once) over a getter that returns `nil`, when the default is known locally.

---

## Lesson 17 â€” `allocationSlot` ascending is NOT the column order: road and trail must walk the SAME explicit slot list

**Date:** 2026-11-15
**Module:** `Functions/Formations/fn_trailColumnSet.sqf`, `Functions/Formations/fn_formationsRoadColumnSet.sqf`
**Type:** Lesson

### Symptom (in game)

The trail column did not follow the road-column order: the RTO (`HQ - Command
Element`, slot 9) walked near the TAIL, and the 1st Rifle Squad's BAR Support Team
led the file. Confirmed from the RPT seat dump:

```
'1st Rifle Squad - BAR Support Team'  natural=1     <- head of the file
'HQ - Command Element'                natural=126   <- eighth
```

### Verified root cause

`fn_trailColumnSet` ordered the chained groups with:

```sqf
_slot = <registry "allocationSlot">;   _chained pushBack [_slot, _gid, _x];
_chained sort true;                    // ascending by allocationSlot
```

`allocationSlot` is the PLATOON FORMATION slot index, not a march position. The
road column does not use it for ordering either: `fn_formationsRoadColumnSet`
walks an explicit doctrine list:

```sqf
private _slotOrder = [9, 0, 4, 1, 2, 3, 10, 5];
// 9 HQ Escort (RTO) -> 0 Vanguard -> 4 Plt Sgt -> 1 -> 2 -> 3 -> 10 Guide -> 5 Reserve
```

Ascending `allocationSlot` therefore produces `0,1,2,3,4,5,9,10`: slot 0 first and
slot 9 (the RTO) almost last. The two columns were never the same column.

### The fix (applied)

`fn_trailColumnSet` now resolves each position with the SAME list:

```sqf
private _slotOrder = [9, 0, 4, 1, 2, 3, 10, 5];
private _rank = _slotOrder find _slot;
if (_rank < 0) then { _rank = 999; };   // 6/7/8 (forward scouts), no slot -> tail
```

Slots 6/7/8 are excluded exactly as the road column excludes them (they advance
ahead of the leader). Groups without a listed slot keep their relative order at the
tail, so nothing is dropped from the file.

### Rules derived

1. **"Same order as the road column" means the same `_slotOrder` array**, not "sort
   by some numeric field". If the list ever changes in one function it must change
   in the other, and the list should eventually live in ONE place.
2. A registry field named `allocationSlot` answers "where in the platoon formation
   is this group", which is a different question from "where in the march file".
   Never use one as a proxy for the other.
3. When a consumer "does not respect the order", check the PRODUCER of the ordering
   (`trailOffsetDist` here) before the consumer that reads it. The queue and the
   follower were faithfully reproducing a wrong sequence.

---

## PENDING-5 â€” `_slotOrder` is duplicated between the road and trail column functions

**Date:** 2026-11-15
**Status:** OPEN â€” refactor, NOT a bug. Do it when the road column is next touched.
**Type:** Architecture / Design Note (direct guide for an AI)
**Scope:** `Functions/Formations/fn_formationsRoadColumnSet.sqf`, `Functions/Formations/fn_trailColumnSet.sqf`

### The duplication

The march order of the column lives in two identical literals:

```sqf
// fn_formationsRoadColumnSet.sqf:42   and   fn_trailColumnSet.sqf  (_slotOrder)
private _slotOrder = [9, 0, 4, 1, 2, 3, 10, 5];
//                     HQ Escort (RTO) -> 0 -> 4 -> 1 -> 2 -> 3 -> 10 -> 5
```

Both are correct today (Lesson 17), so there is no functional bug. The risk is
**drift**: the day the march doctrine changes and only one of them is edited, the
road and trail columns silently put different groups in the same position of the
file â€” the exact class of bug that took a full session to diagnose.

### The planned fix

1. New function `FTCS_fnc_columnSlotOrder` (module `Formations`) returning the list
   (and, optionally, accepting an "include scouts" flag for a future use case).
2. Register it in `description.ext` under `CfgFunctions > Formations` â€” **this
   requires leaving the mission, passing through 3DEN and re-entering**, because
   `description.ext` is not recompiled by an in-game restart.
3. Replace both literals with `private _slotOrder = call FTCS_fnc_columnSlotOrder;`.
4. Document the single source in `FTCS_Data_Structure_Reference.md` if the list is
   ever exposed through a registry field (it is doctrine, so it may belong in the
   platoon registry as `columnSlotOrder`, immutable, seeded once).

### Invariant until then

If either list is edited, **both must be edited in the same change**. Grep
`_slotOrder` before submitting.

---

## Lesson 18 â€” A trail index must be measured FROM THE FRONT (`maxIdx - offset/step`), exactly like the road samples `headDist - offsetDist`

**Date:** 2026-11-15
**Module:** `Functions/Movement/fn_formationsTrailQueueSync.sqf`, `Functions/Formations/fn_formationsGroupFollowTrail.sqf`
**Type:** Lesson

### Symptom (in game)

The trail column appeared REVERSED: the groups closest to the leader were sent
furthest back and the tail walked near the commander. The order in the registry was
verified correct (offset 1 = RTO, offset 133 = Guide), so the error was in the
index, not in the ordering.

### Verified root cause

The seat was computed as a distance from the ORIGIN of the trail:

```sqf
private _naturalIdx = round (_offsetDist / _recordStep);   // WRONG
```

`trailPath` grows from the march start (index 0) to the leader (last index), so
`offset / recordStep` addresses a point the leader walked `offset` metres after
starting - not a point `offset` metres BEHIND him now. With 36 recorded points, the
RTO (offset 1) was sent to index 1: what the leader walked 70 m ago.

### The correct rule (already implemented by the road column)

```sqf
// fn_formationsGroupFollowRoad.sqf:147
_sample = [(_headDist - _offsetDist) max 0, _dynPath] call _fnc_samplePathAtDistance;
```

In index form:

```sqf
private _maxIdx = (count _trailPath) - 1;
private _seat   = _maxIdx - round (_offsetDist / _recordStep);
```

`seat >= 0` means the leader has already walked that depth (the group may move);
`seat < 0` means it has not (the group HOLDS where it was placed). This single
expression replaces both the "distance from origin" bug and the earlier
"progressive release" clamp.

### Rules derived

1. Whenever a trail/road position is derived from a distance behind the leader,
   **subtract from the FRONT** (`headDist` for arcs, `maxIdx` for indexes), never
   add to the origin. Both column systems must use the same convention.
2. Before inventing a rule, read the sibling implementation that already works
   (`fn_formationsGroupFollowRoad` is the reference for every column behaviour).
3. A "reversed column" symptom points at an inverted distance reference, not at the
   sorting of the column: verify the ORDER (offsets/slots) before touching the math,
   then verify the SEAT (index) with one concrete distance.

---

## Lesson 19 â€” Waking a group for a march is ONE function (`fn_groupAwakenForMarch`), not an inline AI block in every loop

**Date:** 2026-11-15
**Module:** `Functions/Formations/fn_groupAwakenForMarch.sqf` (new), `fn_formationsApplyPlatoonOrder.sqf`, `fn_formationsGroupFollowRoad.sqf`, `fn_formationsGroupFollowTrail.sqf`, `fn_applyCommandToTarget.sqf` (x2), `fn_platoonSetOperationalPhase.sqf` (x3)
**Type:** Lesson + Architecture note

### Symptom (in game)

After ordering a TRAIL column the platoon stayed frozen: the leader walked and the
squads remained at the start point, some catching up minutes later, others never.
A second, structural problem surfaced while investigating: FIVE places in the code
base repeated their own `enableAI "PATH"/"MOVE"` + `disableAI ...` block, which
Rule 15 (Point 0) forbids ("at most three native AI commands per site; any change in
unit behaviour goes through a standardised project function").

### Verified root cause

The platoon is deployed into the assembly area with movement AI frozen so the
deployment can be inspected. Only `fn_formationsApplyPlatoonOrder` (cross-country)
re-enabled it, inline. Road march, trail march, the command dispatcher and the
phase setter each carried their own COPY of that block - and the trail loop had
none at all, so `move` / `doFollow` were issued to sleeping units and ignored.

Copying the block into the trail loop (what was done first) fixed the symptom but
multiplied the violation.

### The fix (applied)

1. New `Functions/Formations/fn_groupAwakenForMarch.sqf`:

   ```sqf
   [_grp, _followUnit, _setColumnFormation] call FTCS_fnc_groupAwakenForMarch;
   // per unit: enableAI "PATH"; enableAI "MOVE";
   //           disableAI "AUTOCOMBAT"; disableAI "COVER"; doFollow _followUnit;
   // optionally: _grp setFormation "COLUMN"
   ```

   It is the ONLY place in FTCS that issues those AI commands. TARGET, ROE, speed
   mode, stance and radio protocol are deliberately left to the existing group
   setters (`groupSetAwareMode` / `groupSetROE` / `groupSetSpeed` / `groupSetStance`).

2. Every former inline block now calls it:
   - `fn_formationsApplyPlatoonOrder` (phase < 3) - `false` (keeps the ordered formation)
   - `fn_formationsGroupFollowRoad` - `true` (column), then adds TARGET/RADIOPROTOCOL/forceSpeed
   - `fn_formationsGroupFollowTrail` - `true` (column), then adds RADIOPROTOCOL/forceSpeed
   - `fn_applyCommandToTarget` (road + trail branches)
   - `fn_platoonSetOperationalPhase` (phases 1/2/3) - `false`

3. Registered in `description.ext` under `CfgFunctions > Formations`.

### Rules derived

1. **`disableAI "MOVE"` in the deployment is the reason a march needs a wake-up.**
   A new march world that forgets it will look like a navigation bug (groups never
   leave the start point) when it is an AI-state bug.
2. **Never write `enableAI` / `disableAI` in a loop or a march routine.** Call
   `FTCS_fnc_groupAwakenForMarch`. Grep `enableAI "MOVE"` before submitting: it must
   appear only inside that file.
3. When a march profile needs more than the awakener (no TARGET, no radio, engine
   speed cap), add it AT THE CALL SITE next to the tick that depends on it, not by
   growing the shared function.
4. Adding a function to `description.ext` requires leaving the mission, passing
   through 3DEN and re-entering: an in-game restart does not recompile CfgFunctions.
---

## Lesson 20 â€” `trailPath` indexes are NOT a uniform 2 m grid: a bridge crossing records ONE point spanning ~100 m

**Date:** 2026-11-15
**Module:** `Functions/Roads/fn_trailIndexAtArc.sqf` (new), `fn_formationsTrailQueueSync.sqf`, `fn_formationsGroupFollowTrail.sqf`
**Type:** Lesson

### Symptom (in game)

After a bridge crossing the whole rear half of the column stayed behind: the Scout
Team of the 2nd Squad, all four groups of the 3rd Squad and the Platoon Guide never
received a position. The head of the column walked across correctly.

### Verified root cause (RPT)

```
trail RESUMED at [3398.27,5846.52] dz=0.25
[FTCS][TRAIL][RECORD] LARGE STEP 108.4m at point 55 -> segment spans water/props
```

While the leader is on the deck `fn_trailAdvanceAnchor` records NOTHING (by
design). When it resumes it appends **at most one point per tick**, so the whole
108 m crossing became a SINGLE segment. `headDist` grew by 108 m but `maxIdx` grew
by exactly 1 (54 -> 55).

The seat was computed as

```sqf
seat = maxIdx - round (offset / recordStep);   // ASSUMES 2 m PER INDEX
```

so every group deeper than ~110 m got a negative seat and waited forever:

| group | offset | seat |
|---|---|---|
| HQ Command Element (RTO) | 1 | +54 |
| 2nd Rifle Squad B | 135 | -13 |
| 3rd Rifle Squad (x4) | 173..227 | -32..-59 |
| Mortar Section / Guide | 243..265 | -67..-78 |

The leader had already finished walking, so those seats could never rise: the
groups were orphaned permanently.

### The fix (applied)

An index cannot be derived by division. It must be resolved **by arc** on the real
polyline, exactly like the road column does with
`sample(headDist - offsetDist)`:

```sqf
// Functions/Roads/fn_trailIndexAtArc.sqf
[_trailPath, _targetArc] call FTCS_fnc_trailIndexAtArc;
```

The function walks the polyline summing the REAL `distance2D` between consecutive
points and returns the index of the point on the SAFE side of the requested arc:

- before point 0 -> 0
- between points i and i+1 -> **i** (the EARLIER one)
- past the last point -> last index

Rounding BACK is deliberate: the later point may sit on the far side of a crossing,
so rounding forward would push a group across the gap. No interpolation is done, so
every returned index is still a point the leader really stood on.

Callers updated:
- `fn_formationsTrailQueueSync`: `natural = trailIndexAtArc(trail, headDist - offset)`,
  negative -> HOLD; the order cap also resolves by arc instead of `frontIdx - gap/step`.
- `fn_formationsGroupFollowTrail`: `_naturalIdx` resolved the same way.

### Rules derived

1. **Never divide a distance by `recordStep` to obtain a trail index.** The trail is
   not a uniform grid: any tick where the recorder was halted (elevated ground) or
   the frame rate dropped produces a long segment.
2. `headDist` (arc, real metres) is the only distance measure that survives a jump.
   Indexes are a way to ADDRESS points, not a unit of length.
3. When resolving an arc that falls inside a segment, pick the EARLIER point for a
   walked track (safe ground) and interpolate only for a geometric path (a road
   centreline). The two column systems legitimately differ here.
4. A "column half stuck after a bottleneck" symptom should immediately prompt
   checking `maxIdx` growth against `headDist` growth in the RPT.---

## Lesson 21 â€” A chain that RE-SPACES the column destroys it: round to the NEAREST trail point, and let order be the only constraint

**Date:** 2026-11-15
**Module:** `Functions/Roads/fn_trailIndexAtArc.sqf`, `Functions/Movement/fn_formationsTrailQueueSync.sqf`
**Type:** Lesson

### Symptom (in game)

Every slot marker appeared drawn point on point, with no distance between them,
and the tail of the column never received a seat. RPT seat dump:

```
off=1    -> seat=52
off=14   -> seat=51
off=33   -> seat=50
off=46   -> seat=49
off=68   -> seat=48
off=84   -> seat=47
off=103  -> seat=46
off=122  -> seat=45
```

Thirteen to nineteen metres of doctrinal spacing collapsed into ONE index (2 m).

### Verified root cause (two errors that compound)

1. **The chain re-spaced the column.**

   ```sqf
   if (_frontIdx >= 0 && { _seat >= _frontIdx }) then {
       _seat = _frontIdx - 1;      // ALWAYS exactly one index behind
   };
   ```

   Enforcing order by forcing `frontIdx - 1` guarantees a 2 m step regardless of the
   gap the doctrine assigned. The chain's job is ORDER, not spacing.

2. **The arc resolver rounded BACK.**

   ```sqf
   if (_targetArc < (_arcAtPoint + _segLen)) exitWith { _j };   // always the earlier point
   ```

   With 2 m spacing and a downward round, the arc-derived seat of the NEXT car lands
   on the same index as the previous one, so the `>= frontIdx` branch fired for
   EVERY car and the `-1` became the real spacing.

### The fix (applied)

`fn_trailIndexAtArc` now returns the NEAREST point of the segment:

```sqf
if ((_targetArc - _arcAtPoint) <= (_arcAtNext - _targetArc)) then { _j } else { _j + 1 }
```

`fn_formationsTrailQueueSync` keeps the arc-derived seat untouched and uses
`frontIdx - 1` ONLY as a collision guard (two offsets rounding to the same point):

```sqf
private _seat = _natural;                       // full doctrinal spacing
if (_frontIdx >= 0 && { _seat >= _frontIdx }) then { _seat = _frontIdx - 1; };
```

### Rules derived

1. **A queue enforces order; it must never compute spacing.** Spacing comes from
   the doctrine (`trailOffsetDist` â†’ arc â†’ index). If a chain step is needed, the
   column was mis-spaced upstream - fix that, do not compress it here.
2. **When snapping a distance to a discrete grid, round to the nearest**, unless the
   brand new value is unsafe (mid-crossing). Rounding in one direction accumulates
   error down a chain; per-group rounding error is at most half a step.
3. After any change to a seat formula, read the RPT dump as a sequence: if the seats
   are `n, n-1, n-2, ...` the spacing is being computed, not preserved. Correct
   spacing shows seat differences proportional to the offset differences.
---

## Lesson 22 â€” A trail column must walk the trail POINT BY POINT (cursor), not jump to its seat

**Date:** 2026-11-15
**Module:** `Functions/Formations/fn_formationsGroupFollowTrail.sqf`, `fn_trailColumnSet.sqf`
**Type:** Architecture / Design Note

### The problem this settles

A trail march exists for ONE reason: every group steps on the exact points the
leader walked, in the same order. Forwarding a group straight to its seat index
(`_group move trailPath[seat]`) cannot guarantee that. The engine paths from the
group's current position to that single point, so when the seat advances several
indexes at once the group takes the SHORTEST route: it cuts corners, crosses
diagonals and misses recorded points entirely.

Observed in game: the column walked beside the leader's track instead of on it,
and nothing marked the recorded points as visited.

### The model (the "lane")

Each group holds a CURSOR in the registry: the last trail point it has really
reached.

```sqf
cursor(k)  : last index reached (writer: fn_formationsGroupFollowTrail)
seat(k)    : ceiling published by the column (fn_formationsTrailQueueSync)
next(k)    = min(cursor + 1, seat, maxIdx)      // ONE point ahead, never more
```

Every tick the follower sends `move` to `trailPath[next]`. The cursor advances
only when the group's leader actually arrives:

```
arriveDist = max(1.5, segmentLength * 0.35)
```

The threshold is proportional because a segment is normally 2 m but a bridge
crossing records ONE segment of ~100 m - a fixed 1.5 m would never be reached.

### Why the bridge needs no special case any more

While the trail is cut, `maxIdx` does not grow, so `cursor + 1` does not exist and
the group simply holds its point on the near bank. When the leader records the
first point on the far side, `cursor + 1` exists and the group is asked to walk
THAT single real segment, which the engine resolves over the deck. One group per
new point, front to back, with no queue state required to stop anything: the trail
itself is the barrier.

### Invariants

1. `trailCursorIdx` is written ONLY by `fn_formationsGroupFollowTrail` and seeded
   to `-1` by `fn_trailColumnSet` on every new order (a leftover index would point
   into a re-seeded array).
2. The seat is a CEILING, never a destination.
3. The cursor never jumps more than one index per tick, so no point can be skipped
   unless the 20 s timeout fires (logged with `***`, it is a real failure).
4. A group whose ceiling equals its cursor is not "stuck": it is waiting its turn.
   The timeout must not fire in that state.

### Still to do

- Port the same lane to the road column (ROAD), where `roadPath` plays the role of
  `trailPath` and `roadOffsetDist` the role of the seat. NOT started.
---

## Lesson 23 â€” A 1-index lane stutters, and a doctrinal seat does not stop overtaking

**Date:** 2026-11-15
**Module:** `Functions/Formations/fn_formationsGroupFollowTrail.sqf`, `Functions/Movement/fn_formationsTrailQueueSync.sqf`
**Type:** Lesson

### Symptom (in game)

Two symptoms, both introduced by the point-by-point lane of Lesson 22:

1. **The column started and stopped every 2 m** ("walks 2 m, stops; walks 2 m,
   stops"). It crawled, far slower than the leader.
2. **Groups overtook each other** when one could not find a path: the one behind
   walked past it.

### Root causes

1. **One index per tick is a pedometer, not a position.**

   The follower target was `cursor + 1` and the loop ticked at **1 s**. A soldier
   covers ~1.4 m in a second, so the 2 m target was never reached before the next
   tick re-issued `move` to the same point. Every `move` restarts the AI's path, so
   the group visibly braked, re-accelerated, braked again.

2. **The seat ceiling was doctrinal only.**

   `fn_formationsTrailQueueSync` capped a car with `frontIdx - 1` (Lesson 21
   removed that because it destroyed the spacing), leaving the cap purely
   doctrinal - each car's own arc. When the car in front stalled, the car behind
   still had its own (larger... smaller) seat available and simply walked past.

### The fix (applied)

**Fluidity**

- The cursor is now a POSITION, advanced by a `while` over every recorded point the
  group leader is within reach of (`2.5 m`, scaled to `segLen * 0.35` for long
  bridge segments). It can jump several indexes in one tick.
- The walk target is a LOOK-AHEAD: `cursor + 3`, capped by the seat and `maxIdx`.
  The group always has open ground ahead, so the engine keeps one continuous path.
  The cursor still consumes every point in order, so no corner can be cut.
- Tick reduced from **1 s to 0.35 s**.
- CATCH-UP: if the group is more than 12 m from the point its cursor names (it was
  placed elsewhere at order time, or it lagged while the trail grew), the cursor
  scans the following 60 indexes and jumps to the nearest one. Without it a group
  50 m from index 0 could never satisfy the reach test and stayed pinned forever.

**Order**

```sqf
seat(k) = min( seatDoctrinal(k), seat(k-1) )
```

A car may never reach beyond the ceiling of the car in front. While the column
flows, the doctrinal seat is the smaller value, so the `min` is a no-op and the
spacing is untouched; during a blockage it bites and the car behind WAITS instead
of overtaking.

### Rules derived

1. A per-tick cursor must be bounded by REAL progress, not by tick count. Measure
   position, then derive the index.
2. Always aim a few steps ahead (look-ahead) when the target is a dense point
   sequence: aiming at the next point makes the agent brake at every point.
3. Re-issuing `move` to the point the agent is already standing on is the classic
   stutter: the target must be ahead of the current position whenever one exists.
4. ORDER between agents in a chain is a `min` with the neighbour's CEILING, not a
   re-derivation of the spacing. Spacing comes from doctrine; order comes from the
   neighbour.
5. Any index-based cursor needs a CATCH-UP rule, because the agent's start position
   and the trail origin are unrelated.

---

## Lesson 24 â€” Two groups may never share the SAME `trailOffsetDist` (queue `_gapIdx` floor turns a tie into a forced 2 m step)

**Date:** 2026-11-16
**Module:** `Functions/Formations/fn_formationsTrailCompactColumn.sqf`, `Functions/Movement/fn_formationsTrailQueueSync.sqf`
**Type:** Lesson

### Symptom (static-review finding, not yet seen in a live RPT)

`fn_formationsTrailCompactColumn` paired teams and gave BOTH members of a pair the
SAME `trailOffsetDist` (the first member's), relying on `trailShoulderOffset`
(`Â±0.75 m`) to place them abreast. In the queue that tie cannot survive:

```sqf
// fn_formationsTrailQueueSync.sqf
private _gapIdx = ceil ((_off - _frontDist) / _recordStep);
if (_gapIdx < 1) then { _gapIdx = 1; };     // <- the floor
...
private _maxSeat = _frontSeat - _gapIdx;
```

With `_off == _frontDist`, `_gapIdx = 0` and the floor forces **1 index (~2 m)**
behind the car in front, so the second lane is parked one recorded point back
instead of marching abreast - the compact does not look like a double lane. It
also makes the NEXT pair's gap smaller than doctrine (the chain measures from a
member whose real arclength was fake), compressing the whole file.

### The rule

`trailOffsetDist` is the queue's ordering AND spacing key. It must be **unique per
group inside a column**. A lateral/shoulder layout earns its effect from
`trailShoulderOffset` only; it may NOT express "same depth" through a tie.

### Correct implementation (applied)

```sqf
// distinct arclengths inside the pair window
_entry set ["trailOffsetDist", _cursor + (_memberRank * _pairStep)];  // _pairStep = 1.0
_entry set ["trailShoulderOffset", (_pairHalfSeparation * _side)];    // +/-0.75 m
_entry set ["trailLaneTargetIdx", -1];   // new, LOWER ceiling -> re-pick first point
```

1 m of longitudinal split is invisible (12 % of one recorded step) yet keeps the
queue arithmetic exact, so the pair keeps `_gapIdx = 1` naturally instead of by
clamp.

### Related rules derived

1. Any function that REWRITES `trailOffsetDist` must reseed `trailLaneTargetIdx = -1`
   for the groups it touches: the lane target is a ceiling-bound index and the new
   ceilings are lower, so a stale target makes the group renew BACKWARDS.
2. Groups that do NOT participate in a compaction must lose any stale
   `trailShoulderOffset`, or they stay displaced from a previous layout.
3. Footprint for a compact chain is the NOMINAL headcount model
   `(men - 1) * 3 + 8` (same as `fn_trailColumnSet`), never the MEASURED
   `leader -> rearmost` distance: the latter describes current dispersion, so a
   team still spread out inflates the depth and pushes the column back.

---

## Lesson 25 â€” A stuck-group timeout must release to the SEAT, not to `target + 1`

**Date:** 2026-11-16
**Module:** `Functions/Formations/fn_formationsGroupFollowTrail.sqf`
**Type:** Lesson

### Symptom (static-review finding)

Trail lane timeout after 20 s:

```sqf
_targetIdx = (_targetIdx + 1) min _maxIdx;   // WRONG
```

The group is stuck ON `_targetIdx` (an unreachable point: inside a building, on a
rock). Moving the target ONE index ahead asks it for the next unreachable point,
so the timer fires again 20 s later: the group inches forward one index at a time.
Worse, `_targetIdx` could run PAST the seat, and the clamp

```sqf
_slotIndex = (_targetIdx min _maxIdx) max 0;
```

then replaced the QUEUE's ceiling with the loop's own guess - the single-writer
rule (queue owns the seat) was broken from the follower.

### Correct implementation (applied)

```sqf
private _releaseIdx = (_slotIndex min _maxIdx) max 0;
_targetIdx = _releaseIdx;   // straight to my seat, never beyond it
```

The seat already exists in `trailPath` (the queue only publishes real indexes),
so releasing there is always legal; the group skips the offending point and
re-joins the column. The seat itself is never written by this loop.

### Rules derived

1. A recovery path must REACH a state that cannot re-trigger the same failure.
   Jumping one step from a blocked spot is a retry loop, not a recovery.
2. A consumer that only READS a field must never need to overwrite it to recover:
   if a fallback has to change the value, the ownership of that field is wrong.

---


## Lesson 29 â€” A column resolver must filter its participants with the SAME test the queue uses, or a stale field steals a pair/seat

**Date:** 2026-11-16
**Module:** `Functions/Formations/fn_formationsTrailCompactColumn.sqf`
**Type:** Lesson

### Symptom (in game)

Trail compact worked, **except the last two teams of the column**, which were not
compacted (they stayed in single file / on the old offsets).

### Verified root cause

The participant list was built with ONE clause:

```sqf
private _offsetDist = _entry getOrDefault ["trailOffsetDist", -1];
if (_offsetDist > 0) then { _participants pushBack [_offsetDist, _grpId]; };   // WRONG
```

`trailOffsetDist` is NOT cleared when a group leaves the trail world. A ROAD column
ordered afterwards writes only `roadOffsetDist`, so every group that had marched in
a trail keeps its `trailOffsetDist` forever (the RPT of the same session shows road
groups at 9-78 m and trail leftovers at 158-217 m still holding `off`).

Consequences:

1. Those ghosts were counted as participants, so `_count` was larger than the real
   column and the pairing `[1&2][3&4]...` shifted by the number of intruders.
2. With an odd effective count the loop leaves ONE member on an incomplete pair - and
   because the intruders sort AFTER (or among) the real tail, the member left out is
   one of the LAST real teams.
3. Ghosts also kept a `trailShoulderOffset` from a previous compaction, so they were
   drawn in a lane of a column they did not belong to.

The ROAD compact never showed this because it filters on `roadShoulderOffset != 0`,
a field that only exists while a road column is being laid.

### The rule

A resolver that consumes the registry must select its population with **exactly the
same predicate** as the consumer that will act on the result:

```sqf
platoonId == _pltId
AND movingMode == "FOLLOWING_TRAIL"
AND trailOffsetDist > 0          // the test fn_formationsTrailQueueSync uses
```

Anything wider silently includes groups from another world, another platoon, or a
finished order.

### Applied

- `_participants` uses the three-clause test above (identical to the queue).
- Non-participants are DETACHED from the trail chain: residual `trailOffsetDist` and
  `trailShoulderOffset` are reset to 0, so a ghost can neither take a pair position
  now nor corrupt a later compaction.
- Debug counter under `FTCS_Debug_Mode`:
  `[TRAIL][COMPACT] plt N: X participants -> Y pairs, unpaired=Z, depth=Dm`.
  If `X` differs from the number of groups the queue chains in that platoon, the
  filter is wrong again.

### Rules derived

1. A field that identifies MEMBERSHIP in a march world must be cleared when that
   world ends, or every consumer must re-test membership instead of reading the field
   alone. Prefer the explicit predicate.
2. When a "leftover at the end" symptom appears in a pairing/zip operation, count the
   participants FIRST: an odd or inflated count is the fingerprint of a bad filter,
   not of a bad pairing loop.

---

## Lesson 30 â€” The TRIM floor must include the groups that are still WAITING (a seated-only floor starves the tail)

**Date:** 2026-11-16
**Module:** `Functions/Movement/fn_formationsTrailQueueSync.sqf`, `Functions/Roads/fn_trailTrimToArc.sqf`, `fn_trailColumnSet.sqf`
**Type:** Lesson

### Symptom (in game + RPT `Arma3_x64_2026-11-16_13-53-51.rpt`)

The LAST teams of the trail column took forever to start and finally never started,
while the lieutenant walked hundreds of metres away:

```
13:56:39  'HQ (Guide & Security Element)' off=217 seat=-1  (cap=-1) -> HOLDS
14:28:36  'HQ (Guide & Security Element)' off=217 seat=86  (cap=-1) -> HOLDS
```

32 MINUTES holding, and the seat it finally got (`86`) is not its seat at all.

### Verified root cause

`fn_trailTrimToArc` cuts against `trailMinSeatArc`, which Lesson 27 defined as
`headDist - deepest offset WITH A SEAT`. A group that is still WAITING has no seat -
and it is precisely that group whose depth the trim is eating:

```
seated offsets : 1 .. 158      -> floor = headDist - 158
trimLimit      = floor - 100   -> trims everything before headDist - 258
```

The trail is left with 83-99 points (~170-200 m, verified in the RPT) while the
column needs 217 m. When Mortars/Guide finally reach their turn, the point at their
depth no longer exists: `trailIndexAtArc` saturates at the last surviving index (86)
and the group holds forever. The trim does not kill them at the moment of trimming;
it makes their future seat impossible.

This was introduced by Lesson 27's own fix: replacing an over-cutting floor by an
under-protecting one.

### Correct rule

The floor protects the DEEPEST offset of the column, seated OR waiting:

```sqf
protected = max(deepestSeatedOff, deepestAnyOff)   // queue, every tick
trailMinSeatArc = headDist - protected
```

`deepestAnyOff` is `_frontDist` at the end of the chain walk (updated for every car,
seated or not - the chain note already required it).

Belt and braces: `fn_trailTrimToArc` ALSO floors the cut with the anchor's
`trailMaxOffset` (`headDist - trailMaxOffset`), so even a stale or clamped
`trailMinSeatArc` can never cut ground inside the column's own depth.

### Rules derived

1. A memory bound must protect **every consumer that will need the data**, including
   the ones that are currently blocked and derive their need from a FUTURE position.
   "Currently reading" is not the same as "about to read".
2. When fixing an over-aggressive bound (Lesson 27), state explicitly WHICH offset
   the new floor protects. A floor that is smaller than the largest doctrinal depth
   is not a safety margin, it is a bug waiting for a long march.
3. One symptom (the tail never starts) can have two different causes in sequence:
   first the release criterion, then the data the criterion needs. Check the data
   survives before blaming the timing.

---

## Lesson 31 â€” A stuck-group escape must skip ONE index, never jump to the seat

**Date:** 2026-11-16
**Module:** `Functions/Formations/fn_formationsGroupFollowTrail.sqf`
**Type:** Lesson

### Symptom (in game)

When the lieutenant went far ahead, some groups **cut straight across the terrain**
instead of following the recorded track - "they overtake the whole file".

### Verified root cause

Lesson 25 changed the timeout escape from `target + 1` to the full seat:

```sqf
private _releaseIdx = (_slotIndex min _maxIdx) max 0;
_targetIdx = _releaseIdx;          // WRONG
```

The seat can be 50-150 m ahead. `_group move <that point>` is a PATHFINDING request,
so Arma picks the shortest route to it and the group never steps on the recorded
points in between. That breaks the single invariant the trail column exists for:
every group walks the leader's track, point by point.

The two goals conflict directly:

- skip one index  -> lane invariant preserved, but a truly blocked point retries forever
- jump to the seat -> recovers instantly, but destroys the lane

### Correct resolution (applied)

```sqf
private _nextIdx = ((_targetIdx + 1) min _slotIndex) min _maxIdx;
```

- Steps ONE index per `_stuckTimeout` (20 s): the group still walks every recorded
  point in order, so the lane is intact.
- The recovery is real: a blocked point costs 20 s, not eternity, and the next point
  is usually reachable.
- Never past the seat: the clamp below (`_slotIndex = _targetIdx`) must not be able
  to replace the queue's ceiling with a local guess (the single-writer rule).

### Rules derived

1. In an index-based lane, ANY target that is not the next reachable point is a
   corner-cutting bug by definition - however good the recovery looks.
2. A recovery must be the SMALLEST step that escapes the failure, not the most
   convenient one. "Reach the final destination" is a different operation from
   "recover", and mixing them silently changes the pathing contract.
3. When two invariants conflict (never stuck vs never cut corners), keep the one the
   feature exists for and slow the other down.

---

## Lesson 32 â€” A memory bound may not depend on data published by a thread that runs AFTER it (trim/record equilibrium)

**Date:** 2026-11-16
**Module:** `Functions/Roads/fn_trailTrimToArc.sqf`, `Functions/Formations/fn_formationsGroupFollowTrail.sqf`
**Type:** Lesson

### Symptom (RPT `Arma3_x64_2026-11-16_13-53-51.rpt`, 14:36-14:37)

Everything moved much better, but THE LAST GROUPS were left behind again:

```
off=169 -> seat=6   (max=94)
off=189 -> seat=94  (cap=6)  -> HOLDS
off=200 -> seat=94  (cap=-1) -> HOLDS
off=217 -> seat=94  (cap=-1) -> HOLDS
```

and the trim log shows why `max` is pinned at 94:

```
14:36:24  Trim: dropped 10 pts (26.5m) -> 103 pts
14:36:33  Trim: dropped 10 pts (27.4m) -> 101 pts
14:36:54  Trim: dropped 10 pts (31.3m) ->  95 pts
14:37:05  Trim: dropped 10 pts (27.8m) ->  94 pts
```

### Verified root cause

The trim runs FIRST in the tick; the queue (`fn_formationsTrailQueueSync`) publishes
`trailMinSeatArc` / `trailMaxOffset` AFTERWARDS. So the trim always worked with the
PREVIOUS tick's floor - and on the ticks that mattered those fields did not exist
yet (`getOrDefault` -> 0 -> protection skipped entirely).

With no protection it reached a stable EQUILIBRIUM with the recorder:

```
recorder: +2 m (one point) per 0.25 s tick
trim    : -10 points (~25 m) as soon as 10 are eligible (~every 10 s)
=> path oscillates around 95-103 points and NEVER reaches the 217 m the column needs
```

A group deeper than the plateau can never obtain a seat: `trailIndexAtArc` saturates
at the last surviving index, and `seat` is published as that index - so the group
holds forever, "lost at the back".

### Correct design (applied)

1. **Self-contained guard.** `fn_trailTrimToArc` reads the registry itself and
   protects the deepest `trailOffsetDist` of its platoon with
   `movingMode == "FOLLOWING_TRAIL"` (seated OR waiting). Published anchor values are
   only an ADDITIONAL floor, never the primary one:

   ```sqf
   _guardArc = headDist - deepestOff          // from the registry, this tick
   _guardArc = max(_guardArc, headDist - trailMaxOffset)   // published, if any
   trimLimit = max(tailArc, _guardArc) - cushion
   ```

2. **Batching raised** to 20 points and cushion to 150 m: fewer renumbers, and the
   column-depth guard always wins by a wide margin.
3. **Tail fallback in the follower** (safety net): a group with no seat at all in a
   `>= 2`-point path walks to index 0 - ground the leader really walked, strictly
   behind every seat - instead of freezing where it was placed.

### Rules derived

1. A maintenance pass (trim, eviction, compaction) must derive its bound from the
   SOURCE OF TRUTH it can read itself, in the same tick. Depending on a value another
   thread publishes later makes the bound one tick stale - and a stale bound that is
   SMALLER than the need is not a safety margin, it is a slow starvation.
2. Two loops (add one point / drop many) can form a stable LIMIT CYCLE that looks
   like normal operation in the log and only shows up as "the tail never arrives".
   When you see maintenance firing periodically at roughly the rate of production,
   suspect equilibrium before suspecting the consumer.
3. Every consumer that can be starved needs an explicit, logged fallback
   (`***` prefixed) so the failure is visible instead of silent.

---

## Lesson 33 â€” When the file is compressed against the trail tip, SPACING must yield to ORDER

**Date:** 2026-11-16
**Module:** `Functions/Movement/fn_formationsTrailQueueSync.sqf`
**Type:** Lesson

### Symptom (RPT `Arma3_x64_2026-11-16_13-53-51.rpt`)

Everything worked, but the LAST group of the column was left out:

```
'1st Platoon - Mortar Section'          off=200  seat=2   (max=106) -> SEAT
'HQ (Guide & Security Element)'         off=217  seat=106 (cap=2)   -> HOLDS
```

### Verified root cause

Pure arithmetic impossibility, no timing involved. For the last car:

```
_gapIdx  = ceil((217 - 200) / 2) = 9      // its own doctrinal separation
_frontSeat = 2                            // the car in front only has 2 indexes left
_maxSeat = 2 - 9 = -7  ->  seat = -1  ->  HOLDS
```

The two rules imposed on the car contradict each other while the column is bunched
against the tip of the trail:

- ORDER  : `seat <= frontSeat`            (never overtake)
- SPACING: `seat <= frontSeat - gapIdx`   (keep the doctrinal separation)

`frontSeat - gapIdx < 0` means the SPACING rule cannot be satisfied by ANY valid
index, so the resolution `-1` (hold) fired even though both cars are legitimately
members of the column. The group then waited for the leader to walk far enough for
the file to expand - and if he stopped there, it waited forever.

### Correct rule (applied)

SPACING is a DESIRE; ORDER is a REQUIREMENT. When they cannot both hold, keep the
minimum order - **one index behind the car in front** - and let the group in:

```sqf
if (_seat < 0 && { _frontSeat >= 1 }) then {
    _seat = _frontSeat - 1;      // minimum order, logged under FTCS_Debug_Mode
};
```

Consequences:

- The group enters the column in the SAME tick its predecessor has a seat; it never
  waits for ground that does not exist.
- It recovers its doctrinal gap automatically as the trail grows (the natural seat
  moves back up), so no permanent spacing is lost - only a temporary compression.
- A car whose predecessor genuinely has NO seat (`_frontSeat < 0`) still holds: there
  is nothing to chain behind, and that is correct.

### Rules derived

1. When two constraints can be jointly unsatisfiable, declare which one is a HARD
   requirement and which is a preference, and encode the fallback explicitly. A
   `-1` that means "no solution" becomes a permanent stall if the input never changes.
2. A group outside the column is a WORSE failure than a group temporarily too close:
   the first one is unrecoverable without new orders, the second one heals itself.
3. Prefer closing against a measured quantity (indexes left in the trail) than
   against a doctrinal one (metres of separation). The measured one is what exists.


---

## Lesson 35 â€” A UI layer must be DATA + one gate function, not 25 hand-built arrays

**Date:** 2026-11-17
**Type:** Architecture / Design Note (direct guide for an AI)

**What replaced what:** `fn_openSubordinateMenu` (405 lines, deleted) and
`fn_initCommandingMenus` (607 lines, reduced to three data arrays) are replaced
by the `Menu` module:

```
fn_menuCatalog   DATA: menus, rows, tokens, gates, reopen flags
fn_menuGetState  ONE registry pass -> state snapshot
fn_menuGate      [gate, state, squadRec] -> [enabled, reason]
fn_menuBuild     catalog + state -> rows (labels, %1, dynamic rows, hub)
fn_menuOpen      snapshot -> build -> publish copy -> showCommandingMenu
fn_menuDispatch  "FAMILY:CODE[:ARG]" -> legacy router code
fn_menuReopen    one-shot MouseButtonUp re-open
fn_initMenus     compile catalog once + single player addAction
```

**Invariants an AI must not break:**

1. The catalog is DATA. No function may mutate it: `fn_menuBuild` returns a NEW
   array and `fn_menuOpen` publishes that array. This is what killed the "menu
   corrupted while the engine reads it" family of bugs.
2. Only functions with backend may be painted. A row for a command without a
   `case` in `fn_applyCommandToTarget` is a LIE to the player.
3. Squad identity is the registry (`squadId` + `isSquadLeaderGroup`); the name is
   a caption only (Rule 18).
4. "Squad has no leader" means the anchor's leader is `grpNull`, `DEAD` or
   `INCAPACITATED`. `alive` alone is NOT enough (an unconscious soldier is alive
   but cannot command) - this is the same test as the scout-slot occupancy.
5. The menu sentinel `FTCS_Debug_Menu_Mode` is read once and never toggled in
   game; it is independent of `FTCS_Debug_Mode`.
6. Re-open behaviour is decided in ONE place (`fn_menuDispatch`).

**Retired:** `fn_commandMenusRefresh` (never present on disk; only referenced by
docs) and `fn_openSubordinateMenu`.

---

## Lesson 36 â€” A HARDLINK does not "break": it gets DETACHED when an editor rewrites the file (Arma then loads a stale `description.ext`)

**Date:** 2026-11-17
**Module:** `tools/LinkMission.ps1`, `tools/VerifyLinks.ps1` (new)
**Type:** Lesson + tooling

### Symptom (RPT `Arma3_x64_2026-11-17_20-38-19.rpt`, 20:40:45)

```
Warning Message: Script functions\Interactions\fn_openSubordinateMenu.sqf not found
```

with `fn_openSubordinateMenu.sqf` already deleted from the repository, and with
`class Menu` present in the repo `description.ext`. The new `Menu` module produced
NO logs at all - because `CfgFunctions` never saw it.

### Verified root cause

Measured, not guessed:

```
repo\description.ext              4783 bytes  8x "class Menu"   openSubordinateMenu: 0
Mission_2\description.ext         4405 bytes  0x "class Menu"   openSubordinateMenu: 1
Mission_1\description.ext         4405 bytes  0x "class Menu"   openSubordinateMenu: 1
Mission.Colleville\description.ext 4071 bytes  (REAL FILE, no link)
```

`Mission_1` and `Mission_2` were hardlinks **to each other** - a closed ring with
no link to the repository. `Functions/`, `UI/`, `Doctrines/`, `tools/` were (and
are) **junctions to the repo**, so the mission DID see the new `.sqf` files while
`description.ext` came from somewhere else.

Why it worked before and stopped: a hardlink shares the SAME inode. It cannot
desynchronise by itself. It becomes a **separate file** the moment an editor
saves by writing a new file and replacing the old one (VS Code, many IDEs). From
then on the two paths show the same "link", but hold different content, and Arma
reads the mission-side copy.

`FTCS_Dev_Mission.Colleville` was worse: `description.ext` had been relinked (new
content) but `Functions/`, `Doctrines/`, `UI/` and `tools/` were **real copies**,
so it declared `class Menu` while its frozen `Functions/` had no `Menu/` folder
and still contained `fn_openSubordinateMenu.sqf`. That mission would fail to load
the whole UI layer.

### Rules derived

1. **A junction (folder -> folder) cannot desynchronise. A hardlink (file ->
   file) can.** For any file the engine reads at load time (`description.ext`,
   `init.sqf`), verify CONTENT, never the existence of the link.
2. "The links never failed" and "the file on disk is not the one I edited" are
   both true at the same time. Check hashes before blaming compilation.
3. When one mission of a set is broken, check ALL of them: a stale copy in a
   mission you are not testing will bite later.
4. Real copies of `Functions/` inside a mission are the worst case: the mission
   silently runs frozen code.

### Tooling added

- `tools/LinkMission.ps1`: after creating each file link it compares MD5 with the
  repo and prints `[SYNC OK]` / `[SYNC FAIL]`.
- `tools/VerifyLinks.ps1` (new): audits every `FTCS_*` mission and reports
  `[OK] / [FALLO]` per shared file (content hash) and per shared folder
  (junction vs real copy). Exit code 0 = all missions read the repository.
  Run it before opening Arma after editing `description.ext` or `init.sqf`.

---

## Lesson 37 â€” Rewriting a `description.ext` from a stale copy silently DELETES CfgFunctions classes (trailTrimToArc vanished, trail column died)

**Date:** 2026-11-17
**Module:** `description.ext`, `Functions/Roads/fn_trailAdvanceAnchor.sqf`
**Type:** Lesson

### Symptom (RPT `Arma3_x64_2026-11-17_20-38-19.rpt`)

```
File ...\functions\Roads\fn_trailAdvanceAnchor.sqf..., line 50
Error Undefined variable in expression: ftcs_fnc_trailtrimtoarc
```

The trail column stopped working although `fn_trailTrimToArc.sqf` existed on disk
and had been verified in game the day before.

### Verified root cause

`description.ext` was rewritten (to add the new `Menu` module) starting from an
OLDER in-memory/text version. The rewrite dropped

```sqf
class trailTrimToArc {};
```

which had been added in commit `1896911`. The `.sqf` file was present in
`Functions/Roads/` (reachable through the junction), but the engine only compiles
what `CfgFunctions` declares: the call resolved to an undefined function on EVERY
tick of the recorder thread.

A class-level diff against `HEAD` afterwards showed exactly: 2 classes lost
(`openSubordinateMenu`, `commandMenusRefresh` - both intended) and 8 added (the
`Menu` module). Before the fix the file was 6 classes short of `HEAD`.

### Rules derived

1. **Never rewrite `description.ext` wholesale.** Patch the specific class block.
   A full rewrite silently drops classes added by someone else.
2. After ANY edit to `description.ext`, run a class diff against `git HEAD`:
   ```powershell
   git diff HEAD -- description.ext | Select-String "class "
   ```
   Every removed class must be one you MEANT to remove.
3. An `Undefined variable in expression: ftcs_fnc_*` error means the function is
   not registered in `CfgFunctions` - check `description.ext` BEFORE checking the
   file on disk or the mission links.
4. `actionParams` was considered for reading action labels from IDs; it is not a
   documented native command. Use an explicit published ID list instead of
   introspecting the action list.

---

## Lesson 39 — A platoon ORDER is a registry fact, not a company-wide global

**Date:** 2026-11-20
**Type:** Lesson + Architecture / Design Note (direct guide for an AI)

### Symptom / risk

`FTCS_Platoon_Follow_Mode` (REL/ABS), `FTCS_Platoon_Fixed_Abs_Dir` and
`FTCS_Platoon_Advance_Direction` were COMPANY-WIDE missionNamespace globals. With
3-4 platoons (Etapa B) every platoon inherited the follow mode and axis of
whichever platoon ordered last, and the menu could only answer "what mode is the
platoon in?" by VOTING across groups - which is a state, not an order.

### What was changed (verified on disk)

New platoon registry sentinels (`FTCS_Platoons_Registry[pltId]`), seeded in
`fn_registryInit` from the legacy globals so no state is lost at boot:

| Field | Writer (single) | Readers |
|---|---|---|
| `followMode` REL\|ABS | `fn_applyCommandToTarget` PLT_MODE_RELATIVE/PLT_MODE_ABSOLUTE | `fn_menuGetState` (row label), `fn_menuDispatch` (toggle), `fn_platoonAdvanceAxis`, `fn_formationsCurrentPositionSet`, `fn_formationsApplyPlatoonOrder`, `fn_platoonHaltRejoin`, 4 scout paths in the dispatcher, `fn_formationsGroupDoFollowCommander` |
| `followModeFacing` | ABS order, position capture, formation order, REJOIN-KEEP | `fn_platoonAdvanceAxis` (ABS), follow loop initial target, debug worker |
| `advanceDirection` | follow loop (REL, live), capture, formation order, road column birth, REJOIN-KEEP | same consumers (REL) |

### Two bugs found and fixed on the way

1. **`fn_menuGetState` read `_pltReg` before declaring it** - `private` inside SQF
   does not hoist values; the followMode line landed above the registry read. The
   read was moved BELOW the declaration.
2. **`fn_formationsGroupDoFollowCommander` split its setup into two same-mode
   blocks** (`REL` block and `ABS` block) that each re-declared `private _relPos`
   (Lesson 34/37 family). Merged into ONE shared `_relPos` read + two thin
   mode blocks, which also guarantees `doFollow leader _group` runs in BOTH modes
   exactly as before.

### Invariant for the next AI

- Platoon = ORDER (`followMode`, `advanceDirection`, `followModeFacing`,
  `movementTechnique`, `columnLayout`, `edgeMarginSteps`).
- Group = EXCEPTION (`movingMode`, `squadFormation`, `teamFormation`).
- A group leaving the formation writes ITS `movingMode`; it NEVER touches the
  platoon order. A menu gate that needs "what was ordered" reads the platoon
  field; only "is this squad out of line?" reads the group field.
- The legacy globals are write-only compatibility mirrors now. Any new READ of
  them outside the deployment pipeline is a regression.

---

## Lesson 38 — Menu gates must read REGISTER fields / sentinels, never internal code state
**Date:** 2026-11-20
**Module:** `Functions/Menu/` (fn_menuGate, fn_menuGetState)
**Type:** Architecture / Design Note (direct guide for an AI) + Lesson

### Symptom (RPT `Arma3_x64_2026-11-20_17-37-02.rpt`, session 18:19-18:31)

The March Route menu row "5. Compact Column" stayed GREYED while a leader-trail
column was demonstrably marching (trail tip advancing, groups in
`FOLLOWING_TRAIL`). The same row behaved correctly in road march.

### Verified root cause chain (three distinct bugs found and fixed in this module)

1. **Undeclared variable poisoning the company tree** (fn_applyCommandToTarget,
   case `PLT_TRAIL_COLUMN`): the legacy write-back `_platoonsMap set [_pltKey,
   _pltData]` referenced `_pltData` WITHOUT declaring it first (the road case did
   declare it). Writing nil into `FTCS_Company_Data > platoons > PLT_1` corrupted
   the doctrinal tree, and EVERY menu open afterwards died with
   `Undefined variable in expression: _parsedsquads` in fn_menuGetState.
   Fix: declare `_pltData` like the road case does (later made moot, but the
   lesson is general: a write-back of an undeclared local silently poisons a
   GLOBAL structure — the crash appears later, elsewhere, always "in the menu").

2. **Gate deciding against anchor geometry**: `gate_compact` evaluated
   `roadActive`/`trailActive`/`trailLayout` read from the anchor HashMaps
   (`FTCS_Road_Anchor_PLT_*`, `FTCS_Trail_Anchor_PLT_*`). Those anchors are
   per-world geometry that OUTLIVES a mode change (ordering road march does not
   clear the trail anchor, so `trailActive` stayed true), are mutated every
   0.25 s by the queue-sync thread, and hold no authoritative mode. Any gate
   reading them races the writers and mixes two march worlds in one decision.

3. **No observability**: the RPT never logged what the gate actually read
   (`trailLayout`, `roadLayout`), so the failure mode could only be deduced, not
   verified. Any gate decision MUST be traceable.

### Rules derived (POLICY — mandated by the user, registered as Point 0 Rule 20)

1. **Menu state is decided ONLY by sentinels**: fields of the registries
   (`FTCS_Platoons_Registry`, `FTCS_Groups_Registry_Table`) or cataloged
   missionNamespace flags. NEVER by introspecting function-internal state
   (anchor HashMaps, spawn threads, locals, debug markers).
2. **One-way flow**: gameplay code WRITES its state into the registry/sentinel
   at the moment of change; the menu layer ONLY reads. Fix a missing decision
   input by ADDING a registry field (single writer + documented in
   FTCS_Data_Structure_Reference.md), never by reading deeper into code.
3. **The authoritative march mode of a platoon is**
   `FTCS_Platoons_Registry[pltId]["movementTechnique"]`
   (`CROSS_COUNTRY` | `ROAD_COLUMN` | `TRAIL_COLUMN`), written ONLY by the order
   dispatcher. Gates deriving column availability from anchors are a bug.
4. **Every gate input must be traceable**: a gate reason string exists already
   (`[_enabled, _reason]`); extend the `[FTCS][MENU][STATE]` dump under
   `FTCS_Debug_Menu_Mode` when a gate misbehaves, so the next diagnosis reads
   values, not inferences.

### Correct pattern (as now implemented in fn_menuGate.sqf)

```sqf
case (_gate == "gate_compact"): {
    private _cTech = _state getOrDefault ["moveTech", "CROSS_COUNTRY"];
    if (!(_cTech in ["ROAD_COLUMN", "TRAIL_COLUMN"])) then {
        _enabled = false;
        _reason = "no active column";
    };
};
```

`moveTech` is populated by fn_menuGetState straight from the platoon registry
(one line, pre-existing read). No anchors, no threads, no timing races.

### Related

- Point 0 Rule 20 (new): menu state policy.
- FTCS_Data_Structure_Reference.md section 1-bis: sentinel catalog for menus.
- Lesson 35: UI = DATA + one gate function (this lesson extends it with the
  "what the data may be" constraint).

---
