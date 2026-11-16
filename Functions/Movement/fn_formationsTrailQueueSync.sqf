/*
    ================================================================================
    File: fn_formationsTrailQueueSync.sqf
    Module: Movement
    Author: FTCS Team
    Description: Publishes, once per tick, the queue seat index of every group that
                 is waiting behind an obstacle in a trail column (the "train").

                 ============================ THE PROBLEM ============================
                 Arma 3 cannot reliably produce a pathable point ON a bridge deck:
                 units sent there end up swimming under it. FTCS therefore treats a
                 bridge (and any other non-recordable crossing: a gap, a forest
                 clearance, a defile) as a CUT in the walked trail:

                     fn_trailAdvanceAnchor refuses to record while the leader is
                     elevated (fn_navIsValidGround), so `trailPath` simply STOPS
                     GROWING at the near bank and RESUMES on the far bank.

                 That freeze is the barrier itself. `trailPath` contains ONLY points
                 the leader really walked on walkable ground, so an index into it is
                 always a valid destination - and the gap has no index at all.

                 ============================ THE MODEL =============================
                 The trail column is a TRAIN:

                        leader  --- crossing (no recorded points) ---  idx N (far bank)
                        |                                                        |
                     [T1] [T2] [T3] ...            <- waiting at the near bank
                     near bank, seats exist up to `maxIdx`

                 * THE SEAT IS MEASURED FROM THE FRONT, exactly like the road column
                   samples its slot (`sample(headDist - offsetDist)`, see
                   fn_formationsGroupFollowRoad):

                       seat(k) = maxIdx - round( trailOffsetDist(k) / recordStep )

                   The trail grows from the march start (index 0) to the leader
                   (maxIdx), so measuring the offset from index 0 instead - the earlier
                   bug - sent the HEAD of the column to a point the leader had walked
                   tens of metres earlier and mirrored the whole file.
                 * PROGRESSIVE RELEASE (the column forms in cascade behind the leader):
                   a car may only walk to a point that ALREADY EXISTS.

                       can_move(k)  <=>  seat(k) >= 0

                   A car whose seat is still negative (the leader has not walked that
                   depth yet, or the trail was just seeded) is published as "no seat"
                   (-1) and HOLDS where it was placed. It is never dragged to maxIdx:
                   that clamped the whole platoon onto the leader's own track and
                   collapsed it around him (observed in game, twice).
                 * ORDER is guaranteed by the chain: a car may never be released at or
                   beyond the car in front of it (`seat < seat(prev)`). Every car keeps
                   its OWN doctrinal distance, which is what preserves the spacing
                   between a 2-man cell and an 8-man squad, while a waiting car keeps
                   its place in the file and cannot be overtaken.

                   T(k) keeps its DOCTRINAL distance to the car in front, so the
                   amount a car advances is NOT a constant for the column: a 2-man
                   cell in front and an 8-man squad behind advance by different
                   distances, and that is exactly what preserves the spacing. The
                   spacing is never invented - `trailOffsetDist` was fixed by
                   fn_trailColumnSet when the column was ordered.
                 * While the cut is closed (maxIdx does not grow, leader crossing) NO
                   queued group gets a seat: every seat beyond the near bank does not
                   exist yet, so the train holds its ground where it stands and nobody
                   enters the cut.
                 * When the leader walks the far bank, maxIdx jumps past the crossing and
                   the nearest waiting car is released to the first point that reaches
                   IT; the cars behind are chained from it in ONE pass, front to back,
                   keeping their doctrinal gaps. `prev` moves only when a seat is really
                   published, so the train advances as a block and never overtakes.
                 * A group released that way is population A again on the next tick
                   (its natural index now exists): the queue drops it by itself, no
                   state has to be cleared by hand.

                 ★ ONLY THE INDEX IS PUBLISHED. ★ The physical walk never crosses the
                 cut here: the follower sends the group to `trailPath[seat]`, which is a
                 point on walkable ground; the engine decides how to get from the near
                 bank to the far bank (the bridge has its own path). No point is ever
                 generated between the two banks - that is what this whole pass exists
                 to guarantee.

                 ================== LAYER 3: ORCHESTRATION ==================
                 Reads registry fields and writes the queue fields per group.
                 No engine commands, so the port to Enforce Script is a rewrite of
                 the registry accessors only.

     REGISTRY FIELDS
         READ  : platoonId, movingMode, trailOffsetDist
         WRITE : trailQueueIndex   - the index this WAITING group must walk to
                                   (only written for groups in queue)
                 trailQueueHasSeat - true = the index exists in `trailPath` and the
                                   group may move this tick; false = hold ground
                 trailQueueTipIdx  - maxIdx of this tick (global cap of the column)

                 "trailSlotIndex" is deliberately NOT written here: it is the natural
                 seat consumed by groups that are already across (population A), and a
                 second writer would make one field mean two things (the single-writer
                 rule that fixed the scrambled order at the bridge).

     ANCHOR FIELDS
         WRITE : trailMinSeatArc  - ARCLENGTH of the oldest point the column still
                                    occupies (headDist - deepest offset actually
                                    released). -1 = nothing to report, the trim holds.
         WRITE : trailTailArc     - the deepest offset seen this tick (telemetry and
                                    the trim's zero-guard).
                  This pass is the ONLY place where the whole column (offset +
                  released seat) is known at once, which is why the TRIM's floor is
                  published from here and not from the recorder
                  (fn_trailTrimToArc reads "trailMinSeatArc"). It is an ABSOLUTE
                  arclength, shifted by the trim itself, so it survives a trim and
                  keeps addressing the same ground on the next tick.

     SENTINELS
         trailQueueHasSeat = false  -> this group must HOLD GROUND this tick
         trailQueueIndex   = -1     -> "no valid seat yet" (a column that started on
                                       the obstacle itself). Never nil: the registry
                                       setter DELETES the key on nil and the reader
                                       would then return the previous tick's value.

     Params:
         0: NUMBER - Platoon ID (default: player platoon).
     Returns:
         NUMBER - Number of groups that hold a valid queue seat this tick.
     Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params [["_pltId", -1, [-1]]];

if (_pltId < 0) then { _pltId = missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1]; };

private _registry = missionNamespace getVariable ["FTCS_Groups_Registry_Table", createHashMap];

// --- 1. Read the RECORDED trail from the anchor --------------------------------
// The trail lives in the platoon anchor (`FTCS_Trail_Anchor_PLT_<id> > "trailPath"`),
// the same array fn_formationsGroupFollowTrail samples. There is no global
// "FTCS_Trail_Path" variable: reading one left `maxIdx` at -1 and the whole queue
// answered "no seat" forever.
private _anchor = missionNamespace getVariable [format ["FTCS_Trail_Anchor_PLT_%1", _pltId], createHashMap];
private _trailPath = _anchor getOrDefault ["trailPath", []];
private _maxIdx = (count _trailPath) - 1;

// Arc length of the leader along the recorded trail, in REAL metres. This is the
// only measure that survives a jump in the trail (a bridge crossing adds ONE point
// that can span 100 m), and it is what the road column uses (`headDist`).
private _headDist = _anchor getOrDefault ["headDist", 0];
if (!(_headDist isEqualType 0) || { _headDist < 0 }) then { _headDist = 0; };

// Distance between two recorded points. Needed ONLY to convert the doctrinal METRE
// gap between two teams into a minimum INDEX separation, so two groups can never be
// published the same seat. Read from the anchor so this file cannot disagree with
// the recorder that produced the array.
private _recordStep = _anchor getOrDefault ["recordStep", 2.0];
if (!(_recordStep isEqualType 0) || { _recordStep <= 0 }) then { _recordStep = 2.0; };

// --- 2. Collect the column ordered FRONT TO BACK by trail offset ---------------
// The order MUST be `trailOffsetDist`, the value fn_trailColumnSet assigned when the
// column was ordered (footprint + inter-squad gap). "allocationSlot" is NOT usable:
// it belongs to the platoon formation, is rewritten by the road column and by the
// scout detachment, and does not follow the trail order (Compact changes the offsets
// without touching the slots). A wrong order here makes car N reserve ahead of car
// N-1 and two groups end up on the same point.
private _entries = [];
{
    private _entry = _y;
    if (((_entry getOrDefault ["platoonId", -1]) == _pltId)
        && { ((_entry getOrDefault ["movingMode", ""])) == "FOLLOWING_TRAIL" }) then {
        private _off = _entry getOrDefault ["trailOffsetDist", -1];
        if (_off isEqualType 0 && { _off > 0 }) then {
            // SEAT INDEX resolved BY ARC, exactly like the road column
            // (`sample(headDist - offsetDist)`, fn_formationsGroupFollowRoad:147).
            //
            // Dividing the offset by `recordStep` assumes every index spans 2 m. That
            // is NOT true: the recorder appends one point per tick, so a bridge crossing
            // produces a single segment of ~100 m (RPT: "LARGE STEP 108.4m at point
            // 55"). After such a jump the index arithmetic lags whole dozens of points
            // behind reality and the deep half of the column can never get a seat.
            //
            // Measuring the arc and translating it into an index keeps working with any
            // segment length: `arc -1` = not reached yet (HOLD), `>= 0` = a point the
            // leader really walked.
            private _natural = -1;
            if (_headDist >= _off) then {
                _natural = [_trailPath, _headDist - _off] call FTCS_fnc_trailIndexAtArc;
            };
            _entries pushBack [_x, _off, _natural];
        };
    };
} forEach _registry;

if (count _entries == 0) exitWith { 0 };

// Stable ascending insertion sort (the column is a dozen cars at most). Ascending
// because position 0 is the group nearest the platoon leader.
private _sorted = +_entries;
private _n = count _sorted;
for "_i" from 1 to (_n - 1) do {
    private _cur = _sorted select _i;
    private _j = _i - 1;
    while { _j >= 0 && { ((_sorted select _j) select 1) > (_cur select 1) } } do {
        _sorted set [(_j + 1), (_sorted select _j)];
        _j = _j - 1;
    };
    _sorted set [(_j + 1), _cur];
};

// --- 3. Walk FRONT TO BACK and resolve the seat of every car --------------------
// The seat is an ABSOLUTE index into `trailPath`, measured from the front:
//
//     seat(k) = maxIdx - round( offset(k) / recordStep )
//
// which is the index form of the road rule `sample(headDist - offsetDist)`. The
// list is sorted by offset ASCENDING, i.e. front of the file first, so the head of
// the column is the group whose seat is closest to maxIdx.
//
// A car is RELEASED when its own seat is a recorded point (seat >= 0). While the
// leader has not walked that depth the seat is negative: the group HOLDS its ground
// where it was placed. This is the progressive release that makes the column form
// in cascade behind the leader instead of collapsing onto his track.
//
// The chain is not a copy of the neighbour's seat: each car is placed at ITS OWN
// doctrinal distance from the leader, which is exactly what keeps the spacing (a
// large squad and a 2-man cell both keep the distance they were given). What the
// chain guarantees is ORDER: a car can never be released beyond the car in front of
// it, so the file can never be overtaken.
//
// `_frontIdx` carries the CEILING actually published to the previous car, `_frontDist`
// its offset in metres. `-1` means "no car processed yet".
private _published = 0;
private _frontIdx = -1;
private _frontDist = -1;
// TRIM FLOOR: deepest offset that actually holds a seat this tick. The column's
// oldest occupied point is at arc (headDist - _deepestSeatedOff). Read by
// fn_trailTrimToArc; -1 when no group of this platoon is seated yet.
private _deepestSeatedOff = -1;
// TRIM FLOOR (protection floor): deepest offset of the column THAT IS STILL
// WAITING. A group without a seat needs trail that does not exist yet, so the trim
// must never drop it: the follower releases it the moment its depth is walked. Cut
// against the seated offset alone and the trim ate exactly the metres the waiting
// tail was about to walk (RPT 14:26-14:27: path trimmed to 83-99 points ~170-200 m
// while the column needs 217 m, so Mortars/Guide held for 32 MINUTES).
// `_frontDist` is updated for EVERY car, seated or not (see the chain note below).
private _deepestAnyOff = -1;
// Number of cars already walked by the chain. This - NOT the value of `_frontIdx` -
// decides whether a car has a predecessor, because `-1` is also a legal seat
// ("this car is holding"). 0 = first car of the column.
private _carsDone = 0;

{
    private _grpId = _x select 0;
    private _off = _x select 1;
    private _natural = _x select 2;

    // `_natural` is ALREADY the seat resolved by arc for this car's own offset
    // (`trailIndexAtArc(trail, headDist - offset)`), so it carries the full doctrinal
    // spacing. The chain must only ENFORCE ORDER, never re-space the column:
    // forcing `frontIdx - 1` collapsed every car onto consecutive points (1 index =
    // 2 m apart) and destroyed the 13-19 m doctrinal gaps. Verified in the RPT:
    //
    //     off=1 -> seat=52 / off=14 -> 51 / off=33 -> 50 / off=46 -> 49 ...
    //
    // ORDER **AND** SPACING - two different caps, both needed:
    //
    //   a) ORDER: the car behind may never reach beyond the ceiling of the car in
    //      front. If that car is stuck, the follower stops behind it instead of
    //      overtaking. (Verified wrong without it: "no se intentaron adelantar".)
    //
    //   b) SPACING: the seat must also stay at least ONE recorded point BEHIND the
    //      car in front. Only (a) was applied at first, and the RPT showed the car
    //      behind arriving "justo detrás del otro", i.e. sharing its point and losing
    //      the gap. One index = ~2 m, which is the minimum separation two groups can
    //      hold without standing on each other. This is NOT the old re-spacing bug:
    //      the doctrinal seat is untouched and only the LAST index is reserved.
    private _seat = _natural;

    // THE CHAIN MUST APPLY EVEN WHEN THE CAR IN FRONT IS HOLDING.
    //
    // `_frontIdx` is a SEAT INDEX, and -1 is a legal value (the car in front could
    // not be placed). Testing `_frontIdx >= 0` therefore SKIPPED the whole cap for
    // the car behind a holding car, which then walked to its own natural seat - right
    // past the whole queue. Verified in the RPT:
    //
    //     '2nd Rifle Squad - Team A' off=78 cap=1  -> HOLDS
    //     '2nd Rifle Squad - Team B' off=86 cap=-1 -> SEAT 34   <- overtook everyone
    //
    // The chain is driven by the CARS PROCESSED counter, not by the seat value: the
    // first car of the column has no predecessor, every other car does.
    if (_carsDone > 0) then {
        // SPACING (doctrine): stay at least this car's OWN doctrinal gap behind the
        // car in front, in METRES converted to indexes. That distance is exactly
        // `trailOffsetDist(mine) - trailOffsetDist(front)`, which already contains the
        // front group's footprint + 5 m margin (fn_trailColumnSet).
        private _gapIdx = ceil ((_off - _frontDist) / _recordStep);
        if (_gapIdx < 1) then { _gapIdx = 1; };

        // The ceiling the car in front really published. A car holding at -1 caps
        // everything behind it at -1: the whole tail waits with it.
        private _frontSeat = _frontIdx;

        // ORDER: never beyond the car in front (nobody overtakes).
        if (_frontSeat < 0) then { _frontSeat = -1; };
        if (_seat > _frontSeat) then { _seat = _frontSeat; };

        // SPACING: never closer than this car's doctrinal gap.
        private _maxSeat = _frontSeat - _gapIdx;
        if (_seat > _maxSeat) then { _seat = _maxSeat; };

        // COMPRESSED FILE: SPACING MUST YIELD TO ORDER (Lesson 33).
        //
        // While the column is bunched against the trail tip, `frontSeat - gap` can
        // be NEGATIVE even though BOTH cars are legitimately in the file: the car in
        // front only has a few indexes left, and this car's doctrinal gap is wider
        // than that. Demanding the full gap then drops the car out of the column -
        // and a car that is out of the column never gets another chance until the
        // leader walks again. Verified in the RPT:
        //
        //     'Mortar Section'          off=200 seat=2   (max=106) -> SEAT
        //     'HQ (Guide & Security)'   off=217 seat=106 (cap=2)   -> HOLDS
        //                                                 ^ 2 - ceil(17/2)=9 -> -7
        //
        // The answer is the MINIMUM ORDER (one index behind the car in front), not
        // "hold forever": the group enters the file immediately and recovers its
        // doctrinal gap by itself as soon as the trail grows past it. Losing a group
        // is always worse than a temporarily short gap.
        if (_seat < 0 && { _frontSeat >= 1 }) then {
            _seat = _frontSeat - 1;
            if (missionNamespace getVariable ["FTCS_Debug_Mode", false]) then {
                diag_log format ["[FTCS][TRAIL][QUEUE] '%1' off=%2 compressed (cap=%3 gap=%4) -> MIN ORDER seat=%5",
                    _grpId, _off, _frontSeat, _gapIdx, _seat];
            };
        };

        if (_seat < 0) then { _seat = -1; };
    };

    // Nothing recorded yet (trail just seeded) or the leader has not walked this
    // depth: HOLD. -1, never nil (nil DELETES the key through the registry setter
    // and the reader would return the previous tick's seat), and never a removed
    // key: the follower only accepts >= 0, so the value is unambiguous.
    if (_seat < 0) then {
        [_grpId, "trailQueueHasSeat", false] call FTCS_fnc_registrySet;
        [_grpId, "trailQueueIndex", -1] call FTCS_fnc_registrySet;
        if (missionNamespace getVariable ["FTCS_Debug_Mode", false]) then {
            diag_log format ["[FTCS][TRAIL][QUEUE] '%1' off=%2 seat=%3 (cap=%4) -> HOLDS",
                _grpId, _off, _natural, _frontIdx];
        };
    } else {
        [_grpId, "trailQueueIndex", _seat] call FTCS_fnc_registrySet;
        [_grpId, "trailQueueHasSeat", true] call FTCS_fnc_registrySet;
        _published = _published + 1;
        if (_off > _deepestSeatedOff) then { _deepestSeatedOff = _off; };
        if (missionNamespace getVariable ["FTCS_Debug_Mode", false]) then {
            diag_log format ["[FTCS][TRAIL][QUEUE] '%1' off=%2 seat=%3 (max=%4) -> SEAT",
                _grpId, _off, _seat, _maxIdx];
        };
    };

    // THE CHAIN ADVANCES ON EVERY CAR, INCLUDING THE ONES THAT HOLD.
    //
    // Updating `_frontIdx`/`_frontDist` only in the SEAT branch broke the chain as
    // soon as ONE car could not be placed: the next cars compared themselves against
    // a car TWO positions ahead, their `_gapIdx` came out smaller than the real
    // doctrine and several of them were published the SAME seat. Verified in the
    // RPT:
    //
    //     'HQ (Support Element)'      off=53 -> seat=23
    //     '2nd BAR Support Team'      off=64 -> seat=23     <- same point
    //     'HQ (Command Element)'      off=1  -> seat=23     <- same point
    //
    // A waiting car is still the car in front of the one behind it, so it MUST be
    // recorded here even when it publishes no seat of its own. Its cap carries the
    // "nobody overtakes" rule forward.
    _frontIdx = _seat;
    _frontDist = _off;
    _carsDone = _carsDone + 1;
    if (_off > _deepestAnyOff) then { _deepestAnyOff = _off; };

    // Global cap of the column, published for the follower loop.
    [_grpId, "trailQueueTipIdx", _maxIdx] call FTCS_fnc_registrySet;
} forEach _sorted;

// --- 4. Publish the TRIM FLOOR into the anchor --------------------------------
// `headDist - offset` is the arclength of the OLDEST point the column occupies, in
// the SAME absolute frame the trim uses (headDist is shifted by exactly the trimmed
// length, and so is this value).
//   - no car seated -> -1: the trim HOLDS, because nothing proves which points are
//     still needed (a column that has just started has no tail to drop).
//   - the deepest offset whose seat is clamped at the column ceiling (bridge held
//     open) would place the floor BEYOND the recorded trail; the trim's cushion
//     absorbs it, and "_tailArc > headDist" is clamped to headDist here anyway.
// The floor is the DEEPER of the two: a waiting group protects its own depth just
// like a seated one (it is the very next car to be released), so the trim never
// cuts ground that is about to be walked.
private _protectOff = (_deepestSeatedOff max _deepestAnyOff);
private _tailArc = -1;
if (_protectOff >= 0) then {
    _tailArc = (_headDist - _protectOff) min _headDist;
    if (_tailArc < 0) then { _tailArc = 0; };
};
_anchor set ["trailMinSeatArc", _tailArc];
_anchor set ["trailTailArc", _deepestSeatedOff];
_anchor set ["trailMaxOffset", _protectOff];

if (missionNamespace getVariable ["FTCS_Debug_Mode", false]
    && { missionNamespace getVariable ["FTCS_Debug_Trace", false] }) then {
    diag_log format ["[FTCS][TRAIL][QUEUE] plt %1: maxIdx=%2 cars=%3 seated=%4 tailArc=%5",
        _pltId, _maxIdx, count _sorted, _published, _tailArc];
};

_published
