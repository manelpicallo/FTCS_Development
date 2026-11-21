/*
    ================================================================================
    File: fn_formationsGroupFollowRoad.sqf
    Module: Formations
    Author: FTCS Team
    Description: Controls individual group movement loop while following the platoon leader
                 along a road/trail corridor.
                 - Continuous navigation: groups advance smoothly along road corridor
                   towards their assigned shoulder positions regardless of whether
                   the platoon leader is actively marching or temporarily stationary.
                 - When marching (speed > 2 km/h): Groups match the leader's pace exactly
                   (no slot-chasing acceleration) with natural movement pathing.
                   Road slot points are recomputed once per second.
                 - When leader is stopped (speed <= 2 km/h): Units continue moving until
                   reaching their assigned shoulder position, then hold and align strictly
                   once to the road tangent.
    Params:
        0: GROUP - Subordinate group to navigate along road.
        1: OBJECT - Reference leader (Platoon Commander / Squad Leader).
    Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params ["_group", "_leader"];

if (isNull _group || isNull _leader) exitWith {};

private _threadID = round (time * 1000) + floor (random 1000);
_group setVariable ["FTCS_FollowThread_ID", _threadID];

private _groupID = groupId _group;
private _pltIdFor = missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1];
private _not_able_time = 1.0;
private _timer = time;
private _alignedOnStop = false;
private _facingAppliedOnReady = false;
private _lastTargetPos = [0, 0, 0];
private _last_spd = 10;

// Helper to calculate exact position along a polyline at a specific distance from start
private _fnc_samplePathAtDistance = {
    params ["_distTarget", "_path"];
    private _accum = 0;
    private _foundPt = _path select (count _path - 1);

    for "_i" from 0 to (count _path - 2) do {
        private _ptA = (_path select _i) select 0;
        private _ptB = (_path select (_i + 1)) select 0;
        private _d = _ptA distance2D _ptB;
        if ((_accum + _d) >= _distTarget) exitWith {
            private _frac = if (_d > 0) then { (_distTarget - _accum) / _d } else { 0 };
            private _dir = (_path select _i) select 1;
            private _width = (_path select _i) select 2;
            private _interpPos = [
                (_ptA select 0) + ((_ptB select 0) - (_ptA select 0)) * _frac,
                (_ptA select 1) + ((_ptB select 1) - (_ptA select 1)) * _frac,
                (_ptA select 2) + ((_ptB select 2) - (_ptA select 2)) * _frac
            ];
            _foundPt = [_interpPos, _dir, _width];
        };
        _accum = _accum + _d;
    };
    _foundPt
};

// Explicitly un-freeze and awaken AI units from the assembly area freeze.
// Rule 15: the native AI commands live in ONE standardised function.

[_group, (leader _group), true] call FTCS_fnc_groupAwakenForMarch;

// Road march additionally silences TARGET and the radio protocol, and restores the
// engine's own speed cap: those are march-profile concerns the shared awakener does
// not own. They stay here, next to the road-march tick that depends on them.
{
    _x disableAI "TARGET";
    _x disableAI "RADIOPROTOCOL";
    _x forceSpeed -1;
} forEach (units _group);

// Initial deployment positioning
private _initRoadPos = [ _groupID, "roadTargetPos" ] call FTCS_fnc_registryGet;
if (!isNil "_initRoadPos" && {_initRoadPos isEqualType []} && {count _initRoadPos >= 2}) then {
    _group move _initRoadPos;
};
units _group doFollow leader _group;

[ _groupID, "movingMode", "FOLLOWING_ROAD" ] call FTCS_fnc_registrySet;

while {((_group getVariable ["FTCS_FollowThread_ID", -1]) == _threadID) && 
       ((([ _groupID, "movingMode" ] call FTCS_fnc_registryGet) == "FOLLOWING_ROAD") || 
        (([ _groupID, "movingMode" ] call FTCS_fnc_registryGet) == "HALT"))} do
{
    _spd = speed _leader;

    // Terminate immediately if a newer follow thread was spawned for this group
    if ((_group getVariable ["FTCS_FollowThread_ID", -1]) != _threadID) exitWith {};

    // -------------------------------------------------------------------------
    // 1. ACTIVE MARCH ALONG ROAD (leader speed > 2 km/h)
    // -------------------------------------------------------------------------
    if (_spd > 2) then 
    {
        _last_spd = _spd;

        _timer = time + _not_able_time;

        waitUntil { 
            time > _timer || 
            ((_group getVariable ["FTCS_FollowThread_ID", -1]) != _threadID) ||
            ([ _groupID, "movingMode" ] call FTCS_fnc_registryGet) != "FOLLOWING_ROAD" || 
            unitReady (leader _group) || 
            lifeState (leader _group) == "DEAD" || 
            lifeState (leader _group) == "INCAPACITATED" 
        };

        if ((_group getVariable ["FTCS_FollowThread_ID", -1]) != _threadID) exitWith {};
        if (([ _groupID, "movingMode" ] call FTCS_fnc_registryGet) != "FOLLOWING_ROAD") exitWith {};

        { _x disableAI "RADIOPROTOCOL"; } forEach (units _group);

        // Retrieve assigned road progression distance and shoulder offset
        private _offsetDist = [ _groupID, "roadOffsetDist" ] call FTCS_fnc_registryGet;
        private _shoulderOffset = [ _groupID, "roadShoulderOffset" ] call FTCS_fnc_registryGet;
        if (isNil "_offsetDist") then { _offsetDist = 12.0; };
        if (isNil "_shoulderOffset") then { _shoulderOffset = 0.0; };

        private _curLeaderPos = getPosATL _leader;
        private _curLeaderDir = getDir _leader;

        // Road slot position: sampled from the FROZEN march-oriented anchor path.
        // Slots sample at (headDist - offsetDist): as the leader advances, each slot
        // slides FORWARD along the road, keeping the group offsetDist meters behind.
        private _anchor = missionNamespace getVariable [format ["FTCS_Road_Anchor_PLT_%1", _pltIdFor], createHashMap];
        private _dynPath = _anchor getOrDefault ["roadPath", []];
        private _headDist = _anchor getOrDefault ["headDist", 0];
        private _dynTargetPos = [0, 0, 0];
        private _dynTangentDir = _curLeaderDir;

        if (count _dynPath >= 2) then {
            private _sample = [(_headDist - _offsetDist) max 0, _dynPath] call _fnc_samplePathAtDistance;
            private _roadCenter = _sample select 0;
            _dynTangentDir = _sample select 1;
            private _perpDir = (_dynTangentDir + 90) % 360;
            _dynTargetPos = _roadCenter getPos [abs _shoulderOffset, if (_shoulderOffset < 0) then { (_perpDir + 180) % 360 } else { _perpDir }];
        } else {
            _dynTargetPos = _curLeaderPos getPos [_offsetDist, (_curLeaderDir + 180) % 360];
        };

        // ---------------------------------------------------------------------
        // TRANSITABILITY SNAP (Lesson 13 / PENDING-4, phase C)
        //
        // Two distinct cases leave a road slot without ground support:
        //   a) the shoulder offset pushes it off a narrow bridge deck, or
        //   b) the map's bridge roadway is offset/narrower than the visual deck
        //      (Prokhorovka 1943 crosses on the LEFT edge only), so the geometric
        //      centre of the bridge is WATER for the engine.
        // In both cases the AI would SWIM to the slot and settle under the bridge.
        //
        // fn_findTransitableNear probes the slot (ray DOWN first: an object hit -
        // bridge deck, pier, ramp - means SUPPORTED even when surfaceIsWater says
        // "water"; terrain water test only when nothing solid is hit) and snaps it
        // to the nearest supported point within 12 m.
        // PRIORITY AT A CROSSING: crossing beats geometry - a few metres of lateral
        // drift to reach real traversable ground is always the right trade.
        // ---------------------------------------------------------------------
        private _snapRC = [_dynTargetPos, 12, 1] call FTCS_fnc_findTransitableNear;
        private _snapRCPos = _snapRC select 0;
        private _snapRCOriginal = _snapRC select 1;
        private _snapRCOffset = _snapRC select 2;
        if (_snapRCOffset >= 0) then {
            if (!_snapRCOriginal) then {
                diag_log format ["[FTCS][ROAD][SNAP] *** '%1' slot unsupported (shoulder %2) -> snapped %3 m to %4",
                    _groupID, _shoulderOffset, (round (_snapRCOffset * 10) / 10), _snapRCPos];
            };
            _dynTargetPos = _snapRCPos;
        } else {
            _dynTargetPos = getPosATL (leader _group);
            diag_log format ["[FTCS][ROAD][SNAP] *** '%1' NO traversable ground within 12 m -> HOLDING at %2",
                _groupID, _dynTargetPos];
        };

        // Update registry with current dynamic road target
        [ _groupID, "roadTargetPos", _dynTargetPos ] call FTCS_fnc_registrySet;
        [ _groupID, "roadTangentDir", _dynTangentDir ] call FTCS_fnc_registrySet;

        // Match group pace strictly to leader speed (no adaptive slot-chasing acceleration)
        { _x limitSpeed _spd; } forEach (units _group);

        // ROAD-DIAG (throttled): reports the slot target and whether it is over
        // water. A slot point that lands on water is NOT crossable by Arma's AI,
        // which is the classic "units refuse to step on the bridge" symptom: the
        // slot sampled from the road path drifted laterally off the deck.
        private _dbgKey = format ["FTCS_RoadDbg_%1", _groupID];
        private _now = time;
        // HEIGHT-AWARE water test (Lesson 13 Part B): surfaceIsWater is true on a
        // BRIDGE DECK because it samples the terrain cell below, so a road crossing
        // a bridge must NOT be reported as "on water". Only a slot AT water level
        // (< 1.2 m above terrain) is genuinely uncrossable.
        private _tgtTerrainZ = getTerrainHeightASL [(_dynTargetPos select 0), (_dynTargetPos select 1)];
        private _tgtWater = (surfaceIsWater _dynTargetPos) && { ((_dynTargetPos select 2) - _tgtTerrainZ) < 1.2 };
        // Always report an uncrossable slot (it is a real failure, not telemetry)
        if (_tgtWater) then {
            diag_log format ["[FTCS][ROAD][FOLLOW] *** '%1' slot target is AT WATER LEVEL - AI will refuse to path there.", _groupID];
        };
        // Verbose per-group telemetry only under FTCS_Debug_Mode
        if (missionNamespace getVariable ["FTCS_Debug_Mode", false] && { _now > (_group getVariable [_dbgKey, 0]) }) then {
            _group setVariable [_dbgKey, _now + 5];
            private _ldrPos = getPosATL (leader _group);
            private _ldrTerrainZ = getTerrainHeightASL [(_ldrPos select 0), (_ldrPos select 1)];
            private _ldrWater = (surfaceIsWater _ldrPos) && { ((_ldrPos select 2) - _ldrTerrainZ) < 1.2 };
            diag_log format ["[FTCS][ROAD][FOLLOW] '%1' spd=%2 tgt=%3 tgtWater=%4 ldrWater=%5 offDist=%6 shoulder=%7 distToTgt=%8",
                _groupID, (round (_spd * 10) / 10), _dynTargetPos, _tgtWater, _ldrWater,
                _offsetDist, _shoulderOffset, round ((leader _group) distance2D _dynTargetPos)];
        };

        // Command group movement towards current road position
        _group move _dynTargetPos;
        units _group doFollow leader _group;

        _alignedOnStop = false;
        _facingAppliedOnReady = false;
    }
    // -------------------------------------------------------------------------
    // 2. STOPPED / STATIC (speed <= 2 km/h): Anchor formation along road slot
    // -------------------------------------------------------------------------
    else 
    {
        private _offsetDist = [ _groupID, "roadOffsetDist" ] call FTCS_fnc_registryGet;
        private _shoulderOffset = [ _groupID, "roadShoulderOffset" ] call FTCS_fnc_registryGet;
        if (isNil "_offsetDist") then { _offsetDist = 12.0; };
        if (isNil "_shoulderOffset") then { _shoulderOffset = 0.0; };

        private _curLeaderPos = getPosATL _leader;
        private _curLeaderDir = getDir _leader;

        // Stopped state samples slots from the FROZEN march-oriented anchor path too,
        // keeping slot order strictly fixed regardless of leader head rotation
        private _anchor = missionNamespace getVariable [format ["FTCS_Road_Anchor_PLT_%1", _pltIdFor], createHashMap];
        private _stopPath = _anchor getOrDefault ["roadPath", []];
        private _headDist = _anchor getOrDefault ["headDist", 0];
        private _roadAdvanceDir = _anchor getOrDefault ["advanceDir", [_pltIdFor, "advanceDirection", _curLeaderDir] call FTCS_fnc_registryGetPlatoon];
        private _stopTargetPos = [0, 0, 0];
        private _stopTangentDir = _roadAdvanceDir;

        if (count _stopPath >= 2) then {
            private _sample = [(_headDist - _offsetDist) max 0, _stopPath] call _fnc_samplePathAtDistance;
            private _roadCenter = _sample select 0;
            _stopTangentDir = _sample select 1;
            private _perpDir = (_stopTangentDir + 90) % 360;
            _stopTargetPos = _roadCenter getPos [abs _shoulderOffset, if (_shoulderOffset < 0) then { (_perpDir + 180) % 360 } else { _perpDir }];
        } else {
            _stopTargetPos = _curLeaderPos getPos [_offsetDist, (_roadAdvanceDir + 180) % 360];
        };

        [ _groupID, "roadTargetPos", _stopTargetPos ] call FTCS_fnc_registrySet;
        [ _groupID, "roadTangentDir", _stopTangentDir ] call FTCS_fnc_registrySet;

        // Detect if target position shifted (identical to cross-country logic)
        private _posChanged = ((_stopTargetPos distance2D _lastTargetPos) > 1.5);

        if (!_alignedOnStop || _posChanged) then 
        {
            _group move _stopTargetPos;
            _lastTargetPos = _stopTargetPos;
            _alignedOnStop = true;
            _facingAppliedOnReady = false;
        };

        // Once units arrive at final stopped position (unitReady), apply facing strictly ONCE
        if (!_facingAppliedOnReady && {unitReady (leader _group) || ((leader _group) distance2D _stopTargetPos < 3)}) then 
        {
            _group setFormDir _stopTangentDir;
            _facingAppliedOnReady = true;
        };

        { _x disableAI "RADIOPROTOCOL"; } forEach (units _group);
        if (([ _groupID, "movingMode" ] call FTCS_fnc_registryGet) != "FOLLOWING_ROAD") exitWith {
            // Follow ended: restore radio protocol so units report normally again
            { _x enableAI "RADIOPROTOCOL"; } forEach (units _group);
        };
        sleep 1.0;
    };
};
