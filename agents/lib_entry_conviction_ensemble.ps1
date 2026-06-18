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
    @{
        structure  = 0.20
        btc_rs     = 0.25
        volume     = 0.20
        multitf    = 0.20
        historical = 0.15
    }
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

    if (-not $Weights) { $Weights = Get-ConvictionDefaultWeights }

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
