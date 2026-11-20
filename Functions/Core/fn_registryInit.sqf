/*
    File: fn_registryInit.sqf
    Module: Core
    Author: FTCS Team / Manel P.
    Description: Initializes the Master Encapsulated Group Registry (FTCS_Groups_Registry_Table)
                 from the parsed FTCS_Company_Data hierarchy. Creates one sub-HashMap per group
                 holding all real-time tactical state (state machine, geometry and ORBAT slot
                 allocation), replacing the old scattered per-property hash tables.

    Registry Sub-HashMap properties per group:
        * "movingMode"         : [String] ("AT_WILL", "FOLLOWING_COMMANDER_REL", "FOLLOWING_COMMANDER_ABS", "HALT", "STOP", "CONVOY").
        * "stance"             : [String] ("AT_WILL", "FORCE_UP", "FORCE_MIDDLE", "FORCE_DOWN").
        * "awareMode"          : [String] ("CARELESS", "SAFE", "AWARE", "COMBAT", "STEALTH").
        * "speed"              : [String] ("FULL", "NORMAL", "LIMITED").
        * "roe"                : [String] ("HOLD_FIRE", "FIRE_AT_WILL", "FIRE_IF_FIRED_UPON").
        * "task"               : [String] ("AT_WILL", "MOVING", "SUPPRESSING", "ATTACKING", "WATCHING", "WAITING").
        * "platoonFormation"   : [String] Macro slot formation in the platoon deployment ("COLUMN", "WEDGE", "VEE", "LINE", "DIAMOND").
        * "squadFormation"     : [String] Squad internal formation (written solely by formationsTypeSquadSet).
        * "teamFormation"      : [String] Team native formation as applied to the Arma group (written solely by formationsTypeSquadSet).
        * "allocationSlot"     : [Scalar] Numerical slot assignment in platoon formations (0, 1, 2, 3...).
        * "formationPosition"  : [Array]  Assigned geometric formation slot [Distance, Direction, Leader Object].
        * "relPosition"        : [Array]  Current relative position vector [Distance, Direction, Reference Leader].
        * "parentSquadGroup"   : [Group]  Anchor group of the squad this team belongs to (self-referencing on the anchor).
        * "squadId"            : [String] Doctrinal squad key ("SQD_1_1") - lets consumers group teams without reading the doctrine.
        * "isSquadLeaderGroup" : [Boolean] TRUE only on the group carrying the Squad Leader (squad-level anchor).
        * "platoonId"         : [Scalar] Numeric platoon this group belongs to (0 = unassigned group).
        * "roleKey"           : [String] Doctrine role of the group leader ("PLT_1_LEADER", "SQD_1_2_LEADER", "").

    Also initializes the shared tactical constants and the platoon-level formation
    geometry buffer (Platoon_Formation_Position_List) used by the Formations module.
*/

// ---------------------------------------------------------------------------
// 1. Shared tactical constants (migrated from the legacy init block)
// ---------------------------------------------------------------------------

FTCS_Pace_Soldiers = 3;
FTCS_Platoon_MAX_Infantry_Groups = 14;
FTCS_Squad_MAX_Infantry_Groups = 5;

// Global debug mode sentinel (Controls visual telemetry and map slot markers)
if (isNil "FTCS_Debug_Mode") then {
    FTCS_Debug_Mode = true;
};

// Secondary TRACE sentinel (subordinate to FTCS_Debug_Mode). Gates extremely
// verbose instrumentation - per loop step, per tick, per frame - that is only
// wanted while investigating one specific problem. Rule 19 of the design notes:
// ALL diagnostic traces go behind a sentinel; only REAL FAILURES log always
// (prefixed with ***).
if (isNil "FTCS_Debug_Trace") then {
    FTCS_Debug_Trace = false;
};

// MENU UI sentinel. Selects WHICH commanding UI the session runs and how much it
// logs. READ ONCE at boot and NEVER toggled in game (design decision): a session
// starts either in menu-debug mode or with the real gameplay menus, and stays
// there. true = debug tree (every implemented order reachable, full log dump of
// state and dispatched orders) | false = real gameplay menus (not implemented yet).
// It is INDEPENDENT of FTCS_Debug_Mode: telemetry and the menu layer are two
// separate switches so any combination of the two is possible.
if (isNil "FTCS_Debug_Menu_Mode") then {
    FTCS_Debug_Menu_Mode = true;
};

missionNamespace setVariable ["FTCS_Platoon_Advance_Direction", 0];
missionNamespace setVariable ["FTCS_Last_Commander_Dir", getDir player];

// ---------------------------------------------------------------------------
// 2. Commander group reference (Company HQ group, fallback to player group)
// ---------------------------------------------------------------------------

private _companyHQ = FTCS_Company_Data getOrDefault ["companyHQ", createHashMap];
FTCS_Group_Commander = _companyHQ getOrDefault ["group", group player];

// ---------------------------------------------------------------------------
// 3. Registry access helper closures (global, engine-agnostic)
// ---------------------------------------------------------------------------

// NOTE: SQF arrays collapse nil elements ([a, b, nil] becomes [a, b]), so a
// call with nil as the value arrives here as a 2-element array. That shape is
// interpreted as "DELETE the key" - the nil-clearing semantics every consumer
// of this setter already assumes (e.g. clearing pinnedAnchorPos, mvAligned).
// Passing nil via params would leave _value undefined (undefined-variable
// runtime error), hence the explicit count-based branch instead of params.
// PLATOON state accessor (PHASE 2). The platoon registry is the runtime source
// of truth; during migration the doctrine mirror in FTCS_Company_Data is kept
// in sync so consumers that still read the tree keep observing the same value.
// Usage:
//     [pltId, "movementTechnique", value] call FTCS_fnc_registrySetPlatoon;
//     [pltId, "formationSlots", value]     call FTCS_fnc_registrySetPlatoon;
//     [pltId, "roadPath"]                 call FTCS_fnc_registryGetPlatoon;  // get
// Passing nil (2-element form) deletes the key from the registry only; the
// doctrine mirror is left untouched on deletion unless it had the key, in which
// case it is set to the field's documented empty value.
FTCS_fnc_registrySetPlatoon = {
    params ["_pltId", "_key"];
    if (!(FTCS_Platoons_Registry isEqualType createHashMap)) then { FTCS_Platoons_Registry = createHashMap; };
    private _pltEntry = FTCS_Platoons_Registry getOrDefault [_pltId, createHashMap];
    private _hasValue = ((count _this) > 2);
    private _value = nil;
    if (_hasValue) then { _value = _this select 2; };
    if (_hasValue && { !isNil "_value" }) then {
        _pltEntry set [_key, _value];
    } else {
        if (_key in _pltEntry) then { _pltEntry deleteAt _key; };
    };
    FTCS_Platoons_Registry set [_pltId, _pltEntry];

    // ---- PHASE 8d: doctrine mirror REMOVED for mutable runtime fields ------
    // The mirror existed so consumers still reading FTCS_Company_Data during the
    // migration kept seeing fresh values. After Phase 8b every RUNTIME consumer
    // reads this registry, so mutating the doctrine tree is now pointless and
    // misleading (it is the immutable blueprint - see Lesson 8).
    // Fields that were never mutated at runtime (currentPhase, roadPath, anchors)
    // still get mirrored for any boot-time reader that expects them there.
    private _mirrorKeys = ["currentPhase", "roadPath", "roadAnchor", "trailAnchor"];
    if ((_key in _mirrorKeys) && { _hasValue } && { !isNil "_value" }) then {
        private _platoonsMap = FTCS_Company_Data getOrDefault ["platoons", createHashMap];
        private _pltKeyM = format ["PLT_%1", _pltId];
        private _pltData = _platoonsMap getOrDefault [_pltKeyM, createHashMap];
        if (count _pltData > 0) then {
            _pltData set [_key, _value];
            _platoonsMap set [_pltKeyM, _pltData];
            FTCS_Company_Data set ["platoons", _platoonsMap];
        };
    };
    true;
};

