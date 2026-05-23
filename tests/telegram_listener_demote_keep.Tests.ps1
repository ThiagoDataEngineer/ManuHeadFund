# telegram_listener_demote_keep.Tests.ps1 -- Pester 3.x
# Smoke tests para Cmd-Demote / Cmd-Keep (handler isolado, sem getUpdates loop).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_promotion_ladder.ps1")
. (Join-Path $agentsDir "lib_promotion_gates.ps1")

# Simula state global do listener: journalDir + journalFunctions
$script:journalDir = Join-Path $env:TEMP ("tgkd_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $journalDir -Force | Out-Null

# Substitui Add-DemoteEvent path default por path em tempDir (isola test)
$script:DEMOTE_HISTORY_DEFAULT_PATH = Join-Path $journalDir "demote_history.jsonl"

function Write-TgLog { param($Level,$Msg) }  # mute

# Carrega APENAS as functions Cmd-Demote / Cmd-Keep do telegram_listener via copy inline
# (evita rodar o loop principal que precisa de env vars + getUpdates).
$listenerPath = Join-Path (Split-Path $here -Parent) "scripts\telegram_listener.ps1"
$src = Get-Content $listenerPath -Raw
# Extrai blocos de funcao
if ($src -match '(?ms)^function Cmd-Demote \{.*?^\}') { Invoke-Expression $matches[0] }
if ($src -match '(?ms)^function Cmd-Keep \{.*?^\}')   { Invoke-Expression $matches[0] }


Describe "Cmd-Demote" {
    It "arg vazio retorna usage" {
        $r = Cmd-Demote -Arg ""
        $r -match "Use:" | Should Be $true
    }
    It "demote valido registra evento" {
        $r = Cmd-Demote -Arg "PENDLE drawdown -19%"
        $r -match "Demote registrado" | Should Be $true
        Test-Path $script:DEMOTE_HISTORY_DEFAULT_PATH | Should Be $true
        $line = Get-Content $script:DEMOTE_HISTORY_DEFAULT_PATH | Select-Object -Last 1
        $line -match "PENDLEUSDT" | Should Be $true
    }
    It "normaliza market USDT" {
        $r = Cmd-Demote -Arg "INJ"
        $r -match "INJUSDT|Demote" | Should Be $true
    }
}


Describe "Cmd-Keep" {
    It "arg vazio retorna usage" {
        $r = Cmd-Keep -Arg ""
        $r -match "Use:" | Should Be $true
    }
    It "keep valido registra em keep_decisions.jsonl" {
        $r = Cmd-Keep -Arg "BTC drawdown ok"
        $r -match "Keep registrado" | Should Be $true
        $keepFile = Join-Path $journalDir "keep_decisions.jsonl"
        Test-Path $keepFile | Should Be $true
        $line = Get-Content $keepFile | Select-Object -Last 1
        $line -match "BTCUSDT" | Should Be $true
    }
}

Remove-Item $journalDir -Recurse -Force -ErrorAction SilentlyContinue
