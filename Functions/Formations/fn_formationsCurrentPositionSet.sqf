/*
    ================================================================================
    File: fn_formationsCurrentPositionSet.sqf
    Module: Formations
    Author: FTCS Team
    Description: Captures current real-world ground positions and relative orientations
                 of all platoon squads and nested fireteams on the terrain, locking them
                 into the active formation registry without altering default templates.
                 Preserves two-tier hierarchy:
                 - Tier 1: Squad Leaders anchored relative to Platoon Leader.
                 - Tier 2: Fireteams anchored relative to their own Squad Leader.
    Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4)

    +-----------------------------------------------------------------------------+
    |                 CURRENT GROUND LAYOUT CAPTURE ENGINE                        |
    +-----------------------------------------------------------------------------+
    |                                                                             |
    |  Platoon Leader [Anchor] (Position P, Heading D)                            |
    |         │                                                                   |
    |         ├─► Squad 1 Leader (d1, bearing1 -> relDir to Commander)            |
    |         │        │                                                          |
    |         │        ├─► Fireteam 2 (dist, relDir to Squad 1 Leader)            |
    |         │        └─► Fireteam 3 (dist, relDir to Squad 1 Leader)            |
    |         │                                                                   |
    |         ├─► Squad 2 Leader (d2, bearing2 -> relDir to Commander)            |
    |         │        │                                                          |
    |         │        ├─► Fireteam 2 (dist, relDir to Squad 2 Leader)            |
    |         │        └─► Fireteam 3 (dist, relDir to Squad 2 Leader)            |
    |         │                                                                   |
    |         └─► Squad 3 Leader (d3, bearing3 -> relDir to Commander)            |
    +-----------------------------------------------------------------------------+
    ================================================================================
*/

params [
    ["_platoonLeaderUnit", objNull],
    ["_explicitMode", ""]
];

if (isNull _platoonLeaderUnit) then {
    private _commanderGroup = missionNamespace getVariable ["FTCS_Group_Commander", group player];
    _platoonLeaderUnit = if (!isNull _commanderGroup) then { leader _commanderGroup } else { player };
};

if (isNull _platoonLeaderUnit) exitWith { false };

// 1. Resolve platoon IDENTITY + STATE from the PLATOON REGISTRY (RULE 16).
// Only the DISPLAY NAME comes from the doctrine tree (UI caption, Point 18).
private _pltKey = missionNamespace getVariable ["FTCS_SelectedPlatoonKey", ""];
private _pltNum = missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1];
if (_pltKey != "") then {
    private _parsed = _pltKey splitString "_";
    if (count _parsed > 1) then { _pltNum = parseNumber (_parsed select 1); };
};
private _pltEntryR = (missionNamespace getVariable ["FTCS_Platoons_Registry", createHashMap]) getOrDefault [_pltNum, createHashMap];
private _platoonsMap = FTCS_Company_Data getOrDefault ["platoons", createHashMap];
private _pltData = _platoonsMap getOrDefault [format ["PLT_%1", _pltNum], createHashMap];
private _pltName = _pltData getOrDefault ["name", format ["PLT_%1", _pltNum]];

// Live group map: registry keys ARE groupIds, so hierarchy fields resolve to
// actual group objects in one lookup.
private _liveGroupMap = createHashMap;
{ if (!isNull _x) then { _liveGroupMap set [groupId _x, _x]; }; } forEach allGroups;

if (count (_pltEntryR getOrDefault ["squads", []]) == 0) exitWith {
    systemChat format ["[FTCS Formations] Error: No registered squads found for %1.", _pltKey];
    false;
};

// 2. Validate operational phase: Troops in Phase 0 (DEPLOYMENT / INSPECTION) remain frozen
private _currentPhase = _pltEntryR getOrDefault ["currentPhase", 0];
if (_currentPhase == 0) exitWith {
    systemChat format ["[FTCS Formations] %1 is in DEPLOYMENT / INSPECTION phase (Troops Frozen). Set Operational Phase first.", _pltName];
    hint parseText format ["<t color='#FFAA00'>[FORMATION BLOCKED]</t><br/><t color='#FFFFFF'>%1</t> is in inspection mode.<br/><t color='#00FFCC'>Action required:</t> Set Operational Phase (Approach / Combat) via Platoon Sergeant before locking formation.", _pltName];
    false;
};

