# lib_position_risk_audit.ps1 — Auditoria de risco de posicoes abertas (2026-06-11)
# Pedido user: decisoes de protecao rapidas tomadas PELA aplicacao, nao em sessao manual.
# Caso real que motivou: XMRUSDT 20x isolated com liq a -12.7% do preco e SL decorativo
# ABAIXO da liq (nunca executaria) — nenhum modulo flagava. Fechado manual com +$1.82.
#
# Design fail-safe (Regra de Ouro 5):
#   - Get-PositionRiskAssessment: PURA (zero API/IO) — TDD via Pester
#   - Invoke-PositionRiskAudit: coleta posicoes futures, avalia, alerta TG;
#     EXECUTA apenas acoes de PROTECAO (mover SL — nunca abre/fecha posicao)
#     e somente com journal/RISK_AUTO_PROTECT.flag presente (opt-in explicito).

# ── Avaliacao pura ────────────────────────────────────────────────────────────
# $Position: market, side ("long"|"short"|"buy"|"sell"), leverage, entry, last,
#            liq_price, stop_loss_price (0/null = sem SL)
# Retorna findings: { market, type, severity, detail, action, action_price }
#   action: "SET_SL" (executavel) | "ALERT" (so notifica)
function Get-PositionRiskAssessment {
    param(
        [Parameter(Mandatory)] [object] $Position,
        [double] $LiqProximityPct = 15.0,  # CRITICAL se liq a menos de X% do preco
        [double] $ProfitLockPct   = 8.0,   # lucro >= X% com SL aquem do entry -> breakeven
        [double] $HighLeverage    = 10.0   # INFO acima disso
    )
    $findings = @()
    $entry = if ($Position.entry) { [double]$Position.entry } else { 0.0 }
    $last  = if ($Position.last) { [double]$Position.last } else { 0.0 }
    # return simples (sem ,): caller usa @() — comma-wrap faria array vazio virar Count=1
    if ($entry -le 0 -or $last -le 0) { return $findings }

    $side   = "$($Position.side)".ToLower()
    $isLong = ($side -in @("long", "buy"))
    $lev    = if ($Position.leverage) { [double]$Position.leverage } else { 1.0 }
    $liq    = if ($Position.liq_price) { [double]$Position.liq_price } else { 0.0 }
    $sl     = if ($Position.stop_loss_price) { [double]$Position.stop_loss_price } else { 0.0 }
    $pnlPct = if ($isLong) { (($last - $entry) / $entry) * 100 } else { (($entry - $last) / $entry) * 100 }

    # 1. SL inutil: stop ALEM da liquidacao — liq executa antes, SL nunca dispara.
    #    Acao: SL efetivo = liq com buffer 2% pra dentro.
    if ($liq -gt 0 -and $sl -gt 0) {
        $slBeyondLiq = if ($isLong) { $sl -lt $liq } else { $sl -gt $liq }
        if ($slBeyondLiq) {
            $newSl = if ($isLong) { $liq * 1.02 } else { $liq * 0.98 }
            $findings += [PSCustomObject]@{
                market = "$($Position.market)"; type = "USELESS_SL"; severity = "HIGH"
                detail = "SL $sl alem da liq $liq — stop real eh a liquidacao"
                action = "SET_SL"; action_price = [math]::Round($newSl, 10)
            }
        }
    }

    # 2. Liquidacao proxima: alerta CRITICAL. Fechar eh decisao humana/Mentor — nao auto.
    if ($liq -gt 0) {
        $dist = if ($isLong) { (($last - $liq) / $last) * 100 } else { (($liq - $last) / $last) * 100 }
        if ($dist -le $LiqProximityPct) {
            $findings += [PSCustomObject]@{
                market = "$($Position.market)"; type = "LIQ_PROXIMITY"; severity = "CRITICAL"
                detail = ("liq {0} a {1:0.0}% do preco {2} (lev {3}x)" -f $liq, $dist, $last, $lev)
                action = "ALERT"; action_price = $null
            }
        }
    }

    # 3a. RATCHET de lucro (2026-06-12, gap spot do AIN +26% destravado): ganho
    #     >= RatchetPct trava METADE do ganho. SL protetor = entry +/- pnl/2.
    #     Sobe junto com o pump (monotonico - executor so RAISE). Supersede o
    #     breakeven simples quando dispara (evita 2 SET_SL no mesmo ciclo).
    $RatchetPct = 15.0
    $ratchetFired = $false
    if ($pnlPct -ge $RatchetPct) {
        $protSl = if ($isLong) { $entry * (1 + $pnlPct / 200) } else { $entry * (1 - $pnlPct / 200) }
        $below = ($sl -le 0) -or
                 ($isLong -and $sl -lt $protSl) -or
                 ((-not $isLong) -and $sl -gt $protSl)
        if ($below) {
            $ratchetFired = $true
            $findings += [PSCustomObject]@{
                market = "$($Position.market)"; type = "PROFIT_RATCHET"; severity = "MEDIUM"
                detail = ("PnL {0:+0.0}% - ratchet trava metade do ganho (SL atual {1})" -f $pnlPct, $sl)
                action = "SET_SL"; action_price = [math]::Round($protSl, 10)
            }
        }
    }

    # 3b. Lucro destravado: pnl >= threshold e SL nao protege o entry -> breakeven + 0.2% fee buffer
    if ($pnlPct -ge $ProfitLockPct -and -not $ratchetFired) {
        $beSl = if ($isLong) { $entry * 1.002 } else { $entry * 0.998 }
        $unprotected = ($sl -le 0) -or
                       ($isLong -and $sl -lt $beSl) -or
                       ((-not $isLong) -and $sl -gt $beSl)
        if ($unprotected) {
            $findings += [PSCustomObject]@{
                market = "$($Position.market)"; type = "PROFIT_UNLOCKED"; severity = "MEDIUM"
                detail = ("PnL {0:+0.0}% sem SL protegendo entry {1}" -f $pnlPct, $entry)
                action = "SET_SL"; action_price = [math]::Round($beSl, 10)
            }
        }
    }

    # 4. Leverage alto: informativo (sizing/entrada eh responsabilidade dos gates)
    if ($lev -ge $HighLeverage) {
        $findings += [PSCustomObject]@{
            market = "$($Position.market)"; type = "HIGH_LEVERAGE"; severity = "INFO"
            detail = "leverage ${lev}x >= ${HighLeverage}x"
            action = "ALERT"; action_price = $null
        }
    }

    return $findings
}

