# FTCS - Especificación Completa de la Estructura de Datos (Architecture & Data Model)

> **DOCUMENTO VIVO DE ARQUITECTURA — PUNTO CERO:** Esta es la referencia técnica formal y visual del modelo de datos de FTCS.

---

## 0. DIRECTRIZ OBLIGATORIA: ENUMS Y ESTADOS DEL REGISTRO (DIRECTRIZ ENUM-REGISTRY)

**PROHIBIDO introducir un nuevo valor de ENUM/estado en el registro sin cumplir esta lista completa. Aplica a TODO campo ENUM de `FTCS_Groups_Registry_Table`, `FTCS_Platoons_Registry` y cualquier registro añadido en el futuro.**

Antes de escribir por primera vez un valor nuevo (ej. un nuevo `movingMode`, `orderState`, `stance`, `awareMode`, `teamAttachment`, `movementType`...):

1. **DOCUMENTAR AQUÍ, EN EL MISMO CAMBIO:** añadir el valor a la lista del campo correspondiente en este documento (secciones 3 y 3-bis), con su semántica, escritor único y consumidores.
2. **SINCRONIZAR TODAS LAS LISTAS PARALELAS:** si el mismo enum se valida en más sitios (`init.sqf`, `fn_registryInit.sqf`, validadores de modo, menús de órdenes...), actualizarlos TODOS en el mismo cambio.
3. **VERIFICAR CONSUMIDORES CON GREP ANTES DE ESCRIBIR:** un consumidor que compara contra la lista anterior (`movingMode == "HALT"`, `in [...]`) rompe el contrato en runtime con un valor nuevo. Grep del valor y de sus comparaciones es OBLIGATORIO.
4. **REUTILIZAR ANTES QUE CREAR:** si existe un valor documentado con la semántica necesaria (ej. `"HALT"`), usarlo; inventar sinónimos (`"HALT_FREEZE"`) crea estados paralelos no reconocidos por los consumidores.
5. **PROHIBIDO usar nombres doctrinales como identificadores:** el nombre doctrinal ("1st Rifle Squad", "Able Team (Scouts)") es SOLO representación histórica para el jugador. NUNCA debe usarse para indexar, buscar o comparar en código. Las claves internas son las del registro (`groupIds`, IDs `SQD_X_Y`, campos stampados como `parentSquadGroup`).

---

> **Referencia técnica formal y visual del modelo de datos de FTCS (secciones 1 a 6).**
> Si se modifican, añaden o eliminan campos, tablas de hash o enumeraciones en el código backend (`FTCS_Company_Data`, `FTCS_Groups_Registry_Table`, plantillas doctrinales o registros auxiliares), **este documento debe ser actualizado obligatoriamente** para mantener sincronizada la fuente de verdad.

---

## 1. Mapa Global de Puntos de Entrada (`missionNamespace`)

En el backend de FTCS, toda la simulación se gobierna a través de tres estructuras de datos centrales en memoria:

