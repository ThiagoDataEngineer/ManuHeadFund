# lib_trailing_stop_intelligent.ps1
# Trailing Stop Inteligente + TP/SL Automatico + Saidas Parciais
# 2026-05-29 (recriado apos truncamento acidental)

# ============================================================================
# Initialize-AutomaticTPSL - Inicializar TP/SL automatico com saidas parciais
# ============================================================================

function Initialize-AutomaticTPSL {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]  [double]$Entry,
        [Parameter(Mandatory=$true)]  [double]$CurrentPrice,
        [Parameter(Mandatory=$true)]  [double]$Peak24h,
        [Parameter(Mandatory=$true)]  [double]$Qty,
        [Parameter(Mandatory=$false)] [string]$Mode = "GEM",
        [Parameter(Mandatory=$false)] [double]$TrailingPercent = 14.5
    )

    $tpBase = $Entry * 1.32
    $slBase = $Entry * 0.673

    $trailingStop = $Peak24h * (1 - ($TrailingPercent / 100))
    $trailingStop = [math]::Max($trailingStop, $slBase)

    $level1Price = $Entry + (($tpBase - $Entry) * 0.15)
    $level2Price = $Entry + (($tpBase - $Entry) * 0.40)
    $level3Price = $tpBase

    $partialExits = @(
        [PSCustomObject]@{ Level=1; Price=[math]::Round($level1Price,4); Qty=[math]::Round($Qty*0.5,8);  Percent=50; Action="SELL_50_PERCENT";       Status="PENDING" },
        [PSCustomObject]@{ Level=2; Price=[math]::Round($level2Price,4); Qty=[math]::Round($Qty*0.25,8); Percent=25; Action="SELL_25_PERCENT";       Status="PENDING" },
        [PSCustomObject]@{ Level=3; Price=[math]::Round($level3Price,4); Qty=[math]::Round($Qty*0.25,8); Percent=25; Action="SELL_25_PERCENT_AT_TP"; Status="PENDING" }
    )

    return [PSCustomObject]@{
        TPBase          = [math]::Round($tpBase,4)
        SLBase          = [math]::Round($slBase,4)
        TrailingStop    = [math]::Round($trailingStop,4)
        TrailingPercent = $TrailingPercent
        PartialExits    = $partialExits
        Mode            = $Mode
        InitializedAt   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Entry           = [math]::Round($Entry,4)
        Peak24h         = [math]::Round($Peak24h,4)
        TotalQty        = [math]::Round($Qty,8)
    }
}

# ============================================================================
# Calculate-ATR - Average True Range
# ============================================================================

function Calculate-ATR {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [array]$Candles,
        [Parameter(Mandatory=$false)] [int]$Period = 14
    )

    if ($Candles.Count -lt $Period) { return 0 }

    $trueRanges = @()
    for ($i = 1; $i -lt $Candles.Count; $i++) {
        $high = [double]$Candles[$i].high
        $low = [double]$Candles[$i].low
        $prevClose = [double]$Candles[$i-1].close

        $tr1 = $high - $low
        $tr2 = [Math]::Abs($high - $prevClose)
        $tr3 = [Math]::Abs($low - $prevClose)

        $trueRanges += [Math]::Max($tr1, [Math]::Max($tr2, $tr3))
    }

    $recentTR = $trueRanges | Select-Object -Last $Period
    $atr = ($recentTR | Measure-Object -Average).Average
    return $atr
}

# ============================================================================
# Find-SupportLevels - Detectar suportes em candles
# ============================================================================

