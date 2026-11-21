/*
    ================================================================================
    File: fn_menuGate.sqf
    Module: Menu
    Author: FTCS Team
    Description: Resolves ONE row GATE against the state snapshot produced by
                 fn_menuGetState. Returns [enabled, reason]:

                   enabled : BOOLEAN - TRUE -> row is white and usable
                   reason  : STRING  - short motive appended to the label when the
                                       row is greyed ("already active", "no road
                                       column", "target already marked"...)

                 Gate naming convention (declared in fn_menuCatalog):
                   gate_always              always enabled
                   gate_unit                needs a valid platoon leader unit
                   gate_march               needs an operational phase (> 0)
                   gate_follow_mode         needs a platoon formation ordered
                   gate_scout               needs at least one squad with effectives
                   gate_squads              needs at least one squad with effectives
                   gate_not_halted          disabled when the platoon is HALTED
                   gate_halted              enabled  only when the platoon is HALTED
                   gate_phase<N>            disabled when already in phase <N>
                   gate_form_<F>            disabled when formation == <F>
                   gate_speed_<S>           disabled when speed == <S>
                   gate_stance_<S>          disabled when stance == <S>
                   gate_roe_<R>             disabled when roe == <R>
                   gate_tech_<T>            disabled when movement technique == <T>
                   gate_layout_<L>_<W>      disabled when the <W> column has layout <L>
                   gate_compact             enabled only with a compactable column
                   gate_edge_push/_pull     road edge margin limits
                   gate_scout_<slot>        disabled when that scout slot is in use
                   gate_scout_any           enabled only when a scout slot is in use
                   gate_squad_<n>           squad leader must be alive and active
                   gate_sqdform_<F>         squad formation == <F>
                   gate_sqdstance_<S>       squad stance == <S>
                   gate_has_target          squad has a marked target
                   gate_no_target           squad has NO marked target
                   gate_flank_<SIDE>        that flank is not already open
                   gate_not_following       squad is not already following the platoon

                 This function only READS. Rule 15: no AI command is issued here.
    Language: Strictly English (Rule 7, Rule 11)
    ================================================================================
*/

params [["_gate", "gate_always"], ["_state", createHashMap], ["_squadRec", createHashMap]];

// Hard argument contract (Lesson 34/37 - the RPT proved it twice):
//   * line 70  "getordefault: Type Array, expected HashMap"   -> caller passed (gate, ARRAY, ARRAY)
//   * line 93  "Error ==: Type HashMap, expected ..."          -> caller passed (state, gate, ...)
// A function script does NOT type or reorder what it receives. Normalise HERE, once:
//   1. _gate must be a String (it is the switch key).
//   2. _state / _squadRec must be HashMaps; if only ONE argument was given, accept
//      the single-HashMap form and fall back to the published snapshot.
// Interchanging the two maps is then harmless.
if (!(_gate isEqualType "")) then {
    // Swapped arguments: the state arrived first and the gate id second.
    if ((_gate isEqualType createHashMap) && { _state isEqualType "" }) then {
        private _swap = _gate;
        _gate = _state;
        _state = _swap;
    } else {
        _gate = "gate_always";
    };
};
if (!(_state isEqualType createHashMap)) then {
    _state = missionNamespace getVariable ["FTCS_Menu_LastState", createHashMap];
};
if (!(_state isEqualType createHashMap)) then { _state = createHashMap; };
if (!(_squadRec isEqualType createHashMap)) then { _squadRec = createHashMap; };

// Result slots. Declared BEFORE the scratch slots so no later `private` in this
// script can invalidate them (Lesson 34/37).
private _enabled = true;
private _reason = "";

// ---- SCRATCH SLOTS ---------------------------------------------------------
// Declared ONCE, assigned inside the switch. `private` is SCRIPT-scoped (Lesson
// 34/37): the six `gate_*_` cases below used to declare `private _want` and the
// edge cases `private _isRoad`, so each case invalidated the binding of the
// previous one and the function aborted with "Undefined variable".
private _gWant = "";
private _gRoad = false;
private _gTrail = false;
private _gSteps = 0;
private _gLeader = objNull;
private _gMode = "";
private _gLeaderState = "NO_GROUP";

// --- platoon scalars ----------------------------------------------------------
private _phase = _state getOrDefault ["phase", 0];
private _halted = _state getOrDefault ["halted", false];
private _formation = _state getOrDefault ["formation", ""];
private _speed = _state getOrDefault ["speed", ""];
private _stance = _state getOrDefault ["stance", ""];
private _roe = _state getOrDefault ["roe", ""];
private _tech = _state getOrDefault ["moveTech", "CROSS_COUNTRY"];
private _scoutSlots = _state getOrDefault ["scoutSlots", createHashMap];

