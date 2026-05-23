# B9 fix 2026-05-20 PM6+: TTL cache pra GEM decisions recentes.
# Mesma combo (market + abort_reason) dentro de TTL = skip silencioso (sem custo LLM).

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_gem_decision_cache.ps1")

Describe "B9 GEM recent-decision cache" {
    BeforeEach {
        $script:cachePath = Join-Path $env:TEMP "b9_cache_$([guid]::NewGuid()).json"
    }
    AfterEach {
        Remove-Item $cachePath -Force -ErrorAction SilentlyContinue
    }

    Context "Test-GemRecentlyRejected" {
        It "primeiro registro: NAO rejected previamente" {
            (Test-GemRecentlyRejected -Path $cachePath -Market "DASH" -Reason "MCE_BLOCK 0.1823" -TtlMinutes 60) | Should Be $false
        }
        It "apos Add: rejected dentro do TTL" {
            Add-GemRejection -Path $cachePath -Market "DASH" -Reason "MCE_BLOCK 0.1823"
            (Test-GemRecentlyRejected -Path $cachePath -Market "DASH" -Reason "MCE_BLOCK 0.1823" -TtlMinutes 60) | Should Be $true
        }
        It "fora do TTL: NAO rejected" {
            Add-GemRejection -Path $cachePath -Market "DASH" -Reason "MCE_BLOCK 0.1823"
            # TTL 0 minutos = sempre stale
            (Test-GemRecentlyRejected -Path $cachePath -Market "DASH" -Reason "MCE_BLOCK 0.1823" -TtlMinutes 0) | Should Be $false
        }
        It "reason diferente: NAO rejected (mesmo market)" {
            Add-GemRejection -Path $cachePath -Market "DASH" -Reason "MCE_BLOCK 0.1823"
            (Test-GemRecentlyRejected -Path $cachePath -Market "DASH" -Reason "FQS_LOW" -TtlMinutes 60) | Should Be $false
        }
        It "market diferente: NAO rejected (mesma reason)" {
            Add-GemRejection -Path $cachePath -Market "DASH" -Reason "MCE_BLOCK 0.1823"
            (Test-GemRecentlyRejected -Path $cachePath -Market "ZEC" -Reason "MCE_BLOCK 0.1823" -TtlMinutes 60) | Should Be $false
        }
    }

    Context "rotina de limpeza" {
        It "Add deduplica por (market,reason) -- atualiza timestamp" {
            Add-GemRejection -Path $cachePath -Market "DASH" -Reason "X"
            Start-Sleep -Milliseconds 50
            Add-GemRejection -Path $cachePath -Market "DASH" -Reason "X"
            $entries = Get-Content $cachePath -Raw | ConvertFrom-Json
            @($entries).Count | Should Be 1
        }
    }
}
