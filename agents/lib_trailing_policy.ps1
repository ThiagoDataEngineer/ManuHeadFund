# lib_trailing_policy.ps1 -- Politica de saida PURA por tipo de operacao + motor
# de reversao-vs-manter. Sem LLM (barato), deterministico, 100% TDD-able.
#
# Combo (opcoes 1+2):
#   (2) Resolve-ExitPolicy: scalp/swing/short/long/runner -> parametros proprios.
#   (1) Get-ExitDecision: dado os params + contexto da barra, decide
#       HOLD / TIGHTEN(aperta stop) / PARTIAL / EXIT, incluindo o ladder de
#       reversao: 0-1 sinais=HOLD, =tighten_n aperta (nao vende no fundo,
#       trava ganhos -0.5R), >=exit_n sai. Espelhado p/ SHORT.
#
# Plugga no harness: PolicyFn = { param($ctx) Get-ExitDecision -Policy $p -Context $ctx }
# PS 5.1 safe. PURO.

function Resolve-ExitPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TradeType,
        [string] $Direction = "LONG",
        [string] $Regime = ""
    )
    $isShort = ($Direction -eq "SHORT")
    $t = $TradeType.ToLower()

    switch ($t) {
        "scalp" {
            $p = @{
                breakeven_at_r = 0.5
                trail_method   = "chandelier"; trail_atr_mult = 1.5
                partials       = @(@{ at_r = 1.0; pct = 0.6 })
                time_stop_bars = 8
                reversal_exit_signals = 3; reversal_tighten_signals = 2
            }
        }
        "swing" {
            $p = @{
                breakeven_at_r = 1.0
                trail_method   = "chandelier"; trail_atr_mult = $(if ($isShort) { 2.0 } else { 3.0 })
                partials       = $(if ($isShort) { @(@{ at_r=1.0; pct=0.5 }) } else { @(@{ at_r=1.0; pct=0.33 }, @{ at_r=2.0; pct=0.33 }) })
                time_stop_bars = $(if ($isShort) { 40 } else { 60 })
                reversal_exit_signals = 3; reversal_tighten_signals = 2
            }
        }
        "runner" {
            # pos-parcial / em breakeven: ja e "dinheiro da casa". Sem novas parciais.
            # So sai em reversao confirmada; trail largo p/ deixar correr.
            $p = @{
                breakeven_at_r = 0.0
                trail_method   = "chandelier"; trail_atr_mult = 4.0
                partials       = @()
                time_stop_bars = 0
                reversal_exit_signals = 3; reversal_tighten_signals = 2
            }
        }
        default {
            $t = "standard"
            $p = @{
                breakeven_at_r = 1.0
                trail_method   = "chandelier"; trail_atr_mult = $(if ($isShort) { 2.0 } else { 2.5 })
                partials       = @(@{ at_r=1.0; pct=0.5 })
                time_stop_bars = 30
                reversal_exit_signals = 3; reversal_tighten_signals = 2
            }
        }
    }
    $p.trade_type = $t
    $p.direction  = $Direction
    $p.regime     = $Regime   # hook p/ ajuste regime-aware futuro (validar antes de ativar)
    return $p
}


function Get-ExitDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Policy,
        [Parameter(Mandatory)] [hashtable] $Context
    )
    $side    = [string]$Context.side
    $isLong  = ($side -ne "SHORT")
    $entry   = [double]$Context.entry
    $risk    = [double]$Context.risk
    $rNow    = [double]$Context.r_now
    $peak    = [double]$Context.peak
    $curStop = [double]$Context.current_stop
    $remaining = [double]$Context.remaining_size
    $bars    = [int]$Context.bars_held
    $signals = if ($null -ne $Context.signals) { [int]$Context.signals } else { 0 }
    $atr = 0.0
    if ($null -ne $Context.atr) { $atr = [double]$Context.atr }
    elseif ($Context.bar -and $Context.bar.PSObject.Properties['atr'] -and $Context.bar.atr) { $atr = [double]$Context.bar.atr }

    # ── candidatos de novo stop (ratchet aplicado abaixo) ──
    $cands = New-Object System.Collections.ArrayList
    $beR = [double]$Policy.breakeven_at_r
    if ($beR -gt 0 -and $rNow -ge $beR) { [void]$cands.Add($entry) }

    if ([string]$Policy.trail_method -eq "chandelier" -and $atr -gt 0) {
        $mult = [double]$Policy.trail_atr_mult
        if ($isLong) { [void]$cands.Add($peak - $mult * $atr) } else { [void]$cands.Add($peak + $mult * $atr) }
    }

    # reversao ambigua -> aperta travando ganhos -0.5R (NAO vende no fundo)
    $tightenN = [int]$Policy.reversal_tighten_signals
    if ($tightenN -gt 0 -and $signals -ge $tightenN) {
        $lockR = $rNow - 0.5
        if ($lockR -gt 0) {
            if ($isLong) { [void]$cands.Add($entry + $lockR * $risk) } else { [void]$cands.Add($entry - $lockR * $risk) }
        }
    }

    # escolhe o melhor candidato na direcao do ratchet vs stop atual
    $newStop = $null
    foreach ($c in $cands) {
        if ($isLong) { if ($c -gt $curStop -and ($null -eq $newStop -or $c -gt $newStop)) { $newStop = $c } }
        else         { if ($c -lt $curStop -and ($null -eq $newStop -or $c -lt $newStop)) { $newStop = $c } }
    }
    if ($null -ne $newStop) { $newStop = [math]::Round($newStop, 8) }

    # ── precedencia de acao ──
    # 1. reversao confirmada -> sai
    $exitN = [int]$Policy.reversal_exit_signals
    if ($exitN -gt 0 -and $signals -ge $exitN) {
        return @{ action = "exit"; new_stop = $newStop; size_pct = $remaining }
    }
    # 2. time-stop (barreira vertical)
    $ts = [int]$Policy.time_stop_bars
    if ($ts -gt 0 -and $bars -ge $ts) {
        return @{ action = "exit"; new_stop = $newStop; size_pct = $remaining }
    }
    # 3. parcial (stateless: reduz ate o target_remaining do maior nivel atingido)
    $partials = @($Policy.partials)
    if ($partials.Count -gt 0) {
        $cum = 0.0; $bestTarget = $null
        foreach ($pp in ($partials | Sort-Object { [double]$_.at_r })) {
            $cum += [double]$pp.pct
            if ($rNow -ge [double]$pp.at_r) { $bestTarget = 1.0 - $cum }
        }
        if ($null -ne $bestTarget -and $remaining -gt ($bestTarget + 0.001)) {
            $sz = [math]::Round($remaining - $bestTarget, 4)
            return @{ action = "partial"; new_stop = $newStop; size_pct = $sz }
        }
    }
    # 4. hold (com stop possivelmente apertado)
    return @{ action = "hold"; new_stop = $newStop; size_pct = 0 }
}
