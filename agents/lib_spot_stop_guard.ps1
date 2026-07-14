# lib_spot_stop_guard.ps1 -- Fix #1 (2026-06-23): SPOT stop fail-closed.
#
# PROBLEMA: position_watcher SO alertava no SL do SPOT (linhas 211-216), nunca vendia.
# Com o daemon morto 19->23/06, OPNUSDT despencou a -69% sem ninguem executar o stop.
# No SPOT o stop e SOFTWARE (depende do daemon); no FUTURES fica na corretora.
#
# SOLUCAO: colocar stop-order de VERDADE na CoinEx (/v2/spot/stop-order) -> fail-closed,
# sobrevive daemon caido. MAS sem recriar o bug das 178 duplicatas (sync_and_fix_tp 2026-06-20):
# Resolve-SpotStopActions e PURO e idempotente -- so PLACE quando falta, OK quando ja existe,
# CANCEL duplicatas/desatualizados. Wire fino (Sync-SpotStopsToExchange) executa via API.

# --- NUCLEO PURO (TDD, sem I/O) -------------------------------------------------

function Resolve-SpotStopActions {
    <#
      Decide acoes de stop SPOT comparando posicoes abertas x stops ja na corretora.
      Positions:     objetos { market, qty, stop_price }
      ExistingStops: sell-stops SL pendentes { market, side, trigger_price, amount, order_id }
                     (CONTRATO: so SL -- o wire filtra TP fora antes de passar)
      TolerancePct:  trigger dentro de X% conta como "o mesmo stop" (default 0.5%)
      Retorna acoes: PLACE | OK | CANCEL | SKIP_INVALID
    #>
    param(
        [array]$Positions,
        [array]$ExistingStops = @(),
        [double]$TolerancePct = 0.5
    )
    $actions = @()
    foreach ($pos in @($Positions)) {
        $mkt  = "$($pos.market)"
        $stop = [double]$pos.stop_price
        $qty  = [double]$pos.qty

        # Regra de ouro #1: nunca colocar stop furado. Sinaliza pra humano em vez de inventar.
        if ($stop -le 0 -or $qty -le 0) {
            $actions += [pscustomobject]@{ market=$mkt; action="SKIP_INVALID"; trigger_price=$stop; amount=$qty; order_id=""; reason="stop<=0 ou qty<=0" }
            continue
        }

        $mine = @($ExistingStops | Where-Object { "$($_.market)" -eq $mkt -and "$($_.side)" -eq "sell" })
        $matching = @($mine | Where-Object {
            $t = [double]$_.trigger_price
            $t -gt 0 -and ([math]::Abs($t - $stop) / $stop * 100) -le $TolerancePct
        })

        if ($matching.Count -eq 0) {
            if ($mine.Count -eq 0) {
                # Falta stop -> coloca (fail-closed).
                $actions += [pscustomobject]@{ market=$mkt; action="PLACE"; trigger_price=$stop; amount=$qty; order_id=""; reason="sem stop na corretora" }
            }
            else {
                # Existe stop, mas fora da tolerancia. SPOT = sell-stop (so sobe / ratchet).
                # Se a corretora JA esta mais protegida (trigger >= desejado) -> mantem (nao afrouxa).
                # Se o trailing SUBIU o stop (desejado > corretora) -> UPDATE naquele momento.
                $best = $mine | Sort-Object { [double]$_.trigger_price } -Descending | Select-Object -First 1
                $bestTrig = [double]$best.trigger_price
                if ($bestTrig -ge $stop) {
                    $actions += [pscustomobject]@{ market=$mkt; action="OK"; trigger_price=$bestTrig; amount=$qty; order_id="$($best.order_id)"; reason="corretora ja mais protegida (ratchet)" }
                    foreach ($d in @($mine | Where-Object { "$($_.order_id)" -ne "$($best.order_id)" })) {
                        $actions += [pscustomobject]@{ market=$mkt; action="CANCEL"; trigger_price=[double]$d.trigger_price; amount=[double]$d.amount; order_id="$($d.order_id)"; reason="duplicata" }
                    }
                } else {
                    # trail subiu -> cancela o melhor velho e recoloca no novo nivel
                    $actions += [pscustomobject]@{ market=$mkt; action="UPDATE"; trigger_price=$stop; amount=$qty; order_id="$($best.order_id)"; reason="trailing subiu o stop" }
                    foreach ($d in @($mine | Where-Object { "$($_.order_id)" -ne "$($best.order_id)" })) {
                        $actions += [pscustomobject]@{ market=$mkt; action="CANCEL"; trigger_price=[double]$d.trigger_price; amount=[double]$d.amount; order_id="$($d.order_id)"; reason="duplicata" }
                    }
                }
            }
        }
        else {
            # Ja protegido -> mantem o 1o, cancela o resto (dedup anti bug-178).
            $keep = $matching[0]
            # Auto-upgrade: se o limit do stop existente esta colado no trigger (>= trigger*0.995),
            # nao preenche em gap -> re-poe com limit agressivo. So quando limit_price conhecido (>0).
            $keepLimit = if ($keep.PSObject.Properties['limit_price']) { [double]$keep.limit_price } else { 0 }
            $needsUpgrade = ($keepLimit -gt 0) -and ($keepLimit -ge $stop * 0.995)
            if ($needsUpgrade) {
                $actions += [pscustomobject]@{ market=$mkt; action="UPDATE"; trigger_price=$stop; amount=$qty; order_id="$($keep.order_id)"; reason="upgrade limit agressivo (preenche no gap)" }
            } else {
                $actions += [pscustomobject]@{ market=$mkt; action="OK"; trigger_price=$stop; amount=$qty; order_id="$($keep.order_id)"; reason="stop ja existe" }
            }
            $dups = @($mine | Where-Object { "$($_.order_id)" -ne "$($keep.order_id)" })
            foreach ($d in $dups) {
                $actions += [pscustomobject]@{ market=$mkt; action="CANCEL"; trigger_price=[double]$d.trigger_price; amount=[double]$d.amount; order_id="$($d.order_id)"; reason="duplicata" }
            }
        }
    }
    return $actions
}