// Platoon state reader. Falls back to the doctrine mirror while the field has
// not been seeded into the registry yet (Phase 2 safety net).
FTCS_fnc_registryGetPlatoon = {
    params ["_pltId", "_key"];
    private _pltEntry = (missionNamespace getVariable ["FTCS_Platoons_Registry", createHashMap]) getOrDefault [_pltId, createHashMap];
    if (_key in _pltEntry) exitWith { _pltEntry get _key };
    private _pltData = (FTCS_Company_Data getOrDefault ["platoons", createHashMap]) getOrDefault [format ["PLT_%1", _pltId], createHashMap];
    if (_key in _pltData) exitWith { _pltData get _key };
    // Optional 3rd argument: explicit default when neither source has the key
    if ((count _this) > 2) exitWith { _this select 2 };
    nil
};

FTCS_fnc_registrySet = {
    params ["_groupID", "_key"];
    private _entryKey = if (_groupID isEqualType grpNull) then { groupId _groupID } else { _groupID };
    private _entry = FTCS_Groups_Registry_Table getOrDefault [_entryKey, createHashMap];
    if ((count _this) > 2) then {
        // Guard: a nil value reaching here would raise the engine's
        // "Undefined variable _value" diagnostic on every call - treat it as
        // an explicit DELETE request instead (same semantics as the 2-arg form).
        private _value = _this select 2;
        if (!isNil "_value") then { _entry set [_key, _value]; }
        else { if (_key in _entry) then { _entry deleteAt _key; }; };
    } else {
        if (_key in _entry) then { _entry deleteAt _key; };
    };
    FTCS_Groups_Registry_Table set [_entryKey, _entry];
    true;
};

FTCS_fnc_registryGet = {
    params ["_groupID", "_key"];
    private _entryKey = if (_groupID isEqualType grpNull) then { groupId _groupID } else { _groupID };
    private _entry = FTCS_Groups_Registry_Table getOrDefault [_entryKey, createHashMap];
    _entry getOrDefault [_key, nil];
};

// -------------------------------------------------------
// Registry geometry helper: updates formationPosition & relPosition slots together
// Supports optional _refLeaderGroup to bind fireteams to their specific Squad Leader
// ---------------------------------------------------------------------------

FTCS_fnc_registryUpdatePos = {
    params ["_groupID", "_distance", "_direction", ["_refLeaderGroup", objNull]];
    private _entry = FTCS_Groups_Registry_Table getOrDefault [_groupID, createHashMap];
    private _formPos = _entry getOrDefault ["formationPosition", [-1, -1, objNull]];
    private _relPos = _entry getOrDefault ["relPosition", [-1, -1, objNull]];
    _formPos set [0, _distance]; _formPos set [1, _direction];
    _relPos set [0, _distance]; _relPos set [1, _direction];
    if (!isNull _refLeaderGroup) then {
        _formPos set [2, _refLeaderGroup];
        _relPos set [2, _refLeaderGroup];
    };
    _entry set ["formationPosition", _formPos];
    _entry set ["relPosition", _relPos];
    FTCS_Groups_Registry_Table set [_groupID, _entry];
    true;
};

// ---------------------------------------------------------------------------
// 4. Build one encapsulated registry entry per parsed group
// ---------------------------------------------------------------------------

private _platoonsMap = FTCS_Company_Data getOrDefault ["platoons", createHashMap];
private _registeredCount = 0;

