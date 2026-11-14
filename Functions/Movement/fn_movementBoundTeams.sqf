/*
    ================================================================================
    File: fn_movementBoundTeams.sqf
    Module: Movement
    Author: FTCS Team
    Description: Shared Movement-class utility. Returns the team groups of a
                 squad that are BOUND to the squad and therefore follow a squad
                 movement order. Filtering is driven EXCLUSIVELY by the explicit
                 "teamAttachment" registry field (single source of truth):
                     "SQUAD_BOUND"   -> included (default for ordinary teams)
                     "DETACHED_HOLD" -> excluded (MG emplaced, ordered hold)
                     "DETACHED_FREE" -> excluded (deployed scouts, autonomous)
                 The optional exclusion list lets callers extend the filter with
                 runtime conditions (e.g. a fireteam currently suppressing).
                 Teams lacking a registry entry are treated as SQUAD_BOUND
                 (defensive default: never silently drop a normal team).
    Params:
        0: GROUP - Squad group whose doctrinal data resolves its teams.
                   (Alternatively: 0: STRING - doctrinal squad key "SQD_X_Y".)
        1: STRING - Attachment requirement filter (default "SQUAD_BOUND").
    Returns:
        ARRAY - Bound GROUP objects (may be empty).
    Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params [["_squadRef", grpNull], ["_require", "SQUAD_BOUND"]];

// PHASE 3: squad identity comes EXCLUSIVELY from the registry (RULE 16).
// The old version walked FTCS_Company_Data > parsedSquads twice (once to find
// the squad key, once to list its teams). The registry already carries both
// links per group:
//     "squadId"            -> "SQD_1_1"   (which squad the group belongs to)
//     "isSquadLeaderGroup" -> anchor flag (the group that carries the SL)
//     "teamAttachment"     -> SQUAD_BOUND | DETACHED_HOLD | DETACHED_FREE | ...
// so one registry pass replaces two tree walks.
private _sqdKey = "";
private _anchorRef = grpNull;
if (_squadRef isEqualType grpNull && { !isNull _squadRef }) then {
    private _refId = groupId _squadRef;
    private _refEntry = FTCS_Groups_Registry_Table getOrDefault [_refId, createHashMap];
    _sqdKey = _refEntry getOrDefault ["squadId", ""];
    _anchorRef = _refEntry getOrDefault ["parentSquadGroup", grpNull];
    // When the reference IS the anchor, parentSquadGroup self-references.
    // NOTE: the comparison MUST be parenthesised - `!X isEqualTo Y` parses as
    // `(!X) isEqualTo Y`, i.e. NOT applied to a STRING, which raises
    // "Error !: Type String, expected Bool" at runtime (Lesson 7).
    if (!isNull _anchorRef) then {
        private _anchorEntry = FTCS_Groups_Registry_Table getOrDefault [groupId _anchorRef, createHashMap];
        private _anchorSquad = _anchorEntry getOrDefault ["squadId", ""];
        if (!(_anchorSquad isEqualTo _sqdKey)) then { _anchorRef = _squadRef; };
    } else {
        _anchorRef = _squadRef;
    };
} else {
    _sqdKey = _squadRef;
};

if (_sqdKey == "") exitWith { [] };

private _boundTeams = [];
private _liveGroupMap = createHashMap;
{ if (!isNull _x) then { _liveGroupMap set [groupId _x, _x]; }; } forEach allGroups;

{
    private _gId = _x;
    private _entry = _y;
    if ((_entry getOrDefault ["squadId", ""]) isEqualTo _sqdKey
        && { (_entry getOrDefault ["teamAttachment", "SQUAD_BOUND"]) == _require }) then {
        private _g = _liveGroupMap getOrDefault [_gId, grpNull];
        if (!isNull _g) then { _boundTeams pushBack _g; };
    };
} forEach FTCS_Groups_Registry_Table;

// Fallback: the squad anchor itself when no other team resolved (unified squads)
if (count _boundTeams == 0 && { !isNull _anchorRef }) then {
    private _entry = FTCS_Groups_Registry_Table getOrDefault [groupId _anchorRef, createHashMap];
    if ((_entry getOrDefault ["teamAttachment", "SQUAD_BOUND"]) == _require) then {
        _boundTeams pushBack _anchorRef;
    };
};

_boundTeams
