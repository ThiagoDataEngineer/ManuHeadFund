# agents/lib_trailing_adaptive.ps1
# TDD-driven: Adaptive trailing stops with ATR-dynamic buffer + regime-aware
# Evolução do lib_trailing.ps1 original
#
# Camada 1: ATR-Dinâmico + Regime-Aware (esta implementação)
# Camadas 2-5 virão depois (Mentor reflection, Kelly, Tori, Moon bag)
#
# Dot-source: . (Join-Path $PSScriptRoot "lib_trailing_adaptive.ps1")

# -------------------------------------------------------------------------
# Get-AdaptiveBuffer -- Calcula buffer dinamico por regime + volatilidade
# -------------------------------------------------------------------------
function Get-AdaptiveBuffer {
    <#
    .SYNOPSIS
    Calcula buffer adaptativo para breakeven transition baseado em regime + ATR.
    
    .PARAMETER Range
    Distancia entry -> target (movimento esperado)
    
    .PARAMETER CurrentAtr
    ATR atual (volatilidade intraday)
    
    .PARAMETER HistoricalAtr
    ATR médio histórico (volatilidade baseline)
    
    .PARAMETER Regime
    Regime de mercado: BULL_STRONG, BULL_WEAK, SIDEWAYS, BEAR_STRONG, CAPITULATION, etc
    
    .OUTPUTS
    [double] Buffer em valor absoluto (não percentual)
    
    .EXAMPLE
    $buf = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BULL_STRONG"
    # Retorna ~75 (100 * 0.75 = tight stops em trending market)
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory=$true)][double]$Range,
        [Parameter(Mandatory=$true)][double]$CurrentAtr,
        [Parameter(Mandatory=$true)][double]$HistoricalAtr,
        [ValidateSet("BULL_STRONG","BULL_WEAK","SIDEWAYS","TRANSITION_UP",
                     "TRANSITION_DOWN","BEAR_WEAK","BEAR_STRONG","CAPITULATION")]
        [string]$Regime = "SIDEWAYS"
    )

    # Regime multiplier: controla agressividade do stop por condição de mercado
    $regimeMultiplier = switch($Regime) {
        "BULL_STRONG"       { 0.75 }   # Tight: trending market, confiança alta
        "BULL_WEAK"         { 1.0 }    # Normal: high still there but weakening
        "SIDEWAYS"          { 1.3 }    # Wide: defend against pullback noise
        "TRANSITION_UP"     { 1.1 }    # Slight wider: transitioning up
        "TRANSITION_DOWN"   { 1.2 }    # Wider: caution in downward transition
        "BEAR_WEAK"         { 1.4 }    # Very wide: bear market, protect vs spikes
        "BEAR_STRONG"       { 1.5 }    # Extremely wide: strong downtrend, hold longer
        "CAPITULATION"      { 0.5 }    # Ultra tight: panic phase, exit quick
        default             { 1.0 }
    }

    # ATR ratio: se vol atual > histórica, aumenta buffer; se menor, reduz
    # Evita divide by zero
    $atrRatio = if ($HistoricalAtr -gt 0) {
        $CurrentAtr / $HistoricalAtr
    } else {
        1.0
    }

    # Buffer base = CurrentAtr × regime multiplier × vol ratio
    $buffer = $CurrentAtr * $regimeMultiplier * $atrRatio

    # Minimum floor: não deixar buffer tão apertado que perde a lucratividade
    # 1.5% do range é limite defensivo
    $minBuffer = [math]::Max($Range * 0.015, 1.0)  # never zero

    return [math]::Max($buffer, $minBuffer)
}