{
    private _pltKey = _x;
    private _pltData = _y;
    private _parsedSquads = _pltData getOrDefault ["parsedSquads", createHashMap];

    // Platoon HQ group acts as the default formation leader reference for its squads.
    // Resolved deterministically to the COMMAND element (the group holding the
    // platoon leader), never to whichever team the HashMap happens to yield first.
    private _pltHqSquadId = format ["SQD_%1_0", parseNumber ((_pltKey splitString "_") select 1)];
    private _pltHqGroup = grpNull;
    if (_parsedSquads get _pltHqSquadId isEqualType createHashMap) then {
        private _pltHqSquadData = _parsedSquads get _pltHqSquadId;
        private _teams = _pltHqSquadData getOrDefault ["teams", _pltHqSquadData getOrDefault ["tacticalTeams", createHashMap]];
        private _hqLeaderUnit = (_pltHqSquadData getOrDefault ["assignedRoles", createHashMap]) getOrDefault [format ["PLT_%1_LEADER", parseNumber ((_pltKey splitString "_") select 1)], objNull];
        // 1. Doctrine COMMAND / TEAM_1 element
        {
            private _teamType = toUpper ((_y) getOrDefault ["type", ""]);
            private _grp = (_y) getOrDefault ["group", grpNull];
            if (!isNull _grp && { _teamType in ["TEAM_1", "COMMAND"] }) exitWith { _pltHqGroup = _grp; };
        } forEach _teams;
        // 2. Team whose leader IS the platoon leader unit
        if (isNull _pltHqGroup && { !isNull _hqLeaderUnit }) then {
            {
                private _grp = (_y) getOrDefault ["group", grpNull];
                if (!isNull _grp && { leader _grp == _hqLeaderUnit }) exitWith { _pltHqGroup = _grp; };
            } forEach _teams;
        };
        // 3. Squad-level group (unified HQ)
        if (isNull _pltHqGroup) then { _pltHqGroup = _pltHqSquadData getOrDefault ["group", grpNull]; };
        // 4. Last resort: first resolved team (malformed doctrine only)
        if (isNull _pltHqGroup) then {
            {
                private _grp = _y getOrDefault ["group", grpNull];
                if (!isNull _grp) exitWith { _pltHqGroup = _grp; };
            } forEach _teams;
        };
    };
    private _leaderRef = if (isNull _pltHqGroup) then { FTCS_Group_Commander } else { _pltHqGroup };
    private _formationSlotsMap = _pltData getOrDefault ["formationSlots", createHashMap];
    // Numeric platoon id of the platoon being seeded: stamped on every group
    // entry as "platoonId" so consumers never depend on the FTCS_Player_Platoon_ID
    // global (company-scale safe, Point 18 - identity is data, not a global).
    private _pltNumSeed = parseNumber ((_pltKey splitString "_") select 1);

    private _slot = 0;

    {
        private _sqdId = _x;
        private _sqdData = _y;
        private _isUnified = _sqdData getOrDefault ["isUnified", false];

        // Resolve pre-assigned formation slot for this squad from the doctrine definition
        private _preassignedSlot = -1;
        {
            if (_y == _sqdId) exitWith { _preassignedSlot = _x; };
        } forEach _formationSlotsMap;
        if (_preassignedSlot < 0) then { _preassignedSlot = _slot; };

        // Collect every Arma 3 group belonging to this squad element (including HQ sub-teams)
        private _squadGroups = [];
        private _teamsContainer = _sqdData getOrDefault ["teams", _sqdData getOrDefault ["tacticalTeams", createHashMap]];

        if (count _teamsContainer > 0) then {
            {
                private _teamId = _x;
                private _teamData = _y;
                private _teamGroup = _teamData getOrDefault ["group", grpNull];
                if (!isNull _teamGroup) then {
                    // Doctrine team type ("TEAM_1"/"TEAM_2"/"TEAM_3"...) stamped by
                    // fn_parseEditorGroups. It is the ONLY deterministic way to know
                    // which team is the squad-leader element: HashMap iteration order
                    // is NOT insertion order, so "first team found" is random.
                    private _teamType = toUpper (_teamData getOrDefault ["type", ""]);
                    // Doctrine tactical role of this team ("ASSAULT" | "SCOUT" | "SUPPORT"):
                    // declared in the doctrine template, copied by fn_applyDoctrine into
                    // parsedSquads > team > "tacticalRole". It is the ONLY sanctioned way
                    // to know which team can be detached as scouts (Point 18: never
                    // derive it from the display name or from HashMap order).
                    // Resolve the doctrinal role. parsedSquads is built by fn_parseEditorGroups
                    // AFTER fn_applyDoctrine, so the per-team "tacticalRole" is usually empty.
                    // The authoritative source is FTCS_Company_Data > "doctrineTeamRoles"
                    // (array INDEX -> role, seeded by fn_applyDoctrine) indexed by the team's
                    // ordinal in its TEAM_<N> type. No names, no HashMap order (Point 18).
                    private _teamRole = toUpper (_teamData getOrDefault ["tacticalRole", ""]);
                    if (_teamRole == "") then {
                        private _rolesList = FTCS_Company_Data getOrDefault ["doctrineTeamRoles", []];
                        private _ordinal = parseNumber ((_teamType splitString "_") param [1, "0"]);
                        if (_ordinal > 0 && { _ordinal <= count _rolesList }) then {
                            _teamRole = toUpper ((_rolesList select (_ordinal - 1)));
                        };
                    };
                    // Check if the specific sub-team has its own formation slot (e.g. SQD_1_0_TEAM_2 -> Slot 4)
                    private _teamSlot = _preassignedSlot;
                    {
                        if (_y == _teamId) exitWith { _teamSlot = _x; };
                    } forEach _formationSlotsMap;
                    _squadGroups pushBack [_teamGroup, _teamSlot, _teamType, _teamRole];
                };
            } forEach _teamsContainer;
        } else {
            private _grp = _sqdData getOrDefault ["group", grpNull];
            // Unified squad: its single group IS the squad-leader element
            if (!isNull _grp) then { _squadGroups pushBack [_grp, _preassignedSlot, "UNIFIED"]; };
        };

        // --- Squad-level anchor resolution (DETERMINISTIC) -------------------
        // The anchor is the group carrying the Squad Leader. Priority:
        //   1. Unified squad -> its single group.
        //   2. Multi-team squad -> the team whose doctrine type is TEAM_1
        //      (the command element of a combat squad, the COMMAND element of
        //      a platoon HQ). Never "first team found": HashMap order is random.
        //   3. The team whose leader unit IS the squad's "leader" (name-free).
        //   4. HQ guide/security element (platoon guide) as doctrinal counterpart.
        //   5. Squad-level "group" left by the parser (legacy fallback).
        //   6. First resolved group (malformed doctrine only).
        private _sqdAnchorGroup = grpNull;
        if ((count _teamsContainer) == 0) then {
            _sqdAnchorGroup = _sqdData getOrDefault ["group", grpNull];
        };
        if (isNull _sqdAnchorGroup) then {
            {
                if ((_x select 2) in ["TEAM_1", "COMMAND"]) exitWith { _sqdAnchorGroup = _x select 0; };
            } forEach _squadGroups;
        };
        if (isNull _sqdAnchorGroup) then {
            // Match the squad LEADER unit against each team's leader (doctrine name-free)
            private _sqdLeaderUnit = _sqdData getOrDefault ["leader", objNull];
            if (!isNull _sqdLeaderUnit) then {
                {
                    if (leader (_x select 0) == _sqdLeaderUnit) exitWith { _sqdAnchorGroup = _x select 0; };
                } forEach _squadGroups;
            };
        };
        // Tactical Guide element (HQ squad): points at the platoon guide team,
        // the doctrinal counterpart of the Squad Leader inside the HQ element.
        if (isNull _sqdAnchorGroup) then {
            {
                if ((_x select 2) in ["TEAM_3", "GUIDE", "SECURITY"]) exitWith { _sqdAnchorGroup = _x select 0; };
            } forEach _squadGroups;
        };
        // Squad-level "group" left by the parser (legacy fallback).
        if (isNull _sqdAnchorGroup) then { _sqdAnchorGroup = _sqdData getOrDefault ["group", grpNull]; };
        // Last resort: first resolved group (kept only so a malformed doctrine
        // still registers; never relied on for hierarchy decisions).
        if (isNull _sqdAnchorGroup && { count _squadGroups > 0 }) then { _sqdAnchorGroup = (_squadGroups select 0) select 0; };

        {
            private _group = _x select 0;
            private _groupSlot = _x select 1;
            private _groupTeamRole = if ((count _x) > 3) then { _x select 3 } else { "" };
            private _groupID = groupId _group;
            private _isSquadLeaderGroup = (_group == _sqdAnchorGroup);
            // roleKey: the HIGHEST-RANK DOCTRINE ROLE present in this group
            // (e.g. "PLT_1_LEADER", "SQD_1_2_LEADER"). Empty string when no unit
            // of the group holds a doctrine role.
            //
            // IMPORTANT - this is NOT `leader _group`. Arma 3 picks its own group
            // leader (leadership skill / seniority), and a command group holding
            // BOTH the platoon leader and his RTO often resolves to the RTO. The
            // doctrine role hierarchy is therefore ranked explicitly:
            //   PLT_<N>_LEADER (100) > SQD_*_LEADER (80) > *SERGEANT (60)
            //   > any other doctrine role (40)
            // A player-driven platoon is unaffected (consumers use isPlayer /
            // FTCS_Platoon_Leader_Unit); this ranking only guarantees the field is
            // correct for AI platoons and company scale.
            private _groupLeader = leader _group;
            private _roleKey = "";
            private _roleRank = 0;
            private _groupUnits = units _group;
            private _assigned = _sqdData getOrDefault ["assignedRoles", createHashMap];
            {
                private _roleVar = _x;
                private _roleUnit = _y;
                if (_roleUnit in _groupUnits) then {
                    private _rank = if (_roleVar == format ["PLT_%1_LEADER", _pltNumSeed]) then { 100 }
                        else { if ((_roleVar find "_LEADER") >= 0) then { 80 }
                        else { if ((_roleVar find "SERGEANT") >= 0) then { 60 } else { 40 } } };
                    if (_rank > _roleRank) then {
                        _roleRank = _rank;
                        _roleKey = _roleVar;
                    };
                };
            } forEach _assigned;
            // Keep the reference for logging clarity (leader may hold no role)
            if (isNull _groupLeader) then { _groupLeader = objNull; };

            // Skip already registered groups (idempotent initialization)
            if !(_groupID in FTCS_Groups_Registry_Table) then {
                FTCS_Groups_Registry_Table set [_groupID, createHashMapFromArray [
                    ["movingMode", "AT_WILL"],
                    ["stance", "AT_WILL"],
                    ["awareMode", "SAFE"],
                    ["speed", "NORMAL"],
                    ["roe", "FIRE_IF_FIRED_UPON"],
                    ["task", "AT_WILL"],
                    ["platoonFormation", "COLUMN"],
                    ["allocationSlot", _groupSlot],
                    ["formationPosition", [-1, -1, _leaderRef]],
                    ["relPosition", [-1, -1, _leaderRef]],
                    ["teamAttachment", "SQUAD_BOUND"],
                    ["parentSquadGroup", _sqdAnchorGroup],
                    ["squadId", _sqdId],
                    ["isSquadLeaderGroup", _isSquadLeaderGroup],
                    ["platoonId", _pltNumSeed],
                    ["roleKey", _roleKey],
                    ["tacticalRole", _groupTeamRole]
                ]];
                _registeredCount = _registeredCount + 1;
            } else {
                // Existing entry (re-init): stamp/refresh hierarchy identity
                private _exEntry = FTCS_Groups_Registry_Table getOrDefault [_groupID, createHashMap];
                _exEntry set ["parentSquadGroup", _sqdAnchorGroup];
                _exEntry set ["squadId", _sqdId];
                _exEntry set ["isSquadLeaderGroup", _isSquadLeaderGroup];
                _exEntry set ["platoonId", _pltNumSeed];
                _exEntry set ["roleKey", _roleKey];
                _exEntry set ["tacticalRole", _groupTeamRole];
                FTCS_Groups_Registry_Table set [_groupID, _exEntry];
            };
        } forEach _squadGroups;

        _slot = _slot + 1;

    } forEach _parsedSquads;

} forEach _platoonsMap;

