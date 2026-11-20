/*
    ================================================================================
    File: fn_initCommandingMenus.sqf
    Module: Interactions
    Author: FTCS Team
    Description: LEGACY COMPATIBILITY SHIM. The commanding UI is now declared as
                 pure data in Functions/Menu/fn_menuCatalog.sqf (module "Menu") and
                 rendered by fn_menuOpen / fn_menuBuild / fn_menuGate.

                 This file no longer defines 25 hand-built menu arrays. Everything
                 that had NO backend (Bounding Overwatch, LDA Crossing, Assault
                 Wave, Fire Direction, Sustainment, Fire Support, TLP, Radio,
                 Runner, Medical, Visual Signals, Phase-3 squad sets) has been
                 REMOVED: a menu must never offer a button that does nothing.

                 What survives here are the three SQUAD-LEVEL arrays the order
                 router reads by name when it resolves squad formations, march pace
                 and scout screens. They are kept as data because their codes exist
                 and are verified; the new catalog reuses the same command codes.
    Language: Strictly English (Rule 7, Rule 11)

    +-----------------------------------------------------------------------------+
    |              FTCS COMMANDING MENU - OWNERSHIP AFTER THE REFACTOR            |
    +-----------------------------------------------------------------------------+
    |                                                                             |
    |  DATA (declared once)      Functions/Menu/fn_menuCatalog.sqf               |
    |       |                                                                     |
    |       v                                                                     |
    |  STATE (one pass)          Functions/Menu/fn_menuGetState.sqf              |
    |       |                                                                     |
    |       v                                                                     |
    |  GATES (white / grey)      Functions/Menu/fn_menuGate.sqf                  |
    |       |                                                                     |
    |       v                                                                     |
    |  BUILD (labels + rows)     Functions/Menu/fn_menuBuild.sqf                 |
    |       |                                                                     |
    |       v                                                                     |
    |  SHOW                      Functions/Menu/fn_menuOpen.sqf                  |
    |       |                                                                     |
    |       v                                                                     |
    |  ACT                       Functions/Menu/fn_menuDispatch.sqf              |
    |                               -> FTCS_fnc_applyCommandToTarget (unchanged)  |
    |                                                                             |
    |  This file only keeps the three squad-level arrays the router reads.        |
    +-----------------------------------------------------------------------------+
    ================================================================================
*/

if (missionNamespace getVariable ["FTCS_CommandingMenus_Initialized", false]) exitWith {};

// Operational defaults required by the phase gates (kept here for callers that
// initialise the menus before the registry does).
for "_i" from 1 to 4 do {
    if (isNil (format ["FTCS_Platoon_Phase_%1", _i])) then {
        missionNamespace setVariable [format ["FTCS_Platoon_Phase_%1", _i], 0];
    };
};
FTCS_CurrentPhase = missionNamespace getVariable ["FTCS_Platoon_Phase_1", 0];

if (isNil "FTCS_Platoon_Follow_Mode") then {
    FTCS_Platoon_Follow_Mode = "FOLLOWING_COMMANDER_REL";
};

// =============================================================================
// SQUAD-LEVEL ARRAYS KEPT FOR THE ORDER ROUTER (codes verified in the router)
// =============================================================================

// Squad formations (Phase 1) - every code has a case in the router
FTCS_MENU_SquadFormations_P1 = [
    ["Squad Formations", false],
    ["1. Squad Column", [2], "", -5, [["expression", "['SQD_FORM_COLUMN'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"],
    ["2. Squad Line", [3], "", -5, [["expression", "['SQD_FORM_LINE'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"],
    ["3. Squad File", [4], "", -5, [["expression", "['SQD_FORM_FILE'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"],
    ["4. Squad Wedge", [5], "", -5, [["expression", "['SQD_FORM_WEDGE'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"]
];

// Squad march pace & spacing (Phase 1) - every code has a case in the router
FTCS_MENU_SquadPace_P1 = [
    ["March Pace & Spacing", false],
    ["1. Standard Pace (Walk)", [2], "", -5, [["expression", "['SQD_PACE_NORMAL'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"],
    ["2. Quick Pace (Jog)", [3], "", -5, [["expression", "['SQD_PACE_FAST'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"],
    ["3. Close Interval (5m Spacing)", [4], "", -5, [["expression", "['SQD_SPACING_CLOSE'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"],
    ["4. Open Interval (10m Spacing)", [5], "", -5, [["expression", "['SQD_SPACING_OPEN'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"]
];

// Squad scout screen (squad-level slots) - every code has a case in the router
FTCS_MENU_ScoutScreen_Deploy = [
    ["Squad Scout Screen", false],
    ["1. Deploy to Left Flank Screen", [2], "", -5, [["expression", "['SQD_SCOUT_SLOT_11'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"],
    ["2. Deploy to Right Flank Screen", [3], "", -5, [["expression", "['SQD_SCOUT_SLOT_12'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"],
    ["3. Deploy to Front Center Screen", [4], "", -5, [["expression", "['SQD_SCOUT_SLOT_6'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"],
    ["4. Deploy to Front Left Screen", [5], "", -5, [["expression", "['SQD_SCOUT_SLOT_7'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"],
    ["5. Deploy to Front Right Screen", [6], "", -5, [["expression", "['SQD_SCOUT_SLOT_8'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"],
    ["6. Deploy to Rear Reserve Screen", [7], "", -5, [["expression", "['SQD_SCOUT_SLOT_5'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"],
    ["7. Rejoin Scouts to Squad", [8], "", -5, [["expression", "['TASK_FOLLOW_COMMANDER'] call FTCS_fnc_applyCommandToTarget;"]], "1", "1"]
];

missionNamespace setVariable ["FTCS_CommandingMenus_Initialized", true];
diag_log "[FTCS][MENU] legacy menu arrays reduced to the three squad-level sets (all with backend).";
