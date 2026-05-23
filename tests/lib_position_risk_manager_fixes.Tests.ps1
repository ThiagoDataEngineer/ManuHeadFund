# tests/lib_position_risk_manager_fixes.Tests.ps1
# TDD: Testes para correcoes do Risk Manager

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_position_risk_manager.ps1"

Describe "Risk Manager - Formatacao e NaN Fixes" {
    
    Context "Invoke-PositionRiskScan - Formatacao de Posicoes Abertas" {
        
        It "Deve exibir numero correto de posicoes abertas" {
            # Mock CoinEx-GetPendingPositions
            Mock CoinEx-GetPendingPositions {
                return @(
                    [PSCustomObject]@{
                        market = "BNBUSDT"
                        side = "long"
                        avg_entry_price = "647.06"
                        stop_loss_price = "627.82"
                        take_profit_price = "679.60"
                        liq_price = "0"
                    }
                )
            }
            
            # Mock funcoes internas
            Mock Update-TrailingStop { return [PSCustomObject]@{ success = $false } }
            Mock Adjust-LeverageByVolatility { return [PSCustomObject]@{ success = $false } }
            Mock Protect-FromLiquidation { return [PSCustomObject]@{ success = $false } }
            
            # Capturar output
            $output = Invoke-PositionRiskScan 6>&1 | Out-String
            
            # Verificar que exibe "Posicoes abertas: 1" (com numero)
            $output | Should Match "Posicoes abertas:\s+1"
        }
        
        It "Deve retornar positions_scanned correto" {
            Mock CoinEx-GetPendingPositions {
                return @(
                    [PSCustomObject]@{ market = "BNBUSDT"; side = "long"; avg_entry_price = "647.06" },
                    [PSCustomObject]@{ market = "BTCUSDT"; side = "long"; avg_entry_price = "95000" }
                )
            }
            
            Mock Update-TrailingStop { return [PSCustomObject]@{ success = $false } }
            Mock Adjust-LeverageByVolatility { return [PSCustomObject]@{ success = $false } }
            Mock Protect-FromLiquidation { return [PSCustomObject]@{ success = $false } }
            
            $result = Invoke-PositionRiskScan
            
            $result.positions_scanned | Should Be 2
        }
    }
    
    Context "Protect-FromLiquidation - NaN Fix" {
        
        It "Deve tratar liq_price = 0 sem gerar NaN" {
            Mock CoinEx-GetPendingPositions {
                return @(
                    [PSCustomObject]@{
                        market = "BNBUSDT"
                        side = "long"
                        avg_entry_price = "647.06"
                        liq_price = "0"  # Problema: liq_price = 0
                    }
                )
            }
            
            Mock CoinEx-Get {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ last = "647.50" }
                }
            }
            
            # Capturar output
            $output = Protect-FromLiquidation -Market "BNBUSDT" 6>&1 | Out-String
            
            # Nao deve conter "NaN"
            $output | Should Not Match "NaN"
            
            # Deve indicar que liq_price nao esta disponivel
            $output | Should Match "liq_price nao disponivel|sem liq_price"
        }
        
        It "Deve retornar success=false quando liq_price = 0" {
            Mock CoinEx-GetPendingPositions {
                return @(
                    [PSCustomObject]@{
                        market = "BNBUSDT"
                        side = "long"
                        avg_entry_price = "647.06"
                        liq_price = "0"
                    }
                )
            }
            
            Mock CoinEx-Get {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ last = "647.50" }
                }
            }
            
            $result = Protect-FromLiquidation -Market "BNBUSDT"
            
            $result.success | Should Be $false
            $result.reason | Should Be "liq_price_unavailable"
        }
        
        It "Deve calcular distancia corretamente quando liq_price > 0" {
            Mock CoinEx-GetPendingPositions {
                return @(
                    [PSCustomObject]@{
                        market = "BNBUSDT"
                        side = "long"
                        avg_entry_price = "647.06"
                        liq_price = "500.00"  # Liq price valido
                    }
                )
            }
            
            Mock CoinEx-Get {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ last = "647.50" }
                }
            }
            
            $result = Protect-FromLiquidation -Market "BNBUSDT"
            
            # Distancia = ((647.50 - 500) / 647.50) * 100 = 22.78%
            $result.distance_pct | Should BeGreaterThan 20
            $result.distance_pct | Should BeLessThan 25
        }
    }
    
    Context "Update-TrailingStop - Posicao Detection Fix" {
        
        It "Deve detectar posicao corretamente" {
            Mock CoinEx-GetPendingPositions {
                return @(
                    [PSCustomObject]@{
                        market = "BNBUSDT"
                        side = "long"
                        avg_entry_price = "647.06"
                        stop_loss_price = "627.82"
                    }
                )
            }
            
            Mock CoinEx-Get {
                return [PSCustomObject]@{
                    code = 0
                    data = [PSCustomObject]@{ last = "653.00" }  # +0.92% lucro
                }
            }
            
            Mock CoinEx-GetFuturesCandles {
                # Retornar candles mockados
                $candles = @()
                for ($i = 0; $i -lt 15; $i++) {
                    $candles += [PSCustomObject]@{
                        high = "650"
                        low = "645"
                        close = "647"
                    }
                }
                return $candles
            }
            
            $result = Update-TrailingStop -Market "BNBUSDT" -MinProfitPct 0.5
            
            # Nao deve retornar "no_position"
            $result.reason | Should Not Be "no_position"
        }
    }
}

Write-Host "`n=== EXECUTANDO TESTES ===" -ForegroundColor Cyan
Invoke-Pester -Path $PSCommandPath -Output Detailed
