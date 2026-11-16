/*
    ================================================================================
    File: fn_trailTrimToArc.sqf
    Module: Roads
    Author: FTCS Team
    Description: Sole owner of the TRAIL TRIM: drops the fully-consumed HEAD of the
                 recorded trail (indexes 0..N-1) so a long march does not grow the
                 array without bound. Called by the recorder thread once per tick,
                 right BEFORE recording the leader's next point.

                 ============================ WHY IT EXISTS ==========================
                 The first trim cut at a fixed depth behind the leader:

                     trimLimit = headDist - maxTrailOffset - 200

                 `maxTrailOffset` is the DEEPEST doctrinal offset of the column, and
                 it is seeded ONCE by fn_trailColumnSet. With a real column of
                 ~217 m and a 200 m cushion, the cut landed INSIDE the column: the
                 RPT showed a trim almost every second, 2-3 m each time

                     12:48:27  Trim: dropped 1 tail points (2.84m), path now 120 pts
                     12:48:35  Trim: dropped 1 tail points (2.25m), path now 119 pts

                 while the rear groups still held offsets 189/200/217. Worse, every
                 trim RENUMBERS every persisted index, so the whole column was being
                 renumbered continuously - and a trim that runs out of path (the cut
                 reaches the newest point) also forces `headDist` back, which is the
                 feedback loop that made the column drift backwards.

                 The cushion must be measured from the DEEPEST GROUND THE COLUMN
                 ACTUALLY OCCUPIES, not from a doctrinal number that no longer
                 matches the layout (compact rewrites the offsets; casualties and
                 re-orders change them too).

                 ============================ THE RULE ==============================
                     trimLimit = tailArc - cushion

                 `tailArc` is the ARCLENGTH of the oldest point still occupied by the
                 column, published by fn_formationsTrailQueueSync into the anchor as
                 "trailMinSeatArc" (an ABSOLUTE arclength, so it survives a trim: the
                 queue re-derives it every tick from headDist - offset, which drops by
                 exactly the trimmed length). `-1` means "the queue has not spoken yet"
                 and the trim holds.

                 THE DISCRETE MINIMUM: nothing is dropped until the trim would remove
                 at least `_minDropPts` (20) entries. Small, frequent trims renumber the
                 whole registry for a few metres of memory, which is exactly the
                 fragility this file exists to remove; batching turns a per-tick
                 renumber into one event per ~40 m of march.

                 ===================== THE COLUMN-DEPTH GUARD ======================
                 The cut can never reach inside the column's OWN depth. The guardian
                 value is read from the REGISTRY by this function (deepest
                 `trailOffsetDist` of the platoon, seated OR still waiting), never
                 taken from the values the queue publishes: the queue runs AFTER this
                 function in the same tick, so those describe the previous state. Rely
                 on them and the trim settles into a limit cycle with the recorder -
                 20 points out, one point in - that caps the path below the deepest
                 group and starves the tail forever (Lesson 32).

                 The cushion is ALSO a hard floor on the path length: the trim never
                 leaves fewer than `_minKeptPts`, so the follower always has the
                 trail points it is walking on, and `headDist` can never be pushed back
                 by its own trim.

     Params:
         0: OBJECT  - Platoon leader unit (unused for geometry; keeps the recorder
                      call signature uniform and is available for future telemetry).
         1: HASHMAP - Trail anchor, mutated in-place: trailPath, headDist,
                      trailMinSeatArc, trailTailArc, trailMaxOffset, trimEvents.
                      The caller MUST re-read trailPath and headDist afterwards.
     Returns:
         NUMBER - Number of trail points dropped (0 when nothing was trimmed).
     Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params [["_leader", objNull], ["_anchor", locationNull]];

if (isNull _leader || { _anchor isEqualTo locationNull }) exitWith { 0 };

private _path = _anchor getOrDefault ["trailPath", []];
private _count = count _path;
if (_count < 3) exitWith { 0 };

private _headDist = _anchor getOrDefault ["headDist", 0];
if (!(_headDist isEqualType 0) || { _headDist < 0 }) then { _headDist = 0; };

// Trailing cushion kept BEHIND the oldest point the column still needs, in metres.
// 150 m (75 recorded points): enough for a lagging group plus one bridge segment,
// and wide enough that the column-depth guard always wins by a comfortable margin -
// the cushion is the LAG allowance behind the rear group, never a depth estimate.
private _cushion     = _anchor getOrDefault ["trimCushion", 150.0];
// Batch size: no trim at all below this many dropped points (see header). 20 points
// (~40 m of march) instead of 10: at 10 the trim could fire every ~10 s and the
// registry was still renumbered often enough to keep the column's indexes churning.
private _minDropPts  = 20;
// Hard floor on the resulting path: fewer kept points than this aborts the trim.
private _minKeptPts  = 3;

// Oldest point still occupied by the column (absolute arclength, published by the
// queue). -1 = the queue has not spoken, so no trim this tick: cutting against an
// unknown tail is exactly how the old rule cut inside the column.
private _tailArc = _anchor getOrDefault ["trailMinSeatArc", -1];
if (!(_tailArc isEqualType 0) || { _tailArc < 0 }) exitWith { 0 };

// HARD GUARANTEE: never trim inside the column's own depth.
//
// The published values cannot be trusted for this: `trailMinSeatArc` /
// `trailMaxOffset` are written by fn_formationsTrailQueueSync, which runs AFTER
// this function in the same tick, so on the tick that matters they still describe
// the PREVIOUS column state (or do not exist at all). The trim therefore reads the
// registry ITSELF and protects the DEEPEST trail offset of this platoon, seated or
// still waiting. Without this the recorder and the trim sat in a stable equilibrium
// (10 points out, 10 points in, every ~10 s) that capped the path at ~95 points:
// any group deeper than that never got a seat (RPT 14:37, off=189/200/217 holding
// at `max=94` forever).
private _pltId = missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1];
private _deepestOff = 0;
{
    private _e = _y;
    if (_e isEqualType createHashMap
        && { ((_e getOrDefault ["platoonId", -1]) == _pltId) }
        && { ((_e getOrDefault ["movingMode", ""])) == "FOLLOWING_TRAIL" }) then {
        private _o = _e getOrDefault ["trailOffsetDist", 0];
        if ((_o isEqualType 0) && { _o > _deepestOff }) then { _deepestOff = _o; };
    };
} forEach (missionNamespace getVariable ["FTCS_Groups_Registry_Table", createHashMap]);

// Floor the cut with the column's own rear point, and ALSO with the published
// column floor in case the registry has already lost a group it was placed for.
// A HIGHER arc means LESS is dropped, so the guard takes the MAXIMUM of the two
// candidate floors: whichever keeps more trail wins.
private _guardArc = if (_deepestOff > 0) then { (_headDist - _deepestOff) max 0 } else { 0 };
private _protectOff = _anchor getOrDefault ["trailMaxOffset", 0];
if ((_protectOff isEqualType 0) && { _protectOff > 0 }) then {
    _guardArc = _guardArc max ((_headDist - _protectOff) max 0);
};
// A column that exists must always keep at least its own depth: if neither floor
// could be derived (no group, no published value), do not trim at all this tick.
if (_guardArc <= 0 && { _deepestOff <= 0 }) exitWith { 0 };
if (_guardArc > _tailArc) then { _tailArc = _guardArc; };

private _trimLimit = _tailArc - _cushion;
if (_trimLimit <= 0) exitWith { 0 };

// Walk the polyline once, measuring the real arc to each point, and find how many
// whole points fall strictly BEFORE the limit. The first point at or beyond the
// limit is the new index 0: it anchors the rear slot's position.
private _accum = 0;
private _dropCount = 0;
for "_i" from 0 to (_count - 2) do {
    private _segLen = ((_path select _i) select 0) distance2D ((_path select (_i + 1)) select 0);
    if (_segLen <= 0) then { _segLen = 0.01; };
    if (_accum >= _trimLimit) exitWith {};
    _accum = _accum + _segLen;
    _dropCount = _dropCount + 1;
};

// Batch and floor guards (see header): a handful of points is not worth a renumber
// of the whole registry, and the follower must keep a walkable path.
if (_dropCount < _minDropPts || { (_count - _dropCount) < _minKeptPts }) exitWith { 0 };

private _kept = [];
for "_i" from _dropCount to (_count - 1) do {
    _kept pushBack (_path select _i);
};

// The trimmed length is what the shift of every arclength must compensate.
private _droppedLen = 0;
for "_i" from 0 to (_dropCount - 1) do {
    _droppedLen = _droppedLen + (((_path select _i) select 0) distance2D ((_path select (_i + 1)) select 0));
};

_anchor set ["trailPath", _kept];
_anchor set ["headDist", (_headDist - _droppedLen) max 0];

// SHIFT THE PUBLISHED ARCLENGTHS. They are absolute arcs into the SAME polyline,
// so dropping `_droppedLen` metres from the front moves them by the same amount
// and they keep addressing the same world points. `-1` sentinels stay `-1`.
{
    private _key = _x;
    private _val = _anchor getOrDefault [_key, -1];
    if ((_val isEqualType 0) && { _val >= 0 }) then {
        _anchor set [_key, (_val - _droppedLen) max 0];
    };
} forEach ["trailMinSeatArc", "trailTailArc"];

// RENUMBER THE PERSISTED INDEXES.
//
// Dropping `_dropCount` points from the FRONT shifts EVERY index, so any index a
// follower stored in the registry now addresses different ground. The observable
// damage was groups reaching their slot and then receiving a slot 8 positions
// further BACK (RPT: 'max 94 -> 93 -> ... -> 86' in eight consecutive ticks while
// the leader stood still), i.e. the whole column turned around. Two fields are
// shifted here:
//
//     trailLaneTargetIdx - the point a group is currently walking to
//     trailCursorIdx     - kept for compatibility although nothing reads it
//
// `trailQueueIndex` is NOT shifted: it is republished from scratch by
// fn_formationsTrailQueueSync on the very next tick, from the arc-derived seat.
private _registry = missionNamespace getVariable ["FTCS_Groups_Registry_Table", createHashMap];
if (!isNil "_registry") then {
    {
        private _entry = _y;
        if (_entry isEqualType createHashMap) then {
            {
                private _idx = _entry getOrDefault [_x, -1];
                if (_idx isEqualType 0 && { _idx >= 0 }) then {
                    _entry set [_x, (_idx - _dropCount) max 0];
                };
            } forEach ["trailCursorIdx", "trailLaneTargetIdx"];
        };
    } forEach _registry;
};

_anchor set ["trimEvents", (_anchor getOrDefault ["trimEvents", 0]) + 1];

diag_log format ["[FTCS][TRAIL] Trim: dropped %1 head points (%2m), path now %3 pts (indexes shifted).",
    _dropCount, (round (_droppedLen * 10) / 10), count _kept];

_dropCount
