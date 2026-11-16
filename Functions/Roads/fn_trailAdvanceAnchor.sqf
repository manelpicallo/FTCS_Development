/*
    ================================================================================
    File: fn_trailAdvanceAnchor.sqf
    Module: Roads
    Author: FTCS Team
    Description: Sole owner of the leader-trail progression (TRAIL_COLUMN march).
                 Runs every 0.5s from the dispatcher thread and does two jobs:
                 1) RECORD: appends the leader's real positions to the trail
                    whenever he moves at least _recordStep meters in a plausible
                    direction (angular dead-zone vs the trail tip tangent, same
                    policy as the road anchor: head spins never contaminate the
                    track). FINE-MANEUVER BYPASS: short steps (< 5m) record
                    unconditionally, so spinning in place and tight circling
                    keep feeding the trail instead of freezing it - long
                    deviated strides in normal march remain filtered.
                    Backwards/sideways steps refresh the reference without
                    recording.
                 2) STOP CONVERGENCE: when the leader halts (< 0.5 km/h), headDist
                    snaps to the trail tip arclength so static slots rest at their
                    true distance behind him.
                 3) TRIM: delegates to fn_trailTrimToArc (section 0, BEFORE recording),
                    which cuts the fully consumed HEAD of the trail against the OLDEST
                    ARC THE COLUMN STILL OCCUPIES ("trailMinSeatArc", published by
                    fn_formationsTrailQueueSync), never against the doctrinal
                    maxTrailOffset. Keeps memory bounded during long marches.
                 Slots sample at (headDist - trailOffsetDist) over the trail:
                 each group walks the exact line the leader walked, and every
                 offset point is precisely where the group ahead passed.
    Params:
        0: OBJECT - Platoon leader unit (trail source).
        1: HASHMAP - Trail anchor: { anchorPos, trailPath, headDist, maxTrailOffset,
                     lastAnchorMovePos, generation } mutated in-place.
        2: NUMBER - Minimum movement to record a new trail point (default 2m).
        3: NUMBER - Maximum angular deviation from trail tip tangent (default 60).
    Returns:
        NUMBER - Updated headDist (arclength of the leader along the trail).
    Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params [["_leader", objNull], ["_anchor", locationNull], ["_recordStep", 2.0], ["_maxDeviation", 60]];

if (isNull _leader || { _anchor isEqualTo locationNull }) exitWith {
    _anchor getOrDefault ["headDist", 0]
};

// --- 0. TRIM: fully consumed head points (single writer: fn_trailTrimToArc) -----
// Runs BEFORE anything else: the trim may drop head points and shift headDist, and
// the record below must append to the array that survives. Both values are re-read.
[_leader, _anchor] call FTCS_fnc_trailTrimToArc;

private _path = _anchor getOrDefault ["trailPath", []];
if (count _path == 0) exitWith { _anchor getOrDefault ["headDist", 0] };

private _headDist = _anchor getOrDefault ["headDist", 0];
private _lastMovePos = _anchor getOrDefault ["lastAnchorMovePos", getPosATL _leader];
private _leaderPos = getPosATL _leader;

// --- 1. RECORD: grow the trail behind the walking leader -----------------------
private _moveVec = _leaderPos vectorDiff _lastMovePos;
private _moveDist = _lastMovePos distance2D _leaderPos;

// Current trail tip tangent (direction of the last recorded segment)
private _tipDir = if (count _path >= 2) then {
    ((_path select (count _path - 2)) select 0) getDir ((_path select (count _path - 1)) select 0)
} else {
    getDir _leader
};

if (_moveDist >= _recordStep) then {
    private _moveBearing = _lastMovePos getDir _leaderPos;
    private _deviation = abs ((_moveBearing - _tipDir + 180 + 360) % 360 - 180);

    // Fine-maneuver bypass: with SHORT steps (spin-inside-place, tight circling,
    // repositioning) the angular dead-zone would reject most steps and freeze
    // the trail under the leader. Small moves record unconditionally - head
    // rotations alone still never record (no displacement = no branch entry).
    private _fineManeuver = (_moveDist < 5.0);

    if (_deviation <= _maxDeviation || { _fineManeuver }) then {
        // RECORD GATE: only points that are usable as a group DESTINATION enter
        // the trail. A bridge deck, a ramp or a rooftop is elevated over the
        // terrain cell and is refused by fn_navIsValidGround, so the trail simply
        // STOPS GROWING while the leader crosses - and resumes on the far shore.
        //
        // That freeze is what the queue relies on: followers keep their last valid
        // slot (all of them on solid ground) and slide forward one position at a
        // time as each front group reaches the far side.
        private _recordable = [_leaderPos, 0.5] call FTCS_fnc_navIsValidGround;

        // Diagnostics: report dz (elevation over the terrain cell) on both edges so
        // a mis-thresholded crossing is visible without a separate NAV line.
        private _tzLog = getTerrainHeightASL [_leaderPos select 0, _leaderPos select 1];
        private _dzLog = (round (((_leaderPos select 2) - _tzLog) * 100) / 100);

        if (!_recordable) exitWith {
            // Do NOT record. Refresh the reference so the pending step is not
            // accumulated into the segment recorded after the crossing.
            _anchor set ["lastAnchorMovePos", _leaderPos];
            _anchor set ["trailHalted", true];
            diag_log format ["[FTCS][TRAIL][RECORD] *** trail FROZEN at %1 z=%2 terrainZ=%3 dz=%4 (elevated: not a valid destination)",
                _leaderPos, (round ((_leaderPos select 2) * 100) / 100), (round (_tzLog * 100) / 100), _dzLog];
        };

        // Leaving an elevated stretch: the next recorded segment will start here.
        if (_anchor getOrDefault ["trailHalted", false]) then {
            _anchor set ["trailHalted", false];
            diag_log format ["[FTCS][TRAIL][RECORD] *** trail RESUMED at %1 z=%2 terrainZ=%3 dz=%4",
                _leaderPos, (round ((_leaderPos select 2) * 100) / 100), (round (_tzLog * 100) / 100), _dzLog];
        };

        // Record the leader's position and grow the trail arclength
        _path pushBack [_leaderPos, _moveBearing];
        private _stepGain = (((_path select (count _path - 2)) select 0) distance2D _leaderPos);
        _headDist = _headDist + _stepGain;
        _anchor set ["trailPath", _path];
        _anchor set ["headDist", _headDist];
        _anchor set ["lastAnchorMovePos", _leaderPos];

        // TRAIL-DIAG: a LARGE step is how the trail "jumps the bridge". The path
        // records the leader position every _recordStep (2 m) metres, so normally
        // consecutive points are ~2 m apart. If a step is much larger (leader
        // teleported, sprinted through a low-FPS frame, or crossed a bridge in one
        // sample) the segment becomes a STRAIGHT LINE OVER THE WATER: followers aim
        // at a point on that line and the AI refuses to path there.
        if (missionNamespace getVariable ["FTCS_Debug_Mode", false]) then {
            if (_stepGain > 6.0) then {
                diag_log format ["[FTCS][TRAIL][RECORD] LARGE STEP %1m at point %2 of trail -> segment spans water/props",
                    (round (_stepGain * 10) / 10), (count _path) - 1];
            };
            // A trail entry is [posATL, bearing]: extract the position first and
            // pass it to surfaceIsWater directly. Nesting `select 0` inside the
            // builtin call made the parser compare an ARRAY where a NUMBER was
            // expected -> "Error Type Array, expected Number" (Lesson 13).
            private _lastTrailEntry = _path select (count _path - 1);
            private _lastTrailPos = _lastTrailEntry select 0;
            // HEIGHT-AWARE water test (Lesson 13 Part B): surfaceIsWater samples the
            // TERRAIN cell and returns true on a BRIDGE DECK, which sits above the
            // water. Report only points that are actually AT water level.
            private _terrainZ = getTerrainHeightASL [_lastTrailPos select 0, _lastTrailPos select 1];
            if ((surfaceIsWater _lastTrailPos) && { ((_lastTrailPos select 2) - _terrainZ) < 1.2 }) then {
                diag_log format ["[FTCS][TRAIL][RECORD] leader recorded a point AT WATER LEVEL: %1 (height above terrain %2 m)",
                    _lastTrailPos, (round (((_lastTrailPos select 2) - _terrainZ) * 10) / 10)];
            };
        };
    } else {
        // Deviated move: do not record, refresh the reference window
        _anchor set ["lastAnchorMovePos", _leaderPos];
        // TRAIL-DIAG: a rejected step at a sharp turn can leave the trail BEHIND
        // the leader. If this happens while crossing a bridge, followers keep
        // aiming at the shore side.
        if (missionNamespace getVariable ["FTCS_Debug_Mode", false]) then {
            diag_log format ["[FTCS][TRAIL][RECORD] step REJECTED (deviation %1 deg > %2) - trail lags behind leader",
                (round _deviation), _maxDeviation];
        };
    };
} else {
    // Below record threshold: refresh reference only (no drift accumulation)
    _anchor set ["lastAnchorMovePos", _lastMovePos];

    // --- 2. STOP CONVERGENCE: snap the head to the trail tip when halted -------
    if (speed _leader < 0.5 && { count _path >= 2 }) then {
        // Trail tip arclength is the total path length by construction (headDist
        // grows exactly by appended segment lengths); snap only on real lag
        private _trailLen = 0;
        for "_i" from 0 to (count _path - 2) do {
            _trailLen = _trailLen + (((_path select _i) select 0) distance2D ((_path select (_i + 1)) select 0));
        };
        if (_headDist < _trailLen) then {
            _anchor set ["headDist", _trailLen];
            _headDist = _trailLen;
        };
    };
};

// --- 3. TRIM -------------------------------------------------------------------
// Owned by fn_trailTrimToArc and executed at the START of the tick (section 0),
// because it may drop head points and shift headDist: recording after it appends to
// the array that survives. Nothing is trimmed here.

_headDist
