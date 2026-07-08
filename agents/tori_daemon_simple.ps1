#!/usr/bin/env pwsh
# tori_daemon_simple.ps1 — Production Tori Daemon (simplified, PS5.1 compatible)
# Date: 2026-07-08
# Purpose: 24/7 scanner for high-confluence Tori trades
# Dependencies: lib_tori_confluence_detector, lib_coinex

$ErrorActionPreference = "SilentlyContinue"

$script:LOG_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon.log"
$script:HEARTBEAT_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon_heartbeat.txt"
$script:STATE_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon_state.json"
$script:SCAN_INTERVAL_MIN = 240
$script:CONFLUENCE_THRESHOLD = 80
$script:ActiveSetups = @()
$script:IsRunning = $true

function Write-Log {
    param([string]$msg, [string]$level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$level] $msg"
    Write-Host $entry
    Add-Content -Path $script:LOG_FILE -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Write-Heartbeat {
    $hb = @{
        timestamp = Get-Date -Format "o"
        status = "alive"
        setups_count = $script:ActiveSetups.Count
    } | ConvertTo-Json
    Set-Content -Path $script:HEARTBEAT_FILE -Value $hb -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Load-Dependencies {
    $libPath = Join-Path $PSScriptRoot "lib_tori_confluence_detector.ps1"
    if (Test-Path $libPath) {
        . $libPath
        Write-Log "Loaded lib_tori_confluence_detector" "INFO"
    }

    $coinexPath = Join-Path $PSScriptRoot "lib_coinex.ps1"
    if (Test-Path $coinexPath) {
        . $coinexPath
        Write-Log "Loaded lib_coinex" "INFO"
    }
}

function Get-MarketCandles {
    param([string]$Market, [string]$Timeframe = "1h")

    try {
        $candles = CoinEx-GetFuturesCandles -market $Market -period $Timeframe -limit 100 -TimeoutSec 10 -ErrorAction Stop
        return @($candles)
    } catch {
        Write-Log "Failed to fetch $Market [$Timeframe]: $($_.Message)" "WARN"
        return $null
    }
}

function Analyze-Market {
    param([string]$Market)

    try {
        $candles = Get-MarketCandles -Market $Market -Timeframe "1h"
        if (-not $candles -or $candles.Count -lt 20) {
            return $null
        }

        $highs = @($candles | ForEach-Object { [double]$_.high })
        $lows = @($candles | ForEach-Object { [double]$_.low })
        $closes = @($candles | ForEach-Object { [double]$_.close })
        $volumes = @($candles | ForEach-Object { [double]$_.volume })

        $score = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType "LONG" -TrendlineStartPrice $closes[-1] -TrendlineTouches 2

        if ($score.total_score -ge $script:CONFLUENCE_THRESHOLD) {
            return @{
                market = $Market
                timeframe = "1h"
                confluence_score = $score.total_score
                signals = if ($score.signals_fired) { ($score.signals_fired -join ",") } else { "none" }
                entry_price = [Math]::Round($closes[-1], 8)
                timestamp = Get-Date -Format "o"
            }
        }
    } catch {
        Write-Log "Error analyzing $Market : $($_.Message)" "WARN"
    }

    return $null
}

function Invoke-ScanCycle {
    Write-Log "--- SCAN CYCLE START ---" "INFO"
    $startTime = Get-Date

    try {
        $pairs = @("BTCUSDT", "ETHUSDT", "BNBUSDT", "XRPUSDT", "SOLUSDT", "ADAUSDT", "DOGEUSDT", "AVAXUSDT", "LINKUSDT", "UNIUSDT")
        $newSetups = @()

        foreach ($pair in $pairs) {
            $setup = Analyze-Market -Market $pair
            if ($setup) {
                $newSetups += $setup
                $script:ActiveSetups += $setup
                Write-Log "OPPORTUNITY: $($pair) score=$($setup.confluence_score) signals=$($setup.signals)" "INFO"
            }

            Start-Sleep -Milliseconds 100
        }

        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        Write-Log "Scan complete: $($newSetups.Count) opportunities found in $([Math]::Round($elapsed, 1))s" "INFO"

        if ($newSetups.Count -gt 0) {
            $state = @{
                timestamp = Get-Date -Format "o"
                setups = $newSetups
                total_active = $script:ActiveSetups.Count
            } | ConvertTo-Json -Depth 5
            Set-Content -Path $script:STATE_FILE -Value $state -Encoding UTF8 -ErrorAction SilentlyContinue
        }

    } catch {
        Write-Log "Scan cycle error: $($_.Message)" "ERROR"
    }
}

function Start-ToriDaemon {
    Write-Log "=== TORI DAEMON STARTED ===" "INFO"

    Load-Dependencies

    $nextScan = Get-Date

    while ($script:IsRunning) {
        $now = Get-Date

        if ($now -ge $nextScan) {
            Invoke-ScanCycle
            $nextScan = $now.AddMinutes($script:SCAN_INTERVAL_MIN)
            Write-Log "Next scan: $nextScan" "INFO"
        }

        Write-Heartbeat

        Start-Sleep -Seconds 60
    }

    Write-Log "=== TORI DAEMON STOPPED ===" "INFO"
}

Start-ToriDaemon
