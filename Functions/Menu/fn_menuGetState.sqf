/*
    ================================================================================
    File: fn_menuGetState.sqf
    Module: Menu
    Author: FTCS Team
    Description: Reads the CURRENT tactical state of the player platoon ONCE per
                 menu opening and returns a compact description of it. Every menu
                 build (fn_menuBuild) and every grey/disable decision consumes this
                 snapshot instead of hitting the registry row by row, so a menu
                 opening costs ONE pass over the registry and cannot abort halfway
                 through the UI.

                 This function only READS. It never writes state, never issues AI
                 commands (Rule 15) and never re-reads the doctrine tree for
                 identity (Rule 16): squad EXISTENCE and the squad ANCHOR come from
                 the registry; the doctrine tree is consulted for the DISPLAY NAME
                 only (Rule 18 allows the name as a caption, never as an id).

    Return contract (HashMap):
        "platoonId"      : SCALAR
        "phase"          : SCALAR 0..3            (FTCS_Platoon_Phase_<N>)
        "followMode"     : STRING REL | ABS      (platoon REGISTRY followMode = order)
        "halted"         : BOOLEAN                (registry orderState == "HALTED")
        "formation"      : STRING                 (common platoonFormation; "NONE" until a formation order)
        "stance"         : STRING                 ("MIXED" when groups disagree)
        "speed"          : STRING                 ("MIXED" when groups disagree)
        "roe"            : STRING                 ("MIXED" when groups disagree)
        "moveTech"       : STRING                 (platoon registry movementTechnique)
        "scoutSlots"     : HashMap slot -> squadId ("") when occupied by NOBODY
        "squads"         : ARRAY of HashMap, ordered by doctrinal index:
                              "slot"       : SCALAR 1..N
                              "squadId"    : STRING "SQD_<plt>_<n>"
                              "group"      : GROUP  (anchor, grpNull if gone)
                              "name"       : STRING (doctrinal caption)
                              "leaderOk"   : BOOLEAN (leader alive AND not INCAPACITATED)
                              "leaderState": STRING HEALTHY|DEAD|INCAPACITATED|NO_GROUP
                              "effective"  : SCALAR (alive && not INCAPACITATED)
                              "movingMode" : STRING
                              "squadFormation": STRING
                              "squadStance": STRING
                              "hasTarget"  : BOOLEAN
    Language: Strictly English (Rule 7, Rule 11)
    ================================================================================
*/

params [["_pltId", 1]];

// ---------------------------------------------------------------------------
// ISOLATE THE ARGUMENTS (`params` does NOT create script-scope locals).
// Copying the argument into a fresh `private` makes every invocation own its
// own value.
// ---------------------------------------------------------------------------
private _plt = _pltId;

// Hard type contract (RPT 20:46:11): the platoon registry is keyed by NUMBER. A
// caller passing the wrong shape made `_plt` a HashMap, so line 60 aborted with
// "getOrDefault: expected Number,Bool,Array,String..." and line 130 with
// "Error !=: Type HashMap". Normalise the key ONCE here; every read below (phase
// global, registry lookup, group filter) then receives a number.
if (!(_plt isEqualType 0)) then { _plt = 1; };

// ---- 1. Platoon-level scalars ------------------------------------------------
private _state = createHashMap;
_state set ["platoonId", _plt];
_state set ["phase", missionNamespace getVariable [format ["FTCS_Platoon_Phase_%1", _plt], 0]];

private _pltReg = (missionNamespace getVariable ["FTCS_Platoons_Registry", createHashMap]) getOrDefault [_plt, createHashMap];
if (!(_pltReg isEqualType createHashMap)) then { _pltReg = createHashMap; };

// Follow mode is the ORDER the lieutenant gave the platoon (REL | ABS), read from
// the platoon registry sentinel (Rule 20) - never voted across groups.
_state set ["followMode", _pltReg getOrDefault ["followMode", "REL"]];

private _orderState = _pltReg getOrDefault ["orderState", "MARCH"];
_state set ["halted", (_orderState == "HALTED")];
_state set ["moveTech", _pltReg getOrDefault ["movementTechnique", "CROSS_COUNTRY"]];

// Commander reference ("gate_unit"): registry first, missionNamespace fallback.
// The registry carries it even when the lieutenant has no group at all (Lesson 5).
private _leaderUnit = _pltReg getOrDefault ["leaderUnit", objNull];
if (isNull _leaderUnit) then {
    _leaderUnit = missionNamespace getVariable ["FTCS_Platoon_Leader_Unit", objNull];
};
if (isNull _leaderUnit) then { _leaderUnit = player; };
_state set ["leaderUnit", _leaderUnit];

