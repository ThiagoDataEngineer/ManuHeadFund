# scan_master_universe_integration.Tests.ps1 -- Pester 3.x
#
# Integracao Universe Sweep + Hit-Rate no fluxo do scan_master.
# Garantia: APOS Get-ScannerCandidates retornar top-N, o ciclo:
#   1. Le $global:LAST_UNIVERSE_SNAPSHOT (cache da chamada CoinEx) -- ZERO API extra.
#   2. Chama Get-UniverseSnapshot -Pairs $LAST_UNIVERSE_SNAPSHOT -TopN $N
#   3. Loga via Write-MasterLog: [UNIVERSE], [GATE-QUALITY]
#   4. Computa Compare-ScannerVsUniverse LONG + SHORT
#   5. Loga: [HIT-RATE LONG], [HIT-RATE SHORT]
#   6. N dinamico = $global:GEM_SAFETY.MaxGemsPerDay (fallback 10)
#   7. Circuit breaker: safety pausado -> N=0 e nao loga top movers (so universe ts + gate)
#
# Estrategia: nao rodamos scan_master.ps1 (loop infinito + deps externas).
# Replicamos o BLOCO de integracao em Invoke-UniverseSweepBlock e validamos via
# log capturado + greps no scan_master.ps1 real.

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir = Join-Path (Split-Path $here -Parent) 'scripts'
$agentsDir  = Join-Path (Split-Path $here -Parent) 'agents'
$scanMaster = Join-Path $scriptsDir 'scan_master.ps1'

function Write-Host { param() }

# Dot-source libs reais (Haiku owns)
. (Join-Path $agentsDir 'lib_universe_sweep.ps1')
. (Join-Path $agentsDir 'lib_hit_rate.ps1')
. (Join-Path $agentsDir 'lib_trade_logger.ps1')

# Capture log
$global:CAPTURED_LOG = @()
function Write-MasterLog {
    param([string]$Msg, [string]$Level = "INFO")
    $global:CAPTURED_LOG += [PSCustomObject]@{ msg=$Msg; level=$Level }
}

function Reset-IntegrationGlobals {
    $global:CAPTURED_LOG = @()
    foreach ($v in 'LAST_UNIVERSE_SNAPSHOT','LAST_UNIVERSE_TS','GEM_SAFETY') {
        if (Test-Path "variable:global:$v") {
            Remove-Variable -Name $v -Scope Global -ErrorAction SilentlyContinue
        }
    }
}

# ── Bloco isolado: replica a integracao implementada em scan_master.ps1 ──────
# OBS: chamada real eh inline em Invoke-MasterCycle. Aqui isolamos o que ela
# faz logicamente para teste; o "source-grep" abaixo garante que scan_master.ps1
# realmente contem esses calls em produccao.
function Invoke-UniverseSweepBlock {
    param(
        [object[]] $Candidates,   # top-N do scanner (com .market)
        [bool]     $SafetyPaused = $false
    )

    if (-not $global:LAST_UNIVERSE_SNAPSHOT) { return }

    # N dinamico vem do GEM_SAFETY; fallback 10. Circuit breaker zera N.
    $N = 10
    if ($global:GEM_SAFETY -and $global:GEM_SAFETY.MaxGemsPerDay) {
        $N = [int]$global:GEM_SAFETY.MaxGemsPerDay
    }
    if ($SafetyPaused) { $N = 0 }

    $snapshot = Get-UniverseSnapshot -Pairs $global:LAST_UNIVERSE_SNAPSHOT -TopN $N
    Write-MasterLog (Format-UniverseLogEntry -Snapshot $snapshot)
    Write-MasterLog (Format-GateQualityEntry -GateStats $snapshot.gate_stats)

    if ($N -gt 0) {
        $scannerSymbols = @($Candidates | ForEach-Object { $_.market })
        $longSyms  = @($snapshot.top_long_movers  | ForEach-Object { $_.symbol })
        $shortSyms = @($snapshot.top_short_movers | ForEach-Object { $_.symbol })
        $longCmp  = Compare-ScannerVsUniverse -ScannerTopN $scannerSymbols -UniverseMovers $longSyms  -Direction "LONG"
        $shortCmp = Compare-ScannerVsUniverse -ScannerTopN $scannerSymbols -UniverseMovers $shortSyms -Direction "SHORT"
        Write-MasterLog (Format-HitRateEntry -Comparison $longCmp)
        Write-MasterLog (Format-HitRateEntry -Comparison $shortCmp)
    }
}