# -------------------------------------------------------------------------
# Get-TrailingNewStopAdaptive -- Calcula novo stop por fase com buffer adaptativo
# -------------------------------------------------------------------------
function Get-TrailingNewStopAdaptive {
    <#
    .SYNOPSIS
    Calcula novo stop para posição em trailing com adaptação por regime.
    
    .PARAMETER Pos
    Posição atual [PSCustomObject] com market, side, entry, target, phase, peak, stopCurrent
    
    .PARAMETER CurrentPrice
    Preço atual do ativo
    
    .PARAMETER Regime
    Regime de mercado para ajustar agressividade
    
    .PARAMETER CurrentAtr
    ATR atual (opcional, default 100 para teste)
    
    .PARAMETER HistoricalAtr
    ATR histórico (opcional, default 100)
    
    .OUTPUTS
    [PSCustomObject]@{ newStop, newPhase, newPeak, changed }
    
    .DESCRIPTION
    Fases (LONG):
      0 → 1: Preço atinge 33% do alvo → move stop para BE + adaptive buffer
      1 → 2: Preço atinge 66% do alvo → move stop para lock +33% do ganho
      2 → 3: Preço atinge alvo → move stop para trailing 15% abaixo do pico
      3:     Trailing ativo → atualiza stop se novo pico quebra trailing
    
    SHORT espelhado.
    
    .EXAMPLE
    $pos = [PSCustomObject]@{ market="BTCUSDT"; side="LONG"; entry=60000; target=70000; 
                               phase=0; peak=60000; stopCurrent=59000 }
    $result = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice 63333 -Regime "BULL_STRONG"
    # $result.newPhase = 1, $result.newStop ≈ 60050 (BE + small buffer)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$Pos,
        [Parameter(Mandatory=$true)][double]$CurrentPrice,
        [ValidateSet("BULL_STRONG","BULL_WEAK","SIDEWAYS","TRANSITION_UP",
                     "TRANSITION_DOWN","BEAR_WEAK","BEAR_STRONG","CAPITULATION")]
        [string]$Regime = "SIDEWAYS",
        [double]$CurrentAtr = 100,
        [double]$HistoricalAtr = 100
    )

    $entry  = [double]$Pos.entry
    $target = [double]$Pos.target
    $stop   = [double]$Pos.stopCurrent
    $peak   = [double]$Pos.peak
    $phase  = [int]$Pos.phase
    $side   = $Pos.side

    # Range e buffer adaptativo
    $range  = [math]::Abs($target - $entry)
    $buffer = Get-AdaptiveBuffer -Range $range -CurrentAtr $CurrentAtr `
                                 -HistoricalAtr $HistoricalAtr -Regime $Regime

    $newStop  = $stop
    $newPhase = $phase
    $changed  = $false

    if ($side -eq "LONG") {
        # Pontos de transição em % do alvo
        $gain33  = $entry + $range * 0.33
        $gain66  = $entry + $range * 0.66
        $newPeak = [math]::Max($peak, $CurrentPrice)

        # 2026-07-08: TOP INSTINCT — Detecta signs de reversão em topo
        $topInstinct = $false
        if ($phase -eq 3 -and $newPeak -eq $peak -and $CurrentPrice -ge ($peak * 0.98)) {
            # Pico não muda + preço perto = pico potencial, aperta SL
            $topInstinct = $true
        }

        if ($phase -lt 3 -and $CurrentPrice -ge $target) {
            # Fase 3: Trailing ativo — 15% abaixo do pico, nunca recua
            $newPhase = 3
            $tightFactor = if ($topInstinct) { 0.90 } else { 0.85 }
            $newStop  = [math]::Round($newPeak * $tightFactor, 4)
            $changed  = $true
        } elseif ($phase -lt 2 -and $CurrentPrice -ge $gain66) {
            # Fase 2: Lock +33% do ganho
            $newPhase = 2
            $newStop  = [math]::Round($entry + $range * 0.33, 4)
            $changed  = $true
        } elseif ($phase -lt 1 -and $CurrentPrice -ge $gain33) {
            # Fase 1: Breakeven + adaptive buffer
            $newPhase = 1
            $newStop  = [math]::Round($entry + $buffer, 4)
            $changed  = $true
        } elseif ($phase -eq 3) {
            # Fase 3 ativa: atualizar trailing se novo pico
            $potentialNewStop = [math]::Round($newPeak * 0.85, 4)
            if ($potentialNewStop -gt $stop) {
                $newStop = $potentialNewStop
                $changed = $true
            }
        }

    } else {
        # SHORT: lógica espelhada
        $gain33  = $entry - $range * 0.33
        $gain66  = $entry - $range * 0.66
        $newPeak = [math]::Min($peak, $CurrentPrice)

        # 2026-07-08: TOP INSTINCT — SHORT: detecta floor (fundo potencial)
        $topInstinct = $false
        if ($phase -eq 3 -and $newPeak -eq $peak -and $CurrentPrice -le ($peak * 1.02)) {
            # Pico (piso) não muda + preço perto = piso potencial, aperta SL
            $topInstinct = $true
        }

        if ($phase -lt 3 -and $CurrentPrice -le $target) {
            # Fase 3 SHORT: trailing 15% acima do pico (preço mínimo), nunca recua
            $newPhase = 3
            $tightFactor = if ($topInstinct) { 1.10 } else { 1.15 }
            $newStop  = [math]::Round($newPeak * $tightFactor, 4)
            $changed  = $true
        } elseif ($phase -lt 2 -and $CurrentPrice -le $gain66) {
            # Fase 2 SHORT: lock +33% do ganho (stop sobe, pois SHORT)
            $newPhase = 2
            $newStop  = [math]::Round($entry - $range * 0.33, 4)
            $changed  = $true
        } elseif ($phase -lt 1 -and $CurrentPrice -le $gain33) {
            # Fase 1 SHORT: BE - adaptive buffer
            $newPhase = 1
            $newStop  = [math]::Round($entry - $buffer, 4)
            $changed  = $true
        } elseif ($phase -eq 3) {
            # Fase 3 SHORT ativa: atualizar trailing
            $potentialNewStop = [math]::Round($newPeak * 1.15, 4)
            if ($potentialNewStop -lt $stop) {
                $newStop = $potentialNewStop
                $changed = $true
            }
        }
    }

    # Sempre atualizar peak (fix 2026-05-25: persistir peak mesmo sem fase change)
    $peakChanged = ($newPeak -ne $peak)
    if ($peakChanged) {
        $changed = $true
    }

    return [PSCustomObject]@{
        newStop  = $newStop
        newPhase = $newPhase
        newPeak  = $newPeak
        changed  = $changed
    }
}

# -------------------------------------------------------------------------
# Resolve-AdaptiveStopPersist -- decide persistencia (PURO, TDD)
# -------------------------------------------------------------------------
function Resolve-AdaptiveStopPersist {
    <#
    .SYNOPSIS
    Decide se stopCurrent/phase devem ser persistidos apos o calc do trailing.

    .DESCRIPTION
    PURO (sem I/O). Guard monotonico: o stop NUNCA afrouxa (LONG so sobe / SHORT so desce).
    Corrige a regressao 2026-06-26 (SLX +54% travado protegendo so +28%): antes a
    persistencia gateava SO em mudanca de fase -> runner na fase 3 (terminal) congelava
    o stop pra sempre, pois newPhase nunca diferia de phase. Agora persiste tambem quando
    o trailing ratcheta o stop dentro da mesma fase.

    .OUTPUTS
    [PSCustomObject]@{ update, stopImproved, phaseChanged, newStop, newPhase }
    #>
    param(
        [string]$Side,
        [double]$CurrentStop,
        [int]$CurrentPhase,
        [bool]$CalcChanged,
        [double]$CalcNewStop,
        [int]$CalcNewPhase
    )
    $isShort = ("$Side".ToUpper() -eq "SHORT")
    $stopImproved = if ($isShort) { ($CurrentStop -le 0) -or ($CalcNewStop -lt $CurrentStop) } `
                    else         { $CalcNewStop -gt $CurrentStop }
    $phaseChanged = ($CalcNewPhase -ne $CurrentPhase)
    $shouldUpdate = $CalcChanged -and ($phaseChanged -or $stopImproved)
    $newStop = if ($stopImproved) { $CalcNewStop } else { $CurrentStop }
    return [PSCustomObject]@{
        update       = [bool]$shouldUpdate
        stopImproved = [bool]$stopImproved
        phaseChanged = [bool]$phaseChanged
        newStop      = [double]$newStop
        newPhase     = [int]$CalcNewPhase
    }
}

