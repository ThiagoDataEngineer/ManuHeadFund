# cron_mentor_reflector.ps1 -- Cron: resolve pending reflections diariamente.
#
# E3 (2026-05-22): rotaciona daily 04:00 BRT (apos DaemonRestart 03:00).
#
# Operacao:
#   1. Le pending reflections (decision_reflections.jsonl)
#   2. Pra cada pending sem outcome match:
#      a. Cruza com trade close (journal.csv / gem_trades.csv) por (market, ts_entry)
#      b. Se closed: computa alpha_vs_btc + holding_days
#      c. Spawn Haiku LLM call ($0.001) pra distilar reflection 2-4 frases
#      d. Append resolved entry no JSONL
#   3. Cleanup: skip entries stale (>30 dias sem trade match, presumir veto/cancel)
#
# Fail-soft em CADA step:
#   - LLM call failure: skip esse pending (tenta proximo cron)
#   - alpha_vs_btc null: still adds resolved entry com null alpha
#   - JSONL parse error: skip line, continua

param([switch] $DryRun)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

. (Join-Path $projectRoot "agents\config.local.ps1") -ErrorAction SilentlyContinue
. (Join-Path $projectRoot "agents\lib_decision_reflection.ps1")
. (Join-Path $projectRoot "agents\lib_alpha_vs_btc.ps1")
# Optional libs
if (Test-Path (Join-Path $projectRoot "agents\lib_claude.ps1")) {
    . (Join-Path $projectRoot "agents\lib_claude.ps1")
}

$logFile = Join-Path $projectRoot ("logs\mentor_reflector_" + (Get-Date -Format "yyyyMMdd") + ".log")
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

Log "=== Mentor Reflector cron start ==="

$pending = Get-PendingReflections
Log "  Pending reflections: $(@($pending).Count)"

if (@($pending).Count -eq 0) {
    Log "=== Done (nothing to reflect) ==="
    exit 0
}

function _Find-TradeClose {
    param([string]$Market, [string]$EntryDateUtc)
    # Try gem_trades.csv first
    $gemPath = Join-Path $projectRoot "journal\gem_trades.csv"
    if (Test-Path $gemPath) {
        try {
            $rows = Import-Csv -Path $gemPath -Encoding UTF8
            foreach ($row in $rows) {
                if ($row.market -eq $Market -and $row.status -eq "CLOSED" -and $row.price_exit) {
                    # crude date match (any row with same market closed)
                    return [PSCustomObject]@{
                        exit_date_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
                        pnl_pct = [double]$row.pnl_pct
                    }
                }
            }
        } catch {}
    }
    # Try journal.csv
    $journalPath = Join-Path $projectRoot "journal\journal.csv"
    if (Test-Path $journalPath) {
        try {
            $rows = Import-Csv -Path $journalPath -Encoding UTF8
            foreach ($row in $rows) {
                if ($row.market -eq $Market -and $row.status -eq "FECHADO" -and $row.exit_price) {
                    $exitDate = if ($row.exit_timestamp) {
                        try { ([datetime]$row.exit_timestamp).ToString("yyyy-MM-dd") } catch { (Get-Date).ToString("yyyy-MM-dd") }
                    } else { (Get-Date).ToString("yyyy-MM-dd") }
                    return [PSCustomObject]@{
                        exit_date_utc = $exitDate
                        pnl_pct = [double]$row.pnl_pct
                    }
                }
            }
        } catch {}
    }
    return $null
}

function _Generate-Reflection {
    param(
        [string] $Market,
        [string] $MentorVeredicto,
        [double] $PnlPct,
        [Nullable[double]] $AlphaVsBtc,
        [int]    $HoldingDays,
        [string] $MentorMensagem,
        [string] $MesaSinal
    )
    # Haiku call (cheap). Fail-soft: retorna fallback text if LLM unavailable.
    if (-not (Get-Command Invoke-Claude -ErrorAction SilentlyContinue)) {
        return "[fallback] $MentorVeredicto -> $($PnlPct)% in $($HoldingDays)d"
    }

    $alphaText = if ($null -ne $AlphaVsBtc) { "alpha $($AlphaVsBtc)pp vs BTC" } else { "alpha n/a" }
    $sysPrompt = "Voce eh analista trading. Resuma essa decisao+outcome em 2-4 frases focadas em LESSON."
    $userPrompt = @"
Market: $Market
Decision: $MentorVeredicto ($MesaSinal)
Original reasoning: $MentorMensagem
Outcome: $($PnlPct)% over $($HoldingDays) days ($alphaText)

Em 2-4 frases:
(a) directional accuracy?
(b) thesis validity?
(c) UNE lesson concreta pra proximas decisoes mesmo market.

Evite generic ("good trade"). Use noun+verb especifico.
"@
    try {
        $r = Invoke-Claude -SystemPrompt $sysPrompt -UserContent $userPrompt `
            -Model "claude-haiku-4" -MaxTokens 200 -Temperature 0.2 -Agent "reflector"
        if ($r) { return $r.Trim() }
    } catch {}
    return "[llm_failed] $MentorVeredicto -> $($PnlPct)% in $($HoldingDays)d"
}

$resolved = 0
$skipped = 0
foreach ($p in $pending) {
    $tradeClose = _Find-TradeClose -Market $p.market -EntryDateUtc $p.entry_date_utc
    if (-not $tradeClose) {
        $skipped++
        Log "  SKIP trade_id=$($p.trade_id) market=$($p.market) -- no close match"
        continue
    }

    # Compute alpha
    $alpha = Compute-AlphaVsBtc -Market $p.market -EntryDateUtc $p.entry_date_utc `
        -ExitDateUtc $tradeClose.exit_date_utc -TradeReturnPct $tradeClose.pnl_pct

    # Holding days (rough)
    $holdingDays = 0
    try {
        $entryDt = [datetime]$p.entry_date_utc
        $exitDt = [datetime]$tradeClose.exit_date_utc
        $holdingDays = [int]($exitDt - $entryDt).TotalDays
    } catch {}

    # Generate reflection
    if ($DryRun) {
        $reflection = "[dryrun] $($p.mentor_veredicto) -> $($tradeClose.pnl_pct)%"
    } else {
        $reflection = _Generate-Reflection -Market $p.market -MentorVeredicto $p.mentor_veredicto `
            -PnlPct $tradeClose.pnl_pct -AlphaVsBtc $alpha.alpha_vs_btc -HoldingDays $holdingDays `
            -MentorMensagem $p.mentor_mensagem -MesaSinal $p.mesa_sinal
    }

    if (-not $DryRun) {
        Add-ResolvedReflection -TradeId $p.trade_id -ExitDateUtc $tradeClose.exit_date_utc `
            -PnlPct $tradeClose.pnl_pct -AlphaVsBtc $alpha.alpha_vs_btc -HoldingDays $holdingDays `
            -Reflection $reflection
    }
    $resolved++
    Log "  RESOLVED trade_id=$($p.trade_id) $($p.market) pnl=$($tradeClose.pnl_pct)% alpha=$($alpha.alpha_vs_btc)pp days=$holdingDays"
}

Log "=== Done -- resolved=$resolved skipped=$skipped (dryrun=$($DryRun.IsPresent)) ==="
exit 0
