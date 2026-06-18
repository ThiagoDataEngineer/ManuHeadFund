# lib_entry_conviction_ensemble.ps1 -- Ensemble de conviccao de entrada (0-100)
# Combina eixos ORTOGONAIS num score unico. Trendline vira 1 voto, nao veto.
# Pesos default; o calibrador (lib_feedback_calibrator) aprende os pesos com o tempo.
#
# Eixos suportados (todos opcionais; usa so os presentes):
#   structure  -> qualidade da trendline (Get-StructureScore)
#   btc_rs     -> forca relativa ao BTC  (Get-RsConvictionScore)
#   volume     -> dinheiro antes do preco
#   multitf    -> alinhamento multi-TF   (Get-MultiTimeframeConviction)
#   historical -> analogia com pre-pumps conhecidos
#
# 2026-06-17. ASCII-only (PS 5.1 safe). Sem Export-ModuleMember (dot-source).

function Get-ConvictionDefaultWeights {
    # 2026-06-17: pesos DIRECIONAIS. SHORT e LONG tem precursores diferentes:
    #   LONG  = trend-following (multitf/volume/btc_rs pesam mais)
    #   SHORT = mean-reversion de overextension (overextension/structure pesam mais)
    #           dumps comecam esticados pra cima, nao em downtrend confirmado.
    [CmdletBinding()]
    param([string] $Direction = "LONG")

    if ("$Direction".ToUpper() -eq "SHORT") {
        return @{
            overextension = 0.24
            funding       = 0.18   # longs lotados = squeeze down (top sinal pre-dump)
            structure     = 0.16
            btc_rs        = 0.13
            volume        = 0.13
            historical    = 0.08
            multitf       = 0.08
        }
    }
    # LONG (default)
    @{
        multitf       = 0.20
        btc_rs        = 0.20
        volume        = 0.16
        structure     = 0.14
        historical    = 0.12
        overextension = 0.10
        funding       = 0.08
    }
}

function Get-FundingConvictionScore {
    # Eixo Funding: crowding de posicoes via funding rate (por periodo, fracao).
    # Positivo alto = longs pagam = longs lotados = squeeze down (favorece SHORT).
    # Negativo = shorts lotados = squeeze up (favorece LONG). ~0 = neutro.
    [CmdletBinding()]
    param(
        $FundingRate,
        [string] $Direction = "SHORT",
        [double] $HighRef = 0.0005   # 0.05% por periodo = funding "alto"
    )

    if ($null -eq $FundingRate) { return 50 }
    $fr = [double]$FundingRate

    # Sinal favoravel: SHORT gosta de funding positivo; LONG de negativo
    $signed = if ("$Direction".ToUpper() -eq "SHORT") { $fr } else { -$fr }
    $norm = $signed / $HighRef
    if ($norm -gt 1.5)  { $norm = 1.5 }   # extremo = bonus extra
    if ($norm -lt -1.0) { $norm = -1.0 }

    $score = 50 + ($norm * 33)
    if ($score -gt 100) { $score = 100 }
    if ($score -lt 0)   { $score = 0 }
    [int][math]::Round($score, 0)
}

function Get-FundingRate {
    # I/O: busca funding rate da CoinEx (next se disponivel, senao latest). Fail-soft null.
    [CmdletBinding()]
    param([string] $Market)
    if (-not $global:COINEX_BASE_URL) { return $null }
    try {
        $r = Invoke-RestMethod -Uri "$($global:COINEX_BASE_URL)/v2/futures/funding-rate?market=$Market" -Method GET -TimeoutSec 8
        if ($r.code -eq 0 -and $r.data) {
            $d = $r.data[0]
            if ($d.PSObject.Properties['next_funding_rate'] -and $d.next_funding_rate) { return [double]$d.next_funding_rate }
            if ($d.PSObject.Properties['latest_funding_rate']) { return [double]$d.latest_funding_rate }
        }
    } catch {}
    return $null
}

