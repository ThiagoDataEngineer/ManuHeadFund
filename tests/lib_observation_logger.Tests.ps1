# lib_observation_logger.Tests.ps1
# TDD strict: Add-Observation persiste cascade output em CSV para audit pos-14d.
#
# Schema (journal/short_promotion_criteria_2026_05_15.md): 17 campos.
# Driver de uso: orchestrator_v6.ps1 chama quando tier='observe' (whitelist).
#
# UTF-8 BOM. Pester 3.x. PS 5.1.

. "$PSScriptRoot\..\agents\lib_observation_logger.ps1"

$testFile = Join-Path $env:TEMP "obs_test_$((Get-Random)).csv"

Describe "lib_observation_logger" {

    BeforeEach {
        if (Test-Path $testFile) { Remove-Item $testFile -Force -ErrorAction SilentlyContinue }
    }

    AfterEach {
        if (Test-Path $testFile) { Remove-Item $testFile -Force -ErrorAction SilentlyContinue }
    }

    Context "Add-Observation - schema completo" {
        It "cria arquivo com header CSV se nao existir" {
            Add-Observation -ObsFile $testFile -Market "BTCUSDT" -Regime "BEAR_STRONG" `
                -Direction "SHORT" -DowBrt 5 -WhitelistTier "observe" `
                -WhitelistReason "SHORT em BEAR_STRONG" -ScannerScore 45.5 `
                -MesaConsensus "FORTE_3" -MesaSinal "SHORT" -MentorDecision "APROVAR" `
                -MentorConfidence 75 -EntryPrice 60000 -StopPrice 61500 `
                -TargetPrice 56000 -AtrProxyPct 2.5 -Mode "paper"
            Test-Path $testFile | Should Be $true
            $header = (Get-Content $testFile -TotalCount 1)
            ($header -match "timestamp") | Should Be $true
            ($header -match "market") | Should Be $true
            ($header -match "scanner_score") | Should Be $true
            ($header -match "mesa_consensus") | Should Be $true
        }

        It "appenda linha CSV com 17 campos" {
            Add-Observation -ObsFile $testFile -Market "ETHUSDT" -Regime "TRANSITION_UP" `
                -Direction "LONG" -DowBrt 1 -WhitelistTier "execute" `
                -WhitelistReason "TRANSITION_UP+Mon" -ScannerScore 80 `
                -MesaConsensus "MEDIO_2" -MesaSinal "LONG" -MentorDecision "APROVAR" `
                -MentorConfidence 80 -EntryPrice 3500 -StopPrice 3400 `
                -TargetPrice 3800 -AtrProxyPct 1.8 -Mode "paper"
            $lines = Get-Content $testFile
            $lines.Count | Should Be 2  # header + 1 data
            $cols = ($lines[1] -split ',').Count
            $cols | Should Be 17
        }

        It "appenda multiplas linhas (rolling)" {
            for ($i = 0; $i -lt 3; $i++) {
                Add-Observation -ObsFile $testFile -Market "ALT${i}USDT" -Regime "BEAR_WEAK" `
                    -Direction "SHORT" -DowBrt 3 -WhitelistTier "observe" `
                    -WhitelistReason "SHORT obs" -ScannerScore 30 `
                    -MesaConsensus "CAOS" -MesaSinal "NEUTRO" -MentorDecision "ABORTAR" `
                    -MentorConfidence 40 -EntryPrice 100 -StopPrice 102 `
                    -TargetPrice 96 -AtrProxyPct 2.0 -Mode "paper"
            }
            $lines = Get-Content $testFile
            $lines.Count | Should Be 4  # header + 3 data
        }

        It "usa invariant culture em floats (ponto, nao virgula PT-BR)" {
            Add-Observation -ObsFile $testFile -Market "TEST" -Regime "SIDEWAYS" `
                -Direction "SHORT" -DowBrt 2 -WhitelistTier "observe" `
                -WhitelistReason "test" -ScannerScore 25.75 `
                -MesaConsensus "MEDIO_2" -MesaSinal "SHORT" -MentorDecision "AGUARDAR" `
                -MentorConfidence 50.5 -EntryPrice 1.2345 -StopPrice 1.30 `
                -TargetPrice 1.10 -AtrProxyPct 0.5 -Mode "paper"
            $line = (Get-Content $testFile)[1]
            ($line -match "25\.75") | Should Be $true  # ponto, nao virgula
            ($line -match "1\.2345") | Should Be $true
        }

        It "aceita valores opcionais nulos sem quebrar" {
            Add-Observation -ObsFile $testFile -Market "X" -Regime "SIDEWAYS" `
                -Direction "LONG" -DowBrt 0 -WhitelistTier "skip" `
                -WhitelistReason "no_match" -ScannerScore 0 `
                -MesaConsensus $null -MesaSinal $null -MentorDecision $null `
                -MentorConfidence 0 -EntryPrice 0 -StopPrice 0 `
                -TargetPrice 0 -AtrProxyPct 0 -Mode "paper"
            $line = (Get-Content $testFile)[1]
            ($line -split ",").Count | Should Be 17
        }
    }

    Context "Get-ObservationsByCell - agrega para analytics" {
        It "retorna 0 quando arquivo vazio" {
            $cells = Get-ObservationsByCell -ObsFile $testFile -Direction "SHORT"
            ($cells -is [array] -or $null -eq $cells) | Should Be $true
            if ($cells -is [array]) { $cells.Count | Should Be 0 }
        }

        It "agrupa SHORT observations por regime+dow" {
            # 2 BEAR_STRONG SHORT em Friday + 1 BEAR_WEAK SHORT em Tuesday
            for ($i = 0; $i -lt 2; $i++) {
                Add-Observation -ObsFile $testFile -Market "ALT${i}USDT" -Regime "BEAR_STRONG" `
                    -Direction "SHORT" -DowBrt 5 -WhitelistTier "observe" `
                    -WhitelistReason "test" -ScannerScore 40 `
                    -MesaConsensus "FORTE_3" -MesaSinal "SHORT" -MentorDecision "APROVAR" `
                    -MentorConfidence 70 -EntryPrice 100 -StopPrice 105 `
                    -TargetPrice 90 -AtrProxyPct 2.0 -Mode "paper"
            }
            Add-Observation -ObsFile $testFile -Market "ALT3" -Regime "BEAR_WEAK" `
                -Direction "SHORT" -DowBrt 2 -WhitelistTier "observe" `
                -WhitelistReason "test" -ScannerScore 35 `
                -MesaConsensus "MEDIO_2" -MesaSinal "SHORT" -MentorDecision "APROVAR" `
                -MentorConfidence 60 -EntryPrice 50 -StopPrice 53 `
                -TargetPrice 44 -AtrProxyPct 3.0 -Mode "paper"

            $cells = @(Get-ObservationsByCell -ObsFile $testFile -Direction "SHORT")
            $cells.Count | Should Be 2  # 2 cells distintas
            $beStrong = $cells | Where-Object { $_.Regime -eq "BEAR_STRONG" -and $_.DowBrt -eq 5 }
            $beStrong.N | Should Be 2  # cell N=2 observations
        }

        It "filtra por direction" {
            Add-Observation -ObsFile $testFile -Market "X" -Regime "BEAR_WEAK" -Direction "LONG" `
                -DowBrt 1 -WhitelistTier "observe" -WhitelistReason "x" -ScannerScore 30 `
                -MesaConsensus "MEDIO_2" -MesaSinal "LONG" -MentorDecision "AGUARDAR" `
                -MentorConfidence 50 -EntryPrice 100 -StopPrice 95 -TargetPrice 110 `
                -AtrProxyPct 2 -Mode "paper"
            Add-Observation -ObsFile $testFile -Market "Y" -Regime "BEAR_WEAK" -Direction "SHORT" `
                -DowBrt 1 -WhitelistTier "observe" -WhitelistReason "y" -ScannerScore 30 `
                -MesaConsensus "MEDIO_2" -MesaSinal "SHORT" -MentorDecision "APROVAR" `
                -MentorConfidence 70 -EntryPrice 100 -StopPrice 105 -TargetPrice 90 `
                -AtrProxyPct 2 -Mode "paper"
            $cells = @(Get-ObservationsByCell -ObsFile $testFile -Direction "SHORT")
            $cells.Count | Should Be 1
        }
    }
}