// ---------------------------------------------------------------------------
// 4b. Platoon-level registry (FTCS_Platoons_Registry): per-platoon state map
//     Company-scale safe: one entry per platoon, keyed by platoon number.
//     Populated HERE (doctrine seed time): "squads" = array of squad group
//     refs + "platoonGroup"/"platoonLeader" refs. Runtime code must consume
//     this registry (rule 16) - NEVER re-derive squads from FTCS_Company_Data.
// ---------------------------------------------------------------------------
if (isNil "FTCS_Platoons_Registry") then { FTCS_Platoons_Registry = createHashMap; };

{
    private _pltKey = _x;
    private _pltNum = parseNumber ((_pltKey splitString "_") select 1);
    private _pltData2 = _y;
    private _parsedSquads2 = _pltData2 getOrDefault ["parsedSquads", createHashMap];

    private _squadGroups = [];
    private _platoonHqGroup = grpNull;
    {
        private _sqdData2 = _y;
        private _teams2 = _sqdData2 getOrDefault ["teams", _sqdData2 getOrDefault ["tacticalTeams", createHashMap]];
        if (count _teams2 > 0) then {
            // Team-structured squad: the SQUAD-LEVEL anchor is the squad-leader
            // element - the team whose doctrine type is TEAM_1 (never "the first
            // team found": HashMap key order is NOT deterministic, which is how
            // a BAR support team ended up acting as a squad anchor).
            // Subsequent teams are fireteams whose anchor is their squad leader -
            // they must NOT be in this list, or consumers (platoonHaltRejoin
            // hierarchy split, squad slot dispatchers) would treat every fireteam
            // as a platoon-slot element and re-anchor them against the lieutenant.
            // SAME priority ladder as the group-entry seeding above: TEAM_1 /
            // COMMAND first, then the squad leader unit, then the guide element,
            // then the parser's squad-level group.
            private _anchor = grpNull;
            {
                private _teamType2 = toUpper ((_y) getOrDefault ["type", ""]);
                private _g2 = (_y) getOrDefault ["group", grpNull];
                if (!isNull _g2 && { _teamType2 in ["TEAM_1", "COMMAND"] }) exitWith { _anchor = _g2; };
            } forEach _teams2;
            if (isNull _anchor) then {
                private _leaderUnit2 = _sqdData2 getOrDefault ["leader", objNull];
                if (!isNull _leaderUnit2) then {
                    {
                        private _g3 = (_y) getOrDefault ["group", grpNull];
                        if (!isNull _g3 && { leader _g3 == _leaderUnit2 }) exitWith { _anchor = _g3; };
                    } forEach _teams2;
                };
            };
            if (isNull _anchor) then {
                {
                    private _teamType4 = toUpper ((_y) getOrDefault ["type", ""]);
                    private _g4 = (_y) getOrDefault ["group", grpNull];
                    if (!isNull _g4 && { _teamType4 in ["TEAM_3", "GUIDE", "SECURITY"] }) exitWith { _anchor = _g4; };
                } forEach _teams2;
            };
            if (isNull _anchor) then { _anchor = _sqdData2 getOrDefault ["group", grpNull]; };
            if (!isNull _anchor) then { _squadGroups pushBackUnique _anchor; };
        } else {
            private _g = _sqdData2 getOrDefault ["group", grpNull];
            if (!isNull _g) then { _squadGroups pushBackUnique _g; };
        };
        // Platoon HQ = first squad (SQD_N_0) resolved group
        if ((format ["%1", _x]) find (format ["SQD_%1_0", _pltNum]) == 0) then {
            if (count _squadGroups > 0) then { _platoonHqGroup = _squadGroups select 0; };
        };
    } forEach _parsedSquads2;

    private _existing = FTCS_Platoons_Registry getOrDefault [_pltNum, createHashMap];
    // Registry-first, non-destructive: seed the ORBAT once, preserve any
    // runtime state (orderState, halt snapshot) already written by the menus.
    if (!(_existing getOrDefault ["squads", []] isEqualTo _squadGroups)) then {
        _existing set ["squads", _squadGroups];
    };

    // --- PHASE 2: platoon STATE seeded into the registry ---------------------
    // These fields used to live ONLY in FTCS_Company_Data > platoons > PLT_x.
    // From now on the platoon registry is the runtime source of truth (RULE 16)
    // and the doctrine tree keeps a MIRROR so existing consumers keep working
    // during migration (see fn_registrySetPlatoon below for the write-through).
    //
    //   movementTechnique : "CROSS_COUNTRY" | "ROAD_COLUMN" | "TRAIL_FILE"
    //   roadPath          : ARRAY of [posATL, tangentDir, roadWidth]
    //   roadAnchor        : HASHMAP (road march anchor for this platoon)
    //   trailAnchor       : HASHMAP (trail column anchor for this platoon)
    //   formationSlots    : HASHMAP slotIdx -> squad/team key (mutable at runtime:
    //                       detached scouts re-assign 5/6/7/8/11/12)
    // Only seeded when the registry does not carry them yet (preserve runtime).
    if (isNil { _existing get "movementTechnique" }) then {
        _existing set ["movementTechnique", _pltData2 getOrDefault ["movementTechnique", "CROSS_COUNTRY"]];
    };
    if (isNil { _existing get "roadPath" }) then {
        _existing set ["roadPath", _pltData2 getOrDefault ["roadPath", []]];
    };
    if (isNil { _existing get "roadAnchor" }) then {
        _existing set ["roadAnchor", _pltData2 getOrDefault ["roadAnchor", createHashMap]];
    };
    if (isNil { _existing get "trailAnchor" }) then {
        _existing set ["trailAnchor", _pltData2 getOrDefault ["trailAnchor", createHashMap]];
    };
    if (isNil { _existing get "formationSlots" }) then {
        // Copy (not reference) so runtime scout re-assignments do not silently
        // mutate the doctrine map while we are still mirroring it.
        private _slotsSrc = _pltData2 getOrDefault ["formationSlots", createHashMap];
        _existing set ["formationSlots", +_slotsSrc];
    };
    // currentPhase: operational phase (1 APPROACH / 2 OVERWATCH / 3 COMBAT).
    // Written by fn_platoonSetOperationalPhase through the platoon accessor;
    // seeded here from the doctrine so readers never see a missing key.
    if (isNil { _existing get "currentPhase" }) then {
        _existing set ["currentPhase", _pltData2 getOrDefault ["currentPhase", 0]];
    };
    // One diagnostic line per platoon: shows the resolved squad anchors, which
    // are what EVERY squad-level consumer (HALT/REJOIN, slot dispatchers) sees.
    diag_log format ["[FTCS][REGISTRY] plt %1 squads: %2", _pltNum, (_squadGroups apply { groupId _x }) joinString " | "];
    // Identity dump: platoonId + roleKey per squad ANCHOR of this platoon.
    // Lets a single log line verify the Phase-1 identity fields.
    {
        private _aId = groupId _x;
        private _aEntry = FTCS_Groups_Registry_Table getOrDefault [_aId, createHashMap];
        diag_log format ["[FTCS][REGISTRY]   anchor '%1' plt=%2 squad=%3 role='%4'", _aId, _aEntry getOrDefault ["platoonId", -1], _aEntry getOrDefault ["squadId", "?"], _aEntry getOrDefault ["roleKey", ""]];
    } forEach _squadGroups;
    if (isNull (_existing getOrDefault ["platoonGroup", grpNull]) && { !isNull _platoonHqGroup }) then {
        _existing set ["platoonGroup", _platoonHqGroup];
    };

    // --- Platoon COMMANDER identity (platoon-level, not group-level) -------------
    // "roleKey" answers "which doctrine role lives in THIS group" and therefore
    // cannot identify the platoon leader when the player (or an AI lieutenant)
    // has been detached from every group - the Command Element then reports its
    // RTO as highest role. The platoon entry below answers the real question:
    //     WHO commands this platoon?
    // leaderUnit  : the PLT_<N>_LEADER unit (player or AI), valid even when
    //               it stands outside any group.
    // leaderGroup : group of leaderUnit, or grpNull when he is detached.
    // peerOnly    : TRUE when the leader is NOT inside leaderGroup (player mode).
    //               Consumers must then use isPlayer / leaderUnit, never roleKey.
    private _hqId = format ["SQD_%1_0", _pltNum];
    private _hqData = _parsedSquads2 getOrDefault [_hqId, createHashMap];
    private _hqRoles = _hqData getOrDefault ["assignedRoles", createHashMap];
    private _pltLeaderUnit = _hqRoles getOrDefault [format ["PLT_%1_LEADER", _pltNum], objNull];
    // Fallbacks: player when the doctrine role is missing (single-platoon scope)
    if (isNull _pltLeaderUnit) then {
        private _candidate = missionNamespace getVariable [format ["PLT_%1_LEADER", _pltNum], objNull];
        if (!isNull _candidate) then { _pltLeaderUnit = _candidate; };
    };
    private _pltLeaderGroup = if (!isNull _pltLeaderUnit) then { group _pltLeaderUnit } else { grpNull };
    private _peerOnly = (isNull _pltLeaderGroup) || { !(_pltLeaderUnit in (units _pltLeaderGroup)) };
    _existing set ["leaderUnit", _pltLeaderUnit];
    _existing set ["leaderGroup", _pltLeaderGroup];
    _existing set ["peerOnly", _peerOnly];
    private _ldrVar = if (isNull _pltLeaderUnit) then { "<none>" } else { vehicleVarName _pltLeaderUnit };
    private _ldrName = if (isNull _pltLeaderUnit) then { "<none>" } else { name _pltLeaderUnit };
    private _ldrGrpId = if (isNull _pltLeaderGroup) then { "<detached>" } else { groupId _pltLeaderGroup };
    diag_log format ["[FTCS][REGISTRY] plt %1 leaderVar='%2' leaderName='%3' leaderGroup='%4' peerOnly=%5",
        _pltNum, _ldrVar, _ldrName, _ldrGrpId, _peerOnly];
    // Phase-2 state dump: proves the platoon state lives in the registry now.
    private _p2Tech = _existing getOrDefault ["movementTechnique", "<missing>"];
    private _p2Road = count (_existing getOrDefault ["roadPath", []]);
    private _p2Slots = count (_existing getOrDefault ["formationSlots", createHashMap]);
    diag_log format ["[FTCS][REGISTRY] plt %1 state: movementTechnique='%2' roadPath=%3 formationSlots=%4", _pltNum, _p2Tech, _p2Road, _p2Slots];

    FTCS_Platoons_Registry set [_pltNum, _existing];
} forEach _platoonsMap;

