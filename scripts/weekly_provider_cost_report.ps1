# weekly_provider_cost_report.ps1 -- Domingo 23:00 BRT
#
# Agrega 7d de claude_usage.csv + decisions.csv:
#   - Total calls por provider/model
#   - Custo estimado (Sonnet $0.018/1K in $0.075/1K out, Haiku $0.00025/$0.00125, Groq free, Gemini free)
#   - Mentor decisions por provider
#   - Hallucination rate por provider (sanity: qual LLM ainda erra?)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$journalDir = Join-Path $projectRoot "journal"
Set-Location $projectRoot

. (Join-Path $projectRoot "agents\lib_telegram.ps1")

# Pricing por 1K tokens (Anthropic 2026 pricing)
$pricing = @{
    "claude-sonnet-4"  = @{ in = 0.018; out = 0.075 }
    "claude-haiku-4"   = @{ in = 0.00025; out = 0.00125 }
    "groq:*"             = @{ in = 0.0; out = 0.0 }     # free tier
    "gemini-2.0-flash"   = @{ in = 0.0; out = 0.0 }     # free tier
}

function Get-Pricing {
    param([string]$Model)
    foreach ($k in $pricing.Keys) {
        if ($Model -like $k) { return $pricing[$k] }
    }
    return @{ in = 0; out = 0 }
}

$cutoff = (Get-Date).AddDays(-7)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("=== WEEKLY PROVIDER REPORT $(Get-Date -Format 'yyyy-MM-dd') ===")
$lines.Add("Window: ultimos 7 dias")

# claude_usage.csv stats
$usagePath = Join-Path $journalDir "claude_usage.csv"
$totalCost = 0
$byModel = @{}
if (Test-Path $usagePath) {
    Import-Csv $usagePath -Encoding UTF8 | Where-Object {
        try { [datetime]::Parse($_.timestamp) -ge $cutoff } catch { $false }
    } | ForEach-Object {
        $model = if ($_.model) { $_.model } elseif ($_.provider) { $_.provider } else { "unknown" }
        $inTok = if ($_.input_tokens) { [int]$_.input_tokens } else { 0 }
        $outTok = if ($_.output_tokens) { [int]$_.output_tokens } else { 0 }
        if (-not $byModel.ContainsKey($model)) {
            $byModel[$model] = @{ calls = 0; in_tok = 0; out_tok = 0; cost = 0.0 }
        }
        $byModel[$model].calls++
        $byModel[$model].in_tok += $inTok
        $byModel[$model].out_tok += $outTok
        $p = Get-Pricing $model
        $cost = ($inTok/1000.0)*$p.in + ($outTok/1000.0)*$p.out
        $byModel[$model].cost += $cost
        $totalCost += $cost
    }
}

$lines.Add("")
$lines.Add("PROVIDER USAGE 7d:")
foreach ($k in ($byModel.Keys | Sort-Object)) {
    $m = $byModel[$k]
    $lines.Add(("  {0,-30} calls={1,4} tok_in={2,7} tok_out={3,6} cost=`${4:N3}" -f `
        $k, $m.calls, $m.in_tok, $m.out_tok, $m.cost))
}
$lines.Add(("  TOTAL_COST_7D: `${0:N3} (annual proj: `${1:N2})" -f $totalCost, ($totalCost*52)))

# decisions.csv: provider_used distribution + hallucination rate
$decPath = Join-Path $journalDir "decisions.csv"
if (Test-Path $decPath) {
    $rows = Import-Csv $decPath -Encoding UTF8 | Where-Object {
        try { [datetime]::Parse($_.timestamp) -ge $cutoff } catch { $false }
    }
    $byProv = @{}
    foreach ($r in $rows) {
        if (-not $r.mentor_decision) { continue }
        $p = $r.provider_used; if (-not $p) { $p = "none" }
        if (-not $byProv.ContainsKey($p)) {
            $byProv[$p] = @{ aprovar = 0; vetar = 0; halluc = 0 }
        }
        if ($r.mentor_decision -eq "APROVAR") { $byProv[$p].aprovar++ }
        elseif ($r.mentor_decision -eq "VETAR") { $byProv[$p].vetar++ }
        if ($r.reason -match "Mesa pulou|FQS indisponível") { $byProv[$p].halluc++ }
    }
    $lines.Add("")
    $lines.Add("MENTOR DECISIONS 7d por provider:")
    foreach ($p in ($byProv.Keys | Sort-Object)) {
        $b = $byProv[$p]
        $total = $b.aprovar + $b.vetar
        $hallucPct = if ($total -gt 0) { [math]::Round(100.0*$b.halluc/$total, 1) } else { 0 }
        $lines.Add(("  {0,-25} APROVAR={1,3} VETAR={2,3} | halluc={3} ({4}%)" -f $p, $b.aprovar, $b.vetar, $b.halluc, $hallucPct))
    }
}

$msg = $lines -join "`n"
Write-Host $msg
Send-TelegramAlert -Message $msg | Out-Null
