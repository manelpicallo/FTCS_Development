# FTCS — Session Log (estado de trabajo entre sesiones)

> **PARA LA IA QUE RETOMA EL PROYECTO:** lee este fichero DESPUÉS del
> `FTCS (First-Person Tactical Command Simulation) - Documento de Notas….md`
> (Punto 0), `FTCS_Data_Structure_Reference.md` y `FTCS_Programming_Lessons.md`.
> Este fichero NO es documentación de diseño: es el **diario de sesión**, el punto
> exacto donde se dejó el trabajo, qué está probado y qué NO.
>
> Reglas de este fichero:
> - La entrada **más reciente va ARRIBA**, justo debajo de esta cabecera.
> - Cada entrada es un resumen cerrado: qué se tocó, por qué, qué está verificado y
>   qué queda pendiente. No se reescriben entradas antiguas (son histórico).
> - No duplica lecciones: cada hallazgo técnico vive en
>   `FTCS_Programming_Lessons.md` y aquí sólo se referencia por número.
> - Las entradas se escriben en **castellano** (es documentación para el humano),
>   igual que esta cabecera y el documento de diseño.

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
                           líder está elevado = puente), TRIM a 200 m, y al recortar
                           RENUMERA los índices guardados en el registro
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

### 3. BUG CONOCIDO Y ABIERTO — un grupo puede perder su posición

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

**Corrección propuesta (NO aplicada):** hacer el asiento **monótono creciente** por
grupo: guardar el último publicado y no publicar nunca uno menor. Elimina de raíz
cualquier salto hacia atrás, venga del trim, de la cadena o de una muerte.
Aplicarlo en `fn_formationsTrailQueueSync` (un campo más en el registro).

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

### 5. Error de menú encontrado en el RPT (cosmético, sin arreglar)

```
20:41:25  Error Undefined variable: _pltdatad / _parsedsquadsd / _sdatad
          en fn_openSubordinateMenu.sqf (líneas 271-283)
```

`FTCS_Company_Data` no estaba disponible en ese instante; la cadena de
`getOrDefault` se propaga como `undefined`. **El menú sigue funcionando** con nombres
genéricos ("Squad 1"), sólo ensucia el RPT. Arreglo: guard `isNil "FTCS_Company_Data"`
y caption por defecto. Nota: esa lectura de doctrina en runtime es una concesión para
CAPTIONS (Regla 16), no para lógica.

### 6. Comportamiento esperado que NO es un bug

- **Los grupos del fondo tardan en arrancar en el puente**: su asiento es alto (hasta
  ~115 índices = ~230 m de traza) y el líder debe grabar hasta ahí. Es la cascada.
- **El `max`/`tip` baja en el RPT durante el trim**: es el recorte funcionando. Las
  posiciones de los grupos ya se renumeran.
- **Soldados que se caen del puente**: es el pathfinding del motor en un navmesh
  estrecho con varios grupos convergiendo. No se controla desde la lógica.

### 7. Pendientes para la próxima sesión (por prioridad)

1. **Asiento monótono** en `fn_formationsTrailQueueSync` (§3). Es el único bug abierto
   que rompe la columna.
2. **Guard del menú** en `fn_openSubordinateMenu` (§5).
3. **Cláusulas de líder**: grupo sin líder vivo (`isNull (leader _group)`) y líder
   inconsciente. Hoy no se comprueban; el watchdog cubre sólo líder VIVO.
4. **`fn_formationsTrailCompactColumn`** sigue usando otra fórmula (`_rearmost` en
   vivo + `n*3.5`) en vez de `(n-1)*3 + 8`. Unificar.
5. **PENDING-5**: `_slotOrder` duplicado entre road y trail → extraer a una función.
6. **Lección 14** del fichero de lecciones describe el modelo de ARCOS, ya abandonado:
   marcarla como histórica.
7. **Documentar la migración arco→índice final**: la Lección 22 describe un modelo de
   arco que el follower YA NO usa (el arco vive sólo dentro de la cola).

### 8. Aviso de compilación

> ⚠️ **`fn_groupAwakenForMarch` es una función NUEVA en `CfgFunctions`.**
> Es imprescindible **salir de la misión → editor 3DEN → volver a entrar**.
> Un *Restart* in-game no recompila `description.ext`.

---

## SESIÓN 2026-11-15 (mañana/tarde) — Columna TRAIL: cola de cruce (puentes), orden de marcha y despertar de la IA

**Estado:** implementado. **Orden y cascada VERIFICADOS en el RPT** (15:22).
Queda **un solo bloqueo**: recompilar `CfgFunctions` para que exista
`FTCS_fnc_groupAwakenForMarch` (ver §5).
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
