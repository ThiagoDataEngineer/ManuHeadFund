# lib_exit_intelligence_auto.ps1
# EXIT INTELLIGENCE: Layer 2-4 TOTALMENTE AUTOMATICA (profit-taking)
# Sem aprendizado, sem manual -- regras simples + execucao direta.
# 2026-06-19 (original) | 2026-06-28 REESCRITA (causa raiz)
#
# ============================================================================
# CAUSA RAIZ corrigida (2026-06-28):
#   A versao 2026-06-19 tinha as posicoes HARDCODED (MET qty=559.71, BASED 248.28).
#   Consequencias reais no log da nuvem:
#     - tentava vender 391.797 MET (70% de 559.71) com saldo real de 0.0147 (poeira)
#     - endpoint errado /v2/spot/place-order  -> 404 Not Found (correto: /v2/spot/order)
#     - ccy="USDT" num SELL (deveria ser a moeda base)
#   Resultado: erro todo ciclo, mascarando falhas reais de venda, e ignorando
#   TODAS as outras holdings (FAI/XRP/AIN...).
#
# DESENHO NOVO (alinhado ao lib_spot_stop_guard, ground truth = corretora):
#   - QUANTIDADE: sempre do SALDO REAL (/v2/assets/spot/balance, campo available).
#     O registro de trailing NAO guarda qty -- so niveis de preco. Logo a app
#     decide o fechamento (total/fracionado) SEMPRE sobre o saldo que existe.
#   - ENTRY/STOP: do registro do momento da compra (Get-TrailingPositions).
#     Sem entry conhecido -> SKIP (profit-taking exige saber o ganho; o downside
#     ja e coberto pelo stop real da corretora em lib_spot_stop_guard).
#   - EXECUCAO: via CoinEx-PlaceSpotOrder (endpoint/ccy/client_id/locale corretos).
#   - DUST GUARD: Test-SpotStopPlaceable -- nao tenta vender poeira (sem 404/spam).
#   - RECONCILIACAO: no fechamento 100% chama Close-TrailingPosition (registro
#     em dia com a corretora). Fracionado nao precisa: o proximo ciclo le o saldo
#     fresco e a quantidade ja reflete a venda anterior (auto-reconciliado).
#
# LAYER 2: RSI >=70 (sobrecomprado) + ganho -> vende 25%
# LAYER 3: reversal 3 candles + ganho     -> vende 70%
# LAYER 4: perto do SL (<=2.5%) + ganho   -> vende 100%
# ============================================================================

# --- NUCLEO PURO (TDD, sem I/O) -------------------------------------------------

