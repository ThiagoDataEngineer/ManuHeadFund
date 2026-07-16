# lib_faro_v3_scoring.ps1 — 7-signal scoring (5/7 threshold)
#
# 2026-07-16: sinal "whale" removido do calculo -- pesquisa confirmou que nao
# existe fonte gratis viavel de whale-flow POR MOEDA (Etherscan/BscScan/Solscan
# exigem endereco de contrato por chain, nao ticker; Whale Alert/Nansen sao
# pagos). O engine alimentava esse sinal com Get-Random ha meses -- ruido puro
# contando como "confirmacao" no threshold 5/7, sem o operador saber. Melhor
# reconhecer a lacuna (6 sinais reais) do que fingir ter 7. Substituido por
# "compression" (squeeze de volatilidade via Bollinger bandwidth real,
# lib_auto_market_analysis.ps1 Get-BollingerBands) -- pega o momento ANTES do
# volume explodir, nao so depois (motivado por autopsia real: ZEC comprimiu a
# 0.15x vol, 6h depois igniu a 3.7x, nao detectado na epoca).
function Get-FaroConviction {
    # Mapeia FARO -> conviccao 0-100 para o trigger-bus. So ENTRA (5/7) e
    # URGENTE (6+/7) disparam; conviccao = score normalizado. WATCH/SKIP = 0.
    param([double] $Score, [string] $Decision)
    if ($Decision -ne "ENTRA" -and $Decision -ne "URGENTE") { return 0 }
    $s = [int][Math]::Round($Score)
    if ($s -lt 0)   { $s = 0 }
    if ($s -gt 100) { $s = 100 }
    return $s
}

function Get-FaroScoreV3 {
    param([decimal] $VolScore = 0, [decimal] $PatternScore = 0, [decimal] $SentimentScore = 0, [decimal] $CompressionScore = 0, [decimal] $MomentumScore = 0, [decimal] $FingerprintScore = 0, [decimal] $TimingScore = 0)
    $vol = $VolScore
    $pat = $PatternScore
    $sent = $SentimentScore
    $comp = $CompressionScore
    $mom = $MomentumScore
    $fp = $FingerprintScore
    $timing = $TimingScore
    $signalCount = 0
    if ($vol -gt 0) { $signalCount++ }
    if ($pat -gt 0) { $signalCount++ }
    if ($sent -gt 0) { $signalCount++ }
    if ($comp -gt 0) { $signalCount++ }
    if ($mom -gt 0) { $signalCount++ }
    if ($fp -gt 0) { $signalCount++ }
    if ($timing -gt 0) { $signalCount++ }
    $totalRaw = $vol + $pat + $sent + $comp + $mom + $fp + $timing
    $totalNormalized = if ($totalRaw -gt 0) { [int](($totalRaw / 165) * 100) } else { 0 }
    $totalNormalized = [Math]::Min($totalNormalized, 100)
    # 2026-07-09 EVOLUTION WIRE: signals_needed tunavel (registry 4-6; clamp local bound 2/2)
    $needed = 5
    if (Get-Command Get-EvolutionParams -ErrorAction SilentlyContinue) {
        try {
            $__evo = Get-EvolutionParams
            if ($__evo.faro_signals_needed) {
                $__n = [int]$__evo.faro_signals_needed
                if ($__n -ge 4 -and $__n -le 6) { $needed = $__n }
            }
        } catch {}
    }
    $decision = if ($signalCount -ge ($needed + 1)) { "URGENTE" }
        elseif ($signalCount -ge $needed) { "ENTRA" }
        elseif ($signalCount -eq ($needed - 1)) { "WATCH" }
        else { "SKIP" }
    $confidence = [decimal]($signalCount) / 7.0
    return [PSCustomObject]@{
        score = $totalNormalized
        decision = $decision
        signal_count = $signalCount
        signals_needed = $needed
        confidence = [decimal]::Round($confidence, 2)
        breakdown = @{
            volume = [int]$vol
            pattern = [int]$pat
            sentiment = [int]$sent
            compression = [int]$comp
            momentum = [int]$mom
            fingerprint = [int]$fp
            timing = [int]$timing
        }
    }
}