function Get-OverextensionScore {
    # Eixo Overextension (reversao a media). Dumps comecam ESTICADOS pra cima
    # (overbought + longe da SMA); bounces comecam esticados pra baixo.
    # SHORT: esticado UP = alto. LONG: esticado DOWN = alto. Pure.
    [CmdletBinding()]
    param(
        [double[]] $Closes,
        [string]   $Direction = "SHORT",
        [int]      $SmaPeriod = 20
    )

    if ($null -eq $Closes -or $Closes.Count -lt ($SmaPeriod + 1)) { return 50 }

    $window = $Closes[-$SmaPeriod..-1]
    $sma = ($window | Measure-Object -Average).Average
    if ($sma -le 0) { return 50 }
    $cur = $Closes[-1]
    $devPct = ($cur - $sma) / $sma * 100   # +acima / -abaixo da media

    $rsi = if (Get-Command Get-RSI -ErrorAction SilentlyContinue) { Get-RSI -Closes $Closes -Period 14 } else { 50 }

    $isShort = ("$Direction".ToUpper() -eq "SHORT")
    $score = 50.0

    if ($isShort) {
        # quer esticado pra cima
        if ($devPct -gt 0) { $score += [math]::Min($devPct, 15) / 15 * 30 }
        if     ($rsi -ge 70) { $score += 20 }
        elseif ($rsi -ge 60) { $score += 10 }
    } else {
        # LONG quer esticado pra baixo
        if ($devPct -lt 0) { $score += [math]::Min(-$devPct, 15) / 15 * 30 }
        if     ($rsi -le 30) { $score += 20 }
        elseif ($rsi -le 40) { $score += 10 }
    }

    if ($score -gt 100) { $score = 100 }
    if ($score -lt 0)   { $score = 0 }
    [int][math]::Round($score, 0)
}

function Get-EntryConviction {
    [CmdletBinding()]
    param(
        [hashtable] $Axes,                # @{ btc_rs=87; multitf=100; ... } valores 0-100
        [hashtable] $Weights = $null,
        [string]    $Direction = "LONG",
        [double]    $Threshold = 55
    )

    if (-not $Axes -or $Axes.Count -eq 0) {
        return @{ conviction = 0.0; ready = $false; axes_used = @(); contributions = @{} }
    }

    if (-not $Weights) { $Weights = Get-ConvictionDefaultWeights -Direction $Direction }

    $totalW = 0.0
    $weighted = 0.0
    $contributions = @{}
    $axesUsed = @()

    foreach ($axis in $Axes.Keys) {
        $score = $Axes[$axis]
        if ($null -eq $score) { continue }

        # Peso do eixo (default 0.1 se eixo desconhecido, pra nao ignorar)
        $w = if ($Weights.ContainsKey($axis)) { [double]$Weights[$axis] } else { 0.1 }
        if ($w -le 0) { continue }

        $totalW += $w
        $contrib = $w * [double]$score
        $weighted += $contrib
        $contributions[$axis] = [math]::Round($contrib, 2)
        $axesUsed += $axis
    }

    if ($totalW -le 0) {
        return @{ conviction = 0.0; ready = $false; axes_used = @(); contributions = @{} }
    }

    $conviction = [math]::Round($weighted / $totalW, 1)

    @{
        conviction    = $conviction
        ready         = ($conviction -ge $Threshold)
        threshold     = $Threshold
        direction     = $Direction
        axes_used     = $axesUsed
        contributions = $contributions
    }
}

function Get-StructureScore {
    [CmdletBinding()]
    param(
        [int]  $Touches    = 0,
        [int]  $CandleSpan = 0,
        [bool] $Rejection  = $false
    )

    # Cada toque vale 25 (1=25, 2=50, 3=75). 1 toque NAO eh zero: eh um voto fraco.
    $score = $Touches * 25
    if ($CandleSpan -ge 6) { $score += 15 }
    if ($Rejection)        { $score += 10 }

    if ($score -gt 100) { $score = 100 }
    if ($score -lt 5)   { $score = 5 }   # piso minimo (sempre 1 voto, nunca veto absoluto)

    [int]$score
}

function Write-ConvictionObservation {
    [CmdletBinding()]
    param(
        [string]    $Market,
        [string]    $Direction,
        [double]    $Conviction,
        [hashtable] $Axes,
        [string]    $Path
    )

    $entry = [ordered]@{
        ts         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        date       = (Get-Date).ToString("yyyy-MM-dd")
        market     = $Market
        direction  = $Direction
        conviction = $Conviction
        axes       = $Axes
    }

    $json = $entry | ConvertTo-Json -Compress
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $Path -Value $json -Encoding UTF8
}

