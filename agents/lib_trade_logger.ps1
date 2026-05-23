# lib_trade_logger.ps1 -- Structured TRADE log entries for orchestrator V6.
#
# Contrato:
#   Format-TradeLogEntry -Timestamp -Market -Decision -Regime -Direction
#                        [-Score|-ScannerScore -ScorePredicted]
#                        -Razao -Tier -ConsensusMesa
#     => string formato (v1.5, 2026-05-15):
#        [HH:mm:ss] [TRADE] {Market}: {Decision} regime={X} direction={Y}
#        scanner_score={S1} score_predicted={S2} tier={T} consensus={C} razao={R}
#     - Nulls/empty viram "-"
#     - Aspas duplas em razao escapadas com \"
#     - Pipes/newlines/CR em razao sao removidos
#     - Timestamp vazio => Get-Date no momento
#
#   Backward-compat: -Score (legacy) eh tratado como -ScorePredicted (o numero
#   exibido antes era sempre o LLM-gerado quando cascade abortava no Triagem).
#   Vide journal/diagnose_triagem_tier_d_2026_05_15.md EUREKA A.
#
#   Parse-TradeLogEntry -Line  => PSCustomObject (round-trip)
#     - Linhas nao-TRADE => $null
#     - Aceita formato v1.5 (scanner_score/score_predicted) E formato legacy (score=X)
#
# Sem dependencias externas. Pure functions. UTF-8 BOM.

function _Tl-StringOrDash {
    param($Value)
    if ($null -eq $Value) { return "-" }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return "-" }
    return $s
}

function _Tl-ScoreOrDash {
    param($Value)
    if ($null -eq $Value) { return "-" }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return "-" }
    # Numerico (int ou float): renderiza usando InvariantCulture para evitar virgula
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [byte]) {
        return ([string]$Value)
    }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
        $d = [double]$Value
        # Se inteiro implicito, mantem como inteiro (evita "82.0")
        if ($d -eq [math]::Floor($d)) {
            return ([string]([int64]$d))
        }
        return $d.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    # String que parece numero
    $s = [string]$Value
    $tmp = 0.0
    if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$tmp)) {
        if ($tmp -eq [math]::Floor($tmp)) {
            return ([string]([int64]$tmp))
        }
        return $tmp.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $s
}

function _Tl-CleanRazao {
    param($Value)
    if ($null -eq $Value) { return "-" }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return "-" }
    # Remove CR/LF e pipes (separadores estruturais)
    $s = $s -replace "`r", " "
    $s = $s -replace "`n", " "
    $s = $s -replace "\|", " "
    # Colapsa espacos multiplos
    $s = $s -replace "\s+", " "
    $s = $s.Trim()
    if ([string]::IsNullOrEmpty($s)) { return "-" }
    # Escapa aspas duplas
    $s = $s -replace '"', '\"'
    return $s
}

function _Tl-Timestamp {
    param($Value)
    if ($null -eq $Value -or ([string]::IsNullOrWhiteSpace([string]$Value))) {
        return (Get-Date -Format "HH:mm:ss")
    }
    return [string]$Value
}

