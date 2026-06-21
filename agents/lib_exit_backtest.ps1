# lib_exit_backtest.ps1 -- Harness PURO de replay de saidas (exit strategy backtest).
#
# Por que: profissionalizar o trailing exige MEDIR antes de mudar. Este simulador
# pega uma entrada + candles pos-entrada + uma funcao de POLITICA (scriptblock) e
# replica barra-a-barra, devolvendo o desfecho com metricas profissionais:
#   R realizado, MFE_R (max favoravel), MAE_R (max adverso), capture_ratio,
#   bars_held, exit_reason. Politica-agnostico: plugue a regra ATUAL p/ baseline
#   ou regras novas p/ comparar -- mesma vara de medir.
#
# Realismo (anti-otimismo, Lopez de Prado):
#   - STOP checado ANTES do favoravel dentro da barra (adverso primeiro).
#   - gap: barra que abre alem do stop preenche no OPEN (nao no stop).
#   - LONG: stop so sobe (ratchet up). SHORT: stop so desce.
#   - parciais: R realizado = soma(size_pct_i * R_i).
# PS 5.1 safe. PURO (sem I/O, sem API). 100% TDD-able.

function _Get-RNow {
    param([string]$Side, [double]$Price, [double]$Entry, [double]$Risk)
    if ($Risk -le 0) { return 0.0 }
    if ($Side -eq "SHORT") { return ($Entry - $Price) / $Risk }
    return ($Price - $Entry) / $Risk
}

function Invoke-ExitReplay {
    <#
    .SYNOPSIS
    Simula a gestao de saida de UMA posicao sobre candles historicos.

    .PARAMETER Entry
    Hashtable: side(LONG|SHORT), entry_price, initial_stop. Opcional: trade_type, regime, market.

    .PARAMETER Candles
    Array de candles POS-entrada (ordem cronologica): {open,high,low,close,volume}.

    .PARAMETER PolicyFn
    Scriptblock que recebe um contexto e retorna @{ action="hold|partial|exit"; new_stop=<price|null>; size_pct=<0..1> }.

    .PARAMETER MaxBars
    Barreira vertical: encerra no close da ultima barra permitida.

    .OUTPUTS
    PSCustomObject com r, mfe_r, mae_r, capture_ratio, bars_held, exit_reason, exit_price, etc.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Entry,
        [Parameter(Mandatory)] [object[]]  $Candles,
        [Parameter(Mandatory)] [scriptblock] $PolicyFn,
        [int] $MaxBars = 0
    )

    $side  = [string]$Entry.side
    $e     = [double]$Entry.entry_price
    $stop0 = [double]$Entry.initial_stop
    $isLong = ($side -ne "SHORT")
    $risk  = if ($isLong) { $e - $stop0 } else { $stop0 - $e }
    if ($risk -le 0) { throw "Invoke-ExitReplay: risk invalido (entry=$e stop=$stop0 side=$side)" }

    $bars = @($Candles)
    if ($MaxBars -le 0) { $MaxBars = $bars.Count }

    $curStop   = $stop0
    $remaining = 1.0
    $realizedR = 0.0
    # extremos favoravel/adverso
    $bestPrice  = $e   # melhor preco alcancado (high LONG / low SHORT)
    $worstPrice = $e   # pior preco (low LONG / high SHORT)

    $exitReason = "open"
    $exitPrice  = $null
    $barsHeld   = 0

    for ($i = 0; $i -lt $bars.Count -and $i -lt $MaxBars; $i++) {
        $b = $bars[$i]
        $barsHeld = $i + 1
        $o = [double]$b.open; $h = [double]$b.high; $l = [double]$b.low; $c = [double]$b.close

        # extremos
        if ($isLong) {
            if ($h -gt $bestPrice)  { $bestPrice  = $h }
            if ($l -lt $worstPrice) { $worstPrice = $l }
        } else {
            if ($l -lt $bestPrice)  { $bestPrice  = $l }
            if ($h -gt $worstPrice) { $worstPrice = $h }
        }

        # 1) STOP primeiro (adverso). Gap: fill no open se abrir alem do stop.
        $stopHit = if ($isLong) { $l -le $curStop } else { $h -ge $curStop }
        if ($stopHit) {
            if ($isLong) { $fill = if ($o -le $curStop) { $o } else { $curStop } }
            else         { $fill = if ($o -ge $curStop) { $o } else { $curStop } }
            $realizedR += $remaining * (_Get-RNow -Side $side -Price $fill -Entry $e -Risk $risk)
            $remaining = 0; $exitReason = "stop"; $exitPrice = $fill
            break
        }

        # 2) Politica (favoravel / gestao) -- decide no close da barra
        $rNowClose = _Get-RNow -Side $side -Price $c -Entry $e -Risk $risk
        $ctx = @{
            side = $side; entry = $e; initial_stop = $stop0; risk = $risk
            trade_type = $Entry.trade_type; regime = $Entry.regime; market = $Entry.market
            bar = $b; bar_index = $i; bars_held = $barsHeld
            current_stop = $curStop; remaining_size = $remaining
            realized_r = $realizedR; r_now = $rNowClose
            best_price = $bestPrice; worst_price = $worstPrice
            peak = $bestPrice
            atr = $(if ($b.PSObject.Properties['atr']) { $b.atr } else { $null })
            signals = $(if ($b.PSObject.Properties['signals']) { $b.signals } else { $null })
        }
        $d = & $PolicyFn $ctx
        if ($null -ne $d) {
            $act = [string]$d.action
            # mover stop (so na direcao certa = ratchet)
            if ($null -ne $d.new_stop) {
                $ns = [double]$d.new_stop
                if ($isLong) { if ($ns -gt $curStop) { $curStop = $ns } }
                else         { if ($ns -lt $curStop) { $curStop = $ns } }
            }
            if ($act -eq "exit") {
                $realizedR += $remaining * $rNowClose
                $remaining = 0; $exitReason = "policy_exit"; $exitPrice = $c
                break
            }
            elseif ($act -eq "partial") {
                $sz = [math]::Min([double]$d.size_pct, $remaining)
                if ($sz -gt 0) {
                    $realizedR += $sz * $rNowClose
                    $remaining -= $sz
                    if ($remaining -le 0.0001) { $remaining = 0; $exitReason = "partial_full"; $exitPrice = $c; break }
                }
            }
        }
    }

    # barreira vertical / fim das barras: fecha o restante no ultimo close
    if ($remaining -gt 0) {
        $lastIdx = [math]::Min($bars.Count, $MaxBars) - 1
        if ($lastIdx -lt 0) { $lastIdx = 0 }
        $lc = [double]$bars[$lastIdx].close
        $realizedR += $remaining * (_Get-RNow -Side $side -Price $lc -Entry $e -Risk $risk)
        $remaining = 0; $exitReason = "time"; $exitPrice = $lc
    }

    $mfeR = (_Get-RNow -Side $side -Price $bestPrice  -Entry $e -Risk $risk)
    # MAE como magnitude positiva do adverso
    $maeR = - (_Get-RNow -Side $side -Price $worstPrice -Entry $e -Risk $risk)
    $capture = if ($mfeR -gt 0) { $realizedR / $mfeR } else { 0.0 }

    return [PSCustomObject]@{
        market        = $Entry.market
        side          = $side
        trade_type    = $Entry.trade_type
        regime        = $Entry.regime
        r             = [math]::Round($realizedR, 4)
        mfe_r         = [math]::Round($mfeR, 4)
        mae_r         = [math]::Round($maeR, 4)
        capture_ratio = [math]::Round($capture, 4)
        bars_held     = $barsHeld
        exit_reason   = $exitReason
        exit_price    = $exitPrice
        entry_price   = $e
        win           = ($realizedR -gt 0)
    }
}