```
missionNamespace
├── FTCS_Config                     (HashMap: Parámetros de misión y doctrina activa)
├── FTCS_Company_Data               (HashMap: Árbol Jerárquico Táctico de Compañía - ORBAT)
├── FTCS_Groups_Registry_Table      (HashMap: Registro Plano de Estados y Físicas de Grupos)
├── FTCS_Platoons_Registry          (HashMap: Estado por pelotón, clave NUMBER = ID pelotón)
│     ├── "squads"          : ARRAY de GROUP (anclas de escuadra, sembradas por fn_registryInit)
│     ├── "platoonGroup"    : GROUP  (grupo de mando del HQ de pelotón)
│     ├── "orderState"      : "MARCH" | "HALTED" | "REJOINING"
│     ├── "haltSnapshotLeaderPos" / "haltFacing" : snapshot de HALT
│     ├── "leaderUnit"      : OBJECT (PLT_<N>_LEADER: jugador o IA; válido aunque esté FUERA de todo grupo)
│     ├── "leaderGroup"     : GROUP  (grupo del teniente; grpNull si está desprendido)
│     ├── "peerOnly"        : BOOLEAN (TRUE si el teniente NO está dentro de leaderGroup - modo jugador)
│     │
│     │  --- FASE 2: ESTADO DE PELOTÓN (antes solo en FTCS_Company_Data) ---
│     ├── "currentPhase"     : SCALAR (0 = DEPLOYMENT/INSPECTION, 1 = APPROACH, 2 = OVERWATCH, 3 = COMBAT)
│     │     Escritor: fn_platoonSetOperationalPhase vía FTCS_fnc_registrySetPlatoon.
│     │     Se siembra desde la doctrina; global espejo: FTCS_Platoon_Phase_<N>.
│     ├── "movementTechnique" : ENUM STRING "CROSS_COUNTRY" | "ROAD_COLUMN" | "TRAIL_FILE"
│     │     Escritor: FTCS_fnc_registrySetPlatoon (espejo al árbol durante la migración)
│     ├── "roadPath"         : ARRAY de [posATL, tangentDir, roadWidth] (polilínea activa)
│     ├── "roadAnchor"       : HASHMAP (ancla de marcha por carretera del pelotón)
│     ├── "trailAnchor"      : HASHMAP (ancla de columna de estela del pelotón)
│     ├── "doctrineFormationSlots" : HASHMAP slotIdx (0..12) -> clave doctrinal (PLANTILLA)
│     │     INMUTABLE. Se siembra UNA vez en fn_applyDoctrine desde la composición.
│     │     Nunca se vuelve a escribir. Sirve para RESETEAR el mapa vivo a la doctrina
│     │     (Fase 8 futura: "volver a la formación doctrinal").
│     └── "formationSlots"   : HASHMAP slotIdx (0..12) -> clave doctrinal de squad/team
│           VIVO / MUTABLE. Se siembra desde la plantilla al arrancar y se MODIFICA en
│           runtime: scouts desprendidos (5/6/7/8/11/12), futura reordenación manual de
│           escuadrones por el jugador, futura gestión de bajas.
│           Se COPIA (+), no se referencia, para que las reasignaciones runtime no
│           muten silenciosamente la plantilla inmutable.
│           ÚNICO campo que leen los consumidores runtime (fn_formationsApplyPlatoonOrder).
│
│     >> FUENTE DE VERDAD: el registro. El árbol mantiene un ESPEJO temporal
│        (mantenido por FTCS_fnc_registrySetPlatoon) hasta completar la Fase 3,
│        en la que los consumidores dejarán de leer FTCS_Company_Data.
├── FTCS_Platoon_Phase_1 .. 4       (NUMBER: Fase operacional activa individual por pelotón: 1, 2 o 3)
├── FTCS_Platoon_Follow_Mode        (STRING: Modo de seguimiento activo: "FOLLOWING_COMMANDER_REL" | "FOLLOWING_COMMANDER_ABS")
├── FTCS_Platoon_Fixed_Abs_Dir      (NUMBER: Rumbo fijo congelado en brújula [0-360] para seguimiento y debug en modo absoluto)
├── FTCS_Road_Anchor_PLT_1 .. 4        (HashMap: Ancla de marcha por carretera por pelotón: anchorPos, advanceDir,
│                                        roadPath, headDist, lastAnchorMovePos, edgeMarginSteps, columnLayout, generation)
├── FTCS_Road_Anchor_Gen_PLT_1 .. 4    (NUMBER: Generación del ancla de road march — cada orden nueva invalida hilos previos)
├── FTCS_Trail_Anchor_PLT_1 .. 4       (HashMap: Ancla de columna de estela por pelotón: anchorPos,
│                                        trailPath [ARRAY de [posATL, dir] — estela grabada del líder],
│                                        headDist [NUMBER — arco del líder], maxTrailOffset [NUMBER,
│                                        INFORMATIVO: el TRIM ya no corta contra él],
│                                        trailMinSeatArc [NUMBER — arco ABSOLUTO del punto más antiguo
│                                        que la columna ocupa todavía; -1 = la cola no ha hablado y el
│                                        TRIM no recorta. Escritor: fn_formationsTrailQueueSync;
│                                        lector: fn_trailTrimToArc, que lo desplaza al recortar],
│                                        trailTailArc [NUMBER — offset más profundo con asiento este
│                                        tick, telemetría], trailMaxOffset [NUMBER — offset más
│                                        profundo de la columna INCLUYENDO los grupos que aún
│                                        esperan; suelo DURO del TRIM], trimCushion [NUMBER — metros
│                                        conservados detrás de trailMinSeatArc, default 100],
│                                        trimEvents [NUMBER — nº de TRIM ejecutados],
│                                        lastAnchorMovePos [ATL], generation [NUMBER];
│                                        registro en FTCS_Groups_Registry_Table: trailOffsetDist / trailTargetPos /
│                                        trailTangentDir / movingMode "FOLLOWING_TRAIL")
├── FTCS_Trail_Gen_PLT_1 .. 4          (NUMBER: Generación de trail column — cada orden nueva invalida hilos previos)
└── FTCS_Debug_Mode                 (BOOLEAN: Centinela de depuración, true para telemetría visual y slots en mapa)
```

---

## 2. Árbol Jerárquico Táctico: `FTCS_Company_Data`

Este árbol define la jerarquía militar y el orden de batalla (ORBAT) de la fuerza, desde el Puesto de Mando de Compañía hasta cada escuadra, sus sub-equipos (*fireteams*) y los soldados con roles asignados.

