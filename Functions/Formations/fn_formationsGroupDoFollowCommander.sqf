/*
    Author: FTCS Framework / Manel P.
    Function: FTCS_fnc_formationsGroupDoFollowCommander
    Description: Controls the individual group movement loop to follow the commander 
                 in relative or absolute modes (AI-Agnostic).
                 When marching (speed > 2), subordinates dynamically track leader movement.
                 When stopped (speed <= 2), subordinate groups (Squad Leaders following
                 the Platoon Leader, and Fireteams following their Squad Leader) anchor
                 their formation positions and facing strictly aligned with the platoon's
                 advance direction in that moment (platoon registry "advanceDirection").
                 Follow mode and axis are read from FTCS_Platoons_Registry[pltId]
                 (Rule 20): the group only owns its EXCEPTION ("movingMode").
*/

params ["_group", "_mode", "_leader"];

if (isNull _group || isNull _leader) exitWith {};

// Generate unique follow thread identifier to terminate any previous concurrent thread for this group
private _threadID = round (time * 1000) + floor (random 1000);
_group setVariable ["FTCS_FollowThread_ID", _threadID];

private _groupID = groupId _group;
private _not_able_time = 1;  
private _timer = time;
private _spd = speed _leader;
private _last_spd = 10;
private _lastTargetPos = [0, 0, 0];

// Identify if the reference leader is the main platoon commander (player or platoon HQ leader)
private _isPlatoonCommander = (isPlayer _leader || {_leader == (leader (missionNamespace getVariable ["FTCS_Group_Commander", grpNull]))} || {_leader == (missionNamespace getVariable ["FTCS_Platoon_Leader_Unit", objNull])} || {(vehicleVarName _leader) find "LEADER" >= 0 && {(vehicleVarName _leader) find "SQD_" < 0}});

// Platoon registry sentinels: follow mode and axis belong to the PLATOON (Rule 20).
// Resolved once per thread launch; the live axis is re-read inside the loop.
private _pltId = missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1];
private _pltMode = [_pltId, "followMode", "REL"] call FTCS_fnc_registryGetPlatoon;

// Only initialize advance direction if not previously defined by a formation order or active march
if (_isPlatoonCommander && {_mode != "FOLLOWING_COMMANDER_ABS"}) then {
    if (isNil { [_pltId, "advanceDirection", nil] call FTCS_fnc_registryGetPlatoon }) then {
        [_pltId, "advanceDirection", getDir _leader] call FTCS_fnc_registrySetPlatoon;
    };
};

[ _groupID, "movingMode", _mode ] call FTCS_fnc_registrySet;

// Retrieve current platoon advance direction
private _platoonDir = if (_mode == "FOLLOWING_COMMANDER_ABS") then {
    [_pltId, "followModeFacing", [_pltId, "advanceDirection", getDir _leader] call FTCS_fnc_registryGetPlatoon] call FTCS_fnc_registryGetPlatoon
} else {
    [_pltId, "advanceDirection", getDir _leader] call FTCS_fnc_registryGetPlatoon
};
private _relPos = [ _groupID, "relPosition" ] call FTCS_fnc_registryGet;

// Initial deployment positioning
if (_mode == "FOLLOWING_COMMANDER_REL") then 
{
    if (!isNil "_relPos" && {_relPos isEqualType []} && {count _relPos >= 2} && {(_relPos select 0) >= 0}) then {
        private _dist = _relPos select 0;
        private _relAngle = _relPos select 1;
        private _refHeading = if (speed _leader > 2) then { getDir _leader } else { _platoonDir };
        _group move ((getPosATL _leader) getPos [_dist, _refHeading + _relAngle]);
    };
    units _group doFollow leader _group;
};

if (_mode == "FOLLOWING_COMMANDER_ABS") then 
{
    if (!isNil "_relPos" && {_relPos isEqualType []} && {count _relPos >= 2} && {(_relPos select 0) >= 0}) then {
        _group move ((getPosATL _leader) getPos [_relPos select 0, _platoonDir + (_relPos select 1)]);
    };
    units _group doFollow leader _group;
};

private _alignedOnStop = false;
private _facingAppliedOnReady = false;

while {((_group getVariable ["FTCS_FollowThread_ID", -1]) == _threadID) && 
       (([ _groupID, "movingMode" ] call FTCS_fnc_registryGet) == _mode)} do
