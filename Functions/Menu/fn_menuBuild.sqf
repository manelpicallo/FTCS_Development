/*
    ================================================================================
    File: fn_menuBuild.sqf
    Module: Menu
    Author: FTCS Team
    Description: Turns a CATALOG menu (pure data) plus a STATE snapshot into the
                 final row array the engine will render: labels resolved, dynamic
                 rows injected (follow mode, squad list), and every row's `enabled`
                 flag (field 6) set to "1"/"0" according to its GATE.

                 Contract:
                   - PURE. No showCommandingMenu, no registry reads, no AI commands.
                   - NEVER declares a private variable inside a loop body whose
                     value is needed later (Lesson 28: `private` is script-scoped,
                     a re-declaration inside a `for` invalidates the outer one and
                     aborts the function - the historical menu failure).
                   - Returns a NEW array: the catalog is never mutated, so the
                     engine can safely read the menu it is showing.

    Returns: ARRAY of rows (Arma params: label, keys, submenu, prio, events,
             visible, enabled, meta).
    Language: Strictly English (Rule 7, Rule 11)
    ================================================================================
*/

params [
    ["_menuId", ""],
    ["_state", createHashMap],
    ["_squadIdx", 0]
];

if (_menuId == "" || { !(_state isEqualType createHashMap) }) exitWith { [] };

// -----------------------------------------------------------------------------
// 1. Resolve the catalog source and, for the per-squad menus, the index
// -----------------------------------------------------------------------------
// Per-squad menus are TEMPLATES: one declaration in the catalog serves every
// squad, and the index is a runtime argument. Resolving the template here keeps
// the catalog free of N copies of the same 11 rows.
private _templateId = "";
private _sid = _menuId;
if (_sid find "FTCS_MENU_SquadOrders_" == 0) then { _templateId = "FTCS_MENU_SquadOrders_Template"; };
if (_sid find "FTCS_MENU_SquadFormations_" == 0) then { _templateId = "FTCS_MENU_SquadFormations_Template"; };
if (_sid find "FTCS_MENU_SquadStance_" == 0) then { _templateId = "FTCS_MENU_SquadStance_Template"; };
if (_templateId != "") then {
    if (_squadIdx <= 0) then {
        private _p = _sid splitString "_";
        _squadIdx = parseNumber (_p select (count _p - 1));
    };
};

if (_templateId != "") then {
    if (_squadIdx <= 0) then {
        private _p = _sid splitString "_";
        _squadIdx = parseNumber (_p select (count _p - 1));
    };
};

private _source = if (_templateId != "") then { missionNamespace getVariable [_templateId, []] } else { missionNamespace getVariable [_menuId, []] };
if (!(_source isEqualType []) || { count _source < 2 }) exitWith {
    diag_log format ["[FTCS][MENU] *** BUILD ABORT: catalog '%1' missing or empty.", _menuId];
    []
};

private _squads = _state getOrDefault ["squads", []];
private _squadRec = createHashMap;
if (_squadIdx > 0) then {
    {
        if ((_x getOrDefault ["slot", -1]) == _squadIdx) exitWith { _squadRec = _x; };
    } forEach _squads;
};

// Title: dynamic menus append the doctrinal squad name (LABEL ONLY - Rule 18)
private _title = (_source select 0) select 0;
if (_squadIdx > 0) then {
    private _sqdName = _squadRec getOrDefault ["name", format ["Squad %1", _squadIdx]];
    _title = format ["%1 - %2", _title, _sqdName];
};

// -----------------------------------------------------------------------------
// 2. Build rows: one pass. Every scratch value is declared ONCE here and only
//    ASSIGNED inside the loops (Lesson 34/37: `private` is script-scoped, so a
//    second declaration of the same name inside a block invalidates the first).
// -----------------------------------------------------------------------------
private _rows = [[_title, false]];
private _label = "";
private _events = [];
private _submenu = "";
private _code = "";
private _slot = 0;
private _reason = "";
private _gateResult = [];

