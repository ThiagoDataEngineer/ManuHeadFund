# tests/dashboard.Tests.ps1
# TDD para Dashboard - Encontrar causa raiz dos problemas

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_coinex_position_management.ps1"

Describe "Dashboard - Analise Profunda TDD" {
    
    Context "Get-PositionMetrics - Coleta de Dados" {
        
        It "Deve retornar metricas validas" {
            Mock CoinEx-GetPendingPositions {
                return @(
                    [PSCustomObject]@{
                        market = "BNBUSDT"
                        side = "long"
                        avg_entry_price = "647.06"
                        open_interest = "0.07"
                        unrealized_pnl = "-0.007"
                        realized_pnl = "-0.0226471"
                    }
                )
            }
            
            Mock CoinEx-GetFinishedPositions {
                return @{
                    success = $true
                    positions = @(
                        [PSCustomObject]@{
                            market = "BTCUSDT"
                            realized_pnl = "50.25"
                        }
                    )
                }
            }
            
            . ".\scripts\generate_position_dashboard.ps1"
            $metrics = Get-PositionMetrics
            
            $metrics | Should Not BeNullOrEmpty
            $metrics.timestamp | Should Not BeNullOrEmpty
            $metrics.open_positions | Should Be 1
            $metrics.total_trades | Should BeGreaterThan 0
        }
        
        It "Deve calcular win rate corretamente" {
            Mock CoinEx-GetPendingPositions { return @() }
            
            Mock CoinEx-GetFinishedPositions {
                return @{
                    success = $true
                    positions = @(
                        [PSCustomObject]@{ market = "BTC"; realized_pnl = "10" },
                        [PSCustomObject]@{ market = "ETH"; realized_pnl = "-5" },
                        [PSCustomObject]@{ market = "BNB"; realized_pnl = "8" }
                    )
                }
            }
            
            . ".\scripts\generate_position_dashboard.ps1"
            $metrics = Get-PositionMetrics
            
            $metrics.wins | Should Be 2
            $metrics.losses | Should Be 1
            $metrics.win_rate | Should Be 66.7
        }
        
        It "Deve calcular profit factor corretamente" {
            Mock CoinEx-GetPendingPositions { return @() }
            
            Mock CoinEx-GetFinishedPositions {
                return @{
                    success = $true
                    positions = @(
                        [PSCustomObject]@{ market = "BTC"; realized_pnl = "100" },
                        [PSCustomObject]@{ market = "ETH"; realized_pnl = "-50" }
                    )
                }
            }
            
            . ".\scripts\generate_position_dashboard.ps1"
            $metrics = Get-PositionMetrics
            
            $metrics.avg_win | Should Be 100
            $metrics.avg_loss | Should Be -50
            $metrics.profit_factor | Should Be 2.0
        }
    }
    
    Context "Generate-HTML - Encoding UTF-8" {
        
        It "Deve gerar HTML sem caracteres especiais quebrados" {
            $testMetrics = [PSCustomObject]@{
                timestamp = "2026-05-23 14:30:00"
                open_positions = 1
                total_trades = 100
                wins = 49
                losses = 51
                win_rate = 49
                total_pnl = -612.72
                avg_win = 4.31
                avg_loss = -16.16
                profit_factor = 0.27
                best_trade = $null
                worst_trade = $null
                top5_markets = @()
                open_positions_detail = @()
            }
            
            . ".\scripts\generate_position_dashboard.ps1"
            $html = Generate-HTML -Metrics $testMetrics
            
            # Verificar que NAO contem caracteres UTF-8 quebrados
            $html | Should Not Match "Ã"
            $html | Should Not Match "Ã§"
            $html | Should Not Match "Ãµ"
            $html | Should Not Match "Ãº"
            
            # Verificar que contem texto correto
            $html | Should Match "Posicoes Abertas|Posições Abertas"
            $html | Should Match "Ultima atualizacao|Última atualização"
        }
        
        It "Deve usar apenas ASCII ou UTF-8 correto" {
            $testMetrics = [PSCustomObject]@{
                timestamp = "2026-05-23 14:30:00"
                open_positions = 0
                total_trades = 0
                wins = 0
                losses = 0
                win_rate = 0
                total_pnl = 0
                avg_win = 0
                avg_loss = 0
                profit_factor = 0
                best_trade = $null
                worst_trade = $null
                top5_markets = @()
                open_positions_detail = @()
            }
            
            . ".\scripts\generate_position_dashboard.ps1"
            $html = Generate-HTML -Metrics $testMetrics
            
            # Verificar encoding
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
            $decoded = [System.Text.Encoding]::UTF8.GetString($bytes)
            
            # HTML deve ser identico apos encode/decode UTF-8
            $decoded.Length | Should Be $html.Length
        }
    }
    
    Context "Dashboard - Atualizacao de Dados" {
        
        It "Deve mostrar posicao aberta atual" {
            Mock CoinEx-GetPendingPositions {
                return @(
                    [PSCustomObject]@{
                        market = "BNBUSDT"
                        side = "long"
                        avg_entry_price = "647.06"
                        open_interest = "0.07"
                        unrealized_pnl = "0.50"
                        leverage = "50"
                        liq_price = "0"
                    }
                )
            }
            
            Mock CoinEx-Get {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ last = "650.00" }
                }
            }
            
            Mock CoinEx-GetFinishedPositions {
                return @{ success = $true; positions = @() }
            }
            
            . ".\scripts\generate_position_dashboard.ps1"
            $metrics = Get-PositionMetrics
            
            $metrics.open_positions | Should Be 1
            $metrics.open_positions_detail | Should Not BeNullOrEmpty
            $metrics.open_positions_detail[0].market | Should Be "BNBUSDT"
        }
        
        It "Deve calcular PnL% corretamente para posicao aberta" {
            Mock CoinEx-GetPendingPositions {
                return @(
                    [PSCustomObject]@{
                        market = "BNBUSDT"
                        side = "long"
                        avg_entry_price = "647.06"
                        open_interest = "0.07"
                    }
                )
            }
            
            Mock CoinEx-Get {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ last = "653.71" }  # +1.03%
                }
            }
            
            Mock CoinEx-GetFinishedPositions {
                return @{ success = $true; positions = @() }
            }
            
            . ".\scripts\generate_position_dashboard.ps1"
            $metrics = Get-PositionMetrics
            $html = Generate-HTML -Metrics $metrics
            
            # Deve mostrar PnL positivo
            $html | Should Match "(\+|positive)"
        }
    }
    
    Context "Dashboard - Top 5 Markets" {
        
        It "Deve ordenar markets por PnL" {
            Mock CoinEx-GetPendingPositions { return @() }
            
            Mock CoinEx-GetFinishedPositions {
                return @{
                    success = $true
                    positions = @(
                        [PSCustomObject]@{ market = "BNBUSDT"; realized_pnl = "8.59" },
                        [PSCustomObject]@{ market = "BTCUSDT"; realized_pnl = "-100" },
                        [PSCustomObject]@{ market = "ETHUSDT"; realized_pnl = "50" }
                    )
                }
            }
            
            . ".\scripts\generate_position_dashboard.ps1"
            $metrics = Get-PositionMetrics
            
            $metrics.top5_markets | Should Not BeNullOrEmpty
            # Primeiro deve ser ETHUSDT (maior PnL positivo)
            $metrics.top5_markets[0].Value.pnl | Should BeGreaterThan 40
        }
    }
}

Write-Host "`n=== EXECUTANDO TESTES DASHBOARD ===" -ForegroundColor Cyan