function Find-SupportLevels {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [array]$Candles,
        [Parameter(Mandatory=$false)] [int]$LookbackPeriod = 20,
        [Parameter(Mandatory=$false)] [double]$Tolerance = 0.005
    )

    if ($Candles.Count -lt $LookbackPeriod) { return @() }

    $recentCandles = $Candles | Select-Object -Last $LookbackPeriod
    $currentPrice = $Candles[-1].close

    $supports = @()
    for ($i = 1; $i -lt ($recentCandles.Count - 1); $i++) {
        $current = $recentCandles[$i]
        $prev = $recentCandles[$i - 1]
        $next = $recentCandles[$i + 1]
        if ($current.low -lt $prev.low -and $current.low -lt $next.low) {
            $supports += $current.low
        }
    }

    $groupedSupports = @()
    $supports = $supports | Sort-Object
    foreach ($support in $supports) {
        $found = $false
        for ($i = 0; $i -lt $groupedSupports.Count; $i++) {
            $diff = [Math]::Abs($support - $groupedSupports[$i]) / $groupedSupports[$i]
            if ($diff -le $Tolerance) {
                $groupedSupports[$i] = ($groupedSupports[$i] + $support) / 2
                $found = $true
                break
            }
        }
        if (-not $found) { $groupedSupports += $support }
    }

    return $groupedSupports | Where-Object { $_ -lt $currentPrice } | Sort-Object -Descending
}

# ============================================================================
# Get-StructuralStopTarget - SL/TP baseado em suporte/resistencia REAL
# ============================================================================

