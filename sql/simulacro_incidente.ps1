<#
.SYNOPSIS
  Orquesta el simulacro de incidente de la Parte C (usa sql/simulacro_incidente.sql).

.DESCRIPTION
  Ejecuta psql una vez por paso, conectandose como el login correspondiente, para que el log
  del servidor registre al usuario real de cada paso. Verifica el resultado esperado de cada
  paso y deja una constancia en docs/constancia_escalamiento.txt.
  SOLO contra la base propia de desarrollo.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\sql\simulacro_incidente.ps1 `
      -Psql "C:\Program Files\PostgreSQL\18\bin\psql.exe"
  Agregar -Limpiar para eliminar el usuario y el login de prueba al terminar.

.NOTES
  Antes de correrlo en el equipo que captura el log: activar log_statement = 'all'
  (con 'mod' no se registran los SELECT de los pasos 1 a 3).
#>
param(
    [string]$Psql = 'psql',
    [string]$Servidor = 'localhost',
    [int]$Puerto = 5432,
    [string]$Base = 'copia_u5',
    [string]$UsuarioAdmin = 'postgres',
    [string]$PassAdmin,
    [string]$PassApp = 'cambiar_en_produccion',
    [string]$PassSoporte = 'Sim-Soporte-2026',
    [string]$Constancia,
    [switch]$Limpiar
)

$ErrorActionPreference = 'Stop'
$sql = Join-Path $PSScriptRoot 'simulacro_incidente.sql'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $Constancia) { $Constancia = Join-Path $repo 'docs\constancia_escalamiento.txt' }

if (-not (Get-Command $Psql -ErrorAction SilentlyContinue)) {
    throw "No se encuentra psql ('$Psql'). Usar -Psql con la ruta completa, por ejemplo C:\Program Files\PostgreSQL\18\bin\psql.exe"
}
if ($Base -in @('postgres', 'plantilla_food_store')) {
    throw "Base equivocada ($Base). El simulacro se ejecuta solo contra la base propia (copia_u5)."
}
if (-not $PassAdmin) {
    $ss = Read-Host "Contrasena del usuario $UsuarioAdmin" -AsSecureString
    $PassAdmin = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss))
}
$env:PGCLIENTENCODING = 'UTF8'

function Invoke-Paso {
    param([int]$Paso, [string]$Usuario, [string]$Clave)
    $env:PGPASSWORD = $Clave
    $outF = [IO.Path]::GetTempFileName()
    $errF = [IO.Path]::GetTempFileName()
    $argList = @('-X', '-w', '-h', $Servidor, '-p', $Puerto, '-U', $Usuario, '-d', $Base,
                 '-v', "paso=$Paso", '-v', "pass_soporte=$PassSoporte", '-v', 'ON_ERROR_STOP=0',
                 '-f', ('"{0}"' -f $sql))
    $proc = Start-Process -FilePath $Psql -ArgumentList $argList -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $outF -RedirectStandardError $errF
    $o = Get-Content $outF -Raw -Encoding UTF8
    $e = Get-Content $errF -Raw -Encoding UTF8
    if (-not $o) { $o = '' }
    if (-not $e) { $e = '' }
    Remove-Item $outF, $errF -ErrorAction SilentlyContinue
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    [pscustomobject]@{ Paso = $Paso; Usuario = $Usuario; Salida = $o; Errores = $e; Codigo = $proc.ExitCode }
}

function Get-Filas {
    param([string]$Texto)
    $m = [regex]::Matches($Texto, '\((\d+) (?:fila|filas|row|rows)\)')
    foreach ($x in $m) { [int]$x.Groups[1].Value }
}

$reporte = New-Object System.Collections.Generic.List[string]
function Log-Linea { param([string]$t) Write-Host $t; $reporte.Add($t) }

Log-Linea "SIMULACRO DE INCIDENTE - Parte C"
Log-Linea ("Fecha: {0}   Servidor: {1}:{2}   Base: {3}" -f (Get-Date -Format 's'), $Servidor, $Puerto, $Base)
Log-Linea "Recordatorio: log_statement debe estar en 'all' para registrar los SELECT."
Log-Linea ""

# Paso 0: preparacion
$r0 = Invoke-Paso -Paso 0 -Usuario $UsuarioAdmin -Clave $PassAdmin
Log-Linea "[paso 0] Preparacion (usuario de prueba y login soporte_sim) - codigo psql: $($r0.Codigo)"
if ($r0.Errores -match 'ERROR:|FATAL:') { Log-Linea $r0.Errores; throw "Fallo la preparacion. Revisar el mensaje." }

# Paso 1: intentos fallidos (app_web)
$r1 = Invoke-Paso -Paso 1 -Usuario 'app_web' -Clave $PassApp
$f1 = @(Get-Filas $r1.Salida)
$ok1 = ($f1.Count -eq 5) -and (@($f1 | Where-Object { $_ -ne 0 }).Count -eq 0)
Log-Linea ("[paso 1] 5 intentos fallidos como app_web: {0} resultados con 0 filas -> {1}" -f $f1.Count, $(if ($ok1) { 'OK' } else { 'REVISAR' }))
if ($r1.Errores -match 'ERROR:|FATAL:') { Log-Linea $r1.Errores }

# Paso 2: login exitoso (app_web)
$r2 = Invoke-Paso -Paso 2 -Usuario 'app_web' -Clave $PassApp
$f2 = @(Get-Filas $r2.Salida)
$ok2 = ($f2.Count -eq 1) -and ($f2[0] -eq 1)
Log-Linea ("[paso 2] Inicio de sesion exitoso como app_web: {0} fila -> {1}" -f $(if ($f2.Count) { $f2[0] } else { '?' }), $(if ($ok2) { 'OK' } else { 'REVISAR' }))
if ($r2.Errores -match 'ERROR:|FATAL:') { Log-Linea $r2.Errores }

# Paso 3: lectura masiva (soporte_sim)
$r3 = Invoke-Paso -Paso 3 -Usuario 'soporte_sim' -Clave $PassSoporte
$f3 = @(Get-Filas $r3.Salida)
$n3 = if ($f3.Count) { ($f3 | Measure-Object -Maximum).Maximum } else { 0 }
$ok3 = $n3 -ge 20000
Log-Linea ("[paso 3] Lectura masiva de usuario como soporte_sim: {0} filas leidas -> {1}" -f $n3, $(if ($ok3) { 'OK' } else { 'REVISAR' }))
if ($r3.Errores -match 'ERROR:|FATAL:') { Log-Linea $r3.Errores }

# Paso 4: escalamiento (soporte_sim). Los tres intentos deben fallar.
$r4 = Invoke-Paso -Paso 4 -Usuario 'soporte_sim' -Clave $PassSoporte
$errores4 = [regex]::Matches($r4.Errores, 'ERROR:').Count
$falla = ($errores4 -eq 3)
Log-Linea ""
Log-Linea "[paso 4] Intento de escalamiento como soporte_sim (3 intentos): $errores4 de 3 fallaron"
Log-Linea "---- mensajes del servidor ----"
Log-Linea $r4.Errores.Trim()
Log-Linea "-------------------------------"
if ($falla) {
    Log-Linea "RESULTADO: el escalamiento FALLO en los 3 intentos. El esquema de permisos de la Parte A resiste."
} else {
    Log-Linea "HALLAZGO: al menos un intento de escalamiento NO fallo. El esquema de la Parte A tiene un defecto: corregir roles.sql antes de continuar."
}

if ($Limpiar) {
    $r9 = Invoke-Paso -Paso 9 -Usuario $UsuarioAdmin -Clave $PassAdmin
    Log-Linea ""
    Log-Linea "[limpieza] Usuario y login de prueba eliminados - codigo psql: $($r9.Codigo)"
    if ($r9.Errores -match 'ERROR:|FATAL:') { Log-Linea $r9.Errores }
}

Set-Content -Path $Constancia -Value ($reporte -join "`r`n") -Encoding UTF8
Write-Host ""
Write-Host "Constancia guardada en: $Constancia"
