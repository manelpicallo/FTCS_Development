# FTCS — Session Log (estado de trabajo entre sesiones)

> **PARA LA IA QUE RETOMA EL PROYECTO:** lee este fichero DESPUÉS del
> `FTCS (First-Person Tactical Command Simulation) - Documento de Notas….md`
> (Punto 0), `FTCS_Data_Structure_Reference.md` y `FTCS_Programming_Lessons.md`.
> Este fichero NO es documentación de diseño: es el **diario de sesión**, el punto
> exacto donde se dejó el trabajo, qué está probado y qué NO.
>
> Reglas de este fichero:
> - La entrada **más reciente va ARRIBA**, justo debajo de esta cabecera.
> - Cada entrada es un resumen cerrado de una sesión completa: qué se tocó, por qué,
>   qué está verificado y qué queda pendiente. No se reescriben entradas antiguas.
> - Cuando una sesión se cierra, su entrada se **consolida en un solo bloque**: las
>   entradas intermedias de esa misma sesión se agrupan aquí. El historial técnico
>   detallado de cada incidencia vive en `FTCS_Programming_Lessons.md`, numerado.
> - No duplica lecciones: cada hallazgo técnico vive en
>   `FTCS_Programming_Lessons.md` y aquí sólo se referencia por número.
> - Las entradas se escriben en **castellano** (es documentación para el humano),
>   igual que esta cabecera y el documento de diseño.

---

## SESIÓN 2026-11-20 (ter) — Fila 4 (Follow Mode): modo por defecto, gate y función de menú no cargada

**Estado:** aplicado en disco; pendiente de validar en partida.

### Diagnóstico

1. El menú no cambiaba la etiqueta al ordenar una formación. La construcción de la fila
   (`fn_menuBuild`, `dynamic = "followmode"`) es correcta: muestra siempre el modo CONTRARIO.
   El fallo silencioso está antes: si la función `FTCS_fnc_menuGate`/`fn_menuBuild` no está
   compilada en la sesión (CfgFunctions no recompilado), el bloque de la fila aborta SIN
   error y la fila conserva su etiqueta ESTÁTICA del catálogo ("ABSOLUTE") y `enabled=1`.
   Resultado observable: "sigue diciendo lo mismo y al clicar no pasa nada".
2. El modo semilla era `REL`, no `ABS`.
3. No existía ningún escrito del modo al ordenar una formación.

### Qué se tocó

1. **`fn_initMenus`**: compila los ficheros del módulo Menu al arrancar
   (catálogo, gate, getState, build, open, dispatch, reopen) y avisa con `***` si
   `FTCS_fnc_menuGate` sigue sin existir. La capa de menú deja de depender de que
   `description.ext` se haya recompilado en la sesión.
2. **`fn_menuBuild`**: si `FTCS_fnc_menuGate` no existe, lo registra con `***` en vez de
   abortar en silencio (la fila queda blanca, pero el RPT lo dice).
3. **Semilla `ABS`**: `fn_registryInit` y `fn_initMenus` siembran `followMode = ABS`
   (espejo `FTCS_Platoon_Follow_Mode = FOLLOWING_COMMANDER_ABS`).
4. **Modo de nacimiento de la formación**: bloque nuevo en `fn_applyCommandToTarget` para
   `PLT_FORM_WEDGE/VEE/LINE/ECHELON_RIGHT/ECHELON_LEFT`: la formación **nace siempre en
   `followMode = ABS`** (contrato doctrinal elegido por el usuario). Column/File no lo tocan.
5. **Fila 4**: gate propio `gate_follow_mode` (líder válido + formación ordenada;
   sin formación: gris "order a platoon formation first").
6. **`platoonFormation` con valor explícito `NONE`**: semilla cambiada de `"COLUMN"` a
   `"NONE"` en los 3 sitios de `fn_registryInit`, y escritor nuevo en
   `fn_formationsApplyPlatoonOrder` (escribe la formación ordenada en cada grupo y en el
   grupo del líder; carretera/estela y Ground Lock no la escriben). `gate_follow_mode`
   trata `"NONE"`, `""` y `"MIXED"` como "sin formación". `fn_menuGetState` ya no re-lee el
   registro (`_pltRegState` = `_pltReg`).
7. Traza temporal `[FTCS][MENU][FOLLOW]` en `fn_menuOpen` (bajo `FTCS_Debug_Menu_Mode`).

### Pendiente

- Validar en partida: abrir menú sin formación (fila 4 gris), ordenar Vee y reabrir (fila 4
  blanca, etiqueta RELATIVE), clicar (pasa a ABS y la etiqueta vuelve a RELATIVE/ABSOLUTE
  según el registro). Revisar en el RPT `[FTCS][MENU][FOLLOW]` y `[FTCS][MENU][DISPATCH]`.
- Eliminar la traza temporal `[FTCS][MENU][FOLLOW]` de `fn_menuOpen` cuando se cierre el caso.
- Recordatorio: `platoonFormation` ya es `NONE` al arrancar, pero los consumidores que
  esperaban `"COLUMN"` por defecto deben comprobarlo (grep de `platoonFormation`).

---

## SESIÓN 2026-11-20 (bis) — Follow mode y eje de avance al registro de PELOTÓN

**Estado:** cambios aplicados en disco; pendiente de validación en partida.

### Qué se tocó

1. **Centinelas nuevos en `FTCS_Platoons_Registry[pltId]`:** `followMode` (`REL`|`ABS`),
   `followModeFacing` (rumbo congelado ABS), `advanceDirection` (eje vivo REL),
   `columnLayout` y `edgeMarginSteps` (sembrados a `""` / `0`). Semilla en
   `fn_registryInit` desde los globals legacy, sin pérdida de estado al arrancar.
2. **Escritor único** del modo: `PLT_MODE_RELATIVE` / `PLT_MODE_ABSOLUTE` en
   `fn_applyCommandToTarget`. El resto de escritores del eje (captura de posiciones,
   orden de formación, nacimiento de columna de carretera, REJOIN-KEEP, bucle de
   seguimiento) escriben `advanceDirection` / `followModeFacing` vía
   `FTCS_fnc_registrySetPlatoon`.
