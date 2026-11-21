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

// Hard contract: fn_menuOpen is also used as a code value (addAction function,
// spawned calls). In those contexts "_menuId" may arrive as a NON-string (the
// previous expression's value). Normalise BEFORE any string operation: an Array
// reaching splitString/find aborts the whole open silently.
if (!(_menuId isEqualType "")) then { _menuId = ""; };
if (!(_squadIdx isEqualType 0)) then { _squadIdx = -1; };

// A legacy opener may hand "#USER:<var>"; this pipeline needs the ID itself.
if (_menuId find "#USER:" == 0) then { _menuId = _menuId select [6]; };
// An id arriving with the published suffix ("FTCS_MENU_X_Var") is trimmed back to
// the authored id, so a direct call cannot build a name-of-a-name.
if ((count _menuId > 4) && { (_menuId select [(count _menuId) - 4]) == "_Var" }) then {
    _menuId = _menuId select [0, (count _menuId) - 4];
};

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
// The BUILT rows are published under "FTCS_MENU_<id>_Var", and that is the name
// every navigation row points to (`#USER:FTCS_MENU_<child>_Var`). The catalog
// variable itself is NEVER overwritten: it stays pure immutable data (Lesson:
// overwriting FTCS_MENU_<id> with built rows destroys the menu tree in memory).
private _varName = format ["FTCS_MENU_%1_Var", _targetId];
missionNamespace setVariable [_varName, _rows];
missionNamespace setVariable ["FTCS_Menu_Current", _targetId];

// ---- 5-bis. PRE-BUILD THE CHILDREN OF THIS MENU ------------------------------
// Arma opens a navigation row's `submenu` IMMEDIATELY and reads that variable in
// THAT instant: it never calls a function on the way. Therefore a child menu has
// to EXIST (already built and published) before its parent is shown, otherwise
// Arma paints an empty menu ("name shown, no rows" - the regression after
// pointing submenu to "..._Var").
// Here every child DECLARED IN FTCS_MENU_Parents is built with the SAME snapshot
// used for the parent and published under its "..._Var" name. One level is enough
// for this tree (root -> family -> squad), because when the player enters a
// family menu, that same pass publishes ITS children too.
private _parentsMap = missionNamespace getVariable ["FTCS_MENU_Parents", createHashMap];
if (!(_parentsMap isEqualType createHashMap)) then { _parentsMap = createHashMap; };
private _childIds = _parentsMap getOrDefault [_targetId, []];
if (!(_childIds isEqualType [])) then { _childIds = []; };
{
    private _childId = _x;
    private _childIdx = 0;
    private _isSquadMenu = (_childId find "FTCS_MENU_SquadOrders_" == 0)
                        || (_childId find "FTCS_MENU_SquadFormations_" == 0)
                        || (_childId find "FTCS_MENU_SquadStance_" == 0);
    if (_isSquadMenu) then {
        private _cp = _childId splitString "_";
        _childIdx = parseNumber (_cp select (count _cp - 1));
    };
    private _childRows = [_childId, _state, _childIdx] call FTCS_fnc_menuBuild;
    if ((_childRows isEqualType []) && { count _childRows >= 2 }) then {
        missionNamespace setVariable [format ["FTCS_MENU_%1_Var", _childId], _childRows];
    } else {
        diag_log format ["[FTCS][MENU] *** CHILD BUILD: '%1' produced no rows (child of '%2').", _childId, _targetId];
    };
} forEach _childIds;

// Re-open target: after a row that is flagged REOPEN runs, fn_menuReopen armed by
// fn_menuDispatch shows THIS menu again with recalculated states (one click).
missionNamespace setVariable ["FTCS_Menu_ReopenSelf", [_targetId, _idx]];

if (missionNamespace getVariable ["FTCS_Debug_Menu_Mode", false]) then {
    diag_log format ["[FTCS][MENU][OPEN] menu='%1' rows=%2 root=%3 var='%4'",
        _targetId, count _rows, (if (_debugMenus) then { "DEBUG" } else { "REAL" }), _varName];
};

// ---- 5. TEMPORARY MENU DIAGNOSTIC (FTCS_Debug_Menu_Mode) ----------------------
// Writes what the ROOT follow-mode row (row 4) was built from, so a wrong label is
// diagnosed from values instead of inferred: which root is shown, which sentinel
// the snapshot carried, and how fn_menuBuild resolved it into a label/token.
if (missionNamespace getVariable ["FTCS_Debug_Menu_Mode", false]) then {
    if (_targetId in ["FTCS_MENU_Root", "FTCS_MENU_RealRoot"]) then {
        private _diagFollow = "<none>";
        private _diagRow4 = "<none>";
        if (_state isEqualType createHashMap) then { _diagFollow = _state getOrDefault ["followMode", "<MISSING>"]; };
        if ((_rows isEqualType []) && { count _rows > 4 }) then {
            private _r4 = _rows select 4;
            if ((_r4 isEqualType []) && { count _r4 > 4 }) then {
                _diagRow4 = format ["label='%1' token='%2'", _r4 select 0, ((_r4 select 4) param [0, []] param [1, ""])];
            };
        };
        diag_log format ["[FTCS][MENU][FOLLOW] root='%1' debugMenus=%2 registryFollowMode='%3' row4 %4",
            _targetId, _debugMenus, _diagFollow, _diagRow4];
    };
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