// 3. Resolve active follow mode (Relative vs Absolute). The ORDER lives in the
// platoon registry (Rule 20); an explicit mode passed by the caller wins because
// it is the order being applied right now.
private _followModeCleaned = if (_explicitMode != "") then {
    _explicitMode
} else {
    [_pltNum, "followMode", "REL"] call FTCS_fnc_registryGetPlatoon
};

private _isRelative = (_followModeCleaned != "ABS");
// Normalised group mode string handed to the follow loops
private _followMode = if (_isRelative) then { "FOLLOWING_COMMANDER_REL" } else { "FOLLOWING_COMMANDER_ABS" };
private _leaderGroup = group _platoonLeaderUnit;

// Update the platoon axis sentinels strictly from the leader's current heading.
// Registry first (Rule 20); the legacy globals are still refreshed because the
// deployment pipeline (fn_executeDeployment / fn_initDeployMenu) reads them.
// "followModeFacing" is rewritten too: this capture DEFINES the locked compass
// bearing whenever it runs (REL/ABS switch, ground capture), exactly as the
// former company-wide Fixed_Abs_Dir write did.
private _advanceDir = getDir _platoonLeaderUnit;
[_pltNum, "followModeFacing", _advanceDir] call FTCS_fnc_registrySetPlatoon;
[_pltNum, "advanceDirection", _advanceDir] call FTCS_fnc_registrySetPlatoon;
missionNamespace setVariable ["FTCS_Platoon_Fixed_Abs_Dir", _advanceDir];
missionNamespace setVariable ["FTCS_Last_Commander_Dir", _advanceDir];
missionNamespace setVariable ["FTCS_Platoon_Advance_Direction", _advanceDir];

private _allSubordinateGroups = [];

// 4. Capture Platoon HQ Sub-teams (Tier 1: anchored relative to Platoon Leader)
// PHASE 6: the HQ element is identified by squadId (SQD_<N>_0) in the registry.
private _hqSquadId = format ["SQD_%1_0", _pltNum];
{
    private _gEntry = _y;
    if ((_gEntry getOrDefault ["squadId", ""]) isEqualTo _hqSquadId) then {
        private _tGrp = _liveGroupMap getOrDefault [_x, grpNull];
        if (!isNull _tGrp && {_tGrp != _leaderGroup}) then {
            private _tLeader = leader _tGrp;
            if (!isNull _tLeader) then {
                private _tDist = _tLeader distance2D _platoonLeaderUnit;
                private _tAngle = if (_isRelative) then {
                    _platoonLeaderUnit getRelDir _tLeader
                } else {
                    ((_platoonLeaderUnit getDir _tLeader) - _advanceDir + 360) % 360
                };
                private _gId = groupId _tGrp;

                [_gId, "formationPosition", [_tDist, _tAngle, _leaderGroup]] call FTCS_fnc_registrySet;
                [_gId, "relPosition", [_tDist, _tAngle, _leaderGroup]] call FTCS_fnc_registrySet;

                if !(_tGrp in _allSubordinateGroups) then { _allSubordinateGroups pushBack _tGrp; };
            };
        };
    };
} forEach FTCS_Groups_Registry_Table;