// --- keyed gates (one switch on the prefix keeps the catalog declarative) -----
switch (true) do {
    case (_gate == "gate_always"): {};

    case (_gate == "gate_unit"): {
        _gLeader = _state getOrDefault ["leaderUnit", objNull];
        if (isNull _gLeader) then { _enabled = false; _reason = "commander not found"; };
    };

    case (_gate == "gate_march"): {
        if (_phase <= 0) then { _enabled = false; _reason = "set an operational phase first"; };
    };

    // Submenu visibility gates used by the root menu:
    //   gate_scout  : the Scouts submenu only makes sense with a scout-eligible
    //                 squad (an anchor group still exists to detach teams from).
    //   gate_squads : the Squad Directives hub needs at least one live squad.
    case (_gate == "gate_scout"): {
        private _scoutFound = false;
        {
            if ((_x getOrDefault ["effective", 0]) > 0) exitWith { _scoutFound = true; };
        } forEach (_state getOrDefault ["squads", []]);
        if (!_scoutFound) then { _enabled = false; _reason = "no squads available"; };
    };

    case (_gate == "gate_squads"): {
        private _sqdCount = 0;
        { if ((_x getOrDefault ["effective", 0]) > 0) then { _sqdCount = _sqdCount + 1; }; }
        forEach (_state getOrDefault ["squads", []]);
        if (_sqdCount == 0) then { _enabled = false; _reason = "no squads available"; };
    };

    case (_gate == "gate_not_halted"): {
        if (_halted) then { _enabled = false; _reason = "platoon is halted"; };
    };

    case (_gate == "gate_halted"): {
        if (!_halted) then { _enabled = false; _reason = "halt the platoon first"; };
    };

    case (_gate == "gate_phase1"): {
        if (_phase == 1) then { _enabled = false; _reason = "already active"; };
    };
    case (_gate == "gate_phase2"): {
        if (_phase == 2) then { _enabled = false; _reason = "already active"; };
    };
    case (_gate == "gate_phase3"): {
        if (_phase == 3) then { _enabled = false; _reason = "already active"; };
    };

    case (_gate find "gate_form_" == 0): {
        _gWant = _gate select [10];
        if (_formation == _gWant) then { _enabled = false; _reason = "already active"; };
        if (_phase <= 0) then { _enabled = false; _reason = "set an operational phase first"; };
    };

    case (_gate find "gate_speed_" == 0): {
        _gWant = _gate select [11];
        if (_speed == _gWant) then { _enabled = false; _reason = "already active"; };
    };

    case (_gate find "gate_stance_" == 0): {
        _gWant = _gate select [12];
        if (_stance == _gWant) then { _enabled = false; _reason = "already active"; };
    };

    case (_gate find "gate_roe_" == 0): {
        _gWant = _gate select [9];
        if (_roe == _gWant) then { _enabled = false; _reason = "already active"; };
    };

    case (_gate find "gate_tech_" == 0): {
        _gWant = _gate select [10];
        if (_tech == _gWant) then { _enabled = false; _reason = "already active"; };
    };

    // ---- follow-mode row -----------------------------------------------------
    // The row offers the mode the platoon is NOT in (ABS -> "switch to RELATIVE").
    // It is meaningless before a platoon formation exists, so it stays grey while
    // the platoon has NOT ordered one. "formation" is the common platoonFormation
    // of the groups: "NONE" is the explicit "no formation ordered" state seeded by
    // fn_registryInit; "" and "MIXED" (groups disagree) are treated the same way.
    // Read from the registry, never introspected (Rule 20).
    case (_gate == "gate_follow_mode"): {
        _gLeader = _state getOrDefault ["leaderUnit", objNull];
        if (isNull _gLeader) then {
            _enabled = false; _reason = "commander not found";
        } else {
            if ((_state getOrDefault ["formation", "NONE"]) in ["", "NONE", "MIXED"]) then {
                _enabled = false; _reason = "order a platoon formation first";
            };
        };
    };

    // ---- column layout gates -------------------------------------------------
    // Naming: gate_layout_<LAYOUT>_<WORLD> (WORLD: ROAD|TRAIL)
    // A layout row is greyed when that exact layout is already active in its own
    // march world: re-ordering it would rebuild a column that is already laid.
    case (_gate find "gate_layout_" == 0): {
        private _lRest = _gate select [12];
        private _lSep = _lRest find "_";
        private _lWant = if (_lSep > 0) then { _lRest select [0, _lSep] } else { _lRest };
        private _lWorld = if (_lSep > 0) then { _lRest select [_lSep + 1] } else { "ROAD" };
        _gRoad = _state getOrDefault ["roadActive", false];
        _gTrail = _state getOrDefault ["trailActive", false];
        if (_lWorld == "TRAIL") then {
            if (_gTrail && { (_state getOrDefault ["trailLayout", ""]) == _lWant }) then { _enabled = false; _reason = "already active"; };
        } else {
            if (_gRoad && { (_state getOrDefault ["roadLayout", ""]) == _lWant }) then { _enabled = false; _reason = "already active"; };
        };
    };

    case (_gate == "gate_compact"): {
        // Compact is decided by the PLATOON REGISTRY field `movementTechnique`
        // (Point 0 Rule 16): ROAD_COLUMN -> compactable, TRAIL_COLUMN -> compactable,
        // anything else (CROSS_COUNTRY, default) -> no column to compact. The anchor
        // layouts are NOT consulted: anchors are per-world geometry that outlives a
        // mode change, while the registry field is the single per-platoon truth.
        private _cTech = _state getOrDefault ["moveTech", "CROSS_COUNTRY"];
        if (!(_cTech in ["ROAD_COLUMN", "TRAIL_COLUMN"])) then {
            _enabled = false;
            _reason = "no active column";
        };
    };

    case (_gate == "gate_edge_push"): {
        if ((_state getOrDefault ["moveTech", "CROSS_COUNTRY"]) != "ROAD_COLUMN") then {
            _enabled = false; _reason = "no active road column";
        } else {
            _gSteps = _state getOrDefault ["edgeSteps", 0];
            if (_gSteps >= 4) then { _enabled = false; _reason = "max out (4/4)"; };
        };
    };

    case (_gate == "gate_edge_pull"): {
        if ((_state getOrDefault ["moveTech", "CROSS_COUNTRY"]) != "ROAD_COLUMN") then {
            _enabled = false; _reason = "no active road column";
        } else {
            _gSteps = _state getOrDefault ["edgeSteps", 0];
            if (_gSteps <= 0) then { _enabled = false; _reason = "edge margin at 0"; };
        };
    };

    case (_gate find "gate_sqdform_" == 0): {
        _gWant = _gate select [13];
        if ((_squadRec getOrDefault ["squadFormation", ""]) == _gWant) then { _enabled = false; _reason = "already active"; };
    };

    case (_gate find "gate_sqdstance_" == 0): {
        _gWant = _gate select [15];
        if ((_squadRec getOrDefault ["squadStance", ""]) == _gWant) then { _enabled = false; _reason = "already active"; };
    };

    case (_gate == "gate_has_target"): {
        if (!(_squadRec getOrDefault ["hasTarget", false])) then { _enabled = false; _reason = "no target marked"; };
    };

    case (_gate == "gate_no_target"): {
        if (_squadRec getOrDefault ["hasTarget", false]) then { _enabled = false; _reason = "target already marked"; };
    };

    case (_gate == "gate_flank_L"): {
        if ((_squadRec getOrDefault ["movingMode", ""]) == "FLANK_OPEN_L") then { _enabled = false; _reason = "flank already open"; };
    };
    case (_gate == "gate_flank_R"): {
        if ((_squadRec getOrDefault ["movingMode", ""]) == "FLANK_OPEN_R") then { _enabled = false; _reason = "flank already open"; };
    };

    case (_gate == "gate_not_following"): {
        _gMode = _squadRec getOrDefault ["movingMode", ""];
        if (_gMode in ["FOLLOWING_COMMANDER_REL", "FOLLOWING_COMMANDER_ABS"]) then { _enabled = false; _reason = "already in formation"; };
    };

    case (_gate find "gate_scout_" == 0): {
        // gate_scout_<slot> : slot occupancy, and the providing squad must be able
        // to detach a team (its anchor must still exist).
        if (_gate == "gate_scout_any") then {
            if (count _scoutSlots == 0) then { _enabled = false; _reason = "no detached scouts"; };
        } else {
            private _slot = parseNumber (_gate select [11]);
            if (_slot in _scoutSlots) then {
                _enabled = false;
                _reason = format ["slot %1 in use", _slot];
            };
        };
    };

    case (_gate find "gate_squad_" == 0): {
        // gate_squad_<n> : leader of the squad anchor must be ALIVE and ACTIVE.
        // Arma re-elects a leader when the old one dies, but an INCAPACITATED leader
        // stays in charge and cannot command: the squad is shown as having no
        // active leader until the recovery routine brings him back.
        private _leaderState = _squadRec getOrDefault ["leaderState", "NO_GROUP"];
        switch (_leaderState) do {
            case "HEALTHY": { };
            case "DEAD": { _enabled = false; _reason = "leader dead"; };
            case "INCAPACITATED": { _enabled = false; _reason = "leader incapacitated"; };
            default { _enabled = false; _reason = "group not found"; };
        };
        if ((_squadRec getOrDefault ["effective", 0]) <= 0) then {
            _enabled = false; _reason = "all down";
        };
    };

    default {
        // Unknown gate: fail OPEN (white row) rather than silently hiding a command.
        diag_log format ["[FTCS][MENU] *** UNKNOWN GATE '%1' - row left enabled.", _gate];
    };
};

[_enabled, _reason]