# -------------------------------------------------------------------------
# Update-TrailingStopsAdaptive -- Wrapper que integra adaptive no ciclo master
# -------------------------------------------------------------------------
function Update-TrailingStopsAdaptive {
    <#
    .SYNOPSIS
    Atualiza trailing stops LIVE com buffers adaptativos (substitui Update-TrailingStops).
    
    .DESCRIPTION
    Para cada posição ativa:
    1. Busca regime atual
    2. Busca ATR atual vs histórico
    3. Chama Get-TrailingNewStopAdaptive
    4. Se changed, move stop na exchange + telegram alert
    5. Persiste estado
    
    Requer: Get-TrailingPositions, Save-TrailingPositions, Get-MacroContext
            (ou lib_trailing.ps1 para persistência)
    #>
    [CmdletBinding()]
    param(
        [string]$JournalDir = ""
    )

    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } `
                      else { Join-Path (Split-Path $PSScriptRoot -Parent) "journal" }
    }

    # Busca regime atual (macro context)
    $regime = "SIDEWAYS"
    if (Get-Command Get-MacroContext -ErrorAction SilentlyContinue) {
        try {
            $macro = Get-MacroContext
            if ($macro -and $macro.regime) {
                $regime = [string]$macro.regime
            }
        } catch { }
    }

    # Busca ATR atual (placeholder; em prod usaria últimas barras)
    $currentAtr = 100.0
    $historicalAtr = 100.0
    if (Get-Command Get-TechnicalIndicators -ErrorAction SilentlyContinue) {
        try {
            # Placeholder: em prod carregaria ATR real
        } catch { }
    }

    # Itera posições ativas
    if (-not (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue)) {
        Write-Warning "[Adaptive Trailing] Get-TrailingPositions não encontrada; skipping"
        return
    }

    $positions = @(Get-TrailingPositions)
    $active = $positions | Where-Object { $_.active }

    if (-not $active -or @($active).Count -eq 0) {
        if ($Verbose) { Write-Host "  [Adaptive Trailing] Nenhuma posição ativa." -ForegroundColor DarkGray }
        return
    }

    Write-Host "  [Adaptive Trailing] Verificando $(@($active).Count) posição(ões) com regime=$regime..." -ForegroundColor DarkGreen

    $updated = $false
    $positions = $positions | ForEach-Object {
        $pos = $_
        if (-not $pos.active) { return $pos }

        try {
            # Busca preço atual
            if (Get-Command CoinEx-GetTicker -ErrorAction SilentlyContinue) {
                $ticker = CoinEx-GetTicker $pos.market
                if (-not $ticker) { return $pos }
                $price = [double]$ticker.last
            } else {
                if ($Verbose) { Write-Host "  [Adaptive Trailing] CoinEx-GetTicker não disponível; skip $($pos.market)" }
                return $pos
            }

            # Calcula novo stop
            $calc = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $price -Regime $regime `
                                                -CurrentAtr $currentAtr -HistoricalAtr $historicalAtr

            # Verifica se stop foi atingido (ANTES de atualizar peak)
            $stopped = if ($pos.side -eq "LONG") { $price -le [double]$pos.stopCurrent } `
                       else                       { $price -ge [double]$pos.stopCurrent }

            if ($stopped) {
                # CLOSE POSIÇÃO
                $msg = "[STOP HIT] $($pos.market) $($pos.side) @ $price (stop=$($pos.stopCurrent))"
                Write-Host "  [Adaptive Trailing] $msg" -ForegroundColor Red
                if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
                    try { Send-TelegramAlert -Message $msg | Out-Null } catch { }
                }
                $pos.active = $false
                $pos | Add-Member -NotePropertyName "closedAt" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
                $pos | Add-Member -NotePropertyName "closeReason" -NotePropertyValue "stop_atingido" -Force
                $updated = $true
                return $pos
            }

            # Atualiza peak SEMPRE (fix 2026-05-25)
            if ($calc.newPeak -ne [double]$pos.peak) {
                $pos.peak = $calc.newPeak
                $updated = $true
            }

            # Atualiza stop quando muda de fase OU quando o trailing ratcheta na fase 3.
            # 2026-06-26 FIX (regressao SLX +54% travado protegendo so +28%): antes so
            # atualizava em phase change -> runner na fase 3 (terminal) congelava o
            # stopCurrent pra sempre; o peak subia mas o stop nunca acompanhava.
            # Guard monotonico: NUNCA afrouxa (LONG so sobe / SHORT so desce).
            $persist = Resolve-AdaptiveStopPersist -Side "$($pos.side)" `
                          -CurrentStop ([double]$pos.stopCurrent) -CurrentPhase ([int]$pos.phase) `
                          -CalcChanged ([bool]$calc.changed) -CalcNewStop ([double]$calc.newStop) `
                          -CalcNewPhase ([int]$calc.newPhase)
            $stopImproved = $persist.stopImproved
            if ($persist.update) {
                $oldPhase = $pos.phase
                $oldStop = $pos.stopCurrent
                if ($persist.stopImproved) { $pos.stopCurrent = $persist.newStop }
                $pos.phase = $persist.newPhase
                $pos.updatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                $updated = $true

                # 2026-06-01: Calcular mudança percentual e filtrar pequenas mudanças
                $changePct = if ($oldStop -gt 0) {
                    [math]::Abs(([double]$pos.stopCurrent - $oldStop) / $oldStop * 100)
                } else {
                    0
                }
                
                $minChange = if ($global:TELEGRAM_TRAILING_MIN_CHANGE_PCT) {
                    $global:TELEGRAM_TRAILING_MIN_CHANGE_PCT
                } else {
                    5.0
                }

                $phaseLabel = @("inicial", "breakeven", "lock+33%", "trailing")
                $msg = "[PHASE] $($pos.market) $($pos.side) fase $oldPhase->$($pos.phase) ($($phaseLabel[$pos.phase])) stop $oldStop->$($pos.stopCurrent) | regime=$regime"
                Write-Host "  [Adaptive Trailing] $msg" -ForegroundColor Green
                
                # 2026-06-01: Trailing é cobertura de trades vivos - SEMPRE enviar (TIER IMPORTANT)
                # Não filtrar por INFORMATIVE (que está desativado em production)
                if ($changePct -ge $minChange -and (Get-Command Send-TelegramAlertFiltered -ErrorAction SilentlyContinue)) {
                    try { Send-TelegramAlertFiltered -Message $msg -Tier "IMPORTANT" | Out-Null } catch { }
                }

                # Tenta mover stop na exchange (FUTURES; pos SPOT cai no catch e e
                # protegida de verdade via lib_spot_stop_guard, que le este mesmo
                # stopCurrent). 2026-06-25 fix: chamava com -OrderId/-StopPrice que
                # nao existem na assinatura real CoinEx-SetStopLoss($market,$price)
                # -- PowerShell ignorava os nomeados sem dar erro, $price ficava
                # $null e a chamada nunca movia nada (sempre silenciosamente noop).
                if ($stopImproved -and (Get-Command CoinEx-SetStopLoss -ErrorAction SilentlyContinue)) {
                    try {
                        CoinEx-SetStopLoss -market $pos.market -price $pos.stopCurrent | Out-Null
                    } catch {
                        Write-Host "  [Adaptive Trailing] Aviso: não foi possível mover stop: $_" -ForegroundColor DarkYellow
                    }
                }
            }

        } catch {
            Write-Host "  [Adaptive Trailing] Erro ao processar $($pos.market): $_" -ForegroundColor DarkRed
        }
        return $pos
    }

    if ($updated -and (Get-Command Save-TrailingPositions -ErrorAction SilentlyContinue)) {
        Save-TrailingPositions @($positions)
    }
}