// Column anchors (road and trail) are read here ONCE so the March route gates and
// the Combat row labels never hit missionNamespace a second time.
// COLUMN LAYOUT resolution order: LIVE ANCHOR first, platoon-registry mirror as
// fallback (Point 0 Rule 16). The anchor HashMap is the operational truth (the
// trail queue-sync writer and the compact resolver mutate it every tick); the
// registry copy is only re-published by the march dispatcher, so it can lag one
// order behind. The inverse order greyed the Compact row while a trail column
// was marchable: the registry held the dispatch-time snapshot, the anchor held
// the live layout, and the stale copy won.
private _roadAnchor = missionNamespace getVariable [format ["FTCS_Road_Anchor_PLT_%1", _plt], createHashMap];
if (!(_roadAnchor isEqualType createHashMap)) then { _roadAnchor = createHashMap; };
private _trailAnchor = missionNamespace getVariable [format ["FTCS_Trail_Anchor_PLT_%1", _plt], createHashMap];
if (!(_trailAnchor isEqualType createHashMap)) then { _trailAnchor = createHashMap; };

private _pltRegState = _pltReg;
private _pltRegRoadAnchor = _pltRegState getOrDefault ["roadAnchor", createHashMap];
if (!(_pltRegRoadAnchor isEqualType createHashMap)) then { _pltRegRoadAnchor = createHashMap; };
private _pltRegTrailAnchor = _pltRegState getOrDefault ["trailAnchor", createHashMap];
if (!(_pltRegTrailAnchor isEqualType createHashMap)) then { _pltRegTrailAnchor = createHashMap; };

_state set ["roadActive", (count (_roadAnchor getOrDefault ["roadPath", []]) >= 2)];
_state set ["roadLayout", (_roadAnchor getOrDefault ["columnLayout", _pltRegRoadAnchor getOrDefault ["columnLayout", ""]])];
_state set ["edgeSteps", _roadAnchor getOrDefault ["edgeMarginSteps", 0]];
_state set ["trailActive", (count (_trailAnchor getOrDefault ["trailPath", []]) >= 2)];
_state set ["trailLayout", (_trailAnchor getOrDefault ["columnLayout", _pltRegTrailAnchor getOrDefault ["columnLayout", ""]])];

// ---- 2. ONE registry pass: squash the whole platoon ---------------------------
// Live group objects are resolved through a local groupId -> GROUP map built from
// allGroups: registry keys ARE the groupIds, but the registry may hold an orphan
// entry whose group no longer exists (deleteGroup, failed spawn). That orphan is
// exactly the "group not found" case the menus must expose as a grey row.
private _liveMap = createHashMap;
{ if (!isNull _x) then { _liveMap set [groupId _x, _x]; }; } forEach allGroups;

private _regTable = missionNamespace getVariable ["FTCS_Groups_Registry_Table", createHashMap];
if (!(_regTable isEqualType createHashMap)) then { _regTable = createHashMap; };

private _formationVote = [];
private _stanceVote = [];
private _speedVote = [];
private _roeVote = [];
private _scoutSlots = createHashMap;
private _squadIdx = createHashMap;   // squadId -> index in _squads

// Aggregated per squadId: anchor group, effective count, target flag, movingMode
private _agg = createHashMap;

{
    private _entry = _y;
    if (!(_entry isEqualType createHashMap)) then { _entry = createHashMap; };
    if ((_entry getOrDefault ["platoonId", -1]) != _plt) then { _entry = createHashMap; };

    if (count _entry > 0) then {
        // --- aggregate squad-level facts -----------------------------------
        private _sqdId = _entry getOrDefault ["squadId", ""];
        if (_sqdId != "") then {
            private _rec = _agg getOrDefault [_sqdId, createHashMap];
            if (!(_rec isEqualType createHashMap)) then { _rec = createHashMap; };
            if (!(_rec getOrDefault ["anchor", false]) && { _entry getOrDefault ["isSquadLeaderGroup", false] }) then {
                private _g = _liveMap getOrDefault [_x, grpNull];
                _rec set ["anchor", true];
                _rec set ["group", _g];
                _rec set ["movingMode", _entry getOrDefault ["movingMode", ""]];
                _rec set ["squadFormation", _entry getOrDefault ["squadFormation", ""]];
                _rec set ["squadStance", _entry getOrDefault ["stance", ""]];
            };
            private _gEff = _liveMap getOrDefault [_x, grpNull];
            if (!isNull _gEff) then {
                private _eff = { alive _x && { lifeState _x != "INCAPACITATED" } } count (units _gEff);
                _rec set ["effective", (_rec getOrDefault ["effective", 0]) + _eff];
            };
            if (count (_entry getOrDefault ["squadTarget", []]) >= 8) then { _rec set ["hasTarget", true]; };
            _agg set [_sqdId, _rec];
        };

        // --- scout slot occupancy ------------------------------------------
        // A slot is "in use" only when the group that owns it still exists and
        // has at least one soldier able to fight (Lesson: alive is NOT enough,
        // an INCAPACITATED soldier cannot screen anything).
        private _slot = _entry getOrDefault ["allocationSlot", -1];
        if (_slot in [5, 6, 7, 8, 11, 12]) then {
            private _gSlot = _liveMap getOrDefault [_x, grpNull];
            if (!isNull _gSlot) then {
                private _effSlot = { alive _x && { lifeState _x != "INCAPACITATED" } } count (units _gSlot);
                if (_effSlot > 0) then { _scoutSlots set [_slot, _sqdId]; };
            };
        };

        // --- votes for the "common state" rows -----------------------------
        _formationVote pushBack (_entry getOrDefault ["platoonFormation", ""]);
        _stanceVote pushBack (_entry getOrDefault ["stance", ""]);
        _speedVote pushBack (_entry getOrDefault ["speed", ""]);
        _roeVote pushBack (_entry getOrDefault ["roe", ""]);
    };
} forEach _regTable;

