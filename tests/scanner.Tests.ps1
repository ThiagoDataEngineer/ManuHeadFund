# scanner.Tests.ps1 -- Pester 3.x
# Universe Sweep cache: Get-ScannerCandidates popula $global:LAST_UNIVERSE_SNAPSHOT
# antes de filtrar pelo top-N. ZERO chamada CoinEx extra -- reusa o fetch existente.
#
# Contrato cache:
#   - Apos chamar Get-ScannerCandidates, $global:LAST_UNIVERSE_SNAPSHOT eh array
#     com TODOS os pares fetched (futures + spot), nao apenas os do top.
#   - Cada item tem schema: { symbol, vol_24h, change_24h, market_cap, age_days, spread_pct }
#     (campos ausentes da API CoinEx ficam $null sem quebrar).
#   - Snapshot tem timestamp ($global:LAST_UNIVERSE_TS) e total_pairs implicito (Count).
#   - Retorno de Get-ScannerCandidates permanece intacto (top-N apos filtro).
#   - API retornando vazio -> snapshot = @() (array vazio, nao $null).

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir = Join-Path (Split-Path $here -Parent) 'scripts'
$scanMaster = Join-Path $scriptsDir 'scan_master.ps1'

# Silenciar Write-Host do scanner
function Write-Host { param() }

# Extrai Get-ScannerCandidates de scan_master.ps1 sem rodar o loop principal.
$scanMasterContent = Get-Content -Raw -Path $scanMaster
if ($scanMasterContent -match '(?ms)(^function Get-ScannerCandidates\s*\{.*?^\})') {
    Invoke-Expression $Matches[1]
}

# ── Stubs CoinEx (fixture compartilhada) ──────────────────────────────────────
function _Make-FutureTicker {
    param([string]$Market, [double]$Open, [double]$Close, [double]$ValueUsdt)
    [PSCustomObject]@{ market=$Market; open=$Open; close=$Close; value=$ValueUsdt }
}

function Reset-UniverseGlobals {
    foreach ($v in 'LAST_UNIVERSE_SNAPSHOT','LAST_UNIVERSE_TS','SCANNER_INDEX') {
        if (Test-Path "variable:global:$v") {
            Remove-Variable -Name $v -Scope Global -ErrorAction SilentlyContinue
        }
    }
}

