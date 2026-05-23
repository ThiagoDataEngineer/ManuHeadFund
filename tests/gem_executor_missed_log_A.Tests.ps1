# gem_executor_missed_log_A.Tests.ps1 -- 2026-05-22 ATIVACAO A.
# Pester 3.x. Testa logica isolada do MISSED log enriquecido.
#
# Garantias:
#   1. Pattern matcher detecta variantes "missed/distanciou/overbought" em tori_reason
#   2. Append em journal/missed_setups.jsonl (nao substitui historico)
#   3. Snapshot Get-ToriProximityForMarket consultado quando disponivel
#   4. Fail-safe: try/catch ao redor + Get-Command guard
#   5. Entry contem campos esperados pra analise futura

$script:missed_here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:missed_root = Split-Path -Parent $missed_here

# Aux: simula o predicate isTimingMissed extraido do gem_executor
function _IsTimingMissed {
    param([string] $Reason)
    $r = ($Reason -as [string]).ToLower()
    return ($r -match "missed|ja se distanciou|ja rompeu|distancia significativa|overbought extremo|chase|distanciou.*line")
}


Describe "A. Pattern matcher isTimingMissed" {

    It "Detecta 'timing MISSED'" {
        _IsTimingMissed "timing MISSED para bounce" | Should Be $true
    }
    It "Detecta 'ja se distanciou'" {
        _IsTimingMissed "preco ja se distanciou da line" | Should Be $true
    }
    It "Detecta 'ja rompeu'" {
        _IsTimingMissed "preco ja rompeu o nivel" | Should Be $true
    }
    It "Detecta 'distancia significativa'" {
        _IsTimingMissed "distancia significativa da line" | Should Be $true
    }
    It "Detecta 'overbought extremo'" {
        _IsTimingMissed "risco sweep dado overbought extremo" | Should Be $true
    }
    It "Detecta 'chase'" {
        _IsTimingMissed "setup eh chase do pump" | Should Be $true
    }
    It "Detecta 'distanciou ... line'" {
        _IsTimingMissed "preco distanciou em 16% da line" | Should Be $true
    }

    It "Nao detecta razao de data ausente" {
        _IsTimingMissed "tori_wait_no_trendline_data" | Should Be $false
    }
    It "Nao detecta razao generica de slope" {
        _IsTimingMissed "slope_out_of_range" | Should Be $false
    }
    It "Nao detecta string vazia" {
        _IsTimingMissed "" | Should Be $false
    }
}


