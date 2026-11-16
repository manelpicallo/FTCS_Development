/*
    ================================================================================
    File: fn_trailIndexAtArc.sqf
    Module: Roads
    Author: FTCS Team
    Description: Converts an ARC LENGTH along the recorded trail into the ARRAY
                 INDEX of the recorded point that best represents it.

                 ============================ WHY IT EXISTS ==========================
                 `trailPath` is a list of points the leader really walked, and the
                 distance between consecutive points is only USUALLY `recordStep`
                 (2 m). The recorder appends at most one point per tick, so a single
                 segment can be far longer:

                     trail RESUMED at [3398,5846] dz=0.25
                     LARGE STEP 108.4m at point 55 -> segment spans water/props

                 That is exactly what a bridge crossing looks like: the trail stops
                 at the near bank, the leader walks 108 m over the deck with no
                 recording, and ONE point appears on the far bank.

                 Dividing an offset by `recordStep` assumes every index is 2 m and
                 is therefore WRONG after such a jump: a group 135 m behind ends up
                 with a negative index and waits forever. This function measures the
                 trail as it really is, segment by segment.

                 ============================ THE RULE ==============================
                 Walk the polyline summing the real 2D distance between consecutive
                 points until the accumulated arc reaches the requested value:

                     | requested arc falls ...        | returned index       |
                     |---------------------------------|----------------------|
                     | at or before point 0            | 0                    |
                     | exactly on point i              | i                    |
                     | between points i and i+1        | i or i+1, whichever  |
                     |                                 | is nearer the arc    |
                     | past the last recorded point    | last                 |

                 NEAREST, not "earlier". The points are ~2 m apart, so the nearest one
                 is at most 1 m off the request. Always rounding back lost up to 2 m
                 per group and, applied down the whole column, compressed the file
                 into consecutive indexes: the RPT showed off=1 -> seat 52,
                 off=14 -> 51, off=33 -> 50 ... i.e. 13-19 m of doctrine collapsing
                 into a single 2 m step, the column drawn point on point.

                 The ORDERING guarantee does not belong here: the caller puts a car
                 one index behind whenever its seat would reach the car in front.

                 ==================== WHAT THIS FUNCTION DOES NOT DO ==============
                 It does not interpolate. Every index it returns is a point the
                 leader really stood on, which is the invariant the trail column
                 depends on. (The road column interpolates because its path is a
                 geometric road centreline, not a walked track.)

     Params:
         0: ARRAY   - Recorded trail `[[posATL, tangentDir], ...]` (may be empty).
         1: NUMBER  - Arc length in metres, measured from index 0 (the march start).
     Returns:
         NUMBER - Index into the trail. 0 when the trail is empty, holds a single
                  point, or the requested arc is not positive. Saturates at the last
                  index when the request is beyond the recorded trail.
     Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params [
    ["_trailPath", [], [[]]],
    ["_targetArc", 0, [0]]
];

private _lastIdx = (count _trailPath) - 1;
if (_lastIdx < 0) exitWith { 0 };
if (_lastIdx == 0 || { _targetArc <= 0 }) exitWith { 0 };

// `_arcAtPoint` is the arc length from index 0 to the current point `_j`.
// At each segment the request is tested against BOTH ends and the nearer one wins.
private _arcAtPoint = 0;

for "_j" from 0 to (_lastIdx - 1) do {
    private _posA = (_trailPath select _j) select 0;
    private _posB = (_trailPath select (_j + 1)) select 0;
    private _segLen = _posA distance2D _posB;

    // A zero-length segment contributes no arc; guard against a corrupted entry so
    // an infinite run of identical points can never stall the search.
    if (_segLen <= 0.01) then { _segLen = 0.01; };

    private _arcAtNext = _arcAtPoint + _segLen;

    if (_targetArc < _arcAtNext) exitWith {
        // Inside the segment: closest end wins. `_arcAtPoint` is the arc of point
        // `_j`, `_arcAtNext` the arc of point `_j + 1`.
        if ((_targetArc - _arcAtPoint) <= (_arcAtNext - _targetArc)) then { _j } else { _j + 1 }
    };

    _arcAtPoint = _arcAtNext;
};

// Past the end of the recorded trail: the newest point the leader walked.
_lastIdx