# Funções exportadas: Get-AdaptiveBuffer, Get-TrailingNewStopAdaptive, Update-TrailingStopsAdaptive
# Dot-source ao usar (não é módulo formal)


# -------------------------------------------------------------------------
# Sync-TrailingPositionsWithExchange - Sincroniza posicoes com CoinEx
# -------------------------------------------------------------------------
# 2026-06-01: Função para sincronizar posições abertas com a exchange
# Problema: Quando usuário muda stop/target manualmente na ferramenta,
# o arquivo trailing_positions.json não é atualizado automaticamente.
# Solução: Buscar posições abertas da exchange e atualizar arquivo.
function Sync-TrailingPositionsWithExchange {
    <#
    .SYNOPSIS
    Sincroniza posições de trailing com dados reais da exchange.
    
    .DESCRIPTION
    1. Busca posições abertas da CoinEx
    2. Para cada posição aberta, verifica se existe em trailing_positions.json
    3. Se existe, atualiza stop/target com valores reais da exchange
    4. Se não existe, cria nova entrada
    5. Persiste arquivo atualizado
    
    Útil quando usuário muda stop/target manualmente na ferramenta.
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command CoinEx-GetOpenOrders -ErrorAction SilentlyContinue)) {
        Write-Warning "[Sync Trailing] CoinEx-GetOpenOrders não disponível; skipping sync"
        return
    }

    if (-not (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue)) {
        Write-Warning "[Sync Trailing] Get-TrailingPositions não disponível; skipping sync"
        return
    }

    try {
        # Busca posições abertas da exchange
        $openOrders = @(CoinEx-GetOpenOrders)
        if (-not $openOrders -or @($openOrders).Count -eq 0) {
            if ($Verbose) { Write-Host "  [Sync Trailing] Nenhuma posição aberta na exchange." -ForegroundColor DarkGray }
            return
        }

        # Carrega posições atuais do arquivo
        $positions = @(Get-TrailingPositions)
        $updated = $false

        # Para cada ordem aberta na exchange
        foreach ($order in $openOrders) {
            $market = [string]$order.market
            $orderId = [string]$order.order_id
            
            # Procura posição correspondente por MARKET (2026-06-25 fix: orderId
            # rotaciona a cada novo stop colocado na corretora -- exigir
            # orderId igual fazia o sync nao reconhecer uma posicao previamente
            # fechada (active=false, orderId antigo) quando ela reabria com um
            # novo stop, e criava uma entrada DUPLICATA "exchange_sync" pro
            # mesmo market (causa raiz do caso ZANOUSDT: registro GEM fechado
            # por stop ficava orfao enquanto um 2o registro fantasma nascia sem
            # pk_id/qty, quebrando o upsert Supabase por pk_id=market e
            # deixando a posicao real mal gerenciada). Exclui moon bag legs
            # (moonBagKind) do match -- esses sao geridos por lib_moon_bag, nao
            # pelo sync da exchange.
            $existing = $positions | Where-Object {
                $_.market -eq $market -and -not $_.moonBagKind
            } | Select-Object -First 1

            if ($existing) {
                # 2026-07-22 BACKFILL: registros criados antes do campo origin
                # existir (pre-2026-07-18) ou por caminhos que nao o gravavam
                # (exchange_sync/orphan_auto_register) ficam permanentemente
                # fora da avaliacao do motor shadow (lib_trailing_unified.ps1
                # exige origin.{asset_class,trade_style}, fail-closed, nunca
                # adivinha). Sync roda todo ciclo -- oportunidade natural de
                # corrigir o backlog sem precisar de migracao separada.
                if (-not $existing.origin -or -not $existing.origin.asset_class -or -not $existing.origin.trade_style) {
                    $existing | Add-Member -NotePropertyName "origin" -NotePropertyValue @{
                        asset_class = "$($order.position_type)".ToUpper()
                        trade_style = "SWING"
                    } -Force
                    $updated = $true
                }
                $wasInactive = -not $existing.active
                $oldStop = $existing.stopCurrent
                $oldTarget = $existing.target

                # Busca stop loss e take profit reais
                $newStop = if ($order.stop_price) { [double]$order.stop_price } else { $existing.stopCurrent }
                $newTarget = if ($order.take_profit_price) { [double]$order.take_profit_price } else { $existing.target }

                # Reabre registro antigo quando a exchange mostra ordem viva de
                # novo no mesmo market (posicao fechada e reentrada) -- sem isso
                # o registro ficava com active=false e invisivel pro
                # Update-TrailingStopsAdaptive, mesmo com posicao real aberta.
                if ($wasInactive) {
                    Write-Host ("  [Sync Trailing] {0}: posicao reaberta na exchange (orderId {1} -> {2}) -- reativando registro" -f $market, $existing.orderId, $orderId) -ForegroundColor Yellow
                    $existing.active = $true
                    $existing.entry = [double]$order.price
                    $existing.peak = [double]$order.price
                    $existing.phase = 0
                    $existing.openedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    $existing | Add-Member -NotePropertyName "closedAt" -NotePropertyValue $null -Force
                    $existing | Add-Member -NotePropertyName "closeReason" -NotePropertyValue $null -Force
                    $existing | Add-Member -NotePropertyName "exitPrice" -NotePropertyValue $null -Force
                    $updated = $true
                }
                if ($orderId -and $existing.orderId -ne $orderId) {
                    $existing.orderId = $orderId
                    $updated = $true
                }

                if ($newStop -ne $oldStop -or $newTarget -ne $oldTarget) {
                    Write-Host ("  [Sync Trailing] {0}: stop {1} -> {2}, target {3} -> {4}" -f $market, $oldStop, $newStop, $oldTarget, $newTarget) -ForegroundColor Cyan
                    $existing.stopCurrent = $newStop
                    $existing.target = $newTarget
                    $existing.updatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    $updated = $true

                    # Notificar via Telegram
                    $msg = "SYNC: $market stop atualizado $oldStop -> $newStop (mudanca manual detectada)"
                    if (Get-Command Send-TelegramAlertFiltered -ErrorAction SilentlyContinue) {
                        try { Send-TelegramAlertFiltered -Message $msg -Tier "IMPORTANT" | Out-Null } catch { }
                    }
                } elseif ($wasInactive) {
                    $existing.updatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    $msg = "SYNC: $market reaberto na exchange -- registro de trailing reativado (era stop_atingido)"
                    if (Get-Command Send-TelegramAlertFiltered -ErrorAction SilentlyContinue) {
                        try { Send-TelegramAlertFiltered -Message $msg -Tier "IMPORTANT" | Out-Null } catch { }
                    }
                }
            } else {
                # 2026-06-11 guard: holdings passivos SPOT (PAXG, CET, BTC parking...)
                # nao tem stop orders — registra-los no trailing poderia auto-vende-los.
                # 2026-07-07 fix: o guard so vale pra SPOT. Uma posicao FUTURES (alavancada)
                # SEM stop e o caso mais perigoso de deixar solta (ex.: WLDUSDT short sl=0
                # ficava fora do trailing). FUTURES e SEMPRE adotada; se vier sem stop,
                # calcula-se um stop protetivo DIRECIONAL e o Sync-TrailingToExchange do
                # ciclo empurra pra corretora.
                $posType = "$($order.position_type)".ToUpper()
                $hasExchStop = ($null -ne $order.stop_price)
                $isManaged = $hasExchStop -or ($null -ne $order.take_profit_price)
                if (($posType -ne "FUTURES") -and (-not $isManaged)) {
                    if ($Verbose) { Write-Host "  [Sync Trailing] $market sem SL/TP na exchange — holding passivo SPOT, skip" -ForegroundColor DarkGray }
                    continue
                }

                # Direcao normalizada (buy->LONG, sell->SHORT).
                $newSide = if ($order.side -eq "buy") { "LONG" } else { "SHORT" }
                $entryPx = [double]$order.price

                # Stop protetivo DIRECIONAL quando a corretora nao tem stop:
                #  LONG  -> 5% ABAIXO da entrada; SHORT -> 5% ACIMA da entrada.
                # (o fallback antigo price*0.95 colocava o stop do lado ERRADO num short).
                $stopCalculated = $false
                if ($hasExchStop) {
                    $protStop = [double]$order.stop_price
                } else {
                    $protStop = if ($newSide -eq "SHORT") { [math]::Round($entryPx * 1.05, 8) } else { [math]::Round($entryPx * 0.95, 8) }
                    $stopCalculated = $true
                }
                # Target direcional: LONG acima, SHORT abaixo.
                $protTarget = if ($null -ne $order.take_profit_price) {
                    [double]$order.take_profit_price
                } elseif ($newSide -eq "SHORT") {
                    [math]::Round($entryPx * 0.85, 8)
                } else {
                    [math]::Round($entryPx * 1.15, 8)
                }

                # Posição nova na exchange - criar entrada
                $adoptNote = if ($stopCalculated) { "$market (FUTURES sem stop -> stop protetivo $protStop calculado)" } else { $market }
                Write-Host "  [Sync Trailing] Nova posição detectada: $adoptNote" -ForegroundColor Yellow
                # 2026-07-22 FIX: origin nunca era gravado neste caminho (so
                # gem_executor.ps1, entradas novas do bot, passava origin) --
                # lib_trailing_unified.ps1 (motor shadow) exige origin e
                # recusa "adivinhar", entao TODA posicao adotada via sync
                # (SPOT holdings OU FUTURES orfas, ambos passam por aqui via
                # CoinEx-GetOpenOrders) ficava fora da avaliacao shadow.
                # $posType ja calculado acima (linha ~583) a partir de
                # $order.position_type ("SPOT"|"FUTURES").
                $newPos = [PSCustomObject]@{
                    market = $market
                    side = $newSide
                    entry = $entryPx
                    stop = $protStop
                    target = $protTarget
                    orderId = $orderId
                    source = "exchange_sync"
                    mode = "STANDARD"
                    max_days = 0
                    dd_threshold_pct = 30
                    phase = 0
                    peak = $entryPx
                    stopCurrent = $protStop
                    active = $true
                    openedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    updatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    origin = @{ asset_class = $posType; trade_style = "SWING" }
                }
                $positions += $newPos
                $updated = $true

                # Notificar via Telegram (destaca quando um stop protetivo foi injetado).
                $msg = if ($stopCalculated) {
                    "⚠️ SYNC: $market ($newSide) adotada SEM stop na corretora — stop protetivo $protStop será empurrado"
                } else {
                    "✅ SYNC: Nova posição $market detectada na exchange"
                }
                if (Get-Command Send-TelegramAlertFiltered -ErrorAction SilentlyContinue) {
                    try { Send-TelegramAlertFiltered -Message $msg -Tier "IMPORTANT" | Out-Null } catch { }
                }
            }
        }

        # Persiste se houve mudanças
        if ($updated -and (Get-Command Save-TrailingPositions -ErrorAction SilentlyContinue)) {
            Save-TrailingPositions @($positions)
            Write-Host "  [Sync Trailing] Posições sincronizadas com sucesso." -ForegroundColor Green
        }

    } catch {
        Write-Warning "[Sync Trailing] Erro ao sincronizar: $_"
    }
}

