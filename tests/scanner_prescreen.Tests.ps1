# scanner_prescreen.Tests.ps1 - Pester 3.x tests para Test-MicroCapPrescreen
# Cobre: volume, MC/FDV, idade do contrato, concentracao de holders
# Rodar: Invoke-Pester .\tests\scanner_prescreen.Tests.ps1 -Verbose

$global:ANTHROPIC_API_KEY           = $null
$global:COINEX_ACCESS_ID            = $null
$global:COINEX_SECRET_KEY           = $null
$global:COINEX_BASE_URL             = "https://api.coinex.com"
$global:CLAUDE_MODEL                = "claude-sonnet-4"
$global:CLAUDE_MAX_TOKENS           = 2048
$global:CLAUDE_TEMP_TRADE           = 0.3
$global:COINEX_FEE_ROUNDTRIP_FALLBACK = 0.004
$global:COINEX_FEE_MAKER_FALLBACK   = 0.002
$global:COINEX_FEE_TAKER_FALLBACK   = 0.002
$global:RISCO_MAXIMO_PCT            = 0.01
$global:SCORE_MINIMO                = 55
$global:HALVING_DATE                = [DateTime]::new(2024, 4, 20)
$global:CYCLE_CONSOLIDATION_MONTHS  = 6
$global:CYCLE_BULL_MONTHS           = 18
$global:CYCLE_DISTRIBUTION_MONTHS   = 30

function Write-Host    { param() }
function Write-Warning { param() }
function Invoke-Claude     { param([string]$s, [string]$u) return "{}" }
function Invoke-ClaudeJson { param([string]$s, [string]$u) return $null }
function CoinEx-GetTicker      { param([string]$m) return $null }
function CoinEx-GetFundingRate { param([string]$m) return $null }
function CoinEx-GetMarketInfo  { param([string]$m) return $null }
function Get-EtherscanConcentration { param([string]$m)
    return [PSCustomObject]@{ level="LOW"; threshold=40; top10PctHeld=35 }
}

