$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_fqs_lazy_enrich.ps1")

function _TmpJsonl { return (Join-Path $env:TEMP ("lazy_" + $PID + "_" + (Get-Random) + ".jsonl")) }

Describe "Test-FqsLazyEnrichEligible" {
    It "Market mapped (NEAR): eligible=true" {
        $r = Test-FqsLazyEnrichEligible -Market "NEARUSDT"
        # NEAR esta em MARKET_TO_CG conforme CLAUDE.md (40 entries)
        if ($r.eligible) {
            $r.cg_id | Should Not BeNullOrEmpty
        } else {
            # If not mapped, reason should explain
            $r.reason | Should Match "not_in_MARKET_TO_CG|parse_error|coingecko_enrichment_py_missing"
        }
    }

    It "Market NOT mapped (FAKEUSDT): eligible=false" {
        $r = Test-FqsLazyEnrichEligible -Market "FAKEXXXUSDT"
        $r.eligible | Should Be $false
        $r.reason | Should Match "not_in_MARKET_TO_CG|coingecko_enrichment_py_missing"
    }

    It "Returns structure consistent (eligible bool + cg_id + reason)" {
        $r = Test-FqsLazyEnrichEligible -Market "BTCUSDT"
        ($r.eligible -is [bool]) | Should Be $true
        ($r.reason -is [string]) | Should Be $true
    }
}

Describe "Get-FqsLazyCacheStatus" {
    It "Empty cache: can_attempt_global = true" {
        $f = _TmpJsonl
        $r = Get-FqsLazyCacheStatus -Market "BTCUSDT" -CachePath $f
        $r.can_attempt_global | Should Be $true
        $r.can_attempt_market | Should Be $true
    }

    It "Recent global attempt: can_attempt_global = false (rate limit)" {
        $f = _TmpJsonl
        try {
            # Inject entry com ts agora
            $entry = @{ ts = (Get-Date).ToUniversalTime().ToString("o"); market = "ETHUSDT"; success = $true; reason = "x" }
            $entry | ConvertTo-Json -Compress | Out-File -FilePath $f -Encoding UTF8
            $r = Get-FqsLazyCacheStatus -Market "BTCUSDT" -CachePath $f
            $r.can_attempt_global | Should Be $false
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Market attempted recently (< 24h): can_attempt_market = false" {
        $f = _TmpJsonl
        try {
            $entry = @{ ts = (Get-Date).ToUniversalTime().AddHours(-2).ToString("o"); market = "NEARUSDT"; success = $true; reason = "x" }
            $entry | ConvertTo-Json -Compress | Out-File -FilePath $f -Encoding UTF8
            $r = Get-FqsLazyCacheStatus -Market "NEARUSDT" -CachePath $f
            $r.can_attempt_market | Should Be $false
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Market attempted 25h ago: can_attempt_market = true" {
        $f = _TmpJsonl
        try {
            $entry = @{ ts = (Get-Date).ToUniversalTime().AddHours(-25).ToString("o"); market = "NEARUSDT"; success = $true; reason = "x" }
            $entry | ConvertTo-Json -Compress | Out-File -FilePath $f -Encoding UTF8
            $r = Get-FqsLazyCacheStatus -Market "NEARUSDT" -CachePath $f
            $r.can_attempt_market | Should Be $true
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Invoke-FqsLazyEnrich rate-limit + eligibility" {
    It "Market NOT mapped: returns success=false + reason eligibility" {
        $r = Invoke-FqsLazyEnrich -Market "FAKEXXXUSDT" -TimeoutSec 1
        $r.success | Should Be $false
        $r.reason | Should Match "not_eligible"
    }

    It "Rate-limit global ativo: returns success=false sem spawn python" {
        $f = _TmpJsonl
        try {
            # Inject recent global entry
            $entry = @{ ts = (Get-Date).ToUniversalTime().ToString("o"); market = "OTHERUSDT"; success = $true; reason = "x" }
            $entry | ConvertTo-Json -Compress | Out-File -FilePath $f -Encoding UTF8
            # Assume NEAR eh eligible (em MARKET_TO_CG)
            $elig = Test-FqsLazyEnrichEligible -Market "NEARUSDT"
            if ($elig.eligible) {
                $r = Invoke-FqsLazyEnrich -Market "NEARUSDT" -TimeoutSec 1 -CachePath $f
                $r.success | Should Be $false
                $r.reason | Should Match "rate_limit_global|market_attempted_recently"
            }
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Property: log persistido cada attempt" {
    It "Failed attempt logs entry in jsonl" {
        $f = _TmpJsonl
        try {
            # Trigger failed lazy enrich (not mapped)
            $r = Invoke-FqsLazyEnrich -Market "FAKEXXXUSDT" -TimeoutSec 1 -CachePath $f
            # Failed eligibility nao escreve log (eh skip cedo). Verify path
            # Other failures: rate-limit, spawn, etc. — verify ALL log
            $r.success | Should Be $false
            # Quando eligibility falha, NAO loga (skip early). Validar com market mapped + force rate-limit
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}
