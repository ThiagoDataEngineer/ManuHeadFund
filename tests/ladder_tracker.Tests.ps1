# ladder_tracker.Tests.ps1 -- Pester 3.x para lib_ladder_tracker.ps1
# Sem acentos. CSV InvariantCulture.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
$global:JOURNAL_DIR = Join-Path $env:TEMP "ladder_tracker_test_$((Get-Random).ToString())"
New-Item -ItemType Directory -Path $global:JOURNAL_DIR -Force | Out-Null

. (Join-Path $agentsDir "lib_ladder_tracker.ps1")

Describe "Add-LadderEntryRecord" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "ladder_entry_$((Get-Random).ToString())"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $global:JOURNAL_DIR = $script:tmpDir
    }

    It "cria CSV se nao existe" {
        $csv = Join-Path $global:JOURNAL_DIR "ladder_tracker.csv"
        (Test-Path $csv) | Should Be $false
        Add-LadderEntryRecord -Market "AIUSDT" -TemplateId "tori" -Regime "BULL_STRONG" -Entry 0.099895 -AtrValue 0.005 -TpsCount 3 -SlsCount 1
        (Test-Path $csv) | Should Be $true
    }

    It "header CSV tem as colunas esperadas" {
        Add-LadderEntryRecord -Market "AIUSDT" -TemplateId "tori" -Regime "BULL_STRONG" -Entry 0.099895
        $csv = Join-Path $global:JOURNAL_DIR "ladder_tracker.csv"
        $lines = Get-Content -Path $csv
        $lines[0] | Should Be "ts,market,template_id,regime,entry,atr,tps_count,sls_count,trade_id,notes"
    }

    It "escreve valor sub-dollar com ponto (InvariantCulture, sem virgula PT-BR)" {
        Add-LadderEntryRecord -Market "AIUSDT" -TemplateId "tori" -Regime "BULL_WEAK" -Entry 0.099895 -AtrValue 0.0054
        $csv = Join-Path $global:JOURNAL_DIR "ladder_tracker.csv"
        $lines = Get-Content -Path $csv
        $row = $lines[1]
        ($row -match ",0\.099895,") | Should Be $true
        ($row -match ",0\.0054,")   | Should Be $true
        ($row.Contains(";0,099895")) | Should Be $false
    }
}

Describe "Add-LadderHitRecord" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "ladder_hit_$((Get-Random).ToString())"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $global:JOURNAL_DIR = $script:tmpDir
    }

    It "append em sequencia produz multiplas linhas" {
        Add-LadderHitRecord -Market "AIUSDT" -TemplateId "tori" -HitType "TP1" -LevelIndex 1 -HitPrice 0.15 -QtyClosed 30 -PnlR 0.5 -Regime "BULL_STRONG"
        Add-LadderHitRecord -Market "AIUSDT" -TemplateId "tori" -HitType "TP2" -LevelIndex 2 -HitPrice 0.20 -QtyClosed 30 -PnlR 1.0 -Regime "BULL_STRONG"
        Add-LadderHitRecord -Market "AIUSDT" -TemplateId "tori" -HitType "SL"  -LevelIndex 1 -HitPrice 0.05 -QtyClosed 40 -PnlR -0.5 -Regime "BULL_STRONG"
        $csv = Join-Path $global:JOURNAL_DIR "ladder_hits.csv"
        (Get-Content -Path $csv).Count | Should Be 4   # header + 3
    }

    It "header tem as colunas esperadas" {
        Add-LadderHitRecord -Market "X" -TemplateId "tori" -HitType "TP1" -LevelIndex 1
        $csv = Join-Path $global:JOURNAL_DIR "ladder_hits.csv"
        (Get-Content -Path $csv)[0] | Should Be "ts,market,template_id,regime,hit_type,level_index,hit_price,qty_closed,pnl_r,pnl_usd,trade_id,notes"
    }
}

Describe "Get-LadderPerformance" {

    BeforeEach {
        $script:tmpDir = Join-Path $env:TEMP "ladder_perf_$((Get-Random).ToString())"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
        $global:JOURNAL_DIR = $script:tmpDir
    }

    It "retorna estrutura vazia quando nao ha trades (zero erros)" {
        $r = Get-LadderPerformance
        $r.total_entries | Should Be 0
        $r.total_hits    | Should Be 0
        @($r.by_template).Count | Should Be 0
    }

    It "agrega por template_id x regime corretamente" {
        Add-LadderEntryRecord -Market "AIUSDT" -TemplateId "tori" -Regime "BULL_STRONG" -Entry 0.10 -TpsCount 3
        Add-LadderEntryRecord -Market "WIFUSDT" -TemplateId "tori" -Regime "BULL_STRONG" -Entry 0.50 -TpsCount 3
        Add-LadderEntryRecord -Market "BTCUSDT" -TemplateId "melao_kelly" -Regime "TRANSITION_UP" -Entry 50000 -TpsCount 4

        Add-LadderHitRecord -Market "AIUSDT"  -TemplateId "tori" -Regime "BULL_STRONG" -HitType "TP1" -LevelIndex 1 -PnlR 0.5
        Add-LadderHitRecord -Market "WIFUSDT" -TemplateId "tori" -Regime "BULL_STRONG" -HitType "SL"  -LevelIndex 1 -PnlR -0.5

        $r = Get-LadderPerformance
        $r.total_entries | Should Be 3
        $r.total_hits    | Should Be 2
        @($r.by_template).Count | Should Be 2
        $toriBull = $r.by_template | Where-Object { $_.template_id -eq "tori" -and $_.regime -eq "BULL_STRONG" }
        $toriBull.trades  | Should Be 2
        $toriBull.tp_hits | Should Be 1
        $toriBull.sl_hits | Should Be 1
    }

    It "filtro por month restringe agregacao" {
        Add-LadderEntryRecord -Market "AIUSDT" -TemplateId "tori" -Regime "BULL_STRONG" -Entry 0.10
        $r = Get-LadderPerformance -Month "1999-01"
        $r.total_entries | Should Be 0
    }

    It "WriteJson cria arquivo ladder_performance_YYYY-MM.json" {
        Add-LadderEntryRecord -Market "AIUSDT" -TemplateId "tori" -Regime "BULL_STRONG" -Entry 0.10
        $r = Get-LadderPerformance -WriteJson
        $month = (Get-Date).ToString("yyyy-MM")
        $jsonPath = Join-Path $global:JOURNAL_DIR "ladder_performance_$month.json"
        (Test-Path $jsonPath) | Should Be $true
    }

    It "CSV de entry usa InvariantCulture e e parseavel via Import-Csv" {
        Add-LadderEntryRecord -Market "AIUSDT" -TemplateId "tori" -Regime "BULL_STRONG" -Entry 0.099895 -AtrValue 0.0054
        $csv = Join-Path $global:JOURNAL_DIR "ladder_tracker.csv"
        $rows = Import-Csv -Path $csv
        $rows[0].entry | Should Be "0.099895"
        $rows[0].atr   | Should Be "0.0054"
    }
}