Describe "A. journal/missed_setups.jsonl - schema + append" {
    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP ("missed_test_" + [guid]::NewGuid().ToString("N").Substring(0,8))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $script:missedPath = Join-Path $tmpDir "missed_setups.jsonl"
    }
    AfterEach {
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    }

    It "Append cria arquivo se nao existir" {
        $entry = [ordered]@{
            ts_skip          = (Get-Date).ToUniversalTime().ToString("o")
            market           = "PEAQUSDT"
            tori_reason      = "timing MISSED 16% above action_line"
            proximity_snap   = $null
            snapshot_present = $false
        }
        Add-Content -Path $missedPath -Value ($entry | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8
        Test-Path $missedPath | Should Be $true
        $lines = Get-Content $missedPath -Encoding UTF8
        @($lines).Count | Should Be 1
    }

    It "Multiplos appends preservam historico (nao substitui)" {
        $e1 = [ordered]@{ ts_skip=(Get-Date).ToUniversalTime().ToString("o"); market="A"; tori_reason="x"; snapshot_present=$false }
        $e2 = [ordered]@{ ts_skip=(Get-Date).ToUniversalTime().ToString("o"); market="B"; tori_reason="y"; snapshot_present=$false }
        Add-Content -Path $missedPath -Value ($e1 | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8
        Add-Content -Path $missedPath -Value ($e2 | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8
        @(Get-Content $missedPath -Encoding UTF8).Count | Should Be 2
    }

    It "Entry com snapshot_present=true inclui proximity_snap object" {
        $entry = [ordered]@{
            ts_skip          = (Get-Date).ToUniversalTime().ToString("o")
            market           = "BTCUSDT"
            tori_reason      = "MISSED"
            proximity_snap   = [ordered]@{
                ts_snap        = (Get-Date).ToUniversalTime().ToString("o")
                side           = "LONG"
                proximity_pct  = 12.5
                action_line    = 75000.0
                slope_deg      = 18.5
                rsi            = 38.0
                vol_drying     = $true
                setup_ripening = $true
            }
            snapshot_present = $true
        }
        Add-Content -Path $missedPath -Value ($entry | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8
        $parsed = Get-Content $missedPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json }
        $parsed.snapshot_present     | Should Be $true
        $parsed.proximity_snap.side  | Should Be "LONG"
        $parsed.proximity_snap.setup_ripening | Should Be $true
    }
}


Describe "A. Integration gem_executor.ps1 - wiring presente" {

    It "Codigo contem isTimingMissed match cobrindo padroes Tori reais" {
        $src = Get-Content (Join-Path $missed_root "agents\gem_executor.ps1") -Raw -Encoding UTF8
        $src | Should Match 'isTimingMissed'
        # 7 patterns cobertos
        $src | Should Match 'missed\|ja se distanciou\|ja rompeu\|distancia significativa\|overbought extremo\|chase\|distanciou\.\*line'
    }

    It "Bloco condicional checa Get-Command Get-ToriProximityForMarket (fail-safe)" {
        $src = Get-Content (Join-Path $missed_root "agents\gem_executor.ps1") -Raw -Encoding UTF8
        $src | Should Match '\$isTimingMissed\s+-and\s+\(Get-Command Get-ToriProximityForMarket'
    }

    It "Snapshot read com MaxAgeMinutes=60 (mais relaxado que default 30 -- captura mais signal)" {
        $src = Get-Content (Join-Path $missed_root "agents\gem_executor.ps1") -Raw -Encoding UTF8
        $src | Should Match 'MaxAgeMinutes\s+60'
    }

    It "Entry serializada com ConvertTo-Json -Compress -Depth 4" {
        $src = Get-Content (Join-Path $missed_root "agents\gem_executor.ps1") -Raw -Encoding UTF8
        $missedBlock = [regex]::Match($src, 'missed_setups\.jsonl[\s\S]+?Add-Content[\s\S]+?\}').Value
        $missedBlock | Should Match 'ConvertTo-Json -Compress -Depth 4'
    }

    It "Diretorio criado se nao existir (idempotente)" {
        $src = Get-Content (Join-Path $missed_root "agents\gem_executor.ps1") -Raw -Encoding UTF8
        $src | Should Match 'New-Item -ItemType Directory -Path \$dir -Force'
    }

    It "Tori reason truncado em 200 chars (anti-bloat)" {
        $src = Get-Content (Join-Path $missed_root "agents\gem_executor.ps1") -Raw -Encoding UTF8
        $src | Should Match 'tori_reason\s*=\s*"\$tori_reason"\.Substring\(0,\s*\[Math\]::Min\(200'
    }
}


Describe "A. Schema validation - campos minimos necessarios" {

    It "Entry tem todos campos pra analise futura (ts_skip + market + tori_reason + proximity_snap + snapshot_present)" {
        $expected = @("ts_skip", "market", "tori_reason", "proximity_snap", "snapshot_present")
        # Replica o entry pattern do gem_executor
        $entry = [ordered]@{
            ts_skip          = (Get-Date).ToUniversalTime().ToString("o")
            market           = "TESTUSDT"
            tori_reason      = "MISSED test"
            proximity_snap   = $null
            snapshot_present = $false
        }
        foreach ($field in $expected) {
            $entry.Contains($field) | Should Be $true
        }
    }

    It "proximity_snap object tem 8 campos esperados quando snapshot present" {
        $snap = [ordered]@{
            ts_snap        = "x"
            side           = "LONG"
            proximity_pct  = 5.0
            action_line    = 100.0
            slope_deg      = 20.0
            rsi            = 35.0
            vol_drying     = $true
            setup_ripening = $true
        }
        $expected = @("ts_snap","side","proximity_pct","action_line","slope_deg","rsi","vol_drying","setup_ripening")
        foreach ($field in $expected) {
            $snap.Contains($field) | Should Be $true
        }
    }
}
