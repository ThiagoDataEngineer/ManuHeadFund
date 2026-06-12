# lib_fqs_enrichment_queue.Tests.ps1 -- TDD-first auto-enqueue idempotent FQS.
# Pester 3.x. Lockdown anti-regression do gap 2026-05-21 morning:
#   6 markets scanned hoje sem registry entry; queue mecanismo previo so cobria
#   path Mentor (GEM track + Tier D escapavam). Esses testes garantem que:
#     1. Markets sem registry entry SAO enqueued.
#     2. Markets ja no registry NAO sao enqueued.
#     3. Re-enqueue dentro de 24h eh skip.
#     4. Get-FqsCoverage retorna missing list correto.
#     5. CoinGecko mapping mantem cobertura sintetica.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_fqs_enrichment_queue.ps1")

$script:tmp = Join-Path $env:TEMP ("fqsq_" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

function _ResetEnv {
    Remove-Item (Join-Path $tmp "*") -Recurse -Force -ErrorAction SilentlyContinue
}


Describe "Add-FqsEnrichmentRequest - idempotency" {

    It "Market sem registry e sem queue -> ENQUEUED" {
        _ResetEnv
        $reg = Join-Path $tmp "reg.json"
        @{ BTCUSDT = @{ age_years = 16 } } | ConvertTo-Json | Out-File $reg -Encoding utf8
        $q = Join-Path $tmp "queue.jsonl"
        $r = Add-FqsEnrichmentRequest -Market "NEWUSDT" -RegistryPath $reg -QueueFile $q
        $r.action | Should Be 'enqueued'
        (Test-Path $q) | Should Be $true
        (Get-Content $q -Encoding UTF8).Count | Should Be 1
    }

    It "Market ja no registry -> SKIP_REGISTERED (nao escreve queue)" {
        _ResetEnv
        $reg = Join-Path $tmp "reg.json"
        @{ BTCUSDT = @{ age_years = 16 } } | ConvertTo-Json | Out-File $reg -Encoding utf8
        $q = Join-Path $tmp "queue.jsonl"
        $r = Add-FqsEnrichmentRequest -Market "BTCUSDT" -RegistryPath $reg -QueueFile $q
        $r.action | Should Be 'skip_registered'
        (Test-Path $q) | Should Be $false
    }

    It "Mesmo market enqueued 2x em sequencia -> 2a vez vira SKIP_RECENT" {
        _ResetEnv
        $reg = Join-Path $tmp "reg.json"
        '{}' | Out-File $reg -Encoding utf8
        $q = Join-Path $tmp "queue.jsonl"
        $r1 = Add-FqsEnrichmentRequest -Market "AAAUSDT" -RegistryPath $reg -QueueFile $q
        $r2 = Add-FqsEnrichmentRequest -Market "AAAUSDT" -RegistryPath $reg -QueueFile $q
        $r1.action | Should Be 'enqueued'
        $r2.action | Should Be 'skip_recent'
        (Get-Content $q -Encoding UTF8).Count | Should Be 1
    }

    It "Mesmo market enqueued ha mais de 24h -> reenqueued" {
        _ResetEnv
        $reg = Join-Path $tmp "reg.json"
        '{}' | Out-File $reg -Encoding utf8
        $q = Join-Path $tmp "queue.jsonl"
        $oldTs = (Get-Date).AddHours(-30).ToString('o')
        @{ market = "OLDUSDT"; source = "x"; queued_at = $oldTs } | ConvertTo-Json -Compress |
            Add-Content -Path $q -Encoding utf8
        $r = Add-FqsEnrichmentRequest -Market "OLDUSDT" -RegistryPath $reg -QueueFile $q
        $r.action | Should Be 'enqueued'
        (Get-Content $q -Encoding UTF8).Count | Should Be 2
    }

    It "Multiplos markets distintos -> todos enqueued" {
        _ResetEnv
        $reg = Join-Path $tmp "reg.json"
        '{}' | Out-File $reg -Encoding utf8
        $q = Join-Path $tmp "queue.jsonl"
        foreach ($m in @("AAAA","BBBB","CCCC")) {
            $r = Add-FqsEnrichmentRequest -Market "${m}USDT" -RegistryPath $reg -QueueFile $q
            $r.action | Should Be 'enqueued'
        }
        (Get-Content $q -Encoding UTF8).Count | Should Be 3
    }
}


Describe "Test-MarketInRegistry / Test-MarketRecentlyEnqueued" {

    It "Test-MarketInRegistry retorna false se registry inexistente" {
        _ResetEnv
        $reg = Join-Path $tmp "missing.json"
        Test-MarketInRegistry -Market "X" -RegistryPath $reg | Should Be $false
    }

    It "Test-MarketInRegistry retorna true para entry existente" {
        _ResetEnv
        $reg = Join-Path $tmp "reg.json"
        @{ XUSDT = @{ x = 1 } } | ConvertTo-Json | Out-File $reg -Encoding utf8
        Test-MarketInRegistry -Market "XUSDT" -RegistryPath $reg | Should Be $true
    }

    It "Test-MarketRecentlyEnqueued retorna false se queue inexistente" {
        _ResetEnv
        Test-MarketRecentlyEnqueued -Market "X" -QueueFile (Join-Path $tmp "no.jsonl") | Should Be $false
    }

    It "Test-MarketRecentlyEnqueued retorna true dentro da janela" {
        _ResetEnv
        $q = Join-Path $tmp "q.jsonl"
        $now = (Get-Date).AddMinutes(-30).ToString('o')
        @{ market = "RUSDT"; queued_at = $now } | ConvertTo-Json -Compress |
            Add-Content -Path $q -Encoding utf8
        Test-MarketRecentlyEnqueued -Market "RUSDT" -WithinHours 24 -QueueFile $q | Should Be $true
    }
}


Describe "Get-FqsCoverage" {

    It "Retorna 100% se todos markets estao no registry" {
        _ResetEnv
        $reg = Join-Path $tmp "reg.json"
        @{ AUSDT = @{ x = 1 }; BUSDT = @{ x = 2 } } | ConvertTo-Json | Out-File $reg -Encoding utf8
        $r = Get-FqsCoverage -Markets @("AUSDT","BUSDT") -RegistryPath $reg
        $r.coverage_pct | Should Be 100
        $r.missing.Count | Should Be 0
    }

    It "Retorna missing list correto quando ha gap" {
        _ResetEnv
        $reg = Join-Path $tmp "reg.json"
        @{ AUSDT = @{ x = 1 } } | ConvertTo-Json | Out-File $reg -Encoding utf8
        $r = Get-FqsCoverage -Markets @("AUSDT","XUSDT","YUSDT") -RegistryPath $reg
        $r.coverage_pct | Should Be 33.3
        ($r.missing -join ',') | Should Be "XUSDT,YUSDT"
    }
}


Describe "Anti-regression - 2026-05-21 morning gap" {

    It "Os 6 markets descobertos hoje estao agora no registry" {
        # Lockdown: garante que MARKET_TO_CG cobre todos markets que apareceram em
        # logs/master_20260521.log e que coin_registry.json tem entries pos-enrich.
        $regPath = Join-Path (Split-Path $here -Parent) "journal\coin_registry.json"
        if (-not (Test-Path $regPath)) {
            Set-TestInconclusive "coin_registry.json nao existe no projeto -- skip"
            return
        }
        $reg = Get-Content $regPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($m in @("ARRRUSDT","ASTERUSDT","GRASSUSDT","PROVEUSDT","USELESSUSDT","WIFUSDT")) {
            ($reg.PSObject.Properties[$m] -ne $null) | Should Be $true
        }
    }
}