function Get-StructuralStopTarget {
    <#
    .SYNOPSIS
        Calcula SL e TP usando suporte/resistencia real (pivots de swing,
        Find-SupportLevels) em vez de percentual fixo do entry.

    .DESCRIPTION
        2026-07-30: achado real (owner olhando o grafico do DOGEUSDT) -- o
        auto-repair (Repair-PositionProtection) colocava TP sempre a 32% fixo
        do entry, sem nenhuma leitura de estrutura de mercado. Confirmado com
        dados reais (30d de candle, 4 posicoes abertas na hora): o TP ficava
        SEMPRE fora do range de 30 dias inteiro (~32% de distancia, quando o
        range real do periodo era de 10-15%) -- "quase impossivel de
        acontecer", exatamente como reportado.

        LONG: TP mira a resistencia mais proxima ACIMA do preco (espelha o
        preco pra reusar Find-SupportLevels, que só acha pivots ABAIXO).
        SL mira o suporte mais proximo ABAIXO. SHORT e o espelho disso.

        Fail-safe: se nao ha candles suficientes ou nenhum pivot e' achado
        dentro de um raio razoavel (StructuralMaxPct), cai pro percentual
        fixo (StopPct/TargetPct) -- MESMO comportamento de antes, garante
        que a posicao NUNCA fica sem numero pra usar.

    .PARAMETER Side
        "long" ou "short" (case-insensitive)

    .PARAMETER Entry
        Preco de entrada

    .PARAMETER Candles
        Array de candles (OHLCV) -- mesmo formato usado por Find-SupportLevels

    .PARAMETER StopPct
        Fallback fixo de SL (usado se nao achar pivot de suporte/resistencia)

    .PARAMETER TargetPct
        Fallback fixo de TP (usado se nao achar pivot de suporte/resistencia)

    .PARAMETER StructuralMaxPct
        Raio maximo (%) em que um pivot e considerado "proximo o suficiente"
        pra usar em vez do fallback fixo -- pivot fora desse raio geralmente
        significa dado insuficiente/ruido, nao estrutura real

    .PARAMETER MinTargetFractionOfMode
        2026-07-31 FIX: achado real (owner acompanhou OPUSDT MOMENTUM --
        modo desenhado pra alvo de 150% de distancia, GEM_TARGET_MOMENTUM --
        fechar via TP estrutural a so 1.65%, virando um scalp de 20min sem
        querer). Investigacao confirmou padrao real (3 de 4 eventos pos-fix
        do dia: XRPUSDT, OPUSDT, ETHUSDT todos na faixa de 1.4%-3%) --
        Get-StructuralStopTarget pegava sempre o pivot MAIS PROXIMO dentro
        do raio, sem nenhuma nocao do alvo original pretendido pelo modo do
        trade (MOMENTUM/DISCOVERY/SCALP/PUMP_RIDE, ja tinha TargetPct
        correto disponivel como parametro, so nunca usado como piso). Fix:
        pivot de TP so e aceito no lugar do fallback fixo se a distancia
        dele for >= (TargetPct * MinTargetFractionOfMode) -- caso contrario
        prefere um pivot mais distante dentro do mesmo raio (se houver) ou
        cai pro TargetPct fixo (nunca fecha o trade artificialmente cedo so
        pq havia uma resistencia proxima, quando o modo pedia mais folego).
        Default 0.5 = pivot precisa valer pelo menos metade do alvo original.
        SL nao e afetado (proteger cedo continua sendo sempre desejavel).

    .OUTPUTS
        PSCustomObject { stop_loss, take_profit, sl_source, tp_source }
        source = "structural" (achou pivot real) ou "fixed_pct" (fallback)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]  [string] $Side,
        [Parameter(Mandatory=$true)]  [double] $Entry,
        [Parameter(Mandatory=$false)] [array]  $Candles = @(),
        [Parameter(Mandatory=$false)] [double] $StopPct = 0.08,
        [Parameter(Mandatory=$false)] [double] $TargetPct = 0.32,
        [Parameter(Mandatory=$false)] [double] $StructuralMaxPct = 25.0,
        [Parameter(Mandatory=$false)] [double] $MinTargetFractionOfMode = 0.5
    )
    $minTpDistPct = ($TargetPct * 100.0) * $MinTargetFractionOfMode

    $isLong = ("$Side".ToLower() -eq "long")

    $fixedSl = if ($isLong) { $Entry * (1 - $StopPct) } else { $Entry * (1 + $StopPct) }
    $fixedTp = if ($isLong) { $Entry * (1 + $TargetPct) } else { $Entry * (1 - $TargetPct) }

    $result = [PSCustomObject]@{
        stop_loss   = $fixedSl
        take_profit = $fixedTp
        sl_source   = "fixed_pct"
        tp_source   = "fixed_pct"
    }

    if (@($Candles).Count -lt 20 -or -not (Get-Command Find-SupportLevels -ErrorAction SilentlyContinue)) {
        return $result
    }

    try {
        if ($isLong) {
            # Suporte real (abaixo do preco) pro SL -- pivot mais proximo do entry.
            $supports = @(Find-SupportLevels -Candles $Candles -LookbackPeriod 20)
            $nearestSupport = $supports | Where-Object { $_ -lt $Entry } | Select-Object -First 1
            if ($nearestSupport) {
                $distPct = (($Entry - $nearestSupport) / $Entry) * 100
                if ($distPct -gt 0 -and $distPct -le $StructuralMaxPct) {
                    $result.stop_loss = $nearestSupport
                    $result.sl_source = "structural"
                }
            }

            # Resistencia real (acima do preco) pro TP -- espelha o preco pra
            # reusar Find-SupportLevels (so acha pivots abaixo por design).
            # 2026-07-31: entre os pivots dentro do raio, prefere o mais
            # PROXIMO que ainda respeite o piso minimo (>= alvo original *
            # MinTargetFractionOfMode) -- nao aceita cegamente o 1o da lista,
            # que pode ser proximo demais e fechar o trade cedo demais em
            # relacao ao modo com que foi aberto (MOMENTUM/DISCOVERY etc).
            $mirror = @($Candles | ForEach-Object {
                [PSCustomObject]@{ open=$_.open; high=(2*$Entry - $_.low); low=(2*$Entry - $_.high); close=(2*$Entry - $_.close); volume=$_.volume }
            })
            $mirroredResistances = @(Find-SupportLevels -Candles $mirror -LookbackPeriod 20)
            $resistanceCandidates = @($mirroredResistances | ForEach-Object {
                $nearestResistance = 2 * $Entry - $_
                [PSCustomObject]@{ price = $nearestResistance; dist = (($nearestResistance - $Entry) / $Entry) * 100 }
            } | Where-Object { $_.dist -gt 0 -and $_.dist -le $StructuralMaxPct } | Sort-Object dist)
            $chosen = $resistanceCandidates | Where-Object { $_.dist -ge $minTpDistPct } | Select-Object -First 1
            if (-not $chosen -and $resistanceCandidates.Count -gt 0) {
                # Nenhum pivot bate o piso -- prefere o mais DISTANTE disponivel
                # (ainda estrutural, ainda melhor que % fixo arbitrario) em vez
                # do mais proximo, que fecharia cedo demais pro modo do trade.
                $chosen = $resistanceCandidates | Select-Object -Last 1
            }
            if ($chosen) {
                $result.take_profit = $chosen.price
                $result.tp_source = "structural"
            }
        } else {
            # SHORT: espelho exato do LONG (resistencia pro SL, suporte pro TP).
            $mirror = @($Candles | ForEach-Object {
                [PSCustomObject]@{ open=$_.open; high=(2*$Entry - $_.low); low=(2*$Entry - $_.high); close=(2*$Entry - $_.close); volume=$_.volume }
            })
            $mirroredResistances = @(Find-SupportLevels -Candles $mirror -LookbackPeriod 20)
            $mirroredNearest = $mirroredResistances | Select-Object -First 1
            if ($mirroredNearest) {
                $nearestResistance = 2 * $Entry - $mirroredNearest
                $distPct = (($nearestResistance - $Entry) / $Entry) * 100
                if ($distPct -gt 0 -and $distPct -le $StructuralMaxPct) {
                    $result.stop_loss = $nearestResistance
                    $result.sl_source = "structural"
                }
            }

            # 2026-07-31: mesmo piso minimo aplicado ao TP do SHORT (via
            # suporte real) -- ver comentario espelhado no bloco LONG acima.
            $supports = @(Find-SupportLevels -Candles $Candles -LookbackPeriod 20)
            $supportCandidates = @($supports | Where-Object { $_ -lt $Entry } | ForEach-Object {
                [PSCustomObject]@{ price = $_; dist = (($Entry - $_) / $Entry) * 100 }
            } | Where-Object { $_.dist -gt 0 -and $_.dist -le $StructuralMaxPct } | Sort-Object dist)
            $chosenTp = $supportCandidates | Where-Object { $_.dist -ge $minTpDistPct } | Select-Object -First 1
            if (-not $chosenTp -and $supportCandidates.Count -gt 0) {
                $chosenTp = $supportCandidates | Select-Object -Last 1
            }
            if ($chosenTp) {
                $result.take_profit = $chosenTp.price
                $result.tp_source = "structural"
            }
        }
    } catch {
        # Fail-safe: qualquer erro no calculo estrutural mantem o fallback fixo
        return [PSCustomObject]@{
            stop_loss   = $fixedSl
            take_profit = $fixedTp
            sl_source   = "fixed_pct"
            tp_source   = "fixed_pct"
        }
    }

    return $result
}

