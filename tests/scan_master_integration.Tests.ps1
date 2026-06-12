# scan_master_integration.Tests.ps1 -- Pester 3.x
# Wave 2.5: garante que scan_master.ps1 passa -ScannerInfo e -Mode quando
# chama Invoke-OrchestratorV6 (Risco 2 da Wave 2).
#
# Estrategia:
#   - Nao executamos scan_master.ps1 inteiro (loop infinito + dependencias).
#   - Replicamos o snippet relevante de Invoke-MasterCycle (linhas 295-300)
#     com a correcao da Wave 2.5 e validamos os parametros capturados pelo
#     stub de Invoke-OrchestratorV6.
#   - Tambem fazemos uma checagem de "source-grep" no arquivo real para
#     garantir que a chamada contem -ScannerInfo e -Mode.

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir = Join-Path (Split-Path $here -Parent) "scripts"
$scanMaster = Join-Path $scriptsDir "scan_master.ps1"

# ── Stub de Invoke-OrchestratorV6 captura argumentos ─────────────────────────
$global:ORCH_CALLS = @()
function Invoke-OrchestratorV6 {
    param(
        [string]$Market = "BTCUSDT",
        [switch]$DryRun,
        [PSCustomObject]$ScannerInfo = $null,
        [string]$Mode = "paper"
    )
    $global:ORCH_CALLS += [PSCustomObject]@{
        market      = $Market
        dryRun      = [bool]$DryRun
        scannerInfo = $ScannerInfo
        mode        = $Mode
    }
    return [PSCustomObject]@{
        market    = $Market
        decisao   = "ABORTAR"
        triagem   = $null
        mesa      = $null
        mentor    = $null
        motivo    = "stub"
        timestamp = "stub"
    }
}

# ── Replica do snippet de Invoke-MasterCycle (Wave 2.5) ───────────────────────
# Esta funcao isola a logica que constroi $orchArgs e chama Invoke-OrchestratorV6.
# Wave 2.5 exige:
#   - $orchArgs.ScannerInfo = { score; change; volume } vindos do candidate
#   - $orchArgs.Mode = 'paper' se DryRun, 'live' caso contrario
function Invoke-MasterCycleSnippet {
    param(
        [PSCustomObject]$Candidate,  # { market; scorePonderado; change; volume }
        [switch]$DryRun
    )
    $orchArgs = @{ Market = $Candidate.market }
    if ($DryRun) { $orchArgs.DryRun = $true }
    $orchArgs.ScannerInfo = [PSCustomObject]@{
        score  = $Candidate.scorePonderado
        change = $Candidate.change
        volume = $Candidate.volume
    }
    $orchArgs.Mode = if ($DryRun) { "paper" } else { "live" }
    return (Invoke-OrchestratorV6 @orchArgs)
}

function Reset-OrchCalls {
    $global:ORCH_CALLS = @()
}


Describe "scan_master integration - Wave 2.5 args para Invoke-OrchestratorV6" {

    It "Passa -ScannerInfo populado com score/change/volume" {
        Reset-OrchCalls
        $cand = [PSCustomObject]@{
            market         = "BTCUSDT"
            scorePonderado = 82
            change         = 4.2
            volume         = 1500000
        }
        Invoke-MasterCycleSnippet -Candidate $cand -DryRun | Out-Null
        $global:ORCH_CALLS.Count | Should Be 1
        $global:ORCH_CALLS[0].scannerInfo | Should Not BeNullOrEmpty
        $global:ORCH_CALLS[0].scannerInfo.score  | Should Be 82
        $global:ORCH_CALLS[0].scannerInfo.change | Should Be 4.2
        $global:ORCH_CALLS[0].scannerInfo.volume | Should Be 1500000
    }

    It "Passa -Mode 'paper' quando DryRun" {
        Reset-OrchCalls
        $cand = [PSCustomObject]@{
            market         = "ETHUSDT"
            scorePonderado = 70
            change         = 2.1
            volume         = 800000
        }
        Invoke-MasterCycleSnippet -Candidate $cand -DryRun | Out-Null
        $global:ORCH_CALLS[0].mode | Should Be "paper"
    }

    It "Passa -Mode 'live' quando NAO DryRun" {
        Reset-OrchCalls
        $cand = [PSCustomObject]@{
            market         = "SOLUSDT"
            scorePonderado = 65
            change         = 3.0
            volume         = 500000
        }
        Invoke-MasterCycleSnippet -Candidate $cand | Out-Null
        $global:ORCH_CALLS[0].mode | Should Be "live"
    }

    It "Passa Market correto" {
        Reset-OrchCalls
        $cand = [PSCustomObject]@{
            market         = "PEPEUSDT"
            scorePonderado = 75
            change         = 8.5
            volume         = 2000000
        }
        Invoke-MasterCycleSnippet -Candidate $cand -DryRun | Out-Null
        $global:ORCH_CALLS[0].market | Should Be "PEPEUSDT"
    }
}


