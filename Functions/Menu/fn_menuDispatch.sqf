/*
    ================================================================================
    File: fn_menuDispatch.sqf
    Module: Menu
    Author: FTCS Team
    Description: Single entry point for EVERY menu row. Translates a dispatch token
                 ("FAMILY:CODE[:ARG]") into the command code the order router
                 already understands, then calls FTCS_fnc_applyCommandToTarget.
                 The router keeps its existing cases untouched; this function only
                 adds the argument layer the native menu expressions cannot carry
                 (they cannot call a function with parameters).

                 Token families:
                   PLT   -> platoon commands      ("PLT:FORM:COLUMN")
                   ROAD  -> road / trail columns  ("ROAD:PLT_ROAD_COLUMN")
                   SCOUT -> platoon scout screens ("SCOUT:PLT_SCOUT_FLANK_L")
                   SQD   -> squad orders          ("SQD:MOVE_KEEP:2")
                   SQDF  -> squad formations      ("SQDF:WEDGE:2")
                   SQDS  -> squad stance          ("SQDS:UP:2")
                   MENU  -> navigation            ("MENU:FTCS_MENU_Root")

                 For squad families the ARG is the doctrinal squad index; the router
                 already parses "SQD_<ORDER>..._<n>", so the token is expanded into
                 the exact legacy code ("SQD_MOVE_ADVANCE_KEEP_2"). No new case is
                 needed in the router for any squad command.

                 Rule 19: every dispatched order is logged; real failures are logged
                 ALWAYS with the *** prefix.
    Language: Strictly English (Rule 7, Rule 11)
    ================================================================================
*/

params [["_token", ""]];

if (_token == "") exitWith {};

private _parts = _token splitString ":";
if (count _parts < 2) exitWith {
    diag_log format ["[FTCS][MENU] *** DISPATCH ABORT: malformed token '%1'.", _token];
};

private _family = toUpper (_parts select 0);
private _code = _parts select 1;
private _arg = if (count _parts > 2) then { _parts select 2 } else { "" };

// Set the menu context BEFORE the order runs: the router reads the target,
// the role and the cursor position from missionNamespace.
private _state = missionNamespace getVariable ["FTCS_Menu_LastState", createHashMap];
private _leaderUnit = if (_state isEqualType createHashMap) then { _state getOrDefault ["leaderUnit", player] } else { player };
if (isNull _leaderUnit) then { _leaderUnit = player; };
missionNamespace setVariable ["FTCS_ActiveMenu_Target", _leaderUnit];
missionNamespace setVariable ["FTCS_ActiveMenu_Role", "Menu"];
missionNamespace setVariable ["FTCS_ActiveMenu_Pos", screenToWorld [0.5, 0.5]];
missionNamespace setVariable ["FTCS_ActiveMenu_CursorObject", cursorObject];

// Resolve the squad anchor for the squad families (the router resolves the group
// from the index itself, but the label/trace need the squad id too).
private _squadIdx = if (_arg != "") then { parseNumber _arg } else { 0 };
private _routerCode = _code;
private _squadId = "";
private _sqdRec = createHashMap;

if (_squadIdx > 0) then {
    _squadId = format ["SQD_%1_%2", missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1], _squadIdx];
    {
        if ((_x getOrDefault ["slot", -1]) == _squadIdx) exitWith { _sqdRec = _x; };
    } forEach (_state getOrDefault ["squads", []]);
};

// ---- navigation: show another menu of the tree ---------------------------
// Handled BEFORE the family switch: the token is a MENU ID, not an order code,
// so execution must stop here (falling through would feed it to
// applyCommandToTarget, which logs "not implemented" and kills the commanding
// menu). SQF forbids `exitWith` inside a switch block (Lesson: "Error Missing ;"
// at the case), so the navigation guard lives at script level where exitWith
// is legal and actually exits the whole dispatcher.
if (_family == "MENU") exitWith {
    [_code] call FTCS_fnc_menuOpen;
};

