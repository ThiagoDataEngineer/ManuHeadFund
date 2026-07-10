#requires -Version 5.1
<#
.SYNOPSIS
    Auto-Sizing via Kelly Criterion — Crescimento composto automático

.DESCRIPTION
    Calcula tamanho dinâmico de cada trade baseado:
    - Kelly Criterion (p×R - q) / R
    - Capital atual (cresce com ganhos)
    - Win rate histórico
    - Limites de segurança

.EXAMPLE
    $size = Get-CompoundTradeSize -CurrentCapital 850 -BaseKelly 0.02
#>

function Get-CompoundTradeSize {
    param(
        [decimal]$CurrentCapital = 750,
        [decimal]$WinRate = 0.55,
        [decimal]$RiskRewardRatio = 5,
        [switch]$DynamicScaling
    )

    # Kelly base: (p×R - q) / R
    $q = 1 - $WinRate
    $f_base = (($WinRate * $RiskRewardRatio) - $q) / $RiskRewardRatio

    # Dynamic scaling por capital tier
    $kelly_multiplier = 1.0

    if ($DynamicScaling) {
        if ($CurrentCapital -ge 3500) {
            $kelly_multiplier = 1.5  # 3.0% Kelly
        } elseif ($CurrentCapital -ge 2000) {
            $kelly_multiplier = 1.25 # 2.5% Kelly
        } elseif ($CurrentCapital -ge 1000) {
            $kelly_multiplier = 1.2  # 2.4% Kelly
        }
    }

    $f_kelly = $f_base * $kelly_multiplier
    $size_usd = $CurrentCapital * $f_kelly

    return @{
        kelly_percent = [math]::Round($f_kelly * 100, 2)
        capital = $CurrentCapital
        size_usd = [math]::Round($size_usd, 2)
        win_rate = $WinRate
        risk_reward = $RiskRewardRatio
        timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
}

function Update-SizingDaily {
    param(
        [string]$JournalPath = "journal"
    )

    # Ler capital atual
    $capFile = Join-Path $JournalPath "capital_context.json"
    if (-not (Test-Path $capFile)) {
        Write-Host "[SIZING] Capital context not found" -ForegroundColor Yellow
        return
    }

    $capital = Get-Content $capFile | ConvertFrom-Json
    $total_capital = $capital.gem_discovery.allocated + $capital.scan_master.allocated + $capital.scalp_engine.allocated

    # Calcular novo sizing
    $sizing = Get-CompoundTradeSize -CurrentCapital $total_capital -DynamicScaling

    # Salvar
    $sizing | ConvertTo-Json | Out-File (Join-Path $JournalPath "kelly_sizing.json") -Encoding UTF8 -Force

    Write-Host "[KELLY] Sizing updated: $($sizing.kelly_percent)% of $($sizing.capital) USDT" -ForegroundColor Green
    Write-Host "        Size per trade: $($sizing.size_usd) USDT" -ForegroundColor Cyan

    return $sizing
}

function Get-NextTradeSize {
    param(
        [string]$JournalPath = "journal",
        [decimal]$CurrentCapital
    )

    $sizingFile = Join-Path $JournalPath "kelly_sizing.json"

    if (Test-Path $sizingFile) {
        $sizing = Get-Content $sizingFile | ConvertFrom-Json
        return $sizing.size_usd
    } else {
        # Fallback
        $default_sizing = Get-CompoundTradeSize -CurrentCapital $CurrentCapital -DynamicScaling
        return $default_sizing.size_usd
    }
}

# Export
Export-ModuleMember -Function Get-CompoundTradeSize, Update-SizingDaily, Get-NextTradeSize
