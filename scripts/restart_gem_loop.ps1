#!/usr/bin/env pwsh
# Quick restart script for gem_loop

Write-Host "Killing gem_loop processes..." -ForegroundColor Yellow
Get-Process -Name pwsh -ErrorAction SilentlyContinue |
  Where-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine -like "*gem_loop*" } |
  Stop-Process -Force -ErrorAction SilentlyContinue

Start-Sleep 2

Write-Host "Starting gem_loop..." -ForegroundColor Green
$scriptPath = Join-Path (Split-Path -Parent $PSCommandPath) "gem_loop.ps1"
& $scriptPath -CheckInterval 60