. "$PSScriptRoot\..\agents\scanner.ps1"

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Test-MicroCapPrescreen - Filtro de volume
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Describe "Test-MicroCapPrescreen - filtro de volume" {

    Context "volume USD acima do minimo" {
        It "retorna passed=true quando volume supera o minimo" {
            $ticker = [PSCustomObject]@{ last="1.00"; volume="600000" }
            Mock CoinEx-GetTicker { $ticker }
            Mock Get-CoinGeckoPrescreenData { $null }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $ticker -MinVolume24hUsd 500000
            $r.passed | Should Be $true
        }
    }

    Context "volume USD abaixo do minimo" {
        It "retorna passed=false quando volume esta abaixo do minimo" {
            $ticker = [PSCustomObject]@{ last="0.10"; volume="100000" }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $ticker -MinVolume24hUsd 500000
            $r.passed | Should Be $false
        }

        It "inclui volume no motivo da rejeicao" {
            $ticker = [PSCustomObject]@{ last="0.01"; volume="1000" }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $ticker -MinVolume24hUsd 500000
            $r.reason | Should Match "volume"
        }
    }

    Context "ticker indisponivel" {
        It "retorna passed=false quando ticker nao pode ser obtido" {
            Mock CoinEx-GetTicker { $null }
            $r = Test-MicroCapPrescreen "XYZUSDT" -MinVolume24hUsd 500000
            $r.passed | Should Be $false
            $r.reason | Should Match "indisponivel"
        }
    }
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Test-MicroCapPrescreen - Filtro MC/FDV
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Describe "Test-MicroCapPrescreen - filtro MC/FDV" {

    $global:_tickerOk = [PSCustomObject]@{ last="1.00"; volume="1000000" }

    Context "ratio MC/FDV adequado" {
        It "passa quando circulante e alto em relacao ao FDV" {
            Mock Get-CoinGeckoPrescreenData {
                [PSCustomObject]@{ marketCap=80000000; fdv=100000000; genesisDate="2020-01-01" }
            }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $global:_tickerOk -MinMcFdvRatio 0.20
            $r.passed | Should Be $true
        }

        It "armazena o ratio calculado no resultado" {
            Mock Get-CoinGeckoPrescreenData {
                [PSCustomObject]@{ marketCap=50000000; fdv=100000000; genesisDate="2020-01-01" }
            }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $global:_tickerOk -MinMcFdvRatio 0.20
            $r.mcFdvRatio | Should Be 0.5
        }
    }

    Context "ratio MC/FDV critico - muita diluicao futura" {
        It "rejeita quando FDV muito maior que MC" {
            Mock Get-CoinGeckoPrescreenData {
                [PSCustomObject]@{ marketCap=5000000; fdv=100000000; genesisDate="2020-01-01" }
            }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $global:_tickerOk -MinMcFdvRatio 0.20
            $r.passed | Should Be $false
            $r.reason | Should Match "mc_fdv"
        }
    }

    Context "dados CoinGecko indisponiveis" {
        It "nao bloqueia quando CoinGecko nao retorna dados" {
            Mock Get-CoinGeckoPrescreenData { $null }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $global:_tickerOk -MinMcFdvRatio 0.20
            $r.passed | Should Be $true
        }
    }
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Test-MicroCapPrescreen - Filtro idade do contrato
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Describe "Test-MicroCapPrescreen - filtro idade do contrato" {

    $global:_tickerOk2 = [PSCustomObject]@{ last="1.00"; volume="1000000" }

    Context "token com mais de 90 dias" {
        It "passa quando contrato tem mais de 3 meses" {
            Mock Get-CoinGeckoPrescreenData {
                [PSCustomObject]@{ marketCap=50000000; fdv=60000000; genesisDate="2020-06-01" }
            }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $global:_tickerOk2 -MinContractAgeDays 90
            $r.passed | Should Be $true
        }
    }

    Context "token novo - possivel rug" {
        It "rejeita quando contrato tem menos de 90 dias" {
            $recentDate = ([DateTime]::UtcNow.AddDays(-30)).ToString("yyyy-MM-dd")
            Mock Get-CoinGeckoPrescreenData {
                [PSCustomObject]@{ marketCap=50000000; fdv=60000000; genesisDate=$recentDate }
            }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $global:_tickerOk2 -MinContractAgeDays 90
            $r.passed | Should Be $false
            $r.reason | Should Match "contrato_novo"
        }
    }

    Context "genesis date nulo" {
        It "nao bloqueia quando genesis date nao disponivel" {
            Mock Get-CoinGeckoPrescreenData {
                [PSCustomObject]@{ marketCap=50000000; fdv=60000000; genesisDate=$null }
            }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $global:_tickerOk2 -MinContractAgeDays 90
            $r.passed | Should Be $true
        }
    }
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Test-MicroCapPrescreen - Filtro concentracao de holders
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Describe "Test-MicroCapPrescreen - filtro concentracao de holders" {

    $global:_tickerOk3 = [PSCustomObject]@{ last="1.00"; volume="1000000" }

    Context "concentracao normal" {
        It "passa quando concentracao nao e critica" {
            Mock Get-CoinGeckoPrescreenData {
                [PSCustomObject]@{ marketCap=50000000; fdv=60000000; genesisDate="2020-01-01" }
            }
            Mock Get-EtherscanConcentration {
                [PSCustomObject]@{ level="MEDIUM"; threshold=60; top10PctHeld=55 }
            }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $global:_tickerOk3 -CheckConcentration
            $r.passed | Should Be $true
        }
    }

    Context "concentracao critica - armadilha" {
        It "rejeita quando concentracao e CRITICAL" {
            Mock Get-CoinGeckoPrescreenData {
                [PSCustomObject]@{ marketCap=50000000; fdv=60000000; genesisDate="2020-01-01" }
            }
            Mock Get-EtherscanConcentration {
                [PSCustomObject]@{ level="CRITICAL"; threshold=80; top10PctHeld=90 }
            }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $global:_tickerOk3 -CheckConcentration
            $r.passed | Should Be $false
            $r.reason | Should Match "concentracao_critica"
        }
    }

    Context "concentracao sem CheckConcentration" {
        It "nao verifica concentracao quando switch nao ativo" {
            Mock Get-CoinGeckoPrescreenData {
                [PSCustomObject]@{ marketCap=50000000; fdv=60000000; genesisDate="2020-01-01" }
            }
            # Get-EtherscanConcentration NAO deve ser chamado
            Mock Get-EtherscanConcentration { throw "nao deveria ser chamado" }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $global:_tickerOk3
            $r.passed | Should Be $true
        }
    }
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Test-MicroCapPrescreen - Short-circuit e campos de saida
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Describe "Test-MicroCapPrescreen - short-circuit e saida" {

    Context "falha no primeiro filtro" {
        It "retorna imediatamente na falha de volume sem chamar CoinGecko" {
            $ticker = [PSCustomObject]@{ last="0.001"; volume="10" }
            Mock Get-CoinGeckoPrescreenData { throw "nao deveria ser chamado" }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $ticker -MinVolume24hUsd 500000
            $r.passed | Should Be $false
        }
    }

    Context "todos os filtros passam" {
        It "retorna passed=true e reason=OK quando tudo ok" {
            $ticker = [PSCustomObject]@{ last="1.00"; volume="1000000" }
            Mock Get-CoinGeckoPrescreenData {
                [PSCustomObject]@{ marketCap=80000000; fdv=100000000; genesisDate="2021-01-01" }
            }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $ticker
            $r.passed | Should Be $true
            $r.reason | Should Be "OK"
        }

        It "preenche volumeUsd no resultado" {
            $ticker = [PSCustomObject]@{ last="2.00"; volume="300000" }
            Mock Get-CoinGeckoPrescreenData { $null }
            $r = Test-MicroCapPrescreen "XYZUSDT" -Ticker $ticker -MinVolume24hUsd 100000
            $r.volumeUsd | Should Be 600000
        }
    }
}