Describe "scan_master.ps1 source grep - garante chamada atualizada" {

    It "scan_master.ps1 contem -ScannerInfo na chamada a Invoke-OrchestratorV6" {
        $content = Get-Content -Raw -Path $scanMaster
        ($content -match "ScannerInfo") | Should Be $true
    }

    It "scan_master.ps1 contem -Mode na chamada a Invoke-OrchestratorV6" {
        $content = Get-Content -Raw -Path $scanMaster
        ($content -match "(?ms)Invoke-OrchestratorV6.*?\}|orchArgs.*?Mode") | Should Be $true
        # Verifica explicitamente que orchArgs.Mode foi setado antes da chamada
        ($content -match "orchArgs\.Mode") | Should Be $true
    }
}


# ─────────────────────────────────────────────────────────────────────────────
# Wave 2.5 BUGFIX -- regime no TRADE log
# ─────────────────────────────────────────────────────────────────────────────
# Bug original: log emitia "regime=NEUTRAL" porque scan_master.ps1 lia
# $result.macro.macro_bias (BULLISH/NEUTRAL/BEARISH -- nao canonico) antes
# de $result.triagem.regime (canonico).
#
# Os 8 regimes canonicos validos:
#   BULL_STRONG, BULL_WEAK, SIDEWAYS, TRANSITION_UP, TRANSITION_DOWN,
#   BEAR_WEAK, BEAR_STRONG, CAPITULATION
#
# Estrategia: replicamos Resolve-RegimeForLog do scan_master.ps1 e validamos
# que ele consome $result.triagem.regime (NAO macro.macro_bias) e que o valor
# de saida e sempre canonico ou "UNKNOWN" (nunca "NEUTRAL").

$script:VALID_TRADE_REGIMES_TEST = @(
    "BULL_STRONG","BULL_WEAK","SIDEWAYS","TRANSITION_UP",
    "TRANSITION_DOWN","BEAR_WEAK","BEAR_STRONG","CAPITULATION"
)

function Resolve-RegimeForLogTest {
    param([Parameter(Mandatory=$true)] $Result)
    $candidate = $null
    if ($Result -and $Result.triagem -and $Result.triagem.regime) {
        $candidate = [string]$Result.triagem.regime
    } elseif ($Result -and $Result.regime) {
        $candidate = [string]$Result.regime
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) { return "UNKNOWN" }
    if ($script:VALID_TRADE_REGIMES_TEST -notcontains $candidate) { return "UNKNOWN" }
    return $candidate
}

# Builder helper: monta um $result no formato que Invoke-OrchestratorV6 retorna
function New-OrchResultStub {
    param(
        [string]$TriagemRegime = $null,
        [string]$MacroBias     = "NEUTRAL",
        [string]$TopLevelRegime = $null
    )
    $triagem = $null
    if ($TriagemRegime) {
        $triagem = [PSCustomObject]@{ regime = $TriagemRegime; tier = "C" }
    }
    $obj = [PSCustomObject]@{
        market  = "TESTUSDT"
        decisao = "ABORTAR"
        triagem = $triagem
        macro   = [PSCustomObject]@{ macro_bias = $MacroBias }
    }
    if ($TopLevelRegime) {
        $obj | Add-Member -NotePropertyName regime -NotePropertyValue $TopLevelRegime
    }
    return $obj
}


