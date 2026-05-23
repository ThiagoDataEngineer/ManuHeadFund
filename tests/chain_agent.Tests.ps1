# chain_agent.Tests.ps1 â€” Pester 3.x tests para as novas funcoes de chain_agent.ps1
# Cobre: Get-WhaleAlertData, Get-MempoolHashRibbon, Get-EtherscanConcentration, Resolve-ChainCoinId
# Rodar: Invoke-Pester .\tests\chain_agent.Tests.ps1 -Verbose

# Stubs de dependencias para nao precisar de credenciais ou internet
$ANTHROPIC_API_KEY = $null
$COINEX_ACCESS_ID  = $null
$COINEX_SECRET_KEY = $null
$COINEX_BASE_URL   = "https://api.coinex.com"
$CLAUDE_MODEL      = "claude-sonnet-4"
$CLAUDE_MAX_TOKENS = 2048
$CLAUDE_TEMP_TRADE = 0.3
$COINEX_FEE_ROUNDTRIP_FALLBACK = 0.004
$COINEX_FEE_MAKER_FALLBACK     = 0.002
$COINEX_FEE_TAKER_FALLBACK     = 0.002

function Write-Host    { param() }
function Write-Warning { param() }
function Invoke-Claude     { param([string]$s, [string]$u) return "{}" }
function Invoke-ClaudeJson { param([string]$s, [string]$u) return $null }
function CoinEx-GetTicker      { param([string]$m) return $null }
function CoinEx-GetFundingRate { param([string]$m) return $null }