// Common value, or "MIXED" when the groups disagree (a mixed platoon must show
// every option as selectable, never pretend one value is active).
private _fnc_common = {
    params ["_arr"];
    _arr = _arr select { _x != "" };
    if (count _arr == 0) exitWith { "" };
    private _first = _arr select 0;
    private _same = true;
    { if (_x != _first) then { _same = false; }; } forEach _arr;
    if (_same) then { _first } else { "MIXED" }
};

// Common formation, or "MIXED" when the groups disagree. A platoon that has never
// received a formation order carries "NONE" on every group (fn_registryInit seed),
// so "NONE" is a real state the menu can grey out - it is NOT an empty string.
_state set ["formation", [_formationVote] call _fnc_common];
_state set ["stance", [_stanceVote] call _fnc_common];
_state set ["speed", [_speedVote] call _fnc_common];
_state set ["roe", [_roeVote] call _fnc_common];
_state set ["scoutSlots", _scoutSlots];

// ---- 3. Doctrinal caption (LABEL ONLY - Rule 18) -----------------------------
private _companyTree = missionNamespace getVariable ["FTCS_Company_Data", createHashMap];
if (!(_companyTree isEqualType createHashMap)) then { _companyTree = createHashMap; };
private _platoonsMap = _companyTree getOrDefault ["platoons", createHashMap];
if (!(_platoonsMap isEqualType createHashMap)) then { _platoonsMap = createHashMap; };
private _pltData = _platoonsMap getOrDefault [format ["PLT_%1", _plt], createHashMap];
if (!(_pltData isEqualType createHashMap)) then { _pltData = createHashMap; };
private _parsedSquads = _pltData getOrDefault ["parsedSquads", createHashMap];
if (!(_parsedSquads isEqualType createHashMap)) then { _parsedSquads = createHashMap; };

// ---- 3-bis. TEMPORARY DIAGNOSTIC (debug menu mode only) ----------------------
// Dumps what the doctrine tree ACTUALLY contains for one squad key, so the
// "squad name is 'any'" symptom can be traced to its origin instead of guessed:
//   name=<MISSING>  -> the squads tree has no such key (doctrine not applied)
//   type=ANY        -> the key exists but its value is nil inside the HashMap
//   name='1st Rifle Squad' -> the tree is fine and the bug is in the builder
if (missionNamespace getVariable ["FTCS_Debug_Menu_Mode", false]) then {
    private _probeKey = format ["SQD_%1_1", _plt];
    private _probe = _parsedSquads getOrDefault [_probeKey, createHashMap];
    private _probeName = _probe getOrDefault ["name", "<MISSING>"];
    diag_log format ["[FTCS][DIAG] parsedSquads keys=%1", keys _parsedSquads];
    diag_log format ["[FTCS][DIAG] probe '%1' keys=%2 name=%3 type=%4",
        _probeKey, keys _probe, _probeName, typeName _probeName];
    private _rawSqd = (missionNamespace getVariable ["FTCS_Company_Data", createHashMap]) getOrDefault ["platoons", createHashMap];
    private _rawPlt = _rawSqd getOrDefault [format ["PLT_%1", _plt], createHashMap];
    diag_log format ["[FTCS][DIAG] company platoons=%1  plt keys=%2", keys _rawSqd, keys _rawPlt];
};

