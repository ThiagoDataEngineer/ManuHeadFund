# lib_decision_logger.Tests.ps1 -- Pester 3.x
# Add-Decision: loga TODA chamada orchestrator_v6 (independente de paperOnly).
# Resolve o bug observations.csv vazia (so logava paperOnly).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_observation_logger.ps1"


Describe "Add-Decision - I/O basico" {
    BeforeEach {
        $script:tmpFile = Join-Path $env:TEMP "test_decisions_$([Guid]::NewGuid().ToString('N')).csv"
    }
    AfterEach {
        if (Test-Path $script:tmpFile) { Remove-Item $script:tmpFile -Force }
    }

    It "Cria arquivo + header se nao existir" {
        Add-Decision -DecFile $script:tmpFile -Market "BTCUSDT" -Decision "EXECUTAR" `
                     -Reason "ok" -AbortStage "" -Regime "BULL_STRONG" -Direction "LONG" `
                     -ScannerScore 75 -WhitelistTier "live" -MesaConsensus "FORTE_3" `
                     -MentorDecision "APROVAR" -PaperOnly $false
        Test-Path $script:tmpFile | Should Be $true
        $content = Get-Content $script:tmpFile -Encoding utf8
        $content[0] | Should Match "timestamp"
        $content[0] | Should Match "decision"
        $content[0] | Should Match "abort_stage"
        $content.Length | Should Be 2  # header + 1 row
    }

    It "Append nao recria header" {
        Add-Decision -DecFile $script:tmpFile -Market "BTCUSDT" -Decision "EXECUTAR" `
                     -Reason "ok1" -AbortStage "" -Regime "BULL_STRONG" -Direction "LONG" `
                     -ScannerScore 75 -WhitelistTier "live"
        Add-Decision -DecFile $script:tmpFile -Market "ETHUSDT" -Decision "ABORTAR" `
                     -Reason "tier_d" -AbortStage "triagem" -Regime "NEUTRAL" -Direction "-" `
                     -ScannerScore 30 -WhitelistTier "skip"
        $content = Get-Content $script:tmpFile -Encoding utf8
        $content.Length | Should Be 3
        $content[1] | Should Match "BTCUSDT"
        $content[2] | Should Match "ETHUSDT"
    }
}


Describe "Add-Decision - validacao decision values" {
    BeforeEach {
        $script:tmpFile = Join-Path $env:TEMP "test_dec_val_$([Guid]::NewGuid().ToString('N')).csv"
    }
    AfterEach {
        if (Test-Path $script:tmpFile) { Remove-Item $script:tmpFile -Force }
    }

    It "Aceita EXECUTAR ABORTAR SKIP PAPER" {
        foreach ($d in @("EXECUTAR", "ABORTAR", "SKIP", "PAPER")) {
            { Add-Decision -DecFile $script:tmpFile -Market "X" -Decision $d -Reason "r" `
                          -AbortStage "" -Regime "R" -Direction "L" -ScannerScore 50 -WhitelistTier "live" } |
              Should Not Throw
        }
    }

    It "Rejeita decision invalida" {
        { Add-Decision -DecFile $script:tmpFile -Market "X" -Decision "MAYBE" -Reason "r" `
                      -AbortStage "" -Regime "R" -Direction "L" -ScannerScore 50 -WhitelistTier "live" } |
          Should Throw
    }
}


Describe "Add-Decision - CSV safety" {
    BeforeEach {
        $script:tmpFile = Join-Path $env:TEMP "test_dec_csv_$([Guid]::NewGuid().ToString('N')).csv"
    }
    AfterEach {
        if (Test-Path $script:tmpFile) { Remove-Item $script:tmpFile -Force }
    }

    It "Comma no reason eh escapado (replaced por ;)" {
        Add-Decision -DecFile $script:tmpFile -Market "BTCUSDT" -Decision "ABORTAR" `
                     -Reason "score baixo, macro neutra, regime fraco" -AbortStage "triagem" `
                     -Regime "NEUTRAL" -Direction "-" -ScannerScore 30 -WhitelistTier "skip"
        $content = Get-Content $script:tmpFile -Encoding utf8
        # Conta vírgulas em row 1 — deve bater com num de campos - 1 (sem vírgula extra do reason)
        $row = $content[1]
        $fields = $row -split ','
        $fields.Count | Should Be ($content[0] -split ',').Count
    }
}


Describe "Get-DecisionStats - sumarizacao" {
    BeforeEach {
        $script:tmpFile = Join-Path $env:TEMP "test_dec_stats_$([Guid]::NewGuid().ToString('N')).csv"
        # Popular com 5 decisoes
        for ($i = 0; $i -lt 3; $i++) {
            Add-Decision -DecFile $script:tmpFile -Market "M$i" -Decision "ABORTAR" `
                         -Reason "tier_d" -AbortStage "triagem" -Regime "NEUTRAL" `
                         -Direction "-" -ScannerScore 20 -WhitelistTier "skip"
        }
        Add-Decision -DecFile $script:tmpFile -Market "BTCUSDT" -Decision "EXECUTAR" `
                     -Reason "ok" -AbortStage "" -Regime "BULL_STRONG" -Direction "LONG" `
                     -ScannerScore 75 -WhitelistTier "live"
        Add-Decision -DecFile $script:tmpFile -Market "ETHUSDT" -Decision "PAPER" `
                     -Reason "observe" -AbortStage "" -Regime "BULL_WEAK" -Direction "LONG" `
                     -ScannerScore 60 -WhitelistTier "observe"
    }
    AfterEach {
        if (Test-Path $script:tmpFile) { Remove-Item $script:tmpFile -Force }
    }

    It "Conta decisoes por tipo" {
        $stats = Get-DecisionStats -DecFile $script:tmpFile
        $stats.total | Should Be 5
        $stats.abortar | Should Be 3
        $stats.executar | Should Be 1
        $stats.paper | Should Be 1
    }

    It "Arquivo vazio retorna zeros" {
        $tmp = Join-Path $env:TEMP "nonexistent_$([Guid]::NewGuid().ToString('N')).csv"
        $stats = Get-DecisionStats -DecFile $tmp
        $stats.total | Should Be 0
    }
}
