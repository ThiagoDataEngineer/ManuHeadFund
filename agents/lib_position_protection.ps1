# lib_position_protection.ps1
# Garante que TODA posicao FUTURES tenha TP/SL REAIS na corretora (nao embutidos na ordem).
# Causa raiz corrigida (2026-05-29): CoinEx V2 nao aplica stop_loss/take_profit embutidos
# em ordem MARKET de forma confiavel (posicao ainda nao existe no submit). A solucao e
# colocar SL/TP via set-position-* APOS o fill, validar via pending-position, e retry.
#
# Dependencias (dot-source pelo caller):
#   lib_coinex.ps1                    (CoinEx-GetPendingPositions, CoinEx-Post)
#   lib_order_validation.ps1          (Test-PositionHasStopLoss, Set-PositionStopLossFallback, Set-PositionTakeProfitFallback)
#   lib_coinex_position_management.ps1 (CoinEx-ModifyPositionStopLoss)
#   lib_trailing_stop_intelligent.ps1  (Get-StructuralStopTarget, opcional -- fail-safe cai pro % fixo se ausente)

# ============================================================================
# Set-PositionProtection - Garante SL + TP reais na corretora (idempotente)
# ============================================================================

function Set-PositionProtection {
    <#
    .SYNOPSIS
        Garante que a posicao tenha Stop Loss e Take Profit configurados na CoinEx.
        Valida apos cada tentativa e faz retry/fallback. Alerta se falhar.

    .PARAMETER Market
        Par de trading (ex: INJUSDT)

    .PARAMETER StopLoss
        Preco do stop loss (0 = nao configurar)

    .PARAMETER TakeProfit
        Preco do take profit (0 = nao configurar)

    .PARAMETER MaxRetries
        Tentativas por lado (default 3)

    .PARAMETER AlertOnFailure
        Envia alerta Telegram se ficar sem protecao (default $true)

    .OUTPUTS
        PSCustomObject { success, market, sl_set, tp_set, sl_price, tp_price, reason }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]  [string] $Market,
        [Parameter(Mandatory=$false)] [double] $StopLoss = 0,
        [Parameter(Mandatory=$false)] [double] $TakeProfit = 0,
        [Parameter(Mandatory=$false)] [int]    $MaxRetries = 3,
        [Parameter(Mandatory=$false)] [bool]   $AlertOnFailure = $true
    )

    # Pre-condicao: a posicao precisa existir na corretora.
    $exists = $false
    try {
        $positions = CoinEx-GetPendingPositions -Market $Market
        $exists = ($positions -and @($positions).Count -gt 0 -and [double]@($positions)[0].avg_entry_price -gt 0)
    } catch {
        $exists = $false
    }

    if (-not $exists) {
        return [PSCustomObject]@{
            success = $false
            market  = $Market
            sl_set  = $false
            tp_set  = $false
            reason  = "position_not_found"
        }
    }

    $slSet = $false; $tpSet = $false
    $slPriceFinal = 0.0; $tpPriceFinal = 0.0

    # --- Stop Loss ---
    if ($StopLoss -gt 0) {
        if (Get-Command Set-PositionStopLossFallback -ErrorAction SilentlyContinue) {
            $slr = Set-PositionStopLossFallback -Market $Market -Price ([decimal]$StopLoss) -MaxRetries $MaxRetries
            $slSet = [bool]$slr.success
            if ($slSet) { $slPriceFinal = [double]$slr.stop_loss_price }
        } else {
            # Fallback minimo se lib_order_validation nao carregada
            $slSet = (CoinEx-SetStopLoss $Market $StopLoss)
            if ($slSet) { $slPriceFinal = $StopLoss }
        }
    }

    # --- Take Profit ---
    if ($TakeProfit -gt 0) {
        if (Get-Command Set-PositionTakeProfitFallback -ErrorAction SilentlyContinue) {
            $tpr = Set-PositionTakeProfitFallback -Market $Market -Price ([decimal]$TakeProfit) -MaxRetries $MaxRetries
            $tpSet = [bool]$tpr.success
            if ($tpSet) { $tpPriceFinal = [double]$tpr.take_profit_price }
        } else {
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            try {
                # 2026-07-22: 4 casas fixas zerava preco de tokens sub-centavo
                # (mesmo bug corrigido em Repair-PositionProtection). Usa a
                # precisao real do par quando disponivel.
                $tpRoundPrec = 4
                if (Get-Command Get-MarketPrecision -ErrorAction SilentlyContinue) {
                    try {
                        $tpPrec = Get-MarketPrecision -Market $Market -MarketType "futures"
                        if ($tpPrec -and $tpPrec.quote_ccy_precision -gt 0) { $tpRoundPrec = [int]$tpPrec.quote_ccy_precision }
                    } catch { }
                }
                $resp = CoinEx-Post "/v2/futures/set-position-take-profit" @{
                    market            = $Market
                    market_type       = "FUTURES"
                    take_profit_type  = "mark_price"
                    take_profit_price = ([math]::Round($TakeProfit,$tpRoundPrec)).ToString($inv)
                }
                $tpSet = ($resp.code -eq 0)
                if ($tpSet) { $tpPriceFinal = $TakeProfit }
            } catch { $tpSet = $false }
        }
    }

    # --- Validacao final via corretora (fonte da verdade) ---
    $finalCheck = $null
    if (Get-Command Test-PositionHasStopLoss -ErrorAction SilentlyContinue) {
        Start-Sleep -Milliseconds 500
        $finalCheck = Test-PositionHasStopLoss -Market $Market
        if ($finalCheck.success) {
            $slSet = [bool]$finalCheck.has_stop_loss
            $tpSet = [bool]$finalCheck.has_take_profit
            if ($slSet) { $slPriceFinal = [double]$finalCheck.stop_loss_price }
            if ($tpSet) { $tpPriceFinal = [double]$finalCheck.take_profit_price }
        }
    }

    $needSl = ($StopLoss -gt 0)
    $needTp = ($TakeProfit -gt 0)
    $ok = ((-not $needSl) -or $slSet) -and ((-not $needTp) -or $tpSet)

    if (-not $ok -and $AlertOnFailure -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
        $ts = (Get-Date).ToString("HH:mm dd/MM/yy")
        $missing = @()
        if ($needSl -and -not $slSet) { $missing += "STOP LOSS" }
        if ($needTp -and -not $tpSet) { $missing += "TAKE PROFIT" }
        $alertMsg = "*POSICAO SEM PROTECAO* -- $Market`nFALTANDO: $($missing -join ' + ')`nSL_alvo=$StopLoss TP_alvo=$TakeProfit`nACAO MANUAL NECESSARIA`n_$ts_"
        try { Send-TelegramAlert -Message $alertMsg | Out-Null } catch {}
    }

    return [PSCustomObject]@{
        success  = $ok
        market   = $Market
        sl_set   = $slSet
        tp_set   = $tpSet
        sl_price = $slPriceFinal
        tp_price = $tpPriceFinal
        reason   = if ($ok) { "protected" } else { "partial_or_failed" }
    }
}