// movingMode == "HALT" (platoon HALT, fn_platoonHaltRejoin) does NOT match
// _mode -> the while exits and the group leaves its follow loop: a halted
// group stops following its leader until its mode is rewritten (REJOIN).
{
    _spd = speed _leader;

    // Terminate immediately if a newer follow thread was spawned for this group
    if ((_group getVariable ["FTCS_FollowThread_ID", -1]) != _threadID) exitWith {};

    // -------------------------------------------------------------------------
    // 1. ACTIVE MARCHING (speed > 2 km/h): Dynamic formation tracking.
    //    Fixed 1s cadence (no waitUntil/unitReady gating): re-issuing moves on
    //    unit-ready moments caused path re-plan churn and micro-command spam.
    //    Exit conditions are polled inside the loop condition itself.
    // -------------------------------------------------------------------------
    if (_spd > 2) then 
    {
        _last_spd = _spd;
        { _x limitSpeed _spd; } foreach units _group;

        { _x disableAI "RADIOPROTOCOL"; } foreach units _group;

        // Continuously update the platoon axis of advance from the commander's active
        // march heading (relative mode only). SENTINEL FIRST, one-way flow (Rule 20):
        // gameplay writes, the menu/other threads only read.
        if (_isPlatoonCommander && {_pltMode != "ABS"}) then {
            [_pltId, "advanceDirection", getDir _leader] call FTCS_fnc_registrySetPlatoon;
        };

        _relPos = [ _groupID, "relPosition" ] call FTCS_fnc_registryGet;
        if (!isNil "_relPos" && {_relPos isEqualType []} && {count _relPos >= 2} && {(_relPos select 0) >= 0}) then {
            if (_mode == "FOLLOWING_COMMANDER_REL") then {
                _group move (_leader getRelPos [_relPos select 0, _relPos select 1]);
            } else {
                _group move ((getPosATL _leader) getPos [_relPos select 0, _platoonDir + (_relPos select 1)]);
            };
        };

        units _group doFollow leader _group;

        _alignedOnStop = false;
        _facingAppliedOnReady = false;

        sleep 1.0;
    }
    // -------------------------------------------------------------------------
    // 2. STOPPED / STATIC (speed <= 2 km/h): Anchor formation along platoon heading
    // -------------------------------------------------------------------------
    else 
    {
        // Retrieve latest platoon advance direction in that moment
        private _curPlatoonDir = if (_mode == "FOLLOWING_COMMANDER_ABS") then {
            _platoonDir
        } else {
            [_pltId, "advanceDirection", getDir _leader] call FTCS_fnc_registryGetPlatoon
        };

        // Resolve Platoon Leader unit (Lieutenant / Player or NPC Platoon Leader)
        private _platoonLeader = missionNamespace getVariable ["FTCS_Platoon_Leader_Unit", objNull];
        if (isNull _platoonLeader) then {
            _platoonLeader = missionNamespace getVariable ["FTCS_Formation_Visualizer_Leader", objNull];
        };
        if (isNull _platoonLeader) then {
            if (!((vehicleVarName _leader) find "SQD_" >= 0)) then {
                _platoonLeader = _leader;
            };
        };
        if (isNull _platoonLeader) then { _platoonLeader = player; };

        // Determine facing orientation based on follow mode:
        // In both RELATIVE and ABSOLUTE modes, when stopped, the internal unit facing of each group
        // aligns strictly with the platoon's active formation direction / platoon leader's heading.
        private _targetFacing = if (_mode == "FOLLOWING_COMMANDER_REL") then {
            [_pltId, "advanceDirection", getDir _platoonLeader] call FTCS_fnc_registryGetPlatoon
        } else {
            getDir _platoonLeader
        };

        // Read assigned formation polar coordinates (reusing the script-scope
        // _relPos: a second `private _relPos` here would shadow the outer one and
        // re-trigger the Lesson 34/37 family of scope bugs)
        _relPos = [ _groupID, "relPosition" ] call FTCS_fnc_registryGet;
        private _hasValidPos = (!isNil "_relPos" && {_relPos isEqualType []} && {count _relPos >= 2} && {(_relPos select 0) >= 0});
        private _targetPos = [0, 0, 0];
        if (_hasValidPos) then {
            private _dist = _relPos select 0;
            private _relAngle = _relPos select 1;
            _targetPos = if (_mode == "FOLLOWING_COMMANDER_REL") then {
                (getPosATL _leader) getPos [_dist, _curPlatoonDir + _relAngle]
            } else {
                (getPosATL _leader) getPos [_dist, _platoonDir + _relAngle]
            };
        };

        // Detect if a new formation was ordered while stopped (target position shift)
        private _posChanged = (_hasValidPos && {(_targetPos distance2D _lastTargetPos) > 1.5});

        if (!_alignedOnStop || _posChanged) then 
        {
            if (_hasValidPos) then {
                _group move _targetPos;
                _lastTargetPos = _targetPos;
            };

            _alignedOnStop = true;
            _facingAppliedOnReady = false;
        };

        // Once units arrive at final stopped position (unitReady), apply facing strictly ONCE
        if (!_facingAppliedOnReady && {unitReady (leader _group) || ((leader _group) distance2D _targetPos < 3)}) then 
        {
            _group setFormDir _targetFacing;
            _facingAppliedOnReady = true;
        };

        // Stopped approach: no explicit limitSpeed (natural arrival pacing),
        // matching the road/trail follow standard; the stale last-march speed
        // is never re-applied once the leader has halted.
        { _x disableAI "RADIOPROTOCOL"; } foreach units _group;
        if (([ _groupID, "movingMode" ] call FTCS_fnc_registryGet) != _mode) exitWith {
            // Follow ended: restore radio protocol so units report normally again
            { _x enableAI "RADIOPROTOCOL"; } foreach units _group;
        };
        sleep 1.0;
    };
};