3. **Lectores migrados al registro:** `fn_platoonAdvanceAxis`, `fn_formationsGroupDoFollowCommander`,
   `fn_formationsLiveSlotsDebugWorker`, `fn_platoonHaltRejoin`, `fn_formationsApplyPlatoonOrder`,
   `fn_formationsCurrentPositionSet`, `fn_formationsGroupFollowRoad`, las 4 rutas de
   scouts del dispatcher, y el menú (`fn_menuGetState` + toggle de `fn_menuDispatch`).
4. **Restos del menú retirado eliminados** de los modos REL/ABS: ya no hay
   `showCommandingMenu "#USER:FTCS_MENU_PlatoonFormations_P1"` ni mutaciones directas
   de ese array (podían pisar la reapertura del menú nuevo).
5. **Globals legacy** (`FTCS_Platoon_Follow_Mode`, `FTCS_Platoon_Fixed_Abs_Dir`,
   `FTCS_Platoon_Advance_Direction`, `FTCS_Last_Commander_Dir`) quedan como espejos
   de solo escritura para el pipeline de despliegue. Documentado en
   `FTCS_Data_Structure_Reference.md` (árbol + tabla 1-bis) y Lección 39.

### Pendiente (acordado con el usuario)

- `columnLayout` / `edgeMarginSteps` ya existen en el registro, pero **los gates de
  menú siguen leyendo las anclas**: el paso siguiente (cuando el usuario lo pida) es
  mover `fn_menuGetState` y `gate_layout_*` / `gate_edge_*` a estos campos.
- `convoyMode` (embarcado / vehículos): NO se sembró (sin backend de transporte).

---

## SESIÓN 2026-11-20 — Bug trail resuelto + gates al registro + política de centinelas de menú

**Estado:** sesión cerrada con 4 fijaciones aplicadas y VERIFICADAS en disco (pendiente
solo la validación en partida del fix 4).

### Qué se tocó

1. **BUG PRINCIPAL RESUELTO** — el error `Undefined variable: _parsedsquads/_pltdata`
   del RPT del día 20 (17:41) tenía la causa raíz en `fn_applyCommandToTarget.sqf`,
   caso `PLT_TRAIL_COLUMN` línea 770: write-back `_platoonsMap set [_pltKey, _pltData]`
   con `_pltData` SIN DECLARAR (el caso ROAD sí la declara, línea 502). Envenenaba
   `FTCS_Company_Data > platoons > PLT_1` y reventaba al abrir cualquier menú.
   **Fix:** declarar `_pltData` igual que ROAD (confirmado por el usuario: "solucionado").

2. **Gates UNKNOWN eliminados** — `UNKNOWN GATE ''` (filas de navegación sin gate:
   ahora el build las deja enabled sin llamar al resolutor), `gate_scout` y
   `gate_squads` (añadidos como casos reales en fn_menuGate: al menos una escuadra
   con efectivos).

3. **Acción duplicada en la rueda eliminada** — borrado el bloque legacy
   `[Platoon Orders] Command Net (Radio / Voice)` en fn_initUnitInteractions.sqf
   (más sus 2 acciones SUSPENDED asociadas). Solo queda `[FTCS] Command Menu (Wheel)`
   de fn_initMenus. Cabecera del fichero actualizada (Regla 6).

4. **Compact en trail arreglado EN SERIO** — la fila 5 seguía gris con trail activo
   porque `gate_compact` decidía contra las ANCLAS (geometría que sobrevive al cambio
   de modo y que muta el queue-sync cada tick). Ahora decide contra
   `FTCS_Platoons_Registry[plt]["movementTechnique"]`: ROAD_COLUMN o TRAIL_COLUMN →
   blanca; CROSS_COUNTRY → gris. Igual criterio para gate_edge_push/pull (filas 6/7/8:
   solo ROAD_COLUMN). Pendiente de validar en partida.

### Política nueva registrada (mandato del usuario)

**Punto 0, Regla 20**: los menús deciden su estado SOLO contra centinelas (campos de
registro o flags catalogados); PROHIBIDO introspeccionar estado interno de funciones.
Catálogo completo en `FTCS_Data_Structure_Reference.md` sección 1-bis; lección técnica
en `FTCS_Programming_Lessons.md` Lesson 38.

### Pendiente

- Validar en partida el fix 4 (trail → fila 5 blanca; road → 5/6/7/8 blancas).
- Revisar el gate `gate_layout_*` (fn_menuGate líneas 160-170): todavía lee layouts de
  anclas para el matiz "already active". Candidato a migrar al mismo criterio registro
  en la próxima sesión.
- `FTCS_Menu_Structure_Reference` (referenciado en Punto 0 Regla 13) NO existe en el
  proyecto: decidir si se crea o se retira la regla.

### Cómo probarlo

Salir a Eden y re-entrar (no cambia CfgFunctions, pero los ficheros se compilan al
cargar la misión). Ordenar Trail → menú March Column: fila 5 blanca, 6/7/8 grises.
Compactar → fila 5 se re-grisa hasta re-emitir trail. Ordenar Road → 5/6/7/8 blancas.

---

## SESIÓN 2026-11-17 (CIERRE) — Rediseño de menús entregado; ERROR `_parsedSquads` SIN RESOLVER

**Estado:** el módulo `Menu` está implementado y ARRANCA, pero **el error
`Undefined variable: _parsedSquads / _pltData` SIGUE ABIERTO tras un día entero de
diagnóstico.** No hay solución aplicada.

### 1. Qué SÍ está hecho y funciona

- Módulo `Menu` con 8 ficheros: `menuCatalog` (datos), `menuGetState`, `menuGate`,
  `menuBuild`, `menuOpen`, `menuDispatch`, `menuReopen`, `initMenus`.
- Podados 17 menús sin backend y `SquadSelect_Common` (nombres hardcodeados).
- Borrado `fn_openSubordinateMenu.sqf` (405 líneas) y todas sus llamadas.
- `description.ext`: módulo `Menu` registrado, `openSubordinateMenu` dado de baja,
  **`class trailTrimToArc` restaurada** (se había perdido al reescribir el fichero).
- `fn_applyDoctrine`: `find "mortar"` → dato de doctrina `"unifiedSquads"` (+3 doctrinas).
- `fn_applyCommandToTarget`: `ADVANCE_DEFEND` antes de `ADVANCE_DETACH_`; `default`
  ya no miente (`*** UNHANDLED COMMAND`).
