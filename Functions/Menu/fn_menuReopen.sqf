/*
    ================================================================================
    File: fn_menuReopen.sqf
    Module: Menu
    Author: FTCS Team
    Description: Re-opens a menu after a row has been clicked, using a ONE-SHOT
                 "MouseButtonUp" handler on Display 46 (the technique from the
                 original menu module: the button press executes the row and the
                 button RELEASE re-opens the menu with recalculated states - one
                 click, two effects, no extra click for the player).

                 Why not "sleep 0.05 + showCommandingMenu":
                   Arma closes the commanding menu asynchronously after the row
                   expression runs, and a script-based delay races that close
                   depending on frame time. The release of the button IS a real
                   UI event that fires after the close, so it is deterministic.

                 The handler removes ITSELF on the first run: without that, one
                 handler would accumulate per opening and a single click would
                 re-open the menu N times.

                 Only rows explicitly flagged REOPEN use this. Navigation and
                 state rows do so; terminal orders do not (the player returns to
                 the game), unless the user asks otherwise.
    Language: Strictly English (Rule 7, Rule 11)
    ================================================================================
*/

// NOTE: `params` must run BEFORE any use of the arguments (the old version tested
// `_menuId` three statements above its own `params` line, which reads whatever
// value happened to be in scope instead of the argument).
params [["_menuId", ""], ["_squadIdx", -1]];

if (!(_menuId isEqualType "")) then { _menuId = ""; };
if (!(_squadIdx isEqualType 0)) then { _squadIdx = -1; };

if (_menuId == "") exitWith {};

private _display = findDisplay 46;
if (isNull _display) exitWith {
    // No UI display (headless / early boot): open directly instead of losing the menu.
    [_menuId, _squadIdx] call FTCS_fnc_menuOpen;
};

// One handler at a time: a previous handler still waiting would re-open twice.
private _previous = missionNamespace getVariable ["FTCS_Menu_ReopenEH", -1];
if (_previous >= 0) then {
    _display displayRemoveEventHandler ["MouseButtonUp", _previous];
};

private _eh = _display displayAddEventHandler ["MouseButtonUp", {
    params ["_displayOrControl", "_button", "_x", "_y", "_shift", "_ctrl", "_alt"];

    // Self-removal FIRST: the handler must never fire twice.
    private _id = missionNamespace getVariable ["FTCS_Menu_ReopenEH", -1];
    if (_id >= 0) then {
        (_displayOrControl) displayRemoveEventHandler ["MouseButtonUp", _id];
    };
    missionNamespace setVariable ["FTCS_Menu_ReopenEH", -1];

    // Only the primary (left) button re-opens; a right click dismisses the menu.
    if (_button == 0) then {
        private _pending = missionNamespace getVariable ["FTCS_Menu_ReopenTarget", []];
        if ((_pending isEqualType []) && { count _pending >= 1 }) then {
            private _targetId = _pending select 0;
            private _targetIdx = if (count _pending > 1) then { _pending select 1 } else { -1 };
            if (missionNamespace getVariable ["FTCS_Debug_Menu_Mode", false]) then {
                diag_log format ["[FTCS][MENU][REOPEN] buttonUp -> reopening '%1' (idx=%2).", _targetId, _targetIdx];
            };
            [_targetId, _targetIdx] call FTCS_fnc_menuOpen;
        };
    };
}];

missionNamespace setVariable ["FTCS_Menu_ReopenEH", _eh];
missionNamespace setVariable ["FTCS_Menu_ReopenTarget", [_menuId, _squadIdx]];

if (missionNamespace getVariable ["FTCS_Debug_Menu_Mode", false]) then {
    diag_log format ["[FTCS][MENU][REOPEN] armed for '%1' (idx=%2).", _menuId, _squadIdx];
};
