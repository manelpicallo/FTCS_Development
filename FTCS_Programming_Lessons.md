# FTCS - Programming Lessons Learned (Base de Conocimiento Técnica)

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
| **SESSION** | 2026-11-14 | **CLOSED Session log** | HALT/REJOIN fix + full RULE 16 migration (phases 1-9). Read this first when resuming | whole project |

---

## Lesson 1 — `continue` inside `forEach` breaks SQF compilation with "Error in expression / 0 elements provided, 3 expected"

**Date:** 2026-11-13
**Module:** `Functions/Targeting/fn_targetPersistentMarker.sqf` (Draw3D mission event handler)
**Symptom:**

- Recurring RPT error `Error in expression <...> / 0 elements provided, 3 expected`, always pointing at or near the `drawIcon3D` call that draws the squad-name caption (reported around "line 109" / "l109" in the RPT).
- The error **moved to different line numbers** (66 → 73 → 109) as guards and code were added/removed, which made it look like a data problem.
- The crash happened every frame, deterministically, ONLY when the Draw3D handler was re-spawned (e.g. after `targetClearAllSquads` wiped targets and a new capture re-created the handler). Moving/re-marking a target while the old handler was still alive worked fine.

**Wrong hypotheses we chased (and why they failed):**

1. "The marker position array is nil/partially cleared mid-frame" → added `typeName`/SCALAR guards everywhere. Did NOT fix it: the failure happens at COMPILE time of the handler closure, before any guard can run.
2. "The engine is running an old version of the file" → false; the RPT error line moved with our edits, proving the new file was loaded.
3. "`drawIcon3D` receives a 0-element array" → the array literal was correct; the real problem was upstream in the same expression.