- `init.sqf`: eliminado el `addAction` viejo del líder.
- **Verificado en el RPT:** `[FTCS][MENU] initialized (mode=DEBUG)`, menú abierto con
  11 filas, órdenes despachadas (`SET_PHASE_2`, `PLT_TRAIL_COLUMN`), 5 escuadras
  detectadas por el registro. `fn_openSubordinateMenu.sqf not found`: desaparecido.

### 2. El error ABIERTO (lo que hay que resolver en la próxima sesión)

```
Error in expression <...isEqualType createHashMap)) then { _pltData = ...
Error Undefined variable in expression: _pltdata
Error Undefined variable in expression: _parsedsquads
File ...\Functions\Menu\fn_menuGetState.sqf
```

**Datos recogidos con `[FTCS][DIAG]` (los únicos hechos firmes):**

```
21:42:48  DIAG parsedSquads keys=["SQD_1_2","SQD_1_4",...]  name=1st Rifle Squad
21:42:55  DIAG parsedSquads keys=array                        name=any
```

- **`keys=array`**: en esa llamada `_parsedSquads` **no es un HashMap**.
- **`name=any`**: `getOrDefault` devuelve el valor por defecto.
- Correlación: falla **siempre tras ordenar `PLT_TRAIL_COLUMN`**, y la primera vez
  que se ordena trail funciona. Reiniciar la misión lo resetea.
- Las 10 apariciones del error son **siempre en la misma línea**
  (`if (!(_pltData isEqualType createHashMap))`).
- `line 770` de `fn_applyCommandToTarget` **NUNCA** dio error: descartado.

**Hipótesis DESCARTADAS (no volver a ellas):**

| Hipótesis | Por qué se descartó |
|---|---|
| Enlaces/junctions roto | Junction y hardlink verificados; hash idéntico |
| `description.ext` desincronizado | Sincronizado y verificado en las 3 misiones |
| Fichero recompilado en 3DEN | El error sale con el hash correcto en disco |
| `private` re-declarado en bucles | Corregido; el error persiste |
| Reentrada por `MouseButtonUp` | `[REOPEN] buttonUp` = 0 apariciones en el RPT |
| `params` heredando del hilo | Cambiado a `_this` + validación; **el usuario pidió revertir** |
| `_pltData` en la línea 770 | Nunca aparece ese error en el log |

### 3. Lo único que falta por probar

**Una línea de diagnóstico que muestre qué llega en la llamada que falla:**

```sqf
// Al principio de fn_menuGetState
diag_log format ["[FTCS][DIAG] _this=%1 type=%2 | _pltId=%3 type=%4",
    _this, typeName _this, _pltId, typeName _pltId];
```

**No se ha aplicado.** Es el siguiente paso.

### 4. Documentación borrada hoy

- **Lecciones 34, 38, 39** (eliminadas antes, todas con diagnóstico erróneo).
- **Lecciones 26 y 28** + sus filas del índice: describían este mismo error con la
  causa equivocada (`global como receptor`, `private` en `for` + reentrancia).
- Se conservan 35, 36, 37 (arquitectura del módulo, hardlinks, `description.ext`).

### 5. Aviso de compilación

> ⚠️ **Módulo `Menu` (8 funciones) en `CfgFunctions` y baja de
> `openSubordinateMenu` + `class trailTrimToArc` restaurada.**
> Imprescindible **salir a 3DEN y volver a entrar**.

---

**Estado:** implementado en disco. **NO probado en partida todavía.**

### 1. Qué se hizo

Se sustituyó la UI de menús (25 arrays hechos a mano + `fn_openSubordinateMenu` de
405 líneas) por un módulo de 8 funciones pequeñas con responsabilidad única:

```
fn_menuCatalog   DATOS: menús, filas, tokens, gates, marca de reapertura
fn_menuGetState  UNA pasada al registro -> snapshot de estado del pelotón
fn_menuGate      [gate, estado, escuadra] -> [enabled, motivo]
fn_menuBuild     catálogo + estado -> filas (labels, %1, filas dinámicas, hub)
fn_menuOpen      snapshot -> build -> publica copia -> showCommandingMenu
fn_menuDispatch  "FAMILIA:CODIGO[:ARG]" -> código del router existente
fn_menuReopen    reapertura de un disparo por MouseButtonUp
fn_initMenus     compila el catálogo una vez + addAction única del jugador
```

### 2. Decisiones cerradas (todas del programador)

- Números `N.` en todos los labels (el número es la tecla).
- Grises SÍ, pero solo para comandos implementados; cada gris muestra su motivo.
- Escuadra sin **líder vivo y no incapacitado** -> fila gris con el estado.
- Escuadras desde el registro; la que no existe no se pinta.
- Hub `Squad & Scout Directives` conservado (Scouts en fila 1, escuadras detrás).
- Scouts solo a nivel de pelotón (no dentro del menú de escuadra).
- Nombres SIEMPRE de la doctrina; cero nombres en el código.
- `FTCS_Debug_Menu_Mode` como tercer centinela, en `fn_registryInit`, inmutable en partida.
- Log completo en modo DEBUG, sin filas de diagnóstico en el menú.
- Reapertura por `MouseButtonUp` en navegación y estado.

### 3. Excepciones aprobadas (fuera de menús)

- `fn_applyCommandToTarget`: reordenado `ADVANCE_DEFEND` antes de `ADVANCE_DETACH_`
  (el segundo `case` nunca se alcanzaba) y `default` que ya no miente: loguea
  `*** UNHANDLED COMMAND`.
- `fn_applyDoctrine`: `find "mortar"` sustituido por el dato de doctrina
  `"unifiedSquads"` (Regla 18: el nombre no decide estructura).
- `Doctrines/Data/*.sqf` (3): alta de `"unifiedSquads"`.

### 4. Retirado

- `Functions/Interactions/fn_openSubordinateMenu.sqf` (borrado).
- 17 menús sin backend y los `FTCS_MENU_SquadSelect_Common` hardcodeados.
- `fn_commandMenusRefresh` (ya no existía en disco).

### 5. NO verificado

- No se ha ejecutado Arma: **falta la prueba en partida**.
- Sin probar: reapertura por MouseButtonUp, grises contra estado real,
  reordenación de `ADVANCE_DEFEND`, `unifiedSquads` en las 3 doctrinas.