```
FTCS_Company_Data (HashMap)
│
├── "companyID"          : STRING           -> Código táctico de la compañía (ej. "CO_E", "CO_A", "CO_C")
├── "isMechanized"       : BOOLEAN          -> true / false
├── "transportAsset"     : STRING           -> Classname de vehículo orgánico o ""
├── "selectedIDs"        : ARRAY of STRINGS -> Elementos bajo selección de mando (ej. ["ALL"], ["SQD_1_1"])
├── "selectedType"       : ENUM STRING      -> Ámbito de selección: "COMPANY" | "PLATOON" | "SQUAD" | "VEHICLE"
│
├── "companyHQ"          : HashMap (Puesto de Mando de Compañía)
│     ├── "group"        : GROUP (Arma 3)   -> Objeto del grupo de mando SQUAD_0_0
│     ├── "leader"       : OBJECT (Unit)    -> Oficial al mando (Capitán / HQ_CO_CAPTAIN)
│     ├── "name"         : STRING           -> Nombre doctrinal (ej. "Company HQ")
│     ├── "units"        : ARRAY of OBJECTS -> Soldados asignados a SQUAD_0_0
│     │
│     ├── "assignedRoles": HashMap (Mapeo directo de roles individuales del Estado Mayor)
│     │     ├── "HQ_CO_CAPTAIN"     : OBJECT -> Capitán (Company Commander)
│     │     ├── "HQ_XO_LIEUTENANT"  : OBJECT -> 1st Lieutenant (Executive Officer)
│     │     ├── "HQ_FIRST_SERGEANT" : OBJECT -> First Sergeant (Sargento Primero de Compañía)
│     │     ├── "HQ_COMM_SERGEANT"  : OBJECT -> Communications Sergeant
│     │     ├── "HQ_RADIO_OPERATOR" : OBJECT -> RTO / Radio Operador SCR-300
│     │     ├── "HQ_MESSENGER_1..6" : OBJECT -> Estafetas / Mensajeros a pie (1 al 6)
│     │     └── "HQ_MEDIC"          : OBJECT -> Sanitario de Compañía
│     │
│     └── "tacticalTeams": HashMap (Sub-equipos de SQUAD_0_0)
│           ├── "SQD_0_0_TEAM_1" : [name: "Command Element", group: Group, leader: Object, units: Array]
│           └── "SQD_0_0_TEAM_2" : [name: "Signals & Liaison", group: Group, leader: Object, units: Array]
│
├── "squadsRegistry"     : HashMap (Directorio plano de todas las escuadras: "SQD_X_Y" -> Squad Data)
│
└── "platoons"           : HashMap (Colección de Pelotones: "PLT_0" a "PLT_4")
      │
      ├── "PLT_0" : Pelotón de Mando (Apunta internamente a la estructura de Company HQ)
      │
      └── "PLT_1" .. "PLT_4" : HashMap (Pelotones Tácticos de Combate y Apoyo)
            ├── "name"              : STRING      -> Nombre semántico (ej. "1st Rifle Platoon", "Weapons Platoon")
            ├── "currentPhase"      : NUMBER      -> Fase operacional activa del pelotón (1: APPROACH, 2: OVERWATCH, 3: COMBAT)
            ├── "movementTechnique" : STRING      -> "CROSS_COUNTRY" (táctico a campo través) | "ROAD_COLUMN" (carretera) | "TRAIL_FILE"
            ├── "roadPath"          : ARRAY       -> Polilínea de carretera activa [[posATL, tangentDir, roadWidth], ...] o []
            ├── "isMechanized"      : BOOLEAN     -> true / false
            ├── "transportAsset"    : STRING      -> Classname de transporte de pelotón o ""
            ├── "squads"            : ARRAY of ID -> Lista de IDs de escuadras: ["SQD_1_0", "SQD_1_1", "SQD_1_2", "SQD_1_3"]
            ├── "formationSlots"    : HashMap     -> Mapeo pre-resuelto de slots doctrinales (Slot 0..12 -> ID escuadra/team)
            │
            └── "parsedSquads"   : HashMap (Escuadras resueltas en el motor)
                  │
                  ├── "SQD_X_0" : HashMap (Platoon Leadership HQ Slot)
                  │     ├── "name"          : STRING   -> "HQ Squad"
                  │     ├── "platoonID"     : STRING   -> "PLT_X"
                  │     ├── "group"         : GROUP    -> Grupo de mando (SQUAD_X_0_TEAM_1)
                  │     ├── "leader"        : OBJECT   -> Teniente (PLT_X_LEADER)
                  │     ├── "assignedRoles" : HashMap  -> [PLT_X_LEADER, PLT_X_SERGEANT, PLT_X_RADIO_OPERATOR, PLT_X_RUNNER, PLT_X_MEDIC, PLT_X_GUIDE]
                  │     └── "tacticalTeams" : HashMap (Sub-equipos de Platoon HQ)
                  │           ├── "SQD_X_0_TEAM_1" -> [name: "Command Element", leader: Teniente, units: [Teniente, RTO]]
                  │           ├── "SQD_X_0_TEAM_2" -> [name: "Support Element", leader: Sargento Plt, units: [Sargento, Runner, Medic]]
                  │           └── "SQD_X_0_TEAM_3" -> [name: "Guide & Security Element", leader: Guía Plt, units: [Guía, Estafeta/Seguridad]]
                  │
                  ├── "SQD_X_1" .. "SQD_X_3" : HashMap (Escuadras de Fusileros con Multi-Team)
                  │     ├── "name"          : STRING   -> "1st Rifle Squad", "2nd Rifle Squad", etc.
                  │     ├── "platoonID"     : STRING   -> "PLT_X"
                  │     ├── "isUnified"     : false    -> Tiene sub-equipos tácticos (Teams)
                  │     ├── "leader"        : OBJECT   -> Squad Leader (SQD_X_Y_LEADER)
                  │     │
                  │     └── "tacticalTeams" : HashMap (Equipos de Combate / Fireteams)
                  │           │
                  │           ├── "SQD_X_Y_TEAM_1" : HashMap (Punta / Recon)
                  │           │     ├── "name"         : STRING   -> "Able Team (Scouts)"
                  │           │     ├── "parentSquad"  : STRING   -> "SQD_X_Y"
                  │           │     ├── "type"         : STRING   -> "TEAM_1"
                  │           │     ├── "tacticalRole" : STRING   -> "ASSAULT" | "POINT" | "RECON"
                  │           │     ├── "group"        : GROUP    -> Grupo de Arma 3 (SQUAD_X_Y_TEAM_1)
                  │           │     ├── "leader"       : OBJECT   -> Squad Leader
                  │           │     └── "units"        : ARRAY    -> [Squad Leader, Scout 1, Scout 2]
                  │           │
                  │           ├── "SQD_X_Y_TEAM_2" : HashMap (Base de Fuego)
                  │           │     ├── "name"         : STRING   -> "Baker Team (Base of Fire)"
                  │           │     ├── "tacticalRole" : STRING   -> "SUPPORT"
                  │           │     ├── "group"        : GROUP    -> Grupo de Arma 3 (SQUAD_X_Y_TEAM_2)
                  │           │     └── "units"        : ARRAY    -> [BAR Gunner, Assistant, Ammo Bearer]
                  │           │
                  │           └── "SQD_X_Y_TEAM_3" : HashMap (Maniobra y Asalto)
                  │                 ├── "name"         : STRING   -> "Charlie Team (Maneuver)"
                  │                 ├── "tacticalRole" : STRING   -> "ASSAULT"
                  │                 ├── "group"        : GROUP    -> Grupo de Arma 3 (SQUAD_X_Y_TEAM_3)
                  │                 └── "units"        : ARRAY    -> [Assist Squad Lead, 2x Grenadiers, Riflemen, Medic]
                  │
                  └── "SQD_X_4" (o SQD_4_1..4) : HashMap (Escuadra Unificada de Apoyo Pesado / Mortero / MG)
                        ├── "name"          : STRING   -> "1st Mortar Section", "1st Machine Gun Section"
                        ├── "platoonID"     : STRING   -> "PLT_X"
                        ├── "isUnified"     : true     -> Bypassea la división en teams (opera como un único grupo)
                        ├── "group"         : GROUP    -> Grupo unificado de Arma 3 (ej. SQUAD_4_1_TEAM_1)
                        ├── "leader"        : OBJECT   -> Cabo / Sargento de dotación
                        └── "units"         : ARRAY    -> [Leader, Gunner M2, Assistant, 2x Ammo Bearers]
```