**Verified root cause (researched against the BI wiki, [continue - BI Community Wiki](https://community.bistudio.com/wiki/continue)):**

- The SQF keyword `continue` (introduced in Arma 3 v1.92) is **only supported in `while do`, `for do` and `do..while` loops**. It is **NOT supported inside `forEach` loops** — the [forEach](https://community.bistudio.com/wiki/forEach) wiki page documents no `continue` support either.
- When the SQF parser finds `continue` in a `forEach` body, it treats it as an orphan binary operator and **consumes the following expression** (in our case the `drawIcon3D [...]` array literal, whose parameters come in 3 groups — hence "3 expected") as its operands. The closure **fails to compile**, and because a `Draw3D` handler is recompiled/evaluated every frame, the error repeats every frame.
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

- Rule of thumb: **inside `forEach`, use nested `if/then` (or an `if (...) then { ... } else { ... };` structure) to skip iterations — never `continue`.** `continue` is legal only in `while do` / `for do` / `do..while` loops (existing valid uses in this project: `fn_formationsGroupFollowTrail.sqf`, `fn_marchStuckWatchdog.sqf` — both `while` loops).

**Debugging meta-lesson:** when an SQF error keeps appearing at "the line of a big array literal" and moves around as unrelated code is edited, suspect a **parse/compile-level problem in the same expression or an earlier statement in the same closure** (orphan keyword, unbalanced brackets, binary operator misparse) — not a runtime data problem. Adding more runtime guards cannot fix a closure that never compiles.

---

## Lesson 2 — Mission-folder linker (`tools/LinkMission.ps1` + `LinkMission.bat`): NTFS Junctions + hardlinks keep ONE versioned codebase for every terrain

**Date:** 2026-11-13
**Type:** Architecture / Design Note (direct guide for an AI)
**Module:** `LinkMission.bat` (repo root) → `tools/LinkMission.ps1`

**Problem it solves:**

- Arma 3 identifies each mission by `<MissionName>.<Terrain>` folder name, so testing the same FTCS codebase on a new terrain requires a NEW mission folder — and a NEW, terrain-specific `mission.sqm` that Eden refuses to share.
- Copying `Functions/`, `Doctrines/`, `init.sqf`, etc. into every mission folder would fork the codebase and pollute the GitHub history.

**Architecture ("repo without mission.sqm"):**

- The repo lives in ONE mission folder (currently `FTCS_Dev_Mission.Colleville`) and is the GitHub-versioned source of truth.
- `LinkMission.bat` (repo root) runs `tools/LinkMission.ps1`, which asks for the destination mission folder name and that mission's Eden-generated `mission.sqm`, then:
  1. Creates an NTFS **Junction** (no admin rights needed, unlike symbolic links) inside the destination mission folder for every SHARED item: `Functions`, `Doctrines`, `tools`, and hardlinks for shared files `description.ext`, `init.sqf`, `LinkMission.bat`. Editing code in EITHER folder edits the SAME files.
  2. Copies as REAL local files the per-mission exclusives: `mission.sqm` (each terrain keeps its own world).
- Existing destinations are handled safely: previous junctions are repositioned with `.Delete()` on the reparse point only (NEVER `Remove-Item -Recurse` through a junction — on PowerShell 5.1 it can traverse INTO the repo and delete the real codebase); real files/folders are only replaced after explicit user confirmation.

**Invariants an AI must NOT break:**

- NEVER delete a junction with recursive filesystem tools; delete only the link itself.
- `mission.sqm` must NEVER be linked/hardlinked into the repo — it stays a per-mission local copy (a generic mission.sqm breaks Eden loading on other terrains).
- Shared-item lists live in the `$SharedItems` / `$LocalFiles` arrays at the top of `LinkMission.ps1`; any new top-level shared folder or file of the project must be added there, or new missions will silently miss it.
- Workflow for a new terrain: 1) create+save the empty mission in Eden (generates its mission.sqm), 2) run `LinkMission.bat` from the repo, pointing at that mission.sqm.

---

## RULE 0 (POINT ZERO — ABSOLUTE DIRECTIVE) — Doctrine display names are FORBIDDEN as code identifiers

**Date:** 2026-11-14
**Status:** PERMANENT DIRECTIVE — every AI working on FTCS must follow this to the letter.
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
  NEVER matches (it silently yields zero results — no error, just missing
  participants, exactly the class of bug seen in `fn_platoonHaltRejoin.sqf`).
- **What to use instead (internal references ONLY):**
  - Group OBJECTS (`_grp`, `grpNull`-checked) resolved from the seeded registries
    (`FTCS_Platoons_Registry > pltId > "squads"`), never re-derived from names.
  - Registry-stamped LINK FIELDS written by `fn_registryInit`: `parentSquadGroup`
    (fireteam → its squad group object) and equivalent hierarchy stamps. Family
    membership is resolved by OBJECT REFERENCE equality (`_grp in _squadList`,
    `_entry get "parentSquadGroup" == _sqdGrp`), never by name.
  - Numeric platoon IDs (`FTCS_Player_Platoon_ID`) for platoon-level state.
- **Hierarchy invariant (mandatory for EVERY movement/order function — platoon,
  squad, HALT, REJOIN, marches, formations):**
  1. The lieutenant is the platoon anchor; squads' LEADER groups occupy the
     lieutenant-assigned slots (0–12) and follow the lieutenant (REL/ABS).
  2. ALL other groups inside a squad follow their OWN SQUAD LEADER — never the
     lieutenant — with formation geometry preserved.
  3. Sole exception: groups explicitly re-assigned to a lieutenant-directed slot
     (e.g. scouts to slots 5/6/7/8/11/12) are temporarily anchored to the
     lieutenant, until re-anchored back to their squad leader.
  Any new function must be verified against this invariant before integration;
  a violation is a bug by definition.

**Enforcement:** before submitting any change, grep it for doctrine-name string
matching. If found, redesign using object references from the registry. There
are no exceptions.

---

## Lesson 3 — HashMap key order is NOT deterministic: "first team found" as the squad anchor silently misclassified squads as fireteams

**Date:** 2026-11-14
**Module:** `Functions/Core/fn_registryInit.sqf` (platoon registry seeding), `Functions/Formations/fn_platoonHaltRejoin.sqf` (HALT/REJOIN)
**Type:** Lesson + Architecture note

**Symptom (observed in-game, RPT 18:22:39 / 18:22:52):**

- `[FTCS][HALT] squad '<X>' : N fireteams collected` printed, as "squads", groups that are in fact FIREteams and HQ sub-teams:
  `1st Rifle Squad - BAR Support Team`, `HQ - 1st Platoon (Support Element)`, `3rd Rifle Squad - Rifle Team A`.
- After REJOIN, the slot that should sit behind the platoon leader appeared **in front of him**, and slots 9/10 ended up bunched behind the leader out of order, while slots 1/2/4 looked fine.
- The shift and rejoin bearings for the same group differed by a constant **+45°** (e.g. shift 247° vs rejoin 293°), and one group changed distance (38.8 m -> 18 m).

**Verified root cause:**

1. `fn_registryInit` resolved the squad-level anchor as **"the FIRST team yielded by iterating the squad's `tacticalTeams` HashMap"**:
   ```sqf
   { private _g = (_y) getOrDefault ["group", grpNull];
     if (!isNull _g) exitWith { _first = _g; }; } forEach _teams2;
   ```
   **SQF HashMap iteration order is NOT insertion order and is not guaranteed stable.** The "first" team is arbitrary — sometimes `TEAM_2` (a BAR support element), sometimes the HQ `Support Element`. That arbitrary group then became:
   - the entry in `FTCS_Platoons_Registry > pltId > "squads"`, i.e. what the platoon treats as a squad, **and**
   - the `parentSquadGroup` stamped on every team of that squad, i.e. what fireteams treat as their squad leader.
2. Consequence: HALT/REJOIN classified fireteams as squads. The real squad leader group appeared nowhere, so a fireteam received a platoon-slot re-anchor (`mvFormationShift`) while its siblings followed it as if it were the leader → geometry collapsed around the leader.
3. The +45° discrepancy was a **second, independent bug**: the shift projected the anchor with `platoonAdvanceAxis`, and the rejoin re-projected it with `_rejoinFacing` computed from a value that had been rewritten in between. Two projections of the same offset with different axes.

**The fix (applied):**

- `fn_registryInit` now resolves the anchor **deterministically**, using the doctrinal `"type"` field that `fn_parseEditorGroups` already stamps on each team (`TEAM_1`/`TEAM_2`/`TEAM_3`/`COMMAND`):
  1. unified squad → its `"group"`;
  2. multi-team → the team whose type is `TEAM_1` (or `COMMAND`);
  3. the team whose `leader` is the squad's `"leader"` (name-free);
  4. HQ squads → the `TEAM_3`/`GUIDE`/`SECURITY` element;
  5. parser's squad-level `"group"`;
  6. first resolved group (malformed doctrines only).
- Two new registry fields, seeded by the same pass and documented in `FTCS_Data_Structure_Reference.md`:
  - `"squadId"` — the doctrinal squad key (`"SQD_1_1"`), so teams can be grouped without reading the doctrine;
  - `"isSquadLeaderGroup"` — `true` **only** on the squad anchor.
- `fn_platoonHaltRejoin` now splits squad vs fireteam using those fields (`parentSquadGroup` + `isSquadLeaderGroup`), and a fireteam with no valid anchor is logged and skipped instead of being re-anchored to the lieutenant (Point 18 invariant).
- `continue` inside `forEach` was removed (Lesson 1) and replaced by a positive `if`.
- A `[FTCS][REGISTRY] plt N squads: ...` line now prints the resolved anchors at seed time, so this class of bug is visible in one glance.

**Meta-lesson for future code:**

- **Never** derive hierarchy membership from the iteration order of a HashMap, from "first element", or from `groupId` strings (Point 18). Derive it from an explicit field (`type`, `isSquadLeaderGroup`, `squadId`) seeded once at init.
- If a consumer needs identity data the registry does not carry, the fix is to **add the field in `fn_registryInit`** and document it — never to re-read `FTCS_Company_Data` at runtime (RULE 16).
- When two functions project the same geometry, they must use the **same** axis source (`fn_platoonAdvanceAxis`); otherwise the difference shows up as a constant angular offset.

---

## Lesson 4 — `leader _group` is NOT the doctrine commander: Arma 3 picks the group leader by its own rules

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
- **Arma 3 decides `leader _group` on its own** (leadership skill, seniority, insertion order). When a command group contains several doctrinal roles — the classic case is the platoon leader together with his RTO inside the same `Command Element` group — the engine may resolve the group leader to the RTO.
- Consequence: "the role of the group leader" ≠ "the role of command present in the group". They are two different questions and only the second one is what FTCS needs.

**The fix (applied):**

- `roleKey` is now the **highest-ranked doctrine role present in `units _group`**, resolved by iterating `assignedRoles` and keeping the role whose unit belongs to the group. Explicit priority:
  1. `PLT_<N>_LEADER` → 100
  2. any `*_LEADER` (`SQD_<N>_<M>_LEADER`, ...) → 80
  3. any `*SERGEANT` → 60
  4. any other doctrine role → 40
- Result: the Command Element now reports `role='PLT_1_LEADER'` even when the RTO is the engine-selected group leader.

**Why the player-driven platoon was never affected:**

- When the player IS the platoon leader, the code moves him out of the HQ group, and the follow pipeline identifies the commander through `isPlayer _leader` / `FTCS_Platoon_Leader_Unit — never through `roleKey`.
- The bug only becomes visible with an **AI platoon leader** (autonomous platoons) or at **company scale** (several platoons with their own AI lieutenants), which is exactly Etapa B of the project roadmap.

**Rules derived:**

1. Never infer a doctrinal rank from `leader _group`, `vehicleVarName`, or group membership order. Doctrine ranks come from `assignedRoles` and must be ranked explicitly.
2. When a field must answer "who commands here?", make sure the consumer also asks the right question: **current UI-driven platoon** → `isPlayer` / `FTCS_Platoon_Leader_Unit`; **AI / company scale** → `roleKey`.
3. Any registry field whose value can differ from the engine's own notion of leadership must say so in `FTCS_Data_Structure_Reference.md` — done for `roleKey`.

---

## Lesson 5 — The platoon leader lives in a DIFFERENT group than the doctrinal Command Element: group-level identity cannot answer "who commands the platoon"

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
- `roleKey` is therefore **correct by definition** ("highest doctrine role inside this group") but **cannot answer "who commands the platoon"** — that is a different question, asked at a different level.

**Why this does not break the current single-platoon build:**

- Consumers identify the commander through `isPlayer _leader` / `FTCS_Platoon_Leader_Unit`, never through `roleKey`.
- The registry now records the truth explicitly, so the anomaly is visible instead of silent.

**Open item (does NOT require a composition change now):**

- Whether the same split happens with AI lieutenants (and at company scale) is still unverified. The planned company-scale deployment test will show it in the `[FTCS][REGISTRY] plt N leaderVar=...` lines of every platoon: a lieutenant landing in an engine-named group (e.g. `Alpha 3-6`) instead of the Command Element means the composition places him outside his doctrinal element.

**The fix (applied):**

- Three new fields on the PLATOON entry (`FTCS_Platoons_Registry > pltId`), seeded by `fn_registryInit`:
  - `"leaderUnit"` — the `PLT_<N>_LEADER` unit (player or AI). Valid regardless of which group he belongs to. Falls back to the `PLT_<N>_LEADER` missionNamespace variable.
  - `"leaderGroup"` — `group leaderUnit`, or `grpNull` when he has no group at all.
  - `"peerOnly"` — `true` ONLY when `leaderUnit` is not inside `leaderGroup` (truly groupless). It does NOT mark "leader is in a non-doctrinal group": check `leaderGroup` against the platoon's `platoonGroup` for that.
- A `[FTCS][REGISTRY] plt N leaderVar=... leaderGroup=... peerOnly=...` log line makes the whole state visible at seed time.

**Rules derived (IMPORTANT for every future consumer):**

1. **"Who commands the platoon?"** → read the PLATOON entry (`leaderUnit` / `leaderGroup` / `peerOnly`). Never `roleKey`, never `leader _group`.
2. **"Which doctrine role lives in this group?"** → `roleKey` (group entry). Useful for squads/teams, NOT for the HQ command element in player mode.
3. **While `peerOnly == true`** consumers must keep using `isPlayer _leader` / `FTCS_Platoon_Leader_Unit` (today's working behaviour). `roleKey == "PLT_<N>_LEADER"` will also be true then, but the registry field is the stable source.
3b. `peerOnly == false` does NOT mean "the leader is in the doctrinal Command Element". Always compare `leaderGroup` with `platoonGroup` when the distinction matters.
4. Group-level identity and platoon-level identity are **different levels of the same model**. Mixing them is exactly how the HQ ended up reporting its RTO as commander.

---

## Lesson 6 — Phase 2 pattern: registry is the source of truth, the doctrine tree keeps a MIRROR until consumers are migrated

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
4. **Read through the accessor.** New readers use `[pltId, "field", _default] call FTCS_fnc_registryGetPlatoon;` — registry first, doctrine fallback (safety net for fields not yet seeded).
5. **Never write the tree directly** for these fields from now on. The mirror exists only so Phase 3 can be done consumer-by-consumer with zero-downtime ordering.

**Architecture invariants an AI must NOT break:**

- `FTCS_Platoons_Registry` is keyed by the NUMERIC platoon id (1, 2, 3...), same key as HALT/REJOIN uses. Never mix STRING keys (`"PLT_1"`) into it.
- The doctrine mirror is TEMPORARY. When Phase 3 completes, `FTCS_fnc_registrySetPlatoon` must lose its mirror block and `registryGetPlatoon` its fallback (one edit, clearly marked `---- Doctrine mirror (temporary, removed in Phase 3)`).
- Any new platoon-level state field must be added to BOTH: this document (`FTCS_Data_Structure_Reference.md` §1) and the `[FTCS][REGISTRY] plt N state:` diagnostic line, so seeding problems are visible from the log.
- `roleKey` (group level) and the platoon `leaderUnit`/`leaderGroup`/`peerOnly` triple (platoon level) answer DIFFERENT questions — see Lessons 4 and 5.

---

## Lesson 7 — `!expr isEqualTo value` parses as `(!expr) isEqualTo value` → "Error !: Type String, expected Bool"

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
4. A syntax-only checker (`verify_syntax.ps1` balances braces/brackets/parens) CANNOT catch this: the file is syntactically valid, it fails at RUNTIME on the first evaluation. Only an in-game self-test or the RPT reveals it — which is why every migration step needs a runtime self-test that executes the new code paths.

---

## Lesson 8 — Doctrine is a SEED, not a contract: separate the immutable template from the live state

**Date:** 2026-11-14
**Module:** `Functions/Core/fn_applyDoctrine.sqf`, `Functions/Formations/fn_formationsApplyPlatoonOrder.sqf`
**Type:** Architecture / Design Note (direct guide for an AI)

**The problem this settles.**

Platoon formation slots come from the doctrine composition (`platoonFormationSlots` in the active doctrine data). Two very different things were being conflated:

1. **What the doctrine says the platoon SHOULD look like** — the slot -> squad mapping authored in 3DEN.
2. **What the platoon ACTUALLY looks like right now** — the same mapping after scouts detached, after a squad was wiped, or (future) after the player re-ordered squads.

Reading (1) at runtime makes (2) impossible: every runtime mutation would have to rewrite the doctrine, which must never happen.

**The model now in force (two fields, two lifecycles):**

| Field | Location | Written by | Mutability | Purpose |
|---|---|---|---|---|
| `doctrineFormationSlots` | `FTCS_Platoons_Registry > pltId` | `fn_applyDoctrine` ONLY (at seed time) | **Immutable** | The template. Reset target. |
| `formationSlots` | `FTCS_Platoons_Registry > pltId` | `fn_registryInit` (seed) + runtime writers (`fn_applyCommandToTarget` scouts, future re-order) | **Live / mutable** | What consumers read. |

- Both are **copied** (`+_hash`), never referenced, so mutating the live map can never leak into the template.
- `fn_formationsApplyPlatoonOrder` falls back to `doctrineFormationSlots` when the live map is empty (e.g. after a scout sweep) — still a registry read, never the doctrine tree.
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
- Never make a runtime consumer read `doctrineFormationSlots` as the CURRENT layout — it is the template.
- Never mutate the doctrine tree in runtime; if a value must change during the mission, it belongs in the registry.
- When adding a new doctrine-derived field, seed BOTH: the template (immutable) and the live value (mutable), and document both here.

---

## Lesson 9 — Migrating a consumer: REMOVE every use of the old variable, or it becomes an undefined reference

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

`_targetSquadData` no longer existed, so `_tacticalTeams` silently became an **empty HashMap** (SQF does not error on an undefined variable inside `getOrDefault`, it just yields the default). The team list was empty → no scout team found → the warning. The same stale variable existed in a second block (trail march scout reset).

**Why the syntax checker did not catch it.** The file was perfectly balanced; an undefined LOCAL variable is a runtime concern, not a syntax one.

**The fix (applied).**

Both scout blocks now resolve the squad from the registry:
- the squad's groups = every entry whose `"squadId"` matches;
- the scout element = the first of those that is NOT `"isSquadLeaderGroup"`;
- the parent re-compaction list = the ANCHOR first, then the remaining fireteams (anchor order matters: `fn_formationsTypeSquadSet` treats element 0 as the leader).

**Rules derived.**

1. When migrating a block, **grep the whole function for the removed variable name immediately after the edit** (`_targetSquadData|_tacticalTeams|_teamKeys`). Do it before running, not after the bug report.
2. `getOrDefault` on an undefined variable **fails silently** — it hides the mistake. Prefer materialising shared lookups (squad groups, team lists) in ONE place and passing them down.
3. Any list where element 0 must be the Squad Leader must be built as **anchor first, then teams**, never from an unordered HashMap iteration.
4. `isNotEqualTo` does not exist in SQF (see Lesson 7): write `!(A isEqualTo B)`.

---

## Lesson 10 — Recalling a detached scout must restore its FULL squad state, not just the attachment

**Date:** 2026-11-14
**Module:** `Functions/Interactions/fn_applyCommandToTarget.sqf` (scout recall), `Functions/Formations/fn_platoonHaltRejoin.sqf` (fireteam self-heal)
**Type:** Lesson

**Symptom (in game, reproducible sequence):**

1. Detach a scout to slot 11 → OK.
2. HALT → move → REJOIN → the scout returns to its scout slot → OK.
3. **Recall the scout** (`PLT_SCOUT_REJOIN_ALL` / "Rejoin all scouts") → it goes back into its squad → OK.
4. Move a little → HALT → move → REJOIN → **the recalled scout jumps in FRONT of the platoon leader** instead of following its squad.

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
   - `movingMode` → follow mode
   - `teamAttachment` → `"SQUAD_BOUND"`
   - `allocationSlot` → `-1`
   - `parentSquadGroup` → the squad anchor (self-reference for the anchor, its own anchor for fireteams)
   The anchor is resolved from `squadId` + `isSquadLeaderGroup`, never from names.
2. **`fn_platoonHaltRejoin` self-heals**: if a fireteam reaches the REJOIN with a null `parentSquadGroup` but a valid `squadId`, it rebuilds the link from the registry before deciding how to re-anchor, and logs `anchor self-healed`.

**Rules derived.**

1. A lifecycle transition must reset **every** field that describes the OLD state. "Detached" is not one flag: it is a combination (`movingMode` + `teamAttachment` + `allocationSlot` + `parentSquadGroup`). Reset them together, in one place.
2. Any consumer that branches on `allocationSlot in [5,6,7,8,11,12]` will misfire while a stale slot lingers. Clearing it is part of leaving the detached state.
3. Defensive self-healing at the consumer (`squadId` -> anchor) is cheap and makes the system recover from lost links instead of silently anchoring to the wrong leader.
4. Test the FULL cycle, not a single transition: detach → HALT/REJOIN → recall → move → HALT/REJOIN. The bug only appears on the second REJOIN.

---

## Lesson 11 — "Pick the first matching group" is a bug: doctrine must DECLARE the scout team (`tacticalRole = "SCOUT"`)

**Date:** 2026-11-14
**Module:** `Doctrines/Data/*.sqf`, `Functions/Core/fn_registryInit.sqf`, `Functions/Interactions/fn_applyCommandToTarget.sqf`
**Type:** Lesson + Architecture note

**Symptom (in game).**

Detach a scout → OK. Recall it → OK. Detach **again** → a **different fireteam** gets sent to the scout slot.

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

`FTCS_Groups_Registry_Table` is a HashMap, so `select 0` returned a different fireteam on different runs. The doctrine *did* name the team (`"Scout Team"` in `teamStructure`), but that name is a DISPLAY name and Point 18 forbids using it as an identifier — and `teamRoles` only had `ASSAULT`/`SUPPORT`, so the information was not machine-readable.

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

## Lesson 12 — `parsedSquads` is built AFTER the doctrine: a field stamped in `fn_applyDoctrine` never reaches the runtime team objects

**Date:** 2026-11-14
**Module:** `fn_applyDoctrine.sqf`, `fn_parseEditorGroups.sqf`, `fn_registryInit.sqf`
**Type:** Lesson + Architecture note

**Symptom.** After adding `["teamRoles", ["ASSAULT","SCOUT","ASSAULT","SUPPORT"]]` to the doctrine and projecting `"tacticalRole"` in `fn_registryInit`, the scout detachment STILL reported "no separate scout fireteam".

**Verified root cause — the pipeline order matters:**

```
fn_applyDoctrine      → builds FTCS_Company_Data > platoons > PLT_x > squads
                        (+ doctrine template teams with "tacticalRole")
fn_parseEditorGroups   → CREATES "parsedSquads" FROM SCRATCH, one entry per
                        editor group, each team hash built as a NEW HashMap
                        WITHOUT "tacticalRole"
fn_registryInit        → reads parsedSquads > team > "tacticalRole"   ← EMPTY
```

1. `fn_applyDoctrine` **never creates `parsedSquads`** (grep: 0 hits). It only creates `squads` and `squadsRegistry`.
2. `fn_parseEditorGroups` builds `parsedSquads` later and **overwrites** every team hash, so any field the doctrine put there is lost.
3. Therefore every attempt to read `"tacticalRole"` from `parsedSquads` returns `""`, and the selector falls back — or, before the fallback existed, found nothing at all.

**The fix (applied).**

- `fn_applyDoctrine` now stores the resolved doctrine roles as a plain INDEX → ROLE array:
  `FTCS_Company_Data set ["doctrineTeamRoles", _teamRoles];`
  (an array, not a name lookup: `["ASSAULT","SCOUT","ASSAULT","SUPPORT"]`).
- `fn_registryInit` resolves each team's role by its **ordinal in the `TEAM_<N>` type**:
  `parseNumber ((_teamType splitString "_") select 1)` → `doctrineTeamRoles select (_ordinal - 1)`.
  No display names, no HashMap iteration order (Point 18 compliant).
- `fn_parseEditorGroups` keeps writing `"tacticalRole", ""` with a comment explaining that the role is resolved later, so the field exists in the team hash but is never mistaken for the source of truth.

**Rules derived.**

1. **Check the pipeline order before adding a field.** `parsedSquads` is a RUNTIME structure built by the parser; the doctrine template lives in `squads`. A value written to one is not visible in the other.
2. When two functions build overlapping structures, the LAST writer wins. Add the field where the *last* writer can compute it, or pass it through a parallel, stable structure (here: an index array on `FTCS_Company_Data`).
3. Index-based projection (`teamRoles[i]` ↔ `TEAM_(i+1)`) is deterministic and name-free — prefer it over matching team display names.
4. Always log the raw source (`doctrineTeamRoles=...`) in the self-test: it distinguishes "the doctrine has no SCOUT" from "the projection lost it".

---

## PENDING-1 — Company scale: each AI platoon needs its own follow loop and formation management

**Date:** 2026-11-14
**Status:** OPEN — decision required BEFORE writing any new company-scale feature.
**Type:** Architecture / Design Note (direct guide for an AI)
**Scope:** every movement / formation / order function.

**The open question.**

Migration phases 1–8 put `"platoonId"` on every group entry and `leaderUnit` / `leaderGroup` / `peerOnly` / `squads` on every platoon entry, so the data for multiple platoons already EXISTS. **No consumer uses it per platoon yet.** Almost everything still resolves the platoon with:

```sqf
private _pltId = missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1];
```

**To decide (when company scale starts):**

1. Does EVERY AI platoon run its own `fn_formationsGroupDoFollowCommander` threads and its own `fn_formationsApplyPlatoonOrder` pipeline? (Yes is the natural answer: the loops are already per-group, only the reference leader and the axis are global.)
2. Do the platoon-scoped globals become per-platoon entries in `FTCS_Platoons_Registry`?
   - `FTCS_Platoon_Follow_Mode` → `registrySetPlatoon [pltId, "followMode", ...]`
   - `FTCS_Platoon_Advance_Direction` / `FTCS_Platoon_Fixed_Abs_Dir` / `FTCS_Last_Commander_Dir` → per-platoon axis fields
   - `FTCS_Platoon_Phase_<N>` (already per platoon) → plus registry mirror
3. What is the company-level anchor? The captain orders a platoon to a position; the platoon then runs its own local formation around its own lieutenant.

**Hard rule for any new code written before this is decided:**

- Accept the platoon id as a PARAMETER when it is available, and only fall back to `FTCS_Player_Platoon_ID` when it is not.
- Never bake `FTCS_Player_Platoon_ID` into a new function's core logic.
- Never read a per-platoon global directly if a registry field can carry it.

---

## PENDING-2 — Long-cycle verification of the scout state machine (VERIFIED / CLOSED)

**Date:** 2026-11-14
**Status:** ✔ CLOSED — verified in game. The scout state machine is correct over the full lifecycle.
**Type:** Verification checklist (kept as a regression baseline)

**What was verified:** a single scout deployment works, the scout menu finds the correct team (Lesson 12 fix), AND the full long-cycle below was exercised successfully in game.

**Lifecycle checks (all PASSED in game):**

1. **Three consecutive deploy cycles** → the SAME team detached each time (Lesson 11 non-determinism regression).
2. **HALT → move → REJOIN after a recall** → the recalled team rejoins its OWN squad, never in front of the lieutenant (Lesson 10 regression).
3. **Road march with detached scouts** → column forms correctly, scouts re-chain.
4. **Trail march with detached scouts** → trail chain forms correctly.
5. **Recall (`PLT_SCOUT_REJOIN_ALL`) then HALT/REJOIN** → full state reset holds (`allocationSlot = -1`, `parentSquadGroup` intact).
6. **Mixed case:** squad A with scouts detached + squad B without → only A's scout slots affected.

**Keep this list as a REGRESSION BASELINE:** re-run it after any future change to
`fn_applyCommandToTarget` (scout branch), `fn_platoonHaltRejoin`, `fn_registryInit`
(hierarchy fields) or the doctrine `teamRoles`.

**What to look for in the RPT if a future regression appears:**

- `[FTCS][SELFTEST] SCOUT ... scoutRole=... -> PASS` in every combat squad
- `[FTCS][REJOIN] <grp> anchor self-healed from squadId ...` (means the parent was lost and recovered)
- `[FTCS][REJOIN] <grp> (fireteam) SKIPPED: no parentSquadGroup anchor ...` (means the self-heal failed — this is a BUG, not a valid state).

---

## SESSION LOG 2026-11-14 — HALT/REJOIN fix + full RULE 16 migration

**Status:** CLOSED. All work below is applied, verified in game and documented.
**Purpose:** resume context for the next session WITHOUT re-reading the whole chat.
**Read this first. Then read Lessons 1–12.**

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
- `!A isEqualTo B` is a syntax-and-runtime trap → `!(A isEqualTo B)` (Lesson 7).
- Doctrine is a SEED, not a contract; mutations go to the registry (Lesson 8).
- Migrating code: grep the removed variable — `getOrDefault` on an undefined var fails SILENTLY (Lesson 9).
- Recalling a detached group must reset its FULL state (Lesson 10).
- "Pick the first matching group" is a bug; declare the role in doctrine (Lesson 11).
- `parsedSquads` is built AFTER `fn_applyDoctrine` (Lesson 12).

### 5. Self-tests written (run automatically at mission start)

Search the RPT for `[FTCS][SELFTEST]`:
`PHASE 2..7 ACCEPTANCE`, `SCOUT ROLE ACCEPTANCE`. Every check prints PASS/FAIL/SKIP.
These are the fastest way to confirm the registry seeded correctly in a new mission.

### 6. OPEN ITEM — read PENDING-1 before any new feature

**PENDING-1**: company scale. Each AI platoon needs its own follow loop and
formation management. The registry data already exists (`platoonId`,
`leaderUnit`, per-platoon state), but NO consumer uses it per platoon yet —
everything still resolves `FTCS_Player_Platoon_ID`. Rule for new code: accept
the platoon id as a parameter whenever available.

`PENDING-2` (scout long-cycle verification) is CLOSED and kept as a regression baseline.

### 7. Still to build (nothing started)

Dynamic cover (Fn 1), heavy-weapons/SBF (Fn 2), auto-ammunition (Fn 3),
tactical messengers (Fn 4), tactical map/OPORD, map position degradation,
company mode.
