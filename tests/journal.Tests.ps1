# journal.Tests.ps1 - Pester 3.x tests para Get-JournalStats (metricas novas)
# Rodar: Invoke-Pester .\tests\journal.Tests.ps1 -Verbose

$tmpDir  = Join-Path $env:TEMP "journal_test_$(Get-Random)"
$tmpFile = Join-Path $tmpDir "trades.csv"

[System.IO.Directory]::CreateDirectory($tmpDir) | Out-Null

function Write-Host    { param() }
function Write-Warning { param() }

. "$PSScriptRoot\..\agents\journal.ps1"

# Sobrescreve caminhos do config.ps1 para apontar para diretorio temporario
$JOURNAL_DIR  = $tmpDir
$JOURNAL_FILE = $tmpFile

$HEADERS = "id,timestamp,market,sinal,entry_price,stop_loss,alvo1,alvo2," +
           "quantidade,risco_usd,rr_planejado,score_ponderado,qualidade_setup," +
           "mentor_veredicto,status,exit_price,exit_timestamp,pnl_usd,pnl_pct," +
           "resultado,motivo_saida,erros_execucao,notas,ordem_id"

function Write-TestTrades {
    param([string[]]$Rows)
    @($HEADERS) + $Rows | Out-File -FilePath $tmpFile -Encoding UTF8
}

# Formato: id,timestamp,market,sinal,entry,stop,alvo1,alvo2,qty,risco,rr_plan,score,qualidade,mentor,status,exit,exit_ts,pnl,pnlpct,resultado,motivo,erros,notas,ordem
function MakeRow {
    param($id, $sinal, $entry, $stop, $alvo1, $exit, $pnl, $resultado, $rr, $qualidade, $daysAgo=1)
    $ts     = (Get-Date).AddDays(-$daysAgo).ToString("yyyy-MM-dd HH:mm:ss")
    $exitTs = (Get-Date).AddDays(-$daysAgo).AddHours(2).ToString("yyyy-MM-dd HH:mm:ss")
    "$id,$ts,BTCUSDT,$sinal,$entry,$stop,$alvo1,0,0.01,8.18,$rr,70,$qualidade,EXECUTAR,FECHADO,$exit,$exitTs,$pnl,1.0,$resultado,ALVO1,,,ORD001"
}

# ─────────────────────────────────────────────────────────────────────────────

Describe "Get-JournalStats - profit factor" {

    It "profit factor = grossProfit / grossLoss" {
        Write-TestTrades @(
            (MakeRow "t1" "LONG" 100 95 110 115 50 "WIN"  3.0 "A"),
            (MakeRow "t2" "LONG" 100 95 110 96  -40 "LOSS" 3.0 "B")
        )
        $s = Get-JournalStats -UltimosDias 30
        $s.profitFactor | Should Be 1.25
    }

    It "profit factor INF quando sem perdas" {
        Write-TestTrades @(
            (MakeRow "t1" "LONG" 100 95 110 115 50 "WIN" 3.0 "A"),
            (MakeRow "t2" "LONG" 100 95 110 115 40 "WIN" 3.0 "A")
        )
        $s = Get-JournalStats -UltimosDias 30
        $s.profitFactor | Should Be "INF"
    }

    It "profit factor abaixo de 1 quando losses dominam" {
        Write-TestTrades @(
            (MakeRow "t1" "LONG" 100 95 110 96  -40 "LOSS" 3.0 "B"),
            (MakeRow "t2" "LONG" 100 95 110 96  -40 "LOSS" 3.0 "B"),
            (MakeRow "t3" "LONG" 100 95 110 115  10 "WIN"  3.0 "B")
        )
        $s = Get-JournalStats -UltimosDias 30
        [double]$s.profitFactor | Should BeLessThan 1.0
    }
}

Describe "Get-JournalStats - RR realizado vs planejado" {

    It "RR realizado LONG = (exit - entry) / (entry - stop)" {
        # entry=100, stop=90, exit=130 => stopDist=10, exitDist=30 => RR=3.0
        Write-TestTrades @(
            (MakeRow "t1" "LONG" 100 90 130 130 30 "WIN" 4.0 "A")
        )
        $s = Get-JournalStats -UltimosDias 30
        $s.avgRrRealizado | Should Be 3.0
    }

    It "RR realizado SHORT = (entry - exit) / (stop - entry)" {
        # entry=100, stop=110, exit=70 => stopDist=10, exitDist=30 => RR=3.0
        Write-TestTrades @(
            (MakeRow "t1" "SHORT" 100 110 70 70 30 "WIN" 4.0 "A")
        )
        $s = Get-JournalStats -UltimosDias 30
        $s.avgRrRealizado | Should Be 3.0
    }

    It "RR realizado negativo quando trade fechou contra a direcao" {
        # entry=100, stop=90, exit=95 => exitDist=-5, RR=-0.5
        Write-TestTrades @(
            (MakeRow "t1" "LONG" 100 90 130 95 -8.18 "LOSS" 4.0 "B")
        )
        $s = Get-JournalStats -UltimosDias 30
        $s.avgRrRealizado | Should BeLessThan 0
    }

    It "media de RR realizado com multiplos trades" {
        # t1: entry=100, stop=90, exit=130, RR=3.0
        # t2: entry=100, stop=90, exit=120, RR=2.0 => media=2.5
        Write-TestTrades @(
            (MakeRow "t1" "LONG" 100 90 130 130 30 "WIN" 4.0 "A"),
            (MakeRow "t2" "LONG" 100 90 130 120 20 "WIN" 4.0 "A")
        )
        $s = Get-JournalStats -UltimosDias 30
        $s.avgRrRealizado | Should Be 2.5
    }
}