# ============================================================================
# Calculate-TrailingStopPrice - Calcular novo stop inteligente
# ============================================================================

function Calculate-TrailingStopPrice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [PSCustomObject]$Position,
        [Parameter(Mandatory=$true)] [array]$Candles,
        [Parameter(Mandatory=$true)] [double]$CurrentStopLoss,
        [Parameter(Mandatory=$false)] [double]$MinProfitPctToActivate = 3.0,
        [Parameter(Mandatory=$false)] [int]$MaxPriceAgeSeconds = 60
    )

    $entryPrice = [double]$Position.avg_entry_price
    $leverage = [int]$Position.leverage
    $side = $Position.side

    # --- Guarda de preco defasado (stale price) ---------------------------------
    # Decisao de mover stop NUNCA pode usar preco antigo (cache REST/WS, hold de
    # variavel pelo orquestrador). Fail-closed: se nao conseguimos confirmar que o
    # preco e recente, mantemos o stop atual e nao atualizamos.
    $fresh = CoinEx-GetTickerFresh -market $Position.market
    $currentPrice = [double]$fresh.ticker.last

    $freshCheck = $null
    if (Get-Command Test-PriceFresh -ErrorAction SilentlyContinue) {
        $freshCheck = Test-PriceFresh -FetchedAt $fresh.fetched_at -MaxAgeSeconds $MaxPriceAgeSeconds
    }
    $isStale = ($null -ne $freshCheck -and -not $freshCheck.is_fresh) -or ($fresh.is_fresh -eq $false)

    if ($isStale) {
        $ageStr = if ($freshCheck) { "$($freshCheck.age_seconds)s" } else { "unknown" }
        return [PSCustomObject]@{
            new_stop_price = $CurrentStopLoss
            reason = "Stale price (age=$ageStr > ${MaxPriceAgeSeconds}s) - stop nao movido (fail-closed)"
            should_update = $false
            stale = $true
            pnl_pct = $null
        }
    }

    $pnlPct = if ($side -eq "long") {
        (($currentPrice - $entryPrice) / $entryPrice) * 100
    } else {
        (($entryPrice - $currentPrice) / $entryPrice) * 100
    }

    if ($pnlPct -lt $MinProfitPctToActivate) {
        return [PSCustomObject]@{
            new_stop_price = $CurrentStopLoss
            reason = "Profit $([Math]::Round($pnlPct, 2))% below activation threshold ($MinProfitPctToActivate%)"
            should_update = $false
            stale = $false
            pnl_pct = $pnlPct
        }
    }

    $atr = Calculate-ATR -Candles $Candles -Period 14
    $atrPct = ($atr / $currentPrice) * 100
    $supports = Find-SupportLevels -Candles $Candles -LookbackPeriod 20

    $trailingPct = 0
    $reason = ""

    if ($leverage -ge 50) {
        $trailingPct = 1.5; $reason = "High leverage (${leverage}x)"
    } elseif ($leverage -ge 20) {
        $trailingPct = 2.5; $reason = "Medium-high leverage (${leverage}x)"
    } elseif ($leverage -ge 10) {
        $trailingPct = 3.5; $reason = "Medium leverage (${leverage}x)"
    } else {
        $trailingPct = 4.5; $reason = "Low leverage (${leverage}x)"
    }

    if ($atrPct -gt 3.0) {
        $trailingPct += 1.0
        $reason += ", high volatility (ATR $([Math]::Round($atrPct, 2))%)"
    } elseif ($atrPct -lt 1.0) {
        $trailingPct -= 0.5
        $reason += ", low volatility (ATR $([Math]::Round($atrPct, 2))%)"
    }

    $nearestSupport = $null
    if ($supports.Count -gt 0) {
        $nearestSupport = $supports[0]
        $distanceToSupport = (($currentPrice - $nearestSupport) / $currentPrice) * 100
        if ($distanceToSupport -lt 2.0) {
            $trailingPct = [Math]::Min($trailingPct, $distanceToSupport + 0.5)
            $reason += ", near support at `$$([Math]::Round($nearestSupport, 4))"
        }
    }

    $newStopPrice = if ($side -eq "long") {
        $currentPrice * (1 - ($trailingPct / 100))
    } else {
        $currentPrice * (1 + ($trailingPct / 100))
    }

    $shouldUpdate = $false
    if ($side -eq "long") {
        if ($newStopPrice -gt $CurrentStopLoss) { $shouldUpdate = $true }
        else { $newStopPrice = $CurrentStopLoss; $reason = "Stop not moved (would move down)" }
    } else {
        if ($newStopPrice -lt $CurrentStopLoss) { $shouldUpdate = $true }
        else { $newStopPrice = $CurrentStopLoss; $reason = "Stop not moved (would move up)" }
    }

    return [PSCustomObject]@{
        new_stop_price = [Math]::Round($newStopPrice, 4)
        trailing_pct = [Math]::Round($trailingPct, 2)
        reason = $reason
        should_update = $shouldUpdate
        stale = $false
        pnl_pct = [Math]::Round($pnlPct, 2)
        atr = [Math]::Round($atr, 8)
        atr_pct = [Math]::Round($atrPct, 2)
        nearest_support = if ($nearestSupport) { [Math]::Round($nearestSupport, 4) } else { $null }
    }
}

