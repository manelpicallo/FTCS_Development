/*
    ================================================================================
    File: fn_commandMenusRefresh.sqf
    Module: UI
    Author: FTCS Team
    Description: Sole owner of the ENABLE STATE of the dynamic command menus. Reads
                 the registry (never the doctrine, Point 16) and rewrites the
                 enabled flag (element 6) and the dynamic captions of every menu
                 whose availability depends on live tactical state:

                    FTCS_MENU_PlatoonScouts        (detached scout slots)
                    FTCS_MENU_ScoutScreen_Deploy   (squad scout screen slots)
                    FTCS_MENU_PlatoonFormations_P1 (Relative / Absolute follow)
                    FTCS_MENU_RoadMarchLayout      (staggered / shoulders / trail /
                                                    COMPACT / edge margin rows)
                    FTCS_MENU_SquadDirectives      (hub: one row per squad)
                    FTCS_MENU_SquadOrders_1..4     (movement rows gated by target)

                 ============================ WHY IT EXISTS ==========================
                 This block used to live inline inside fn_openSubordinateMenu, so the
                 menu state was only recomputed WHEN SOMEONE OPENED A MENU. The
                 consequences observed in game:

                   - Compact Column stayed grey after ordering Leader Trail Column
                     (the flag was computed before the anchor existed), so it could
                     not be reached until the whole menu was reopened from scratch;
                   - two threads could run the rebuild at the same time (the addAction
                     click and the march dispatcher), which is what produced the
                     "Undefined variable" storm reported at line 281 of
                     fn_openSubordinateMenu (Lesson 28).

                 Layering: this file owns STATE -> MENU FLAGS. fn_openSubordinateMenu
                 only decides WHICH menu to show and shows it. Dispatchers that change
                 the march world (fn_applyCommandToTarget) call this function when the
                 order is applied, so the flags are already correct the next time a
                 menu is displayed.

                 ============================ THE RE-ENTRANCY GUARD ==================
                 The rebuild is IDEMPOTENT but not re-entrant: SQF `private` lives in
                 the scope of the SCRIPT, so a second simultaneous invocation
                 re-declares the variables the first one is still holding inside its
                 own `for` loops (Lesson 28). A single bool sentinel in
                 missionNamespace makes the second caller skip the rebuild - the
                 arrays are already up to date after the first one.

     Params:
         0: NUMBER - Platoon ID to refresh (default: player platoon).
     Returns:
         BOOLEAN - true when the menus were refreshed, false when the call was
                   skipped (re-entrant invocation) or the menu arrays are absent.
     Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params [["_pltId", -1, [0]]];

if (_pltId < 0) then { _pltId = missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1]; };

// --- 0. Re-entrancy guard ------------------------------------------------------
// A skipped refresh is harmless: the other invocation is writing the same values.
if (missionNamespace getVariable ["FTCS_Menu_RefreshBusy", false]) exitWith { false };
missionNamespace setVariable ["FTCS_Menu_RefreshBusy", true];

// Every menu definition lives in missionNamespace, created once by the menu
// initializer. If none of them exists there is nothing to refresh (init not run).
if (isNil "FTCS_MENU_RoadMarchLayout") exitWith {
    missionNamespace setVariable ["FTCS_Menu_RefreshBusy", false];
    false
};

// ---------------------------------------------------------------------------
// 1. Follow mode (Platoon Formations menu)
// The currently active mode appears greyed ("0") so the alternative is selectable.
// Indices in FTCS_MENU_PlatoonFormations_P1:
//   select 9 -> Option 9: Relative
//   select 10 -> Option 10: Absolute
// ---------------------------------------------------------------------------
private _currentFollowMode = missionNamespace getVariable ["FTCS_Platoon_Follow_Mode", "FOLLOWING_COMMANDER_REL"];
if (_currentFollowMode == "FOLLOWING_COMMANDER_REL") then {
    (FTCS_MENU_PlatoonFormations_P1 select 9) set [6, "0"]; // Relative disabled (gray)
    (FTCS_MENU_PlatoonFormations_P1 select 10) set [6, "1"]; // Absolute enabled (white)
} else {
    (FTCS_MENU_PlatoonFormations_P1 select 9) set [6, "1"]; // Relative enabled (white)
    (FTCS_MENU_PlatoonFormations_P1 select 10) set [6, "0"]; // Absolute disabled (gray)
};

// ---------------------------------------------------------------------------
// 2. Detached scout slots (Slots 11, 12, 7, 6, 8, 5)
// A slot is greyed while a COMBAT-EFFECTIVE team occupies it; if every soldier of
// that team is dead or incapacitated the slot is re-enabled so fresh scouts can
// reinforce it. PHASE 3: formationSlots is read from the platoon REGISTRY (RULE 16);
// the accessor falls back to the doctrine mirror while the migration is in flight.
// ---------------------------------------------------------------------------
private _activeSlotsMap = [_pltId, "formationSlots", createHashMap] call FTCS_fnc_registryGetPlatoon;
if (!(_activeSlotsMap isEqualType createHashMap)) then { _activeSlotsMap = createHashMap; };

private _fnc_isSlotOccupiedAndEffective = {
    params ["_slotNum"];
    private _isOccupied = false;
    if (_slotNum in _activeSlotsMap) then {
        private _grpCandidate = grpNull;
        if (!isNil "Platoon_Formation_Position_List" && {count Platoon_Formation_Position_List > _slotNum}) then {
            _grpCandidate = (Platoon_Formation_Position_List select _slotNum) select 2;
        };
        if (isNull _grpCandidate && {!isNil "FTCS_Groups_Registry_Table"}) then {
            {
                if ((_y getOrDefault ["allocationSlot", -1]) == _slotNum) exitWith {
                    private _cand = missionNamespace getVariable [_x, grpNull];
                    if (!isNull _cand) then { _grpCandidate = _cand; };
                };
            } forEach FTCS_Groups_Registry_Table;
        };
        if (!isNull _grpCandidate) then {
            private _effectiveCount = { alive _x && {lifeState _x != "INCAPACITATED"} } count (units _grpCandidate);
            _isOccupied = (_effectiveCount > 0);
        };
    };
    _isOccupied
};

if (!isNil "FTCS_MENU_Platoon_Scouts") then {
    private _occ11 = [11] call _fnc_isSlotOccupiedAndEffective;
    private _occ12 = [12] call _fnc_isSlotOccupiedAndEffective;
    private _occ7  = [7] call _fnc_isSlotOccupiedAndEffective;
    private _occ6  = [6] call _fnc_isSlotOccupiedAndEffective;
    private _occ8  = [8] call _fnc_isSlotOccupiedAndEffective;
    private _occ5  = [5] call _fnc_isSlotOccupiedAndEffective;

    (FTCS_MENU_Platoon_Scouts select 1) set [6, if (_occ11) then { "0" } else { "1" }]; // Left Flank (Slot 11)
    (FTCS_MENU_Platoon_Scouts select 2) set [6, if (_occ12) then { "0" } else { "1" }]; // Right Flank (Slot 12)
    (FTCS_MENU_Platoon_Scouts select 3) set [6, if (_occ7)  then { "0" } else { "1" }]; // Front Left (Slot 7)
    (FTCS_MENU_Platoon_Scouts select 4) set [6, if (_occ6)  then { "0" } else { "1" }]; // Front Center (Slot 6)
    (FTCS_MENU_Platoon_Scouts select 5) set [6, if (_occ8)  then { "0" } else { "1" }]; // Front Right (Slot 8)
    (FTCS_MENU_Platoon_Scouts select 6) set [6, if (_occ5)  then { "0" } else { "1" }]; // Rear (Slot 5)
};

// Squad-level scout screen menu
if (!isNil "FTCS_MENU_ScoutScreen_Deploy") then {
    private _occ11s = [11] call _fnc_isSlotOccupiedAndEffective;
    private _occ12s = [12] call _fnc_isSlotOccupiedAndEffective;
    private _occ6s  = [6] call _fnc_isSlotOccupiedAndEffective;
    private _occ7s  = [7] call _fnc_isSlotOccupiedAndEffective;
    private _occ8s  = [8] call _fnc_isSlotOccupiedAndEffective;
    private _occ5s  = [5] call _fnc_isSlotOccupiedAndEffective;

    (FTCS_MENU_ScoutScreen_Deploy select 1) set [6, if (_occ11s) then { "0" } else { "1" }]; // Slot 11
    (FTCS_MENU_ScoutScreen_Deploy select 2) set [6, if (_occ12s) then { "0" } else { "1" }]; // Slot 12
    (FTCS_MENU_ScoutScreen_Deploy select 3) set [6, if (_occ6s)  then { "0" } else { "1" }]; // Slot 6
    (FTCS_MENU_ScoutScreen_Deploy select 4) set [6, if (_occ7s)  then { "0" } else { "1" }]; // Slot 7
    (FTCS_MENU_ScoutScreen_Deploy select 5) set [6, if (_occ8s)  then { "0" } else { "1" }]; // Slot 8
    (FTCS_MENU_ScoutScreen_Deploy select 6) set [6, if (_occ5s)  then { "0" } else { "1" }]; // Slot 5
};

// ---------------------------------------------------------------------------
// 3. Road March Column Layout menu
// Rows: 0=title, 1=staggered, 2=left, 3=right, 4=trail, 5=compact,
//       6=push, 7=pull, 8=reset
// Row 5 = Compact Column: enabled with a ROAD column in STAGGERED/COMPACT layout,
// OR with an active leader-TRAIL column not yet compacted (the trail double-lane
// router in fn_applyCommandToTarget, PLT_ROAD_COMPACT). Disabled under
// single-shoulder LEFT/RIGHT road columns (already single-file, nothing to compact).
// Rows 6-8 = stepped edge margin (road world only): push while below the 4-step
// cap, pull-in / reset only while pushed out.
// ---------------------------------------------------------------------------
private _anchorM = missionNamespace getVariable [format ["FTCS_Road_Anchor_PLT_%1", _pltId], createHashMap];
private _roadActive = count (_anchorM getOrDefault ["roadPath", []]) >= 2;
private _roadLayout = _anchorM getOrDefault ["columnLayout", "STAGGERED"];
private _trailAnchorM = missionNamespace getVariable [format ["FTCS_Trail_Anchor_PLT_%1", _pltId], createHashMap];
private _trailActive = count (_trailAnchorM getOrDefault ["trailPath", []]) >= 2;
private _trailLayout = _trailAnchorM getOrDefault ["columnLayout", "STAGGERED"];
private _edgeSteps = _anchorM getOrDefault ["edgeMarginSteps", 0];

private _compactAllowed = (_roadActive && { _roadLayout in ["STAGGERED", "COMPACT"] })
                       || (_trailActive && { _trailLayout == "STAGGERED" });
(FTCS_MENU_RoadMarchLayout select 5) set [6, if (_compactAllowed) then { "1" } else { "0" }];
// Rows 2/3 = single-shoulder columns (LEFT/RIGHT): ALWAYS enabled - they deploy the
// full road pipeline with a forced side, no prior staggered column required.
(FTCS_MENU_RoadMarchLayout select 2) set [6, "1"];
(FTCS_MENU_RoadMarchLayout select 3) set [6, "1"];

private _rowPush = FTCS_MENU_RoadMarchLayout select 6;
_rowPush set [6, if (_roadActive && { _edgeSteps < 4 }) then { "1" } else { "0" }];
_rowPush set [0, if (_edgeSteps > 0) then {
    format ["6. Push Out From Road (+3m) [OUT x%1/4]", _edgeSteps]
} else {
    "6. Push Out From Road (+3m)"
}];
(FTCS_MENU_RoadMarchLayout select 7) set [6, if (_roadActive && { _edgeSteps > 0 }) then { "1" } else { "0" }];
(FTCS_MENU_RoadMarchLayout select 8) set [6, if (_roadActive && { _edgeSteps > 0 }) then { "1" } else { "0" }];

// ---------------------------------------------------------------------------
// 4. Squad & Scout Directives hub + Squad Orders submenus (dynamic rebuild)
// One hub entry per doctrinal squad (3 or 4, real doctrine names) plus the scouts
// row; each Squad Orders submenu enables its movement rows only when the squad
// captured its OWN target (Targeting class) and highlights Rejoin when the squad
// is detached/pinned from its formation slot.
//
// PHASE 8b: squad EXISTENCE comes from the registry ("squadId"), so the hub shows
// exactly the squads that are actually registered. The doctrine tree is consulted
// ONLY for the display caption (Point 18: label, not identity).
//
// ALL loop variables are declared ONCE, before the loops: a `private` inside a
// `for` body lives in the SCRIPT scope, so the next iteration re-declares it while
// the previous one may still be in flight (Lesson 28) - and a re-entrant call would
// wipe it under the running loop.
// ---------------------------------------------------------------------------
private _pltKeyD = format ["PLT_%1", _pltId];
// FTCS_Company_Data is a missionNamespace GLOBAL, read through getVariable and
// type-guarded: the tree can legitimately be absent (menu opened from the self
// command net before the doctrine is applied). A missing tree only degrades the
// CAPTIONS - row gating comes from the registry.
private _companyTreeD = missionNamespace getVariable ["FTCS_Company_Data", createHashMap];
if (!(_companyTreeD isEqualType createHashMap)) then { _companyTreeD = createHashMap; };
private _platoonsMapD = _companyTreeD getOrDefault ["platoons", createHashMap];
if (!(_platoonsMapD isEqualType createHashMap)) then { _platoonsMapD = createHashMap; };
private _pltDataD = _platoonsMapD getOrDefault [_pltKeyD, createHashMap];
if (!(_pltDataD isEqualType createHashMap)) then { _pltDataD = createHashMap; };
private _parsedSquadsD = _pltDataD getOrDefault ["parsedSquads", createHashMap];
if (!(_parsedSquadsD isEqualType createHashMap)) then { _parsedSquadsD = createHashMap; };
private _regSquadIds = createHashMap;
{ if (((_y) getOrDefault ["platoonId", -1]) == _pltId) then { _regSquadIds set [(_y) getOrDefault ["squadId", ""], true]; }; } forEach FTCS_Groups_Registry_Table;

private _sqdKeyD = "";
private _sDataD = createHashMap;
private _hasSquadD = false;
private _hubRow = [];
private _doctName = "";
private _menuArr = [];
private _teamsD = createHashMap;
private _sqdHasTgt = false;
private _sqdGrpD = grpNull;
private _eD = createHashMap;

// Hub rebuild: rows 2-5 map to squads 1-4 (show only existing doctrinal squads)
for "_si" from 1 to 4 do {
    _sqdKeyD = format ["SQD_%1_%2", _pltId, _si];
    _sDataD = _parsedSquadsD getOrDefault [_sqdKeyD, createHashMap];
    if (!(_sDataD isEqualType createHashMap)) then { _sDataD = createHashMap; };
    _hasSquadD = (_sqdKeyD in _regSquadIds);
    _hubRow = FTCS_MENU_SquadDirectives select (1 + _si);
    _doctName = _sDataD getOrDefault ["name", format ["Squad %1", _si]];
    _hubRow set [0, format ["%1. %2", _si + 1, _doctName]];
    _hubRow set [6, if (_hasSquadD) then { "1" } else { "0" }];
};

// Squad Orders submenus (rows: 0=title, 1=mark, 2-4=movement, 5-7=in-formation, 8=rejoin)
// PER-SQUAD gating: the movement rows mirror the squad's OWN captured target (any of
// its teams carrying "squadTarget"), never the global commander target - one squad's
// capture cannot unlock another squad's movement rows. Same rule as the menu builder.
for "_si2" from 1 to 4 do {
    _menuArr = missionNamespace getVariable [format ["FTCS_MENU_SquadOrders_%1", _si2], []];
    if (count _menuArr >= 9) then {
        // Resolve this squad's bound teams from the parsed doctrine data
        _sqdKeyD = format ["SQD_%1_%2", _pltId, _si2];
        _sDataD = _parsedSquadsD getOrDefault [_sqdKeyD, createHashMap];
        if (!(_sDataD isEqualType createHashMap)) then { _sDataD = createHashMap; };
        _teamsD = _sDataD getOrDefault ["tacticalTeams", createHashMap];
        if (!(_teamsD isEqualType createHashMap)) then { _teamsD = createHashMap; };
        if (count _teamsD == 0) then { _teamsD = _sDataD getOrDefault ["teams", createHashMap]; };
        if (!(_teamsD isEqualType createHashMap)) then { _teamsD = createHashMap; };

        // Squad owns a target when ANY of its team registry entries (or the
        // squad-level group fallback) carries a populated "squadTarget"
        _sqdHasTgt = false;
        {
            private _grpD = (_y) getOrDefault ["group", grpNull];
            if (!isNull _grpD) then {
                _eD = FTCS_Groups_Registry_Table getOrDefault [groupId _grpD, createHashMap];
                if (count (_eD getOrDefault ["squadTarget", []]) >= 8) exitWith { _sqdHasTgt = true; };
            };
        } forEach _teamsD;
        if (!_sqdHasTgt) then {
            _sqdGrpD = _sDataD getOrDefault ["group", grpNull];
            if (!isNull _sqdGrpD) then {
                _eD = FTCS_Groups_Registry_Table getOrDefault [groupId _sqdGrpD, createHashMap];
                if (count (_eD getOrDefault ["squadTarget", []]) >= 8) then { _sqdHasTgt = true; };
            };
        };

        (_menuArr select 0) set [0, format ["Squad Orders - Squad %1%2", _si2, if (_sqdHasTgt) then { " [TGT MARKED]" } else { "" }]];
        for "_ri" from 2 to 4 do {
            (_menuArr select _ri) set [6, if (_sqdHasTgt) then { "1" } else { "0" }];
        };
    };
};

missionNamespace setVariable ["FTCS_Menu_RefreshBusy", false];

true
