/*
    ================================================================================
    File: fn_formationsTrailCompactColumn.sqf
    Module: Formations
    Author: FTCS Team
    Description: Compacts the leader-trail column into a STAGGERED double lane.
                 - The master trajectory does not change: every slot keeps its
                   arclength over the leader's recorded track. What changes is
                   the chain and the lateral placement:
                     * Teams are paired in march order: pair [1&2], [3&4]...
                     * Both members of a pair get THEIR OWN trail arclength inside
                       the pair window (the second member sits `_pairStep` behind
                       the first), each displaced laterally +/-0.75m perpendicular
                       to the local trail tangent (1.5m total lane separation,
                       centered on the leader's walked line).
                     * The arclengths MUST differ: the queue
                       (fn_formationsTrailQueueSync) chains cars by
                       `ceil((off - off_front) / recordStep)` and forces a
                       minimum of ONE index between two cars. Two groups with the
                       SAME offset therefore got a forced 2 m index gap - i.e. the
                       second lane was pushed back one point instead of marching
                       abreast of the first.
                     * The next pair starts after the bigger member's NOMINAL
                       manpower footprint ((men - 1) * 3m + 8m, the same model as
                       fn_trailColumnSet) + pairGap. The MEASURED leader->rearmost
                       distance is deliberately NOT used: it reflects the team's
                       current dispersion, so a team still spread out in line would
                       inflate the depth and push the whole column back.
                 - Result: the single-file trail column depth roughly halves
                   while every team still marches exactly on the leader's line.
                 - Groups with trailOffsetDist > 0 participate; forward/center
                   entries are untouched (same criteria as road compact).
                 - Lane state is LEFT UNTOUCHED: `trailLaneTargetIdx` belongs to the
                   follow loop and is neither reset to -1 nor re-indexed here. Each
                   participating group is displaced IN PLACE instead: its target point
                   is its CURRENT position pushed sideways by the new shoulder offset,
                   so it slides into the lane without walking back. Groups that do
                   NOT participate lose any stale shoulder offset.
                 - Marks the trail anchor columnLayout = "COMPACT" (locks the
                   menu option until the trail order is re-issued).
                ======================== WHO PARTICIPATES =========================
                ONLY the groups the queue would chain in THIS platoon and in the
                TRAIL world, using the SAME test as fn_formationsTrailQueueSync:

                    platoonId == _pltId
                    AND movingMode == "FOLLOWING_TRAIL"
                    AND trailOffsetDist > 0

                The old test was `trailOffsetDist > 0` alone. Every group that ever
                marched in a trail KEEPS that field, so a road-column group that
                still carried a stale trail offset from a previous order was counted
                as a participant, consumed a pair position, and left the REAL tail
                (the last two teams) on an incomplete pair - observed in game as
                "everything compacted except the last two".

                ====================== NON-PARTICIPANTS ARE CLEARED =================
                Groups of this platoon that are NOT in the column get their residual
                trail fields cleared (trailOffsetDist 0, trailShoulderOffset 0). A
                ghost offset is exactly what corrupted the pairing above, and it also
                makes the queue publish seats for groups that are not marching.

    Params:
        0: NUMBER - Platoon ID whose trail anchor owns the chain.
    Returns:
        NUMBER - Count of re-assigned groups (0 if not compactable).
    Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params [["_pltId", 1]];

private _pairHalfSeparation = 1.0;  // lateral meters each member deviates from the walked line
private _pairStep = 1.0;            // longitudinal split inside a pair (distinct arclengths)
private _pairGap = 3.0;             // meters between consecutive pairs

// SPACING RULE - the SAME model fn_trailColumnSet uses (one margin, no hidden
// constants): a team occupies `(men - 1) * soldierPace` behind its first man and
// reserves `separateDist` (body + separation) before the next team.
private _soldierPace  = 3.0;
private _separateDist = 2.0;

private _anchor = missionNamespace getVariable [format ["FTCS_Trail_Anchor_PLT_%1", _pltId], createHashMap];
private _trailPath = _anchor getOrDefault ["trailPath", []];
if (count _trailPath < 2) exitWith {
    systemChat "[TRAIL COMPACT] Error: no active trail column (anchor missing).";
    0
};

// Collect participating trail groups. The three-clause test is IDENTICAL to the one
// fn_formationsTrailQueueSync uses to build the column, so this resolver pairs
// exactly the groups the queue chains - a stale `trailOffsetDist` left by a previous
// road march can no longer steal a pair position from the real tail (Lesson 29).
private _participants = [];
{
    private _entry = _y;
    private _grpId = _x;
    private _offsetDist = _entry getOrDefault ["trailOffsetDist", -1];
    if (   ((_entry getOrDefault ["platoonId", -1]) == _pltId)
        && { ((_entry getOrDefault ["movingMode", ""])) == "FOLLOWING_TRAIL" }
        && { (_offsetDist isEqualType 0) && { _offsetDist > 0 } }) then {
        _participants pushBack [_offsetDist, _grpId];
    };
} forEach FTCS_Groups_Registry_Table;

if (count _participants < 2) exitWith {
    systemChat "[TRAIL COMPACT] Error: not enough chained groups to pair.";
    0
};
_participants sort true;

// Resolve the group object by groupId to compute its manpower footprint
private _fnc_resolveGroup = {
    params ["_grpId"];
    private _grp = objNull;
    { if (groupId _x == _grpId) exitWith { _grp = _x }; } forEach allGroups;
    _grp
};

// Pairing resolver: consecutive teams share one PAIR WINDOW, opposite sides
private _cursor = 0; // longitudinal distance along the trail (relative to leader)
private _pairIndex = 0;
private _count = count _participants;
for "_i" from 0 to (_count - 1) step 2 do {
    private _aIdx = _i;
    private _bIdx = _i + 1;
    private _hasPartner = (_bIdx < _count);

    // Pair footprint: the bigger member drives the inter-pair advance
    private _footprintMax = 0;
    private _members = [_aIdx];
    if (_hasPartner) then { _members pushBack _bIdx; };

    {
        private _grpId = (_participants select _x) select 1;
        private _grp = [_grpId] call _fnc_resolveGroup;
        private _unitCount = if (!isNull _grp) then { count (units _grp) max 1 } else { 4 };
        // NOMINAL footprint (deterministic by headcount, never by current pose):
        // 4 men -> 17 m, 3 men -> 14 m, exactly like fn_trailColumnSet.
        private _footprint = (((_unitCount - 1) * _soldierPace) + _separateDist);
        if (_footprint > _footprintMax) then { _footprintMax = _footprint; };
    } forEach _members;

    // Assign both members of the pair: DISTINCT arclengths (so the queue keeps its
    // one-index minimum naturally instead of forcing it), opposite lateral sides.
    private _memberRank = 0;
    {
        private _idx = _x;
        private _side = if ((_idx % 2) == 0) then { -1 } else { 1 }; // left / right
        private _grpId = (_participants select _idx) select 1;
        private _entry = FTCS_Groups_Registry_Table getOrDefault [_grpId, createHashMap];

        _entry set ["trailOffsetDist", _cursor + (_memberRank * _pairStep)];
        _entry set ["trailShoulderOffset", (_pairHalfSeparation * _side)];
        // THE LANE CURSOR BELONGS TO THE FOLLOW LOOP - this function must NOT touch
        // `trailLaneTargetIdx`:
        //   * -1 means "brand new column": the loop walks the group from the head of
        //     the trail, so every group retraces the track it already walked.
        //   * the index of the NEW arclength lands AHEAD of the queue's still-OLD
        //     `trailSlotIndex`, so the loop considers the group to be past its ceiling
        //     and walks it backwards to the head once more.
        // Instead the group is displaced IN PLACE: the target point is its CURRENT
        // position pushed sideways by the new shoulder offset. The loop keeps its
        // cursor, the queue publishes the new seat on its next tick, and the group
        // slides into the lane where it already stands.
        private _grpObj = [_grpId] call _fnc_resolveGroup;
        if (!isNull _grpObj) then {
            private _lead = leader _grpObj;
            if (!isNull _lead) then {
                private _sh = _pairHalfSeparation * _side;
                private _perpDir = if (_sh < 0) then { (getDir _lead + 270) % 360 } else { (getDir _lead + 90) % 360 };
                _entry set ["trailTargetPos", (getPosATL _lead) getPos [abs _sh, _perpDir]];
            };
        };
        FTCS_Groups_Registry_Table set [_grpId, _entry];

        _memberRank = _memberRank + 1;
    } forEach _members;

    // Advance to the next pair position
    _cursor = _cursor + _footprintMax + _pairGap;
    _pairIndex = _pairIndex + 1;
};

// Groups that do NOT participate are DETACHED from the trail column: clear any
// residual trail offset and shoulder so they neither take a pair position now nor
// corrupt the pairing of a later compaction. Their lane ceiling does not change, so
// `trailLaneTargetIdx` is left untouched.
{
    private _grpId = _x;
    private _entry = _y;
    if (_entry isEqualType createHashMap) then {
        private _off = _entry getOrDefault ["trailOffsetDist", -1];
        private _isMember = (_off isEqualType 0) && { _off > 0 }
                         && { ((_entry getOrDefault ["platoonId", -1]) == _pltId) }
                         && { ((_entry getOrDefault ["movingMode", ""])) == "FOLLOWING_TRAIL" };
        if (!_isMember) then {
            private _hasOffset = (_off isEqualType 0) && { _off > 0 };
            private _hasShoulder = ((_entry getOrDefault ["trailShoulderOffset", 0]) != 0);
            if (_hasOffset || { _hasShoulder }) then {
                _entry set ["trailOffsetDist", 0];
                _entry set ["trailShoulderOffset", 0];
                FTCS_Groups_Registry_Table set [_grpId, _entry];
            };
        };
    };
} forEach FTCS_Groups_Registry_Table;

// Lock the layout and update the max offset for the trail trimming logic
_anchor set ["columnLayout", "COMPACT"];
_anchor set ["maxTrailOffset", _cursor + ((_count min 2) * _pairStep)];

if (missionNamespace getVariable ["FTCS_Debug_Mode", false]) then {
    // Eligible groups vs pairs actually formed: an odd count leaves the LAST group
    // unpaired on purpose, but a count that does not match the live column means the
    // participant filter is letting outsiders in (Lesson 29).
    diag_log format ["[FTCS][TRAIL][COMPACT] plt %1: %2 participants -> %3 pairs, unpaired=%4, depth=%5m",
        _pltId, _count, _pairIndex, (_count % 2), (round _cursor)];
};

systemChat format ["[TRAIL COMPACT] Double lane engaged: %1 pairs, chain depth %2m.", _pairIndex, round _cursor];
_pairIndex
