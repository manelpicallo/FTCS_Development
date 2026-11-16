/*
    ================================================================================
    File: fn_findTransitableNear.sqf
    Module: Roads
    Author: FTCS Team
    Description: Finds the nearest GROUND-SUPPORTED point to a requested slot.

                 Used by the march pipelines (trail / road) before a group is told
                 to move. Arma exposes no "is there a navmesh here?" query, so the
                 test is built from what the ENGINE can actually report.

                 WHY A RAY AND NOT `surfaceIsWater`:
                 `surfaceIsWater` samples the TERRAIN CELL below the point. On a
                 bridge deck that cell is the river, so the call returns TRUE for a
                 perfectly walkable deck. Rejecting on that basis made the whole
                 formation refuse to cross (Prokhorovka 1943 bridges are only ~0.5 m
                 above the water line, so a height comparison does not save it
                 either - the deck can sit closer than 1.2 m to the water).

                 DECISION ORDER - the ray is the SOURCE OF TRUTH:
                   1. Cast a ray straight DOWN from 2 m above the point.
                   2. If it hits a NON-TERRAIN OBJECT (bridge deck, pier, platform,
                      ramp) at the requested height -> SUPPORTED. This is what makes
                      bridges and piers usable even when the terrain below is water.
                   3. Only when the ray hits no object does the point stand on
                      TERRAIN: then the height-aware water test decides
                      (wet only if surface is water AND the point sits at water
                      level, i.e. below 1.2 m above the terrain).

                 Search order:
                   0. The requested point itself.
                   1. Concentric rings (step `_step` metres, 8 directions per ring)
                      up to `_maxRadius`, nearest-first.
                 The ring order keeps the slot layout coherent: a whole column
                 shifts by similar small lateral offsets instead of scattering.

     Why it exists:
                 "At a bridge crossing the PRIORITY IS CROSSING, not the exact
                 formation geometry." Moving a slot by 2-4 m to land on real
                 traversable ground is strictly better than sending the group to
                 swim to a geometrically perfect but unreachable point.

     Params:
         0: ARRAY  - Requested slot position [x, y, z].
         1: NUMBER - OPTIONAL maximum search radius in metres (default 12 - a wide
                     bridge deck can leave the slot up to half a width off).
         2: NUMBER - OPTIONAL ring step in metres (default 1).
         3: NUMBER - OPTIONAL height tolerance in metres (default 1.5). A ray hit
                     lower than (requestedZ - tolerance) is terrain, not a deck.
     Returns:
         ARRAY - [foundPos, isOriginal, offsetMetres]
                 0: foundPos      - the point to use (equals the request if ok)
                 1: isOriginal    - BOOLEAN, true when the requested point was used
                 2: offsetMetres  - SCALAR, planar distance from the request
                 When nothing is found, foundPos is the requested point, isOriginal
                 is false and offsetMetres is -1 (caller decides to hold or retry).
     Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params [
    ["_slotPos", [0, 0, 0], [[]]],
    ["_maxRadius", 12, [0]],
    ["_step", 1, [0]],
    ["_heightTol", 1.5, [0]]
];

if (count _slotPos < 3) exitWith { [_slotPos, true, 0] };

// ---------------------------------------------------------------------------
// Local helper: is this point standing on something solid?
//   RAY FIRST (bridge decks / piers / ramps are objects over water)
//   TERRAIN WATER TEST SECOND (only when nothing solid was hit)
// ---------------------------------------------------------------------------
private _fnc_isSupported = {
    params ["_p"];

    private _top = _p vectorAdd [0, 0, 2.0];
    private _bottom = _p vectorAdd [0, 0, -3.0];
    private _hits = lineIntersectsSurfaces [_top, _bottom, objNull, objNull, true, 1, "GEOM", "NONE"];

    if (count _hits > 0) then {
        private _hitInfo = _hits select 0;
        private _hitObj  = _hitInfo select 2;
        private _hitPos  = _hitInfo select 0;
        // PROBE TRACE (debug only): what the ray actually found at this point.
        // A vanilla bridge deck appears here as a non-null object; open water and
        // bare terrain report a null object. This is the single line that tells
        // "there is a deck here" from "there is only river here".
        if (missionNamespace getVariable ["FTCS_Debug_Mode", false]) then {
            diag_log format ["[FTCS][SNAP][PROBE] p=%1 hitObj=%2 hitZ=%3 needZ=%4",
                _p,
                (if (isNull _hitObj) then { "<terrain>" } else { typeOf _hitObj }),
                (if (_hitPos isEqualType []) then { round ((_hitPos select 2) * 100) / 100 } else { "?" }),
                round (((_p select 2) - _heightTol) * 100) / 100];
        };
        // Non-terrain object hit at (or near) the requested height -> a structure
        // the unit can stand on. Bridge deck, pier, ramp, platform: all valid,
        // regardless of the water cell underneath.
        if (!isNull _hitObj && { (_hitPos isEqualType []) }) then {
            if ((_hitPos select 2) >= ((_p select 2) - _heightTol)) exitWith { true };
        };
    };

    // Nothing solid above the terrain: apply the height-aware water test.
    private _terrainZ = getTerrainHeightASL [_p select 0, _p select 1];
    private _atWaterLevel = (surfaceIsWater _p) && { ((_p select 2) - _terrainZ) < 1.2 };
    (!_atWaterLevel)
};

// ---------------------------------------------------------------------------
// 0. The requested point itself
// ---------------------------------------------------------------------------
if ([_slotPos] call _fnc_isSupported) exitWith { [_slotPos, true, 0] };

// ---------------------------------------------------------------------------
// 1. Concentric rings: nearest-first, 8 directions per ring
// ---------------------------------------------------------------------------
private _best = _slotPos;
private _bestDist = -1;
private _radius = _step;

while { _radius <= _maxRadius && { _bestDist < 0 } } do {
    private _dirs = [0, 45, 90, 135, 180, 225, 270, 315];
    {
        if (_bestDist < 0) then {
            private _cand2d = [_slotPos select 0, _slotPos select 1, 0] getPos [_radius, _x];
            // Keep the requested height: the deck we are looking for is the one
            // the slot was computed against, not the terrain far below it.
            private _cand3 = [_cand2d select 0, _cand2d select 1, (_slotPos select 2)];
            if ([_cand3] call _fnc_isSupported) then {
                _best = _cand3;
                _bestDist = _slotPos distance2D _cand3;
            };
        };
    } forEach _dirs;
    _radius = _radius + _step;
};

if (_bestDist < 0) exitWith { [_slotPos, false, -1] };
[_best, false, _bestDist]