. "$PSScriptRoot\..\agents\chain_agent.ps1"

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Get-WhaleAlertData
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Describe "Get-WhaleAlertData" {

    Context "saida de exchange (outflow > inflow) - bullish" {
        It "retorna whaleSignal BULLISH quando saidas superam entradas" {
            Mock Invoke-RestMethod {
                [PSCustomObject]@{
                    count = 3
                    transactions = @(
                        [PSCustomObject]@{ from=@{owner_type="exchange"}; to=@{owner_type="unknown"}; amount_usd=5000000 },
                        [PSCustomObject]@{ from=@{owner_type="exchange"}; to=@{owner_type="unknown"}; amount_usd=3000000 },
                        [PSCustomObject]@{ from=@{owner_type="unknown"};  to=@{owner_type="exchange"}; amount_usd=1000000 }
                    )
                }
            }
            $r = Get-WhaleAlertData -Market "BTCUSDT"
            $r             | Should Not BeNullOrEmpty
            $r.whaleSignal | Should Be "BULLISH"
            $r.outflowUSD  | Should BeGreaterThan $r.inflowUSD
        }
    }

    Context "entrada em exchange (inflow > outflow) - bearish" {
        It "retorna whaleSignal BEARISH quando entradas superam saidas" {
            Mock Invoke-RestMethod {
                [PSCustomObject]@{
                    count = 2
                    transactions = @(
                        [PSCustomObject]@{ from=@{owner_type="unknown"}; to=@{owner_type="exchange"}; amount_usd=10000000 },
                        [PSCustomObject]@{ from=@{owner_type="unknown"}; to=@{owner_type="exchange"}; amount_usd=8000000  }
                    )
                }
            }
            $r = Get-WhaleAlertData -Market "BTCUSDT"
            $r.whaleSignal | Should Be "BEARISH"
            $r.inflowUSD   | Should BeGreaterThan $r.outflowUSD
        }
    }

    Context "lista de transacoes vazia" {
        It "retorna whaleSignal NEUTRO quando nao ha transacoes" {
            Mock Invoke-RestMethod {
                [PSCustomObject]@{ count = 0; transactions = @() }
            }
            $r = Get-WhaleAlertData -Market "BTCUSDT"
            $r.whaleSignal | Should Be "NEUTRO"
            $r.inflowUSD   | Should Be 0
            $r.outflowUSD  | Should Be 0
        }
    }

    Context "API indisponivel (excecao de rede)" {
        It "retorna null em vez de lancar excecao" {
            Mock Invoke-RestMethod { throw "connection refused" }
            $r = Get-WhaleAlertData -Market "BTCUSDT"
            $r | Should BeNullOrEmpty
        }
    }

    Context "filtragem por valor minimo" {
        It "ignora transacoes abaixo do MinValueUSD" {
            Mock Invoke-RestMethod {
                [PSCustomObject]@{
                    count = 2
                    transactions = @(
                        # Abaixo do limiar - deve ser ignorada
                        [PSCustomObject]@{ from=@{owner_type="unknown"}; to=@{owner_type="exchange"}; amount_usd=500000  },
                        # Acima do limiar
                        [PSCustomObject]@{ from=@{owner_type="exchange"}; to=@{owner_type="unknown"}; amount_usd=2000000 }
                    )
                }
            }
            $r = Get-WhaleAlertData -Market "BTCUSDT" -MinValueUSD 1000000
            $r.whaleSignal | Should Be "BULLISH"
            $r.inflowUSD   | Should Be 0
            $r.outflowUSD  | Should Be 2000000
        }
    }

    Context "estrutura do objeto retornado" {
        It "retorna todas as propriedades esperadas" {
            Mock Invoke-RestMethod {
                [PSCustomObject]@{
                    count = 1
                    transactions = @(
                        [PSCustomObject]@{ from=@{owner_type="exchange"}; to=@{owner_type="unknown"}; amount_usd=3000000 }
                    )
                }
            }
            $r     = Get-WhaleAlertData -Market "BTCUSDT"
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "whaleSignal") | Should Be $true
            ($names -contains "inflowUSD")   | Should Be $true
            ($names -contains "outflowUSD")  | Should Be $true
            ($names -contains "netFlowUSD")  | Should Be $true
            ($names -contains "txCount")     | Should Be $true
            ($names -contains "topMoves")    | Should Be $true
        }
    }
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Get-MempoolHashRibbon
# MA30 = media das ultimas 5 semanas  |  MA60 = media das ultimas 10 semanas
# BUY_SIGNAL: MA30 > MA60 * 1.02 (recuperacao de mineradores)
# BEARISH:    MA30 < MA60 * 0.98 (capitulacao em curso)
# NEUTRO:     diferenca dentro de 2%
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Describe "Get-MempoolHashRibbon" {

    Context "MA30 acima de MA60 - recuperacao pos-capitulacao" {
        It "retorna signal BUY_SIGNAL quando MA30 supera MA60" {
            Mock Invoke-RestMethod {
                # 60 semanas baixas, depois 5 semanas altas
                # MA5 (last 5) = 600e18 | MA10 (last 10) = media(5*300e18 + 5*600e18) = 450e18
                # MA5 > MA10 -> BUY_SIGNAL
                $weeks = @()
                for ($i = 0; $i -lt 60; $i++) { $weeks += [PSCustomObject]@{ avgHashrate = 300e18 } }
                for ($i = 0; $i -lt 5;  $i++) { $weeks += [PSCustomObject]@{ avgHashrate = 600e18 } }
                [PSCustomObject]@{ hashrates = $weeks }
            }
            $r = Get-MempoolHashRibbon -Market "BTCUSDT"
            $r              | Should Not BeNullOrEmpty
            $r.signal       | Should Be "BUY_SIGNAL"
            $r.hashRate30d  | Should BeGreaterThan $r.hashRate60d
        }
    }

    Context "MA30 abaixo de MA60 - capitulacao de mineradores em curso" {
        It "retorna signal BEARISH quando MA30 esta abaixo de MA60" {
            Mock Invoke-RestMethod {
                # 60 semanas altas, depois 5 semanas baixas
                # MA5 (last 5) = 300e18 | MA10 (last 10) = media(5*600e18 + 5*300e18) = 450e18
                # MA5 < MA10 -> BEARISH
                $weeks = @()
                for ($i = 0; $i -lt 60; $i++) { $weeks += [PSCustomObject]@{ avgHashrate = 600e18 } }
                for ($i = 0; $i -lt 5;  $i++) { $weeks += [PSCustomObject]@{ avgHashrate = 300e18 } }
                [PSCustomObject]@{ hashrates = $weeks }
            }
            $r = Get-MempoolHashRibbon -Market "BTCUSDT"
            $r.signal      | Should Be "BEARISH"
            $r.hashRate30d | Should BeLessThan $r.hashRate60d
        }
    }

    Context "MA30 e MA60 dentro de 2 pct" {
        It "retorna signal NEUTRO quando MAs sao aproximadamente iguais" {
            Mock Invoke-RestMethod {
                $weeks = @()
                for ($i = 0; $i -lt 65; $i++) { $weeks += [PSCustomObject]@{ avgHashrate = 500e18 } }
                [PSCustomObject]@{ hashrates = $weeks }
            }
            $r = Get-MempoolHashRibbon -Market "BTCUSDT"
            $r.signal | Should Be "NEUTRO"
        }
    }

    Context "market nao-BTC" {
        It "retorna null para ETHUSDT (nao usa PoW BTC)" {
            $r = Get-MempoolHashRibbon -Market "ETHUSDT"
            $r | Should BeNullOrEmpty
        }
    }

    Context "API indisponivel" {
        It "retorna null sem lancar excecao" {
            Mock Invoke-RestMethod { throw "timeout" }
            $r = Get-MempoolHashRibbon -Market "BTCUSDT"
            $r | Should BeNullOrEmpty
        }
    }

    Context "historico insuficiente" {
        It "retorna null quando menos de 10 semanas disponiveis" {
            Mock Invoke-RestMethod {
                $weeks = @()
                for ($i = 0; $i -lt 5; $i++) { $weeks += [PSCustomObject]@{ avgHashrate = 500e18 } }
                [PSCustomObject]@{ hashrates = $weeks }
            }
            $r = Get-MempoolHashRibbon -Market "BTCUSDT"
            $r | Should BeNullOrEmpty
        }
    }

    Context "estrutura do objeto retornado" {
        It "retorna todas as propriedades esperadas" {
            Mock Invoke-RestMethod {
                $weeks = @()
                for ($i = 0; $i -lt 65; $i++) { $weeks += [PSCustomObject]@{ avgHashrate = 500e18 } }
                [PSCustomObject]@{ hashrates = $weeks }
            }
            $r     = Get-MempoolHashRibbon -Market "BTCUSDT"
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "signal")      | Should Be $true
            ($names -contains "hashRate30d") | Should Be $true
            ($names -contains "hashRate60d") | Should Be $true
            ($names -contains "ribbonPct")   | Should Be $true
        }
    }
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Get-EtherscanConcentration
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Describe "Get-EtherscanConcentration" {

    Context "top 10 holders com concentracao critica acima de 80 pct" {
        It "retorna concentrationRisk CRITICAL" {
            Mock Invoke-RestMethod {
                [PSCustomObject]@{
                    status = "1"
                    result = @(
                        [PSCustomObject]@{ TokenHolderQuantity = "850000" },
                        [PSCustomObject]@{ TokenHolderQuantity = "50000"  },
                        [PSCustomObject]@{ TokenHolderQuantity = "10000"  }
                    )
                }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -match "tokensupply" } {
                [PSCustomObject]@{ status = "1"; result = "1000000" }
            }
            $r = Get-EtherscanConcentration -Market "UNIUSDT"
            $r                   | Should Not BeNullOrEmpty
            $r.concentrationRisk | Should Be "CRITICAL"
            $r.top10Pct          | Should BeGreaterThan 80
        }
    }

    Context "top 10 holders com concentracao alta entre 50 e 80 pct" {
        It "retorna concentrationRisk HIGH" {
            Mock Invoke-RestMethod {
                [PSCustomObject]@{
                    status = "1"
                    result = @(
                        [PSCustomObject]@{ TokenHolderQuantity = "600000" },
                        [PSCustomObject]@{ TokenHolderQuantity = "50000"  }
                    )
                }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -match "tokensupply" } {
                [PSCustomObject]@{ status = "1"; result = "1000000" }
            }
            $r = Get-EtherscanConcentration -Market "UNIUSDT"
            $r.concentrationRisk | Should Be "HIGH"
            $r.top10Pct          | Should BeGreaterThan 50
            $r.top10Pct          | Should BeLessThan 80
        }
    }

    Context "top 10 holders bem distribuidos abaixo de 50 pct" {
        It "retorna concentrationRisk NORMAL" {
            Mock Invoke-RestMethod {
                [PSCustomObject]@{
                    status = "1"
                    result = @(
                        [PSCustomObject]@{ TokenHolderQuantity = "30000" },
                        [PSCustomObject]@{ TokenHolderQuantity = "20000" }
                    )
                }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -match "tokensupply" } {
                [PSCustomObject]@{ status = "1"; result = "1000000" }
            }
            $r = Get-EtherscanConcentration -Market "UNIUSDT"
            $r.concentrationRisk | Should Be "NORMAL"
            $r.top10Pct          | Should BeLessThan 50
        }
    }

    Context "ativos nao-ERC20" {
        It "retorna null para BTC (modelo UTXO)" {
            $r = Get-EtherscanConcentration -Market "BTCUSDT"
            $r | Should BeNullOrEmpty
        }

        It "retorna null para SOL (nao ERC-20)" {
            $r = Get-EtherscanConcentration -Market "SOLUSDT"
            $r | Should BeNullOrEmpty
        }

        It "retorna null para ETH (ativo nativo, nao token)" {
            $r = Get-EtherscanConcentration -Market "ETHUSDT"
            $r | Should BeNullOrEmpty
        }
    }

    Context "token sem contrato mapeado" {
        It "retorna null para token desconhecido" {
            $r = Get-EtherscanConcentration -Market "XYZUSDT"
            $r | Should BeNullOrEmpty
        }
    }

    Context "API Etherscan indisponivel" {
        It "retorna null sem lancar excecao" {
            Mock Invoke-RestMethod { throw "API rate limit exceeded" }
            $r = Get-EtherscanConcentration -Market "UNIUSDT"
            $r | Should BeNullOrEmpty
        }
    }

    Context "Etherscan retorna status de erro" {
        It "retorna null quando status diferente de 1" {
            Mock Invoke-RestMethod {
                [PSCustomObject]@{ status = "0"; message = "NOTOK"; result = "Max rate limit reached" }
            }
            $r = Get-EtherscanConcentration -Market "UNIUSDT"
            $r | Should BeNullOrEmpty
        }
    }

    Context "estrutura do objeto retornado" {
        It "retorna todas as propriedades esperadas" {
            Mock Invoke-RestMethod {
                [PSCustomObject]@{
                    status = "1"
                    result = @( [PSCustomObject]@{ TokenHolderQuantity = "200000" } )
                }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -match "tokensupply" } {
                [PSCustomObject]@{ status = "1"; result = "1000000" }
            }
            $r     = Get-EtherscanConcentration -Market "UNIUSDT"
            $names = @($r.PSObject.Properties.Name)
            ($names -contains "concentrationRisk") | Should Be $true
            ($names -contains "top10Pct")          | Should Be $true
            ($names -contains "holderCount")       | Should Be $true
            ($names -contains "marketLabel")       | Should Be $true
        }
    }
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#  Resolve-ChainCoinId
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Describe "Resolve-ChainCoinId" {

    Context "mercados conhecidos do mapa" {
        It "resolve BTC para bitcoin" {
            Resolve-ChainCoinId "BTCUSDT" | Should Be "bitcoin"
        }
        It "resolve ETH para ethereum" {
            Resolve-ChainCoinId "ETHUSDT" | Should Be "ethereum"
        }
        It "resolve SOL para solana" {
            Resolve-ChainCoinId "SOLUSDT" | Should Be "solana"
        }
        It "resolve LINK para chainlink" {
            Resolve-ChainCoinId "LINKUSDT" | Should Be "chainlink"
        }
    }

    Context "mercado desconhecido" {
        It "retorna base em lowercase para token sem mapeamento" {
            Resolve-ChainCoinId "XYZUSDT" | Should Be "xyz"
        }
        It "funciona sem sufixo USDT" {
            Resolve-ChainCoinId "BTC" | Should Be "bitcoin"
        }
    }
}
