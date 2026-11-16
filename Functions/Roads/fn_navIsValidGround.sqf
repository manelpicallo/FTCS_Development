/*
    ================================================================================
    File: fn_navIsValidGround.sqf
    Module: Roads
    Author: FTCS Team
    Description: Engine adapter (LAYER 2) - "may a unit be SENT TO this point?".

                 This is the SINGLE place where FTCS asks the world whether a
                 position is a usable ground destination. Everything above it (trail
                 recording, march slots, future clearances) is pure logic and never
                 knows how the answer is produced.

                 ============================ THE RULE ============================
                 A point is a VALID DESTINATION when it is NOT ELEVATED over the
                 terrain cell it stands on:

                     dz = z - getTerrainHeightASL(x, y)
                     valid  <=>  dz <= elevationTolerance      (default 0.5 m)

                 That is the whole test. It is deliberately ONE measurement.

                 ==================== WHY NOTHING ELSE IS USED ====================
                 Measured in-game on Prokhorovka 1943 (RPT evidence):

                 | situation                | dz          | verdict |
                 |--------------------------|-------------|---------|
                 | open ground / shore      | -1.00..-0.05| VALID   |
                 | shallow river (ford)     | ~0          | VALID   |
                 | bridge ramp              | +1.84       | REFUSED |
                 | bridge deck, low         | +3.32       | REFUSED |
                 | bridge deck, centre      | +21.6       | REFUSED |

                 Rejected alternatives, each tested and discarded:

                 - `surfaceType`: identical on land and on a bridge deck (it reports
                   the terrain texture under the structure), so it cannot discriminate.
                 - `surfaceIsWater`: TRUE on a bridge deck too (samples the cell
                   below), so it would reject every shoreline as well.
                 - `nearRoads`: returns nothing for these vanilla bridges - they are
                   map geometry, not CfgRoads entries.
                 - `nearestTerrainObjects ["BRIDGE"]`: also returns nothing.
                 - A downward RAY (`lineIntersectsSurfaces`): it hits grass, rocks,
                   posts and other terrain objects near the shoreline, producing
                   intermittent false rejections ("structure" on flat ground) and,
                   because it is evaluated per tick, markers appeared and vanished.
                   It added noise without adding information. Removed.

                 Water is deliberately NOT rejected: a trail must be able to follow a
                 river where units can wade, and the engine itself decides whether a
                 unit walks or swims. Elevation is the only disqualifier.

                 ENFUSION PORT (ArmA 4 / Reforger)
                 The body reduces to one surface-height comparison:
                     return (pos.Y - world.GetSurfaceHeight(pos)) <= tolerance;
                 No caller changes.

     Params:
         0: ARRAY   - Position to test [x, y, z].
         1: NUMBER  - OPTIONAL elevation tolerance in metres (default 0.5). A point
                      standing higher than this above the terrain cell is refused.
         2: BOOLEAN - OPTIONAL reserved flag (unused, kept for call-site
                      compatibility). Water is never rejected on its own.
     Returns:
         BOOLEAN - true when the point is a usable ground destination.
     Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params [
    ["_pos", [0, 0, 0], [[]]],
    ["_elevationTol", 0.5, [0]],
    ["_waterIsInvalid", true, [true]]
];

if (count _pos < 3) exitWith { false };

// Elevation over the terrain cell. Terrain height includes the water surface, so a
// bridge deck sits tens of metres above the value below it.
private _terrainZ = getTerrainHeightASL [_pos select 0, _pos select 1];
private _dz = (_pos select 2) - _terrainZ;
private _isValid = (_dz <= _elevationTol);

// VERDICT TRACE (debug only): one line per point with the numbers that decide it.
if (missionNamespace getVariable ["FTCS_Debug_Mode", false]) then {
    diag_log format ["[FTCS][NAV] p=%1 z=%2 terrainZ=%3 dz=%4 -> %5",
        _pos,
        (round ((_pos select 2) * 100) / 100),
        (round (_terrainZ * 100) / 100),
        (round (_dz * 100) / 100),
        (if (_isValid) then { "VALID" } else { "REFUSED (elevated)" })];
};

_isValid