Describe "scan_master Wave 2.5 bugfix - regime canonico no TRADE log" {

    It "Resolve-RegimeForLog le do triagem.regime (NAO do macro.macro_bias)" {
        # Triagem retorna SIDEWAYS; macro_bias e NEUTRAL.
        # O bug antigo retornaria "NEUTRAL"; o fix deve retornar "SIDEWAYS".
        $result = New-OrchResultStub -TriagemRegime "SIDEWAYS" -MacroBias "NEUTRAL"
        $regime = Resolve-RegimeForLogTest -Result $result
        $regime | Should Be "SIDEWAYS"
        $regime | Should Not Be "NEUTRAL"
    }

    It "Emite SIDEWAYS quando triagem.regime=SIDEWAYS (caso IMXUSDT/DOTUSDT)" {
        $result = New-OrchResultStub -TriagemRegime "SIDEWAYS" -MacroBias "NEUTRAL"
        Resolve-RegimeForLogTest -Result $result | Should Be "SIDEWAYS"
    }

    It "Emite TRANSITION_DOWN quando triagem.regime=TRANSITION_DOWN (caso CFXUSDT)" {
        $result = New-OrchResultStub -TriagemRegime "TRANSITION_DOWN" -MacroBias "NEUTRAL"
        Resolve-RegimeForLogTest -Result $result | Should Be "TRANSITION_DOWN"
    }

    It "Emite BULL_STRONG quando triagem.regime=BULL_STRONG (macro pode estar BULLISH)" {
        $result = New-OrchResultStub -TriagemRegime "BULL_STRONG" -MacroBias "BULLISH"
        Resolve-RegimeForLogTest -Result $result | Should Be "BULL_STRONG"
    }

    It "NUNCA emite valor nao-canonico (NEUTRAL/BULLISH/BEARISH/vazio)" {
        # Quando triagem nao existe e macro.macro_bias=NEUTRAL, fallback NAO pode ser NEUTRAL
        $result = New-OrchResultStub -TriagemRegime $null -MacroBias "NEUTRAL"
        $regime = Resolve-RegimeForLogTest -Result $result
        $regime | Should Not Be "NEUTRAL"
        $regime | Should Not Be "BULLISH"
        $regime | Should Not Be "BEARISH"
        [string]::IsNullOrWhiteSpace($regime) | Should Be $false
    }

    It "Quando triagem.regime e null, fallback e 'UNKNOWN' (nao NEUTRAL)" {
        $result = New-OrchResultStub -TriagemRegime $null -MacroBias "NEUTRAL"
        Resolve-RegimeForLogTest -Result $result | Should Be "UNKNOWN"
    }

    It "Rejeita valor nao-canonico vindo de campo legado (NEUTRAL) -> UNKNOWN" {
        # Defensivo: se algum caller legado popular result.regime='NEUTRAL', sanitiza.
        $result = New-OrchResultStub -TriagemRegime $null -MacroBias "BEARISH" -TopLevelRegime "NEUTRAL"
        Resolve-RegimeForLogTest -Result $result | Should Be "UNKNOWN"
    }

    It "Aceita todos os 8 regimes canonicos" {
        foreach ($r in $script:VALID_TRADE_REGIMES_TEST) {
            $result = New-OrchResultStub -TriagemRegime $r -MacroBias "NEUTRAL"
            Resolve-RegimeForLogTest -Result $result | Should Be $r
        }
    }
}


Describe "scan_master.ps1 source grep - bugfix regime aplicado" {

    It "scan_master.ps1 define Resolve-RegimeForLog" {
        $content = Get-Content -Raw -Path $scanMaster
        ($content -match "function Resolve-RegimeForLog") | Should Be $true
    }

    It "scan_master.ps1 NAO le mais macro.macro_bias para -Regime no Format-TradeLogEntry" {
        $content = Get-Content -Raw -Path $scanMaster
        # A linha bugada antiga era:
        #   $regimeCtx = if ($result.macro -and $result.macro.macro_bias) { $result.macro.macro_bias }
        # Garante que esse padrao especifico nao existe mais.
        ($content -match '\$regimeCtx\s*=\s*if\s*\(\s*\$result\.macro\s+-and\s+\$result\.macro\.macro_bias\s*\)') | Should Be $false
    }

    It "scan_master.ps1 usa Resolve-RegimeForLog para popular regimeCtx" {
        $content = Get-Content -Raw -Path $scanMaster
        ($content -match '\$regimeCtx\s*=\s*Resolve-RegimeForLog') | Should Be $true
    }
}