// ---------------------------------------------------------------------------
// 5. Register ad-hoc teams and unassigned groups as well
// ---------------------------------------------------------------------------

{
    private _teamGroup = (_y) getOrDefault ["group", grpNull];
    if (!isNull _teamGroup) then {
        private _groupID = groupId _teamGroup;
        if !(_groupID in FTCS_Groups_Registry_Table) then {
            FTCS_Groups_Registry_Table set [_groupID, createHashMapFromArray [
                ["movingMode", "AT_WILL"],
                ["stance", "AT_WILL"],
                ["awareMode", "SAFE"],
                ["speed", "NORMAL"],
                ["roe", "FIRE_IF_FIRED_UPON"],
                ["task", "AT_WILL"],
                ["platoonFormation", "COLUMN"],
                ["allocationSlot", -1],
                ["formationPosition", [-1, -1, FTCS_Group_Commander]],
                ["relPosition", [-1, -1, FTCS_Group_Commander]],
                ["teamAttachment", "SQUAD_BOUND"],
                // Ad-hoc team: belongs to no registered squad -> no anchor, no squad id
                ["parentSquadGroup", grpNull],
                ["squadId", ""],
                ["isSquadLeaderGroup", false],
                ["platoonId", 0],
                ["roleKey", ""]
            ]];
            _registeredCount = _registeredCount + 1;
        };
    };
} forEach (FTCS_Company_Data getOrDefault ["teams", createHashMap]);

{
    private _groupID = groupId _x;
    if !(_groupID in FTCS_Groups_Registry_Table) then {
        FTCS_Groups_Registry_Table set [_groupID, createHashMapFromArray [
            ["movingMode", "AT_WILL"],
            ["stance", "AT_WILL"],
            ["awareMode", "SAFE"],
            ["speed", "NORMAL"],
            ["roe", "FIRE_IF_FIRED_UPON"],
            ["task", "AT_WILL"],
            ["platoonFormation", "COLUMN"],
            ["allocationSlot", -1],
            ["formationPosition", [-1, -1, FTCS_Group_Commander]],
            ["relPosition", [-1, -1, FTCS_Group_Commander]],
            ["teamAttachment", "SQUAD_BOUND"],
            // Unassigned group: no squad hierarchy at all
            ["parentSquadGroup", grpNull],
            ["squadId", ""],
            ["isSquadLeaderGroup", false],
            ["platoonId", 0],
            ["roleKey", ""]
        ]];
        _registeredCount = _registeredCount + 1;
    };
} forEach (FTCS_Company_Data getOrDefault ["unassignedGroups", []]);

