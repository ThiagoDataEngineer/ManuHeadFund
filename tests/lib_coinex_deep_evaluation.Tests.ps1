# tests/lib_coinex_deep_evaluation.Tests.ps1
# Avaliacao Profunda de TODAS as funcoes CoinEx com TDD

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_coinex_position_management.ps1"

Describe "CoinEx API - Avaliacao Profunda" {
    
    # ========================================================================
    # CATEGORIA 1: Autenticacao e Assinatura
    # ========================================================================
    
    Context "Autenticacao - CoinEx-Sign e CoinEx-Headers" {
        
        It "CoinEx-Sign deve gerar assinatura valida" {
            $method = "GET"
            $path = "/v2/assets/futures/balance"
            $body = ""
            $secret = "test-secret-key"
            
            $result = CoinEx-Sign $method $path $body $secret
            
            $result | Should Not BeNullOrEmpty
            $result.sig | Should Not BeNullOrEmpty
            $result.ts | Should Not BeNullOrEmpty
            $result.sig.Length | Should BeGreaterThan 40
        }
        
        It "CoinEx-Headers deve incluir todos os campos obrigatorios" {
            $method = "GET"
            $path = "/v2/assets/futures/balance"
            $body = ""
            $accessId = "test-access-id"
            $secretKey = "test-secret-key"
            
            $headers = CoinEx-Headers $method $path $body $accessId $secretKey
            
            $headers.ContainsKey("X-COINEX-KEY") | Should Be $true
            $headers.ContainsKey("X-COINEX-SIGN") | Should Be $true
            $headers.ContainsKey("X-COINEX-TIMESTAMP") | Should Be $true
            $headers["X-COINEX-KEY"] | Should Be $accessId
        }
    }
    
    # ========================================================================
    # CATEGORIA 2: Endpoints Publicos (Sem Autenticacao)
    # ========================================================================
    
    Context "Endpoints Publicos - Market Data" {
        
        It "CoinEx-GetFuturesCandles deve retornar candles validos" {
            Mock Invoke-RestMethod {
                param($Uri, $Method, $ErrorAction)
                return [PSCustomObject]@{
                    code = 0
                    data = @(
                        [PSCustomObject]@{
                            created_at = "1779555408009"
                            open = "100"
                            high = "105"
                            low = "95"
                            close = "102"
                            volume = "1000"
                        }
                    )
                }
            } -Verifiable
            
            $candles = CoinEx-GetFuturesCandles -market "BTCUSDT" -period "1hour" -limit 10
            
            $candles | Should Not BeNullOrEmpty
            $candles | Should BeOfType [PSCustomObject]
            if ($candles.Count) {
                $candles.Count | Should BeGreaterThan 0
                $candles[0].open | Should Be 100
            } else {
                # Se retornou objeto unico, nao array
                $candles.open | Should Be 100
            }
            
            Assert-VerifiableMocks
        }
        
        It "CoinEx-GetTicker deve retornar ticker valido" {
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{
                        last = "95000"
                        vol = "1000"
                        updated_at = 1779555408009
                    }
                }
            }
            
            $ticker = CoinEx-GetTicker -market "BTCUSDT"
            
            $ticker | Should Not BeNullOrEmpty
            $ticker.last | Should Be "95000"
        }
        
        It "CoinEx-GetTickerFresh deve validar freshness" {
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{
                        last = "95000"
                        vol = "1000"
                        updated_at = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 1000)
                    }
                }
            }
            
            $freshTicker = CoinEx-GetTickerFresh -market "BTCUSDT"
            
            $freshTicker | Should Not BeNullOrEmpty
            $freshTicker.ticker | Should Not BeNullOrEmpty
            $freshTicker.ticker.last | Should Be "95000"
            $freshTicker.is_fresh | Should Be $true
        }
        
        It "CoinEx-GetDepth deve retornar order book" {
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{
                        asks = @(@("95100", "1.5"))
                        bids = @(@("94900", "2.0"))
                    }
                }
            }
            
            $depth = CoinEx-GetDepth -market "BTCUSDT" -limit 20
            
            $depth | Should Not BeNullOrEmpty
            $depth.asks | Should Not BeNullOrEmpty
            $depth.bids | Should Not BeNullOrEmpty
        }
        
        It "CoinEx-GetFuturesMarkets deve retornar lista de mercados" {
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    code = 0
                    data = @(
                        [PSCustomObject]@{ market = "BTCUSDT"; min_amount = "0.001" },
                        [PSCustomObject]@{ market = "ETHUSDT"; min_amount = "0.01" }
                    )
                }
            }
            
            $markets = CoinEx-GetFuturesMarkets
            
            $markets | Should Not BeNullOrEmpty
            $markets.Count | Should Be 2
            $markets[0].market | Should Be "BTCUSDT"
        }
    }
    
    # ========================================================================
    # CATEGORIA 3: Balance e Capital
    # ========================================================================
    
    Context "Balance e Capital" {
        
        It "CoinEx-GetBalance deve retornar balance valido" {
            Mock CoinEx-Get {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{
                        USDT = [PSCustomObject]@{
                            available = "1000.50"
                            frozen = "50.25"
                        }
                    }
                }
            }
            
            $balance = CoinEx-GetBalance
            
            $balance | Should Not BeNullOrEmpty
            $balance.USDT | Should Not BeNullOrEmpty
        }
        
        It "CoinEx-GetFuturesCapitalUSDT deve retornar capital disponivel" {
            # Garantir que credenciais estao configuradas
            $script:COINEX_ACCESS_ID = "test-id"
            $script:COINEX_SECRET_KEY = "test-key"
            
            Mock CoinEx-Get {
                return [PSCustomObject]@{
                    code = 0
                    data = @(
                        [PSCustomObject]@{
                            ccy = "USDT"
                            available = "2500.75"
                        }
                    )
                }
            }
            
            $capital = CoinEx-GetFuturesCapitalUSDT
            
            $capital | Should BeGreaterThan 0
            $capital | Should Be 2500.75
        }
        
        It "CoinEx-GetSpotCapitalUSDT deve retornar capital spot" {
            # Garantir que credenciais estao configuradas
            $script:COINEX_ACCESS_ID = "test-id"
            $script:COINEX_SECRET_KEY = "test-key"
            
            Mock CoinEx-Get {
                return [PSCustomObject]@{
                    code = 0
                    data = @(
                        [PSCustomObject]@{
                            ccy = "USDT"
                            available = "1500.25"
                        }
                    )
                }
            }
            
            $capital = CoinEx-GetSpotCapitalUSDT
            
            $capital | Should BeGreaterThan 0
            $capital | Should Be 1500.25
        }
    }
    
    # ========================================================================
    # CATEGORIA 4: Posicoes
    # ========================================================================
    
    Context "Gestao de Posicoes" {
        
        It "CoinEx-GetPosition deve retornar posicao especifica" {
            Mock CoinEx-Get {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{
                        market = "BTCUSDT"
                        side = "long"
                        avg_entry_price = "95000"
                        open_interest = "0.1"
                    }
                }
            }
            
            $position = CoinEx-GetPosition -market "BTCUSDT"
            
            $position | Should Not BeNullOrEmpty
            $position.market | Should Be "BTCUSDT"
            $position.side | Should Be "long"
        }
        
        It "CoinEx-GetPendingPositions deve retornar todas as posicoes" {
            Mock CoinEx-Get {
                return [PSCustomObject]@{
                    code = 0
                    data = @(
                        [PSCustomObject]@{ market = "BTCUSDT"; side = "long" },
                        [PSCustomObject]@{ market = "ETHUSDT"; side = "short" }
                    )
                }
            }
            
            $positions = CoinEx-GetPendingPositions
            
            $positions | Should Not BeNullOrEmpty
            $positions.Count | Should Be 2
        }
        
        It "CoinEx-GetFinishedPositions deve retornar historico" {
            Mock CoinEx-Get {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{
                        records = @(
                            [PSCustomObject]@{
                                market = "BTCUSDT"
                                realized_pnl = "50.25"
                                finished_type = "market"
                            }
                        )
                    }
                }
            }
            
            $result = CoinEx-GetFinishedPositions -Limit 10
            
            $result.success | Should Be $true
            $result.positions | Should Not BeNullOrEmpty
        }
    }
    
    # ========================================================================
    # CATEGORIA 5: Ordens
    # ========================================================================
    
    Context "Gestao de Ordens" {
        
        It "CoinEx-PlaceOrder deve criar ordem com parametros corretos" {
            Mock CoinEx-Post {
                param($path, $bodyObj)
                
                $bodyObj.market | Should Be "BTCUSDT"
                $bodyObj.side | Should Be "buy"
                $bodyObj.type | Should Be "market"
                $bodyObj.amount | Should Match "^\d+\.?\d*$"
                
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ order_id = "12345" }
                }
            }
            
            $order = CoinEx-PlaceOrder "BTCUSDT" "buy" "market" 0.01
            
            $order | Should Not BeNullOrEmpty
            $order.order_id | Should Be "12345"
        }
        
        It "CoinEx-PlaceOrder deve incluir stop loss quando fornecido" {
            Mock CoinEx-Post {
                param($path, $bodyObj)
                
                $bodyObj.stop_loss_price | Should Be "90000"
                $bodyObj.stop_loss_type | Should Be "mark_price"
                
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ order_id = "12345" }
                }
            }
            
            $order = CoinEx-PlaceOrder "BTCUSDT" "buy" "market" 0.01 $null 90000 $null
            
            Assert-MockCalled CoinEx-Post -Times 1
        }
        
        It "CoinEx-CancelOrder deve cancelar ordem por order_id" {
            Mock CoinEx-Post {
                param($path, $bodyObj)
                
                $bodyObj.market | Should Be "BTCUSDT"
                $bodyObj.order_id | Should Be "12345"
                
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ order_id = "12345" }
                }
            }
            
            $result = CoinEx-CancelOrder -Market "BTCUSDT" -OrderId "12345"
            
            $result.success | Should Be $true
        }
    }
    
    # ========================================================================
    # CATEGORIA 6: Stop Loss e Take Profit
    # ========================================================================
    
    Context "Stop Loss e Take Profit" {
        
        It "CoinEx-ModifyPositionStopLoss deve atualizar SL" {
            # 2026-07-23 FIX: endpoint real e set-position-stop-loss (fix
            # 2026-06-11, modify-* nao existe/retornava 4004 -- ver
            # knowledge/COINEX_REFERENCE.md:421). Teste nunca atualizado.
            Mock CoinEx-Post {
                param($path, $bodyObj)

                $path | Should Be "/v2/futures/set-position-stop-loss"
                $bodyObj.market | Should Be "BTCUSDT"
                $bodyObj.stop_loss_price | Should Be "90000"
                
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ stop_loss_price = "90000" }
                }
            }
            
            $result = CoinEx-ModifyPositionStopLoss -Market "BTCUSDT" -Price 90000
            
            $result.success | Should Be $true
            $result.stop_loss_price | Should Be "90000"
        }
        
        It "CoinEx-ModifyPositionTakeProfit deve atualizar TP" {
            Mock CoinEx-Post {
                param($path, $bodyObj)
                
                $path | Should Be "/v2/futures/modify-position-take-profit"
                $bodyObj.take_profit_price | Should Be "105000"
                
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ take_profit_price = "105000" }
                }
            }
            
            $result = CoinEx-ModifyPositionTakeProfit -Market "BTCUSDT" -Price 105000
            
            $result.success | Should Be $true
        }
        
        It "CoinEx-SetStopLoss deve criar SL inicial" {
            Mock CoinEx-Post {
                param($path, $bodyObj)
                
                $path | Should Be "/v2/futures/set-position-stop-loss"
                
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ stop_loss_price = "90000" }
                }
            }
            
            $result = CoinEx-SetStopLoss "BTCUSDT" 90000
            
            $result | Should Not BeNullOrEmpty
        }
    }
    
    # ========================================================================
    # CATEGORIA 7: Leverage e Margin
    # ========================================================================
    
    Context "Leverage e Margin" {
        
        It "CoinEx-AdjustPositionLeverage deve ajustar leverage" {
            Mock CoinEx-Post {
                param($path, $bodyObj)
                
                $path | Should Be "/v2/futures/adjust-position-leverage"
                $bodyObj.leverage | Should Be "10"
                
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ leverage = "10" }
                }
            }
            
            $result = CoinEx-AdjustPositionLeverage -Market "BTCUSDT" -Leverage 10
            
            $result.success | Should Be $true
        }
        
        It "CoinEx-AdjustPositionMargin deve adicionar margin" {
            Mock CoinEx-Post {
                param($path, $bodyObj)
                
                $path | Should Be "/v2/futures/adjust-position-margin"
                $bodyObj.amount | Should Be "50"
                $bodyObj.type | Should Be "add"
                
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ amount = "50" }
                }
            }
            
            $result = CoinEx-AdjustPositionMargin -Market "BTCUSDT" -Amount 50 -Type "add"
            
            $result.success | Should Be $true
        }
    }
    
    # ========================================================================
    # CATEGORIA 8: Market Info e Fees
    # ========================================================================
    
    Context "Market Info e Fees" {
        
        It "CoinEx-GetMarketInfo deve retornar specs do mercado" {
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{
                        market = "BTCUSDT"
                        min_amount = "0.001"
                        max_leverage = "100"
                    }
                }
            }
            
            $info = CoinEx-GetMarketInfo -market "BTCUSDT"
            
            $info | Should Not BeNullOrEmpty
            $info.market | Should Be "BTCUSDT"
        }
        
        It "CoinEx-GetFundingRate deve retornar funding rate" {
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    code = 0
                    data = @(
                        [PSCustomObject]@{
                            market = "BTCUSDT"
                            latest_funding_rate = "0.0001"
                        }
                    )
                }
            }
            
            $funding = CoinEx-GetFundingRate -market "BTCUSDT"
            
            $funding | Should Not BeNullOrEmpty
            $funding | Should Be 0.0001
        }
        
        It "CoinEx-GetFeeContext deve retornar contexto completo de fees" {
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    code = 0
                    data = @(
                        [PSCustomObject]@{
                            market = "BTCUSDT"
                            latest_funding_rate = "0.0001"
                        }
                    )
                }
            }
            
            $feeContext = CoinEx-GetFeeContext -market "BTCUSDT"
            
            $feeContext | Should Not BeNullOrEmpty
            $feeContext.makerRate | Should Not BeNullOrEmpty
            $feeContext.takerRate | Should Not BeNullOrEmpty
            $feeContext.market | Should Be "BTCUSDT"
        }
    }
    
    # ========================================================================
    # CATEGORIA 9: Validacao de Parametros
    # ========================================================================
    
    Context "Validacao de Parametros" {
        
        It "CoinEx-PlaceOrder deve usar InvariantCulture para decimais" {
            Mock CoinEx-Post {
                param($path, $bodyObj)
                
                # Verificar que usa ponto, nao virgula
                $bodyObj.amount | Should Match "^\d+\.\d+$"
                $bodyObj.amount | Should Not Match ","
                
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ order_id = "12345" }
                }
            }
            
            $order = CoinEx-PlaceOrder "BTCUSDT" "buy" "market" 0.015
            
            Assert-MockCalled CoinEx-Post -Times 1
        }
        
        It "CoinEx-PlaceOrder deve incluir stp_mode por padrao" {
            Mock CoinEx-Post {
                param($path, $bodyObj)
                
                $bodyObj.stp_mode | Should Be "ct"
                
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ order_id = "12345" }
                }
            }
            
            $order = CoinEx-PlaceOrder "BTCUSDT" "buy" "limit" 0.01 95000
            
            Assert-MockCalled CoinEx-Post -Times 1
        }
    }
}

Write-Host "`n=== EXECUTANDO AVALIACAO PROFUNDA ===" -ForegroundColor Cyan
Write-Host "Total de categorias: 9" -ForegroundColor Yellow
Write-Host "Total de testes: ~40" -ForegroundColor Yellow