Describe "Get-ScannerCandidates universe cache" {

    BeforeEach { Reset-UniverseGlobals }
    AfterEach  { Reset-UniverseGlobals }

    Context "cache de universe completo" {

        It "popula `$global:LAST_UNIVERSE_SNAPSHOT antes de filtrar top-N" {
            function CoinEx-GetAllFuturesTickers {
                @(
                    (_Make-FutureTicker -Market "BTCUSDT" -Open 100 -Close 105 -ValueUsdt 50000000),
                    (_Make-FutureTicker -Market "ETHUSDT" -Open 100 -Close 110 -ValueUsdt 30000000),
                    (_Make-FutureTicker -Market "SOLUSDT" -Open 100 -Close 95  -ValueUsdt 10000000)
                )
            }
            function CoinEx-GetAllSpotTickers { @() }

            $null = Get-ScannerCandidates -TopN 1 -MinVolUsd 500000
            $global:LAST_UNIVERSE_SNAPSHOT | Should Not Be $null
        }

        It "snapshot contem TODOS os pares fetched (nao so top-N)" {
            function CoinEx-GetAllFuturesTickers {
                @(
                    (_Make-FutureTicker -Market "A_USDT" -Open 100 -Close 120 -ValueUsdt 10000000),
                    (_Make-FutureTicker -Market "B_USDT" -Open 100 -Close 115 -ValueUsdt 8000000),
                    (_Make-FutureTicker -Market "C_USDT" -Open 100 -Close 105 -ValueUsdt 6000000),
                    (_Make-FutureTicker -Market "D_USDT" -Open 100 -Close 102 -ValueUsdt 5000000),
                    (_Make-FutureTicker -Market "E_USDT" -Open 100 -Close 95  -ValueUsdt 4000000)
                )
            }
            function CoinEx-GetAllSpotTickers { @() }

            $top = @(Get-ScannerCandidates -TopN 2 -MinVolUsd 500000)
            $top.Count | Should Be 2
            # Snapshot tem TODOS os 5 pares (universo completo)
            @($global:LAST_UNIVERSE_SNAPSHOT).Count | Should Be 5
        }

        It "cada item do snapshot tem fields normalizados para lib_universe_sweep" {
            function CoinEx-GetAllFuturesTickers {
                @(_Make-FutureTicker -Market "BTCUSDT" -Open 100 -Close 110 -ValueUsdt 50000000)
            }
            function CoinEx-GetAllSpotTickers { @() }

            $null = Get-ScannerCandidates -TopN 1 -MinVolUsd 500000
            $item = @($global:LAST_UNIVERSE_SNAPSHOT)[0]
            $names = @($item.PSObject.Properties.Name)
            ($names -contains "symbol")     | Should Be $true
            ($names -contains "vol_24h")    | Should Be $true
            ($names -contains "change_24h") | Should Be $true
            ($names -contains "market_cap") | Should Be $true
            ($names -contains "age_days")   | Should Be $true
            ($names -contains "spread_pct") | Should Be $true
        }

        It "Get-ScannerCandidates retorna top-N intacto (backward compat)" {
            function CoinEx-GetAllFuturesTickers {
                @(
                    (_Make-FutureTicker -Market "BIG_USDT"  -Open 100 -Close 130 -ValueUsdt 100000000),
                    (_Make-FutureTicker -Market "MID_USDT"  -Open 100 -Close 105 -ValueUsdt 20000000),
                    (_Make-FutureTicker -Market "TINY_USDT" -Open 100 -Close 101 -ValueUsdt 1000000)
                )
            }
            function CoinEx-GetAllSpotTickers { @() }

            $top = @(Get-ScannerCandidates -TopN 1 -MinVolUsd 500000)
            $top.Count | Should Be 1
            # BIG tem maior score (mais movimento + maior volume)
            $top[0].market | Should Be "BIG_USDT"
            # Mesmo schema legado: market, marketType, change, volume, score
            $tnames = @($top[0].PSObject.Properties.Name)
            ($tnames -contains "market")     | Should Be $true
            ($tnames -contains "marketType") | Should Be $true
        }

        It "API vazia: snapshot eh array vazio, NUNCA `$null" {
            function CoinEx-GetAllFuturesTickers { @() }
            function CoinEx-GetAllSpotTickers { @() }

            $null = Get-ScannerCandidates -TopN 5 -MinVolUsd 500000
            # @() unwraps via pipeline; verificamos via Test-Path no escopo global
            (Test-Path variable:global:LAST_UNIVERSE_SNAPSHOT) | Should Be $true
            @($global:LAST_UNIVERSE_SNAPSHOT).Count | Should Be 0
        }

        It "change_24h reflete a variacao percentual (close vs open)" {
            function CoinEx-GetAllFuturesTickers {
                @(_Make-FutureTicker -Market "XYZUSDT" -Open 100 -Close 115 -ValueUsdt 5000000)
            }
            function CoinEx-GetAllSpotTickers { @() }

            $null = Get-ScannerCandidates -TopN 1 -MinVolUsd 500000
            $item = @($global:LAST_UNIVERSE_SNAPSHOT)[0]
            # 100 -> 115 = +15%
            [math]::Round([double]$item.change_24h, 2) | Should Be 15.00
            $item.symbol  | Should Be "XYZUSDT"
            $item.vol_24h | Should Be 5000000
        }

        It "snapshot inclui pares abaixo de MinVolUsd (universo bruto, antes de filtro)" {
            function CoinEx-GetAllFuturesTickers {
                @(
                    (_Make-FutureTicker -Market "RICH_USDT" -Open 100 -Close 120 -ValueUsdt 5000000),
                    (_Make-FutureTicker -Market "POOR_USDT" -Open 100 -Close 110 -ValueUsdt 100000) # vol < min
                )
            }
            function CoinEx-GetAllSpotTickers { @() }

            $top = @(Get-ScannerCandidates -TopN 5 -MinVolUsd 500000)
            $top.Count | Should Be 1  # POOR filtrado do top
            @($global:LAST_UNIVERSE_SNAPSHOT).Count | Should Be 2  # mas no snapshot
            $syms = @(@($global:LAST_UNIVERSE_SNAPSHOT) | ForEach-Object { $_.symbol })
            ($syms -contains "POOR_USDT") | Should Be $true
        }
    }
}