// ---------------------------------------------------------------------------
// 6. Platoon-level formation geometry buffer (14 slots: commander + 0..12)
// ---------------------------------------------------------------------------

Platoon_Formation_Position_List = [[], [], [], [], [], [], [], [], [], [], [], [], [], []];

// ---------------------------------------------------------------------------
// 7. SELF-TEST (Phase 2 acceptance) - writes every check to the RPT.
//    No console needed: a single [FTCS][SELFTEST] block proves that
//    (a) the platoon state was seeded into the registry,
//    (b) the doctrine mirror is in sync,
//    (c) the write-through accessor updates BOTH sides,
//    (d) the read accessor honours registry -> tree -> default order.
//    The write-through test restores the original value before finishing, so
//    the self-test has NO side effects on the running mission.
// ---------------------------------------------------------------------------
diag_log "[FTCS][SELFTEST] ===== PHASE 2 ACCEPTANCE ====";
{
    private _tId = _x;
    private _tReg = FTCS_Platoons_Registry getOrDefault [_tId, createHashMap];
    private _tTree = (FTCS_Company_Data getOrDefault ["platoons", createHashMap]) getOrDefault [format ["PLT_%1", _tId], createHashMap];

    private _regTech  = _tReg getOrDefault ["movementTechnique", "<MISSING>"];
    private _treeTech = _tTree getOrDefault ["movementTechnique", "<missing>"];
    private _regRoad  = count (_tReg getOrDefault ["roadPath", []]);
    private _treeRoad = count (_tTree getOrDefault ["roadPath", []]);
    private _regSlots = count (_tReg getOrDefault ["formationSlots", createHashMap]);
    private _treeSlots= count (_tTree getOrDefault ["formationSlots", createHashMap]);

    private _okSeed  = !(_regTech isEqualTo "<MISSING>");
    // Mirror check only applies when the doctrine tree actually carries the field
    private _okMirror= !(_treeTech isEqualTo "<missing>") && { _regTech isEqualTo _treeTech } && { _regSlots isEqualTo _treeSlots };
    diag_log format ["[FTCS][SELFTEST] plt %1 SEED   reg(tech=%2 road=%3 slots=%4) tree(tech=%5 road=%6 slots=%7) -> %8",
        _tId, _regTech, _regRoad, _regSlots, _treeTech, _treeRoad, _treeSlots,
        (if (_okSeed) then { "PASS" } else { "FAIL" })];
    // MIRROR only applies when the doctrine tree actually has a PLT_<id> entry.
    // Platoon 0 is the Company HQ: it lives under "companyHQ", not "platoons",
    // so it legitimately has no mirror to compare against (SKIP, not FAIL).
    private _hasTree = !(_treeTech isEqualTo "<missing>");
    private _mirrorVerdict = if (!_hasTree) then { "SKIP" } else { if (_okMirror) then { "PASS" } else { "FAIL" } };
    diag_log format ["[FTCS][SELFTEST] plt %1 MIRROR registry==tree -> %2", _tId, _mirrorVerdict];

    // (c) WRITE-THROUGH test: write a sentinel via the accessor, read both sides,
    //     then restore the original value. Sentinel is unique so it cannot be
    //     confused with a real technique value.
    private _sentinel = "SELFTEST_SENTINEL";
    [_tId, "movementTechnique", _sentinel] call FTCS_fnc_registrySetPlatoon;
    private _regAfter  = (FTCS_Platoons_Registry getOrDefault [_tId, createHashMap]) getOrDefault ["movementTechnique", "<none>"];
    private _treeAfter = ((FTCS_Company_Data getOrDefault ["platoons", createHashMap]) getOrDefault [format ["PLT_%1", _tId], createHashMap]) getOrDefault ["movementTechnique", "<none>"];
    diag_log format ["[FTCS][SELFTEST] plt %1 WRITE  reg=%2 tree=%3 -> %4",
        _tId, _regAfter, _treeAfter,
        (if ((_regAfter isEqualTo _sentinel) && { _treeAfter isEqualTo _sentinel }) then { "PASS" } else { "FAIL" })];

    // (d) READ accessor: registry value, then fallback default for a missing key
    private _readVal = [_tId, "movementTechnique", "<DEFAULT>"] call FTCS_fnc_registryGetPlatoon;
    private _readDef = [_tId, "__no_such_key__", "<DEFAULT>"] call FTCS_fnc_registryGetPlatoon;
    diag_log format ["[FTCS][SELFTEST] plt %1 READ   value=%2 default=%3 -> %4",
        _tId, _readVal, _readDef,
        (if ((_readVal isEqualTo _sentinel) && { _readDef isEqualTo "<DEFAULT>" }) then { "PASS" } else { "FAIL" })];

    // Restore the original technique through the SAME accessor (mirror included)
    [_tId, "movementTechnique", _regTech] call FTCS_fnc_registrySetPlatoon;
    diag_log format ["[FTCS][SELFTEST] plt %1 RESTORED to '%2'", _tId, _regTech];
} forEach (keys FTCS_Platoons_Registry);
diag_log "[FTCS][SELFTEST] ===== END PHASE 2 ACCEPTANCE =====";

// ---------------------------------------------------------------------------
// 8. PHASE 3 SELF-TEST - registry-only consumers.
//    Verifies that the migrated readers see the SAME data the registry holds
//    and that the hierarchy fields the Movement class depends on are complete:
//      (a) every registered group carries squadId + platoonId + teamAttachment
//      (b) every non-anchor group resolves a non-null parentSquadGroup
//      (c) the platoon slot map used by UI/pipelines is a HashMap with slots
//      (d) fn_movementBoundTeams returns a non-empty set for a squad anchor
//    No side effects: nothing is written.
// ---------------------------------------------------------------------------
diag_log "[FTCS][SELFTEST] ===== PHASE 3 ACCEPTANCE ====";
// Summary line instead of one line per group (log stays readable at company scale)
private _f3FieldsFail = 0;
private _f3ParentFail = 0;
{
    private _sEntry = _y;
    private _sSquad = _sEntry getOrDefault ["squadId", "<MISSING>"];
    private _sPlt   = _sEntry getOrDefault ["platoonId", "<MISSING>"];
    private _sAttach= _sEntry getOrDefault ["teamAttachment", "<MISSING>"];
    private _sIsAnc = _sEntry getOrDefault ["isSquadLeaderGroup", "<MISSING>"];
    private _sParent= _sEntry getOrDefault ["parentSquadGroup", grpNull];
    if ((_sSquad isEqualTo "<MISSING>") || { _sPlt isEqualTo "<MISSING>" } || { _sAttach isEqualTo "<MISSING>" } || { _sIsAnc isEqualTo "<MISSING>" }) then {
        _f3FieldsFail = _f3FieldsFail + 1;
        diag_log format ["[FTCS][SELFTEST] F3 FIELDS '%1' squad=%2 plt=%3 attach=%4 anchor=%5 -> FAIL", _x, _sSquad, _sPlt, _sAttach, _sIsAnc];
    };
    // Orphans: belonging to a squad (squadId set) but carrying no anchor at all.
    // Groups with an EMPTY squadId (ad-hoc teams / unassigned groups) are NOT orphans.
    private _noSquad = (_sSquad isEqualTo "");
    if ((_sIsAnc isEqualTo false) && { !_noSquad } && { isNull _sParent }) then {
        _f3ParentFail = _f3ParentFail + 1;
        diag_log format ["[FTCS][SELFTEST] F3 ORPHAN '%1' squad=%2 -> FAIL", _x, _sSquad];
    };
} forEach FTCS_Groups_Registry_Table;
diag_log format ["[FTCS][SELFTEST] F3 FIELDS total=%1 missingFields=%2 orphanTeams=%3 -> %4",
    count FTCS_Groups_Registry_Table, _f3FieldsFail, _f3ParentFail,
    (if ((_f3FieldsFail == 0) && { _f3ParentFail == 0 }) then { "PASS" } else { "FAIL" })];