---

## 3. Registro Plano de Físicas y Máquinas de Estado: `FTCS_Groups_Registry_Table`

Mientras que `FTCS_Company_Data` representa la jerarquía militar, esta tabla es un **directorio plano indexado por el identificador del grupo en el motor (`groupId _group`)**. 

Permite que las funciones de combate, IA, órdenes y formaciones consulten y alteren en tiempo real el comportamiento físico de cualquier grupo sin tener que recorrer árboles anidados.

```
FTCS_Groups_Registry_Table (HashMap)
│
└── [GroupID: STRING] (ej. "SQUAD_1_1_TEAM_1", "SQUAD_4_1_TEAM_1", "SQUAD_0_0")
      │
      ├── "movingMode"        : ENUM STRING (Ver DIRECTRIZ ENUM-REGISTRY, sección 0)
      │     Valores válidos (censo verificado contra escritores reales en código):
      │     ├── "AT_WILL"                 -> La IA decide su movimiento táctico libremente. Default al spawn.
      │     ├── "FOLLOWING_COMMANDER_REL" -> Sigue al líder manteniendo rumbo y vector relativo.
      │     ├── "FOLLOWING_COMMANDER_ABS" -> Sigue al líder congelando la geometría absoluta del mapa.
      │     ├── "HALT"                    -> Alto temporal manteniendo sector y cobertura. VALOR CANÓNICO DE CONGELACIÓN: los bucles follow (fn_formationsGroupDoFollowCommander, fn_formationsGroupFollowRoad) lo aceptan en su condición while para seguir procesando sin reanclar. Único escritor autorizado: fn_platoonHaltRejoin (HALT). NO usar sinónimos.
      │     ├── "STOP"                    -> Parada estricta (`doStop`, cero reubicación de IA). Escritores: fn_squadOrderApply, fn_formationsGroupListFollowCommander.
      │     ├── "MOVING_TO_OBJECTIVE"     -> Marcha activa hacia punto objetivo (fn_mvTeamMarchLoop vivo). Escritores: fn_mvSquadAdvanceToPoint, fn_mvFormationShift.
      │     ├── "HOLD_POSITION"           -> Anclado al mundo en posición fija (ADVANCE_DETACH_HOLD/DEFEND). Escritores: fn_mvTeamMarchLoop, fn_squadOrderApply (legado).
      │     ├── "FOLLOWING_ROAD"          -> Marcha por carretera (fn_formationsGroupFollowRoad). Escritor: fn_formationsGroupFollowRoad / columnas de carretera.
      │     ├── "FOLLOWING_TRAIL"         -> Columna de estela (fn_formationsGroupFollowTrail / fn_trailColumnSet).
      │     ├── "SCOUT_DETACHED"          -> Scouts desplegados autónomos (fn_applyCommandToTarget, junto a teamAttachment DETACHED_FREE).
      │     └── "CONVOY"                  -> Marcha en convoy rodado detrás de un vehículo guía (reservado).
      │     NOTA HISTÓRICA (no usar): "HALT_FREEZE" fue introducido por fn_platoonHaltRejoin sin pasar por la directriz y quedó NO RECONOCIDO por los consumidores (bucles while comparando contra "HALT"). Documentado como lección: ver FTCS_Programming_Lessons.md.
      │
      ├── "stance"            : ENUM STRING (Ver DIRECTRIZ ENUM-REGISTRY, sección 0)
      │     Valores válidos:
      │     ├── "AUTO"                -> La IA adapta su postura al fuego recibido.
      │     ├── "AT_WILL"            -> Libre albedrío de postura (valor DEFAULT del registro: fn_registryInit). Semánticamente equivalente a AUTO pero escrito con nombre distinto — NO unificar sin revisar consumidores.
      │     ├── "FOLLOWING_COMMANDER_STANCE" -> Copia la postura del teniente en cada tick (erguido/agachado/tendado). Escritor/consumidor: pipeline de stance por grupo. Estaba INDOCUMENTADO — añadido por censo de código real.
      │     ├── "FORCE_UP"     -> Obliga a mantenerse de pie (asalto rápido / carrera).
      │     ├── "FORCE_MIDDLE" -> Obliga a permanecer agachado (avance cauteloso).
      │     └── "FORCE_DOWN"   -> Obliga a permanecer cuerpo a tierra (cuerpo a cubierto).
      │
      ├── "awareMode"         : ENUM STRING (Comportamiento nativo de combate en Arma 3)
      │     Valores válidos:
      │     └── "ROAD_MARCH" (perfil disciplinado de marcha por carretera: AWARE + COVER/AUTOTARGET deshabilitados; escritor: pipeline de carretera/trail). Escritor de los demás valores: FTCS_fnc_groupSetAwareMode.
      │
      ├── "speed"             : ENUM STRING
      │     Valores válidos:
      │     └── "LIMITED" (Paso) | "NORMAL" (Trote) | "FULL" (Carrera a fondo)
      │
      ├── "roe"               : ENUM STRING (Reglas de Enfrentamiento)
      │     Valores válidos:
      │     ├── "FIRE_AT_WILL"         -> Disparar libremente al detectar enemigos (Combate Amarillo).
      │     ├── "FIRE_IF_FIRED_UPON"   -> Fuego de respuesta / discreción (Combate Verde).
      │     └── "HOLD_FIRE"            -> Alto el fuego total / sigilo estricto (Combate Azul).
      │
      ├── "task"              : ENUM STRING (Directiva táctica activa)
      │     Valores válidos:
      │     ├── "AT_WILL"      -> Libre albedrío táctico.
      │     ├── "MOVING"       -> Desplazándose hacia waypoint o línea de fase.
      │     ├── "SUPPRESSING"  -> Fuego de supresión continuo sobre un sector/edificio.
      │     ├── "ATTACKING"    -> Asaltando y limpiando una posición enemiga.
      │     ├── "WATCHING"     -> Vigilando un sector asignado en desenfilada.
      │     └── "WAITING"      -> En espera en Assembly Area o Línea de Partida.
      │
      ├── "platoonFormation"  : ENUM STRING (Formación macro del slot que este elemento ocupa en el despliegue del pelotón)
      │     Valores válidos:
      │     └── "COLUMN" | "LINE" | "WEDGE" | "VEE" | "ECHELON_RIGHT" | "ECHELON_LEFT" | "DIAMOND" | "FILE"
      │     Escritor único: fn_formationsTypePlatoonSet (pipeline de formaciones de
      │     pelotón). Sustituye al antiguo "formationType" (eliminado por ambiguo).
      │     Default doctrinal al spawn: "COLUMN" (fn_registryInit, spawnSupportUnit).
      │     La marcha por carretera NO escribe este campo (geometría propia vía
      │     campos "road*").
      │
      ├── "squadFormation"    : ENUM STRING (Formación interna vigente del squad)
      │     Valores válidos: idénticos a "platoonFormation".
      │     Escritor único: fn_formationsTypeSquadSet (pipeline de formaciones de
n      │     squad). Persistente: solo una nueva orden de formación la sobrescribe.
      │     Default de seguridad del consumidor (Movement): "COLUMN".
      │     Consumidores: fn_mvSquadAdvanceToPoint (marcha/llegada del squad en
      │     su geometría) y futuras maniobras (bounding overwatch, assault...)
      │     cuando movementType = NORMAL_MOVE.
      │
      ├── "teamFormation"     : ENUM STRING (Formación nativa aplicada al grupo de Arma de cada team)
      │     Valores válidos: idénticos a "platoonFormation".
      │     Escritor único: fn_formationsTypeSquadSet (junto a cada setFormation
      │     del pipeline de squads, elementos 0 a 4). Refleja la geometría real
      │     que el motor de Arma 3 aplica a cada grupo de armas, para migración
      │     limpia a Enforce Script (Arma 4) donde las formaciones del motor
      │     pueden diferir de las de SQF.
      │
      ├── "teamAttachment"    : ENUM STRING (Atribución del sub-equipo a su escuadra — Movement/Formations)
      │     Valores válidos (censo verificado):
      │     ├── "SQUAD_BOUND"    -> Arrastrado por las órdenes de movimiento del squad (defecto).
      │     ├── "DETACHED_HOLD"  -> Desligado y fijo (MG emplazada, hold ordenado): ignora movimientos de squad.
      │     ├── "DETACHED_FREE"  -> Desligado autónomo (scouts desplegados): ignora movimientos de squad. Puede coexistir con movingMode "SCOUT_DETACHED".
      │     └── "ADVANCE_DETACH_DEFEND" -> Punto de avance marcado: doMove al objetivo, desligarse y adoptar postura defensiva (fn_mvTeamMarchLoop / órdenes ADVANCE_DETACH_*).
      │
      ├── "movementType"      : ENUM STRING (Maniobra táctica activa del grupo/squad — Movement class)
      │     Valores válidos:
      │     ├── "NORMAL_MOVE"         -> Desplazamiento simple a punto (primitiva ADVANCE_TO_POINT).
      │     ├── "BOUNDING_OVERWATCH"  -> Salto de rana entre teams (reservado, primer cliente: overwatch).
      │     ├── "ASSAULT"             -> Carga contra posición (reservado).
      │     └── "MOVING_OVERWATCH"    -> Avance con cobertura en movimiento (reservado).
      │     Escritura: al entrar en la maniobra (dispatcher de órdenes SQD_MOVE_* / primitivas fn_mv*).
      │     Limpieza: al terminar el bucle de marcha del team (fn_mvTeamMarchLoop) -> "NORMAL_MOVE".
      │
      ├── "platoonId"         : SCALAR (Número de pelotón: 1, 2, 3...; 0 = grupo suelto)
      │     Identidad de pelotón por GRUPO. Sustituye el uso del global
      │     FTCS_Player_Platoon_ID en runtime (company-scale safe, Punto 18).
      │     Escritor único: fn_registryInit.
      │
      ├── "roleKey"           : STRING (Rol doctrinal de MAYOR RANGO presente en el grupo)
      │     Valores: "PLT_<N>_LEADER", "SQD_<N>_<M>_LEADER", "SQD_<N>_0_LEADER",
      │     o "" cuando ninguna unidad del grupo tiene rol doctrinal.
      │     RESOLUCIÓN (fn_registryInit): se recorre assignedRoles (roleVar -> unit)
      │     y se queda el rol cuya unidad PERTENECE a units _group, con prioridad:
      │       PLT_<N>_LEADER = 100  >  *_LEADER = 80  >  *SERGEANT = 60  >  resto = 40
      │     NO es `leader _group`: Arma 3 elige su propio líder de grupo (habilidad
      │     de liderazgo / antigüedad), y un grupo de mando que contiene AL teniente
      │     Y a su RTO resuelve habitualmente al RTO. Ejemplo real observado:
      │     'HQ - 1st Platoon (Command Element)' con leader = RTO devolvía
      │     "PLT_1_RADIO_OPERATOR" antes de aplicar la prioridad por rango.
      │     Sustituye el matching por vehicleVarName (find "LEADER"/"find SQD_",
      │     prohibido por Punto 18) SOLO en modo IA/compañía: en modo jugador los
      │     consumidores deben seguir usando isPlayer / FTCS_Platoon_Leader_Unit.
      │     Escritor único: fn_registryInit.
      │
      ├── "tacticalRole"      : STRING (Rol táctico doctrinal del team)
      │     Valores censados: "ASSAULT" | "SCOUT" | "SUPPORT" | "HQ_ELEMENT" | "" 
      │     Origen: doctrine template "teamRoles" -> fn_applyDoctrine -> parsedSquads
      │     > team > "tacticalRole" -> fn_registryInit (este campo).
      │     "SCOUT" marca el team que el pelotón puede desprender a un slot de
      │     scouts (5/6/7/8/11/12). ÚNICO criterio autorizado para elegirlo:
      │     nunca el nombre del team (Punto 18) ni el orden de un HashMap.
      │     Escritor único: fn_registryInit. Consumidor: fn_applyCommandToTarget
      │     (SQD_SCOUT_*), con fallback determinista TEAM_2 si no hay rol SCOUT.
      │
      ├── "squadId"           : STRING (Clave doctrinal del squad, ej. "SQD_1_1", "SQD_1_0")
      │     Agrupa todos los grupos de una misma escuadra SIN recorrer el árbol doctrinal.
      │     Escritor único: fn_registryInit (siembra). Consumidores: fn_platoonHaltRejoin
      │     (split squad/fireteam), futuras primitivas de órdenes por escuadra.
      │     Default: nil en grupos sueltos (no pertenecen a ninguna escuadra registrada).
      │
      ├── "isSquadLeaderGroup" : BOOLEAN
      │     TRUE solo en el grupo que porta al Squad Leader (grupo-ancla de la escuadra).
      │     Resolución determinista en fn_registryInit: squad unificado -> su grupo;
      │     multi-team -> team de tipo doctrinal TEAM_1/COMMAND; fallback -> team cuyo
      │     leader es el "leader" del squad; fallback HQ -> team GUIDE/SECURITY.
      │     NUNCA se resuelve por orden de iteración de HashMap (orden no determinista).
      │     Escritor único: fn_registryInit. Consumidores: fn_platoonHaltRejoin.
      │     Default: false en grupos sueltos y en fireteams.
      │
      ├── "parentSquadGroup"  : GROUP (referencia al grupo-ancla de la escuadra)
      │     Auto-referencia (el propio grupo) cuando isSquadLeaderGroup == true.
      │     Escritor: fn_registryInit. Consumidor: fn_platoonHaltRejoin (los fireteams
      │     siguen al leader del ancla), fn_formationsTypeSquadSet (herencia de formación).
      │
      ├── "allocationSlot"    : SCALAR (Entero: 0, 1, 2, 3...)
      │     Índice de ranura geométrica dentro de la formación de su pelotón/escuadra.
      │
      ├── "formationPosition" : ARRAY [Distance: SCALAR, Direction: SCALAR, LeaderRef: OBJECT/GROUP]
      │     Posición relativa teórica asignada dentro de la formación respecto a su líder guía.
      │     Ejemplo: [25, 180, Group_Platoon_Leader] (a 25 metros a retaguardia del líder).
      │
      ├── "relPosition"       : ARRAY [Distance: SCALAR, Direction: SCALAR, LeaderRef: OBJECT/GROUP]
      │     Vector de posición relativa real instantáneo en el terreno para corregir desvíos.
      │
      ├── "roadTargetPos"     : ARRAY [x, y, z]  -> Posición objetivo instantánea en la carretera (modo marcha en carretera).
      ├── "roadTangentDir"    : SCALAR           -> Rumbo/tangente de la carretera en la posición objetivo asignada.
      ├── "roadOffsetDist"    : SCALAR           -> Distancia lineal acumulada a lo largo de la carretera desde el líder guía.
      ├── "roadShoulderOffset": SCALAR           -> Desplazamiento lateral perpendicular al eje de la calzada (-1 babor / +1 estribor / 0 centro).
      ├── "roadColumnSide"    : SCALAR           -> Lado informativo de acera en marcha por carretera (-1 babor / +1 estribor / 0 centro). Escritor único: fn_formationsRoadColumnSet.
      ├── "roadTeamIndex"     : SCALAR           -> Índice numérico ordinal del sub-equipo/fireteam dentro de la escuadra (1, 2, 3...).
      │
      ├── "trailOffsetDist"   : SCALAR           -> Arco doctrinal de la columna de estela (metros detrás del líder).
      │     Escritor único: fn_trailColumnSet (al formar la columna) y fn_formationsTrailCompactColumn
      │     (al compactar). NO es un asiento fijo por grupo: es la fuente de la cadena de cola.
      │     INVARIANTE DE UNICIDAD: dos grupos de la misma columna nunca pueden compartir el
      │     MISMO valor (la cola impone `ceil((mío − delante)/recordStep)` con mínimo 1 índice,
      │     así que un empate se convierte en 2 m forzados). El compact del trail da a cada
      │     miembro de la pareja un arco propio (+1 m el segundo) por esta razón.
      ├── "trailShoulderOffset" : SCALAR         -> Desplazamiento lateral en metros perpendicular a la
      │     tangente de la traza (±0.75 = doble carril compacto; 0 = fila india).
      │     Escritores: fn_trailColumnSet (0 al formar columna) y fn_formationsTrailCompactColumn
      │     (fija/limpia el valor). Consumidor único: fn_formationsGroupFollowTrail, que desplaza
      │     el punto objetivo con `getPos` sobre la tangente del punto alcanzado.
      ├── "trailLaneTargetIdx" : SCALAR          -> Índice de `trailPath` al que el grupo está caminando
      │     AHORA (-1 = ninguno todavía). Escritor único: fn_formationsGroupFollowTrail (lo renueva al
      │     llegar); fn_trailColumnSet y fn_formationsTrailCompactColumn lo RESEMBRAN a -1 al cambiar
      │     el techo del grupo; fn_trailAdvanceAnchor lo RENUMERA al recortar la cola (TRIM).
      ├── "trailSlotIndex"    : SCALAR           -> RESERVADO / SIN ESCRITOR. Antiguo asiento natural del
      │     grupo. fn_formationsGroupFollowTrail aún lo lee como preferente sobre el asiento natural:
      │     si alguna función futura lo sembrara, congelaría los asientos de la columna para siempre.
      │     No escribirlo sin revisar antes ese consumidor.
      ├── "trailQueueIndex"   : SCALAR           -> Asiento de COLA publicado por fn_formationsTrailQueueSync
      │     (clase Movement). Sólo se escribe para los grupos que esperan tras un corte; -1 = sin asiento
      │     válido (se mantienen en su posición). Consumidor previsto: fn_formationsGroupFollowTrail.
      ├── "trailQueueHasSeat" : BOOLEAN          -> true = el grupo tiene asiento de cola válido en este tick;
      │     false = debe mantener el terreno. Escritor único: fn_formationsTrailQueueSync.
      ├── "trailQueueTipIdx"  : SCALAR           -> maxIdx de la traza grabada en este tick (tope global de la
      │     columna). Escritor único: fn_formationsTrailQueueSync. Sirve para que el consumidor nunca pida un
      │     índice que aún no existe en trailPath.
      ├── "trailCursorIdx"    : SCALAR           -> RESERVADO / SIN CONSUMIDOR (compatibilidad). El carril
      │     actual no lo usa: el progreso vive en `trailLaneTargetIdx`, que se renueva sólo al alcanzar
      │     el punto (look-ahead de 3 índices). fn_trailAdvanceAnchor lo renumera al recortar la cola por
      │     si alguna versión futura vuelve a leerlo.
      │
      └── "squadTarget"       : ARRAY (tupla target de 8 campos + opcional marca temporal)
            Blanco capturado PROPIO de esta escuadra mediante "Mark Target"
            (Targeting class). Tupla idéntica a la del target del comandante:
            [isObject, targetType, objectRef, approachPos, impactPos, distance,
             bearing, label]. nil cuando la escuadra no tiene blanco asignado.
            Consumido (borrado) al ejecutar una orden de movimiento con blanco
            (ADVANCE_KEEP / ADVANCE_DETACH_HOLD / ADVANCE_DETACH_DEFEND).
            Alimenta el marcador 3D persistente (fn_targetPersistentMarker).
      └── "squadTargetSquadName": STRING -> Nombre doctrinal de la escuadra propietaria
            del blanco (campo "name" de parsedSquads), capturado junto al target
            para la segunda línea del marcador persistente. nil cuando no hay blanco.
```

