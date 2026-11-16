/*
    ================================================================================
    File: fn_formationsGroupFollowTrail.sqf
    Module: Formations
    Author: FTCS Team
    Description: Per-group navigation loop for TRAIL_COLUMN march (mirror of
                 fn_formationsGroupFollowRoad with identical AI discipline):
                 - Marching (leader speed > 2 km/h): group matches the leader's
                   pace exactly (limitSpeed _spd), no slot-chasing acceleration.
                 - Stopped: groups close into their assigned trail slot, then
                   hold and align once to the local trail tangent.
                 - Slot sampling: sample(trailPath, headDist - trailOffsetDist),
                   i.e. the exact point the leader (and the group ahead) walked.
                 - Thread exits when a newer trail order invalidates the
                   generation, or movingMode leaves FOLLOWING_TRAIL.
                 AI profile is set by the dispatcher (ROAD_MARCH aware-mode,
                 NORMAL speed, FIRE_IF_FIRED_UPON, FOLLOW_COMMANDER_STANCE).
    Params:
        0: GROUP - Subordinate group to navigate along the leader trail.
        1: OBJECT - Reference leader (Platoon Commander).
    Compatibility: Arma 3 (SQF) | Designed for Enforce Script (Arma 4) port.
    ================================================================================
*/

params ["_group", "_leader"];

if (isNull _group || isNull _leader) exitWith {};

private _threadID = round (time * 1000) + floor (random 1000);
_group setVariable ["FTCS_TrailThread_ID", _threadID];

private _groupID = groupId _group;
private _pltIdFor = missionNamespace getVariable ["FTCS_Player_Platoon_ID", 1];
// 0.35 s: the lane re-issues `move` to a point a few steps AHEAD, so the loop can
// keep up with the group's real progress. A 1 s tick meant a soldier walked ~1.4 m
// between updates, which is why the column looked like it started and stopped
// every 2 m - the target had already been reached (or was never reached) when the
// next order arrived.
private _tickTime = 0.35;
private _lastTargetPos = [0, 0, 0];
private _alignedOnStop = false;
private _facingAppliedOnReady = false;

// Sampler: interpolate along the trail polyline at a given arclength
private _fnc_sampleTrail = {
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
            private _interpPos = [
                (_ptA select 0) + ((_ptB select 0) - (_ptA select 0)) * _frac,
                (_ptA select 1) + ((_ptB select 1) - (_ptA select 1)) * _frac,
                (_ptA select 2) + ((_ptB select 2) - (_ptA select 2)) * _frac
            ];
            _foundPt = [_interpPos, _dir];
        };
        _accum = _accum + _d;
    };
    _foundPt
};

// =============================================================================
// UN-FREEZE THE SQUAD.
//
// The platoon is parked in the assembly area with its AI movement disabled so the
// deployment can be inspected. Every march world must WAKE the units when it takes
// over, otherwise `move`/`doFollow` issued by this loop are silently ignored and the
// group stays behind while the leader walks away - the "lost stragglers" symptom.
// This was missing here (cross-country and road march already did it).
//
// Rule 15: the native AI commands live in ONE standardised function, shared with
// cross-country, road march and the command dispatcher.
// =============================================================================
[_group, (leader _group), true] call FTCS_fnc_groupAwakenForMarch;

// Trail march also silences the radio protocol and restores the engine speed cap,
// matching the disciplined march profile used by road march.
{
    _x disableAI "RADIOPROTOCOL";
    _x forceSpeed -1;
} forEach (units _group);

// No initial move: until the recorded trail covers this group's depth
// (headDist >= offset), the group stands STATIC at its current position and
// is released progressively as the leader walks (column forms on the move).

[ _groupID, "movingMode", "FOLLOWING_TRAIL" ] call FTCS_fnc_registrySet;