function Format-TradeLogEntry {
    [CmdletBinding()]
    param(
        [Parameter()] $Timestamp,
        [Parameter(Mandatory=$true)] [string] $Market,
        [Parameter(Mandatory=$true)] [string] $Decision,
        [Parameter()] $Regime,
        [Parameter()] $Direction,
        [Parameter()] $Score,            # LEGACY (deprecated): tratado como ScorePredicted
        [Parameter()] $ScannerScore,     # NOVO (v1.5): score deterministico do Get-QuickTechScore
        [Parameter()] $ScorePredicted,   # NOVO (v1.5): score cosmetico Llama (triagem.score_predicted)
        [Parameter()] $Razao,
        [Parameter()] $Tier,
        [Parameter()] $ConsensusMesa
    )

    $ts   = _Tl-Timestamp $Timestamp
    $reg  = _Tl-StringOrDash $Regime
    $dir  = _Tl-StringOrDash $Direction
    $ti   = _Tl-StringOrDash $Tier
    $cn   = _Tl-StringOrDash $ConsensusMesa
    $rz   = _Tl-CleanRazao   $Razao

    # Backward-compat: se -Score (legacy) foi passado e -ScorePredicted nao,
    # mapeia para ScorePredicted (o numero legado SEMPRE era LLM-gerado quando
    # cascade abortava no Triagem -- vide diagnose 2026-05-15 EUREKA A).
    $sp = $ScorePredicted
    if ($PSBoundParameters.ContainsKey('Score') -and -not $PSBoundParameters.ContainsKey('ScorePredicted')) {
        $sp = $Score
    }

    $sc  = _Tl-ScoreOrDash $ScannerScore
    $spr = _Tl-ScoreOrDash $sp

    return ("[{0}] [TRADE] {1}: {2} regime={3} direction={4} scanner_score={5} score_predicted={6} tier={7} consensus={8} razao={9}" `
        -f $ts, $Market, $Decision, $reg, $dir, $sc, $spr, $ti, $cn, $rz)
}

# Regex de parsing -- v1.5 (scanner_score + score_predicted) com fallback legacy (score=X).
$script:TL_PARSE_RE_V15 = [regex]'^\[(?<ts>\d{2}:\d{2}:\d{2})\]\s+\[TRADE\]\s+(?<market>\S+):\s+(?<decision>\S+)\s+regime=(?<regime>\S+)\s+direction=(?<direction>\S+)\s+scanner_score=(?<scanner_score>\S+)\s+score_predicted=(?<score_predicted>\S+)\s+tier=(?<tier>\S+)\s+consensus=(?<consensus>\S+)\s+razao=(?<razao>.*)$'
$script:TL_PARSE_RE_LEGACY = [regex]'^\[(?<ts>\d{2}:\d{2}:\d{2})\]\s+\[TRADE\]\s+(?<market>\S+):\s+(?<decision>\S+)\s+regime=(?<regime>\S+)\s+direction=(?<direction>\S+)\s+score=(?<score>\S+)\s+tier=(?<tier>\S+)\s+consensus=(?<consensus>\S+)\s+razao=(?<razao>.*)$'

function Parse-TradeLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [AllowEmptyString()] [AllowNull()] [string] $Line
    )

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

    $m = $script:TL_PARSE_RE_V15.Match($Line)
    if ($m.Success) {
        $sp = $m.Groups['score_predicted'].Value
        return [PSCustomObject]@{
            Timestamp      = $m.Groups['ts'].Value
            Market         = $m.Groups['market'].Value
            Decision       = $m.Groups['decision'].Value
            Regime         = $m.Groups['regime'].Value
            Direction      = $m.Groups['direction'].Value
            ScannerScore   = $m.Groups['scanner_score'].Value
            ScorePredicted = $sp
            # Legacy alias para compat com consumidores que ainda olham .Score
            Score          = $sp
            Tier           = $m.Groups['tier'].Value
            ConsensusMesa  = $m.Groups['consensus'].Value
            Razao          = $m.Groups['razao'].Value
        }
    }

    $m = $script:TL_PARSE_RE_LEGACY.Match($Line)
    if ($m.Success) {
        $sc = $m.Groups['score'].Value
        return [PSCustomObject]@{
            Timestamp      = $m.Groups['ts'].Value
            Market         = $m.Groups['market'].Value
            Decision       = $m.Groups['decision'].Value
            Regime         = $m.Groups['regime'].Value
            Direction      = $m.Groups['direction'].Value
            ScannerScore   = "-"
            ScorePredicted = $sc
            Score          = $sc
            Tier           = $m.Groups['tier'].Value
            ConsensusMesa  = $m.Groups['consensus'].Value
            Razao          = $m.Groups['razao'].Value
        }
    }

    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
# Novas funcoes: Format-UniverseLogEntry, Format-GateQualityEntry, Format-HitRateEntry
# Adicionadas 2026-05-15 para lib_universe_sweep e lib_hit_rate

function Format-UniverseLogEntry {
    [CmdletBinding()]
    param(
        [Parameter()] [object] $Snapshot
    )

    if ($null -eq $Snapshot) {
        return "[UNIVERSE] pairs=? ts=?"
    }

    $pairs = if ($null -ne $Snapshot.total_pairs) { $Snapshot.total_pairs } else { "?" }
    $ts = if ($null -ne $Snapshot.snapshot_ts) {
        $Snapshot.snapshot_ts | Get-Date -Format "HH:mm:ss"
    } else {
        "?"
    }

    return "[UNIVERSE] pairs=$pairs ts=$ts"
}

function Format-GateQualityEntry {
    [CmdletBinding()]
    param(
        [Parameter()] [object] $GateStats
    )

    if ($null -eq $GateStats) {
        return "[GATE-QUALITY] -"
    }

    $mcap = if ($null -ne $GateStats.mcap_below_1m) { $GateStats.mcap_below_1m } else { "?" }
    $age = if ($null -ne $GateStats.age_below_7d) { $GateStats.age_below_7d } else { "?" }
    $vol = if ($null -ne $GateStats.vol_below_500k) { $GateStats.vol_below_500k } else { "?" }
    $spread = if ($null -ne $GateStats.spread_above_5pct) { $GateStats.spread_above_5pct } else { "?" }

    return "[GATE-QUALITY] mcap<`$1M:$mcap idade<7d:$age vol<`$500k:$vol spread>5%:$spread"
}

function Format-HitRateEntry {
    [CmdletBinding()]
    param(
        [Parameter()] [object] $Comparison
    )

    if ($null -eq $Comparison) {
        return "[HIT-RATE ?] -"
    }

    $direction = if ($null -ne $Comparison.direction) { $Comparison.direction } else { "?" }
    $caught = if ($null -ne $Comparison.caught_by_scanner) { $Comparison.caught_by_scanner } else { "?" }
    $total = if ($null -ne $Comparison.total_movers) { $Comparison.total_movers } else { "?" }

    $base = "[HIT-RATE $direction] $caught/$total caught"

    if ($null -ne $Comparison.missed -and $Comparison.missed.Count -gt 0) {
        $missed_str = [string]::Join(" ", $Comparison.missed)
        $base += " | missed: $missed_str"
    }

    return $base
}