function Get-VolumeConvictionScore {
    # Eixo Volume: volume recente vs baseline. Spike = dinheiro entrando (move real).
    # Pre-pump classico: volume sobe ANTES do preco. Direction-neutro (interesse = move).
    [CmdletBinding()]
    param(
        [double[]] $Volumes,
        [int]      $RecentN = 3
    )

    if ($null -eq $Volumes -or $Volumes.Count -lt ($RecentN + 3)) { return 50 }

    $recent = $Volumes[-$RecentN..-1]
    $baseline = $Volumes[0..($Volumes.Count - $RecentN - 1)]
    $recentAvg = ($recent | Measure-Object -Average).Average
    $baseAvg   = ($baseline | Measure-Object -Average).Average
    if ($baseAvg -le 0) { return 50 }

    $ratio = $recentAvg / $baseAvg
    $score = 50 + (($ratio - 1) * 40)
    if ($ratio -ge 2) { $score += 10 }   # spike forte = bonus

    if ($score -gt 100) { $score = 100 }
    if ($score -lt 0)   { $score = 0 }
    [int][math]::Round($score, 0)
}

function Get-RangePositionScore {
    # Eixo Estrutura: posicao do preco no range recente.
    # LONG perto do suporte (fundo) = bom; SHORT perto da resistencia (topo) = bom.
    [CmdletBinding()]
    param(
        [double[]] $Highs,
        [double[]] $Lows,
        [double]   $CurrentPrice,
        [string]   $Direction = "LONG"
    )

    if ($null -eq $Highs -or $null -eq $Lows -or $Highs.Count -eq 0 -or $Lows.Count -eq 0) { return 50 }
    $hi = ($Highs | Measure-Object -Maximum).Maximum
    $lo = ($Lows  | Measure-Object -Minimum).Minimum
    $range = $hi - $lo
    if ($range -le 0) { return 50 }

    $pos = ($CurrentPrice - $lo) / $range   # 0 = suporte, 1 = resistencia
    if ($pos -lt 0) { $pos = 0 }
    if ($pos -gt 1) { $pos = 1 }

    $score = if ("$Direction".ToUpper() -eq "SHORT") { $pos * 100 } else { (1 - $pos) * 100 }
    [int][math]::Round($score, 0)
}

function Get-StructureFromCandles {
    # Eixo Estrutura (trendline/S-R real): conta toques no suporte (LONG) ou
    # resistencia (SHORT) e alimenta Get-StructureScore (toques+span+rejeicao).
    [CmdletBinding()]
    param(
        [double[]] $Highs,
        [double[]] $Lows,
        [double[]] $Closes,
        [string]   $Direction = "LONG",
        [double]   $TolerancePct = 0.012
    )

    if ($null -eq $Highs -or $null -eq $Lows -or $null -eq $Closes) { return 50 }
    $n = $Lows.Count
    if ($n -lt 5) { return 50 }

    $isShort = ("$Direction".ToUpper() -eq "SHORT")
    $touchIdx = @()
    $rejection = $false

    if ($isShort) {
        $level = ($Highs | Measure-Object -Maximum).Maximum
        $band  = $level * (1 - $TolerancePct)
        for ($i = 0; $i -lt $n; $i++) {
            if ($Highs[$i] -ge $band) {
                $touchIdx += $i
                if ($Highs[$i] -gt 0 -and (($Highs[$i] - $Closes[$i]) / $Highs[$i]) -gt 0.003) { $rejection = $true }
            }
        }
    } else {
        $level = ($Lows | Measure-Object -Minimum).Minimum
        $band  = $level * (1 + $TolerancePct)
        for ($i = 0; $i -lt $n; $i++) {
            if ($Lows[$i] -le $band) {
                $touchIdx += $i
                if ($Lows[$i] -gt 0 -and (($Closes[$i] - $Lows[$i]) / $Lows[$i]) -gt 0.003) { $rejection = $true }
            }
        }
    }

    $touches = $touchIdx.Count
    $span = if ($touches -ge 2) { $touchIdx[-1] - $touchIdx[0] } else { 0 }

    if (Get-Command Get-StructureScore -ErrorAction SilentlyContinue) {
        return Get-StructureScore -Touches $touches -CandleSpan $span -Rejection $rejection
    }
    # fallback simples
    [int][math]::Min(100, $touches * 25)
}

