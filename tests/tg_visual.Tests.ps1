# tg_visual.Tests.ps1 -- TDD para refatoracao visual Telegram (2026-05-17)
# Pester 3.x, sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
$global:TELEGRAM_API_BASE = "https://api.telegram.org"

function Invoke-RestMethod {
    param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
    return [PSCustomObject]@{ ok = $true; result = [PSCustomObject]@{ message_id = 1 } }
}

. (Join-Path $agentsDir "lib_telegram.ps1")

Describe "Get-TierBadge" {
    It "tier A retorna green circle + A" {
        $b = Get-TierBadge -Tier "A"
        $b | Should Match "A"
    }
    It "tier D retorna red circle + D" {
        $b = Get-TierBadge -Tier "D"
        $b | Should Match "D"
    }
    It "tier desconhecido retorna apenas string upper" {
        $b = Get-TierBadge -Tier "x"
        $b | Should Be "X"
    }
}

Describe "Get-DirectionEmoji" {
    It "LONG retorna chartUp emoji" {
        $em = Get-DirectionEmoji -Direction "LONG"
        $em | Should Not BeNullOrEmpty
    }
    It "SHORT retorna chartDn emoji" {
        $em = Get-DirectionEmoji -Direction "SHORT"
        $em | Should Not BeNullOrEmpty
    }
    It "NEUTRO retorna string vazia" {
        $em = Get-DirectionEmoji -Direction "NEUTRO"
        $em | Should Be ""
    }
}

Describe "Get-ConfidenceBar" {
    It "0% retorna 10 pontos" {
        $b = Get-ConfidenceBar -Pct 0
        $b | Should Be ".........."
    }
    It "100% retorna 10 #" {
        $b = Get-ConfidenceBar -Pct 100
        $b | Should Be "##########"
    }
    It "72% retorna 7# + 3." {
        $b = Get-ConfidenceBar -Pct 72
        $b | Should Be "#######..."
    }
    It "width 5 funciona" {
        $b = Get-ConfidenceBar -Pct 60 -Width 5
        $b | Should Be "###.."
    }
}

Describe "Format-TgEsquadraoResult visual" {
    It "Decisao APROVAR mostra check emoji + EXECUTAR" {
        $tri = [PSCustomObject]@{ tier="B"; score_predicted=72 }
        $mes = [PSCustomObject]@{ consensus="FORTE_3"; sinal_consenso="LONG"; score_avg=77 }
        $men = [PSCustomObject]@{ decision="APROVAR"; confianca=72; mentor_mensagem="razao..." }
        $m = Format-TgEsquadraoResult -Market "KAITOUSDT" -Triagem $tri -Mesa $mes -Mentor $men -Decisao "EXECUTAR"
        $m | Should Match "KAITOUSDT"
        $m | Should Match "EXECUTAR"
        $m | Should Match "FORTE_3"
        $m | Should Match "Mentor"
    }
    It "DRY_RUN_EXECUTAR tem indicador simulado" {
        $tri = [PSCustomObject]@{ tier="B"; score_predicted=72 }
        $m = Format-TgEsquadraoResult -Market "KAITOUSDT" -Triagem $tri -Decisao "DRY_RUN_EXECUTAR"
        $m | Should Match "simulado"
    }
    It "compact mode trunca Mentor msg a 90 chars" {
        $global:TG_FORMAT_MODE = "compact"
        $longMsg = ("x" * 500)
        $tri = [PSCustomObject]@{ tier="B"; score_predicted=72 }
        $men = [PSCustomObject]@{ decision="APROVAR"; confianca=72; mentor_mensagem=$longMsg }
        $m = Format-TgEsquadraoResult -Market "X" -Triagem $tri -Mentor $men -Decisao "EXECUTAR"
        $m | Should Match "x{90}\.\.\."
        $global:TG_FORMAT_MODE = "verbose"
    }
}

Describe "Format-TgCycleSummary visual" {
    It "header tem CICLO + window + momentum bar" {
        $m = Format-TgCycleSummary -Window "NEUTRAL" -MomentScore 50 `
            -TrailSummary "nenhuma" -GemSummary "nenhum" -ScanSummary "8 pares" `
            -OrchSummary "KAITOUSDT EXECUTAR() | HYPEUSDT ABORTAR()" `
            -NextMin 60 -NextTime "23:30" -ElapsedSec 261 -DryRun
        $m | Should Match "CICLO"
        $m | Should Match "NEUTRAL"
        $m | Should Match "50/100"
        # contador exec/abort
        $m | Should Match "1 exec"
        $m | Should Match "1 abort"
    }
    It "compact mode esconde lista detalhada" {
        $global:TG_FORMAT_MODE = "compact"
        $m = Format-TgCycleSummary -Window "NEUTRAL" -MomentScore 50 `
            -TrailSummary "x" -GemSummary "x" -ScanSummary "x" `
            -OrchSummary "A EXECUTAR() | B ABORTAR() | C ABORTAR()" `
            -NextMin 60 -NextTime "23:30" -ElapsedSec 100 -DryRun
        # nao deve ter linha por par
        $lines = ($m -split "`n").Count
        $lines | Should BeLessThan 12
        $global:TG_FORMAT_MODE = "verbose"
    }
}

Describe "Format-HeartbeatMessage visual" {
    It "header tem HEARTBEAT + heart emoji" {
        $m = Format-HeartbeatMessage -Window "NEUTRAL" -NextMin 60 -NextTime "23:30" `
            -WatchCount 8 -CyclesQuiet 2 -DryRun
        $m | Should Match "HEARTBEAT"
        $m | Should Match "DRY"
        $m | Should Match "8 pares"
        $m | Should Match "2 ciclo"
    }
}

Describe "Format-TgSystemStart visual" {
    It "mostra SISTEMA LIGADO e DRY/LIVE" {
        $m_dry  = Format-TgSystemStart -DryRun
        $m_live = Format-TgSystemStart
        $m_dry  | Should Match "DRY RUN"
        $m_live | Should Match "LIVE"
        $m_dry  | Should Match "SISTEMA LIGADO"
    }
}
