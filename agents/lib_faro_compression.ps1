# lib_faro_compression.ps1 — Volatility squeeze (pre-ignition detector)
#
# 2026-07-16: substitui o sinal "whale" (removido, sem fonte gratis viavel --
# ver lib_faro_v3_scoring.ps1). Bollinger bandwidth caindo = range comprimindo
# = energia acumulando antes de romper. Motivado por autopsia real: ZEC
# comprimiu a 0.15x vol, 6h depois igniu a 3.7x -- padrao nao detectado na
# epoca porque nenhum sinal do FARO olhava pra ANTES do volume explodir, so
# pra depois (volume_plus exige ratio>=2.0, ja em spike).
function Get-CompressionScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Closes,
        [int] $BandwidthLookback = 20,   # candles pra media historica de bandwidth
        [double] $SqueezeRatioMax = 0.5  # bandwidth atual <= 50% da media = squeeze
    )
    if (-not $Closes -or $Closes.Count -lt ($BandwidthLookback + 20)) { return 0 }
    if (-not (Get-Command Get-BollingerBands -ErrorAction SilentlyContinue)) { return 0 }

    # bandwidth atual (ultimos 20 closes) vs bandwidth media historica (janelas
    # anteriores) -- squeeze = comprimido em relacao ao proprio historico da
    # moeda, nao um numero absoluto (cada moeda tem volatilidade base diferente).
    $currentBb = Get-BollingerBands -Closes $Closes -Period 20
    if ($currentBb.bandwidth -le 0) { return 0 }

    $histBandwidths = @()
    $step = 5
    for ($i = $BandwidthLookback; $i -ge $step; $i -= $step) {
        $windowEnd = $Closes.Count - $i
        if ($windowEnd -lt 20) { continue }
        $window = $Closes[0..($windowEnd - 1)]
        if ($window.Count -lt 20) { continue }
        $bb = Get-BollingerBands -Closes $window -Period 20
        if ($bb.bandwidth -gt 0) { $histBandwidths += $bb.bandwidth }
    }
    if ($histBandwidths.Count -lt 2) { return 0 }

    $avgHistBandwidth = ($histBandwidths | Measure-Object -Average).Average
    if ($avgHistBandwidth -le 0) { return 0 }

    $squeezeRatio = $currentBb.bandwidth / $avgHistBandwidth
    if ($squeezeRatio -gt $SqueezeRatioMax) { return 0 }   # nao esta comprimido o suficiente

    # Quanto mais apertado (ratio menor), maior o score -- mais energia acumulada.
    $score = switch ($squeezeRatio) {
        { $_ -le 0.20 } { 20; break }
        { $_ -le 0.30 } { 15; break }
        { $_ -le 0.40 } { 10; break }
        default         { 5 }
    }
    return [Math]::Min($score, 20)
}
