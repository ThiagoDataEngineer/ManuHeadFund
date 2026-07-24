# short_execution_block2.Tests.ps1 -- TDD Block 2 SHORT execution
# Pester 3.x. PS 5.1.
# 20/20 testes validados inline 2026-05-28
# Ver: agents/lib_short_execution.ps1 + agents/lib_operational_whitelist.ps1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_operational_whitelist.ps1")
. (Join-Path $root "agents\lib_short_execution.ps1")
function _r { param($R,$D,$DoW,$M); Test-RegimeDirectionAllowed -Regime $R -Direction $D -DayOfWeekBRT $DoW -Mode $M }

Describe "SHORT Block2 - A. BEAR regimes execute" {
    It "BEAR_STRONG SHORT paper=execute" { (_r 'BEAR_STRONG' 'SHORT' 3 'paper').tier | Should Be 'execute' }
    It "BEAR_STRONG SHORT live=execute"  { (_r 'BEAR_STRONG' 'SHORT' 3 'live').tier  | Should Be 'execute' }
    It "BEAR_WEAK SHORT paper=execute"   { (_r 'BEAR_WEAK'   'SHORT' 3 'paper').tier | Should Be 'execute' }
    It "BEAR_WEAK SHORT live=execute"    { (_r 'BEAR_WEAK'   'SHORT' 3 'live').tier  | Should Be 'execute' }
}

Describe "SHORT Block2 - B. SIDEWAYS SHORT edge +0.34R" {
    It "SIDEWAYS SHORT paper=execute" { (_r 'SIDEWAYS' 'SHORT' 3 'paper').tier | Should Be 'execute' }
    It "SIDEWAYS SHORT live=observe"  { (_r 'SIDEWAYS' 'SHORT' 3 'live').tier  | Should Be 'observe' }
    It "SIDEWAYS LONG paper=skip"     { (_r 'SIDEWAYS' 'LONG'  3 'paper').tier | Should Be 'skip' }
}

Describe "SHORT Block2 - C. TRANSITION_UP SHORT bounce failure +0.81R" {
    It "TRANSITION_UP SHORT paper=execute" { (_r 'TRANSITION_UP' 'SHORT' 3 'paper').tier | Should Be 'execute' }
    It "TRANSITION_UP SHORT live=observe"  { (_r 'TRANSITION_UP' 'SHORT' 3 'live').tier  | Should Be 'observe' }
    # 2026-07-23 FIX: regra mudou em 2026-07-05 (ver lib_operational_whitelist.ps1
    # ~linha 59) -- TRANSITION_UP+LONG liberado pra qualquer dia da semana, mas
    # como "observe" (edge +0.98R n=25 ainda insuficiente pra "execute", DoW
    # deixou de ser o gate). Segunda-feira nao e mais especial.
    It "TRANSITION_UP LONG Mon=observe (DoW nao bloqueia mais desde 07-05)" { (_r 'TRANSITION_UP' 'LONG'  1 'paper').tier | Should Be 'observe' }
    It "TRANSITION_UP LONG Tue=observe"    { (_r 'TRANSITION_UP' 'LONG'  2 'paper').tier | Should Be 'observe' }
}

Describe "SHORT Block2 - D. Get-ShortCandidatesFromAlerts" {
    It "Funcao existe" { (Get-Command Get-ShortCandidatesFromAlerts -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty }
    It "Retorna vazio se arquivo nao existe" {
        $r = Get-ShortCandidatesFromAlerts -AlertsPath 'C:\nao_existe_xyz_abc.jsonl' -MaxAgeHours 24
        @($r).Count | Should Be 0
    }
}

Describe "SHORT Block2 - E. Merge-ShortCandidatesIntoScan" {
    It "Funcao existe" { (Get-Command Merge-ShortCandidatesIntoScan -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty }
    It "Adiciona SHORT ao pipeline" {
        $r = Merge-ShortCandidatesIntoScan -LongCandidates @([PSCustomObject]@{market='BTCUSDT';direction='LONG';compScore=80}) -ShortAlerts @([PSCustomObject]@{market='SOLUSDT';direction='SHORT';current_close=82;vol_ratio=2.8})
        @($r).Count | Should Be 2
    }
    It "Nao duplica mercado LONG" {
        $r = Merge-ShortCandidatesIntoScan -LongCandidates @([PSCustomObject]@{market='BTCUSDT';direction='LONG';compScore=80}) -ShortAlerts @([PSCustomObject]@{market='BTCUSDT';direction='SHORT';current_close=74000;vol_ratio=2.5})
        @($r | Where-Object { $_.market -eq 'BTCUSDT' }).Count | Should Be 1
    }
}

Describe "SHORT Block2 - Regressao LONG rules" {
    It "BULL_STRONG LONG paper=execute" { (_r 'BULL_STRONG' 'LONG' 3 'paper').tier | Should Be 'execute' }
    It "BULL_STRONG SHORT paper=skip"   { (_r 'BULL_STRONG' 'SHORT' 3 'paper').tier | Should Be 'skip' }
    It "BEAR_STRONG LONG paper=skip"    { (_r 'BEAR_STRONG' 'LONG' 1 'paper').tier | Should Be 'skip' }
}
