/*
    ================================================================================
    File: fn_menuCatalog.sqf
    Module: Menu
    Author: FTCS Team
    Description: DATA ONLY. Declares every menu of the FTCS commanding UI as a
                 pure data tree. No logic, no registry reads, no AI commands.

                 Row layout (params of the native commandingMenu row):
                   0 : label            STRING  ("%1" tokens are substituted by
                                                 fn_menuBuild with the row args)
                   1 : keys             ARRAY   ([2] = fires with key "1")
                   2 : submenu          STRING  ("#USER:FTCS_MENU_..." or "")
                   3 : priority         SCALAR  (-5, project convention)
                   4 : events           ARRAY   ([["expression", <code>]])
                   5 : visible          STRING  ("1")
                   6 : enabled          STRING  ("1"/"0") - fn_menuBuild overrides
                   7 : META             ARRAY   <= FTCS EXTENSION, not read by Arma:
                                                 [payload, gate, reopen, dynamic]
                          payload : STRING  dispatch token, e.g. "PLT:SET_PHASE"
                          gate    : STRING  gate id resolved by fn_menuBuild
                          reopen  : BOOLEAN TRUE -> MouseButtonUp re-opens after click
                          dynamic : STRING  special label/args injection id

                 A row whose backend command does NOT exist is NOT declared here:
                 the menu never shows a button that pretends to work.

                 NAVIGATION ROWS (submenu): they open a CHILD menu and Arma keeps
                 the menu alive ONLY because field 2 (submenu) is NON-EMPTY. Moving
                 the child id into the row expression turns the row into a TERMINAL
                 order: Arma runs the expression and CLOSES the menu, so the child
                 opens and vanishes instantly.
                 What changed is the TARGET: instead of "#USER:<catalog var>" (raw
                 data, static enabled flags, no gates), the row points to
                 "#USER:FTCS_MENU_<child>_Var", the BUILT copy published by
                 fn_menuOpen. Navigation stays engine-driven (menu alive) AND the
                 child arrives already gated, so grey/white is decided by
                 fn_menuGate - never by a static "0" written here.
                 Rule for new rows: to grey a row, its gate lives in fn_menuGate; to
                 change its text, the meta dynamic id (field 7) is used; to hide it,
                 field 5 is set to "0". The catalog stays DATA ONLY.
    Language: Strictly English (Rule 7, Rule 11)

    +-----------------------------------------------------------------------------+
    |                      FTCS MENU CATALOG (data tree)                          |
    +-----------------------------------------------------------------------------+
    |                                                                             |
    |  FTCS_MENU_Root                                                             |
    |    ├── Phase            -> Phase 1 / 2 / 3                                  |
    |    ├── Formations       -> Column/Wedge/Vee/Line/Ech.R/Ech.L/Lock Ground    |
    |    ├── MarchRoute       -> Staggered/L/R/Trail/Compact/Push/Pull/Reset      |
    |    ├── FollowMode       -> REL <-> ABS            (single dynamic row)      |
    |    ├── HaltRejoin       -> HALT / REJOIN KEEP / REJOIN NEW / Regroup         |
    |    ├── PaceTech         -> Pace x3 + Technique x2                           |
    |    ├── PlatoonStance    -> Auto/Up/Middle/Down/Follow                        |
    |    ├── WeaponsControl   -> Hold/Tight/Free                                  |
    |    ├── Scouts           -> 6 screens + Rejoin All                           |
    |    └── SquadHub         -> [1] Scouts Directive, [2..N] squads, Back        |
    |          └── SquadOrders_<n> -> Mark/Move/Hold/Flanks/FallBack/Rejoin +     |
    |                                Formations / Stance                          |
    |                ├── SquadFormations_<n>                                      |
    |                └── SquadStance_<n>                                          |
    +-----------------------------------------------------------------------------+
    ================================================================================
*/

// Expression every actionable row runs. ONE shape for the whole catalog:
// ['FAMILY:CODE[:ARG]'] call FTCS_fnc_menuDispatch;
// The dispatch token carries the command AND its arguments, so the router never
// needs one `case` per squad index (SQD_MOVE_ADVANCE_KEEP_1..4 collapse to one).

