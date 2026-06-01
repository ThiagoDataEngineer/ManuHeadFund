# position_sizer.ps1 - Calculo de tamanho de posicao com regra dos 1%
# Baseado em: Tudor Jones (1% rule), Kelly Criterion, ATR-based sizing
# Dot-source: . (Join-Path $PSScriptRoot "position_sizer.ps1")

. (Join-Path $PSScriptRoot "config.ps1")

# R:R efetivo descontando round-trip de taxas (maker+taker do round trip)
# Sem FeeContext usa fallback 0.08% round-trip (0.03% maker + 0.05% taker — confirmado API live)
function Get-EffectiveRR {
    param([double]$Entry, [double]$Stop, [double]$Target, $FeeContext = $null)
    $roundTrip     = if ($FeeContext) { $FeeContext.roundTrip / 100 } else { $COINEX_FEE_ROUNDTRIP_FALLBACK }
    $feeCost       = $Entry * $roundTrip
    $effectiveLoss = [math]::Abs($Entry - $Stop)   + $feeCost
    $effectiveProf = [math]::Abs($Target - $Entry) - $feeCost
    if ($effectiveLoss -le 0) { return 0 }
    return [math]::Round($effectiveProf / $effectiveLoss, 2)
}

# Calcula tamanho da posicao baseado em risco fixo (1% do capital)
function Get-PositionSize {
    param(
        [double]$CapitalTotal,          # Capital disponivel em USD
        [double]$EntryPrice,            # Preco de entrada
        [double]$StopLoss,              # Preco do stop loss
        [double]$RiscoMaxPct    = $RISCO_MAXIMO_PCT,
        [double]$AlavancagemMax = $ALAVANCAGEM_MAX,
        [string]$Market        = ""
    )

    if ($EntryPrice -le 0) { throw "EntryPrice deve ser maior que 0" }
    if ($StopLoss  -le 0) { throw "StopLoss deve ser maior que 0" }
    if ($EntryPrice -eq $StopLoss) { throw "EntryPrice e StopLoss nao podem ser iguais" }

    # 2026-05-19 PM: Kelly-aware sizing opt-in via $global:USE_KELLY_SIZING.
    # Default OFF = legacy CapitalTotal * RiscoMaxPct.
    # Flag ON + Get-ExecutorSize disponivel: substitui riscoUSD pelo Kelly resolvido.
    $riscoUSD = $CapitalTotal * $RiscoMaxPct
    if ($global:USE_KELLY_SIZING -eq $true -and (Get-Command Get-ExecutorSize -ErrorAction SilentlyContinue)) {
        try {
            $modeForKelly = if ($Market -match "GEM") { "GEM" } else { "TIER_A" }
            $szKelly = Get-ExecutorSize -Market $Market -Mode $modeForKelly -Capital $CapitalTotal -BasePct $RiscoMaxPct
            if ($szKelly.size_usd -gt 0 -and $szKelly.method -eq "kelly_adaptive") {
                $riscoUSD = [double]$szKelly.size_usd
            }
        } catch {}
    }
    $stopDistance   = [math]::Abs($EntryPrice - $StopLoss)
    $stopPct        = $stopDistance / $EntryPrice

    # Tamanho baseado no risco: unidades = risco$ / distancia_stop$
    $qtd            = $riscoUSD / $stopDistance
    $valorPosicao   = $qtd * $EntryPrice

    # Verificar se ultrapassa alavancagem maxima
    $alavancagem    = $valorPosicao / $CapitalTotal
    if ($alavancagem -gt $AlavancagemMax) {
        $qtd            = ($CapitalTotal * $AlavancagemMax) / $EntryPrice
        $valorPosicao   = $qtd * $EntryPrice
        $alavancagem    = $AlavancagemMax
        $riscoReal      = $qtd * $stopDistance
    } else {
        $riscoReal = $riscoUSD
    }

    return [PSCustomObject]@{
        market          = $Market
        capitalTotal    = $CapitalTotal
        entryPrice      = $EntryPrice
        stopLoss        = $StopLoss
        stopDistanceUSD = [math]::Round($stopDistance, 4)
        stopPct         = [math]::Round($stopPct * 100, 2)
        riscoMaxUSD     = [math]::Round($riscoUSD, 2)
        riscoRealUSD    = [math]::Round($riscoReal, 2)
        quantidadeUnits = [math]::Round($qtd, 6)
        valorPosicaoUSD = [math]::Round($valorPosicao, 2)
        alavancagem     = [math]::Round($alavancagem, 2)
        aprovado        = $true
        motivo          = "OK"
    }
}