switch (_family) do {

    // ---- platoon-level commands (codes exist verbatim in the router) --------
    case "PLT": {
        switch (_code) do {
            case "SET_PHASE": { _routerCode = format ["SET_PHASE_%1", _arg]; };
            case "FORM":      { _routerCode = format ["PLT_FORM_%1", _arg]; };
            case "MODE_TOGGLE": {
                private _cur = missionNamespace getVariable ["FTCS_Platoon_Follow_Mode", "FOLLOWING_COMMANDER_REL"];
                _routerCode = if (_cur == "FOLLOWING_COMMANDER_REL") then { "PLT_MODE_ABSOLUTE" } else { "PLT_MODE_RELATIVE" };
            };
            case "MODE_ABSOLUTE";
            case "MODE_RELATIVE": {
                _routerCode = format ["PLT_%1", _code];
            };
            case "HALT":            { _routerCode = "PLT_HALT"; };
            case "REJOIN_KEEP":     { _routerCode = "PLT_REJOIN_KEEP"; };
            case "REJOIN_NEW":      { _routerCode = "PLT_REJOIN_NEW"; };
            case "FOLLOW_COMMANDER":{ _routerCode = "PLT_FOLLOW_COMMANDER"; };
            case "PACE_NORMAL":     { _routerCode = "PACE_NORMAL"; };
            case "PACE_LIMITED":    { _routerCode = "PACE_LIMITED"; };
            case "PACE_FAST":       { _routerCode = "PACE_FAST"; };
            case "TECH_TRAVELING":  { _routerCode = "TECH_TRAVELING"; };
            case "TECH_TRAVELING_OVERWATCH": { _routerCode = "TECH_TRAVELING_OVERWATCH"; };
            case "STANCE_AUTO":     { _routerCode = "PLT_STANCE_AUTO"; };
            case "STANCE_UP":       { _routerCode = "PLT_STANCE_UP"; };
            case "STANCE_MIDDLE":   { _routerCode = "PLT_STANCE_MIDDLE"; };
            case "STANCE_DOWN":     { _routerCode = "PLT_STANCE_DOWN"; };
            case "STANCE_FOLLOW":   { _routerCode = "PLT_STANCE_FOLLOW_COMMANDER"; };
            case "WCS_HOLD":        { _routerCode = "WCS_HOLD"; };
            case "WCS_TIGHT":       { _routerCode = "WCS_TIGHT"; };
            case "WCS_FREE":        { _routerCode = "WCS_FREE"; };
            default {
                diag_log format ["[FTCS][MENU] *** UNHANDLED PLT TOKEN '%1' - nothing executed.", _code];
                _routerCode = "";
            };
        };
    };

    // ---- road / trail columns -----------------------------------------------
    case "ROAD": {
        _routerCode = _code;
    };

    // ---- platoon scout screens ----------------------------------------------
    case "SCOUT": {
        _routerCode = _code;
    };

    // ---- squad orders --------------------------------------------------------
    case "SQD": {
        switch (_code) do {
            case "TARGET_MARK":      { _routerCode = format ["SQD_TARGET_MARK_%1", _squadIdx]; };
            case "MOVE_DETACH":      { _routerCode = format ["SQD_MOVE_ADVANCE_DETACH_%1", _squadIdx]; };
            case "MOVE_DEFEND":      { _routerCode = format ["SQD_MOVE_ADVANCE_DEFEND_%1", _squadIdx]; };
            case "MOVE_KEEP":        { _routerCode = format ["SQD_MOVE_ADVANCE_KEEP_%1", _squadIdx]; };
            case "DEFEND":           { _routerCode = format ["SQD_DEFEND_%1", _squadIdx]; };
            case "FLANK_L":          { _routerCode = format ["SQD_FLANK_OPEN_L_%1", _squadIdx]; };
            case "FLANK_R":          { _routerCode = format ["SQD_FLANK_OPEN_R_%1", _squadIdx]; };
            case "FALL_BACK":        { _routerCode = format ["SQD_FALL_BACK_%1", _squadIdx]; };
            case "REJOIN_FORMATION": { _routerCode = format ["SQD_REJOIN_FORMATION_%1", _squadIdx]; };
            default {
                diag_log format ["[FTCS][MENU] *** UNHANDLED SQD TOKEN '%1' - nothing executed.", _code];
                _routerCode = "";
            };
        };
    };

    // ---- squad formation / stance -------------------------------------------
    case "SQDF": {
        _routerCode = format ["SQD_FORM_%1", _code];
    };
    case "SQDS": {
        switch (_code) do {
            case "AUTO":   { _routerCode = "STANCE_AUTO"; };
            case "UP":     { _routerCode = "STANCE_UP"; };
            case "MIDDLE": { _routerCode = "STANCE_MIDDLE"; };
            case "DOWN":   { _routerCode = "STANCE_DOWN"; };
            case "FOLLOW": { _routerCode = "STANCE_FOLLOW_COMMANDER"; };
            default { _routerCode = ""; };
        };
    };

    default {
        diag_log format ["[FTCS][MENU] *** UNKNOWN DISPATCH FAMILY '%1' (token '%2').", _family, _token];
        _routerCode = "";
    };
};