function Get-ExitReplayStats {
    <#
    .SYNOPSIS
    Agrega uma colecao de desfechos do Invoke-ExitReplay em metricas-resumo.
    #>
    [CmdletBinding()]
    param([object[]] $Outcomes)

    $rows = @($Outcomes | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) {
        return [PSCustomObject]@{ n=0; win_rate=0; avg_r=0; median_r=0; total_r=0; avg_mfe_r=0; avg_capture=0; expectancy=0 }
    }

    $rVals = @($rows | ForEach-Object { [double]$_.r })
    $wins  = @($rows | Where-Object { [double]$_.r -gt 0 })
    $caps  = @($rows | Where-Object { $null -ne $_.capture_ratio } | ForEach-Object { [double]$_.capture_ratio })
    $mfes  = @($rows | Where-Object { $null -ne $_.mfe_r }         | ForEach-Object { [double]$_.mfe_r })

    $sorted = @($rVals | Sort-Object)
    $mid = [int][math]::Floor($sorted.Count / 2)
    $median = if ($sorted.Count % 2 -eq 1) { $sorted[$mid] } else { ($sorted[$mid-1] + $sorted[$mid]) / 2.0 }

    return [PSCustomObject]@{
        n           = $rows.Count
        win_rate    = [math]::Round($wins.Count / $rows.Count, 4)
        avg_r       = [math]::Round(($rVals | Measure-Object -Average).Average, 4)
        median_r    = [math]::Round($median, 4)
        total_r     = [math]::Round(($rVals | Measure-Object -Sum).Sum, 4)
        avg_mfe_r   = if ($mfes.Count) { [math]::Round(($mfes | Measure-Object -Average).Average, 4) } else { 0 }
        avg_capture = if ($caps.Count) { [math]::Round(($caps | Measure-Object -Average).Average, 4) } else { 0 }
        expectancy  = [math]::Round(($rVals | Measure-Object -Average).Average, 4)  # R por trade
    }
}
