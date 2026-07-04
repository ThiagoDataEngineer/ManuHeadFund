# lib_crowding_signal.Tests.ps1 — TDD do sinal de crowding (Pester 3.x)
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "agents\lib_crowding_signal.ps1")

Describe "Resolve-CrowdingVerdict (logica pura, evidencia 2026-07-04)" {
    It "funding extremo positivo = CROWDED_LONGS com short_boost" {
        $v = Resolve-CrowdingVerdict -FundingPct 0.12
        $v.crowding | Should Be "CROWDED_LONGS"
        $v.short_boost | Should Be $true
        $v.long_caution | Should Be $true
    }
    It "funding extremo NEGATIVO NAO habilita long (evidencia: 43% acerto)" {
        $v = Resolve-CrowdingVerdict -FundingPct -0.15
        $v.crowding | Should Be "CROWDED_SHORTS"
        $v.long_enable | Should Be $false
        $v.short_boost | Should Be $false
    }
    It "faixa moderada (+0.05) = NEUTRAL (momentum continua, so extremo reverte)" {
        (Resolve-CrowdingVerdict -FundingPct 0.05).crowding | Should Be "NEUTRAL"
    }
    It "threshold parametrizavel muda o corte" {
        (Resolve-CrowdingVerdict -FundingPct 0.06 -ExtremePct 0.05).crowding | Should Be "CROWDED_LONGS"
    }
    It "exatamente no threshold conta como extremo (>=)" {
        (Resolve-CrowdingVerdict -FundingPct 0.10).crowding | Should Be "CROWDED_LONGS"
    }
}

Describe "Get-CrowdingThresholds (overlay bounded, fail-safe)" {
    $tmp = Join-Path $env:TEMP "crowd_test_$(Get-Random)"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    It "sem overlay = default 0.10" {
        (Get-CrowdingThresholds -JournalDir $tmp).extreme_pct | Should Be 0.10
    }
    It "overlay valido aplica" {
        '{"extreme_pct": 0.08}' | Out-File (Join-Path $tmp "crowding_thresholds.json") -Encoding UTF8
        (Get-CrowdingThresholds -JournalDir $tmp).extreme_pct | Should Be 0.08
    }
    It "overlay fora do bound e clampado (0.05..0.30)" {
        '{"extreme_pct": 0.01}' | Out-File (Join-Path $tmp "crowding_thresholds.json") -Encoding UTF8
        (Get-CrowdingThresholds -JournalDir $tmp).extreme_pct | Should Be 0.05
        '{"extreme_pct": 9}' | Out-File (Join-Path $tmp "crowding_thresholds.json") -Encoding UTF8
        (Get-CrowdingThresholds -JournalDir $tmp).extreme_pct | Should Be 0.30
    }
    It "overlay corrompido = default (fail-safe)" {
        'lixo{{{' | Out-File (Join-Path $tmp "crowding_thresholds.json") -Encoding UTF8
        (Get-CrowdingThresholds -JournalDir $tmp).extreme_pct | Should Be 0.10
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
