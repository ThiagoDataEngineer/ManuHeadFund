# replay_decisions_analyzer.ps1 -- Analise offline de decisoes passadas
#
# Re-roda Build-MentorFullContext sobre decisoes historicas + classifica:
#   - "improved": decisao foi hallucination, prompt atual ja resolveria
#   - "consistent": razao continua valida com prompt atual
#   - "needs_attention": ambigu (Mentor cita FQS=indisponivel mas registry tem entry)
#
# ZERO custo LLM -- so prompt construction + pattern matching.
# Roda manual ou agendado pos-cron pra audit retrospectivo.

param(
    [int]$LastN = 50,
    [switch]$Verbose,
    [switch]$JsonOutput
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$journalDir = Join-Path $projectRoot "journal"
Set-Location $projectRoot

. (Join-Path (Join-Path $projectRoot "agents") "lib_fundamental_quality.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "mentor_agent.ps1")

$decPath = Join-Path $journalDir "decisions.csv"
if (-not (Test-Path $decPath)) { Write-Host "decisions.csv ausente" -ForegroundColor Red; exit 1 }

# 2026-05-21 sessao manha: cross-reference com mentor_hallucinations.jsonl pra excluir
# decisoes flagadas em tempo real do merit count (era backlog post Mentor hallucination audit).
$hallucPath = Join-Path $journalDir "mentor_hallucinations.jsonl"
$hallucSet = @{}  # key = "$market|$dateUTC" (1-day granularity)
if (Test-Path $hallucPath) {
    Get-Content $hallucPath -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        try {
            $h = $line | ConvertFrom-Json -ErrorAction Stop
            if ($h.market -and $h.ts) {
                $dateUtc = $h.ts.Substring(0, 10)  # YYYY-MM-DD
                $key = "$($h.market)|$dateUtc"
                $hallucSet[$key] = $true
            }
        } catch {}
    }
}

$rows = Import-Csv $decPath -Encoding UTF8 |
        Where-Object { $_.mentor_decision } |
        Sort-Object timestamp -Descending |
        Select-Object -First $LastN

$analyzed = @()
foreach ($r in $rows) {
    $reason = $r.reason
    $market = $r.market

    # Re-monta FullContext atual
    try {
        $ctx = Build-MentorFullContext -Market $market -Mode "TIER_B_PAPER"
    } catch { $ctx = $null }

    $classification = "consistent"
    $delta_notes = @()

    # Cross-reference real-time hallucination detector (logs em mentor_hallucinations.jsonl).
    # Decisoes flagadas como hallucination em prod nao contam como merit (sao bug do LLM).
    if ($r.timestamp) {
        try {
            $rowDate = ([DateTime]::Parse($r.timestamp)).ToUniversalTime().ToString("yyyy-MM-dd")
            $key = "$market|$rowDate"
            if ($hallucSet.ContainsKey($key)) {
                $classification = "hallucination_detected"
                $delta_notes += "Real-time detector flagged mentor_hallucinations.jsonl entry mesma data+market. Excluido do merit count."
            }
        } catch {}
    }

    # Detector tipo A: "Mesa pulou" hallucination (resolvido)
    if ($reason -match "Mesa pulou") {
        $classification = "improved"
        $delta_notes += "Era hallucination tipo A (Mesa pulou). Prompt atual usa NAO_APLICAVEL."
    }

    # Detector tipo E (PM6): "Conflito CRITICO DE MODO" (bug arquitetural â€” mode mapping cego)
    if ($reason -match "CONFLITO.*MODO|conflito.*modo|mutuamente exclusivos") {
        $classification = "improved"
        $delta_notes += "Era bug arquitetural PM6 (mode mapping cego). Fix: 4 modes ortogonais incl TIER_A_PAPER."
    }

    # Detector fail-safe (infra issue, nao decisao)
    if ($reason -match "Mentor indisponivel") {
        $classification = "infra_issue"
        $delta_notes += "Fail-safe por cascade total fail. Nao conta como decisao de merito."
    }

    # Detector tipo B: KNOWLEDGE empty
    if ($reason -match "caixa preta|sem knowledge|ausÃªncia de knowledge") {
        $classification = "improved"
        $delta_notes += "Era hallucination tipo B (knowledge empty). Prompt atual skip header se vazio."
    }

    # Detector tipo C: [ALERTA] trigger
    if ($reason -match "ALERTA") {
        $classification = "improved"
        $delta_notes += "Era hallucination tipo C ([ALERTA] trigger). Substituido por linguagem neutra."
    }

    # Detector tipo D: FQS nÃ£o declarado quando registry tem
    if ($reason -match "FQS nÃ£o declarado|FQS indisponÃ­vel") {
        if ($ctx -and $ctx.fqs -and $null -ne $ctx.fqs.score) {
            $classification = "needs_attention"
            $delta_notes += "Mentor disse FQS missing mas registry TEM entry (fqs=$($ctx.fqs.score)/$($ctx.fqs.category)). Prompt PM3 deve resolver via uppercase FQS=."
        } elseif ($ctx -and $ctx.fqs -and $ctx.fqs.category -eq "N/A_no_registry") {
            $delta_notes += "FQS realmente missing -- enqueue ativo, sera enriquecido sabado."
        }
    }

    $analyzed += [PSCustomObject]@{
        timestamp = $r.timestamp
        market    = $market
        decision  = $r.mentor_decision
        provider  = $r.provider_used
        class     = $classification
        notes     = ($delta_notes -join " | ")
    }
}

$improved = @($analyzed | Where-Object { $_.class -eq "improved" }).Count
$attention = @($analyzed | Where-Object { $_.class -eq "needs_attention" }).Count
$consistent = @($analyzed | Where-Object { $_.class -eq "consistent" }).Count
$infraIssue = @($analyzed | Where-Object { $_.class -eq "infra_issue" }).Count
$hallucinated = @($analyzed | Where-Object { $_.class -eq "hallucination_detected" }).Count

if ($JsonOutput) {
    @{ analyzed = $analyzed; summary = @{ improved=$improved; needs_attention=$attention; consistent=$consistent; infra_issue=$infraIssue; hallucination_detected=$hallucinated; total=$rows.Count } } |
        ConvertTo-Json -Depth 5
    exit 0
}

Write-Host "" -ForegroundColor Cyan
Write-Host "=== REPLAY ANALYZER ($LastN decisoes) ===" -ForegroundColor Cyan
Write-Host "  improved (hallucination/conflict resolved): $improved" -ForegroundColor Green
Write-Host "  needs_attention (ambigu):                   $attention" -ForegroundColor Yellow
Write-Host "  consistent (razao continua valida):         $consistent" -ForegroundColor White
Write-Host "  infra_issue (Mentor indisponivel):          $infraIssue" -ForegroundColor DarkYellow
Write-Host "  hallucination_detected (real-time logged):  $hallucinated" -ForegroundColor Magenta
$meritDecisions = $rows.Count - $infraIssue - $improved - $hallucinated
Write-Host "  Decisoes-de-MERITO (excl bug/infra/hallcn):  $meritDecisions" -ForegroundColor Cyan
Write-Host ""

if ($Verbose) {
    Write-Host "Detalhe:" -ForegroundColor Cyan
    foreach ($a in $analyzed) {
        $c = switch ($a.class) {
            "improved" { "Green" }
            "needs_attention" { "Yellow" }
            default { "Gray" }
        }
        Write-Host ("  {0,-25} {1,-14} {2,-8} {3,-20} {4}" -f $a.timestamp, $a.market, $a.decision, $a.class, $a.notes) -ForegroundColor $c
    }
}

# Save report
$reportPath = Join-Path $journalDir ("replay_analyzer_" + (Get-Date -Format "yyyyMMdd_HHmm") + ".json")
@{ analyzed = $analyzed; summary = @{ improved=$improved; needs_attention=$attention; consistent=$consistent; total=$rows.Count } } |
    ConvertTo-Json -Depth 5 | Out-File $reportPath -Encoding utf8
Write-Host "[OK] Report saved: $reportPath" -ForegroundColor DarkGray