# Fixture: 5 pares com movimento conhecido
function Seed-UniverseFixture {
    $global:LAST_UNIVERSE_SNAPSHOT = @(
        [PSCustomObject]@{ symbol="BTCUSDT"; vol_24h=5000000; change_24h=2.5;  market_cap=$null; age_days=$null; spread_pct=0.02 }
        [PSCustomObject]@{ symbol="ETHUSDT"; vol_24h=3000000; change_24h=1.2;  market_cap=$null; age_days=$null; spread_pct=0.03 }
        [PSCustomObject]@{ symbol="DOGEUSDT";vol_24h=2000000; change_24h=10.0; market_cap=$null; age_days=$null; spread_pct=0.05 }
        [PSCustomObject]@{ symbol="MOONUSDT";vol_24h=1500000; change_24h=20.0; market_cap=$null; age_days=$null; spread_pct=0.10 }
        [PSCustomObject]@{ symbol="DUMPUSDT";vol_24h=1000000; change_24h=-15.0;market_cap=$null; age_days=$null; spread_pct=0.08 }
    )
    $global:LAST_UNIVERSE_TS = Get-Date
}


Describe "scan_master Universe Sweep integration" {

    BeforeEach { Reset-IntegrationGlobals }
    AfterEach  { Reset-IntegrationGlobals }

    It "loga [UNIVERSE] e [GATE-QUALITY] apos snapshot" {
        Seed-UniverseFixture
        $cands = @([PSCustomObject]@{ market="BTCUSDT" })
        Invoke-UniverseSweepBlock -Candidates $cands -SafetyPaused $false
        $msgs = @($global:CAPTURED_LOG | ForEach-Object { $_.msg })
        ($msgs -join " ") -match "\[UNIVERSE\]"     | Should Be $true
        ($msgs -join " ") -match "\[GATE-QUALITY\]" | Should Be $true
    }

    It "loga [HIT-RATE LONG] e [HIT-RATE SHORT]" {
        Seed-UniverseFixture
        $cands = @([PSCustomObject]@{ market="MOONUSDT" }, [PSCustomObject]@{ market="DUMPUSDT" })
        Invoke-UniverseSweepBlock -Candidates $cands -SafetyPaused $false
        $msgs = @($global:CAPTURED_LOG | ForEach-Object { $_.msg })
        $joined = ($msgs -join " ")
        $joined -match "\[HIT-RATE LONG\]"  | Should Be $true
        $joined -match "\[HIT-RATE SHORT\]" | Should Be $true
    }

    It "computa Compare-ScannerVsUniverse para LONG e SHORT (caught contagem correta)" {
        Seed-UniverseFixture
        # MOONUSDT esta no top LONG; DUMPUSDT esta no top SHORT
        $cands = @([PSCustomObject]@{ market="MOONUSDT" }, [PSCustomObject]@{ market="DUMPUSDT" })
        Invoke-UniverseSweepBlock -Candidates $cands -SafetyPaused $false
        $msgs = @($global:CAPTURED_LOG | ForEach-Object { $_.msg })
        $longLine  = $msgs | Where-Object { $_ -match "\[HIT-RATE LONG\]" } | Select-Object -First 1
        $shortLine = $msgs | Where-Object { $_ -match "\[HIT-RATE SHORT\]" } | Select-Object -First 1
        $longLine  | Should Not Be $null
        $shortLine | Should Not Be $null
        # Pelo menos 1 caught em cada direcao
        $longLine  -match "1/\d+ caught" | Should Be $true
        $shortLine -match "1/\d+ caught" | Should Be $true
    }

    It "N dinamico vem de `$global:GEM_SAFETY.MaxGemsPerDay" {
        Seed-UniverseFixture
        $global:GEM_SAFETY = [PSCustomObject]@{ MaxGemsPerDay = 2 }
        $cands = @([PSCustomObject]@{ market="BTCUSDT" })
        Invoke-UniverseSweepBlock -Candidates $cands -SafetyPaused $false
        $msgs = @($global:CAPTURED_LOG | ForEach-Object { $_.msg })
        # Com N=2, [HIT-RATE LONG] deve ter total=2 (top 2 longs do universo)
        $longLine = $msgs | Where-Object { $_ -match "\[HIT-RATE LONG\]" } | Select-Object -First 1
        $longLine -match "/2 caught" | Should Be $true
    }

    It "Circuit breaker: SafetyPaused=`$true zera N -- nao loga hit-rate" {
        Seed-UniverseFixture
        $cands = @([PSCustomObject]@{ market="BTCUSDT" })
        Invoke-UniverseSweepBlock -Candidates $cands -SafetyPaused $true
        $msgs = @($global:CAPTURED_LOG | ForEach-Object { $_.msg })
        # UNIVERSE + GATE-QUALITY ainda devem aparecer (snapshot computado)
        ($msgs -join " ") -match "\[UNIVERSE\]"     | Should Be $true
        ($msgs -join " ") -match "\[GATE-QUALITY\]" | Should Be $true
        # Mas hit-rate nao
        ($msgs -join " ") -match "\[HIT-RATE LONG\]"  | Should Be $false
        ($msgs -join " ") -match "\[HIT-RATE SHORT\]" | Should Be $false
    }

    It "Snapshot ausente: bloco degrada (sem erro, sem log)" {
        Reset-IntegrationGlobals
        $cands = @([PSCustomObject]@{ market="BTCUSDT" })
        { Invoke-UniverseSweepBlock -Candidates $cands -SafetyPaused $false } | Should Not Throw
        @($global:CAPTURED_LOG).Count | Should Be 0
    }
}

