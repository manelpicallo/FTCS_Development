/*
    ================================================================================
    File: fn_trailColumnSet.sqf
    Module: Formations
    Author: FTCS Team
    Description: Freezes the leader-trail anchor and assigns staggered trail
                 offsets to every subordinate group for TRAIL_COLUMN march.
                 - Column definition is identical to the road march order of
                   slots (HQ Escort first, then squads per footprint), but the
                   master trajectory is the LEADER'S OWN TRACK: groups inherit
                   the exact points the leader walked, so everyone follows the
                   same terrain line (ravines, tree lanes, defiles).
                 - slot order: [9, 0, 4, 1, 2, 3, 10, 5] - the SAME list
                   fn_formationsRoadColumnSet walks, so the trail column and the
                   road column put the same group first (slot 9, HQ Escort, the
                   RTO). Each team then consumes its deterministic footprint
                   ((unitCount - 1) * 3m + 5m) + inter-squad separation, matching
                   the road march pace math. Slots 6/7/8 (forward scouts) are
                   excluded, exactly like the road column.
                 - Offsets are RELATIVE to the leader (consumers sample at
                   headDist - offsetDist over the recorded trail).
                 - Initial formation: all groups start stacked 1m behind the
                   leader and shift into place as the leader walks (the trail
                   grows behind him and slots ride along).
                 Writes into FTCS_Groups_Registry_Table (trailOffsetDist /
                 trailTargetPos / trailTangentDir) consumed by
                 fn_formationsGroupFollowTrail on its 1s ticks.
    Params:
        0: NUMBER - Platoon ID.
        1: ARRAY - Subordinate groups to chain into the column.
        2: OBJECT - Platoon leader unit (trail source).
    Returns:
        NUMBER - Count of chained groups (0 on failure).
    Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params [["_pltId", 1], ["_subGroups", []], ["_leader", objNull]];

// Guard order matters: a NULL leader is a different failure from an EMPTY group
// list, and both used to return the same 0 with no trace. The caller restores
// CROSS_COUNTRY on 0, so the reason must be visible in the RPT (Rule 19: real
// failures log always, with the *** prefix).
if (isNull _leader) exitWith {
    diag_log format ["[FTCS][TRAIL] *** ABORT: platoon %1 has no valid leader unit.", _pltId];
    0
};
if ((!(_subGroups isEqualType [])) || { count _subGroups == 0 }) exitWith {
    diag_log format ["[FTCS][TRAIL] *** ABORT: platoon %1 has no subordinate groups to chain (subGroups=%2).", _pltId, _subGroups];
    0
};

// SPACING RULE - one number per concept, no hidden constants:
//     soldierPace  = metres of depth taken by ONE more soldier behind the leader
//     separateDist = fixed margin between two teams (body + separation)
//     headGap      = where the first team starts, behind the leader
//
// The old code had the 5 m margin buried inside the footprint expression and a
// second 8 m "inter-squad buffer" added on top, so the gap for a 4-man team was
// 13 m of margin for 9 m of soldiers. Now there is exactly ONE margin.
private _soldierPace  = 3.0;   // metres per soldier behind the first
private _separateDist = 8.0;   // body + separation between two teams
private _headGap      = 1.0;   // first slot starts 1m behind the leader

// Freeze the trail anchor: seeded with the leader's current position.
// The seed direction is 0 as a placeholder: consumers facing the first walked
// segment (point0 -> point1) instead of trusting the seed facing, so the
// leader's head rotation at order time never leaks into group orientation.
private _trailPath = [[getPosATL _leader, 0]];
private _anchor = createHashMap;
_anchor set ["anchorPos", getPosATL _leader];
_anchor set ["trailPath", _trailPath];
_anchor set ["headDist", 0];               // leader sits at the trail tip (index = last)
_anchor set ["lastAnchorMovePos", getPosATL _leader];
// Spacing between two recorded trail points. Consumers convert a group's march
// offset into a POINT INDEX with `round(offset / recordStep)`; the recorder uses
// the same value as its minimum step (fn_trailAdvanceAnchor, _recordStep param),
// so index and arclength stay aligned.
_anchor set ["recordStep", 2.0];
_anchor set ["generation", (missionNamespace getVariable [format ["FTCS_Trail_Gen_PLT_%1", _pltId], 0])];
missionNamespace setVariable [format ["FTCS_Trail_Anchor_PLT_%1", _pltId], _anchor];

// Chain the subordinate groups in the ROAD COLUMN MARCH ORDER, single file.
//
// The order is NOT "allocationSlot ascending": the trail column must walk the same
// sequence the road column walks, and that sequence is an explicit doctrine list.
// fn_formationsRoadColumnSet uses `[9, 0, 4, 1, 2, 3, 10, 5]`, i.e.:
//
//     9  HQ Escort (carries the RTO)   <- FIRST behind the leader
//     0  Vanguard / 1st Squad
//     4  Platoon Sergeant
//     1  2nd Squad
//     2  3rd Squad
//     3  4th Squad / Mortars
//     10 Platoon Guide
//     5  Rear Reserve
//
// Sorting by `allocationSlot` put slot 0 first and slot 9 (the RTO) almost at the
// TAIL, so the trail column was not the road column at all: verified in game, the
// BAR support team of the 1st Squad led the file while the Command Element walked
// eighth. Both columns must agree, so the same list is used here.
//
// Slots 6/7/8 (forward scouts) are excluded, exactly as the road column does: those
// groups advance ahead of the leader and are not part of the rear file.
//
// Groups whose slot is not in the list (detached teams, no slot, -1) go to the tail
// in their original order, so nothing is ever dropped from the column.
private _slotOrder = [9, 0, 4, 1, 2, 3, 10, 5];

private _chained = [];
{
    if (!isNull _x && { _x != group _leader }) then {
        private _gid = groupId _x;
        private _gEntry = FTCS_Groups_Registry_Table getOrDefault [_gid, createHashMap];
        // HQ sub-teams are ranked by their REGISTRY ROLE sentinel, not by the raw
        // `allocationSlot` the doctrine seeder happened to give them: the three HQ
        // elements must land on the SAME slots the cross-country COLUMN doctrine
        // uses (COMMAND 9 / SUPPORT 4 / GUIDE 10), regardless of seed order.
        private _hqRole = _gEntry getOrDefault ["hqElementRole", ""];
        private _slot = _gEntry getOrDefault ["allocationSlot", -1];
        if (_hqRole != "") then {
            _slot = switch (_hqRole) do {
                case "COMMAND": { 9 };
                case "SUPPORT": { 4 };
                case "GUIDE":   { 10 };
                default { _slot };
            };
        };
        if (!(_slot isEqualType 0) || { _slot < 0 }) then { _slot = -1; };
        // `find` returns -1 when the slot is not in the list (including 6/7/8, the
        // forward scouts, and -1 for groups with no slot): those go to the tail.
        private _rank = _slotOrder find _slot;
        if (_rank < 0) then { _rank = 999; };
        _chained pushBack [_rank, _gid, _x];
    };
} forEach _subGroups;
_chained sort true;

private _offsetCursor = _headGap;
private _assignedCount = 0;
{
    private _grpId = _x select 1;
    private _grp = _x select 2;
    private _unitCount = count (units _grp) max 1;

    private _entry = FTCS_Groups_Registry_Table getOrDefault [_grpId, createHashMap];
    _entry set ["trailOffsetDist", _offsetCursor];
    _entry set ["trailTargetPos", getPosATL _leader]; // first tick refines from the trail
    _entry set ["trailTangentDir", getDir _leader];
    _entry set ["trailShoulderOffset", 0]; // single-file: clears any prior compact pairing
    _entry set ["movingMode", "FOLLOWING_TRAIL"];
    // LANE TARGET: the index of the trail point this group is CURRENTLY walking to.
    // -1 = "nothing yet"; the follower picks the first one and only renews it after
    // physically reaching the previous point. It is reset on every new order because
    // the trail is re-seeded and an old index would address different ground.
    _entry set ["trailLaneTargetIdx", -1];
    FTCS_Groups_Registry_Table set [_grpId, _entry];

    // Advance the cursor by this team's DETERMINISTIC footprint.
    //
    // WHY NOT MEASURE THE TEAM (the old `_rearmost` probe):
    // it measured how far apart the group's soldiers happened to stand AT ORDER
    // TIME. A team still spread out in line covered 15 m and pushed the cursor 18 m;
    // the same team already bunched under its leader covered 2 m and pushed it only
    // 7 m. Two teams in the same column therefore ended up with nearly identical
    // offsets, their trail arcs collapsed onto the same metre and their markers piled
    // up at the bridge entrance - points the leader never walked.
    //
    // The footprint is a property of the UNIT COUNT, not of the current pose:
    //     pace   = (n - 1) x _soldierPace   one pace per soldier behind the leader
    //     margin = _separateDist             body + separation to the next team
    // so 4 men -> 9 + 5 = 14 m, 3 men -> 6 + 5 = 11 m, 5 men -> 12 + 5 = 17 m, always.
    //
    // This is the ONLY spacing rule and it applies to EVERY group in the column.
    private _footprint = (((_unitCount - 1) * _soldierPace) + _separateDist);
    _offsetCursor = _offsetCursor + _footprint;
    _assignedCount = _assignedCount + 1;
} forEach _chained;

// Highest assigned offset. INFORMATIVE ONLY: the trim does NOT cut against it
// anymore (it goes stale as soon as the layout changes - compact, casualties,
// re-orders). fn_trailTrimToArc cuts against "trailMinSeatArc", the oldest arc the
// column really occupies, published by fn_formationsTrailQueueSync every tick.
private _maxOffset = _offsetCursor;
_anchor set ["maxTrailOffset", _maxOffset];
// TRIM state: -1 = the queue has not spoken yet, so the recorder trims nothing.
_anchor set ["trailMinSeatArc", -1];
_anchor set ["trailTailArc", -1];
// Deepest offset of the column, republished by fn_formationsTrailQueueSync every
// tick. fn_trailTrimToArc treats it as a HARD FLOOR: the trim can never cut ground
// that is still inside the column's own depth.
_anchor set ["trailMaxOffset", _maxOffset];
// Lag allowance behind the rear group. MUST match the default in fn_trailTrimToArc:
// a seeded value always wins over that default, so 100 here silently defeated the
// 150 m cushion the trim was tuned for (Lesson 32).
_anchor set ["trimCushion", 150.0];
_anchor set ["trimEvents", 0];
_anchor set ["columnLayout", "STAGGERED"]; // re-issuing trail unlocks the Compact option

systemChat format ["[TRAIL COLUMN] %1 teams chained behind the leader track.", _assignedCount];
_assignedCount
