# lib_trailing_policy_live.ps1 -- Wire LIVE ATIVO do motor de politicas de saida.
#
# Liga Resolve-ExitPolicyGated + Get-ExitDecision ao trailing REAL: a cada ciclo
# computa a politica gated por tendencia/regime e APLICA o trailing stop na
# posicao (ratchet-only). NAO e shadow -- age de verdade.
#
# SEGURANCA (anti-duplicata / anti-double-sell -- licao dos 178 stops dup):
#  - So MEXE no stop (stopCurrent do journal), ratchet-only (nunca afrouxa).
#  - NAO executa parciais/saidas: isso continua dono do Invoke-ExitIntelligenceAuto
#    (um unico dono por acao -> sem venda duplicada).
#  - O push pra corretora continua sendo o UNICO Sync-TrailingToExchange (com trava
#    anti-disparo). Este motor so grava no journal; o sync existente empurra.
#  - E logica de SAIDA: o stop INICIAL (risco 1%) nao muda. Gate defere ao trailing
#    ATUAL no regime bear corrente (mudanca de comportamento ~zero ate virar bull).
#
# Requer: lib_trailing_baseline + lib_trailing_policy. PURO (decisao+apply em memoria).

function Get-TrailingCandleMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Candles,
        [int] $SmaPeriod = 20,
        [int] $AtrPeriod = 14
    )
    $bars = @($Candles)
    if ($bars.Count -eq 0) { return $null }
    $closes = @($bars | ForEach-Object { [double]$_.close })
    $lastClose = $closes[-1]

    $smaWin = if ($closes.Count -ge $SmaPeriod) { $closes[($closes.Count-$SmaPeriod)..($closes.Count-1)] } else { $closes }
    $sma = ($smaWin | Measure-Object -Average).Average

    $trs = New-Object System.Collections.ArrayList
    for ($i = 1; $i -lt $bars.Count; $i++) {
        $h = [double]$bars[$i].high; $l = [double]$bars[$i].low; $cp = [double]$bars[$i-1].close
        $tr = [math]::Max($h - $l, [math]::Max([math]::Abs($h - $cp), [math]::Abs($l - $cp)))
        [void]$trs.Add($tr)
    }
    $atrWin = if ($trs.Count -ge $AtrPeriod) { $trs[($trs.Count-$AtrPeriod)..($trs.Count-1)] } else { @($trs) }
    $atr = if ($atrWin.Count -gt 0) { ($atrWin | Measure-Object -Average).Average } else { 0.0 }

    return @{
        last_close = $lastClose
        sma        = [math]::Round($sma, 8)
        atr        = [math]::Round($atr, 8)
        trend_up   = ($lastClose -gt $sma)
    }
}