// ---- 4. Squad list, ordered by the NUMERIC index of the squadId ---------------
// Point 18: the squadId is the identity, the name is only a caption. Iterating
// the aggregation map would give HashMap order (Lesson 3), so the list is sorted
// on the trailing number of "SQD_<plt>_<n>".
//
// NO `private` inside this loop (Lesson 34/37): `private` is SCRIPT-scoped, and
// BIS_fnc_sortBy below executes a code block as well. Re-declaring a name used
// earlier in the script (`_pltData`, `_parsedSquads`, `_name`) invalidated the
// OUTER declaration, which is exactly how `SQD_1_1 'any'` was logged: the name
// lookup died and the default "" was returned.
private _squads = [];
private _bSqdId = "";
private _bRec = createHashMap;
private _bParts = [];
private _bOrd = 99;
private _bGrp = grpNull;
private _bLeader = objNull;
private _bState = "NO_GROUP";
private _bName = "";

{
    _bSqdId  = _x;
    _bRec    = _y;
    _bParts  = _bSqdId splitString "_";
    _bOrd    = if (count _bParts >= 3) then { parseNumber (_bParts select 2) } else { 99 };

    _bGrp    = _bRec getOrDefault ["group", grpNull];
    _bLeader = if (!isNull _bGrp) then { leader _bGrp } else { objNull };

    // Leader state as a flat cascade of POSITIVE assignments. The previous nested
    // if/else chain closed with `};` on consecutive lines, and the SQF parser read
    // the trailing `;` of an empty branch as a statement separator that shifted
    // the following block: the error surfaced as
    //   "Error in expression <ate = \"HEALTHY\"; }; }; }; }; _bName = ...>"
    // followed by "Undefined variable: _parsedSquads" on a line that was fine.
    // No nesting, no trailing semicolons after a closing brace.
    _bState = "NO_GROUP";
    if (!isNull _bGrp) then { _bState = "HEALTHY"; };
    if (!isNull _bGrp && { isNull _bLeader }) then { _bState = "NO_GROUP"; };
    if (!isNull _bLeader && { !alive _bLeader }) then { _bState = "DEAD"; };
    if (!isNull _bLeader && { alive _bLeader } && { (lifeState _bLeader) == "INCAPACITATED" }) then {
        _bState = "INCAPACITATED";
    };

    _bName = (_parsedSquads getOrDefault [_bSqdId, createHashMap]) getOrDefault ["name", ""];
    if (!(_bName isEqualType "")) then { _bName = ""; };
    if (_bName == "") then { _bName = format ["Squad %1", _bOrd]; };

    _squads pushBack createHashMapFromArray [
        ["slot", _bOrd],
        ["squadId", _bSqdId],
        ["group", _bGrp],
        ["name", _bName],
        ["leaderOk", (_bState == "HEALTHY")],
        ["leaderState", _bState],
        ["effective", _bRec getOrDefault ["effective", 0]],
        ["movingMode", _bRec getOrDefault ["movingMode", ""]],
        ["squadFormation", _bRec getOrDefault ["squadFormation", ""]],
        ["squadStance", _bRec getOrDefault ["squadStance", ""]],
        ["hasTarget", _bRec getOrDefault ["hasTarget", false]]
    ];
} forEach _agg;

// Sorting without a closure: a tiny insertion-free bubble pass keeps the state
// function free of code blocks, so no further scope interaction is possible.
private _swap = false;
private _tmp = createHashMap;
private _j = 0;
private _nSqd = count _squads;
while { true } do {
    _swap = false;
    _j = 0;
    while { _j < _nSqd - 1 } do {
        if ((_squads select _j) getOrDefault ["slot", 99] > (_squads select (_j + 1)) getOrDefault ["slot", 99]) then {
            _tmp = _squads select _j;
            _squads set [_j, _squads select (_j + 1)];
            _squads set [_j + 1, _tmp];
            _swap = true;
        };
        _j = _j + 1;
    };
    if (!_swap) exitWith {};
};

_state set ["squads", _squads];

if (missionNamespace getVariable ["FTCS_Debug_Menu_Mode", false]) then {
    diag_log format ["[FTCS][MENU][STATE] plt=%1 phase=%2 halted=%3 follow=%4 formation=%5 stance=%6 speed=%7 roe=%8 squads=%9 scouts=%10",
        _plt, _state get "phase", _state get "halted", _state get "followMode",
        _state get "formation", _state get "stance", _state get "speed", _state get "roe",
        count _squads, count _scoutSlots];
    {
        diag_log format ["[FTCS][MENU][STATE]   %1 '%2' leader=%3 eff=%4 mode=%5 tgt=%6",
            _x get "squadId", _x get "name", _x get "leaderState",
            _x get "effective", _x get "movingMode", _x get "hasTarget"];
    } forEach _squads;
};

_state