Describe "Get-JournalStats - breakdown por qualidade de setup" {

    It "retorna stats separadas por qualidade" {
        Write-TestTrades @(
            (MakeRow "t1" "LONG" 100 90 130 130 30  "WIN"  4.0 "A"),
            (MakeRow "t2" "LONG" 100 90 130 130 30  "WIN"  4.0 "A"),
            (MakeRow "t3" "LONG" 100 90 130 96  -10 "LOSS" 3.0 "B"),
            (MakeRow "t4" "LONG" 100 90 130 130 30  "WIN"  3.0 "B")
        )
        $s = Get-JournalStats -UltimosDias 30
        # Setup A: 2 wins, 0 losses => winRate 100%
        # Setup B: 1 win, 1 loss   => winRate 50%
        # Verificamos que retornou sem erro e tem as metricas base
        $s.total    | Should Be 4
        $s.wins     | Should Be 3
    }

    It "journal com todos setups C retorna stats sem erro" {
        Write-TestTrades @(
            (MakeRow "t1" "LONG" 100 90 130 96 -10 "LOSS" 2.0 "C"),
            (MakeRow "t2" "LONG" 100 90 130 96 -10 "LOSS" 2.0 "C")
        )
        $s = Get-JournalStats -UltimosDias 30
        $s.winRate | Should Be 0
    }
}

Describe "Get-JournalStats - maior sequencia de perdas" {

    It "maxLossStreak = 3 quando ha 3 perdas seguidas" {
        Write-TestTrades @(
            (MakeRow "t1" "LONG" 100 90 130 130  30 "WIN"  3.0 "A" 5),
            (MakeRow "t2" "LONG" 100 90 130 96  -10 "LOSS" 3.0 "B" 4),
            (MakeRow "t3" "LONG" 100 90 130 96  -10 "LOSS" 3.0 "B" 3),
            (MakeRow "t4" "LONG" 100 90 130 96  -10 "LOSS" 3.0 "B" 2),
            (MakeRow "t5" "LONG" 100 90 130 130  30 "WIN"  3.0 "A" 1)
        )
        $s = Get-JournalStats -UltimosDias 30
        $s.maxLossStreak | Should Be 3
    }

    It "maxLossStreak = 1 quando perdas sao alternadas" {
        Write-TestTrades @(
            (MakeRow "t1" "LONG" 100 90 130 130  30 "WIN"  3.0 "A" 4),
            (MakeRow "t2" "LONG" 100 90 130 96  -10 "LOSS" 3.0 "B" 3),
            (MakeRow "t3" "LONG" 100 90 130 130  30 "WIN"  3.0 "A" 2),
            (MakeRow "t4" "LONG" 100 90 130 96  -10 "LOSS" 3.0 "B" 1)
        )
        $s = Get-JournalStats -UltimosDias 30
        $s.maxLossStreak | Should Be 1
    }

    It "maxLossStreak = 0 quando todos sao wins" {
        Write-TestTrades @(
            (MakeRow "t1" "LONG" 100 90 130 130 30 "WIN" 3.0 "A"),
            (MakeRow "t2" "LONG" 100 90 130 130 30 "WIN" 3.0 "A")
        )
        $s = Get-JournalStats -UltimosDias 30
        $s.maxLossStreak | Should Be 0
    }

    It "maxLossStreak correto quando todas sao perdas" {
        Write-TestTrades @(
            (MakeRow "t1" "LONG" 100 90 130 96 -10 "LOSS" 3.0 "B" 3),
            (MakeRow "t2" "LONG" 100 90 130 96 -10 "LOSS" 3.0 "B" 2),
            (MakeRow "t3" "LONG" 100 90 130 96 -10 "LOSS" 3.0 "B" 1)
        )
        $s = Get-JournalStats -UltimosDias 30
        $s.maxLossStreak | Should Be 3
    }
}