# --- STOP DESEJADO (PURO) -------------------------------------------------------

function Resolve-DesiredStop {
    <#
      Calcula um stop SEMPRE VALIDO (abaixo do preco) p/ qualquer holding, rastreado ou nao.
      Causa raiz: protetor so cobria gem_trades.csv -> compras da nuvem ficavam nuas.
      Agora toda posicao (vinda do SALDO) ganha stop:
        - rastreada (CSV/journal) -> usa o stop conhecido (o maior = ratchet)
        - nao rastreada            -> default DefaultStopPct abaixo do preco
        - stop ACIMA do preco (furada) -> re-ancora em last*(1-MinBufferPct) (nunca stop morto)
      PURO. Last invalido -> 0 (caller ignora).
    #>
    param(
        [double]$Last,
        [double]$CsvStop = 0,
        [double]$JournalStop = 0,
        [double]$DefaultStopPct = 0.12,
        [double]$MinBufferPct = 0.02
    )
    if ($Last -le 0) { return 0 }
    $known = [math]::Max([double]$CsvStop, [double]$JournalStop)
    $stop = if ($known -gt 0) { $known } else { $Last * (1 - $DefaultStopPct) }
    # nunca stop morto (acima/no preco) -> re-ancora abaixo
    if ($stop -ge $Last) { $stop = $Last * (1 - $MinBufferPct) }
    return [math]::Round($stop, 8)
}

# --- LIMIT AGRESSIVO (PURO) -----------------------------------------------------

function Get-SpotStopLimitPrice {
    <#
      CoinEx spot stop = stop-LIMIT (stop-MARKET ja deu problema no passado). Um limit
      EXATO no trigger NAO preenche se o preco gapou abaixo. Solucao: preco de execucao
      X% ABAIXO do trigger -> vira limit marketavel, preenche atravessando o gap, sem
      precisar de stop-market. SlippagePct = pior preenchimento garantido (default 3%).
      PURO. Trigger invalido -> 0 (caller decide).
    #>
    param(
        [double]$TriggerPrice,
        [double]$SlippagePct = 0.03
    )
    if ($TriggerPrice -le 0) { return 0 }
    $p = [math]::Round($TriggerPrice * (1 - $SlippagePct), 8)
    if ($p -lt 0) { return 0 }
    return $p
}