### 6. Aviso de compilación

> ⚠️ **MÓDULO NUEVO EN `CfgFunctions`: `Menu`** (8 funciones) y baja de
> `openSubordinateMenu`. Es imprescindible **salir de la misión → editor 3DEN →
> volver a entrar**. Un *Restart* in-game no recompila `description.ext`.

---

**Estado:** la **columna de trail funciona perfectamente y es muy robusta tal y como
está implementada ahora** (valoración del programador en partida). Arranca en cascada,
todos los grupos entran, nadie corta camino, el TRIM no estrangula la traza y el último
grupo ya no se queda fuera. **Lo único pendiente es probar el COMPACT de trail.**

### 1. Cómo funciona la columna hoy (leer esto primero)

```
fn_trailColumnSet            reparte trailOffsetDist = (n-1)*3 + 8 por grupo
                             orden de la columna     = [9,0,4,1,2,3,10,5]  (RTO primero)
                             siembra el ancla: trailMinSeatArc/-1, trailMaxOffset,
                             trimCushion/150, trailLaneTargetIdx/-1
fn_trailAdvanceAnchor        hilo del recorder (0.25 s):
                             0) fn_trailTrimToArc ANTES de grabar
                             1) graba 1 punto / 2 m si fn_navIsValidGround (dz <= 0.5)
                             2) convergencia al parar (headDist = longitud real)
fn_trailTrimToArc            ÚNICO escritor del TRIM. Lee el registro él mismo y nunca
                             recorta dentro de la profundidad de la columna; lote de 20
                             puntos, colchón 150 m, mínimo 3 puntos. Desplaza headDist y
                             los arcos publicados, y renumera los índices persistidos.
fn_formationsTrailQueueSync  publica por grupo trailQueueIndex / trailQueueHasSeat /
                             trailQueueTipIdx y en el ancla trailMinSeatArc, trailTailArc,
                             trailMaxOffset. seat = trailIndexAtArc(headDist - offset),
                             encadenado ORDEN + SEPARACIÓN; si el archivo está comprimido,
                             mínima ORDEN (1 índice) antes que HOLDS.
fn_formationsGroupFollowTrail  un hilo por grupo (0.35 s). Camina PUNTO A PUNTO con
                             trailLaneTargetIdx (look-ahead 3), aplica
                             trailShoulderOffset (doble carril), timeout = salta UN índice.
fn_groupAwakenForMarch       ÚNICO sitio que emite enableAI/disableAI (Regla 15)
```

**Invariantes que NO se pueden romper:**

1. `trailPath` sólo lo escribe `fn_trailAdvanceAnchor`, y sólo con puntos que pasan
   `fn_navIsValidGround` (dz ≤ 0.5 m). El congelamiento en el puente ES la barrera.
2. Todo índice persistido en el registro debe renumerarse cuando el TRIM recorta
   (hoy: `trailCursorIdx`, `trailLaneTargetIdx`). Si se añade otro campo de índice,
   **hay que añadirlo a esa lista**.
3. La cola garantiza ORDEN y SEPARACIÓN; nunca recalcula el espaciado doctrinal. La
   separación **cede ante el orden** cuando el archivo está comprimido contra la punta.
4. Ningún límite de memoria puede depender de un valor que otro hilo publique DESPUÉS
   de él (Lección 32).
5. El grupo siempre camina puntos reales de la traza, en orden: nunca se le manda al
   asiento de golpe (Lección 31).

### 2. Lo verificado en partida

| Comprobación | Resultado |
|---|---|
| Arranque en cascada | ✅ todos los grupos arrancan, mucho más rápido que antes |
| Orden de la columna | ✅ RTO primero (`off=1`), Guide último |
| Separación doctrinal | ✅ asientos distintos y escalonados |
| Sin cortar camino | ✅ todos siguen la traza del líder |
| Último grupo | ✅ entra en la columna (orden mínima si hace falta) |
| Cruce de puente | ✅ verificado en sesiones anteriores |
| Menú de órdenes | ✅ se abre; Compact se habilita sin reabrir |

### 3. Problemas encontrados hoy y su causa raíz (todas cerradas)

| Problema | Causa | Lección |
|---|---|---|
| Menú no se abría (`_pltdatad` línea 281) | global `FTCS_Company_Data` usado como receptor de `getOrDefault` | 26 |
| El mismo error se repetía en partida | fichero sin recompilar + Arma retenía el fichero abierto | 26 |
| Error de variables de menú en cascada | `private` dentro de `for` + reentrancia → se extrajo `fn_commandMenusRefresh` | 28 |
| Compact trail: dos últimos sin compactar | participantes filtrados solo por `trailOffsetDist > 0` (fantasmas de otra marcha) | 29 |
| Últimos grupos tardaban / no arrancaban | el TRIM se comía la traza bajo su profundidad | 30, 32 |
| Grupos cortaban camino | el timeout saltaba al asiento en vez de un índice | 31 |
| Último grupo fuera de la columna | `frontSeat - gapIdx` negativo → HOLDS | 33 |

### 4. Ficheros tocados en la sesión

| Fichero | Qué se hizo |
|---|---|
| `Functions/UI/fn_commandMenusRefresh.sqf` | **NUEVA.** Único dueño del estado de los menús; guard de reentrancia. `description.ext > UI` |
| `Functions/Interactions/fn_openSubordinateMenu.sqf` | Adelgazado: refresca y muestra, ya no recalcula flags |
| `Functions/Interactions/fn_applyCommandToTarget.sqf` | Llama al refresco al final de cada cambio de marcha |
| `Functions/Roads/fn_trailTrimToArc.sqf` | **NUEVA.** Único escritor del TRIM, con guard de profundidad propio |
| `Functions/Roads/fn_trailAdvanceAnchor.sqf` | TRIM delegado (sección 0) |
| `Functions/Movement/fn_formationsTrailQueueSync.sqf` | Publica `trailMinSeatArc`, `trailTailArc`, `trailMaxOffset`; orden mínima si el archivo está comprimido |
| `Functions/Formations/fn_formationsTrailCompactColumn.sqf` | Filtro de participantes = el de la cola; arco propio por miembro; footprint nominal |
| `Functions/Formations/fn_formationsGroupFollowTrail.sqf` | Timeout de un índice; fallback al índice 0 si no hay asiento |
| `Functions/Formations/fn_trailColumnSet.sqf` | Siembra de trim (`trailMinSeatArc`, `trailMaxOffset`, `trimCushion` 150) |
| `description.ext`, `tools/verify_syntax.ps1` | Registro de las dos funciones nuevas |