function Get-PrePumpFingerprintScore {
    # Eixo Historico: fingerprint de pre-pump (analogia com o que precede pumps).
    # Precursores: compressao de range + volume subindo + higher-lows (LONG) /
    # lower-highs (SHORT). Pure. Base 50; cada precursor adiciona.
    [CmdletBinding()]
    param(
        [double[]] $Highs,
        [double[]] $Lows,
        [double[]] $Closes,
        [double[]] $Volumes,
        [string]   $Direction = "LONG"
    )

    if ($null -eq $Highs -or $null -eq $Lows -or $null -eq $Closes -or $null -eq $Volumes) { return 50 }
    $n = $Closes.Count
    if ($n -lt 8 -or $Highs.Count -lt $n -or $Lows.Count -lt $n -or $Volumes.Count -lt $n) { return 50 }

    $half = [int][math]::Floor($n / 2)
    $isShort = ("$Direction".ToUpper() -eq "SHORT")

    # 1. Compressao de range (recent mais apertado que earlier = energia acumulando)
    $earlierRanges = @(); $recentRanges = @()
    for ($i = 0; $i -lt $half; $i++)      { $earlierRanges += ($Highs[$i] - $Lows[$i]) }
    for ($i = $half; $i -lt $n; $i++)     { $recentRanges  += ($Highs[$i] - $Lows[$i]) }
    $eR = ($earlierRanges | Measure-Object -Average).Average
    $rR = ($recentRanges  | Measure-Object -Average).Average
    $compBonus = 0.0
    if ($eR -gt 0 -and $rR -lt $eR) {
        $ratio = ($eR - $rR) / $eR
        $compBonus = [math]::Min(1.0, $ratio) * 20
    }

    # 2. Volume subindo (recent vs earlier)
    $eVol = (@($Volumes[0..($half-1)]) | Measure-Object -Average).Average
    $rVol = (@($Volumes[$half..($n-1)]) | Measure-Object -Average).Average
    $volBonus = 0.0
    if ($eVol -gt 0 -and $rVol -gt $eVol) {
        $volBonus = [math]::Min(1.0, (($rVol / $eVol) - 1)) * 20
    }

    # 3. Estrutura direcional (higher-lows LONG / lower-highs SHORT) no recent
    $structBonus = 0.0
    if ($isShort) {
        if ($Highs[$n-1] -lt $Highs[$half]) { $structBonus = 10 }
    } else {
        if ($Lows[$n-1] -gt $Lows[$half]) { $structBonus = 10 }
    }

    $score = 50 + $compBonus + $volBonus + $structBonus
    if ($score -gt 100) { $score = 100 }
    if ($score -lt 0)   { $score = 0 }
    [int][math]::Round($score, 0)
}

function Resolve-ConvictionOverride {
    # Decide se a conviccao do ensemble destrava um veto do Tori (SKIP/WAIT).
    # FAIL-SAFE: so com FlagOn; nunca overrida DataAbsent; ENTER nao se aplica.
    [CmdletBinding()]
    param(
        [string] $ToriSignal,
        [double] $Conviction,
        [bool]   $DataAbsent = $false,
        [bool]   $FlagOn = $false,
        [double] $Threshold = 75
    )

    $sig = "$ToriSignal".ToUpper()

    if ($sig -notin @("SKIP","WAIT")) {
        return @{ allow = $false; reason = "not_applicable (tori=$sig, sem veto)" }
    }
    if (-not $FlagOn) {
        return @{ allow = $false; reason = "conviction_gate_off" }
    }
    if ($DataAbsent) {
        return @{ allow = $false; reason = "data_absent (sem base p/ override)" }
    }
    if ($Conviction -ge $Threshold) {
        return @{ allow = $true; reason = "conviction_override: $Conviction >= $Threshold (tori $sig vencido)" }
    }
    return @{ allow = $false; reason = "conviction $Conviction < $Threshold (respeita veto Tori)" }
}