# --- FALLBACK + DUST GUARD (PUROS, TDD) -----------------------------------------

function Test-SpotStopFallback {
    <#
      Decide se o daemon deve VENDER a mercado porque o stop-limit da corretora NAO
      executou (preco atravessou o stop e o limit ficou pendurado). Cinto+suspensorio:
      a corretora protege com daemon morto; o daemon protege contra gap-through.
      So dispara quando o preco caiu ALEM do buffer abaixo do stop (evita corrida com o limit).
      Fail-safe: preco<=0 (ticker furado) ou qty/stop invalidos -> nunca dispara.
    #>
    param(
        [double]$CurrentPrice,
        [double]$StopPrice,
        [double]$Qty,
        [double]$BufferPct = 0.01
    )
    if ($CurrentPrice -le 0 -or $StopPrice -le 0 -or $Qty -le 0) {
        return @{ fire=$false; reason="dados invalidos" }
    }
    $threshold = $StopPrice * (1 - $BufferPct)
    if ($CurrentPrice -le $threshold) {
        return @{ fire=$true; reason="preco $CurrentPrice atravessou stop $StopPrice (limit nao executou)" }
    }
    return @{ fire=$false; reason="acima do gatilho de fallback" }
}

function Test-SpotStopPlaceable {
    <#
      Classifica se da pra colocar stop-order nesta posicao. Evita tentar (e logar erro)
      todo ciclo em poeira/sub-nano/simbolo invalido. PURO (MinAmount opcional -- caller
      resolve via Get-MarketPrecision, que faz I/O; aqui so recebe o valor ja calculado).

      2026-07-14: MinNotionalUsd fixo ($5) nao cobria o min_amount REAL do par -- ordem
      passava no check interno mas era rejeitada pela CoinEx (lote minimo do par maior
      que o notional calculado). MinAmount, se fornecido, adiciona esse segundo piso.
    #>
    param(
        [string]$Market,
        [double]$Qty,
        [double]$Price,
        [double]$MinNotionalUsd = 5.0,
        [Nullable[double]]$MinAmount = $null
    )
    if ($Market -notmatch 'USDT$')      { return @{ placeable=$false; reason="simbolo_invalido" } }
    if ($Price -le 0)                   { return @{ placeable=$false; reason="sem_preco" } }
    if ($Price -lt 1e-7)                { return @{ placeable=$false; reason="preco_sub_nano" } }
    if (($Qty * $Price) -lt $MinNotionalUsd) { return @{ placeable=$false; reason="poeira" } }
    if ($MinAmount -and $MinAmount.Value -gt 0 -and $Qty -lt $MinAmount.Value) {
        return @{ placeable=$false; reason="abaixo_lote_minimo_par" }
    }
    return @{ placeable=$true; reason="ok" }
}

# --- COBERTURA POR SALDO REAL (wire) --------------------------------------------