# ── Coleta + execucao fail-safe ───────────────────────────────────────────────
function Invoke-PositionRiskAudit {
    [CmdletBinding()]
    param([switch] $AutoProtect)

    if (-not (Get-Command CoinEx-Get -ErrorAction SilentlyContinue)) {
        Write-Warning "[RiskAudit] lib_coinex nao carregada; skip"
        return
    }

    $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot -Parent) "journal" }
    $autoFlag = $AutoProtect -or (Test-Path (Join-Path $journalDir "RISK_AUTO_PROTECT.flag"))
    $statePath = Join-Path $journalDir "risk_audit_state.json"

    # Dedup de alertas: 1 alerta por market:type por dia (nao spamar TG a cada ciclo)
    $alerted = @{}
    if (Test-Path $statePath) {
        try { (Get-Content $statePath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $alerted[$_.Name] = $_.Value } } catch {}
    }
    $today = Get-Date -Format "yyyy-MM-dd"

    $positions = @()
    try {
        $fp = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES"
        if ($fp.code -eq 0) {
            foreach ($p in @($fp.data)) {
                if (-not $p -or -not $p.market) { continue }
                $last = 0.0
                try { $t = CoinEx-GetTicker $p.market; $last = [double]$t.last } catch {}
                if ($last -le 0) { continue }
                $positions += [PSCustomObject]@{
                    market = "$($p.market)"; side = "$($p.side)"
                    leverage = $p.leverage; entry = $p.avg_entry_price; last = $last
                    liq_price = $p.liq_price; stop_loss_price = $p.stop_loss_price
                }
            }
        }
    } catch {
        Write-Warning "[RiskAudit] coleta falhou: $_"
        return
    }

    foreach ($pos in $positions) {
        $findings = @(Get-PositionRiskAssessment -Position $pos)
        foreach ($f in $findings) {
            $key = "$($f.market):$($f.type)"
            $color = switch ($f.severity) { "CRITICAL" { "Red" } "HIGH" { "Red" } "MEDIUM" { "Yellow" } default { "DarkYellow" } }
            Write-Host "  [RiskAudit] $($f.severity) $($f.market) $($f.type): $($f.detail)" -ForegroundColor $color

            # Auto-protecao: so SET_SL (mover stop), nunca abrir/fechar posicao
            $executed = $false
            if ($autoFlag -and $f.action -eq "SET_SL" -and $f.action_price -and
                (Get-Command CoinEx-ModifyPositionStopLoss -ErrorAction SilentlyContinue)) {
                try {
                    $r = CoinEx-ModifyPositionStopLoss -Market $f.market -Price ([decimal]$f.action_price)
                    if ($r.success) {
                        $executed = $true
                        Write-Host "  [RiskAudit] PROTEGIDO: $($f.market) SL -> $($f.action_price)" -ForegroundColor Green
                    }
                } catch { Write-Warning "[RiskAudit] SET_SL $($f.market) falhou: $_" }
            }

            # Telegram: severity >= MEDIUM, dedup por dia (acao executada sempre notifica)
            $shouldAlert = ($f.severity -in @("CRITICAL", "HIGH", "MEDIUM")) -and
                           ($executed -or $alerted[$key] -ne $today)
            if ($shouldAlert -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
                $sufixo = if ($executed) { "`n✅ AUTO: SL movido para $($f.action_price)" }
                          elseif ($f.action -eq "SET_SL") { "`nRecomendado: SL -> $($f.action_price) (RISK_AUTO_PROTECT.flag ativa execucao)" }
                          else { "" }
                try { Send-TelegramAlert -Message "🛡️ RISK AUDIT [$($f.severity)] $($f.market) $($f.type)`n$($f.detail)$sufixo" | Out-Null } catch {}
                $alerted[$key] = $today
            }
        }
    }

    # ── SPOT (2026-06-12): GEMs do trailing — gap que deixou AIN +26% destravado.
    # Sem liq em spot; regras ativas: PROFIT_RATCHET / PROFIT_UNLOCKED.
    # Executor fail-safe: novo stop ANTES de cancelar o velho (nunca fica sem stop);
    # monotonico (LONG so sobe). Tudo opt-in via mesma flag RISK_AUTO_PROTECT.
    if (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue) {
        $spotBalances = @{}
        try {
            $sb = CoinEx-Get "/v2/assets/spot/balance"
            if ($sb.code -eq 0) {
                foreach ($b in @($sb.data)) { $spotBalances["$($b.ccy)".ToUpper()] = [double]$b.available + [double]$b.frozen }
            }
        } catch { Write-Warning "[RiskAudit] spot balance falhou: $_"; return }

        $spotTrailing = @(Get-TrailingPositions | Where-Object { $_.active })
        foreach ($tpos in $spotTrailing) {
            $mkt = "$($tpos.market)"
            $base = if ($mkt -match "USDT$") { $mkt.Substring(0, $mkt.Length - 4) } else { $mkt }
            $qty = if ($spotBalances.ContainsKey($base)) { $spotBalances[$base] } else { 0.0 }
            if ($qty -le 0) { continue }  # nao eh spot (ou ja vendida)

            $last = 0.0
            try { $t = CoinEx-GetTicker $mkt; $last = [double]$t.last } catch {}
            if ($last -le 0) { continue }
            if ($qty * $last -lt 2) { continue }  # dust

            # SL real = trigger do stop order pendente na corretora (nao o arquivo)
            $stopOrder = $null
            try {
                $so = CoinEx-Get "/v2/spot/pending-stop-order?market=$mkt&market_type=SPOT&page=1&limit=10"
                $stopOrder = @($so.data) | Where-Object { $_.stop_id -and $_.side -eq "sell" } | Select-Object -First 1
            } catch {
                # fail-closed: sem visibilidade do stop atual, nao mexe neste mercado
                Write-Warning "[RiskAudit] $mkt pending-stop-order falhou; skip"
                continue
            }
            $slCur = if ($stopOrder) { [double]$stopOrder.trigger_price } else { 0.0 }

            $pos = [PSCustomObject]@{
                market = $mkt; side = "long"; leverage = 1
                entry = $tpos.entry; last = $last
                liq_price = 0; stop_loss_price = $slCur
            }
            $findings = @(Get-PositionRiskAssessment -Position $pos)
            foreach ($f in $findings) {
                $key = "$($f.market):$($f.type):spot"
                Write-Host "  [RiskAudit][SPOT] $($f.severity) $($f.market) $($f.type): $($f.detail)" -ForegroundColor Yellow

                $executed = $false
                $newSl = [double]$f.action_price
                # monotonico: LONG spot so SOBE o stop
                if ($autoFlag -and $f.action -eq "SET_SL" -and $newSl -gt $slCur -and
                    (Get-Command CoinEx-PlaceSpotStopOrder -ErrorAction SilentlyContinue)) {
                    try {
                        $rNew = CoinEx-PlaceSpotStopOrder -Market $mkt -Side "sell" -Amount $qty -TriggerPrice $newSl
                        if ($rNew -and $rNew.stop_id) {
                            $executed = $true
                            # novo confirmado -> cancela o antigo (se falhar, fica stop duplo inofensivo)
                            if ($stopOrder) {
                                try { CoinEx-Post "/v2/spot/cancel-stop-order" @{ market = $mkt; market_type = "SPOT"; stop_id = [long]$stopOrder.stop_id } | Out-Null } catch {
                                    Write-Warning "[RiskAudit] $mkt cancel stop velho falhou (duplo stop, inofensivo): $_"
                                }
                            }
                            # sincroniza trailing file (stopCurrent so sobe)
                            try {
                                $all = @(Get-TrailingPositions)
                                foreach ($p2 in $all) {
                                    if ($p2.market -eq $mkt -and $p2.active -and [double]$p2.stopCurrent -lt $newSl) {
                                        $p2.stopCurrent = $newSl; $p2.stop = $newSl
                                        $p2.updatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                                    }
                                }
                                Save-TrailingPositions $all
                            } catch { Write-Warning "[RiskAudit] $mkt trailing sync: $_" }
                            Write-Host "  [RiskAudit][SPOT] PROTEGIDO: $mkt stop -> $newSl (qty $qty)" -ForegroundColor Green
                        }
                    } catch { Write-Warning "[RiskAudit] SET_SL spot $mkt falhou: $_" }
                }

                $shouldAlert = ($f.severity -in @("CRITICAL", "HIGH", "MEDIUM")) -and
                               ($executed -or $alerted[$key] -ne $today)
                if ($shouldAlert -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
                    $sufixo = if ($executed) { "`n[OK] AUTO: stop spot movido para $newSl" }
                              elseif ($f.action -eq "SET_SL") { "`nRecomendado: stop -> $($f.action_price)" }
                              else { "" }
                    try { Send-TelegramAlert -Message "RISK AUDIT SPOT [$($f.severity)] $($f.market) $($f.type)`n$($f.detail)$sufixo" | Out-Null } catch {}
                    $alerted[$key] = $today
                }
            }
        }
    }

    try { $alerted | ConvertTo-Json | Set-Content $statePath -Encoding utf8 } catch {}
}