Documentación al día: `FTCS_Data_Structure_Reference.md` (§3, campos nuevos del ancla),
`FTCS_Programming_Lessons.md` (Lecciones 24-33), `FTCS_Menu_Structure_Reference`
(propiedad del estado de los menús).

### 4-bis. Episodio de la tarde: regresión del refresco de menús (CERRADA por reversión)

Entre las **19:00 y las 19:30** aparecieron errores `Undefined variable` en
`fn_commandMenusRefresh` que no existían a las 15:02. **Los introduje yo** con ediciones
sucesivas del guard y del punto de llamada; el código de las 15:02 (commit `1896911`
"Trail mode prefecta") funcionaba y siguió funcionando hasta que se tocó.

**Cerrado revirtiendo el fichero a `1896911`**, byte a byte, y el dispatcher a `call`.
Fuera todo lo añadido en esa franja: guard por `FTCS_Menu_RefreshTick`, las locales
`_menu*`, `spawn` y `_registryRef`.

**Dos diagnósticos descartados que deben olvidarse** (no se recogen en las lecciones
porque era falso): “global como receptor de `select`/`forEach`” y “scope de `call`”.
El código que funcionaba ya hacía AMBAS cosas.

> **Regla de trabajo para la próxima sesión:** ante un informe de regresión, comparar
> con el ÚLTIMO COMMIT CONOCIDO BUENO antes de diagnosticar. Había commits disponibles
y no se usaron hasta mucho después.

### 5. Pendiente — lo único que queda

1. **Probar el COMPACT de trail con la columna ya robusta.** Qué comprobar:
   - Las parejas marchan **a la par** (±0.75 m del eje) y el **último** equipo también.
   - El log `[FTCS][TRAIL][COMPACT] plt N: X participants -> Y pairs, unpaired=Z`
     cuadra con la columna real (`unpaired` 0 o 1).
   - Giro cerrado, parada/arranque (dispara el TRIM) y puente **con la columna
     compactada**.
   - Descompactar re-ordenando Leader Trail Column.

### 6. Deuda técnica conocida (no bloquea)

1. `trailSlotIndex` sigue sin escritor pero el follower lo **prefiere**: reservado y
   documentado, no escribir sin revisar el consumidor.
2. Fusionar `fn_formationsRoadCompactColumn` y `fn_formationsTrailCompactColumn` en un
   helper común con dos samplers.
3. Compact de carretera: pasar del footprint medido al nominal (el de trail ya lo usa).
4. **PENDING-5**: `_slotOrder = [9,0,4,1,2,3,10,5]` duplicado → extraer a función.
5. **PENDING-6 (prioridad)**: auditar los globals usados como receptor (`getOrDefault` /
   `forEach` / `select`) en TODO el proyecto. Ya ha mordido tres veces (Lecciones 26 y
   35). Un grep inicial encontró ~72 coincidencias; solo rompen en posición de
   receptor, pero hay que revisarlas una a una.
6. Grupo sin líder vivo / líder inconsciente: no comprobado; el watchdog cubre sólo
   líder VIVO.

---

## SESIÓN 2026-11-15 (CIERRE) — Columna TRAIL: estado final, verificado y pendientes

**Estado:** la columna de estela **funciona**: arranca en cascada, respeta el orden
(RTO primero), mantiene la separación doctrinal y **cruza el puente** liberando a los
grupos uno tras otro. Queda **un bug conocido** (un grupo puede perder su sitio si su
líder muere) y varios pendientes. Última prueba: RPT `Arma3_x64_2026-11-15_17-04-23.rpt`,
recorrido largo con paradas, puente y bajas.

### 1. Cómo está montado ahora (leer esto primero)

```
fn_trailColumnSet          reparte trailOffsetDist  = (n-1)*3 + 8   por grupo
                           orden de la columna      = [9,0,4,1,2,3,10,5]  (RTO primero)
fn_trailAdvanceAnchor      graba la traza del líder (1 punto / 2 m, se congela si el
                           líder está elevado = puente); delega el TRIM (ver la
                           entrada de cierre 2026-11-16, el modelo cambió)
fn_formationsTrailQueueSync publica por grupo: trailQueueIndex (su asiento),
                           trailQueueHasSeat, trailQueueTipIdx
                           seat = trailIndexAtArc(trail, headDist - offset)
                           acotado por el grupo de delante (orden + separación)
fn_formationsGroupFollowTrail  camina PUNTO A PUNTO: guarda trailLaneTargetIdx, va
                           a un punto 3 índices por delante, y solo renueva cuando
                           llega (2.5 m). HOLD si la cola no le da asiento.
fn_groupAwakenForMarch     ÚNICO sitio que emite enableAI/disableAI (Regla 15)
```

**Invariantes que NO se pueden romper:**
1. `trailPath` sólo lo escribe `fn_trailAdvanceAnchor`, y sólo con puntos que pasan
   `fn_navIsValidGround` (dz ≤ 0.5 m). El congelamiento en el puente ES la barrera.
2. Todo índice persistido en el registro debe renumerarse cuando el TRIM recorta
   (hoy: `trailCursorIdx`, `trailLaneTargetIdx`). Si se añade otro campo de índice,
   **hay que añadirlo a esa lista**.
3. La cola garantiza ORDEN y SEPARACIÓN; nunca recalcula el espaciado doctrinal.
4. `_targetIdx` se acota con `(x min _maxIdx) max 0` antes de indexar `trailPath`.

### 2. Lo verificado en el RPT final

| Comprobación | Resultado |
|---|---|
| Cascada de arranque | ✅ cada grupo arranca al alcanzar su profundidad |
| Orden de la columna | ✅ RTO primero (`off=1`), Guide último |
| Separación doctrinal | ✅ asientos distintos y escalonados (115, 112, 105, 101, 92, 88, 82, 75...) |
| Cruce de puente | ✅ esperan en la orilla y pasan en orden; la columna se recompleta |
| Movimiento fluido | ✅ sin tirones de 2 m |
| Giros cerrados | ✅ el grupo sigue sin quedarse clavado |
| Sin errores de código en el flujo | ✅ (sólo el error de menú, ver §5) |