function Get-PositionExitDecision {
    <#
    .SYNOPSIS
    Decisao de saida gated p/ UMA posicao viva (candles + regime). Pura: nao age.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Position,   # {market,side,entry,stop,stopCurrent,peak,openedAt}
        [Parameter(Mandatory)] [object[]] $Candles,
        [string] $Regime = ""
    )
    $side  = if ($Position.side) { [string]$Position.side } else { "LONG" }
    $entry = [double]$Position.entry
    $initStop = if ($Position.stop) { [double]$Position.stop } else { [double]$Position.stopCurrent }
    $curStop  = if ($Position.stopCurrent) { [double]$Position.stopCurrent } else { $initStop }
    $isLong = ($side -ne "SHORT")
    $risk = if ($isLong) { $entry - $initStop } else { $initStop - $entry }

    $m = Get-TrailingCandleMetrics -Candles $Candles
    if ($null -eq $m -or $risk -le 0) { return $null }

    $peak = if ($Position.peak) { [double]$Position.peak } else { $m.last_close }
    $rNow = if ($isLong) { ($m.last_close - $entry) / $risk } else { ($entry - $m.last_close) / $risk }

    $barsHeld = 1
    try {
        if ($Position.openedAt) {
            $d = ([datetime]::Now - [datetime]$Position.openedAt).TotalDays
            $barsHeld = [math]::Max(1, [int][math]::Floor($d))
        }
    } catch { }

    $pol = Resolve-ExitPolicyGated -TrendUp ([bool]$m.trend_up) -Regime $Regime -Direction $side
    $ctx = @{
        side = $side; entry = $entry; risk = $risk; r_now = $rNow
        peak = $peak; current_stop = $curStop; remaining_size = 1.0
        bars_held = $barsHeld; signals = 0; atr = $m.atr
    }
    $dec = Get-ExitDecision -Policy $pol -Context $ctx

    $wouldMove = $false
    if ($null -ne $dec.new_stop) {
        $wouldMove = if ($isLong) { [double]$dec.new_stop -gt $curStop } else { [double]$dec.new_stop -lt $curStop }
    }

    return [PSCustomObject]@{
        ts            = (Get-Date).ToString("o")
        market        = [string]$Position.market
        side          = $side
        regime        = $Regime
        trend_up      = [bool]$m.trend_up
        selected      = $pol.selected
        gate_reason   = $pol.gate_reason
        action        = $dec.action
        r_now         = [math]::Round($rNow, 3)
        current_stop  = $curStop
        new_stop      = $dec.new_stop
        would_move    = $wouldMove
        size_pct      = $dec.size_pct
        atr           = $m.atr
        last_close    = $m.last_close
    }
}

function Invoke-TrailingPolicyLive {
    <#
    .SYNOPSIS
    Aplica o trailing gated nas posicoes (ratchet-only no stopCurrent em memoria).
    NAO persiste nem empurra -- o caller faz Save-TrailingPositions + Sync existente.
    Retorna { positions (modificadas); changes }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Positions,
        [Parameter(Mandatory)] [hashtable] $CandleMap,   # market -> candles
        [string] $Regime = ""
    )
    $changes = New-Object System.Collections.ArrayList
    foreach ($pos in $Positions) {
        $mk = [string]$pos.market
        $candles = $CandleMap[$mk]
        if (-not $candles -or @($candles).Count -lt 2) { continue }

        $dec = Get-PositionExitDecision -Position $pos -Candles @($candles) -Regime $Regime
        if ($null -eq $dec) { continue }

        # so aplica STOP, ratchet-only (would_move ja garante direcao). Parciais/saidas: outro dono.
        if ($dec.would_move -and $null -ne $dec.new_stop) {
            $old = [double]$pos.stopCurrent
            $pos.stopCurrent = [double]$dec.new_stop
            [void]$changes.Add([PSCustomObject]@{
                ts=$dec.ts; market=$mk; side=$dec.side; selected=$dec.selected
                old_stop=$old; new_stop=[double]$dec.new_stop; r_now=$dec.r_now
                trend_up=$dec.trend_up; regime=$Regime; reason=$dec.gate_reason
            })
        }
    }
    return [PSCustomObject]@{ positions = $Positions; changes = @($changes) }
}

function Get-RegimeFromState {
    [CmdletBinding()]
    param([string] $Path = "journal/regime_state.json")
    try {
        if (Test-Path $Path) {
            $j = Get-Content $Path -Raw | ConvertFrom-Json
            if ($j.regime) { return [string]$j.regime }
            if ($j.current_regime) { return [string]$j.current_regime }
        }
    } catch { }
    return ""
}

function Write-TrailingPolicyAudit {
    # Audit trail das acoes REAIS aplicadas (mandatorio p/ live -- nao e shadow).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Changes,
        [string] $Path = "journal/trailing_policy_audit.jsonl"
    )
    if (@($Changes).Count -eq 0) { return $true }
    try {
        $dir = Split-Path $Path -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        foreach ($c in $Changes) { Add-Content -Path $Path -Value ($c | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8 }
        return $true
    } catch {
        Write-Warning "Write-TrailingPolicyAudit falhou: $($_.Exception.Message)"
        return $false
    }
}