while { ((_group getVariable ["FTCS_TrailThread_ID", -1]) == _threadID) &&
        (([ _groupID, "movingMode" ] call FTCS_fnc_registryGet) == "FOLLOWING_TRAIL") } do
{
    private _spd = speed _leader;
    if ((_group getVariable ["FTCS_TrailThread_ID", -1]) != _threadID) exitWith {};

    private _anchor = missionNamespace getVariable [format ["FTCS_Trail_Anchor_PLT_%1", _pltIdFor], createHashMap];
    private _trailPath = _anchor getOrDefault ["trailPath", []];
    private _headDist = _anchor getOrDefault ["headDist", 0];
    private _offsetDist = [_groupID, "trailOffsetDist"] call FTCS_fnc_registryGet;
    if (isNil "_offsetDist") then { _offsetDist = 12.0; };

    // WAITING state: the recorded trail does not yet cover this group's depth.
    // Hold static (no move, no limitSpeed) until the leader has walked enough;
    // groups release in chain order (nearest offset first) as the trail grows.
    //
    // A group the queue has given a seat is EXEMPT: that seat is an index that
    // already exists in the recorded trail, so it can be walked even while
    // `headDist` says otherwise (during a crossing the trail stops growing on
    // purpose while the leader is on the deck).
    // A group WITHOUT a seat is not exempt: its depth has not been walked yet, and
    // holding where it was placed is the correct answer (see the HOLD block below).
    // Same trap as further down: the getter returns NIL when the queue has not
    // published yet (first tick), and a `private X = <nil>` leaves X undefined.
    private _queueFlagEarly = [_groupID, "trailQueueHasSeat"] call FTCS_fnc_registryGet;
    if (isNil "_queueFlagEarly") then { _queueFlagEarly = false; };
    private _inQueueEarly = ((_queueFlagEarly isEqualType true) && { _queueFlagEarly });

    // RELEASE CRITERION: does this group OWN a recorded point yet?
    //
    // The old test was `_headDist < (_offsetDist + 2.0)`, i.e. "the trail is not yet
    // 2 m deeper than my offset". Two problems:
    //
    //  - the FIRST recorded point lands at arc 0 -> 2 and `headDist` only becomes 2,
    //    so a group at offset 1 needed the SECOND point (arc 4) before moving: the
    //    column visibly waited ~4-5 m, and the deeper groups waited proportionally
    //    longer even though their seat already existed;
    //  - the +2.0 was a leftover margin: the seat is already validated against the
    //    real trail, so it can never point at ground the leader has not reached.
    //
    // The truth is simply "is a seat published". The queue resolves the seat by arc
    // (`headDist - offset`), so the moment the leader has walked this group's depth a
    // seat exists and the group is released - which is exactly the cascade wanted:
    // RTO moves at 1 m, the next at 6 m, and so on.
    if (!_inQueueEarly && { _headDist < _offsetDist }) then {
        // NOT RELEASED YET: keep the squad following its own leader so it is never
        // left behind. `doStop` is deliberately NOT used - it puts the AI to sleep and
        // the first `move` after it needs a full path re-plan, which is exactly how
        // units ended up stranded at the start point while the commander walked away.
        { _x limitSpeed _spd; } forEach (units _group);
        units _group doFollow leader _group;
        sleep 0.5;
        continue;
    };

    // =========================================================================
    // TRAIN MODEL: the column follows FIXED TRAIL POINTS BY INDEX.
    //
    // A point of the recorded trail is a coordinate the leader really walked. It
    // never moves: `trailPath` only GROWS, existing entries are never rewritten.
    // Each group therefore holds an INDEX into that array instead of an arclength.
    // Its target is `trailPath[index]` verbatim - no interpolation, no re-sampling.
    //
    // That is what makes the column behave like a train: the markers stay nailed
    // to the ground at the millimetre, and when the front group leaves the column
    // every following group takes the NEXT point of the SAME array one step back.
    // (The previous arclength sampling re-derived every position on every tick, so
    // markers drifted and several groups could resolve to the same metre.)
    //
    // The index is derived from the group's natural march offset:
    //     slotIndex = round(trailOffsetDist / recordStep)
    // `recordStep` is the spacing the RECORDER uses between stored points (2 m), so
    // the index maps the offset onto the stored array exactly.
    // =========================================================================
    private _targetPos = [0, 0, 0];
    private _tangentDir = getDir _leader;

    private _recordStep = _anchor getOrDefault ["recordStep", 2.0];
    if (!(_recordStep isEqualType 0) || { _recordStep <= 0 }) then { _recordStep = 2.0; };

    // THE COLUMN IS A TRAIN, NOT A LINE OF FIXED MARKS.
    //
    // What the user sees and what the code must produce, step by step:
    //   - While the column walks, EVERY group downstream of the leader ALSO walks
    //     (a road column is a continuous stream, it never freezes).
    //   - When the front group stops, the ones behind keep closing up and then
    //     STOP TOO - they come to rest, bunched, with the SAME spacing they already
    //     had, right behind the car in front. They never hover metres behind the
    //     tail point with a hole in front of them.
    //   - The queue hands out FIXED, non-overlapping seats (front to back): seat k
    //     is the same recorded point for the whole march, and the group ahead has
    //     reserved the seats in between. That is what makes the spacing survive.
    //   - A seat beyond the tip is NOT a reason to freeze: the group walks up to the
    //     LAST RECORDED point (the tip) and comes to rest there, never being clamped
    //     into a knot because the seat it holds (beyond the tip) is still unique.
    //
    // History: seats beyond the tip used to `continue` with a 0.5 s sleep, so the
    // group never issued a move at all, stood frozen on a possibly bogus spot, and
    // the tail appeared pinned / stacked at the bridge entrance while the leader
    // walked. That is exactly the "tres puntos activos uno al lado del otro" the RPT
    // showed: seats 0, 1 and 2 all inside the first few metres of the deck.
    // The index we occupy is resolved in ONE of two ways, and exactly one field is
    // read per branch (single writer per field):
    //
    //   ACROSS   -> "trailSlotIndex", the natural seat of the column.
    //   IN QUEUE -> "trailQueueIndex", published by fn_formationsTrailQueueSync for
    //               the groups waiting behind a cut (bridge / gap / clearance). There
    //               the seat is NOT the natural one: it is the near-bank point, so the
    //               train holds its ground instead of being sent to an index that does
    //               not exist yet.
    //
    // We NEVER write these fields: the queue owns them, and echoing our own guess
    // back would make the group behind inherit a seat nobody assigned.
    // CRITICAL: `FTCS_fnc_registryGet` returns NIL for an absent key, and in SQF
    // `private _x = <nil>;` does NOT create the variable at all - the next line that
    // reads it raises "Undefined variable in expression". Every read below must land
    // in a DEFAULT via `isNil`, not via `isEqualType` (Lessons 9 and 14).
    //
    // SEAT INDEX measured FROM THE FRONT of the trail, the same way the road column
    // samples it (`headDist - offsetDist`). `trailPath` grows from the march start
    // (index 0) to the leader (last index), so a bare `round(offset / recordStep)` is
    // a distance from the ORIGIN and mirrored the whole column.
    //
    // And dividing by `recordStep` is not enough either: a bridge crossing records
    // ONE point spanning ~100 m, so the index arithmetic lags whole dozens of points
    // behind reality (RPT: "LARGE STEP 108.4m"). The offset is therefore resolved by
    // ARC on the real polyline, which works with any segment length. A negative index
    // (the leader has not walked this depth) puts the group in HOLD.
    private _maxIdx = (count _trailPath) - 1;
    private _headDist = _anchor getOrDefault ["headDist", 0];
    if (!(_headDist isEqualType 0) || { _headDist < 0 }) then { _headDist = 0; };
    // SEAT MISSING FROM THE PATH is a DIFFERENT state from "not walked yet".
    //
    // `headDist >= _offsetDist` only says the leader has walked this depth; it does
    // not say the POINT is still in `trailPath`. When the path is shorter than the
    // requested arc (trim equilibrium, a jump, a fresh anchor) `trailIndexAtArc`
    // saturates at the last index and the group would sit on it forever - the RPT
    // showed three groups pinned at `max=94` while holding offsets 189/200/217.
    // Detect it explicitly so the recovery below can act instead of waiting.
    // `trailIndexAtArc` saturates at the last index when the requested arc is past
    // the end, so "the index we got" alone cannot tell "exact last point" from
    // "clamped". `_headDist` is the trail's full arclength by construction (the
    // recorder grows it by exactly each appended segment), so the comparison below
    // is the cheap equivalent: the requested arc must fit inside the recorded path.
    private _naturalIdx = -1;
    private _pathCoversOffset = false;
    if (_headDist >= _offsetDist) then {
        _pathCoversOffset = true;
        _naturalIdx = [_trailPath, _headDist - _offsetDist] call FTCS_fnc_trailIndexAtArc;
    };

    private _queueHasSeat = [_groupID, "trailQueueHasSeat"] call FTCS_fnc_registryGet;
    if (isNil "_queueHasSeat") then { _queueHasSeat = false; };
    private _queueSpoke = (_queueHasSeat isEqualType true);
    private _inQueue = ((_queueHasSeat isEqualType true) && { _queueHasSeat });

    private _queuedIdx = [_groupID, "trailQueueIndex"] call FTCS_fnc_registryGet;
    if (isNil "_queuedIdx") then { _queuedIdx = -1; };

    private _slotIdxStored = [_groupID, "trailSlotIndex"] call FTCS_fnc_registryGet;
    if (isNil "_slotIdxStored") then { _slotIdxStored = -1; };

    private _slotIndex = if (_inQueue && { _queuedIdx isEqualType 0 } && { _queuedIdx >= 0 }) then {
        _queuedIdx
    } else {
        if ((_slotIdxStored isEqualType 0) && { _slotIdxStored >= 0 }) then { _slotIdxStored } else { _naturalIdx }
    };

    // TAIL FALLBACK: this group has NO seat anywhere in the file, yet the path holds
    // at least two walkable points. It then walks to the OLDEST surviving point
    // (index 0) instead of freezing where it was placed - that freeze is how the tail
    // was "lost" while the leader marched away (RPT 14:37: three groups pinned at
    // `max=94` holding offsets 189/200/217). Index 0 is ground the leader really
    // walked and is strictly behind every other seat, so the group rejoins the file
    // in order without cutting corners. The trim now protects the full column depth,
    // so this is a safety net, not the normal path.
    private _noSeatAtAll = (!_inQueue && { !_queueSpoke } && { _naturalIdx < 0 });
    if (_noSeatAtAll && { _maxIdx >= 1 }) then {
        _slotIndex = 0;
        if (missionNamespace getVariable ["FTCS_Debug_Mode", false]) then {
            diag_log format ["[FTCS][TRAIL][LANE] *** '%1' off=%2 has no seat in a %3-point path -> tail fallback idx 0",
                _groupID, (round _offsetDist), _maxIdx + 1];
        };
    };

    // HOLD: the leader has not walked this group's depth yet, so the point its seat
    // maps to does not exist in the recorded trail. Standing still WHERE IT WAS PLACED
    // is the only correct answer:
    //   - it must NOT be sent to the tip (maxIdx): during a crossing the tip is the
    //     near bank, and during the initial column build-up it is the leader's own
    //     track, so sending everyone there collapses the platoon around him while its
    //     slots stay empty (observed in game);
    //   - it must NOT be skipped by the groups behind it (the queue chains them from
    //     the nearest car that really holds a seat).
    //
    // The queue publishes this as "no seat" (trailQueueHasSeat = false) for every
    // group whose depth has not been walked yet, so the check needs both flags:
    // the queue must have spoken, and it must not have given us a seat.
    // LEADER NOT YET WALKED THIS DEPTH: the seat index is NEGATIVE because the trail
    // is measured from the front (`maxIdx - offset/step`). Waiting groups still follow
    // their own leader so they never fall behind - they simply wait their turn to be
    // placed on the column. `doStop` is NOT used: it puts the AI to sleep and the
    // first `move` after it costs a full path re-plan (this is what left stragglers
    // standing at the start point while the leader walked away).
    // HOLD = STAY EXACTLY WHERE THIS GROUP IS. No new destination is issued.
    //
    // The queue answered "no seat" (trailQueueHasSeat = false). That means the group
    // must NOT consume any further trail point this tick - so its cursor must not be
    // advanced and it must not be sent to one either. Sending it to `trailPath[cursor]`
    // (the old fallback) made every waiting group converge on the SAME index, which is
    // exactly what the RPT shows:
    //
    //     'HQ - Command Element'          offset=1   tgt=[3550.07,5767.3]
    //     '3rd Rifle Squad - BAR Support' offset=111 tgt=[3550.07,5767.3]
    //     '3rd Rifle Squad - Rifle Team A' offset=125 tgt=[3550.07,5767.3]
    //
    // Three groups parked on one point and looking like they overtook each other.
    //
    // `doFollow` keeps the squad tied to its own leader without a path re-plan, so it
    // stays awake and starts immediately once a seat is published.
    if (_inQueue == false && { _queueSpoke }) then {
        {
            _x limitSpeed 0;
        } forEach (units _group);
        units _group doFollow leader _group;
        sleep 0.5;
        continue;
    };

    // SEAT BEYOND THE TIP is no longer clamped here.
    //
    // Clamping to `maxIdx` was the source of the "hesitation at the bridge": while
    // the trail was frozen the tip stayed at one index, every waiting group was sent
    // to that SAME index, and the moment the leader recorded a point on the far bank
    // the tip jumped ~100 m and all their targets moved at once. Groups visibly went,
    // came back, blocked each other and finally crossed two or three at a time.
    //
    // The queue already guarantees that every published seat EXISTS in the trail
    // (`trailIndexAtArc` never returns past the last point), so there is nothing to
    // clamp: either the group owns a real point or it holds (HOLD block above).
    private _seatBeyondTip = false;

    // =========================================================================
    // THE LANE: walk the trail POINT BY POINT, never jump to the seat.
    //
    // `_slotIndex` is the CEILING this group may reach (its doctrinal seat, capped
    // by the column). It is NOT a destination. Ordering a group straight to that
    // index made the engine take the shortest path instead of the leader's track:
    // the column cut corners, crossed diagonals and never stepped on the recorded
    // points, which is the one thing a trail march exists to guarantee.
    //
    // Each group now holds a CURSOR: the last trail point it actually reached.
    // Every tick it is sent to `cursor + 1` (or to its ceiling, whichever is nearer),
    // so it must consume EVERY point in order, exactly as the leader walked them.
    //
    // The bridge then needs no special case: while the trail is cut, `maxIdx` does
    // not grow, so `cursor + 1` does not exist and the group simply holds its point
    // on the near bank. When the leader records the first point on the far side,
    // index `cursor + 1` exists and the engine is asked to walk that one real
    // segment - the bridge - with its own pathfinding.
    // =========================================================================
    // Declared OUTSIDE the branch: an SQF `private` lives only inside the block that
    // declares it, and the debug trace at the end of the tick reads this value from
    // the outer scope (that mismatch has already cost two runs: "Undefined variable
    // in expression: _targetIdx").
    private _targetIdx = -1;

    if (count _trailPath >= 2) then {
        // A negative seat means there is nothing to advance to this tick. The HOLD
        // block above already exited for that case, so reaching here with `-1` can
        // only mean the queue has not published yet (first tick).
        if (_slotIndex < 0) then {
            { _x limitSpeed _spd; } forEach (units _group);
            units _group doFollow leader _group;
            sleep 0.5;
            continue;
        };
        if (_slotIndex > _maxIdx) then { _slotIndex = _maxIdx };

        // ===================================================================
        // THE LANE - SIMPLE VERSION.
        //
        // The group owns ONE index: `trailSlotIndex`, published by the queue. It walks
        // towards a point a few indexes ahead of its previous target, never past its
        // seat, and only renews that target when it has physically reached it.
        //
        // No projection, no arc bookkeeping, no cursor rescuing. Every such mechanism
        // tried today created a feedback loop in which the cursor ran ahead of the
        // column until every group sat on the last recorded point.
        //
        // The bridge needs no special case: while the trail is cut, `maxIdx` does not
        // grow, the seat stays on the near bank and the group simply waits there.
        // ===================================================================
        private _leaderPosNow = getPosATL (leader _group);

        // The index this group is CURRENTLY walking to (-1 = none yet).
        _targetIdx = [_groupID, "trailLaneTargetIdx"] call FTCS_fnc_registryGet;
        if (isNil "_targetIdx") then { _targetIdx = -1; };
        if (!(_targetIdx isEqualType 0)) then { _targetIdx = -1; };

        // Has the group reached the point it was walking to? Then it may pick the
        // next one. `2.5 m` is the tolerance; on a long bridge segment it scales so a
        // 100 m span is still reachable.
        private _reached = false;
        if (_targetIdx < 0) then {
            _reached = true;                       // never walked anywhere yet
        } else {
            private _tgt = (_trailPath select (_targetIdx min _maxIdx)) select 0;
            private _segLen = _tgt distance2D _leaderPosNow;
            _reached = (_segLen <= (2.5 max (_segLen * 0.35)));
        };

        if (_reached) then {
            // Next target: a few indexes ahead of the one just reached, capped by the
            // seat and by the recorded trail. `3` indexes = ~6 m of look-ahead, which
            // keeps the movement fluid without letting the group cut corners.
            private _from = if (_targetIdx < 0) then { 0 } else { _targetIdx };
            _targetIdx = (_from + 3) min _slotIndex;
            if (_targetIdx > _maxIdx) then { _targetIdx = _maxIdx };
            if (_targetIdx < 0) then { _targetIdx = 0 };
            [_groupID, "trailLaneTargetIdx", _targetIdx] call FTCS_fnc_registrySet;
        };

        // TIMEOUT: a point can be truly unreachable (inside a building, on a rock).
        // It does NOT fire while the group waits at its seat: that is queuing.
        //
        // SKIP ONE POINT, NEVER JUMP TO THE SEAT. Releasing the group straight to
        // `_slotIndex` looked like a clean escape but it handed the engine a target
        // tens of metres ahead: Arma paths the SHORTEST way there, so the group cut
        // across the terrain and never stepped on the intermediate recorded points -
        // exactly the "they overtake the whole file" symptom. Stepping one index per
        // timeout keeps the lane invariant (every point is walked in order) and still
        // recovers: a truly blocked index is skipped after `_stuckTimeout` seconds.
        //
        // `_targetIdx` is also never allowed PAST the seat: the clamp below uses it
        // as the ceiling, and the queue must stay the only owner of that number.
        private _stuckKey = format ["FTCS_TrailLaneStuck_%1", _groupID];
        private _stuckSince = _group getVariable [_stuckKey, -1];
        private _stuckTimeout = 20;
        if (_targetIdx >= _slotIndex) then {
            _group setVariable [_stuckKey, -1];
        } else {
            if (_stuckSince < 0) then {
                _group setVariable [_stuckKey, time];
            } else {
                if ((time - _stuckSince) > _stuckTimeout) then {
                    private _nextIdx = ((_targetIdx + 1) min _slotIndex) min _maxIdx;
                    diag_log format ["[FTCS][TRAIL][LANE] *** '%1' stuck at idx %2 for %3s -> skipping to %4 (seat %5)",
                        _groupID, _targetIdx, round (time - _stuckSince), _nextIdx, _slotIndex];
                    _targetIdx = _nextIdx;
                    [_groupID, "trailLaneTargetIdx", _targetIdx] call FTCS_fnc_registrySet;
                    _group setVariable [_stuckKey, time];
                };
            };
        };

        // CLAMP BEFORE INDEXING. `_targetIdx` is a value carried across ticks and the
        // trail is rebuilt by the trim, so it can point past the current array. Reading
        // it unclamped raised "Undefined variable in expression: _entry" every tick and
        // the group never received a target at all.
        _slotIndex = (_targetIdx min _maxIdx) max 0;
        private _entry = _trailPath select _slotIndex;
        _targetPos = +(_entry select 0);
        _tangentDir = _entry select 1;

        // Compact double-lane placement: lateral offset perpendicular to the
        // local trail tangent (pairs share the point, +/-0.75 m off the line)
        private _sh = [_groupID, "trailShoulderOffset"] call FTCS_fnc_registryGet;
        if (!isNil "_sh" && { _sh != 0 }) then {
            private _perp = (_tangentDir + 90) % 360;
            _targetPos = _targetPos getPos [abs _sh, if (_sh < 0) then { (_perp + 180) % 360 } else { _perp }];
        };
    } else {
        _slotIndex = 0;
        _targetPos = getPosATL _leader getPos [_offsetDist, (getDir _leader + 180) % 360];
    };

    // -------------------------------------------------------------------------
    // SLOT VALIDITY (bridge / obstacle rejection)
    //
    // A point of the RECORDED trail is always walkable: the recorder refuses to
    // store elevated points (bridge decks and ramps), so `trailPath` contains only
    // ground the leader stood on. This check therefore exists as a belt-and-braces
    // guard for the fallback branch above (no trail yet) and for shoulder offsets
    // that push the slot off the line.
    //
    // 0.5 m is the calibrated elevation tolerance: highest ground sample measured
    // was dz=-0.05, lowest bridge sample dz=+1.84.
    // -------------------------------------------------------------------------
    private _slotValid = [_targetPos, 0.5] call FTCS_fnc_navIsValidGround;

    if (_slotValid) then {
        // The INDEX we occupy is published by fn_formationsTrailQueueSync (single
        // writer). Here we only report the ground we are heading to, so the group
        // behind can inherit the point we are vacating. Writing the index from two
        // threads was the second cause of the scrambled order at the bridge: this
        // loop overwrote the queue's reservation with its own natural guess.
        if (missionNamespace getVariable ["FTCS_Debug_Mode", false]) then {
            if (!_queueSpoke) then { diag_log format ["[FTCS][TRAIL][QUEUE] '%1' queue silent -> natural idx %2", _groupID, _naturalIdx]; };
            if (_inQueue) then {
                diag_log format ["[FTCS][TRAIL][LANE] '%1' seat %2 -> walking to idx %3 (tip %4)",
                    _groupID, _slotIndex, _targetIdx, _maxIdx];
            };
        };
        [_groupID, "trailTargetPos", +_targetPos] call FTCS_fnc_registrySet;
    } else {
        // The slot is not walkable (shoulder pushed it off the trail, or a
        // fallback point over water). Hold position: the group already stands on
        // ground it was allowed to occupy.
        _targetPos = getPosATL (leader _group);
        [_groupID, "trailTargetPos", +_targetPos] call FTCS_fnc_registrySet;
        diag_log format ["[FTCS][TRAIL][QUEUE] *** '%1' slot at index %2 not walkable -> HOLDING",
            _groupID, _slotIndex];
    };

    [ _groupID, "trailTangentDir", _tangentDir ] call FTCS_fnc_registrySet;

    // Debug telemetry: per-group assigned trail slot marker (orange dot with the
    // group's chain distance label), refreshed in this same 1s tick loop.
    // Guard: groups with non-positive offsets are not chain members - never
    // create orphan markers for them (leftovers from a previous march world).
    if (missionNamespace getVariable ["FTCS_Debug_Mode", false] && { _offsetDist > 0 }) then {
        private _tName = format ["FTCS_DEBUG_TRAIL_SLOT_%1", _groupID];
        if (getMarkerType _tName == "") then {
            createMarkerLocal [_tName, _targetPos];
            _tName setMarkerTypeLocal "mil_dot";
            _tName setMarkerColorLocal "ColorOrange";
            _tName setMarkerSizeLocal [0.75, 0.75];
        };
        _tName setMarkerPosLocal _targetPos;
        _tName setMarkerTextLocal format [" (T%1m)", round _offsetDist];
    };

    // TRAIL-DIAG (throttled per group every 5 s under FTCS_Debug_Mode):
    // reports where this group is being sent and whether that point is over
    // water. A trail slot that lands on water is uncrossable for the AI and is
    // what makes groups pile up at a bridge entrance.
    if (missionNamespace getVariable ["FTCS_Debug_Mode", false]) then {
        private _dbgKey = format ["FTCS_TrailDbg_%1", _groupID];
        if (time > (_group getVariable [_dbgKey, 0])) then {
            _group setVariable [_dbgKey, time + 5];
            // HEIGHT-AWARE water test (Lesson 13 Part B): surfaceIsWater is true on a
            // bridge deck because it samples the terrain cell below. Only treat the
            // slot as water when the slot is AT water level (< 1.2 m above terrain).
            private _tgtTerrainZ = getTerrainHeightASL [(_targetPos select 0), (_targetPos select 1)];
            private _tgtWater = (surfaceIsWater _targetPos) && { ((_targetPos select 2) - _tgtTerrainZ) < 1.2 };
            private _ldrPos = getPosATL (leader _group);
            private _ldrTerrainZ = getTerrainHeightASL [(_ldrPos select 0), (_ldrPos select 1)];
            private _ldrWater = (surfaceIsWater _ldrPos) && { ((_ldrPos select 2) - _ldrTerrainZ) < 1.2 };
            private _stuck = ((leader _group) distance2D _targetPos) > 25 && { (speed (leader _group)) < 0.5 };
            diag_log format ["[FTCS][TRAIL][FOLLOW] '%1' spd=%2 offset=%3 tgt=%4 tgtWater=%5 ldrWater=%6 distToTgt=%7 stuck=%8",
                _groupID, (round (_spd * 10) / 10), (round _offsetDist), _targetPos, _tgtWater, _ldrWater,
                round ((leader _group) distance2D _targetPos), _stuck];
            if (_tgtWater) then {
                diag_log format ["[FTCS][TRAIL][FOLLOW] *** '%1' trail slot is AT WATER LEVEL - AI cannot path there.", _groupID];
            };
            if (_stuck) then {
                diag_log format ["[FTCS][TRAIL][FOLLOW] *** '%1' STUCK far from its slot (>25 m, ~0 km/h).", _groupID];
            };
        };
    };

    if (_spd > 2) then {
        // Marching: exact leader pace, natural pathing, no forced facing
        { _x limitSpeed _spd; } forEach (units _group);
        _group move _targetPos;
        units _group doFollow leader _group;

        _alignedOnStop = false;
        _facingAppliedOnReady = false;

        sleep _tickTime;
    } else {
        // Stopped: close into the slot, then align once to the trail tangent
        private _posChanged = ((_targetPos distance2D _lastTargetPos) > 1.5);
        if (!_alignedOnStop || _posChanged) then {
            _group move _targetPos;
            _lastTargetPos = _targetPos;
            _alignedOnStop = true;
            _facingAppliedOnReady = false;
        };

        if (!_facingAppliedOnReady && { unitReady (leader _group) || ((leader _group) distance2D _targetPos < 3) }) then {
            _group setFormDir _tangentDir;
            _facingAppliedOnReady = true;
        };

        { _x disableAI "RADIOPROTOCOL"; } forEach (units _group);
        if (([ _groupID, "movingMode" ] call FTCS_fnc_registryGet) != "FOLLOWING_TRAIL") exitWith {
            // Follow ended: restore radio protocol so units report normally again
            { _x enableAI "RADIOPROTOCOL"; } forEach (units _group);
        };
        sleep _tickTime;
    };
};

// Thread exit: clean up this group's debug slot marker when leaving trail mode
private _exitMarker = format ["FTCS_DEBUG_TRAIL_SLOT_%1", _groupID];
if (getMarkerType _exitMarker != "") then { deleteMarkerLocal _exitMarker; };
