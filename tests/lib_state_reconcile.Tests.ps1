# lib_state_reconcile.Tests.ps1 -- Pester 3.x
# TDD Fix #2 (2026-06-23): UMA fonte de verdade.
# Hoje 3 fontes se contradizem: gem_trades.csv diz 6 futures OPEN (fantasma),
# trailing_positions.json diz que fecharam, e tem 4 recovery DUPLICADAS (x2).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_state_reconcile.ps1")

Describe "Remove-DuplicatePositions - dedup trailing_positions.json" {
    It "Mesma market 2x -> mantem 1 (a mais recente por created_at)" {
        $pos = @(
            [pscustomobject]@{ market="UBUSDT"; active=$true; created_at="2026-06-22T23:53:13" }
            [pscustomobject]@{ market="UBUSDT"; active=$true; created_at="2026-06-22T23:53:59" }
        )
        $r = @(Remove-DuplicatePositions -Positions $pos)
        $r.Count | Should Be 1
        $r[0].created_at | Should Be "2026-06-22T23:53:59"
    }

    It "Markets distintos -> preserva todos" {
        $pos = @(
            [pscustomobject]@{ market="UBUSDT";  active=$true; created_at="2026-06-22T23:53:59" }
            [pscustomobject]@{ market="PAXGUSDT"; active=$true; created_at="2026-06-22T23:53:59" }
            [pscustomobject]@{ market="TNSR";     active=$true; created_at="2026-06-22T23:53:59" }
        )
        @(Remove-DuplicatePositions -Positions $pos).Count | Should Be 3
    }

    It "Prefere a ATIVA quando ha ativa + fechada do mesmo market" {
        $pos = @(
            [pscustomobject]@{ market="XMRUSDT"; active=$false; created_at="2026-06-12T11:53:07" }
            [pscustomobject]@{ market="XMRUSDT"; active=$true;  created_at="2026-06-11T10:00:00" }
        )
        $r = @(Remove-DuplicatePositions -Positions $pos)
        $r.Count | Should Be 1
        $r[0].active | Should Be $true
    }

    It "Lista vazia -> vazia" {
        @(Remove-DuplicatePositions -Positions @()).Count | Should Be 0
    }
}

Describe "Resolve-StaleCsvStatus - CSV fantasma vs exchange real" {
    It "OPEN no CSV mas NAO existe na exchange -> marca CLOSED" {
        $csv = @(
            [pscustomobject]@{ market="XMRUSDT";  status="OPEN" }
            [pscustomobject]@{ market="TRUMPUSDT"; status="OPEN" }
            [pscustomobject]@{ market="BASEDUSDT"; status="OPEN" }
        )
        $live = @("BASEDUSDT")  # so BASED esta vivo de fato
        $stale = @(Resolve-StaleCsvStatus -CsvRows $csv -LiveMarkets $live)
        $stale.Count | Should Be 2
        ($stale.market -contains "XMRUSDT") | Should Be $true
        ($stale.market -contains "TRUMPUSDT") | Should Be $true
        ($stale.market -contains "BASEDUSDT") | Should Be $false
    }

    It "Tudo vivo -> nada stale" {
        $csv = @([pscustomobject]@{ market="UBUSDT"; status="OPEN" })
        @(Resolve-StaleCsvStatus -CsvRows $csv -LiveMarkets @("UBUSDT")).Count | Should Be 0
    }

    It "Linhas ja CLOSED sao ignoradas (so cuida das OPEN)" {
        $csv = @(
            [pscustomobject]@{ market="OLDUSDT"; status="CLOSED" }
            [pscustomobject]@{ market="XMRUSDT"; status="OPEN" }
        )
        $stale = @(Resolve-StaleCsvStatus -CsvRows $csv -LiveMarkets @())
        $stale.Count | Should Be 1
        $stale[0].market | Should Be "XMRUSDT"
    }
}