# Valida o setup completo e bloqueia se criterios nao forem atendidos
function Test-TradeSetup {
    param(
        [double]$CapitalTotal,
        [double]$EntryPrice,
        [double]$StopLoss,
        [double]$Alvo1,
        [double]$ScorePonderado,    # Score dos agentes 0-100
        [string]$Sinal,             # "LONG" ou "SHORT"
        [double]$RRMinimo       = $RR_MINIMO,
        [double]$ScoreMinimo    = $SCORE_MINIMO,
        [double]$RiscoMaxPct    = $RISCO_MAXIMO_PCT,
        [double]$AlavancagemMax = $ALAVANCAGEM_MAX,
        [string]$Market = "",
        $FeeContext = $null     # PSCustomObject de CoinEx-GetFeeContext
    )

    $bloqueios = @()

    # 1. Score minimo
    if ($ScorePonderado -lt $ScoreMinimo) {
        $bloqueios += "Score ponderado $ScorePonderado < minimo $ScoreMinimo"
    }

    # 2. Stop definido
    if ($StopLoss -le 0) {
        $bloqueios += "Stop loss nao definido (Tudor Jones: sem stop = sem trade)"
    }

    # 3. Alvo definido
    if ($Alvo1 -le 0) {
        $bloqueios += "Alvo nao definido"
    }

    # 4. Calcula R:R efetivo (com taxas) se tiver dados suficientes
    $rr = 0; $rrEfetivo = 0
    if ($StopLoss -gt 0 -and $Alvo1 -gt 0 -and $EntryPrice -gt 0) {
        $stopDist   = [math]::Abs($EntryPrice - $StopLoss)
        $targetDist = [math]::Abs($Alvo1 - $EntryPrice)
        if ($stopDist -gt 0) { $rr = [math]::Round($targetDist / $stopDist, 2) }
        $rrEfetivo = Get-EffectiveRR -Entry $EntryPrice -Stop $StopLoss -Target $Alvo1 -FeeContext $FeeContext

        if ($rrEfetivo -lt $RRMinimo) {
            $roundTripPct = if ($FeeContext) { $FeeContext.roundTrip } else { $COINEX_FEE_ROUNDTRIP_FALLBACK * 100 }
            $bloqueios += "R:R efetivo $rrEfetivo (bruto=$rr, fees=$($roundTripPct)%) < minimo $RRMinimo"
        }
    }

    # 5. Stop do lado errado
    if ($Sinal -eq "LONG" -and $StopLoss -ge $EntryPrice) {
        $bloqueios += "Stop ACIMA do preco de entrada para LONG - impossivel"
    }
    if ($Sinal -eq "SHORT" -and $StopLoss -le $EntryPrice) {
        $bloqueios += "Stop ABAIXO do preco de entrada para SHORT - impossivel"
    }

    # 6. Calcula tamanho se nao ha bloqueios criticos
    $sizing = $null
    if ($bloqueios.Count -eq 0 -or ($bloqueios | Where-Object { $_ -match "Score|R:R" })) {
        try {
            $sizing = Get-PositionSize `
                -CapitalTotal $CapitalTotal `
                -EntryPrice $EntryPrice `
                -StopLoss $StopLoss `
                -RiscoMaxPct $RiscoMaxPct `
                -AlavancagemMax $AlavancagemMax `
                -Market $Market
        } catch {
            $bloqueios += "Erro no calculo de posicao: $_"
        }
    }

    $aprovado = $bloqueios.Count -eq 0

    return [PSCustomObject]@{
        aprovado        = $aprovado
        bloqueios       = $bloqueios
        rr              = $rr
        rrEfetivo       = $rrEfetivo
        feeContext      = $FeeContext
        sizing          = $sizing
        mensagem        = if ($aprovado) { "SETUP APROVADO - pode executar" } else { "SETUP BLOQUEADO: $($bloqueios -join ' | ')" }
    }
}

# Exibe resumo formatado do sizing
function Show-TradePlan {
    param([object]$Validation)

    $cor = if ($Validation.aprovado) { "Green" } else { "Red" }

    Write-Host ""
    Write-Host "===== PLANO DE TRADE =====" -ForegroundColor Cyan
    Write-Host "Status: $($Validation.mensagem)" -ForegroundColor $cor

    if ($Validation.bloqueios.Count -gt 0) {
        Write-Host "Bloqueios:" -ForegroundColor Red
        $Validation.bloqueios | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    }

    if ($Validation.sizing) {
        $s = $Validation.sizing
        Write-Host ""
        Write-Host "Sizing (regra 1%):" -ForegroundColor Yellow
        Write-Host "  Capital:     $($s.capitalTotal) USD"
        Write-Host "  Risco max:   $($s.riscoMaxUSD) USD ($($s.stopPct)% do preco)"
        Write-Host "  Entrada:     $($s.entryPrice)"
        Write-Host "  Stop:        $($s.stopLoss) (dist: $($s.stopDistanceUSD))"
        Write-Host "  Quantidade:  $($s.quantidadeUnits) unidades"
        Write-Host "  Valor pos:   $($s.valorPosicaoUSD) USD"
        Write-Host "  Alavancagem: $($s.alavancagem)x"
        Write-Host "  R:R bruto:   1:$($Validation.rr)"
        $fc = $Validation.feeContext
        if ($fc) {
            Write-Host "  R:R efetivo: 1:$($Validation.rrEfetivo) (fees: $($fc.roundTrip)% round-trip | funding24h: $($fc.funding24h)%)" -ForegroundColor $(if($Validation.rrEfetivo -ge 2){"Green"}else{"Yellow"})
            Write-Host "  HoldCost24h: $($fc.holdCost24h)% do valor" -ForegroundColor DarkGray
        } else {
            Write-Host "  R:R efetivo: 1:$($Validation.rrEfetivo) (fallback 0.08% fees)" -ForegroundColor Yellow
        }
    }
    Write-Host "=========================" -ForegroundColor Cyan
    Write-Host ""
}