// =============================================================================
// ROOT - one row per FAMILY (keeps the root at 11 rows, under the 12-row limit)
// =============================================================================
FTCS_MENU_Root = [
    ["[DEBUG] FTCS - PLATOON COMMAND", false],
    ["1. Operational Phase", [2], "#USER:FTCS_MENU_Phase_Var", -5, [["expression", ""]], "1", "1", ["", "", false, "nav:FTCS_MENU_Phase"]],
    ["2. Platoon Formations", [3], "#USER:FTCS_MENU_Formations_Var", -5, [["expression", ""]], "1", "1", ["", "", false, "nav:FTCS_MENU_Formations"]],
    ["3. March Column & Route", [4], "#USER:FTCS_MENU_MarchRoute_Var", -5, [["expression", ""]], "1", "1", ["", "gate_march", false, "nav:FTCS_MENU_MarchRoute"]],
    ["4. Follow Mode: ABSOLUTE (Fixed Compass)", [5], "", -5, [["expression", "['PLT:MODE_TOGGLE'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:MODE_TOGGLE", "gate_follow_mode", false, "followmode"]],
    ["5. Halt & Rejoin", [6], "#USER:FTCS_MENU_HaltRejoin_Var", -5, [["expression", ""]], "1", "1", ["", "", false, "nav:FTCS_MENU_HaltRejoin"]],
    ["6. Pace & Movement Technique", [7], "#USER:FTCS_MENU_PaceTech_Var", -5, [["expression", ""]], "1", "1", ["", "gate_march", false, "nav:FTCS_MENU_PaceTech"]],
    ["7. Platoon Stance", [8], "#USER:FTCS_MENU_PlatoonStance_Var", -5, [["expression", ""]], "1", "1", ["", "", false, "nav:FTCS_MENU_PlatoonStance"]],
    ["8. Weapons Control", [9], "#USER:FTCS_MENU_WeaponsControl_Var", -5, [["expression", ""]], "1", "1", ["", "", false, "nav:FTCS_MENU_WeaponsControl"]],
    ["9. Platoon Scouts", [10], "#USER:FTCS_MENU_Scouts_Var", -5, [["expression", ""]], "1", "1", ["", "gate_scout", false, "nav:FTCS_MENU_Scouts"]],
    ["10. Squad Directives", [11], "#USER:FTCS_MENU_SquadHub_Var", -5, [["expression", ""]], "1", "1", ["", "gate_squads", false, "nav:FTCS_MENU_SquadHub"]]
];

// =============================================================================
// 1. OPERATIONAL PHASE TRANSITION
// =============================================================================
FTCS_MENU_Phase = [
    ["Operational Phase Transition", false],
    ["1. Set Phase 1: APPROACH (Traveling & Security)", [2], "", -5, [["expression", "['PLT:SET_PHASE:1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:SET_PHASE:1", "gate_phase1", true, ""]],
    ["2. Set Phase 2: CONTACT LIKELY / OVERWATCH", [3], "", -5, [["expression", "['PLT:SET_PHASE:2'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:SET_PHASE:2", "gate_phase2", true, ""]],
    ["3. Set Phase 3: COMBAT & ASSAULT (Fire & Maneuver)", [4], "", -5, [["expression", "['PLT:SET_PHASE:3'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:SET_PHASE:3", "gate_phase3", true, ""]]
];

// =============================================================================
// 2. PLATOON FORMATIONS (the ACTIVE formation stays visible but greyed)
// =============================================================================
FTCS_MENU_Formations = [
    ["Platoon Formations", false],
    ["1. Platoon Column (Trail / Road March)", [2], "", -5, [["expression", "['PLT:FORM:COLUMN'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:FORM:COLUMN", "gate_form_COLUMN", false, ""]],
    ["2. Platoon Wedge (Security / Cross-country)", [3], "", -5, [["expression", "['PLT:FORM:WEDGE'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:FORM:WEDGE", "gate_form_WEDGE", false, ""]],
    ["3. Platoon Vee (Flexible Front)", [4], "", -5, [["expression", "['PLT:FORM:VEE'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:FORM:VEE", "gate_form_VEE", false, ""]],
    ["4. Platoon Line (Full Frontage Assault)", [5], "", -5, [["expression", "['PLT:FORM:LINE'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:FORM:LINE", "gate_form_LINE", false, ""]],
    ["5. Platoon Echelon Right (Right Flank Refused)", [6], "", -5, [["expression", "['PLT:FORM:ECHELON_RIGHT'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:FORM:ECHELON_RIGHT", "gate_form_ECHELON_RIGHT", false, ""]],
    ["6. Platoon Echelon Left (Left Flank Refused)", [7], "", -5, [["expression", "['PLT:FORM:ECHELON_LEFT'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:FORM:ECHELON_LEFT", "gate_form_ECHELON_LEFT", false, ""]],
    ["7. Adopt Ground Layout (Lock Positions)", [8], "", -5, [["expression", "['PLT:FORM:LOCK_GROUND'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:FORM:LOCK_GROUND", "gate_not_halted", false, ""]]
];

// =============================================================================
// 3. MARCH COLUMN & ROUTE (exports): layout rows + edge-margin rows
// =============================================================================
FTCS_MENU_MarchRoute = [
    ["March Column & Route", false],
    ["1. Staggered Column (Dual Shoulder)", [2], "", -5, [["expression", "['ROAD:PLT_ROAD_COLUMN'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["ROAD:PLT_ROAD_COLUMN", "gate_layout_STAGGERED_ROAD", false, ""]],
    ["2. Column Left (Single Shoulder)", [3], "", -5, [["expression", "['ROAD:ROAD_COLUMN_LEFT'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["ROAD:ROAD_COLUMN_LEFT", "gate_layout_LEFT", false, ""]],
    ["3. Column Right (Single Shoulder)", [4], "", -5, [["expression", "['ROAD:ROAD_COLUMN_RIGHT'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["ROAD:ROAD_COLUMN_RIGHT", "gate_layout_RIGHT", false, ""]],
    ["4. Leader Trail Column (Follow My Track)", [5], "", -5, [["expression", "['ROAD:PLT_TRAIL_COLUMN'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["ROAD:PLT_TRAIL_COLUMN", "gate_layout_STAGGERED_TRAIL", false, ""]],
    ["5. Compact Column (Close Ranks)", [6], "", -5, [["expression", "['ROAD:PLT_ROAD_COMPACT'] call FTCS_fnc_menuDispatch;"]], "1", "0", ["ROAD:PLT_ROAD_COMPACT", "gate_compact", false, ""]],
    ["6. Push Out From Road (+3m)", [7], "", -5, [["expression", "['ROAD:ROAD_EDGE_PUSH'] call FTCS_fnc_menuDispatch;"]], "1", "0", ["ROAD:ROAD_EDGE_PUSH", "gate_edge_push", false, ""]],
    ["7. Pull In To Road (-3m)", [8], "", -5, [["expression", "['ROAD:ROAD_EDGE_PULL'] call FTCS_fnc_menuDispatch;"]], "1", "0", ["ROAD:ROAD_EDGE_PULL", "gate_edge_pull", false, ""]],
    ["8. Return To Road (Reset)", [9], "", -5, [["expression", "['ROAD:ROAD_EDGE_RESET'] call FTCS_fnc_menuDispatch;"]], "1", "0", ["ROAD:ROAD_EDGE_RESET", "gate_edge_pull", false, ""]]
];

// =============================================================================
// 4. HALT & REJOIN (fixed 4 rows: 3 real states cannot be collapsed)
// =============================================================================
FTCS_MENU_HaltRejoin = [
    ["Halt & Rejoin", false],
    ["1. HALT - Freeze Platoon (Lieutenant Explores)", [2], "", -5, [["expression", "['PLT:HALT'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:HALT", "gate_not_halted", true, ""]],
    ["2. REJOIN - Re-group (Arrive on Halt Facing)", [3], "", -5, [["expression", "['PLT:REJOIN_KEEP'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:REJOIN_KEEP", "gate_halted", true, ""]],
    ["3. REJOIN - Re-group (Lieutenant Current Facing)", [4], "", -5, [["expression", "['PLT:REJOIN_NEW'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:REJOIN_NEW", "gate_halted", true, ""]],
    ["4. Regroup on Commander (Follow Me)", [5], "", -5, [["expression", "['PLT:FOLLOW_COMMANDER'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:FOLLOW_COMMANDER", "gate_unit", false, ""]]
];

// =============================================================================
// 5. PACE & MOVEMENT TECHNIQUE
// =============================================================================
FTCS_MENU_PaceTech = [
    ["Pace & Movement Technique", false],
    ["1. Normal March Pace", [2], "", -5, [["expression", "['PLT:PACE_NORMAL'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:PACE_NORMAL", "gate_speed_NORMAL", false, ""]],
    ["2. Limited (Slow / Patrol) Pace", [3], "", -5, [["expression", "['PLT:PACE_LIMITED'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:PACE_LIMITED", "gate_speed_LIMITED", false, ""]],
    ["3. Fast / Rush Pace", [4], "", -5, [["expression", "['PLT:PACE_FAST'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:PACE_FAST", "gate_speed_FULL", false, ""]],
    ["4. Traveling (Standard March)", [5], "", -5, [["expression", "['PLT:TECH_TRAVELING'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:TECH_TRAVELING", "gate_tech_CROSS_COUNTRY", false, ""]],
    ["5. Traveling Overwatch (Cautious Advance)", [6], "", -5, [["expression", "['PLT:TECH_TRAVELING_OVERWATCH'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:TECH_TRAVELING_OVERWATCH", "gate_tech_OVERWATCH", false, ""]]
];

// =============================================================================
// 6. PLATOON TACTICAL STANCE
// =============================================================================
FTCS_MENU_PlatoonStance = [
    ["Platoon Tactical Stance", false],
    ["1. Auto Stance (Combat Default)", [2], "", -5, [["expression", "['PLT:STANCE_AUTO'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:STANCE_AUTO", "gate_stance_AUTO", false, ""]],
    ["2. Force Stand Up (Rush / Fast Bound)", [3], "", -5, [["expression", "['PLT:STANCE_UP'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:STANCE_UP", "gate_stance_FORCE_UP", false, ""]],
    ["3. Force Crouch (Cautious Advance)", [4], "", -5, [["expression", "['PLT:STANCE_MIDDLE'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:STANCE_MIDDLE", "gate_stance_FORCE_MIDDLE", false, ""]],
    ["4. Force Prone (Take Cover / Pin Down)", [5], "", -5, [["expression", "['PLT:STANCE_DOWN'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:STANCE_DOWN", "gate_stance_FORCE_DOWN", false, ""]],
    ["5. Follow Commander Stance (Mirror)", [6], "", -5, [["expression", "['PLT:STANCE_FOLLOW'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:STANCE_FOLLOW", "gate_stance_FOLLOW_COMMANDER_STANCE", false, ""]]
];

// =============================================================================
// 7. WEAPONS CONTROL
// =============================================================================
FTCS_MENU_WeaponsControl = [
    ["Weapons Control Status", false],
    ["1. Weapons Hold (Do Not Fire)", [2], "", -5, [["expression", "['PLT:WCS_HOLD'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:WCS_HOLD", "gate_roe_HOLD_FIRE", false, ""]],
    ["2. Weapons Tight (Confirmed Hostile Only)", [3], "", -5, [["expression", "['PLT:WCS_TIGHT'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:WCS_TIGHT", "gate_roe_FIRE_IF_FIRED_UPON", false, ""]],
    ["3. Weapons Free (Engage on Sight)", [4], "", -5, [["expression", "['PLT:WCS_FREE'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["PLT:WCS_FREE", "gate_roe_FIRE_AT_WILL", false, ""]]
];

// =============================================================================
// 8. PLATOON SCOUTS (7 order rows; the label names the providing squad)
// =============================================================================
FTCS_MENU_Scouts = [
    ["Platoon Scout Directives", false],
    ["1. Deploy Left Flank Screen", [2], "", -5, [["expression", "['SCOUT:PLT_SCOUT_FLANK_L'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SCOUT:PLT_SCOUT_FLANK_L", "gate_scout_11", true, "scout_11"]],
    ["2. Deploy Right Flank Screen", [3], "", -5, [["expression", "['SCOUT:PLT_SCOUT_FLANK_R'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SCOUT:PLT_SCOUT_FLANK_R", "gate_scout_12", true, "scout_12"]],
    ["3. Deploy Front Left Screen", [4], "", -5, [["expression", "['SCOUT:PLT_SCOUT_FRONT_L'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SCOUT:PLT_SCOUT_FRONT_L", "gate_scout_7", true, "scout_7"]],
    ["4. Deploy Front Center Screen", [5], "", -5, [["expression", "['SCOUT:PLT_SCOUT_FRONT_C'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SCOUT:PLT_SCOUT_FRONT_C", "gate_scout_6", true, "scout_6"]],
    ["5. Deploy Front Right Screen", [6], "", -5, [["expression", "['SCOUT:PLT_SCOUT_FRONT_R'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SCOUT:PLT_SCOUT_FRONT_R", "gate_scout_8", true, "scout_8"]],
    ["6. Deploy Rear Reserve Screen", [7], "", -5, [["expression", "['SCOUT:PLT_SCOUT_REAR'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SCOUT:PLT_SCOUT_REAR", "gate_scout_5", true, "scout_5"]],
    ["7. Rejoin All Platoon Scouts", [8], "", -5, [["expression", "['SCOUT:PLT_SCOUT_REJOIN_ALL'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SCOUT:PLT_SCOUT_REJOIN_ALL", "gate_scout_any", true, ""]]
];

// =============================================================================
// 9. SQUAD HUB (row 1 = Scouts Directive, rows 2..N = real squads, last = Back)
//    Rows 2..N are REBUILT per opening from the registry by fn_menuBuild:
//    a squad that does not exist is never painted.
// =============================================================================
FTCS_MENU_SquadHub = [
    ["Squad & Scout Directives", false],
    ["1. Scouts Directive", [2], "#USER:FTCS_MENU_Scouts_Var", -5, [["expression", ""]], "1", "1", ["", "", false, "nav:FTCS_MENU_Scouts"]],
    ["2. [SQUAD_SLOT_1]", [3], "#USER:FTCS_MENU_SquadOrders_1", -5, [["expression", ""]], "1", "1", ["", "gate_squad_1", true, "squad_row:1"]],
    ["3. [SQUAD_SLOT_2]", [4], "#USER:FTCS_MENU_SquadOrders_2", -5, [["expression", ""]], "1", "1", ["", "gate_squad_2", true, "squad_row:2"]],
    ["4. [SQUAD_SLOT_3]", [5], "#USER:FTCS_MENU_SquadOrders_3", -5, [["expression", ""]], "1", "1", ["", "gate_squad_3", true, "squad_row:3"]],
    ["5. [SQUAD_SLOT_4]", [6], "#USER:FTCS_MENU_SquadOrders_4", -5, [["expression", ""]], "1", "1", ["", "gate_squad_4", true, "squad_row:4"]]
];

// =============================================================================
// 10. SQUAD ORDERS (one template per squad index 1..4, built by fn_menuBuild)
//     Row 1  : Mark Target (greyed when a target is already marked)
//     Rows 2-4: Move to target (greyed when there is NO marked target)
//     Row 5  : Hold & Defend
//     Rows 6-7: Open Flank L/R
//     Row 8  : Fall Back 15m
//     Row 9  : Rejoin Platoon Formation
//     Row 10 : Squad Formation  -> submenu
//     Row 11 : Squad Stance     -> submenu
// =============================================================================
FTCS_MENU_SquadOrders_Template = [
    ["Squad Orders", false],
    ["1. Mark Target at Crosshair", [2], "", -5, [["expression", "['SQD:TARGET_MARK:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQD:TARGET_MARK:%1", "gate_no_target", true, ""]],
    ["2. Move to Target & Hold", [3], "", -5, [["expression", "['SQD:MOVE_DETACH:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQD:MOVE_DETACH:%1", "gate_has_target", false, ""]],
    ["3. Move to Target & Defend", [4], "", -5, [["expression", "['SQD:MOVE_DEFEND:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQD:MOVE_DEFEND:%1", "gate_has_target", false, ""]],
    ["4. Move to Target & Keep Formation", [5], "", -5, [["expression", "['SQD:MOVE_KEEP:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQD:MOVE_KEEP:%1", "gate_has_target", false, ""]],
    ["5. Hold Current Position / Defend", [6], "", -5, [["expression", "['SQD:DEFEND:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQD:DEFEND:%1", "gate_always", false, ""]],
    ["6. Open Flank Left", [7], "", -5, [["expression", "['SQD:FLANK_L:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQD:FLANK_L:%1", "gate_flank_L", false, ""]],
    ["7. Open Flank Right", [8], "", -5, [["expression", "['SQD:FLANK_R:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQD:FLANK_R:%1", "gate_flank_R", false, ""]],
    ["8. Fall Back (15m)", [9], "", -5, [["expression", "['SQD:FALL_BACK:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQD:FALL_BACK:%1", "gate_always", false, ""]],
    ["9. Rejoin Platoon Formation", [10], "", -5, [["expression", "['SQD:REJOIN_FORMATION:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQD:REJOIN_FORMATION:%1", "gate_not_following", false, ""]],
    ["10. Squad Formation", [11], "#USER:FTCS_MENU_SquadFormations_%1_Var", -5, [["expression", ""]], "1", "1", ["", "gate_always", false, "nav:FTCS_MENU_SquadFormations_%1"]],
    ["11. Squad Stance", [12], "#USER:FTCS_MENU_SquadStance_%1_Var", -5, [["expression", ""]], "1", "1", ["", "gate_always", false, "nav:FTCS_MENU_SquadStance_%1"]]
];

// =============================================================================
// 11. SQUAD FORMATIONS (per squad index)
// =============================================================================
FTCS_MENU_SquadFormations_Template = [
    ["Squad Formations", false],
    ["1. Squad Column", [2], "", -5, [["expression", "['SQDF:COLUMN:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQDF:COLUMN:%1", "gate_sqdform_COLUMN", false, ""]],
    ["2. Squad Line", [3], "", -5, [["expression", "['SQDF:LINE:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQDF:LINE:%1", "gate_sqdform_LINE", false, ""]],
    ["3. Squad File", [4], "", -5, [["expression", "['SQDF:FILE:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQDF:FILE:%1", "gate_sqdform_FILE", false, ""]],
    ["4. Squad Wedge", [5], "", -5, [["expression", "['SQDF:WEDGE:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQDF:WEDGE:%1", "gate_sqdform_WEDGE", false, ""]]
];

// =============================================================================
// 12. SQUAD STANCE (per squad index)
// =============================================================================
FTCS_MENU_SquadStance_Template = [
    ["Squad Tactical Stance", false],
    ["1. Auto Stance (Combat Default)", [2], "", -5, [["expression", "['SQDS:AUTO:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQDS:AUTO:%1", "gate_sqdstance_AUTO", false, ""]],
    ["2. Force Stand Up", [3], "", -5, [["expression", "['SQDS:UP:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQDS:UP:%1", "gate_sqdstance_FORCE_UP", false, ""]],
    ["3. Force Crouch", [4], "", -5, [["expression", "['SQDS:MIDDLE:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQDS:MIDDLE:%1", "gate_sqdstance_FORCE_MIDDLE", false, ""]],
    ["4. Force Prone (Take Cover)", [5], "", -5, [["expression", "['SQDS:DOWN:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQDS:DOWN:%1", "gate_sqdstance_FORCE_DOWN", false, ""]],
    ["5. Follow Commander Stance (Mirror)", [6], "", -5, [["expression", "['SQDS:FOLLOW:%1'] call FTCS_fnc_menuDispatch;"]], "1", "1", ["SQDS:FOLLOW:%1", "gate_sqdstance_FOLLOW_COMMANDER_STANCE", false, ""]]
];

// =============================================================================
// 13. MENU TREE INDEX (parent id -> CHILDREN ids)
// =============================================================================
// fn_menuOpen reads this map to PRE-BUILD every child of the menu it is about to
// show: Arma opens a row's `submenu` instantly and never calls a function on the
// way, so a child must already exist (built + gated) before its parent appears.
// Adding a submenu = one line here; forgetting it only means the child is empty
// the first time it is opened from the parent (fn_menuOpen logs a *** CHILD BUILD
// line in that case, so the omission is visible in the RPT).
FTCS_MENU_Parents = createHashMapFromArray [
    ["FTCS_MENU_Root", [
        "FTCS_MENU_Phase", "FTCS_MENU_Formations", "FTCS_MENU_MarchRoute",
        "FTCS_MENU_HaltRejoin", "FTCS_MENU_PaceTech", "FTCS_MENU_PlatoonStance",
        "FTCS_MENU_WeaponsControl", "FTCS_MENU_Scouts", "FTCS_MENU_SquadHub"
    ]],
    ["FTCS_MENU_SquadHub", [
        "FTCS_MENU_Scouts",
        "FTCS_MENU_SquadOrders_1", "FTCS_MENU_SquadOrders_2",
        "FTCS_MENU_SquadOrders_3", "FTCS_MENU_SquadOrders_4"
    ]],
    ["FTCS_MENU_SquadOrders_1", ["FTCS_MENU_SquadFormations_1", "FTCS_MENU_SquadStance_1"]],
    ["FTCS_MENU_SquadOrders_2", ["FTCS_MENU_SquadFormations_2", "FTCS_MENU_SquadStance_2"]],
    ["FTCS_MENU_SquadOrders_3", ["FTCS_MENU_SquadFormations_3", "FTCS_MENU_SquadStance_3"]],
    ["FTCS_MENU_SquadOrders_4", ["FTCS_MENU_SquadFormations_4", "FTCS_MENU_SquadStance_4"]]
];

true
