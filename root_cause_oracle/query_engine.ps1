#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Query = "What issues are detected?",
    [string]$OracleJsonPath = ".\root_cause_oracle\oracle_complete.json"
)

if (-not (Test-Path $OracleJsonPath)) {
    Write-Host "ERROR: Oracle JSON not found at $OracleJsonPath" -ForegroundColor Red
    Write-Host "Run detector_complete.ps1 first." -ForegroundColor Yellow
    exit 1
}

$oracle = Get-Content $OracleJsonPath | ConvertFrom-Json

$queryLower = $Query.ToLower()

$domains = @{
    "ENTRADA" = @("trade", "enter", "gem", "discovery", "execution", "scan", "signal", "candidate")
    "POSICAO" = @("trailing", "stop", "exit", "position", "take-profit", "close", "trail", "loss")
    "INFRAESTRUTURA" = @("telegram", "alert", "supabase", "database", "table", "api", "coinex", "schema", "grant", "permission")
    "LEARNING" = @("grade", "score", "confidence", "decision", "mentor", "evolution", "multiplier", "learning", "cache")
}

$matchedDomains = @()
foreach ($domain in $domains.Keys) {
    $keywords = $domains[$domain]
    $found = $false
    foreach ($kw in $keywords) {
        if ($queryLower -match $kw) {
            $found = $true
            break
        }
    }
    if ($found) {
        $matchedDomains += $domain
    }
}

if ($matchedDomains.Count -eq 0) {
    $matchedDomains = @("ENTRADA", "POSICAO", "INFRAESTRUTURA", "LEARNING")
}

$relevantFindings = $oracle.findings | Where-Object { $_ }

Write-Host ""
Write-Host "ROOT CAUSE ORACLE - QUERY RESULTS" -ForegroundColor Cyan
Write-Host ""
Write-Host "Query: $Query" -ForegroundColor Yellow
Write-Host "Domains: $($matchedDomains -join ', ')" -ForegroundColor Gray
Write-Host ""

if ($queryLower -match "trade|enter") {
    Write-Host "ROUTE: ENTRADA (Entry Pipeline)" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "CHAIN: gem_discovery -> Tori gate -> Mesa -> Mentor -> gem_executor" -ForegroundColor Gray
    Write-Host ""

    $issues = $relevantFindings | Where-Object {
        $_.bug -in @("bug_2", "bug_2b", "bug_4", "bug_6", "bug_7", "bug_8", "bug_12")
    }

    if ($issues) {
        Write-Host "ISSUES FOUND: $($issues.Count)" -ForegroundColor Red
        $issues | ForEach-Object {
            $desc = switch ($_.bug) {
                "bug_2" { "API v1 /candlestick endpoint in v2 context" }
                "bug_2b" { "Period format error (1h vs 1hour)" }
                "bug_4" { "Schema mismatch (trailing_state vs trailing_positions)" }
                "bug_6" { "Missing capital_context table (Supabase)" }
                "bug_7" { "Missing cron_state table (Supabase)" }
                "bug_8" { "Cache collision: market key without direction separation" }
                "bug_12" { "Telegram whitelist regex mismatch (TRADE EJECUTADO blocked)" }
                default { $_.pattern }
            }
            Write-Host "  [FAIL] [$($_.bug)] $desc (confidence: $($_.confidence))" -ForegroundColor Red
        }
    } else {
        Write-Host "No entry pipeline issues detected" -ForegroundColor Green
    }
}
elseif ($queryLower -match "trail|stop|exit|position|close") {
    Write-Host "ROUTE: POSICAO (Position Management)" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "CHAIN: position_watcher -> lib_trailing -> circuit_breaker -> moon_bag" -ForegroundColor Gray
    Write-Host ""

    $issues = $relevantFindings | Where-Object {
        $_.bug -in @("bug_4", "bug_8")
    }

    if ($issues) {
        Write-Host "ISSUES FOUND: $($issues.Count)" -ForegroundColor Red
        $issues | ForEach-Object {
            Write-Host "  [FAIL] [$($_.bug)] $($_.pattern) (confidence: $($_.confidence))" -ForegroundColor Red
        }
    } else {
        Write-Host "No position management issues detected" -ForegroundColor Green
    }
}
elseif ($queryLower -match "telegram|alert|notification") {
    Write-Host "ROUTE: INFRAESTRUTURA (Telegram Alerts)" -ForegroundColor Magenta
    Write-Host ""

    $whitelist = $relevantFindings | Where-Object { $_.bug -eq "bug_12" }
    if ($whitelist) {
        Write-Host "[FAIL] Whitelist Filter Issue" -ForegroundColor Red
        Write-Host "   Expected: 'ordem aberta'" -ForegroundColor Yellow
        Write-Host "   Received: 'TRADE EJECUTADO'" -ForegroundColor Yellow
        Write-Host "   Result: Messages blocked silently" -ForegroundColor Red
    } else {
        Write-Host "[OK] Telegram alerts configured correctly" -ForegroundColor Green
    }
}
elseif ($queryLower -match "schema|table|database|supabase") {
    Write-Host "ROUTE: INFRAESTRUTURA (Database Schema)" -ForegroundColor Magenta
    Write-Host ""

    $missing = $relevantFindings | Where-Object { $_.bug -in @("bug_6", "bug_7") }
    if ($missing) {
        Write-Host "[FAIL] Missing Tables:" -ForegroundColor Red
        $missing | ForEach-Object {
            Write-Host "   * $($_.table)" -ForegroundColor Red
        }
    } else {
        Write-Host "[OK] All required tables exist" -ForegroundColor Green
    }
}
elseif ($queryLower -match "score|confidence|decision|grade|learning") {
    Write-Host "ROUTE: LEARNING (Evolution Engine)" -ForegroundColor Magenta
    Write-Host ""

    $scoreIssues = $relevantFindings | Where-Object { $_.pattern -in @("tainted_score", "empty_global") }
    if ($scoreIssues) {
        Write-Host "ISSUES FOUND: $($scoreIssues.Count)" -ForegroundColor Red
        $scoreIssues | ForEach-Object {
            Write-Host "  [FAIL] [$($_.bug)] $($_.pattern)" -ForegroundColor Red
        }
    } else {
        Write-Host "[OK] Learning pipeline appears intact" -ForegroundColor Green
    }
}
else {
    Write-Host "GENERAL DIAGNOSTIC" -ForegroundColor Magenta
    Write-Host ""

    if ($relevantFindings.Count -gt 0) {
        Write-Host "ISSUES DETECTED: $($relevantFindings.Count)" -ForegroundColor Red
        $relevantFindings | ForEach-Object {
            Write-Host "  [$($_.bug)] $($_.pattern) - confidence: $($_.confidence)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[OK] No critical issues detected" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Total findings: $($oracle.summary.total_findings)" -ForegroundColor Gray
Write-Host "  Coverage: $($oracle.summary.coverage)" -ForegroundColor Gray
Write-Host "  Avg confidence: $($oracle.summary.confidence_avg)" -ForegroundColor Gray
Write-Host ""