---

## 4. Estructura de Plantillas de Doctrina: `Doctrines/Data/*.sqf`

Es la estructura pura *Data-Driven* que genera el conversor de composiciones 3DEN (`tools/convert_compositions.ps1`) y que alimenta tanto al motor genérico de spawn `FTCS_fnc_spawnDoctrine` como al constructor jerárquico `FTCS_fnc_applyDoctrine`:

```
Doctrinal Data Template (HashMap devuelto por cada fichero SQF)
│
├── "doctrineID"              : STRING           -> "SPE_US_ARMY_RIFLE_COMPANY", "101_US_PARA_COMPANY_V2_1"
├── "companyLetter"           : STRING           -> Letra designada: "E", "A", "C"
├── "side"                    : SIDE (Arma 3)    -> west (Eje) | east (Soviéticos) | resistance (Aliados)
├── "requiredMods"            : ARRAY of STRINGS -> ["SPE"], ["IFA3"], ["fow"]
├── "isMechanized"            : BOOLEAN          -> false / true
├── "transportAsset"          : STRING           -> "" o clase de semioruga / camión
│
├── "platoonNames"            : ARRAY of STRINGS -> ["Company HQ", "1st Rifle Platoon", "2nd Rifle Platoon", ...]
├── "squadsPerPlatoon"        : SCALAR           -> 4
│
├── "companyHQRoles"          : ARRAY of STRINGS -> Roles asignados en SQUAD_0_0:
│                                                  ["CO_CAPTAIN", "XO_LIEUTENANT", "FIRST_SERGEANT",
│                                                   "COMM_SERGEANT", "RADIO_OPERATOR", "MESSENGER_1..6", "COMPANY_MEDIC"]
│
├── "platoonHQRoles"          : ARRAY of STRINGS -> Roles asignados en SQD_X_0:
│                                                  ["PLATOON_LEADER", "PLATOON_SERGEANT", "PLATOON_RTO", "PLATOON_RUNNER", "PLATOON_MEDIC", "PLATOON_GUIDE", "PLATOON_MESSENGER"]
│
├── "platoonHQTeamStructure"  : ARRAY of ARRAYS  -> [["Command Element", ["PLATOON_LEADER", "PLATOON_RTO"]],
│                                                   ["Support Element", ["PLATOON_SERGEANT", "PLATOON_RUNNER", "PLATOON_MEDIC"]],
│                                                   ["Guide & Security Element", ["PLATOON_GUIDE", "PLATOON_MESSENGER"]]]
│
├── "squadDesignations"       : HashMap          -> Mapeo semántico de escuadras ("SQD_X_Y" -> Nombre):
│     ├── "SQD_1_1" : "1st Rifle Squad"
│     ├── "SQD_1_2" : "2nd Rifle Squad"
│     ├── "SQD_1_3" : "3rd Rifle Squad"
│     ├── "SQD_4_1" : "1st Mortar Section"
│     └── "SQD_4_3" : "1st Machine Gun Section"
│
├── "teamStructure"           : ARRAY of STRINGS -> Nombres de los sub-equipos de fusileros:
│                                                  ["Able Team (Scouts)", "Baker Team (Base of Fire)", "Charlie Team (Maneuver)"]
├── "teamRoles"               : ARRAY of STRINGS -> Roles tácticos de cada sub-equipo:
│                                                  ["ASSAULT", "SUPPORT", "ASSAULT"]
│
├── "platoonFormationSlots"   : HashMap (Opcional) -> Mapeo macro de ranuras de formación (Slot 0..12 -> ID patrón):
│     ├── 0  : "SQD_X_1"         (1st Rifle Squad -> Vanguard / Center)
│     ├── 1  : "SQD_X_2"         (2nd Rifle Squad -> Left Flank)
│     ├── 2  : "SQD_X_3"         (3rd Rifle Squad -> Right Flank)
│     ├── 3  : "SQD_X_4"         (4th Squad / Mortar Section)
│     ├── 4  : "SQD_X_0_TEAM_2"  (Platoon Sergeant & Support)
│     ├── 5  : "SQD_X_Y_TEAM_Z"  (Opcional: Detached Scout / Rear Reserve)
│     ├── 6..8: "SQD_X_Y_TEAM_Z" (Opcional: Forward Advanced Scout Screen)
│     ├── 9  : "SQD_X_0_TEAM_1"  (Attached HQ Command Group / Escort)
│     ├── 10 : "SQD_X_0_TEAM_3"  (Platoon Guide / HQ Security / Rear Anchor)
│     └── 11..12: "SQD_X_Y_TEAM_Z" (Opcional: Outer Flank Security Screens)
│
└── "entities"                : ARRAY of TUPLES (Tupla estándar de 7 u 8 campos por soldado/vehículo):
      │
      └── [
            0: className      (STRING)         -> "SPE_US_Captain", "SPE_US_HMGunner_M2"
            1: offsetXYZ      (ARRAY [X, Y, Z])-> Coordenadas relativas al punto ancla del Capitán: [-60, 36, 0]
            2: relativeDir    (SCALAR)         -> Ángulo relativo de orientación (0 a 360 grados)
            3: varName        (STRING)         -> "HQ_CO_CAPTAIN", "PLT_1_LEADER", "SQD_1_1_LEADER"
            4: groupVar       (STRING)         -> "SQUAD_0_0", "SQUAD_1_1_TEAM_1", "SQUAD_4_3_TEAM_1"
            5: rank           (STRING)         -> "CAPTAIN", "LIEUTENANT", "SERGEANT", "CORPORAL", "PRIVATE"
            6: isVehicle      (BOOLEAN)        -> false (Infantería) | true (Vehículo / Blindado)
            7: customLoadout  (ARRAY Opcional) -> Array nativo getUnitLoadout / setUnitLoadout de Arma 3
          ]
```

