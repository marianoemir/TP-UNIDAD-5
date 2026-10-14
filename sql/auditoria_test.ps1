# ============================================================================
# auditoria_test.ps1 - Parte B.2: corre la secuencia de prueba con psql y agrega
# un intento de CONEXION fallido real (contrasena incorrecta de app_web).
#
# Por que con psql y no con pgAdmin: psql -f manda cada sentencia por separado, asi
# el log muestra una linea LOG por sentencia. Y un login con clave incorrecta genera
# un FATAL del motor (distinto de fn_autenticar con 0 filas, que no deja error).
#
# SE EJECUTA SOLO contra la base propia (copia_u5). Requiere la auditoria activa
# (log_connections=on, log_disconnections=on, log_statement=all).
#
# Uso, desde la raiz del repo, en PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\sql\auditoria_test.ps1 -Psql "C:\Program Files\PostgreSQL\17\bin\psql.exe"
#
# Deja tres marcas en el log para recortarlo despues:
#   auditoria_b: inicio  /  auditoria_test: inicio ... fin  /  auditoria_b: fin
# ============================================================================
param(
    [string]$Psql     = "C:\Program Files\PostgreSQL\17\bin\psql.exe",
    [string]$Servidor = "localhost",
    [int]$Puerto      = 5432,
    [string]$Base     = "copia_u5"
)

if ($Base -in @("postgres", "plantilla_food_store")) {
    Write-Host "Base equivocada ($Base). Usar copia_u5." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $Psql)) {
    Write-Host "No se encuentra psql en: $Psql (usar -Psql con la ruta correcta)" -ForegroundColor Red
    exit 1
}

$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$sql  = Join-Path $aqui "auditoria_test.sql"

# La contrasena de postgres se pide por pantalla: no queda en el historial ni en el repo.
$seg  = Read-Host "Contrasena de postgres" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seg)
$passPostgres = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

function Marca($texto) {
    $env:PGPASSWORD = $passPostgres
    & $Psql -h $Servidor -p $Puerto -U postgres -d $Base -w -q -c "SELECT '$texto' AS marca;" | Out-Null
}

Marca "auditoria_b: inicio"

Write-Host "`n== 1) Secuencia lectura / insercion / actualizacion / fn_autenticar (como postgres) ==" -ForegroundColor Cyan
$env:PGPASSWORD = $passPostgres
& $Psql -h $Servidor -p $Puerto -U postgres -d $Base -w -v ON_ERROR_STOP=1 -f $sql

Write-Host "`n== 2) Intento de conexion con contrasena INCORRECTA (se espera un FATAL) ==" -ForegroundColor Cyan
$env:PGPASSWORD = "clave_incorrecta_audit_test"
& $Psql -h $Servidor -p $Puerto -U app_web -d $Base -w -c "SELECT 1;"
Write-Host "(El error anterior es lo esperado: confirma que la conexion fue rechazada.)" -ForegroundColor Yellow

Marca "auditoria_b: fin"

Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
$passPostgres = $null
Write-Host "`nListo. Ahora buscar en el log la marca 'auditoria_b: inicio' y recortar hasta 'auditoria_b: fin'." -ForegroundColor Green