// (c) platoon slot map is readable through the accessor
{
    private _sId = _x;
    private _sSlots = [_sId, "formationSlots", createHashMap] call FTCS_fnc_registryGetPlatoon;
    diag_log format ["[FTCS][SELFTEST] F3 SLOTS plt %1 type=%2 count=%3 -> %4",
        _sId, typeName _sSlots, (count _sSlots),
        (if (_sSlots isEqualType createHashMap) then { "PASS" } else { "FAIL" })];
} forEach (keys FTCS_Platoons_Registry);

// (d) bound-team resolution through the registry (squadId path)
// Guarded: fn_movementBoundTeams lives in CfgFunctions. init.sqf waits for
// compilation before calling registryInit, but the guard keeps this self-test
// safe if the call order ever changes.
if (!isNil "FTCS_fnc_movementBoundTeams") then {
    {
        private _bId = _x;
        private _bSquads = (FTCS_Platoons_Registry getOrDefault [_bId, createHashMap]) getOrDefault ["squads", []];
        private _bChecked = 0;
        private _bEmpty = 0;
        {
            if (!isNull _x) then {
                private _teams = [_x] call FTCS_fnc_movementBoundTeams;
                _bChecked = _bChecked + 1;
                if (count _teams == 0) then { _bEmpty = _bEmpty + 1; };
            };
        } forEach _bSquads;
        diag_log format ["[FTCS][SELFTEST] F3 BOUND  plt %1 squadsChecked=%2 emptyResults=%3 -> %4",
            _bId, _bChecked, _bEmpty,
            (if ((_bChecked > 0) && { _bEmpty == 0 }) then { "PASS" } else { "CHECK" })];
    } forEach (keys FTCS_Platoons_Registry);
} else {
    diag_log "[FTCS][SELFTEST] F3 BOUND  SKIPPED (fn_movementBoundTeams not compiled yet)";
};
diag_log "[FTCS][SELFTEST] ===== END PHASE 3 ACCEPTANCE =====";

// ---------------------------------------------------------------------------
// 9. PHASE 4 SELF-TEST - platoon-level readers migrated to the registry.
//    fn_targetMark     : resolves a squad's groups via "squadId"
//    fn_platoonSetOperationalPhase : resolves a platoon via "platoonId"
//    Verifies that BOTH lookups yield the expected population, i.e. that the
//    registry actually supports what those two functions now rely on.
// ---------------------------------------------------------------------------
diag_log "[FTCS][SELFTEST] ===== PHASE 4 ACCEPTANCE ====";
{
    private _p4Id = _x;
    private _p4Entry = FTCS_Platoons_Registry getOrDefault [_p4Id, createHashMap];
    private _p4Squads = _p4Entry getOrDefault ["squads", []];
    // (i) squadId lookup -> groups per registered squad anchor
    private _p4SquadsWithGroups = 0;
    private _p4SquadsEmpty = 0;
    {
        if (!isNull _x) then {
            private _sqdId = (FTCS_Groups_Registry_Table getOrDefault [groupId _x, createHashMap]) getOrDefault ["squadId", ""];
            private _cnt = 0;
            { if (((_y) getOrDefault ["squadId", ""]) isEqualTo _sqdId) then { _cnt = _cnt + 1; }; } forEach FTCS_Groups_Registry_Table;
            if (_cnt > 0) then { _p4SquadsWithGroups = _p4SquadsWithGroups + 1; } else { _p4SquadsEmpty = _p4SquadsEmpty + 1; };
        };
    } forEach _p4Squads;
    // (ii) platoonId lookup -> groups of this platoon
    private _p4Groups = 0;
    { if (((_y) getOrDefault ["platoonId", -1]) == _p4Id) then { _p4Groups = _p4Groups + 1; }; } forEach FTCS_Groups_Registry_Table;
    // (iii) currentPhase key present
    private _p4Phase = _p4Entry getOrDefault ["currentPhase", "<MISSING>"];
    diag_log format ["[FTCS][SELFTEST] F4 plt %1 squadIdLookup(ok=%2 empty=%3) platoonIdGroups=%4 currentPhase=%5 -> %6",
        _p4Id, _p4SquadsWithGroups, _p4SquadsEmpty, _p4Groups, _p4Phase,
        (if ((_p4SquadsEmpty == 0) && { !(_p4Phase isEqualTo "<MISSING>") }) then { "PASS" } else { "CHECK" })];
} forEach (keys FTCS_Platoons_Registry);
diag_log "[FTCS][SELFTEST] ===== END PHASE 4 ACCEPTANCE =====";

// ---------------------------------------------------------------------------
// 10. PHASE 5 SELF-TEST - order-menu helpers migrated to the registry:
//     _fnc_getPlatoonSquadInfo  (per-squad anchor)  -> needs exactly ONE anchor
//     _fnc_getAllPlatoonSquads  (whole platoon)     -> needs every platoon group
//     Verifies the registry can serve both WITHOUT the doctrine tree.
// ---------------------------------------------------------------------------
diag_log "[FTCS][SELFTEST] ===== PHASE 5 ACCEPTANCE ====";
{
    private _p5Id = _x;
    private _p5Entry = FTCS_Platoons_Registry getOrDefault [_p5Id, createHashMap];
    private _p5Squads = _p5Entry getOrDefault ["squads", []];
    // (i) exactly one anchor per squadId (what _fnc_getPlatoonSquadInfo relies on)
    private _p5DupAnchors = 0;
    private _p5NoAnchor = 0;
    {
        if (!isNull _x) then {
            private _sqdId = (FTCS_Groups_Registry_Table getOrDefault [groupId _x, createHashMap]) getOrDefault ["squadId", ""];
            private _anchors = 0;
            { if (((_y) getOrDefault ["squadId", ""]) isEqualTo _sqdId && { (_y) getOrDefault ["isSquadLeaderGroup", false] }) then { _anchors = _anchors + 1; }; } forEach FTCS_Groups_Registry_Table;
            if (_anchors == 0) then { _p5NoAnchor = _p5NoAnchor + 1; };
            if (_anchors > 1) then { _p5DupAnchors = _p5DupAnchors + 1; };
        };
    } forEach _p5Squads;
    // (ii) whole-platoon count (what _fnc_getAllPlatoonSquads returns)
    private _p5All = 0;
    { if (((_y) getOrDefault ["platoonId", -1]) == _p5Id) then { _p5All = _p5All + 1; }; } forEach FTCS_Groups_Registry_Table;
    diag_log format ["[FTCS][SELFTEST] F5 plt %1 anchors(squads=%2 noAnchor=%3 dup=%4) platoonGroups=%5 -> %6",
        _p5Id, count _p5Squads, _p5NoAnchor, _p5DupAnchors, _p5All,
        (if ((_p5NoAnchor == 0) && { _p5DupAnchors == 0 }) then { "PASS" } else { "FAIL" })];
} forEach (keys FTCS_Platoons_Registry);
diag_log "[FTCS][SELFTEST] ===== END PHASE 5 ACCEPTANCE =====";