### 3. BUG CONOCIDO — un grupo puede perder su posición (ENTRADA HISTÓRICA)

> **Desactualizado el 2026-11-16:** la cola se reescribió por completo (ver la entrada
> de cierre de 2026-11-16). Se conserva como historial del diagnóstico, NO como estado
> actual del código.

**Síntoma:** al morir el líder de un grupo (cayó al agua en el puente), ese grupo se
quedó plantado y terminó con el asiento de **otro** grupo (`seat 31` cuando le
tocaba ~60). El resto de la columna funcionó y dejó el hueco libre.

**Evidencia del RPT:**

```
20:21:43  '2nd Rifle Squad - Rifle Team B'  off=86  seat=43  (cap=3)  -> HOLDS
20:21:44  '2nd Rifle Squad - Rifle Team B'  off=86  seat=0   (cap=44) -> SEAT
```

El `cap` (asiento del grupo de delante) saltó de **3 a 44** en un tick.

**Diagnóstico:** la cola construye la cadena filtrando por `movingMode ==
"FOLLOWING_TRAIL"`. Si un grupo parpadea fuera de ese modo (reorganización tras la
muerte del líder) o cambia de identidad, la cadena se reconstruye sin él y vuelve a
entrar con el `_frontIdx` de otro grupo → hereda un asiento ajeno.

**Corrección propuesta entonces (superada):** asiento monótono creciente por grupo. La
cola actual resuelve el mismo problema de otra forma: el orden es una cadena estricta
por `trailOffsetDist` y el asiento se deriva por arco en cada tick, sin memoria previa
que pueda quedar desfasada.

**Nota:** Arma reasigna el líder del grupo automáticamente al morir, y el follower usa
`_group move` / `leader _group`, así que **el grupo sí continúa**; lo que se rompe es
su ASIENTO, no su movimiento.

### 4. Errores encontrados y corregidos HOY (no repetirlos)

| # | Error | Causa | Lección |
|---|---|---|---|
| 1 | `_queueflagearly` undefined | `registryGet` devuelve `nil` y `private x = nil` no crea la variable | 16 |
| 2 | Columna invertida | el asiento se medía desde el ORIGEN, no desde el frente | 18 |
| 3 | RTO casi al final de la fila | se ordenaba por `allocationSlot`, no por la lista de marcha | 17 |
| 4 | Puntos pegados uno tras otro | la cadena forzaba `frontIdx - 1` (2 m) en vez de la distancia doctrinal | 21 |
| 5 | Tirones de 2 m | objetivo `cursor+1` con tick de 1 s | 23 |
| 6 | Todos al último punto | mazclé índice y arco; cursor realimentado | 22, 23 |
| 7 | `_entry` / `_targetPos` undefined | `select` con índice fuera de rango tras el trim | — |
| 8 | Grupos dando la vuelta tras parar | el TRIM recorta por delante y desplaza TODOS los índices; `trailLaneTargetIdx` no se renumeraba | — |

El nº 8 es el que explica el "llega, se marca atrás y vuelve" que sólo pasaba al
parar y arrancar (de un tirón el trim no se dispara).

### 5. Error de menú encontrado en el RPT — ARREGLADO el 2026-11-16

```
20:41:25  Error Undefined variable: _pltdatad / _parsedsquadsd / _sdatad
          en fn_openSubordinateMenu.sqf (líneas 271-283)
```

Se diagnosticó aquí como "cosmético"; en realidad **impedía abrir el menú** (el script
abortaba antes de `showCommandingMenu`). Cerrado en la sesión del 2026-11-16: lectura
vía `missionNamespace getVariable` + guardas de tipo, y el refresco de flags se extrajo
a `fn_commandMenusRefresh`. Ver Lecciones 26 y 28.

### 6. Comportamiento esperado que NO es un bug

- **Los grupos del fondo tardan en arrancar en el puente**: su asiento es alto (hasta
  ~115 índices = ~230 m de traza) y el líder debe grabar hasta ahí. Es la cascada.
- **El `max`/`tip` baja en el RPT durante el trim**: es el recorte funcionando. Las
  posiciones de los grupos ya se renumeran.
- **Soldados que se caen del puente**: es el pathfinding del motor en un navmesh
  estrecho con varios grupos convergiendo. No se controla desde la lógica.

### 7. Pendientes que quedaron en esta fecha — estado al 2026-11-16

| # | Pendiente | Estado hoy |
|---|---|---|
| 1 | Asiento monótono en la cola | **Superado.** La cola se reescribió (2026-11-16) |
| 2 | Guard del menú | **Hecho.** Lecciones 26 y 28 |
| 3 | Cláusulas de líder (líder muerto / inconsciente) | **Sigue abierto.** Sólo está el watchdog de líder vivo |
| 4 | Fórmula del footprint en el compact de trail | **Hecho.** Usa el modelo nominal |
| 5 | PENDING-5: `_slotOrder` duplicado | **Sigue abierto** |
| 6 | Lección 14 (modelo de arcos) marcada como histórica | **Hecho** |
| 7 | Migración arco→índice documentada | **Hecho** (Lección 22 y entrada de cierre) |

### 8. Aviso de compilación

> ⚠️ **`fn_groupAwakenForMarch` es una función NUEVA en `CfgFunctions`.**
> Es imprescindible **salir de la misión → editor 3DEN → volver a entrar**.
> Un *Restart* in-game no recompila `description.ext`.

---

## SESIÓN 2026-11-15 (mañana/tarde) — Columna TRAIL: cola de cruce (puentes), orden de marcha y despertar de la IA

> **Estado actual (2026-11-16):** cerrada. `fn_groupAwakenForMarch` está registrada y
> compilada; la columna funciona. Se conserva como historial del diseño de la cola de
> cruce.

**Estado en su fecha:** implementado. **Orden y cascada VERIFICADOS en el RPT** (15:22);
quedaba recompilar `CfgFunctions` para que existiese `FTCS_fnc_groupAwakenForMarch`.
**Foco:** seguimiento en columna de estela (TRAIL_COLUMN) y su cruce de puentes / cortes.

### 1. El modelo que se acordó (esto es lo que hay que entender primero)