# ============================================================================
# Test-AllPositionsProtected - Audita TODAS posicoes abertas por SL/TP ausente
# ============================================================================

function Test-AllPositionsProtected {
    <#
    .SYNOPSIS
        Varre todas as posicoes FUTURES abertas e reporta quais estao sem SL ou TP.

    .OUTPUTS
        Array de PSCustomObject { market, side, entry, has_sl, sl_price, has_tp, tp_price, protected, liq_price }
    #>
    [CmdletBinding()]
    param()

    $results = @()
    try {
        $positions = CoinEx-GetPendingPositions
    } catch {
        return @()
    }

    foreach ($pos in @($positions)) {
        if (-not $pos -or [double]$pos.avg_entry_price -le 0) { continue }
        $market   = [string]$pos.market
        $sl       = [double]$pos.stop_loss_price
        $tp       = [double]$pos.take_profit_price
        $hasSl    = ($sl -gt 0)
        $hasTp    = ($tp -gt 0)
        $liq      = if ($pos.PSObject.Properties['liq_price']) { [double]$pos.liq_price } else { 0 }

        $results += [PSCustomObject]@{
            market    = $market
            side      = [string]$pos.side
            entry     = [double]$pos.avg_entry_price
            has_sl    = $hasSl
            sl_price  = $sl
            has_tp    = $hasTp
            tp_price  = $tp
            liq_price = $liq
            protected = ($hasSl -and $hasTp)
        }
    }

    return $results
}