# -------------------------------------------------------------------------
# Whale/Bacon Alert Handler - Receber alertas com tipo (compra/venda)
# -------------------------------------------------------------------------
function Send-WhaleAlert {
    <#
    .SYNOPSIS
    Envia alerta de whale/bacon com tipo de transação (compra/venda).
    
    .PARAMETER Market
    Par de trading (ex: BTCUSDT)
    
    .PARAMETER Amount
    Quantidade movida
    
    .PARAMETER Price
    Preço da transação
    
    .PARAMETER Type
    Tipo: "BUY" ou "SELL"
    
    .PARAMETER Source
    Fonte do alerta (ex: "whale_monitor", "bacon_detector")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Market,
        [Parameter(Mandatory=$true)][double]$Amount,
        [Parameter(Mandatory=$true)][double]$Price,
        [Parameter(Mandatory=$true)][ValidateSet("BUY","SELL")][string]$Type,
        [Parameter(Mandatory=$false)][string]$Source = "whale_monitor"
    )

    $emoji = if ($Type -eq "BUY") { "[WHALE BUY]" } else { "[WHALE SELL]" }
    $usdValue = [math]::Round($Amount * $Price, 2)
    
    $msg = "$emoji | $Market`nVolume: $Amount @ $Price`nValor: \$$usdValue`nFonte: $Source"
    
    # Whale/Bacon é CRÍTICO - sempre enviar
    if (Get-Command Send-TelegramAlertFiltered -ErrorAction SilentlyContinue) {
        try { Send-TelegramAlertFiltered -Message $msg -Tier "CRITICAL" | Out-Null } catch { }
    } elseif (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
        try { Send-TelegramAlert -Message $msg | Out-Null } catch { }
    }
}

# Exportadas: Sync-TrailingPositionsWithExchange, Send-WhaleAlert
