/*
    ================================================================================
    File: fn_initMenus.sqf
    Module: Menu
    Author: FTCS Team
    Description: Boots the FTCS commanding UI: compiles the declarative catalog and
                 registers the SINGLE self-action the player uses to deploy the menu
                 with the mouse wheel.

                 Design decisions honoured here:
                   - ONE action on the player. No action is ever attached to an NPC
                     (the NPC interaction layer stays disabled for now).
                   - The UI mode is decided by FTCS_Debug_Menu_Mode, READ ONLY: the
                     sentinel is set once at boot and never toggled in game.
                   - Nothing is built per opening: the catalog is data, so "opening"
                     a menu is a read + a build, never a full reconstruction of the
                     whole tree (the failure mode of the previous implementation).

                 The real (non-debug) root is declared as an empty placeholder: the
                 gameplay UI is designed in FTCS_Menu_Structure_Reference and will be
                 implemented in a later pass. It is NOT a legacy remnant.
    Language: Strictly English (Rule 7, Rule 11)
    ================================================================================
*/

if (missionNamespace getVariable ["FTCS_Menus_Initialized", false]) exitWith {};

// ---- 0. Compile the MENU MODULE FUNCTIONS -----------------------------------
// The menu layer is loaded HERE, from the catalog itself, instead of relying on
// CfgFunctions. Reason: CfgFunctions is compiled when the mission loads, and a
// function added to description.ext is NOT visible in a running session - a menu
// that calls a missing FTCS_fnc_menuGate/menuBuild aborts SILENTLY (the row
// keeps whatever it had, the click does nothing). Reading the module files as
// plain script files at boot makes the whole UI layer version-proof.
//
// fn_menuCatalog.sqf is DATA ONLY and it is NOT executed here: it declares the
// menu trees as bare missionNamespace assignments, so it must only ever be run as
// the compile-time file of this very function (CfgFunctions). Running it a second
// time at boot re-declares the arrays BEFORE the accessor closures exist, which
// broke the boot with `getOrDefault: Type Array, expected HashMap`.
private _moduleDir = "Functions\Menu\";
private _moduleFiles = [
    "fn_menuGate.sqf",
    "fn_menuGetState.sqf",
    "fn_menuBuild.sqf",
    "fn_menuOpen.sqf",
    "fn_menuDispatch.sqf",
    "fn_menuReopen.sqf"
];
{
    private _f = _x;
    // `compile` builds the code; `call` runs it. `preprocessFileLineNumbers` alone
    // returns the FILE TEXT (a String) - never executed, so the module functions
    // stayed undefined and every `call FTCS_fnc_menuGate` aborted.
    call compile preprocessFileLineNumbers (_moduleDir + _f);
    diag_log format ["[FTCS][MENU] module loaded: %1 (gate=%2)", _f, str (!isNil "FTCS_fnc_menuGate")];
} forEach _moduleFiles;

// ---- 1. Compile the data catalog (compiled ONCE, then pure data) ------------
// `call compile preprocessFileLineNumbers` does NOT return the file value (it
// returns the last statement's value only through `call`), so the check below is
// made on the DATA itself (`FTCS_MENU_Root`), never on the call result: an Array
// in a boolean test is exactly the failure mode this boot used to hit.
if (isNil "FTCS_MENU_Root") then {
    call compile preprocessFileLineNumbers "Functions\Menu\fn_menuCatalog.sqf";
};

if (isNil "FTCS_fnc_menuGate") then {
    diag_log "[FTCS][MENU] *** INIT: FTCS_fnc_menuGate is STILL undefined after the module load - the UI will not paint rows.";
};

if (isNil "FTCS_MENU_Root") then {
    diag_log "[FTCS][MENU] *** INIT ABORT: catalog could not be compiled.";
} else {
    // Operational defaults required by the phase gates.
    for "_i" from 1 to 4 do {
        if (isNil (format ["FTCS_Platoon_Phase_%1", _i])) then {
            missionNamespace setVariable [format ["FTCS_Platoon_Phase_%1", _i], 0];
        };
    };
    // Follow mode: a formation is seeded in ABSOLUTE (fixed compass). The REL mode
    // is an explicit order the lieutenant gives through root row 4, never a silent
    // default (a formation that quietly turns with the leader is not a formation).
    if (isNil "FTCS_Platoon_Follow_Mode") then {
        FTCS_Platoon_Follow_Mode = "FOLLOWING_COMMANDER_ABS";
    };

    // Real-gameplay root placeholder (designed in the Menu Structure Reference).
    if (isNil "FTCS_MENU_RealRoot") then {
        FTCS_MENU_RealRoot = [
            ["FTCS - PLATOON COMMAND", false],
            ["1. Platoon Orders (not implemented yet)", [2], "", -5, [["expression", ""]], "1", "0", ["", "", false, ""]]
        ];
    };

    missionNamespace setVariable ["FTCS_Menus_Initialized", true];

    // ---- 2. Single player self-action -------------------------------------
    // Removed first so a re-init (respawn / mission reload) never duplicates it.
    // Legacy player actions from the retired menu system are swept too: their IDs
    // were published under a legacy key by the previous implementation. The
    // deployment UI action belongs to init.sqf and is NOT touched here.
    private _oldIds = missionNamespace getVariable ["FTCS_Menu_OpenActionIds", []];
    { player removeAction _x; } forEach _oldIds;
    {
        player removeAction _x;
        diag_log format ["[FTCS][MENU] removed legacy player action %1.", _x];
    } forEach (missionNamespace getVariable ["FTCS_Legacy_PlayerActions", []]);
    missionNamespace setVariable ["FTCS_Legacy_PlayerActions", []];

    private _actionLabel = if (missionNamespace getVariable ["FTCS_Debug_Menu_Mode", true]) then {
        "<t color='#00FFCC'>[FTCS DEBUG] Command Menu (Wheel)</t>"
    } else {
        "<t color='#00FFCC'>[FTCS] Command Menu (Wheel)</t>"
    };

    // addAction params: target, title, function, args, priority, showWindow,
    //                   hideOnUse, shortcut, condition. It returns the action ID.
    private _actionId = player addAction [
        _actionLabel,
        { [] call FTCS_fnc_menuOpen; },
        nil,
        1.5,
        true,
        false,
        "",
        "true",
        0.0
    ];
    missionNamespace setVariable ["FTCS_Menu_OpenActionIds", [_actionId]];

    diag_log format ["[FTCS][MENU] initialized (mode=%1).",
        (if (missionNamespace getVariable ["FTCS_Debug_Menu_Mode", true]) then { "DEBUG" } else { "REAL" })];
};
