# lib_mce_gates.ps1 — MCE Gates: Market Context Engine (timing BRT + Fear&Greed)

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Test-BrtTradingWindow {
    <#
    .SYNOPSIS
    Verifica se horário BRT é favorável pra trading.
    Melhor janela: 11h-15h BRT (máximo volume + traders ativo).
    #>
    param(
        [datetime] $Brt = (Get-Date),
        [string] $Regime = "SIDEWAYS"
    )

    $hour = $Brt.Hour

    # Melhores janelas por regime
    $allowedHours = switch ($Regime) {
        "BULL" {
            @(11, 12, 13, 14, 15, 16)  # 11h-16h BRT
        }
        "BEAR" {
            @(14, 15, 16)  # 14h-16h BRT (mercado mais estável)
        }
        default {
            @(11, 12, 13, 14, 15)  # 11h-15h (padrão)
        }
    }

    $allowed = $hour -in $allowedHours
    $action = if ($allowed) { "OK" } else { "WAIT" }

    return [PSCustomObject]@{
        hour_brt = $hour
        allowed = $allowed
        action = $action
        regime = $Regime
        recommended_window = if ($Regime -eq "BULL") { "11h-16h" } elseif ($Regime -eq "BEAR") { "14h-16h" } else { "11h-15h" }
    }
}

function Get-FearGreedIndex {
    <#
    .SYNOPSIS
    Retorna Fear & Greed index simplificado (cache via arquivo).
    Escalas: EXTREME_FEAR (0-25), FEAR (25-45), NEUTRAL (45-55), GREED (55-75), EXTREME_GREED (75-100)
    #>
    param(
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    # Lê do cache (última atualização)
    $cacheFile = Join-Path $JournalDir "fear_greed_cache.json"
    $defaultIndex = 50  # Neutro

    if (Test-Path $cacheFile) {
        try {
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
            if ($cache.index) {
                $index = [int]$cache.index
            } else {
                $index = $defaultIndex
            }
        } catch {
            $index = $defaultIndex
        }
    } else {
        $index = $defaultIndex
    }

    # Mapeia escala
    $level = switch ($index) {
        {$_ -lt 25} { "EXTREME_FEAR" }
        {$_ -lt 45} { "FEAR" }
        {$_ -lt 55} { "NEUTRAL" }
        {$_ -lt 75} { "GREED" }
        default { "EXTREME_GREED" }
    }

    return [PSCustomObject]@{
        index = $index
        level = $level
        trade_recommendation = switch ($level) {
            "EXTREME_FEAR" { "LONG entry mais conservador (medo = oportunidade)" }
            "FEAR" { "LONG entry em confluência forte" }
            "NEUTRAL" { "Entry normal, sem viés" }
            "GREED" { "SHORT considerado, LONG reduzido" }
            "EXTREME_GREED" { "SHORT foco, LONG evitar" }
        }
    }
}

function Invoke-MceGate {
    <#
    .SYNOPSIS
    Combina BRT window + Fear&Greed pra decisão final.
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Regime,
        [datetime] $Brt = (Get-Date),
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    $brtTest = Test-BrtTradingWindow -Brt $Brt -Regime $Regime
    $fg = Get-FearGreedIndex -JournalDir $JournalDir

    # Decisão
    $allows = $brtTest.allowed -and ($fg.level -notmatch "EXTREME")
    $action = if ($allows) { "ALLOW" } else { "RESTRICT" }

    return [PSCustomObject]@{
        market = $Market
        action = $action
        brt_window = $brtTest.action
        hour_brt = $brtTest.hour_brt
        fear_greed = $fg.level
        recommendation = "$($brtTest.action) BRT + $($fg.trade_recommendation)"
    }
}