# ============================================================================
# Repair-PositionProtection - Conserta posicao especifica sem SL/TP
# ============================================================================

function Repair-PositionProtection {
    <#
    .SYNOPSIS
        Reaplica SL/TP em uma posicao aberta que esta sem protecao.
        Calcula SL/TP a partir do entry real se nao fornecidos.

    .PARAMETER Market
        Par (ex: INJUSDT)

    .PARAMETER StopLoss
        SL explicito (0 = calcular do entry)

    .PARAMETER TakeProfit
        TP explicito (0 = calcular do entry)

    .PARAMETER StopPct
        % de stop abaixo do entry para LONG (default 0.08 = 8% spot)

    .PARAMETER TargetPct
        % de alvo acima do entry para LONG (default 0.32 = 32% spot)

    .PARAMETER EnableTrailing
        Se $true, marca a posicao para trailing continuo (journal flag)

    .OUTPUTS
        PSCustomObject resultado do Set-PositionProtection + valores calculados
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]  [string] $Market,
        [Parameter(Mandatory=$false)] [double] $StopLoss = 0,
        [Parameter(Mandatory=$false)] [double] $TakeProfit = 0,
        [Parameter(Mandatory=$false)] [double] $StopPct = 0.08,
        [Parameter(Mandatory=$false)] [double] $TargetPct = 0.32,
        [Parameter(Mandatory=$false)] [bool]   $EnableTrailing = $true
    )

    $positions = CoinEx-GetPendingPositions -Market $Market
    if (-not $positions -or @($positions).Count -eq 0) {
        return [PSCustomObject]@{ success=$false; market=$Market; reason="position_not_found" }
    }
    $pos   = @($positions)[0]
    $entry = [double]$pos.avg_entry_price
    $side  = ([string]$pos.side).ToLower()

    if ($entry -le 0) {
        return [PSCustomObject]@{ success=$false; market=$Market; reason="invalid_entry" }
    }

    # 2026-07-09 AUDITOR TRAILING: calibracao per-asset do stop (TDD 7/7).
    # 0.08 fixo gerava falso-positivo ~70% (wick de microcap estoura stop).
    # Se caller nao passou StopPct explicito, calibra via ATR% com clamps [2%,12%].
    # Fail-safe: qualquer erro -> mantem 0.08 legado.
    if ($StopPct -eq 0.08 -and (Get-Command Get-PerAssetStopPct -ErrorAction SilentlyContinue)) {
        try {
            $candles = $null
            if (Get-Command CoinEx-GetFuturesCandles -ErrorAction SilentlyContinue) {
                $candles = CoinEx-GetFuturesCandles $Market "1h" 30
            } elseif (Get-Command CoinEx-GetCandles -ErrorAction SilentlyContinue) {
                $candles = CoinEx-GetCandles $Market "1h" 30
            }
            if ($candles) {
                $calib = Get-PerAssetStopPct -Candles @($candles)
                if ($calib.source -eq "atr") {
                    Write-Host "  [StopCalib] $Market ATR%=$($calib.atr_pct) -> stop_pct=$($calib.stop_pct) (era 0.08 fixo)" -ForegroundColor DarkCyan
                    $StopPct = [double]$calib.stop_pct
                }
            }
        } catch {
            Write-Host "  [StopCalib] $Market falhou ($_) -- mantendo 0.08 legado" -ForegroundColor Yellow
        }
    }

    # 2026-07-22 FIX: arredondamento fixo em 4 casas zerava SL/TP de tokens de
    # preco muito baixo (PEPE ~$0.0000045 -> Round(x,4) = 0). Set-PositionProtection
    # entao via StopLoss/TakeProfit=0, tratava como "nada a fazer" e reportava
    # success=true com posicao SEM protecao real -- silencioso, recorrente todo
    # ciclo do trailing monitor. Usa a precisao real do par (Get-MarketPrecision,
    # ja usado em outros pontos do sizing) em vez de "4" hardcoded.
    $roundPrec = 4
    if (Get-Command Get-MarketPrecision -ErrorAction SilentlyContinue) {
        try {
            $prec = Get-MarketPrecision -Market $Market -MarketType "futures"
            if ($prec -and $prec.quote_ccy_precision -gt 0) { $roundPrec = [int]$prec.quote_ccy_precision }
        } catch { }
    }

    # Calcular SL/TP se nao fornecidos (direcao-aware)
    #
    # 2026-07-30: SL/TP fixo em % do entry (StopPct/TargetPct=32%) nunca lia
    # suporte/resistencia real -- achado direto pelo owner olhando o grafico
    # do DOGEUSDT ("quase impossivel de acontecer o TP", "SL bem apertado").
    # Confirmado com dado real: TP a 32% ficava sempre FORA do range de 30
    # dias inteiro do par. Get-StructuralStopTarget (lib_trailing_stop_
    # intelligent.ps1) tenta achar o pivot de suporte/resistencia real mais
    # proximo primeiro (mesma logica ja validada no motor de trailing
    # unificado); só cai pro % fixo se nao houver candles ou pivot dentro de
    # um raio razoavel (25% -- fail-safe, nunca fica sem numero pra usar).
    if ($StopLoss -le 0 -or $TakeProfit -le 0) {
        $__structural = $null
        if (Get-Command Get-StructuralStopTarget -ErrorAction SilentlyContinue) {
            try {
                $__candles = $null
                if (Get-Command CoinEx-GetFuturesCandles -ErrorAction SilentlyContinue) {
                    $__candles = @(CoinEx-GetFuturesCandles $Market "4hour" 60)
                } elseif (Get-Command CoinEx-GetCandles -ErrorAction SilentlyContinue) {
                    $__candles = @(CoinEx-GetCandles $Market "4hour" 60)
                }
                if ($__candles) {
                    $__structural = Get-StructuralStopTarget -Side $side -Entry $entry -Candles $__candles -StopPct $StopPct -TargetPct $TargetPct
                }
            } catch { $__structural = $null }
        }

        if ($__structural) {
            if ($StopLoss   -le 0) { $StopLoss   = [math]::Round($__structural.stop_loss, $roundPrec) }
            if ($TakeProfit -le 0) { $TakeProfit = [math]::Round($__structural.take_profit, $roundPrec) }
            Write-Verbose "Repair-PositionProtection: $Market SL=$($__structural.sl_source) TP=$($__structural.tp_source)"
        } else {
            if ($side -eq "long") {
                if ($StopLoss   -le 0) { $StopLoss   = [math]::Round($entry * (1 - $StopPct), $roundPrec) }
                if ($TakeProfit -le 0) { $TakeProfit = [math]::Round($entry * (1 + $TargetPct), $roundPrec) }
            } else {
                if ($StopLoss   -le 0) { $StopLoss   = [math]::Round($entry * (1 + $StopPct), $roundPrec) }
                if ($TakeProfit -le 0) { $TakeProfit = [math]::Round($entry * (1 - $TargetPct), $roundPrec) }
            }
        }
    }

    $protect = Set-PositionProtection -Market $Market -StopLoss $StopLoss -TakeProfit $TakeProfit -MaxRetries 3

    # Marcar trailing no journal se solicitado
    if ($EnableTrailing -and $protect.success) {
        try {
            $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot -Parent) "journal" }
            $tpPath = Join-Path $journalDir "trailing_positions.json"
            if (Test-Path $tpPath) {
                $arr = Get-Content $tpPath -Raw | ConvertFrom-Json
                $found = $false
                foreach ($item in $arr) {
                    if ($item.market -eq $Market -and $item.active -eq $true) {
                        $item.stop         = $StopLoss
                        $item.stopCurrent  = $StopLoss
                        $item.target       = $TakeProfit
                        $item.trailing     = $true
                        $item.updatedAt    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        $found = $true
                    }
                }
                if ($found) { $arr | ConvertTo-Json -Depth 12 | Set-Content $tpPath -Encoding utf8 }
            }
        } catch {
            Write-Verbose "Repair-PositionProtection: falha ao atualizar journal trailing: $_"
        }
    }

    return [PSCustomObject]@{
        success        = $protect.success
        market         = $Market
        side           = $side
        entry          = $entry
        stop_loss      = $StopLoss
        take_profit    = $TakeProfit
        sl_set         = $protect.sl_set
        tp_set         = $protect.tp_set
        trailing_armed = ($EnableTrailing -and $protect.success)
        reason         = $protect.reason
    }
}

# ============================================================================
# Funcoes exportadas:
#   Set-PositionProtection
#   Test-AllPositionsProtected
#   Repair-PositionProtection
# ============================================================================