---

## 5. Pipeline Operativo y Flujo de Transformación

```
[3DEN Custom Composition (.sqe)]
                │
                ▼ (tools/convert_compositions.ps1)
[Doctrines/Data/*.sqf]  ─────────► Pure Data-Driven HashMap
                │
                ▼ (FTCS_fnc_spawnDoctrine)
      Instanciación en 3D
  (Rotación planar 2D de offsets)
                │
                ├─────────────────────────────────────────┐
                ▼                                         ▼
     FTCS_fnc_applyDoctrine                    FTCS_fnc_parseEditorGroups
(Construye el árbol de Compañía:          (Asocia grupos reales del motor,
   FTCS_Company_Data con HQs,              oficiales individuales y escuadras
   Platoons, Squads y Teams)                a las claves de FTCS_Company_Data)
                │                                         │
                └────────────────────┬────────────────────┘
                                     │
                                     ▼
                          FTCS_fnc_registryInit
                   (Rellena el registro plano por grupo:
                        FTCS_Groups_Registry_Table
                     con estados, slots y geometrías)
                                     │
                                     ▼
                      FTCS_fnc_initUnitInteractions
                 (Asigna AddActions diagéticas en 1ª persona:
                   - Retícula / cursorObject sobre líderes
                   - Invocación de commandingMenu nativo [#USER:]
                   - Inyección de órdenes a Escuadra, Pelotón o Teams)
```