// ---------------------------------------------------------------------------
// 11. PHASE 6 SELF-TEST - fn_formationsCurrentPositionSet (geometry capture).
//     The two-tier capture needs, per squad: ONE anchor (Tier 1) and its
//     fireteams resolvable by squadId (Tier 2). Verifies the registry can
//     serve that shape, and that the HQ element is separable by squadId.
// ---------------------------------------------------------------------------
diag_log "[FTCS][SELFTEST] ===== PHASE 6 ACCEPTANCE ====";
{
    private _p6Id = _x;
    private _p6Entry = FTCS_Platoons_Registry getOrDefault [_p6Id, createHashMap];
    private _p6Squads = _p6Entry getOrDefault ["squads", []];
    private _p6HqId = format ["SQD_%1_0", _p6Id];
    // Tier-1/Tier-2 shape check for every registered squad
    private _p6Ok = 0;
    private _p6Bad = 0;
    {
        if (!isNull _x) then {
            private _sqdId = (FTCS_Groups_Registry_Table getOrDefault [groupId _x, createHashMap]) getOrDefault ["squadId", ""];
            private _anchor = 0;
            private _twins = 0;
            { if (((_y) getOrDefault ["squadId", ""]) isEqualTo _sqdId) then {
                if ((_y) getOrDefault ["isSquadLeaderGroup", false]) then { _anchor = _anchor + 1; } else { _twins = _twins + 1; };
            }; } forEach FTCS_Groups_Registry_Table;
            if ((_anchor == 1) && { !isNull (leader _x) }) then { _p6Ok = _p6Ok + 1; } else { _p6Bad = _p6Bad + 1; };
            diag_log format ["[FTCS][SELFTEST] F6 plt %1 squad '%2' anchor=%3 fireteams=%4 leaderOk=%5",
                _p6Id, _sqdId, _anchor, _twins, (!isNull (leader _x))];
        };
    } forEach _p6Squads;
    // HQ element must be reachable by squadId and separable from combat squads
    private _p6HqGroups = 0;
    { if (((_y) getOrDefault ["squadId", ""]) isEqualTo _p6HqId) then { _p6HqGroups = _p6HqGroups + 1; }; } forEach FTCS_Groups_Registry_Table;
    diag_log format ["[FTCS][SELFTEST] F6 plt %1 squadsOk=%2 squadsBad=%3 hqGroups(%4)=%5 -> %6",
        _p6Id, _p6Ok, _p6Bad, _p6HqId, _p6HqGroups,
        (if (_p6Bad == 0) then { "PASS" } else { "FAIL" })];
} forEach (keys FTCS_Platoons_Registry);
diag_log "[FTCS][SELFTEST] ===== END PHASE 6 ACCEPTANCE =====";

// ---------------------------------------------------------------------------
// 12. PHASE 7 SELF-TEST - doctrine slot template vs live slot map.
//     "doctrineFormationSlots" (immutable, seeded by fn_applyDoctrine) must
//     exist for every platoon, and "formationSlots" (live) must start EQUAL to
//     it. From then on only the live map is mutated at runtime.
// ---------------------------------------------------------------------------
diag_log "[FTCS][SELFTEST] ===== PHASE 7 ACCEPTANCE ====";
{
    private _p7Id = _x;
    private _p7Entry = FTCS_Platoons_Registry getOrDefault [_p7Id, createHashMap];
    private _p7Tpl = _p7Entry getOrDefault ["doctrineFormationSlots", "<MISSING>"];
    private _p7Live = _p7Entry getOrDefault ["formationSlots", "<MISSING>"];
    private _p7TplOk = (_p7Tpl isEqualType createHashMap);
    private _p7LiveOk = (_p7Live isEqualType createHashMap);
    private _p7Same = if (_p7TplOk && { _p7LiveOk }) then { _p7Tpl isEqualTo _p7Live } else { false };
    diag_log format ["[FTCS][SELFTEST] F7 plt %1 template=%2 live=%3 equal=%4 -> %5",
        _p7Id,
        (if (_p7TplOk) then { count _p7Tpl } else { _p7Tpl }),
        (if (_p7LiveOk) then { count _p7Live } else { _p7Live }),
        _p7Same,
        (if (_p7TplOk && { _p7LiveOk }) then { "PASS" } else { "FAIL" })];
    // Consumers must read the LIVE map, never the template
    private _p7Read = [_p7Id, "formationSlots", createHashMap] call FTCS_fnc_registryGetPlatoon;
    if (!(_p7Read isEqualType createHashMap)) then {
        diag_log format ["[FTCS][SELFTEST] F7 plt %1 accessorRead -> FAIL (not a HashMap)", _p7Id];
    };
} forEach (keys FTCS_Platoons_Registry);
diag_log "[FTCS][SELFTEST] ===== END PHASE 7 ACCEPTANCE =====";

// ---------------------------------------------------------------------------
// 13. SCOUT TEAM SELECTION SELF-TEST - the doctrine MUST declare exactly one
//     team per combat squad with tacticalRole "SCOUT". The scout detachment
//     command picks that team; with zero or duplicated SCOUT roles it falls back
//     to TEAM_2 (deterministic), which would differ from the doctrine intent.
// ---------------------------------------------------------------------------
diag_log "[FTCS][SELFTEST] ===== SCOUT ROLE ACCEPTANCE ====";
diag_log format ["[FTCS][SELFTEST] SCOUT doctrineTeamRoles=%1", str (FTCS_Company_Data getOrDefault ["doctrineTeamRoles", "<MISSING>"])];
{
    private _sId = _x;
    private _sSquads = (FTCS_Platoons_Registry getOrDefault [_sId, createHashMap]) getOrDefault ["squads", []];
    {
        if (!isNull _x) then {
            private _sqdId = (FTCS_Groups_Registry_Table getOrDefault [groupId _x, createHashMap]) getOrDefault ["squadId", ""];
            private _scouts = [];
            private _fireteams = 0;
            {
                if (((_y) getOrDefault ["squadId", ""]) isEqualTo _sqdId) then {
                    if ((_y) getOrDefault ["isSquadLeaderGroup", false]) then {
                        // anchor: never a scout
                    } else {
                        _fireteams = _fireteams + 1;
                        if (((_y) getOrDefault ["tacticalRole", ""]) isEqualTo "SCOUT") then { _scouts pushBack _x; };
                    };
                };
            } forEach FTCS_Groups_Registry_Table;
            private _verdict = if (_fireteams == 0) then { "SKIP" }
                else { if (count _scouts == 1) then { "PASS" } else { "FAIL" } };
            diag_log format ["[FTCS][SELFTEST] SCOUT plt %1 squad '%2' fireteams=%3 scoutRole=%4 -> %5",
                _sId, _sqdId, _fireteams, (if (count _scouts == 0) then { "none" } else { _scouts joinString "," }), _verdict];
        };
    } forEach _sSquads;
} forEach (keys FTCS_Platoons_Registry);
diag_log "[FTCS][SELFTEST] ===== END SCOUT ROLE ACCEPTANCE =====";

diag_log format ["FTCS: Master Group Registry initialized (%1 groups registered).", _registeredCount];
true;