function Get-SpotHoldingsForStop {
    <#
      CAUSA RAIZ: o protetor lia gem_trades.csv -> compras da nuvem (nao registradas)
      ficavam NUAS. Agora le o SALDO REAL da corretora (ground truth): TODA holding com
      valor >= MinUsd ganha stop, rastreada ou nao. Stop desejado via Resolve-DesiredStop
      (CSV/journal se conhecido, senao default % abaixo do preco).
      Retorna { market, qty, stop_price } pronto p/ Sync-SpotStopsToExchange.
    #>
    param(
        [double]$MinUsd = 5.0,
        [string]$GemTradesPath = "",
        [string]$TrailingFile = ""
    )
    $out = @()
    if (-not (Get-Command CoinEx-Get -ErrorAction SilentlyContinue)) { return $out }
    $jdir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot) "journal" }
    if (-not $GemTradesPath) { $GemTradesPath = Join-Path $jdir "gem_trades.csv" }
    $explicitTrailingFile = [bool]$TrailingFile
    if (-not $TrailingFile)  { $TrailingFile  = Join-Path $jdir "trailing_positions.json" }

    # mapas de stop conhecido (CSV + journal trailing) por market
    $csvStop = @{}; $jStop = @{}
    if (Test-Path $GemTradesPath) {
        try { foreach ($t in (Import-Csv $GemTradesPath)) {
            if ($t.market_type -eq "SPOT" -and $t.status -eq "OPEN" -and [double]$t.stop_price -gt 0) { $csvStop["$($t.market)"] = [double]$t.stop_price }
        } } catch {}
    }
    # 2026-06-25 fix: desde a migracao p/ Supabase (USE_SUPABASE_STATE.flag), o
    # arquivo local trailing_positions.json NAO EXISTE MAIS -- ler direto daqui
    # sempre achava vazio, e o stop adaptativo (breakeven/lock+33%/trailing)
    # NUNCA chegava na corretora; o stop real ficava parado no default 12% ou
    # no nivel de entrada original (causa raiz de ZANO/AIN/SPCXX etc. com stop
    # real muito mais largo que o pretendido). Usa a abstracao Get-TrailingPositions
    # (resolve Supabase-vs-arquivo) quando disponivel e nenhum -TrailingFile
    # explicito foi passado (preserva comportamento p/ chamadas com path custom).
    # Tambem nao filtra mais por active=true: active e bookkeeping interno do
    # Adaptive Trailing (pode ficar false por um "stop hit" so-software nunca
    # confirmado na corretora) -- a protecao real nao pode regredir por causa
    # disso. Resolve-DesiredStop so usa o MAIOR (ratchet), entao isso nunca afrouxa.
    if (-not $explicitTrailingFile -and (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue)) {
        try {
            foreach ($p in @(Get-TrailingPositions)) {
                if ($p.PSObject.Properties['stopCurrent'] -and [double]$p.stopCurrent -gt 0) {
                    $jStop["$($p.market)"] = [double]$p.stopCurrent
                }
            }
        } catch {}
    } elseif (Test-Path $TrailingFile) {
        try { foreach ($p in (Get-Content $TrailingFile -Raw | ConvertFrom-Json)) {
            if ($p.PSObject.Properties['stopCurrent'] -and [double]$p.stopCurrent -gt 0) { $jStop["$($p.market)"] = [double]$p.stopCurrent }
        } } catch {}
    }

    $stable = @("USDT","USDC","USD","DAI","TUSD","BUSD")
    $bal = try { CoinEx-Get "/v2/assets/spot/balance" } catch { $null }
    if (-not $bal -or $bal.code -ne 0) { return $out }
    foreach ($c in @($bal.data)) {
        $ccy = "$($c.ccy)".ToUpper()
        if ($ccy -in $stable) { continue }
        $qty = ([double]$c.available) + ([double]$c.frozen)
        if ($qty -le 0) { continue }
        $mkt = "${ccy}USDT"
        $last = 0.0
        try { $tk = Invoke-RestMethod "https://api.coinex.com/v2/spot/ticker?market=$mkt" -TimeoutSec 6 -ErrorAction Stop; if ($tk.data) { $last = [double]$tk.data[0].last } } catch {}
        if ($last -le 0) { continue }
        if (($qty * $last) -lt $MinUsd) { continue }   # poeira
        $desired = Resolve-DesiredStop -Last $last -CsvStop ([double]$csvStop[$mkt]) -JournalStop ([double]$jStop[$mkt])
        if ($desired -le 0) { continue }
        $out += [pscustomobject]@{ market = $mkt; qty = ([double]$c.available); stop_price = $desired }
    }
    return $out
}

# --- WIRE FINO (I/O CoinEx; nao testado por unit, so smoke) ---------------------