function Resolve-ExitAutoDecision {
    <#
      Decide UMA acao de saida automatica para uma holding, a partir de dados ja
      coletados (precos + niveis + saldo real). PURO e deterministico -> testavel.

      Retorna sempre um objeto com .action em:
        SKIP  -> dados insuficientes / poeira / sem entry (nao avalia)
        HOLD  -> avaliou mas nenhuma layer disparou
        SELL  -> uma layer disparou (layer/pct/sellQty preenchidos)

      sellQty ja vem pronto p/ a corretora: fracao do SALDO REAL, com haircut no
      100% (0.997, evita "balance not enough") e floor em 6 casas (nao estoura o
      saldo por arredondamento p/ cima).
    #>
    param(
        [double[]]$Closes,            # closes recentes (>=4), antigo->novo
        [double]  $Current,           # preco atual
        [double]  $Entry,             # entry do registro (compra). <=0 => SKIP
        [double]  $Sl = 0,            # stop atual conhecido. <=0 => Layer 4 inativa
        [double]  $RealQty = 0,       # saldo REAL disponivel na corretora (base)
        [double]  $MinNotionalUsd = 5.0
    )

    $mk = { param($a,$p,$q,$r) [pscustomobject]@{
        action=$a; layer=$p; pct=$q; sellQty=0.0; reason=$r
        rsi=$null; gain=$null; distToSL=$null; reversal=$null } }

    # Guardas (fail-safe): nunca operar sobre dados furados.
    if ($Current -le 0)        { return (& $mk 'SKIP' 0 0 'sem_preco') }
    if ($RealQty -le 0)        { return (& $mk 'SKIP' 0 0 'sem_saldo') }
    if (($RealQty * $Current) -lt $MinNotionalUsd) { return (& $mk 'SKIP' 0 0 'poeira') }
    if ($Entry -le 0)          { return (& $mk 'SKIP' 0 0 'sem_entry') }   # profit-taking exige ganho conhecido
    if (-not $Closes -or @($Closes).Count -lt 4) { return (& $mk 'SKIP' 0 0 'poucos_candles') }

    $closes = @($Closes | ForEach-Object { [double]$_ })

    # RSI (media simples de ganhos/perdas -- identico ao original validado).
    $gains = @(); $losses = @()
    for ($i = 1; $i -lt $closes.Count; $i++) {
        $chg = $closes[$i] - $closes[$i-1]
        if ($chg -gt 0) { $gains += $chg } else { $losses += [Math]::Abs($chg) }
    }
    $avgGain = if ($gains.Count  -gt 0) { ($gains  | Measure-Object -Average).Average } else { 0 }
    $avgLoss = if ($losses.Count -gt 0) { ($losses | Measure-Object -Average).Average } else { 0 }
    $rs  = if ($avgLoss -gt 0) { $avgGain / $avgLoss } else { 100 }
    $rsi = 100 - (100 / (1 + $rs))

    # Reversal: 3 closes em queda monotonica (pico->queda).
    $r3 = $closes[-3..-1]
    $isReversal = ($r3[-1] -lt $r3[-2]) -and ($r3[-2] -lt $r3[-3])

    $gain     = (($Current - $Entry) / $Entry) * 100
    $distToSL = if ($Sl -gt 0) { (($Current - $Sl) / $Current) * 100 } else { [double]999 }

    # helper: fracao do saldo real -> qty marketavel (floor 6 casas, nunca estoura).
    $fracQty = { param($frac) [math]::Floor([double]$RealQty * [double]$frac * 1e6) / 1e6 }

    $decide = {
        param($action,$layer,$pct,$frac,$reason)
        $q = & $fracQty $frac
        $o = & $mk $action $layer $pct $reason
        $o.sellQty = $q; $o.rsi = [math]::Round($rsi,1); $o.gain = [math]::Round($gain,2)
        $o.distToSL = [math]::Round($distToSL,2); $o.reversal = $isReversal
        if ($action -eq 'SELL' -and $q -le 0) {
            # fracao arredondou p/ zero (qty minuscula) -> nao da pra vender
            $o.action = 'HOLD'; $o.reason = "qty_zero ($reason)"
        }
        return $o
    }

    # Prioridade: L4 (critico, 100%) -> L3 (reversal, 70%) -> L2 (RSI, 25%).
    # Toda layer exige ganho (> 0): so realiza lucro, nunca vende no prejuizo aqui.
    if (($distToSL -le 2.5) -and ($gain -gt 0)) {
        return (& $decide 'SELL' 4 100 0.997 'perto_SL_com_ganho')
    }
    if ($isReversal -and ($gain -gt 0)) {
        return (& $decide 'SELL' 3 70 0.70 'reversal_detectado')
    }
    if (($rsi -ge 70) -and ($gain -gt 0)) {
        return (& $decide 'SELL' 2 25 0.25 'rsi_sobrecomprado')
    }

    return (& $decide 'HOLD' 0 0 0 'nenhuma_layer')
}

# --- WIRE FINO (I/O CoinEx; nao testado por unit, so smoke) ---------------------