# ============================================================================
# Update-PositionTrailingStop - Atualizar stop de uma posicao
# ============================================================================

function Update-PositionTrailingStop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Market,
        [Parameter(Mandatory=$false)] [bool]$DryRun = $false
    )

    try {
        $positions = @(CoinEx-GetPendingPositions -Market $Market)
        if ($positions.Count -eq 0) {
            return [PSCustomObject]@{ success = $false; market = $Market; error = "Position not found" }
        }

        $position = $positions[0]
        $currentStopLoss = [double]$position.stop_loss_price
        if ($currentStopLoss -eq 0) {
            return [PSCustomObject]@{ success = $false; market = $Market; error = "No stop loss configured" }
        }

        $candles = @(CoinEx-GetFuturesCandles -market $Market -period "15min" -limit 50)
        if ($candles.Count -lt 20) {
            return [PSCustomObject]@{ success = $false; market = $Market; error = "Insufficient candle data" }
        }

        $calculation = Calculate-TrailingStopPrice -Position $position -Candles $candles -CurrentStopLoss $currentStopLoss

        if (-not $calculation.should_update) {
            return [PSCustomObject]@{
                success = $true; market = $Market; action = "no_update"
                reason = $calculation.reason; current_stop = $currentStopLoss; pnl_pct = $calculation.pnl_pct
            }
        }

        if (-not $DryRun) {
            $result = CoinEx-ModifyPositionStopLoss -Market $Market -Price $calculation.new_stop_price
            if (-not $result.success) {
                return [PSCustomObject]@{ success = $false; market = $Market; error = "API error: $($result.error_msg)" }
            }
        }

        return [PSCustomObject]@{
            success = $true; market = $Market
            action = if ($DryRun) { "simulated" } else { "updated" }
            old_stop = $currentStopLoss; new_stop = $calculation.new_stop_price
            trailing_pct = $calculation.trailing_pct; reason = $calculation.reason
            pnl_pct = $calculation.pnl_pct; atr_pct = $calculation.atr_pct
            nearest_support = $calculation.nearest_support
        }
    }
    catch {
        return [PSCustomObject]@{ success = $false; market = $Market; error = $_.Exception.Message }
    }
}