function Sync-SpotStopsToExchange {
    <#
      Le posicoes SPOT abertas + stops pendentes na corretora, resolve acoes e EXECUTA.
      Idempotente: rodar a cada ciclo do position_watcher e seguro (nao duplica).
      Fail-soft: erro em uma posicao nao derruba as outras.
      Retorna o log de acoes executadas (pra o daemon logar/alertar).
    #>
    param(
        [array]$Positions,  # { market, qty, stop_price } -- vem de Get-OpenSpotPositions
        [string]$TrailingFile = ""
    )
    $results = @()
    if (-not (Get-Command CoinEx-Get -ErrorAction SilentlyContinue)) { return $results }

    # NOTA 2026-06-24: o stop_price desejado JA vem pronto de Get-SpotHoldingsForStop
    # (incorpora CSV + trailing stopCurrent COM re-ancora abaixo do preco). Nao re-mesclar
    # trailing aqui -> mesclar reintroduzia o stopCurrent MORTO acima do preco (PAXG 4064).

    # Filtra poeira/sub-nano/simbolo invalido ANTES de tentar (evita erro+spam todo ciclo).
    $priceMap = @{}
    $placeable = @()
    foreach ($pos in @($Positions)) {
        $mkt = "$($pos.market)"
        $last = 0.0
        try {
            $tk = Invoke-RestMethod "https://api.coinex.com/v2/spot/ticker?market=$mkt" -TimeoutSec 8 -ErrorAction Stop
            if ($tk.data) { $last = [double]$tk.data[0].last }
        } catch {}
        $priceMap[$mkt] = $last
        $minAmt = $null
        if (Get-Command Get-MarketPrecision -ErrorAction SilentlyContinue) {
            try {
                $prec = Get-MarketPrecision -Market $mkt -MarketType "spot"
                if ($prec -and $prec.min_amount) { $minAmt = [double]$prec.min_amount }
            } catch {}
        }
        $chk = Test-SpotStopPlaceable -Market $mkt -Qty ([double]$pos.qty) -Price $last -MinAmount $minAmt
        if ($chk.placeable) {
            $placeable += $pos
        } else {
            # SKIP silencioso (ok=true -> daemon nao loga WARN): poeira nao polui o log.
            $results += [pscustomobject]@{ market=$mkt; action="SKIP_DUST"; ok=$true; detail=$chk.reason }
        }
    }
    $Positions = $placeable

    # Coleta stops SL pendentes por mercado.
    # SL vs TP: um sell e SL se (trigger <= preco atual) OU (trigger ~= stop desejado).
    # 2026-06-24 FIX: o filtro antigo (trig>=last => TP) confundia o SL com TP quando o
    # preco CAIA ABAIXO do stop (PAXG: trigger 4064 > preco 3988) -> Resolve nao via o stop
    # -> recolocava todo ciclo -> 14 duplicatas (bug 178 de novo). Casa pelo stop desejado.
    $existing = @()
    foreach ($pos in @($Positions)) {
        $mkt = "$($pos.market)"
        $desired = [double]$pos.stop_price
        try {
            $last = [double]$priceMap[$mkt]
            $so = CoinEx-Get "/v2/spot/pending-stop-order?market=$mkt&market_type=SPOT&page=1&limit=100"
            if ($so.code -eq 0) {
                foreach ($s in @($so.data)) {
                    if ("$($s.side)" -ne "sell") { continue }
                    $trig = [double]$s.trigger_price
                    if ($trig -le 0) { continue }
                    $nearDesired = ($desired -gt 0) -and ([math]::Abs($trig - $desired) / $desired -le 0.05)
                    $belowPrice  = ($last -gt 0 -and $trig -le $last)
                    if (-not ($nearDesired -or $belowPrice)) { continue }  # TP real (acima do preco e longe do stop) -> ignora
                    # API /v2/spot/pending-stop-order retorna 'stop_id' (nao 'order_id').
                    $sid = if ($s.PSObject.Properties['stop_id']) { "$($s.stop_id)" } else { "$($s.order_id)" }
                    $lim = if ($s.PSObject.Properties['price']) { [double]$s.price } else { 0 }
                    $existing += [pscustomobject]@{
                        market = $mkt; side = "sell"; trigger_price = $trig
                        amount = [double]$s.amount; order_id = $sid; limit_price = $lim
                    }
                }
            }
        } catch {}
    }

    $actions = Resolve-SpotStopActions -Positions $Positions -ExistingStops $existing
    foreach ($a in $actions) {
        try {
            switch ($a.action) {
                "PLACE" {
                    $lim = Get-SpotStopLimitPrice -TriggerPrice $a.trigger_price
                    CoinEx-PlaceSpotStopOrder -Market $a.market -Side "sell" -TriggerPrice $a.trigger_price -Amount $a.amount -LimitPrice $lim | Out-Null
                    $results += [pscustomobject]@{ market=$a.market; action="PLACE"; ok=$true; detail="trigger=$($a.trigger_price) limit=$lim" }
                }
                "CANCEL" {
                    if ($a.order_id -and (Get-Command CoinEx-CancelStopOrder -ErrorAction SilentlyContinue)) {
                        CoinEx-CancelStopOrder -Market $a.market -StopId $a.order_id -MarketType "SPOT" | Out-Null
                        $results += [pscustomobject]@{ market=$a.market; action="CANCEL"; ok=$true; detail="$($a.reason) id=$($a.order_id)" }
                    }
                }
                "UPDATE" {
                    # trail subiu: cancela o stop velho e recoloca no nivel novo (mais protegido)
                    if ($a.order_id -and (Get-Command CoinEx-CancelStopOrder -ErrorAction SilentlyContinue)) {
                        CoinEx-CancelStopOrder -Market $a.market -StopId $a.order_id -MarketType "SPOT" | Out-Null
                    }
                    $lim = Get-SpotStopLimitPrice -TriggerPrice $a.trigger_price
                    CoinEx-PlaceSpotStopOrder -Market $a.market -Side "sell" -TriggerPrice $a.trigger_price -Amount $a.amount -LimitPrice $lim | Out-Null
                    $results += [pscustomobject]@{ market=$a.market; action="UPDATE"; ok=$true; detail="stop subiu p/ $($a.trigger_price)" }
                }
                "SKIP_INVALID" {
                    $results += [pscustomobject]@{ market=$a.market; action="SKIP_INVALID"; ok=$false; detail=$a.reason }
                }
                # "OK" -> nada a fazer (ja protegido)
            }
        } catch {
            $results += [pscustomobject]@{ market=$a.market; action=$a.action; ok=$false; detail="erro: $_" }
        }
    }

    # FALLBACK: se o preco atravessou o stop e o stop-limit da corretora NAO executou,
    # o daemon vende a mercado (protege contra gap-through). So nas placeable, com preco bom.
    foreach ($pos in @($Positions)) {
        $mkt = "$($pos.market)"
        $last = [double]$priceMap[$mkt]
        $fb = Test-SpotStopFallback -CurrentPrice $last -StopPrice ([double]$pos.stop_price) -Qty ([double]$pos.qty)
        if (-not $fb.fire) { continue }
        try {
            # cancela qualquer stop pendente desse mkt (evita venda dupla) e vende a mercado
            $sids = @($existing | Where-Object { "$($_.market)" -eq $mkt } | ForEach-Object { $_.order_id })
            foreach ($sid in $sids) {
                if ($sid -and (Get-Command CoinEx-CancelStopOrder -ErrorAction SilentlyContinue)) {
                    CoinEx-CancelStopOrder -Market $mkt -StopId $sid -MarketType "SPOT" | Out-Null
                }
            }
            # haircut 0.3% + floor 6 casas: arredondar p/ cima estourava o saldo ("balance not enough")
            $sellQty = [math]::Floor([double]$pos.qty * 0.997 * 1e6) / 1e6
            CoinEx-PlaceSpotOrder -Market $mkt -Side "sell" -Type "market" -Amount $sellQty | Out-Null
            $results += [pscustomobject]@{ market=$mkt; action="FALLBACK_SELL"; ok=$true; detail=$fb.reason }
        } catch {
            $results += [pscustomobject]@{ market=$mkt; action="FALLBACK_SELL"; ok=$false; detail="erro: $_" }
        }
    }

    return $results
}
