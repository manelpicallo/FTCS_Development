/*
    ================================================================================
    File: fn_openSubordinateMenu.sqf
    Module: Interactions
    Author: FTCS Team
    Description: Called from an addAction on a subordinate leader or self command net.
                 Stores active target context in global variables and invokes the
                 appropriate native commandingMenu (#USER:) dynamically adapted
                 to the current Operational Phase (Doctrine FM 3-21.8).
    Language: Strictly English (Rule 7, Rule 11)

    +-----------------------------------------------------------------------------+
    |                    DYNAMIC PHASE MENU ROUTING                               |
    +-----------------------------------------------------------------------------+
    |                                                                             |
    |   [Target Interaction] â”€â”€â–º [Distance Check]                                 |
    |                                â”‚                                            |
    |                    <= 20m â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€ > 20m â”€â”€â–º #USER:FTCS_MENU_VisualSignals|
    |                      â”‚                                                      |
    |        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”                                       |
    |        â–¼                            â–¼                                       |
    |  [PLATOON / SERGEANT]            [SQUAD LEADER]                             |
    |        â”‚                            â”‚                                       |
    |   Check FTCS_CurrentPhase      Check FTCS_CurrentPhase                      |
    |        â”œâ”€ Phase 1: Approach         â”œâ”€ Phase 1: Approach                    |
    |        â”‚   (#USER:Sgt_Phase1)       â”‚   (#USER:Squad_Phase1)                |
    |        â”œâ”€ Phase 2: Overwatch        â”œâ”€ Phase 2: Overwatch                   |
    |        â”‚   (#USER:Sgt_Phase2)       â”‚   (#USER:Squad_Phase2)                |
    |        â””â”€ Phase 3: Combat           â””â”€ Phase 3: Combat                      |
    |            (#USER:Sgt_Phase3)           (#USER:Squad_Phase3)                |
    +-----------------------------------------------------------------------------+
    ================================================================================
*/

params [
    ["_targetUnit", objNull],
    ["_caller", objNull],
    ["_actionId", -1],
    ["_arguments", []]
];

if (isNull _targetUnit) exitWith {};

_arguments params [
    ["_menuType", "SQUAD"],
    ["_roleLabel", "Subordinate"],
    ["_bypassDistance", false]
];

// Ensure commanding menus are compiled and initialized in memory
if (isNil "FTCS_CommandingMenus_Initialized") then {
    call FTCS_fnc_initCommandingMenus;
};

// Resolve the platoon ID for the active context (platoon of target or player)
private _pltId = missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1];
if (!isNull _targetUnit) then {
    private _uVar = vehicleVarName _targetUnit;
    if (_uVar != "" && {_uVar find "PLT_" >= 0}) then {
        private _parts = _uVar splitString "_";
        private _idx = _parts find "PLT";
        if (_idx >= 0 && {count _parts > _idx + 1}) then {
            private _parsed = parseNumber (_parts select (_idx + 1));
            if (_parsed > 0) then { _pltId = _parsed; };
        };
    };
};

// Retrieve active operational phase for this specific platoon (Default: Phase 1 - APPROACH)
private _curPhase = missionNamespace getVariable [format ["FTCS_Platoon_Phase_%1", _pltId], 1];

// Store active target context for expression evaluation inside commandingMenu items
missionNamespace setVariable ["FTCS_ActiveMenu_Target", _targetUnit];
missionNamespace setVariable ["FTCS_ActiveMenu_Role", _roleLabel];
missionNamespace setVariable ["FTCS_ActiveMenu_Pos", screenToWorld [0.5, 0.5]];
missionNamespace setVariable ["FTCS_ActiveMenu_CursorObject", cursorObject];

private _distance = player distance _targetUnit;
private _isSelf = (_targetUnit == player);

// Select appropriate commandingMenu according to role, operational phase, and distance
private _menuName = switch (_menuType) do {
    case "SQUAD": {
        if (_distance <= 20 || _isSelf || _bypassDistance) then {
            switch (_curPhase) do {
                case 1: { "#USER:FTCS_MENU_Squad_Phase1" };
                case 2: { "#USER:FTCS_MENU_Squad_Phase2" };
                case 3: { "#USER:FTCS_MENU_Squad_Phase3" };
                default { "#USER:FTCS_MENU_Squad_Phase1" };
            };
        } else {
            "#USER:FTCS_MENU_VisualSignals"
        };
    };
    case "PLATOON_SERGEANT";
    case "PLATOON": {
        if (_distance <= 20 || _isSelf || _bypassDistance) then {
            switch (_curPhase) do {
                case 0: { "#USER:FTCS_MENU_PhaseTransition" }; // Force phase selection if troops still in deployment inspection
                case 1: { "#USER:FTCS_MENU_Sgt_Phase1" };
                case 2: { "#USER:FTCS_MENU_Sgt_Phase2" };
                case 3: { "#USER:FTCS_MENU_Sgt_Phase3" };
                default { "#USER:FTCS_MENU_PhaseTransition" };
            };
        } else {
            "#USER:FTCS_MENU_VisualSignals"
        };
    };
    case "PHASE_TRANSITION": {
        "#USER:FTCS_MENU_PhaseTransition"
    };
    case "TLP_PLANNING": {
        "#USER:FTCS_MENU_TLP_Planning"
    };
    case "RADIO": {
        "#USER:FTCS_MENU_RadioComms"
    };
    case "RUNNER": {
        "#USER:FTCS_MENU_RunnerDispatch"
    };
    case "MEDIC": {
        "#USER:FTCS_MENU_MedicalTriage"
    };
    case "VISUAL": {
        "#USER:FTCS_MENU_VisualSignals"
    };
    default {
        switch (_curPhase) do {
            case 1: { "#USER:FTCS_MENU_Squad_Phase1" };
            case 2: { "#USER:FTCS_MENU_Squad_Phase2" };
            case 3: { "#USER:FTCS_MENU_Squad_Phase3" };
            default { "#USER:FTCS_MENU_Squad_Phase1" };
        };
    };
};

// Refresh every dynamic menu flag before showing. Single owner of the flags is
// fn_commandMenusRefresh: it reads the registry only, skips a concurrent call by
// its own re-entrancy guard, and the arrays it protects are already correct.
[_pltId] call FTCS_fnc_commandMenusRefresh;

showCommandingMenu _menuName;