// 5. Capture Combat Squads & nested Fireteams (Two-tier hierarchy)
// PHASE 6: hierarchy comes from the registry (RULE 16):
//   squadId            -> which squad a group belongs to
//   isSquadLeaderGroup -> the ONE group carrying the Squad Leader (Tier 1)
//   parentSquadGroup   -> the anchor a Tier-2 fireteam hangs from
//
// NOTE: the two-tier capture is a GEOMETRY pass, so it is done per SQUAD
// (anchor first, then its teams) to keep the exact original semantics: Tier 1
// relative to the platoon leader, Tier 2 relative to the squad anchor.
{
    private _sqdAnchor = _x;
    if (!isNull _sqdAnchor && { _sqdAnchor != _leaderGroup }) then {
        private _sqdId = (FTCS_Groups_Registry_Table getOrDefault [groupId _sqdAnchor, createHashMap]) getOrDefault ["squadId", ""];

        // Skip the HQ element: it was captured in step 4
        if (!(_sqdId isEqualTo _hqSquadId)) then {
            // ---- Tier 1: squad anchor relative to the Platoon Leader
            private _sqdAnchorObj = leader _sqdAnchor;
            if (!isNull _sqdAnchorObj) then {
                private _sqdDist = _sqdAnchorObj distance2D _platoonLeaderUnit;
                private _sqdAngle = if (_isRelative) then {
                    _platoonLeaderUnit getRelDir _sqdAnchorObj
                } else {
                    ((_platoonLeaderUnit getDir _sqdAnchorObj) - _advanceDir + 360) % 360
                };
                private _aId = groupId _sqdAnchor;

                [_aId, "formationPosition", [_sqdDist, _sqdAngle, _leaderGroup]] call FTCS_fnc_registrySet;
                [_aId, "relPosition", [_sqdDist, _sqdAngle, _leaderGroup]] call FTCS_fnc_registrySet;
                if !(_sqdAnchor in _allSubordinateGroups) then { _allSubordinateGroups pushBack _sqdAnchor; };

                // ---- Tier 2: fireteams of this squad relative to the anchor
                {
                    private _teamEntry = _y;
                    if ((_teamEntry getOrDefault ["squadId", ""]) isEqualTo _sqdId
                        && { !(_teamEntry getOrDefault ["isSquadLeaderGroup", false]) }) then {
                        private _subTeamGrp = _liveGroupMap getOrDefault [_x, grpNull];
                        if (!isNull _subTeamGrp) then {
                            private _subLeader = leader _subTeamGrp;
                            if (!isNull _subLeader) then {
                                private _subDist = _subLeader distance2D _sqdAnchorObj;
                                private _subAngle = if (_isRelative) then {
                                    _sqdAnchorObj getRelDir _subLeader
                                } else {
                                    ((_sqdAnchorObj getDir _subLeader) - _advanceDir + 360) % 360
                                };
                                private _subGId = groupId _subTeamGrp;

                                [_subGId, "formationPosition", [_subDist, _subAngle, _sqdAnchor]] call FTCS_fnc_registrySet;
                                [_subGId, "relPosition", [_subDist, _subAngle, _sqdAnchor]] call FTCS_fnc_registrySet;
                                if !(_subTeamGrp in _allSubordinateGroups) then { _allSubordinateGroups pushBack _subTeamGrp; };
                            };
                        };
                    };
                } forEach FTCS_Groups_Registry_Table;
            };
        };
    };
} forEach (_pltEntryR getOrDefault ["squads", []]);

// 6. Launch concurrent follow-commander movement threads for all subordinate groups
if (count _allSubordinateGroups > 0) then {
    [_allSubordinateGroups, _followMode] spawn FTCS_fnc_formationsGroupListFollowCommander;
};

// 7. Update 2D tactical map formation arrow marker & debug slot points
{
    if (_x find "FTCS_MAP_FORMATION_ARROW" == 0 || _x find "FTCS_FORMATION_MARKER" == 0 || _x find "FTCS_DEBUG_SLOT_" == 0) then {
        deleteMarkerLocal _x;
    };
} forEach allMapMarkers;

private _anchorPos = getPosATL _platoonLeaderUnit;
private _arrowMarkerName = format ["FTCS_MAP_FORMATION_ARROW_%1", round time];
private _arrowMarker = createMarkerLocal [_arrowMarkerName, _anchorPos];
_arrowMarker setMarkerTypeLocal "mil_arrow2";
_arrowMarker setMarkerColorLocal "ColorGreen";
_arrowMarker setMarkerDirLocal _advanceDir;
_arrowMarker setMarkerSizeLocal [1.2, 1.8];
_arrowMarker setMarkerTextLocal format [" %1 (Ground Locked - %2°)", _pltName, round _advanceDir];

// 8. Launch real-time dynamic formation slots visualizer on map
missionNamespace setVariable ["FTCS_Debug_Mode", true];
[_platoonLeaderUnit] spawn FTCS_fnc_formationsLiveSlotsDebugWorker;

// 9. Player feedback
private _modeLabel = if (_isRelative) then { "Relative" } else { "Absolute" };
systemChat format ["[FORMATION LOCKED] %1 formation geometry anchored to current real-world ground layout (%2 mode).", _pltName, _modeLabel];
hint parseText format ["<t color='#00FFCC'>[GROUND LAYOUT LOCKED]</t><br/><t color='#FFFFFF'>%1</t><br/><t color='#FFAA00'>Mode:</t> %2<br/><t color='#AAAAAA'>Positions and relative bearings captured from active terrain coordinates.", _pltName, _modeLabel];

true;
