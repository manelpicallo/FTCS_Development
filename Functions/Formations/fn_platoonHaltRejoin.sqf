/*
    ================================================================================
    File: fn_platoonHaltRejoin.sqf
    Module: Formations
    Author: FTCS Team
    Description: PLATOON-level HALT and REJOIN primitive (lieutenant orders).

                 PLT_HALT:
                  - Freezes every formation group: movingMode = "HALT" written
                    into every group registry entry (squads, bound fireteams,
                    detached scouts). Follow loops exit on their own (their
                    mode no longer matches).
                  - Snapshot stored REGISTRY-FIRST: platoon orderState "HALTED",
                    haltSnapshotLeaderPos + haltFacing (platoon advance axis).
                  - The platoon leader is NOT frozen: he keeps exploring.

                 PLT_REJOIN (facingMode: 0 = KEEP halt facing, 1 = NEW = the
                 lieutenant's CURRENT axis):
                  - KEEP contract: the frozen axis is written to ALL axis
                    variables (REL live dir + ABS fixed compass) before the
                    loops respawn. In REL it governs the ARRIVAL deployment
                    only (the march branch takes over as soon as the lieutenant
                    walks); in ABS it PERSISTS (fixed compass contract).
                  - Squads converge on the CURRENT platoon leader position:
                    each squad's frozen offset from the halt snapshot leader
                    position is rotated onto the rejoin facing and the squad
                    re-anchors there (mvFormationShift) + follow loop respawned
                    on the lieutenant.
                  - Fireteams follow their own squad leader (parentSquadGroup).
                    Hierarchy split squad vs fireteam is driven by the registry
                    fields seeded by fn_registryInit: isSquadLeaderGroup marks
                    the squad anchor, squadId groups the teams of one squad.
                    A fireteam without a valid anchor is logged and left alone
                    (never re-anchored to the lieutenant - Point 18 invariant).
                  - Detached scouts (slot 5/6/7/8/11/12 + DETACHED_FREE) re-
                    anchor to the lieutenant like squads.
                  - State returns to "MARCH"; snapshot cleared.

     Registry layout:
         platoon entry (FTCS_Platoons_Registry > pltId [NUMBER key]):
             "orderState"            : "MARCH" | "HALTED" | "REJOINING"
             "haltSnapshotLeaderPos" : [x, y, z]
             "haltFacing"            : NUMBER
             "squads"                : ARRAY of GROUP (squad anchors, seeded by
                                       fn_registryInit - see Point 18 invariant)
         group entry (FTCS_Groups_Registry_Table > groupId):
             "haltedAtPos"           : [x, y, z]  (set on HALT, cleared on REJOIN)
             "parentSquadGroup"      : GROUP      (squad anchor, seeded by registryInit)
             "isSquadLeaderGroup"    : BOOLEAN    (TRUE only on the squad anchor)
             "squadId"               : STRING     ("SQD_1_1" doctrine key)

     Params:
         0: STRING - "HALT" | "REJOIN".
         1: NUMBER - OPTIONAL platoon ID (default: player's platoon).
         2: NUMBER - OPTIONAL rejoin facing mode (0 = keep halt facing,
                     1 = lieutenant current facing; default 0).
     Returns:
         BOOLEAN - true when the order was applied.
     Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params [["_order", ""], ["_pltId", -1, [-1]], ["_facingMode", 0, [0]]];

if (!(_order in ["HALT", "REJOIN"])) exitWith {
    systemChat format ["[PLT HALT/REJOIN] Unknown order '%1'.", _order];
    false
};
if (_pltId < 0) then { _pltId = missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1]; };

// --- Resolve the platoon registry entry (RULE 16: the ORBAT comes from the
//     PLATOON REGISTRY, seeded by fn_registryInit with a NUMBER key - same key
//     type used here. Runtime NEVER re-derives squads from FTCS_Company_Data).
private _registry = missionNamespace getVariable ["FTCS_Platoons_Registry", createHashMap];
private _plt = _registry getOrDefault [_pltId, createHashMap];
private _squadList = (_plt getOrDefault ["squads", []]) select { !isNull _x };

if (count _squadList == 0) exitWith {
    systemChat format ["[PLT HALT] Error: platoon %1 has no registered squads.", _pltId];
    diag_log format ["[FTCS][HALT] plt %1: no squads in registry - HALT aborted.", _pltId];
    false
};

// --- Platoon leader (lieutenant) resolution ----------------------------------
private _pltLeader = missionNamespace getVariable ["FTCS_Platoon_Leader_Unit", objNull];
if (isNull _pltLeader) then {
    private _pltGrp = _plt getOrDefault ["platoonGroup", grpNull];
    if (!isNull _pltGrp) then { _pltLeader = leader _pltGrp; };
};
if (isNull _pltLeader) exitWith {
    systemChat format ["[PLT %1] Error: platoon leader not found.", _order];
    false
};

private _groupsRegistry = missionNamespace getVariable ["FTCS_Groups_Registry_Table", createHashMap];

// groupId display names are NOT valid missionNamespace identifiers (spaces/
// parentheses), so live groups are resolved by matching groupId against
// allGroups - the registry key IS the group's groupId.
private _liveGroupMap = createHashMap;
{ if (!isNull _x) then { _liveGroupMap set [groupId _x, _x]; }; } forEach allGroups;

// ============================================================================
// HALT
// ============================================================================
if (_order == "HALT") then {

    // --- Hierarchy traversal: platoon -> squads -> bound fireteams + scouts --
    // Membership is resolved by the registry hierarchy fields only (RULE 16):
    //   parentSquadGroup     -> anchor group (squad leader element) of the team
    //   isSquadLeaderGroup   -> TRUE on the anchor itself
    // Both are seeded deterministically by fn_registryInit from the doctrinal
    // team type, so no group is ever classified by "first team found".
    private _allGroups = [];
    {
        private _sqd = _x;
        _allGroups pushBack _sqd;
        private _fireteamCount = 0;
        {
            private _key = format ["%1", _x];
            private _entry = _y;
            private _parent = _entry getOrDefault ["parentSquadGroup", grpNull];
            if (!isNull _parent && { _parent == _sqd } && { !(_entry getOrDefault ["isSquadLeaderGroup", false]) }) then {
                private _g = _liveGroupMap getOrDefault [_key, grpNull];
                if (!isNull _g && { !(_g in _allGroups) }) then {
                    _allGroups pushBack _g;
                    _fireteamCount = _fireteamCount + 1;
                };
            };
        } forEach _groupsRegistry;
        diag_log format ["[FTCS][HALT] squad '%1' : %2 fireteams collected.", groupId _sqd, _fireteamCount];
    } forEach _squadList;

    // Detached scouts with a direct platoon slot (genuinely emplaced teams are
    // excluded by the slot+attachment filter): they freeze where they are and
    // that frozen spot becomes their formation point.
    {
        private _key = format ["%1", _x];
        private _entry = _y;
        private _slot = _entry getOrDefault ["allocationSlot", -1];
        if (_slot in [5, 6, 7, 8, 11, 12]
            && { (_entry getOrDefault ["teamAttachment", ""]) == "DETACHED_FREE" }) then {
            private _g = _liveGroupMap getOrDefault [_key, grpNull];
            if (!isNull _g && { !(_g in _allGroups) }) then {
                _allGroups pushBack _g;
                diag_log format ["[FTCS][HALT] detached scout '%1' (slot %2) collected.", _key, _slot];
            };
        };
    } forEach _groupsRegistry;

    // --- Snapshot registry-first (needed by REJOIN later) --------------------
    private _haltFacing = [_pltLeader] call FTCS_fnc_platoonAdvanceAxis;
    _plt set ["orderState", "HALTED"];
    _plt set ["haltSnapshotLeaderPos", getPosATL _pltLeader];
    _plt set ["haltFacing", _haltFacing];
    _registry set [_pltId, _plt];
    missionNamespace setVariable ["FTCS_Platoons_Registry", _registry];

    // --- THE ACTION: movingMode = "HALT" + frozen position per group ---------
    private _written = 0;
    {
        if (!isNull _x) then {
            private _grpId = groupId _x;
            [_grpId, "movingMode", "HALT"] call FTCS_fnc_registrySet;
            [_grpId, "haltedAtPos", getPosATL (leader _x)] call FTCS_fnc_registrySet;
            _written = _written + 1;
            diag_log format ["[FTCS][HALT] %1 : movingMode=HALT + haltedAtPos escrito (platoon %2).", _grpId, _pltId];
        };
    } forEach _allGroups;

    systemChat format ["[PLT HALT] %1 grupos congelados (facing %2 deg). El teniente sigue explorando.", _written, round _haltFacing];
    diag_log format ["[FTCS][HALT] plt %1: HALT completado - %2/%3 grupos congelados.", _pltId, _written, count _allGroups];

// ============================================================================
// REJOIN
// ============================================================================
} else {

    private _state = _plt getOrDefault ["orderState", "MARCH"];
    if (_state != "HALTED") exitWith {
        systemChat "[PLT REJOIN] Refused: the platoon is not HALTED - issue HALT first.";
        diag_log format ["[FTCS][REJOIN] plt %1: refused (orderState=%2).", _pltId, _state];
        false
    };

    private _snapshotLeaderPos = _plt getOrDefault ["haltSnapshotLeaderPos", getPosATL _pltLeader];
    // Facing mode: 0 = KEEP the axis frozen at HALT, 1 = NEW = lieutenant's
    // CURRENT axis of advance. The frozen geometry is rotated onto this facing.
    private _rejoinFacing = if (_facingMode == 1) then {
        [_pltLeader] call FTCS_fnc_platoonAdvanceAxis
    } else {
        _plt getOrDefault ["haltFacing", [_pltLeader] call FTCS_fnc_platoonAdvanceAxis]
    };

    private _followModeR = missionNamespace getVariable ["FTCS_Platoon_Follow_Mode", "FOLLOWING_COMMANDER_REL"];
    if (!(_followModeR in ["FOLLOWING_COMMANDER_REL", "FOLLOWING_COMMANDER_ABS"])) then {
        _followModeR = "FOLLOWING_COMMANDER_REL";
    };

    _plt set ["orderState", "REJOINING"];
    _registry set [_pltId, _plt];
    missionNamespace setVariable ["FTCS_Platoons_Registry", _registry];

    // VARIANT A (KEEP facing): pin the CANONICAL platoon axis to haltFacing
    // BEFORE respawning the follow loops, in ALL THREE axis variables the
    // pipeline can read:
    //   REL -> FTCS_Platoon_Advance_Direction / Last_Commander_Dir
    //   ABS -> FTCS_Platoon_Fixed_Abs_Dir (fn_platoonAdvanceAxis priority 2)
    // Without the ABS write, KEEP was a no-op in absolute mode: the follow
    // loops and fn_mvFormationShift kept projecting on whatever Fixed_Abs_Dir
    // value was in force before the HALT.
    // CONTRACT: in REL the frozen axis only governs the ARRIVAL deployment -
    // the active-march branch rewrites it live as soon as the lieutenant walks
    // (>2 km/h), which is exactly the REL contract (formation turns with him).
    // In ABS the frozen axis PERSISTS, which is the ABS contract (fixed
    // compass bearing until a new formation/ABS order).
    if (_facingMode == 0) then {
        missionNamespace setVariable ["FTCS_Last_Commander_Dir", _rejoinFacing];
        missionNamespace setVariable ["FTCS_Platoon_Advance_Direction", _rejoinFacing];
        missionNamespace setVariable ["FTCS_Platoon_Fixed_Abs_Dir", _rejoinFacing];
    };

    // Gather participants exactly like HALT did (squads + fireteams + scouts).
    // Same registry hierarchy contract as the HALT pass above (parentSquadGroup
    // + isSquadLeaderGroup), so both orders see the SAME participant set.
    private _allGroups = [];
    { _allGroups pushBack _x; } forEach _squadList;
    {
        private _key = format ["%1", _x];
        private _entry = _y;
        private _parent = _entry getOrDefault ["parentSquadGroup", grpNull];
        if (!isNull _parent && { _parent in _squadList } && { !(_entry getOrDefault ["isSquadLeaderGroup", false]) }) then {
            private _g = _liveGroupMap getOrDefault [_key, grpNull];
            if (!isNull _g && { !(_g in _allGroups) }) then { _allGroups pushBack _g; };
        };
    } forEach _groupsRegistry;
    {
        private _key = format ["%1", _x];
        private _entry = _y;
        private _slot = _entry getOrDefault ["allocationSlot", -1];
        if (_slot in [5, 6, 7, 8, 11, 12]
            && { (_entry getOrDefault ["teamAttachment", ""]) == "DETACHED_FREE" }) then {
            private _g = _liveGroupMap getOrDefault [_key, grpNull];
            if (!isNull _g && { !(_g in _allGroups) }) then { _allGroups pushBack _g; };
        };
    } forEach _groupsRegistry;

    private _rejoined = 0;
    {
        // Null groups were filtered at gather time; the guard is kept as a
        // positive if-block (never `continue` inside forEach - see Lesson 1).
        if (!isNull _x) then {
            private _grpId = groupId _x;
            private _entry = _groupsRegistry getOrDefault [_grpId, createHashMap];

            // Restore pacing and resume the active follow mode
            { _x limitSpeed -1; } forEach (units _x);
            [_grpId, "movingMode", _followModeR] call FTCS_fnc_registrySet;
            [_grpId, "haltedAtPos", nil] call FTCS_fnc_registrySet;

            private _haltPos = _entry getOrDefault ["haltedAtPos", getPosATL (leader _x)];

            private _slot = _entry getOrDefault ["allocationSlot", -1];
            private _isDetachedScout = (_slot in [5, 6, 7, 8, 11, 12]
                && { (_entry getOrDefault ["teamAttachment", ""]) == "DETACHED_FREE" });

            if (_x in _squadList || _isDetachedScout) then {
                // Squad / detached scout: re-anchor its frozen offset from the
                // halt snapshot leader position, rotated onto the rejoin facing.
                private _frozenOffset = _haltPos vectorDiff _snapshotLeaderPos;
                private _dist = vectorMagnitude _frozenOffset;
                private _bearing = if (_dist > 1) then { _snapshotLeaderPos getDir _haltPos } else { _rejoinFacing };
                // KEEP: preserve the frozen absolute bearing. NEW: rotate the
                // geometry so the offset lands on the CURRENT advance axis.
                private _targetBearing = if (_facingMode == 1 && _dist > 1) then {
                    _rejoinFacing + (_bearing - (_plt getOrDefault ["haltFacing", _rejoinFacing]))
                } else { _bearing };
                private _target = (getPosATL _pltLeader) getPos [_dist, _targetBearing];

                if (!_isDetachedScout) then {
                    [_x, _target] call FTCS_fnc_mvFormationShift;
                };
                [_x, _followModeR, _pltLeader] spawn FTCS_fnc_formationsGroupDoFollowCommander;
                _rejoined = _rejoined + 1;
                diag_log format ["[FTCS][REJOIN] %1 re-anchoring to %2 (dist %3m, bearing %4).", _grpId, _target, round _dist, round _targetBearing];
            } else {
                // Fireteam: respawn its follow loop with its OWN squad leader as
                // reference (same hierarchy it had before the halt). No lieutenant
                // fallback: that would violate the hierarchy invariant (Point 18).
                private _parentSqd = _entry getOrDefault ["parentSquadGroup", grpNull];
                // SELF-HEAL: if the anchor link was lost (e.g. a recalled scout whose
                // parentSquadGroup was cleared while it sat in a platoon slot), the
                // group still knows its squad through "squadId". Rebuild the link
                // from the registry so the team rejoins its OWN squad, never the
                // lieutenant.
                if (isNull _parentSqd) then {
                    private _sqdIdR = _entry getOrDefault ["squadId", ""];
                    if (_sqdIdR != "") then {
                        {
                            if (isNull _parentSqd
                                && { ((_y) getOrDefault ["squadId", ""]) isEqualTo _sqdIdR }
                                && { (_y) getOrDefault ["isSquadLeaderGroup", false] }) then {
                                _parentSqd = _liveGroupMap getOrDefault [_key, grpNull];
                            };
                        } forEach _groupsRegistry;
                        if (!isNull _parentSqd) then {
                            [_grpId, "parentSquadGroup", _parentSqd] call FTCS_fnc_registrySet;
                            [_grpId, "teamAttachment", "SQUAD_BOUND"] call FTCS_fnc_registrySet;
                            [_grpId, "allocationSlot", -1] call FTCS_fnc_registrySet;
                            diag_log format ["[FTCS][REJOIN] %1 anchor self-healed from squadId '%2' -> '%3'.", _grpId, _sqdIdR, groupId _parentSqd];
                        };
                    };
                };
                if (!isNull _parentSqd && { !isNull (leader _parentSqd) }) then {
                    [_x, _followModeR, (leader _parentSqd)] spawn FTCS_fnc_formationsGroupDoFollowCommander;
                    _rejoined = _rejoined + 1;
                    diag_log format ["[FTCS][REJOIN] %1 (fireteam) follow respawned on squad-leader ref.", _grpId];
                } else {
                    diag_log format ["[FTCS][REJOIN] %1 (fireteam) SKIPPED: no parentSquadGroup anchor in registry.", _grpId];
                };
            };
        };
    } forEach _allGroups;

    // Snapshot cleared: orderState back to MARCH
    _plt set ["orderState", "MARCH"];
    _plt set ["haltSnapshotLeaderPos", nil];
    _plt set ["haltFacing", nil];
    _registry set [_pltId, _plt];
    missionNamespace setVariable ["FTCS_Platoons_Registry", _registry];

    systemChat format ["[PLT REJOIN] %1 elementos convergiendo (facing %2 deg).", _rejoined, round _rejoinFacing];
    diag_log format ["[FTCS][REJOIN] plt %1: REJOIN completado - %2 grupos re-anclados.", _pltId, _rejoined];
    true
};
