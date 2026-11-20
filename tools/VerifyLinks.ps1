# =============================================================================
# FTCS - VERIFICADOR DE SINCRONIA MISIÓN <-> REPOSITORIO
# =============================================================================
# Comprueba que cada misión enlazada al repositorio está leyendo REALMENTE el
# contenido del repositorio. No comprueba si el enlace existe (eso lo hace
# Windows): comprueba si el CONTENIDO coincide, que es lo que rompe Arma.
#
# Cuándo usarlo:
#   - Antes de abrir Arma, después de editar description.ext / init.sqf.
#   - Cuando Arma cargue una función que ya no existe, o cargue una versión vieja.
#
# Por qué existe:
#   Functions/, UI/, Doctrines/ y tools/ son JUNCTIONS (carpeta -> carpeta):
#   no pueden desincronizarse.
#   description.ext, init.sqf y LinkMission.bat son HARDLINKS (fichero -> fichero).
#   Un hardlink se separa del repo en cuanto un editor REESCRIBE el fichero en
#   lugar de modificarlo en sitio: el enlace sigue pareciendo correcto, pero el
#   contenido deja de ser el del repo. Era exactamente el fallo del 2026-11-17.
#
# Uso:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\VerifyLinks.ps1
# =============================================================================

$RepoRoot = "C:\Users\Usuario\Desktop\Arma_3_code\FTCS_Development"
$MissionsRoot = "C:\Users\Usuario\Documents\Arma 3 - Other Profiles\PLAYER%201\missions"

# Solo se comprueban las misiones FTCS: las demas carpetas del perfil pertenecen
# a otros proyectos y no deben tocarse ni avisarse.
$MissionFilter = "FTCS_*"

# Elementos compartidos como FICHERO (los unicos que pueden desincronizarse)
$SharedFiles = @("description.ext", "init.sqf")
# Elementos compartidos como CARPETA (junctions: se informan, nunca fallan)
$SharedDirs = @("Functions", "Doctrines", "UI", "tools")

Clear-Host
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "   FTCS - VERIFICACION DE SINCRONIA CON EL REPOSITORIO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $RepoRoot)) {
    Write-Host "[ERROR] No existe el repositorio: $RepoRoot" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path $MissionsRoot)) {
    Write-Host "[ERROR] No existe la carpeta de misiones: $MissionsRoot" -ForegroundColor Red
    exit 2
}

$problems = 0
$warnings = 0

# ---- Hash de referencia del repositorio ------------------------------------
$repoHashes = @{}
foreach ($f in $SharedFiles) {
    $p = Join-Path $RepoRoot $f
    if (Test-Path $p) {
        $repoHashes[$f] = (Get-FileHash -Path $p -Algorithm MD5).Hash
    } else {
        Write-Host "[WARN] Falta en el repo: $f" -ForegroundColor DarkYellow
        $warnings++
    }
}

$misiones = Get-ChildItem $MissionsRoot -Directory | Where-Object { $_.Name -like $MissionFilter }

if ($misiones.Count -eq 0) {
    Write-Host "[WARN] No hay misiones '$MissionFilter' en $MissionsRoot" -ForegroundColor DarkYellow
    exit 1
}

foreach ($m in $misiones) {
    Write-Host "$($m.Name)" -ForegroundColor Cyan

    # --- ficheros compartidos: el contenido debe ser identico -----------------
    foreach ($f in $SharedFiles) {
        $dst = Join-Path $m.FullName $f
        if (-not (Test-Path $dst)) {
            continue
        }
        $item = Get-Item $dst -Force
        $dstHash = (Get-FileHash -Path $dst -Algorithm MD5).Hash

        if ($repoHashes.ContainsKey($f) -and $dstHash -eq $repoHashes[$f]) {
            Write-Host ("  [OK]     {0,-18} {1}" -f $f, "contenido identico al repo") -ForegroundColor Green
        } else {
            $linkType = if ($item.LinkType) { $item.LinkType } else { "archivo real (sin enlace)" }
            Write-Host ("  [FALLO]  {0,-18} contenido DISTINTO al repo  ({1})" -f $f, $linkType) -ForegroundColor Red
            Write-Host ("           repo={0}  mision={1}" -f $repoHashes[$f], $dstHash) -ForegroundColor DarkGray
            Write-Host "           Arma cargara este contenido, NO el del repositorio." -ForegroundColor Red
            Write-Host "           Arreglo: reenlazar, o copiar el fichero del repo encima." -ForegroundColor Red
            $problems++
        }
    }

    # --- carpetas compartidas: informativo -----------------------------------
    foreach ($d in $SharedDirs) {
        $dst = Join-Path $m.FullName $d
        if (-not (Test-Path $dst)) {
            Write-Host ("  [WARN]   {0,-18} no enlazada en esta mision" -f $d) -ForegroundColor DarkYellow
            $warnings++
            continue
        }
        $item = Get-Item $dst -Force
        if ($item.LinkType -eq "Junction") {
            $targetTxt = if ($item.Target -is [array]) { $item.Target[0] } else { $item.Target }
            Write-Host ("  [OK]     {0,-18} junction -> {1}" -f $d, $targetTxt) -ForegroundColor Green
        } else {
            # Una copia real de Functions/ es el peor caso: el codigo se congela.
            Write-Host ("  [FALLO]  {0,-18} es un elemento REAL, no un junction" -f $d) -ForegroundColor Red
            Write-Host "           El codigo de esta mision NO se actualiza con el repo." -ForegroundColor Red
            $problems++
        }
    }

    Write-Host ""
}

# ---- Resumen ---------------------------------------------------------------
Write-Host "======================================================" -ForegroundColor Cyan
if ($problems -eq 0) {
    Write-Host " RESULTADO: OK - todas las misiones leen el repositorio." -ForegroundColor Green
    if ($warnings -gt 0) { Write-Host " Avisos: $warnings" -ForegroundColor DarkYellow }
    exit 0
} else {
    Write-Host " RESULTADO: $problems PROBLEMA(S) - Arma NO esta leyendo el repo." -ForegroundColor Red
    Write-Host " Solucion rapida: ejecutar LinkMission.bat y elegir la mision afectada." -ForegroundColor Yellow
    exit 1
}