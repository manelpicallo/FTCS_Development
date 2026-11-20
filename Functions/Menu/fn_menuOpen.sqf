/*
    ================================================================================
    File: fn_menuOpen.sqf
    Module: Menu
    Author: FTCS Team
    Description: THE single entry point of the FTCS commanding UI. Resolves which
                 root the session runs (the sentinel is READ, never toggled: the
                 mode is fixed at mission start and cannot change mid-game),
                 snapshots the state, builds the rows and shows the menu.

                 Pipeline:
                   [sentinel] -> root id
                        |
                        v
                   [fn_menuGetState]   ONE pass, state snapshot
                        |
                        v
                   [fn_menuBuild]      rows with gates + labels
                        |
                        v
                   [showCommandingMenu "#USER:<published var>"]

                 The published variable is the ONLY array the engine ever reads:
                 the catalog is never mutated, so a menu cannot be corrupted while
                 the engine displays it (Lesson 26/28 family of failures).

                 Any abort BEFORE showCommandingMenu is logged with *** so a menu
                 that fails to appear is never silent again.
    Language: Strictly English (Rule 7, Rule 11)

    +-----------------------------------------------------------------------------+
    |                        MENU OPEN - CONTROL FLOW                             |
    +-----------------------------------------------------------------------------+
    |  [_menuId] call FTCS_fnc_menuOpen                                           |
    |       menuId = "" -> resolve root from the sentinel                         |
    |       menuId = "FTCS_MENU_SquadOrders_2" -> per-squad menu (index parsed)   |
    +-----------------------------------------------------------------------------+
    ================================================================================
*/

params [["_menuId", ""], ["_squadIdx", -1]];

// ---- 1. Sentinel: read ONCE, never toggled in game (design decision) ---------
private _debugMenus = missionNamespace getVariable ["FTCS_Debug_Menu_Mode", true];

// ---- 2. Resolve the menu to show --------------------------------------------
private _targetId = _menuId;
if (_targetId == "") then {
    _targetId = if (_debugMenus) then { "FTCS_MENU_Root" } else { "FTCS_MENU_RealRoot" };
};

// Per-squad menus carry the index in their id ("..._<n>")
private _idx = _squadIdx;
if (_idx < 0) then {
    private _isSquadMenu = (_targetId find "FTCS_MENU_SquadOrders_" == 0)
                        || (_targetId find "FTCS_MENU_SquadFormations_" == 0)
                        || (_targetId find "FTCS_MENU_SquadStance_" == 0);
    if (_isSquadMenu) then {
        private _parts = _targetId splitString "_";
        _idx = parseNumber (_parts select (count _parts - 1));
    } else {
        _idx = 0;
    };
};

// ---- 3. Snapshot the state (one pass) ---------------------------------------
private _pltId = missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1];
private _state = [_pltId] call FTCS_fnc_menuGetState;
missionNamespace setVariable ["FTCS_Menu_LastState", _state];

// ---- 4. Build the rows ------------------------------------------------------
private _rows = [_targetId, _state, _idx] call FTCS_fnc_menuBuild;

if (!(_rows isEqualType []) || { count _rows < 2 }) exitWith {
    diag_log format ["[FTCS][MENU] *** OPEN ABORT: menu '%1' produced no rows (rows=%2).",
        _targetId, (if (_rows isEqualType []) then { count _rows } else { -1 })];
};

// ---- 5. Publish a FRESH copy and show it ------------------------------------
private _varName = format ["FTCS_MENU_%1_Var", _targetId];
missionNamespace setVariable [_varName, _rows];
missionNamespace setVariable ["FTCS_Menu_Current", _targetId];

// Re-open target: after a row that is flagged REOPEN runs, fn_menuReopen armed by
// fn_menuDispatch shows THIS menu again with recalculated states (one click).
missionNamespace setVariable ["FTCS_Menu_ReopenSelf", [_targetId, _idx]];

if (missionNamespace getVariable ["FTCS_Debug_Menu_Mode", false]) then {
    diag_log format ["[FTCS][MENU][OPEN] menu='%1' rows=%2 root=%3 var='%4'",
        _targetId, count _rows, (if (_debugMenus) then { "DEBUG" } else { "REAL" }), _varName];
};

showCommandingMenu format ["#USER:%1", _varName];

// Any pending one-shot re-open handler belongs to the PREVIOUS menu: disarm it so
// it cannot fire against a menu the player has already left.
private _staleEh = missionNamespace getVariable ["FTCS_Menu_ReopenEH", -1];
if (_staleEh >= 0) then {
    private _disp = findDisplay 46;
    if (!isNull _disp) then { _disp displayRemoveEventHandler ["MouseButtonUp", _staleEh]; };
    missionNamespace setVariable ["FTCS_Menu_ReopenEH", -1];
};
