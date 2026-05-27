# mentor_calibration_report.ps1 -- CLI wrapper para C.5 calibration dashboard.
# Uso: .\scripts\mentor_calibration_report.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "agents\config.local.ps1") -ErrorAction SilentlyContinue
. (Join-Path $root "agents\lib_mentor_calibration.ps1")

$c = Get-MentorCalibration
Write-Output (Format-CalibrationReport -Calibration $c)