// -----------------------------------------------------------------------------
// Execute. Squad formation/stance families carry an index in a DIFFERENT shape
// (the router reads the squad from the ACTIVE MENU target for those two), so the
// context is set to the squad anchor leader before calling.
// -----------------------------------------------------------------------------
private _squadTarget = objNull;
if (_squadIdx > 0) then {
    private _grp = _sqdRec getOrDefault ["group", grpNull];
    if (!isNull _grp) then { _squadTarget = leader _grp; };
    if (!isNull _squadTarget) then {
        missionNamespace setVariable ["FTCS_ActiveMenu_Target", _squadTarget];
        missionNamespace setVariable ["FTCS_ActiveMenu_Role", _sqdRec getOrDefault ["name", _squadId]];
    };
};

if (_routerCode == "") exitWith {
    diag_log format ["[FTCS][MENU] *** NOTHING EXECUTED for token '%1'.", _token];
};

if (missionNamespace getVariable ["FTCS_Debug_Menu_Mode", false]) then {
    diag_log format ["[FTCS][MENU][DISPATCH] token='%1' -> code='%2' squad=%3",
        _token, _routerCode, (if (_squadId == "") then { "-" } else { _squadId })];
};

[_routerCode] call FTCS_fnc_applyCommandToTarget;

// -----------------------------------------------------------------------------
// Re-open policy: NAVIGATION and STATE rows re-open the SAME menu through the
// one-shot MouseButtonUp handler (press executes, release re-opens). Terminal
// orders close the menu and return the player to the game. The list lives HERE,
// in ONE place, so moving a family between the two behaviours is a one-line edit.
// -----------------------------------------------------------------------------
private _reopenFamilies = ["PLT", "ROAD", "SCOUT", "SQD", "SQDF", "SQDS"];
private _shouldReopen = (_family in _reopenFamilies);

// Squad TARGET MARK re-opens the squad menu AFTER the 3D capture completes
// (fn_targetMark does it): arming the button-up handler as well would double it.
if (_family == "SQD" && { _code == "TARGET_MARK" }) then { _shouldReopen = false; };

if (_shouldReopen) then {
    private _self = missionNamespace getVariable ["FTCS_Menu_ReopenSelf", ["", -1]];
    if ((_self isEqualType []) && { count _self >= 1 } && { (_self select 0) != "" }) then {
        [_self select 0, (if (count _self > 1) then { _self select 1 } else { -1 })] call FTCS_fnc_menuReopen;
    };
};