function Invoke-ExitIntelligenceAuto {
    <#
    .SYNOPSIS
        Exit Intelligence automatica (profit-taking Layer 2-4) sobre o SALDO REAL.
    .DESCRIPTION
        Enumera TODAS as holdings spot reais da corretora (ground truth), cruza com
        entry/stop do registro de compra (Get-TrailingPositions) e, via nucleo puro
        Resolve-ExitAutoDecision, decide e executa venda total/fracionada.
        Zero hardcode, zero manual. Idempotente por ciclo (saldo fresco reconcilia).
    #>
    [CmdletBinding()]
    param(
        [double]$MinNotionalUsd = 5.0
    )

    $executed = @()
    if (-not (Get-Command CoinEx-Get -ErrorAction SilentlyContinue)) { return $executed }
    if (-not (Get-Command CoinEx-PlaceSpotOrder -ErrorAction SilentlyContinue)) { return $executed }

    # 1) Registro do momento da compra: entry/stop por mercado.
    $entryMap = @{}; $stopMap = @{}
    if (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue) {
        try {
            foreach ($p in @(Get-TrailingPositions)) {
                $mk = "$($p.market)"
                if (-not $mk) { continue }
                if ($p.PSObject.Properties['entry'] -and [double]$p.entry -gt 0) { $entryMap[$mk] = [double]$p.entry }
                # stop atual: prefere stopCurrent (trailing) > stop (entrada).
                $sc = if ($p.PSObject.Properties['stopCurrent'] -and [double]$p.stopCurrent -gt 0) { [double]$p.stopCurrent }
                      elseif ($p.PSObject.Properties['stop'] -and [double]$p.stop -gt 0) { [double]$p.stop }
                      else { 0 }
                if ($sc -gt 0) { $stopMap[$mk] = $sc }
            }
        } catch {}
    }

    # 2) Saldo REAL = ground truth da quantidade.
    $bal = try { CoinEx-Get "/v2/assets/spot/balance" } catch { $null }
    if (-not $bal -or $bal.code -ne 0) { return $executed }
    $stable = @("USDT","USDC","USD","DAI","TUSD","BUSD")

    foreach ($c in @($bal.data)) {
        $ccy = "$($c.ccy)".ToUpper()
        if ($ccy -in $stable) { continue }
        $realQty = [double]$c.available            # SO o disponivel (frozen pode estar preso em stop-order)
        if ($realQty -le 0) { continue }
        $market = "${ccy}USDT"

        try {
            $ticker = CoinEx-GetTicker -Market $market -ErrorAction SilentlyContinue
            if (-not $ticker) { continue }
            $current = [double]$ticker.last
            if ($current -le 0) { continue }

            # entry/stop do registro (sem entry -> nucleo retorna SKIP, nao vende as cegas)
            $entry = if ($entryMap.ContainsKey($market)) { [double]$entryMap[$market] } else { 0 }
            $sl    = if ($stopMap.ContainsKey($market))  { [double]$stopMap[$market] }  else { 0 }
            if ($entry -le 0) { continue }   # nao rastreado: profit-taking nao se aplica (SL real cobre o downside)

            # candles 1h p/ RSI + reversal
            $candleResp = try { CoinEx-Get "/v2/spot/kline?market=$market&period=1hour&limit=14" } catch { $null }
            $candles = $candleResp.data
            if (-not $candles) { continue }
            $closes = @($candles | ForEach-Object { [double]$_.close })

            $d = Resolve-ExitAutoDecision -Closes $closes -Current $current -Entry $entry -Sl $sl -RealQty $realQty -MinNotionalUsd $MinNotionalUsd

            Write-Host ("[{0}] {1} | preco={2} ganho={3}% RSI={4} distSL={5}% rev={6} -> {7} {8}" -f `
                $ccy, $d.action, $current, $d.gain, $d.rsi, $d.distToSL, $d.reversal, $d.action, $d.reason) -ForegroundColor Gray

            if ($d.action -ne 'SELL') { continue }

            Write-Host ("[EXIT-L{0}] {1} {2}: vendendo {3}% = {4} @ {5}" -f $d.layer, $ccy, $d.reason, $d.pct, $d.sellQty, $current) -ForegroundColor Yellow
            try {
                $r = CoinEx-PlaceSpotOrder -Market $market -Side "sell" -Type "market" -Amount $d.sellQty
                $filled = if ($r -and $r.PSObject.Properties['filled_amount']) { [double]$r.filled_amount } else { $d.sellQty }
                $realized = [math]::Round($filled * $current, 2)
                Write-Host ("          EXECUTADO: {0} USDT realizado" -f $realized) -ForegroundColor Green
                $executed += @{ market=$market; layer=$d.layer; pct=$d.pct; qty=$d.sellQty; reason=$d.reason }

                # RECONCILIACAO: fechamento total -> registro em dia com a corretora.
                if ($d.pct -ge 100 -and (Get-Command Close-TrailingPosition -ErrorAction SilentlyContinue)) {
                    try { Close-TrailingPosition -Market $market -Reason "exit_auto_L$($d.layer)_$($d.reason)" -ExitPrice $current | Out-Null } catch {}
                }
            } catch {
                Write-Host ("          Erro ao vender: {0}" -f $_) -ForegroundColor Red
            }
        } catch {
            Write-Host ("[EXIT-ERR] {0}: {1}" -f $ccy, $_) -ForegroundColor Red
        }
    }

    return $executed
}