Una columna de estela es un **tren**. Arma 3 no puede generar un punto de destino
fiable sobre la cubierta de un puente (la IA acaba nadando por debajo), así que el
puente se trata como un **CORTE de la traza**:

- `fn_trailAdvanceAnchor` **deja de grabar** mientras el líder está elevado
  (`fn_navIsValidGround`, dz > 0.5 m). La traza se congela en la orilla de salida y
  **se reanuda al otro lado**. Ese congelamiento es deliberado: es la barrera.
- Mientras la traza no crece, `maxIdx` no avanza → **nadie pasa el corte**.
- Cuando el líder marca puntos al otro lado, cada grupo entra en su punto **en
  cascada, de delante a atrás**, conservando su distancia doctrinal.

**La regla de medida (crítica — se implementó mal dos veces):**

```
seat(k) = maxIdx − round( trailOffsetDist(k) / recordStep )
```

Se mide **desde el FRENTE**, igual que la columna de carretera
(`fn_formationsGroupFollowRoad` → `sample(headDist − offsetDist)`).
Medir `round(offset / recordStep)` sin restar `maxIdx` da distancias **desde el
origen** de la traza y **invierte la columna entera** (Lección 18).

- `seat >= 0` → el líder ya ha andado esa profundidad → **el grupo camina a su punto**.
- `seat < 0` → todavía no → **HOLD** (el grupo espera, pero nunca se mueve al punto 0
  ni al `maxIdx`: eso es lo que apelmazaba el pelotón sobre el teniente).

### 2. Orden de la columna

El orden **no** es `allocationSlot` ascendente. Es la **misma lista explícita que la
columna de carretera**:

```sqf
_slotOrder = [9, 0, 4, 1, 2, 3, 10, 5];
//             9 = HQ Escort (el RTO) → PRIMERO detrás del teniente
//             0 → 4 → 1 → 2 → 3 → 10 (Guide) → 5 (Reserve);  scouts 6/7/8 excluidos
```

Ver Lección 17. Antes el RTO (slot 9) caía casi al final de la fila.

### 3. Ficheros tocados (todos con fecha 2026-11-15)

| Fichero | Qué cambió |
|---|---|
| `Functions/Movement/fn_formationsTrailQueueSync.sqf` | **Reescrito.** Lee la traza del ANCLA (`FTCS_Trail_Anchor_PLT_<id> > trailPath`); orden por `trailOffsetDist`; `seat = maxIdx − round(off/step)`; publica `trailQueueIndex` (−1 = HOLD), `trailQueueHasSeat`, `trailQueueTipIdx`; el encadenado respeta la distancia doctrinal y nunca deja que un coche alcance al de delante |
| `Functions/Formations/fn_formationsGroupFollowTrail.sqf` | Consume la cola (`trailQueueHasSeat` / `trailQueueIndex`); `_naturalIdx = maxIdx − round(offset/step)`; protección `isNil` en todas las lecturas del registro (Lección 16); HOLD sin `doStop`; despertar de la IA vía la función nueva |
| `Functions/Formations/fn_trailColumnSet.sqf` | Orden por `_slotOrder = [9,0,4,1,2,3,10,5]` (antes `allocationSlot` ascendente) |
| `Functions/Formations/fn_groupAwakenForMarch.sqf` | **NUEVA.** Único sitio del proyecto que emite comandos de IA de movimiento |
| `Functions/Formations/fn_formationsApplyPlatoonOrder.sqf` | Bloque inline de `enableAI` → llamada a la función nueva |
| `Functions/Formations/fn_formationsGroupFollowRoad.sqf` | Bloque inline de `enableAI` → llamada a la función nueva |
| `Functions/Interactions/fn_applyCommandToTarget.sqf` | Dos bloques inline (rama road y rama trail) → llamada a la función nueva |
| `Functions/Groups/fn_platoonSetOperationalPhase.sqf` | Tres bloques inline (fases 1/2/3) → llamada a la función nueva |
| `description.ext` | Nueva clase `groupAwakenForMarch` en `CfgFunctions > Formations` |
| `tools/verify_syntax.ps1` | Añadidos `fn_groupAwakenForMarch.sqf` y `fn_formationsTrailQueueSync.sqf` a la lista verificada |

### 4. Documentación actualizada

- `FTCS_Data_Structure_Reference.md` §3: campos `trailOffsetDist`, `trailSlotIndex`,
  `trailQueueIndex`, `trailQueueHasSeat`, `trailQueueTipIdx` (escritor + consumidor).
- `FTCS_Programming_Lessons.md`: **Lecciones 15, 16, 17, 18, 19** y **PENDING-5**.

### 5. Estado real de la verificación en partida

**✔ Verificado en el RPT de las 15:22** (`Arma3_x64_2026-11-15_12-03-50.rpt`):

- **El orden de la columna es correcto.** `HQ - 1st Platoon (Command Element)`
  aparece con `off=1`, es decir, **el RTO es el primero** de la cadena
  (Lección 17 arreglada).
- **La cascada funciona.** Todos los grupos profundos emiten
  `-> HOLDS (depth not walked yet)` con `seat` negativo al arrancar: nadie se mueve
  hasta que el líder ha andado su profundidad (Lección 18 arreglada).
- **Los errores anteriores ya no aparecen:** ni `_queueflagearly` ni `_queuespoke`
  (Lección 16 arreglada).

**✘ ÚNICO ERROR PENDIENTE — no es de lógica, es de compilación:**

```
15:22:47  Error Undefined variable in expression: ftcs_fnc_groupawakenformarch
File ...\FTCS_Dev_Mission_2.Prokhorovka\functions\Formations\fn_formationsGroupFollowTrail.sqf, line 75
```

La misión se ejecutó **sin recompilar `CfgFunctions`**. `fn_groupAwakenForMarch`
no existe en el motor porque `description.ext` no se releyó, así que las 6 llamadas
fallan y el hilo del follower muere en su primera línea (antes de publicar
movimiento). Verificado en disco: el registro en `description.ext` es correcto y no
hay clases duplicadas — **es exclusivamente falta de recompilación.**

**Consecuencia esperada tras recompilar:** el `enableAI` pasa a ejecutarse y los
grupos que hoy dicen `HOLDS` deben empezar a moverse en cascada.

**✔ Verificado en el RPT de las 17:04** (primera prueba con la función compilada):
los grupos **se mueven bien** y el RTO va delante. Ningún error de código.