function Get-MarketConviction {
    # Orquestrador I/O: busca candles + BTC, computa eixos, retorna conviccao.
    # Reusa funcoes ja dot-sourced (Get-CoinExCandles, Get-TrendDirection,
    # Get-MultiTimeframeConviction, Get-BtcRelativeStrength). Fail-soft = null.
    [CmdletBinding()]
    param(
        [string] $Market,
        [string] $Direction = "LONG",
        [bool]   $IsFutures = $true
    )

    if (-not (Get-Command Get-CoinExCandles -ErrorAction SilentlyContinue)) { return $null }

    try {
        $c1H = Get-CoinExCandles -Market $Market -Period "1hour" -Limit 100 -IsFutures $IsFutures
        $c4H = Get-CoinExCandles -Market $Market -Period "4hour" -Limit 60  -IsFutures $IsFutures
        $c1D = Get-CoinExCandles -Market $Market -Period "1day"  -Limit 60  -IsFutures $IsFutures
        if (-not $c1H -or $c1H.Count -lt 20) { return $null }

        $axes = @{}
        if (Get-Command Get-MultiTimeframeConviction -ErrorAction SilentlyContinue) {
            $t1D = Get-TrendDirection -Candles $c1D -Timeframe "1D"
            $t4H = Get-TrendDirection -Candles $c4H -Timeframe "4H"
            $t1H = Get-TrendDirection -Candles $c1H -Timeframe "1H"
            $axes.multitf = Get-MultiTimeframeConviction -Trend1D $t1D -Trend4H $t4H -Trend1H $t1H -Direction $Direction
        }
        if (Get-Command Get-BtcRelativeStrength -ErrorAction SilentlyContinue) {
            $btc = Get-CoinExCandles -Market "BTCUSDT" -Period "1hour" -Limit 100 -IsFutures $true
            if ($btc -and $btc.Count -ge 2) {
                $alt = @($c1H | ForEach-Object { [double]$_.close })
                $btcCloses = @($btc | ForEach-Object { [double]$_.close })
                $rs = Get-BtcRelativeStrength -AltCloses $alt -BtcCloses $btcCloses -Beta 1.0
                if ($rs) { $axes.btc_rs = Get-RsConvictionScore -Rs $rs.rs -BtcReturn $rs.btc_return -Direction $Direction }
            }
        }
        # Eixo Volume (volume-antes-do-preco) -- usa volumes do 1H
        if (Get-Command Get-VolumeConvictionScore -ErrorAction SilentlyContinue) {
            $vols = @($c1H | ForEach-Object { [double]$_.volume })
            $axes.volume = Get-VolumeConvictionScore -Volumes $vols
        }
        # Eixo Overextension (reversao a media) -- KEY pro SHORT (esticado pra cima)
        if ((Get-Command Get-OverextensionScore -ErrorAction SilentlyContinue) -and $c1H.Count -ge 21) {
            $clz = @($c1H | ForEach-Object { [double]$_.close })
            $axes.overextension = Get-OverextensionScore -Closes $clz -Direction $Direction
        }
        # Eixo Funding (crowding) -- top sinal pre-dump em perpetuos
        if ($IsFutures -and (Get-Command Get-FundingRate -ErrorAction SilentlyContinue)) {
            $fr = Get-FundingRate -Market $Market
            if ($null -ne $fr) { $axes.funding = Get-FundingConvictionScore -FundingRate $fr -Direction $Direction }
        }
        # Eixo Estrutura (trendline/S-R real) -- usa highs/lows/closes do 4H
        if ((Get-Command Get-StructureFromCandles -ErrorAction SilentlyContinue) -and $c4H -and $c4H.Count -ge 5) {
            $h4 = @($c4H | ForEach-Object { [double]$_.high })
            $l4 = @($c4H | ForEach-Object { [double]$_.low })
            $cl4 = @($c4H | ForEach-Object { [double]$_.close })
            $axes.structure = Get-StructureFromCandles -Highs $h4 -Lows $l4 -Closes $cl4 -Direction $Direction
        }
        # Eixo Historico (fingerprint pre-pump) -- usa 4H (highs/lows/closes/volumes)
        if ((Get-Command Get-PrePumpFingerprintScore -ErrorAction SilentlyContinue) -and $c4H -and $c4H.Count -ge 8) {
            $h4 = @($c4H | ForEach-Object { [double]$_.high })
            $l4 = @($c4H | ForEach-Object { [double]$_.low })
            $cl4 = @($c4H | ForEach-Object { [double]$_.close })
            $v4 = @($c4H | ForEach-Object { [double]$_.volume })
            $axes.historical = Get-PrePumpFingerprintScore -Highs $h4 -Lows $l4 -Closes $cl4 -Volumes $v4 -Direction $Direction
        }

        if ($axes.Count -eq 0) { return $null }
        $conv = Get-EntryConviction -Axes $axes -Direction $Direction
        $conv.axes_detail = $axes
        return $conv
    } catch {
        return $null
    }
}

function Get-ConvictionStats {
    [CmdletBinding()]
    param(
        [string] $Path
    )

    if (-not (Test-Path $Path)) {
        return @{ count = 0; avg_conviction = 0.0; observations = @() }
    }

    $obs = @()
    Get-Content $Path | Where-Object { $_.Trim() } | ForEach-Object {
        $o = $_ | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($o) { $obs += $o }
    }

    if ($obs.Count -eq 0) {
        return @{ count = 0; avg_conviction = 0.0; observations = @() }
    }

    $avg = ($obs | Measure-Object conviction -Average).Average

    @{
        count          = $obs.Count
        avg_conviction = [math]::Round($avg, 1)
        observations   = $obs
    }
}
