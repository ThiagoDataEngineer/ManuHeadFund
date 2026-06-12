# lib_llm_quota_optimizer.ps1 — LLM Quota Optimization & Rate Limiting
# Context: Groq free tier = 14.4K reqs/dia. Mesa 3 drones × 6-12s latencia cada = burst heavy.
# Solution: (1) Skip Mesa trivial signals, (2) Rate limit inter-drone, (3) Cache LLM responses
# Impact: 6x reduction (5min → 30min interval) + aggressive filtering = ~2.4K reqs/dia (5.8 days runway on 14.4K)

# ── Rate Limiter: Throttle drones para evitar burst Groq ──────────────────────
# Trata: Mesa dispara 3 drones em paralelo; se 3 markets simu → 9 drones = 429
# Solução: fila FIFO com min delay entre drones (stagger)

$script:RATE_LIMIT_STATE = @{
    lastDroneCallTime = $null  # timestamp do ultimo call
}

function Invoke-DroneLimited {
    <#
    .SYNOPSIS
    Wrapper para chamar drone (Termal/Radar/Lidar) com rate limiting intercalado.
    .PARAMETER DroneFunc
    Nome funcao: "Invoke-ThermalDrone", etc
    .PARAMETER RateLimitMs
    Minimo delay entre drones (ms) — 2000ms padrão
    #>
    param(
        [Parameter(Mandatory=$true)][string]$DroneFunc,
        [Parameter(Mandatory=$true)][hashtable]$DroneParams,
        [Parameter(Mandatory=$false)][int]$RateLimitMs = 2000,
        [Parameter(Mandatory=$false)][bool]$SkipLimit = $false
    )

    if ($script:RATE_LIMIT_STATE.lastDroneCallTime -and -not $SkipLimit) {
        $elapsed = [int]((Get-Date) - $script:RATE_LIMIT_STATE.lastDroneCallTime).TotalMilliseconds
        if ($elapsed -lt $RateLimitMs) {
            $toSleep = $RateLimitMs - $elapsed
            Write-Verbose "[RateLimit] Sleep ${toSleep}ms antes de chamar $DroneFunc"
            Start-Sleep -Milliseconds $toSleep
        }
    }

    $script:RATE_LIMIT_STATE.lastDroneCallTime = Get-Date

    # Invoca funcao dinamicamente com parametros
    $result = & $DroneFunc @DroneParams
    return $result
}

function Test-SmaFlatline {
    <#
    .SYNOPSIS
    Detecta se o par está em consolidação trivial (SMA praticamente plano).
    Retorna $true = SKIP Mesa (não há momentum para analisar).
    .PARAMETER SmaShort
    SMA9 ou equivalente curto
    .PARAMETER SmaLong
    SMA21 ou equivalente longo
    .PARAMETER FlatnessThresholdPct
    Máx % de diferença considerado "plano" (default 2.0%)
    #>
    param(
        [Parameter(Mandatory=$true)][double]$SmaShort,
        [Parameter(Mandatory=$true)][double]$SmaLong,
        [Parameter(Mandatory=$false)][double]$FlatnessThresholdPct = 2.0
    )

    if ($SmaLong -le 0) { return $false }  # Evita divisão por zero

    $diff = [math]::Abs($SmaShort - $SmaLong)
    $diffPct = ($diff / $SmaLong) * 100

    # Se SMA9 e SMA21 divergem < 2%, não há momentum forte = skip Mesa
    return ($diffPct -lt $FlatnessThresholdPct)
}

function New-QuotaTracker {
    <#
    .SYNOPSIS
    Cria tracker para monitorar consumo de quota LLM ao longo do dia.
    .PARAMETER Provider
    "anthropic" | "groq" | "gemini"
    #>
    param(
        [string]$Provider = "groq"
    )

    $path = Join-Path $env:TEMP "llm_quota_${Provider}_$(Get-Date -Format 'yyyy-MM-dd').json"
    
    if (-not (Test-Path $path)) {
        $init = @{
            date             = (Get-Date -Format 'yyyy-MM-dd')
            provider         = $Provider
            callsToday       = 0
            callsLastHour    = 0
            estimatedTotal   = 0
            lastCall         = (Get-Date).ToUniversalTime().ToString("o")
            warnings         = @()
        }
        $init | ConvertTo-Json | Out-File -FilePath $path -Encoding utf8
        return $init
    }

    return (Get-Content $path -Raw | ConvertFrom-Json)
}

function Update-QuotaTracker {
    <#
    .SYNOPSIS
    Incrementa contador após chamada LLM. Retorna $true se ainda está OK, $false se atingiu 80% quota.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Provider,
        [Parameter(Mandatory=$false)][int]$CallsToAdd = 1,
        [Parameter(Mandatory=$false)][int]$DailyQuota = 14400  # Groq free tier
    )

    $path = Join-Path $env:TEMP "llm_quota_${Provider}_$(Get-Date -Format 'yyyy-MM-dd').json"
    
    $tracker = if (Test-Path $path) {
        Get-Content $path -Raw | ConvertFrom-Json
    } else {
        New-QuotaTracker -Provider $Provider
    }

    $tracker.callsToday += $CallsToAdd
    $tracker.lastCall = (Get-Date).ToUniversalTime().ToString("o")
    
    $usedPct = ($tracker.callsToday / $DailyQuota) * 100
    $isOk = $usedPct -lt 80

    if (-not $isOk) {
        $warning = "[QUOTA WARNING] $Provider`: $($tracker.callsToday)/$DailyQuota calls ($([math]::Round($usedPct, 1))%) - activate Mesa skip mode"
        if ($warning -notin $tracker.warnings) {
            $tracker.warnings += $warning
        }
    }

    $tracker | ConvertTo-Json | Out-File -FilePath $path -Encoding utf8 -Force

    return $isOk
}

function Test-MesaSkip {
    <#
    .SYNOPSIS
    Decide se Mesa deve ser pulada para economizar quota.
    Criterios: (1) SMA flatline, (2) No volume spike, (3) Groq quota >80%
    #>
    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$Candidate,  # Tem: sma9, sma21, vol24h_spike, etc
        [Parameter(Mandatory=$false)][bool]$CheckQuota = $true
    )

    # Critério 1: SMA flatline
    if ($Candidate.sma9 -and $Candidate.sma21) {
        if (Test-SmaFlatline -SmaShort $Candidate.sma9 -SmaLong $Candidate.sma21 -FlatnessThresholdPct 2.0) {
            Write-Verbose "[MesaSkip] $($Candidate.market): SMA flatline - skip Mesa"
            return $true
        }
    }

    # Critério 2: Sem volume spike
    if ($Candidate.vol24h_spike -and $Candidate.vol24h_spike -lt 1.5) {
        Write-Verbose "[MesaSkip] $($Candidate.market): Vol spike $($Candidate.vol24h_spike)x < 1.5x - skip Mesa"
        return $true
    }

    # Critério 3: Groq quota esgotando
    if ($CheckQuota) {
        $tracker = New-QuotaTracker -Provider "groq"
        $usedPct = ($tracker.callsToday / 14400) * 100
        if ($usedPct -gt 80) {
            Write-Verbose "[MesaSkip] Groq quota $([math]::Round($usedPct, 1))% > 80% - activate emergency Mesa skip"
            return $true
        }
    }

    return $false
}