**✘ SEGUNDO BUG ENCONTRADO Y CORREGIDO — la mitad trasera quedó huérfana:**

```
trail RESUMED at [3398.27,5846.52] dz=0.25
trail RECORD: LARGE STEP 108.4m at point 55 -> segment spans water/props
```

Al cruzar el puente el recorder graba **un solo punto** que abarca los 108 m del
cruce, así que `headDist` creció 108 m pero `maxIdx` creció **1** (54 → 55).
Calcular `seat = maxIdx − offset/2` supone 2 m por índice y revienta tras un salto:
todo grupo con offset > ~110 m quedaba con `seat` negativo y **esperaba para
siempre** (2nd Scout, 3rd Squad completo, Mortars, Guide).

Corregido: el asiento se resuelve **POR ARCO** con la función nueva
`FTCS_fnc_trailIndexAtArc`, igual que hace carretera (`sample(headDist − offset)`).
Nunca se divide por `recordStep`. Ver **Lección 20**.

**✘ TERCER PROBLEMA — el follower SALTABA puntos (aplicado PASO 1 + PASO 2):**

Con el arco resuelto, los asientos ya eran correctos, pero el follower seguía
mandando cada grupo **directamente a su asiento**. El motor tomaba el camino más
corto, así que la columna **no pisaba la traza**: cortaba esquinas y nunca pasaba
por los puntos grabados.

**Solución aplicada: el CARRIL (lane).** Ver **Lección 22**.

- Nuevo campo de registro `trailCursorIdx`: último índice de traza **pisado de
  verdad** por el grupo. Se siembra a `-1` en `fn_trailColumnSet`.
- El follower ya **no** manda al asiento: manda a `min(cursor + 1, seat, maxIdx)`,
  es decir **un punto por tick**. El cursor avanza sólo al llegar
  (`arriveDist = max(1.5, segLen * 0.35)`, proporcional para que un segmento de
  puente de 100 m sea alcanzable).
- Timeout de 20 s por punto inalcanzable (salta uno y loguea `***`).
- **El puente ya no necesita caso especial:** mientras la traza está cortada,
  `maxIdx` no crece, `cursor + 1` no existe y el grupo espera en la orilla. Cuando
  aparece un punto al otro lado, el grupo recibe **ese único segmento real** y el
  motor lo resuelve por el deck.

**✘ CUARTO PROBLEMA — el carril de 1 índice: tirones y adelantamientos
(corregido, ver Lección 23):**

1. **Tirones:** el objetivo era `cursor + 1` con un tick de **1 s**. Un soldado anda
   ~1,4 m en 1 s, así que nunca alcanzaba los 2 m antes del siguiente tick, y cada
   `move` reiniciaba el pathfinding → **arranca, frena, arranca, frena**.
   *Corrección:* el cursor es una POSICIÓN que avanza con un `while` sobre todos los
   puntos alcanzados; el objetivo va con **look-ahead (+3 índices)**; tick a **0,35 s**;
   y **catch-up** (si el grupo está a más de 12 m de su punto de cursor, salta al
   índice más cercano de los siguientes 60).
2. **Adelantamientos:** el techo era sólo doctrinal, así que si uno se atascaba el de
   detrás tenía su propio asiento libre y lo pasaba.
   *Corrección:* `seat(k) = min( seatDoctrinal(k), seat(k-1) )` — el de detrás nunca
   pasa del techo del de delante. Mientras la columna fluye el `min` no hace nada
   (el doctrinal es menor), así que el espaciado no se toca.

**Pendiente de verificar en juego:** fluidez (sin tirones), que nadie adelante, y el
cruce de puente completo.

**NO hecho (Paso 3, descartado por el usuario):** portar el carril a ROAD.

### 6. Cómo verificar (próxima sesión, en este orden)

1. **Salir a 3DEN y volver a entrar** — OBLIGATORIO y causa del error anterior.
   Hay una función nueva en `description.ext` y un *Restart* in-game no recompila
   `CfgFunctions`. Confirmación de que ha funcionado: en el RPT ya **no** aparece
   `Undefined variable ftcs_fnc_groupawakenformarch`.
2. Con `FTCS_Debug_Mode` activo, ordenar `PLT_TRAIL_COLUMN` y buscar en el RPT:
   - `[FTCS][MARCH] group 'X' awakened (...)` → el despertar de la IA funciona.
   - `[FTCS][TRAIL][QUEUE] 'HQ ... Command Element' off=1 seat=<maxIdx> -> SEAT`
     como **primera** línea de la cadena → el RTO va delante.
   - `... -> HOLDS (depth not walked yet)` en los grupos profundos al arrancar.
3. Cruzar un puente y comprobar que **nadie entra** hasta que el líder graba al otro
   lado, y que después entran **uno a uno, de delante a atrás**.

### 7. Pendientes abiertos que salieron de esta sesión

- **PENDING-5** (`FTCS_Programming_Lessons.md`): `_slotOrder` está **duplicado** en
  `fn_formationsRoadColumnSet` y `fn_trailColumnSet`. Extraer a
  `FTCS_fnc_columnSlotOrder` cuando se toque la columna de carretera.
- **`fn_formationsTrailCompactColumn`** reescribe `trailOffsetDist` **sin avisar a la
  cola**, y su lógica es del modelo anterior. Hay que re-derivar la cadena o impedir
  Compact durante un cruce. **No se ha tocado.**
- **Lección 14** del fichero de lecciones sigue describiendo el modelo de **arcos**
  (`trailQueueInheritArc`), que fue abandonado. Marcarla como histórica.
- Detección de puentes como sistema propio (hoy es consecuencia del congelamiento de
  la traza, no un detector explícito), y reutilización para otros cortes
  (claros de bosque, zonas de peligro).
- Columna de carretera (`fn_formationsRoadColumnSet`) y su tratamiento de puentes:
  se dejaron explícitamente para después.

### 8. Aviso de compilación

> ⚠️ **NUEVA FUNCIÓN EN `CfgFunctions`:** `groupAwakenForMarch`.
> Es imprescindible **salir de la misión → editor 3DEN → volver a entrar**.
> Un *Restart* in-game no recompila `description.ext` y las llamadas fallarán con
> `Undefined variable FTCS_fnc_groupAwakenForMarch`.