# ── Source-grep: scan_master.ps1 real contem as chamadas Universe Sweep ──────
Describe "scan_master.ps1 source contains Universe Sweep wiring" {

    It "scan_master.ps1 chama Get-UniverseSnapshot apos scanner" {
        $src = Get-Content -Raw -Path $scanMaster
        ($src -match "Get-UniverseSnapshot") | Should Be $true
    }

    It "scan_master.ps1 chama Format-UniverseLogEntry e Format-GateQualityEntry" {
        $src = Get-Content -Raw -Path $scanMaster
        ($src -match "Format-UniverseLogEntry")  | Should Be $true
        ($src -match "Format-GateQualityEntry")  | Should Be $true
    }

    It "scan_master.ps1 chama Compare-ScannerVsUniverse para LONG e SHORT" {
        $src = Get-Content -Raw -Path $scanMaster
        ($src -match "Compare-ScannerVsUniverse") | Should Be $true
        ($src -match 'Direction\s+(["\x27])LONG\1')  | Should Be $true
        ($src -match 'Direction\s+(["\x27])SHORT\1') | Should Be $true
    }

    It "scan_master.ps1 le `$global:GEM_SAFETY.MaxGemsPerDay para N dinamico" {
        $src = Get-Content -Raw -Path $scanMaster
        ($src -match 'GEM_SAFETY.*MaxGemsPerDay') | Should Be $true
    }

    It "scan_master.ps1 dot-sources lib_universe_sweep e lib_hit_rate" {
        $src = Get-Content -Raw -Path $scanMaster
        ($src -match 'lib_universe_sweep') | Should Be $true
        ($src -match 'lib_hit_rate')       | Should Be $true
    }
}