# ============================================================================
# Update-AllTrailingStops - Atualizar todas as posicoes
# ============================================================================

function Update-AllTrailingStops {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [bool]$DryRun = $false
    )

    try {
        $positions = @(CoinEx-GetPendingPositions)
        if ($positions.Count -eq 0) {
            return [PSCustomObject]@{ success = $true; message = "No open positions"; total_positions = 0; updated = 0; no_update = 0; errors = 0; results = @() }
        }

        $results = @()
        foreach ($pos in $positions) {
            $market = $pos.market
            Write-Verbose "Processing $market..."
            $result = Update-PositionTrailingStop -Market $market -DryRun $DryRun
            $results += $result
            Start-Sleep -Milliseconds 200
        }

        return [PSCustomObject]@{
            success = $true
            total_positions = $positions.Count
            updated = @($results | Where-Object { $_.action -eq "updated" }).Count
            simulated = @($results | Where-Object { $_.action -eq "simulated" }).Count
            no_update = @($results | Where-Object { $_.action -eq "no_update" }).Count
            errors = @($results | Where-Object { -not $_.success }).Count
            results = $results
        }
    }
    catch {
        return [PSCustomObject]@{ success = $false; error = $_.Exception.Message; results = @() }
    }
}

# ============================================================================
# Funcoes exportadas:
#   Initialize-AutomaticTPSL
#   Calculate-ATR
#   Find-SupportLevels
#   Calculate-TrailingStopPrice
#   Update-PositionTrailingStop
#   Update-AllTrailingStops
# ============================================================================