---

## 6. Orquestación Jerárquica de Formaciones (Two-Tier Formation Pipeline)

El sistema de formaciones y movimiento concurrente se orquesta mediante el siguiente flujo modular:

```
[Mando: Menú Nativo o Directiva Táctica]
                 │
                 ▼
FTCS_fnc_formationsApplyPlatoonOrder
(1. Resuelve el Pelotón seleccionado desde FTCS_Company_Data)
(2. Verifica fase operacional activa: si está en Phase 0 DEPLOYMENT/INSPECTION -> Bloquea orden)
(3. Estructura el árbol jerárquico de grupos: Escuadras y sus Sub-Equipos)
(4. Dispara FTCS_fnc_formationsTypePlatoonSet)
                 │
                 ├──► FTCS_fnc_formationsTypePlatoonSet
                 │    (Calcula ranuras macro del Pelotón: 0 a 12)
                 │    (Actualiza "formationPosition" y "relPosition" en FTCS_Groups_Registry_Table)
                 │    │
                 │    └──► FTCS_fnc_formationsTypeSquadSet (Recursivo por Escuadra)
                 │         (Calcula ranuras internas de cada Fireteam: Able, Baker, Charlie)
                 │         (Cada Sub-Equipo se orienta y sigue la estela de su Squad Leader)
                 │
                 ▼
FTCS_fnc_formationsGroupListFollowCommander (Batch Asíncrono)
                 │
                 └──► FTCS_fnc_formationsGroupDoFollowCommander (Hilo Concurrente por Grupo)
                      (Cada grupo ejecuta su navegación continua respetando el estado doctrinal)
```
