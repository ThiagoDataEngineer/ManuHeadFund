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
      todo ciclo em poeira/sub-nano/simbolo invalido. PURO.
    #>
    param(
        [string]$Market,
        [double]$Qty,
        [double]$Price,
        [double]$MinNotionalUsd = 5.0
    )
    if ($Market -notmatch 'USDT$')      { return @{ placeable=$false; reason="simbolo_invalido" } }
    if ($Price -le 0)                   { return @{ placeable=$false; reason="sem_preco" } }
    if ($Price -lt 1e-7)                { return @{ placeable=$false; reason="preco_sub_nano" } }
    if (($Qty * $Price) -lt $MinNotionalUsd) { return @{ placeable=$false; reason="poeira" } }
    return @{ placeable=$true; reason="ok" }
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

    # Stop DESEJADO = o trailing stopCurrent quando MAIOR que o SL original (ratchet).
    # Assim o stop na corretora SEGUE o trailing pra cima (nao fica preso no SL inicial).
    if (-not $TrailingFile) {
        $__jdir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot) "journal" }
        $TrailingFile = Join-Path $__jdir "trailing_positions.json"
    }
    $trailMap = @{}
    if (Test-Path $TrailingFile) {
        try {
            foreach ($tp in (Get-Content $TrailingFile -Raw | ConvertFrom-Json)) {
                if ($tp.active -eq $true -and $tp.PSObject.Properties['stopCurrent']) {
                    $trailMap["$($tp.market)"] = [double]$tp.stopCurrent
                }
            }
        } catch {}
    }
    $Positions = @($Positions | ForEach-Object {
        $sp = [double]$_.stop_price
        $tc = if ($trailMap.ContainsKey("$($_.market)")) { $trailMap["$($_.market)"] } else { 0.0 }
        $desired = if ($tc -gt $sp) { $tc } else { $sp }   # LONG ratchet: pega o mais alto
        [pscustomobject]@{ market=$_.market; qty=$_.qty; stop_price=$desired }
    })

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
        $chk = Test-SpotStopPlaceable -Market $mkt -Qty ([double]$pos.qty) -Price $last
        if ($chk.placeable) {
            $placeable += $pos
        } else {
            # SKIP silencioso (ok=true -> daemon nao loga WARN): poeira nao polui o log.
            $results += [pscustomobject]@{ market=$mkt; action="SKIP_DUST"; ok=$true; detail=$chk.reason }
        }
    }
    $Positions = $placeable

    # Coleta stops SL pendentes por mercado (so sells com trigger abaixo do last = SL).
    $existing = @()
    foreach ($pos in @($Positions)) {
        $mkt = "$($pos.market)"
        try {
            $last = [double]$priceMap[$mkt]
            $so = CoinEx-Get "/v2/spot/pending-stop-order?market=$mkt&market_type=SPOT&page=1&limit=20"
            if ($so.code -eq 0) {
                foreach ($s in @($so.data)) {
                    if ("$($s.side)" -ne "sell") { continue }
                    $trig = [double]$s.trigger_price
                    if ($trig -le 0) { continue }
                    if ($last -gt 0 -and $trig -ge $last) { continue }  # TP, nao SL -> ignora
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
            CoinEx-PlaceSpotOrder -Market $mkt -Side "sell" -Type "market" -Amount ([double]$pos.qty) | Out-Null
            $results += [pscustomobject]@{ market=$mkt; action="FALLBACK_SELL"; ok=$true; detail=$fb.reason }
        } catch {
            $results += [pscustomobject]@{ market=$mkt; action="FALLBACK_SELL"; ok=$false; detail="erro: $_" }
        }
    }

    return $results
}