{
    private _row = +_x;
    if ((count _row >= 8) && { (_row select 7) isEqualType [] }) then {
        private _meta = _row select 7;
        private _payload = _meta param [0, ""];
        private _gate    = _meta param [1, ""];
        private _kind    = _meta param [3, ""];

        // --- label / payload substitution ----------------------------------
        _label = _row select 0;
        _events = _row select 4;
        _submenu = _row select 2;

        if (_squadIdx > 0) then {
            // Only texts that actually CARRY the %1 token are formatted: calling
            // format on a literal without tokens makes Arma warn (and the row
            // would keep a stray placeholder).
            if (_label find "%1" >= 0) then { _label = format [_label, _squadIdx]; };
            if ((_submenu isEqualType "") && { _submenu find "%1" >= 0 }) then { _submenu = format [_submenu, _squadIdx]; };
            if ((count _events > 0) && { (_events select 0) isEqualType [] }) then {
                _code = (_events select 0) param [1, ""];
                if ((_code isEqualType "") && { _code find "%1" >= 0 }) then {
                    _events = [["expression", format [_code, _squadIdx]]];
                };
            };
        };

        _row set [0, _label];
        _row set [2, _submenu];
        _row set [4, _events];

        // --- dynamic label injection ---------------------------------------
        if (_kind == "followmode") then {
            private _follow = _state getOrDefault ["followMode", "FOLLOWING_COMMANDER_REL"];
            if (_follow == "FOLLOWING_COMMANDER_REL") then {
                _row set [0, "4. Follow Mode: ABSOLUTE (Fixed Compass)"];
                _meta set [0, "PLT:MODE_ABSOLUTE"];
            } else {
                _row set [0, "4. Follow Mode: RELATIVE (Turn with Leader)"];
                _meta set [0, "PLT:MODE_RELATIVE"];
            };
            private _codeTmp = format ["['%1'] call FTCS_fnc_menuDispatch;", _meta select 0];
            _row set [4, [["expression", _codeTmp]]];
        };

        if (_kind in ["scout_11", "scout_12", "scout_6", "scout_7", "scout_8", "scout_5"]) then {
            _slot = parseNumber (_kind select [6]);
            private _owner = (_state getOrDefault ["scoutSlots", createHashMap]) getOrDefault [_slot, ""];
            if (_owner != "") then {
                private _srcName = "";
                {
                    if ((_x getOrDefault ["squadId", ""]) == _owner) exitWith { _srcName = _x getOrDefault ["name", ""]; };
                } forEach _squads;
                if (_srcName != "") then {
                    _row set [0, format ["%1 (%2)", _row select 0, _srcName]];
                };
            };
        };

        if (_kind == "squad_row") then {
            // Squad hub rows: label = "<n>. <doctrinal name>" resolved from state
            _slot = parseNumber ((_gate splitString "_") select 2);
            private _rec = createHashMap;
            {
                if ((_x getOrDefault ["slot", -1]) == _slot) exitWith { _rec = _x; };
            } forEach _squads;
            if (count _rec == 0) then {
                _row set [5, "0"];   // visible: a squad that does not exist is NOT painted
            } else {
                _row set [0, format ["%1. %2", _slot + 1, _rec getOrDefault ["name", format ["Squad %1", _slot]]]];
            };
        };

        // NOTE: hub rows are REBUILT below from the registry (one row per real
        // squad). The four template rows above only provide the key/priority slots
        // for the first four squads and are skipped when the hub is rebuilt.

        // --- GATE -> enabled flag ------------------------------------------
        // Navigation-only rows (pure submenu openers) carry NO gate: calling the
        // resolver with an empty id only produced "UNKNOWN GATE ''" log noise on
        // every menu open. They stay enabled unconditionally.
        if (_gate == "") then {
            _gateResult = [true, ""];
        } else {
            _gateResult = [_gate, _state, _squadRec] call FTCS_fnc_menuGate;
        };
        _row set [6, if (_gateResult select 0) then { "1" } else { "0" }];

        // Reason is appended to the label so the greyed row explains itself
        _reason = _gateResult select 1;
        if (!(_gateResult select 0) && { _reason != "" }) then {
            _row set [0, format ["%1   [%2]", _row select 0, _reason]];
        };
    };

    _rows pushBack _row;
} forEach (_source select [1]);

// -----------------------------------------------------------------------------
// 3. Squad hub: rebuild rows 2..N+1 from the REGISTRY (one row per real squad).
//    A squad that does not exist is never painted, so the hub shows 3 or 4 rows
//    depending on the doctrine and on what actually spawned.
// -----------------------------------------------------------------------------
if (_menuId == "FTCS_MENU_SquadHub") then {
    private _head = [_rows select 0];
    _head pushBack (_rows select 1);          // "1. Scouts Directive" stays first
    private _n = 0;
    private _enabled = "1";
    private _sub = "";
    {
        _n = _n + 1;
        _slot = _x getOrDefault ["slot", _n];
        _label = format ["%1. %2", _n + 1, _x getOrDefault ["name", format ["Squad %1", _slot]]];
        _gateResult = ["gate_squad_1", _state, _x] call FTCS_fnc_menuGate;
        _enabled = if (_gateResult select 0) then { "1" } else { "0" };
        _reason = _gateResult select 1;
        if (_enabled == "0" && { _reason != "" }) then { _label = format ["%1   [%2]", _label, _reason]; };
        _sub = format ["#USER:FTCS_MENU_SquadOrders_%1", _slot];
        _head pushBack [_label, [_n + 2], _sub, -5, [["expression", ""]], "1", _enabled, ["", "", false, ""]];
    } forEach _squads;
    _rows = _head;
};

_rows
