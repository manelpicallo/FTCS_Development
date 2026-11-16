/*
    ================================================================================
    File: fn_groupAwakenForMarch.sqf
    Module: Formations
    Author: FTCS Team
    Description: THE ONLY PLACE IN FTCS THAT WAKES A GROUP FOR A MARCH.

                 ============================ THE PROBLEM ============================
                 The platoon is deployed into the assembly area with its movement AI
                 frozen, so the deployment can be inspected before anything moves.
                 Any march world that starts from that state must re-enable movement
                 on every soldier, or the `move` / `doFollow` it issues are silently
                 ignored and the squad is left standing while the leader walks away
                 (the "lost stragglers" symptom).

                 ============================ THE RULE ==============================
                 Rule 15 (Point 0) forbids spreading raw AI commands through the
                 code base: at most three native AI commands per site, and any change
                 in unit behaviour must go through a standardised project function.
                 This file IS that function. Road march, trail march, the platoon
                 formation dispatcher and the command dispatcher all call it instead
                 of repeating their own enableAI / disableAI block.

                 WHAT IT SETS, AND WHY (same profile as the former inline blocks):

                     enableAI  "PATH" / "MOVE"  -> movement is possible again
                     disableAI "AUTOCOMBAT"     -> disciplined march, no free chasing
                     disableAI "COVER"          -> no diving for cover mid-column
                     doFollow  leader unit      -> soldiers stay with their own leader

                 It deliberately does NOT touch TARGET, ROE, speed mode, stance or
                 radio protocol: those belong to the per-mode group setters
                 (FTCS_fnc_groupSetAwareMode / groupSetROE / groupSetSpeed /
                 groupSetStance), which each caller applies separately.

                 ==================== WHY IT SITS ON THE GROUP ======================
                 The commands are per UNIT, but the semantic is per GROUP: "this group
                 may march now". The caller passes the group and the unit it must
                 follow, and never has to remember that the list must include the
                 group leader.

     Params:
         0: GROUP  - Group to awaken.
         1: OBJECT - Unit this group must follow (its march reference). Defaults to
                     the group's own leader when omitted or null.
         2: BOOLEAN - OPTIONAL. true (default) also sets "COLUMN" as the native
                     formation, matching every column march. Pass false to keep the
                     formation the caller already applied.
     Returns:
         NUMBER - Number of soldiers awakened (0 when the group is null/empty).
     Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params [
    ["_group", grpNull, [grpNull]],
    ["_followUnit", objNull, [objNull]],
    ["_setColumnFormation", true, [true]]
];

if (isNull _group) exitWith { 0 };

// Fall back to the group's own leader: a march always references a unit, and the
// caller should not have to resolve it just to wake the squad.
if (isNull _followUnit) then { _followUnit = leader _group; };

private _units = units _group;
if (count _units == 0) exitWith { 0 };

{
    if (!isNull _x) then {
        _x enableAI "PATH";
        _x enableAI "MOVE";
        _x disableAI "AUTOCOMBAT";
        _x disableAI "COVER";
        if (!isNull _followUnit) then { _x doFollow _followUnit; };
    };
} forEach _units;

if (_setColumnFormation) then { _group setFormation "COLUMN"; };

if (missionNamespace getVariable ["FTCS_Debug_Mode", false]) then {
    diag_log format ["[FTCS][MARCH] group '%1' awakened (%2 units, follow=%3, column=%4)",
        groupId _group, count _units, (if (isNull _followUnit) then { "<none>" } else { name _followUnit }), _setColumnFormation];
};

count _units
