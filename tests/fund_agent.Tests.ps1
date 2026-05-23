# fund_agent.Tests.ps1 â€” Pester 3.x tests para fund_agent.ps1
# Cobre: Resolve-CoinGeckoId
# Rodar: Invoke-Pester .\tests\fund_agent.Tests.ps1 -Verbose

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
$global:HALVING_DATE                = [DateTime]::new(2024, 4, 19)
$global:CYCLE_CONSOLIDATION_MONTHS  = 6
$global:CYCLE_BULL_MONTHS           = 18
$global:CYCLE_DISTRIBUTION_MONTHS   = 24

function Write-Host    { param() }
function Write-Warning { param() }
function Invoke-Claude     { param([string]$s, [string]$u) return "{}" }
function Invoke-ClaudeJson { param([string]$s, [string]$u) return $null }
function CoinEx-GetFundingRate { param([string]$m) return $null }

function Invoke-RestMethod {
    param([string]$Uri, [string]$Method, [switch]$ErrorAction)
    # stub â€” testes nao fazem chamadas HTTP reais
    return $null
}

. "$PSScriptRoot\..\agents\fund_agent.ps1"

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Resolve-CoinGeckoId
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Describe "Resolve-CoinGeckoId" {

    Context "mercados conhecidos do mapa" {
        It "resolve BTCUSDT para bitcoin" {
            Resolve-CoinGeckoId "BTCUSDT" | Should Be "bitcoin"
        }
        It "resolve ETHUSDT para ethereum" {
            Resolve-CoinGeckoId "ETHUSDT" | Should Be "ethereum"
        }
        It "resolve SOLUSDT para solana" {
            Resolve-CoinGeckoId "SOLUSDT" | Should Be "solana"
        }
        It "resolve BNBUSDT para binancecoin" {
            Resolve-CoinGeckoId "BNBUSDT" | Should Be "binancecoin"
        }
        It "resolve XRPUSDT para ripple" {
            Resolve-CoinGeckoId "XRPUSDT" | Should Be "ripple"
        }
        It "resolve AVAXUSDT para avalanche-2" {
            Resolve-CoinGeckoId "AVAXUSDT" | Should Be "avalanche-2"
        }
    }

    Context "mercado desconhecido" {
        It "retorna base em lowercase para token sem mapeamento" {
            Resolve-CoinGeckoId "XYZUSDT" | Should Be "xyz"
        }
        It "funciona sem sufixo USDT" {
            Resolve-CoinGeckoId "BTC" | Should Be "bitcoin"
        }
        It "token novo retorna lowercase" {
            Resolve-CoinGeckoId "NEWCOINUSDT" | Should Be "newcoin"
        }
    }
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  ConvertFrom-DefiLlamaResponse
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Describe "ConvertFrom-DefiLlamaResponse" {

    $fakeChains = @(
        [PSCustomObject]@{ name="Ethereum"; tvl=50000000000 },
        [PSCustomObject]@{ name="BSC";      tvl=10000000000 },
        [PSCustomObject]@{ name="Solana";   tvl=5000000000  },
        [PSCustomObject]@{ name="Arbitrum"; tvl=3000000000  },
        [PSCustomObject]@{ name="Polygon";  tvl=1000000000  }
    )

    Context "dados normais" {
        It "calcula totalTvlB correto (69B)" {
            $r = ConvertFrom-DefiLlamaResponse $fakeChains
            $r.totalTvlB | Should Be 69.0
        }
        It "calcula ethDominance de 72.5%" {
            $r = ConvertFrom-DefiLlamaResponse $fakeChains
            $r.ethDominance | Should Be 72.5
        }
        It "top5Chains contem Ethereum" {
            $r = ConvertFrom-DefiLlamaResponse $fakeChains
            $r.top5Chains | Should Match "Ethereum"
        }
        It "top5Chains contem valores em B" {
            $r = ConvertFrom-DefiLlamaResponse $fakeChains
            $r.top5Chains | Should Match "50B"
        }
        It "retorna objeto com tres campos" {
            $r = ConvertFrom-DefiLlamaResponse $fakeChains
            $r.totalTvlB   | Should Not BeNullOrEmpty
            $r.ethDominance | Should Not BeNullOrEmpty
            $r.top5Chains  | Should Not BeNullOrEmpty
        }
    }

    Context "dados invalidos" {
        It "retorna null para array vazio" {
            ConvertFrom-DefiLlamaResponse @() | Should Be $null
        }
        It "retorna null para null" {
            ConvertFrom-DefiLlamaResponse $null | Should Be $null
        }
    }
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  ConvertFrom-MessariResponse
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Describe "ConvertFrom-MessariResponse" {

    $fakeResponse = [PSCustomObject]@{
        data = [PSCustomObject]@{
            market_data = [PSCustomObject]@{
                volume_last_24_hours      = 10000000000
                real_volume_last_24_hours = 3000000000
            }
            on_chain_data = [PSCustomObject]@{
                active_addresses = 1000000
            }
        }
    }

    Context "dados normais" {
        It "calcula realVolRatio de 0.30" {
            $r = ConvertFrom-MessariResponse $fakeResponse "bitcoin"
            $r.realVolRatio | Should Be 0.3
        }
        It "extrai activeAddresses" {
            $r = ConvertFrom-MessariResponse $fakeResponse "bitcoin"
            $r.activeAddresses | Should Be 1000000
        }
        It "preserva coinId" {
            $r = ConvertFrom-MessariResponse $fakeResponse "bitcoin"
            $r.coinId | Should Be "bitcoin"
        }
        It "retorna campos de volume" {
            $r = ConvertFrom-MessariResponse $fakeResponse "bitcoin"
            $r.reportedVol24h | Should Be 10000000000
            $r.realVolume24h  | Should Be 3000000000
        }
    }

    Context "ratio baixo indica wash trading" {
        $washResponse = [PSCustomObject]@{
            data = [PSCustomObject]@{
                market_data = [PSCustomObject]@{
                    volume_last_24_hours      = 100000000
                    real_volume_last_24_hours = 5000000
                }
                on_chain_data = [PSCustomObject]@{ active_addresses = 0 }
            }
        }
        It "ratio 0.05 indica alto wash trading" {
            $r = ConvertFrom-MessariResponse $washResponse "shitcoin"
            $r.realVolRatio | Should Be 0.05
        }
    }

    Context "dados nulos" {
        It "retorna null para response null" {
            ConvertFrom-MessariResponse $null "bitcoin" | Should Be $null
        }
        It "retorna null quando data e null" {
            $empty = [PSCustomObject]@{ data = $null }
            ConvertFrom-MessariResponse $empty "bitcoin" | Should Be $null
        }
    }
}
