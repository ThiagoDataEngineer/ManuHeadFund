# tests\lib_order_validation.Tests.ps1
# TDD Tests para lib_order_validation.ps1
# 2026-05-24
# Compatible with Pester 3.x

# Load dependencies
. "$PSScriptRoot\..\agents\config.ps1"
. "$PSScriptRoot\..\agents\lib_coinex.ps1"
. "$PSScriptRoot\..\agents\lib_coinex_position_management.ps1"
. "$PSScriptRoot\..\agents\lib_order_validation.ps1"

Describe "lib_order_validation - Test-PositionHasStopLoss" {
    
    Context "Quando posicao tem stop loss configurado" {
        Mock CoinEx-GetPendingPositions {
            return @([PSCustomObject]@{
                market = "TESTUSDT"
                side = "long"
                open_interest = "100"
                avg_entry_price = "1.5000"
                latest_price = "1.5500"
                stop_loss_price = "1.4000"
                take_profit_price = "1.6000"
                unrealized_pnl = "5.00"
                unrealized_pnl_rate = "3.33"
            })
        }
        
        It "Deve retornar has_stop_loss = true" {
            $result = Test-PositionHasStopLoss -Market "TESTUSDT"
            
            $result.success | Should Be $true
            $result.has_stop_loss | Should Be $true
            $result.stop_loss_price | Should Be 1.4000
            $result.has_take_profit | Should Be $true
            $result.take_profit_price | Should Be 1.6000
        }
    }
    
    Context "Quando posicao NAO tem stop loss" {
        Mock CoinEx-GetPendingPositions {
            return @([PSCustomObject]@{
                market = "NOSTOPUSDT"
                side = "long"
                open_interest = "100"
                avg_entry_price = "2.0000"
                latest_price = "2.0500"
                stop_loss_price = "0"
                take_profit_price = "0"
                unrealized_pnl = "2.50"
                unrealized_pnl_rate = "2.50"
            })
        }
        
        It "Deve retornar has_stop_loss = false" {
            $result = Test-PositionHasStopLoss -Market "NOSTOPUSDT"
            
            $result.success | Should Be $true
            $result.has_stop_loss | Should Be $false
            $result.stop_loss_price | Should Be 0
            $result.has_take_profit | Should Be $false
            $result.take_profit_price | Should Be 0
        }
    }
    
    Context "Quando posicao nao existe" {
        Mock CoinEx-GetPendingPositions { return @() }
        
        It "Deve retornar success = false" {
            $result = Test-PositionHasStopLoss -Market "NOTFOUNDUSDT"
            
            $result.success | Should Be $false
            $result.error | Should Be "Position not found"
            $result.has_stop_loss | Should Be $false
        }
    }
}

Describe "lib_order_validation - Set-PositionStopLossFallback" {
    
    Context "Quando set-position-stop-loss funciona" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{
                code = 0
                message = "Success"
                data = [PSCustomObject]@{
                    market = "TESTUSDT"
                    stop_loss_price = "1.3500"
                }
            }
        }
        
        Mock CoinEx-GetPendingPositions {
            return @([PSCustomObject]@{
                market = "TESTUSDT"
                stop_loss_price = "1.3500"
                take_profit_price = "0"
            })
        }
        
        Mock Start-Sleep {}
        
        It "Deve configurar stop loss com sucesso" {
            $result = Set-PositionStopLossFallback -Market "TESTUSDT" -Price 1.35 -MaxRetries 3
            
            $result.success | Should Be $true
            $result.method_used | Should Be "set-position-stop-loss"
            $result.attempts | Should Be 1
        }
    }
    
    Context "Quando todas as tentativas falham" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{
                code = 3008
                message = "Busy"
                data = $null
            }
        }
        
        Mock CoinEx-GetPendingPositions {
            return @([PSCustomObject]@{
                market = "TESTUSDT"
                stop_loss_price = "0"
                take_profit_price = "0"
            })
        }
        
        Mock Start-Sleep {}
        
        It "Deve retornar success = false apos MaxRetries" {
            $result = Set-PositionStopLossFallback -Market "TESTUSDT" -Price 1.35 -MaxRetries 2
            
            $result.success | Should Be $false
            $result.error | Should Match "Failed to set stop loss"
            $result.method_used | Should Be "none"
            $result.attempts | Should Be 2
        }
    }
}

Describe "lib_order_validation - Invoke-OrderWithValidation" {
    
    Context "Quando ordem completa com sucesso" {
        Mock CoinEx-AdjustPositionLeverage {
            return [PSCustomObject]@{
                success = $true
                leverage = 5
                margin_mode = "isolated"
            }
        }
        
        Mock CoinEx-PlaceOrder {
            return [PSCustomObject]@{
                order_id = "12345"
                market = "TESTUSDT"
                side = "buy"
                amount = "100"
            }
        }
        
        Mock Set-PositionStopLossFallback {
            return [PSCustomObject]@{
                success = $true
                method_used = "set-position-stop-loss"
                stop_loss_price = 1.35
                attempts = 1
            }
        }
        
        Mock Set-PositionTakeProfitFallback {
            return [PSCustomObject]@{
                success = $true
                method_used = "set-position-take-profit"
                take_profit_price = 1.65
                attempts = 1
            }
        }
        
        Mock Test-PositionHasStopLoss {
            return [PSCustomObject]@{
                success = $true
                has_stop_loss = $true
                stop_loss_price = 1.35
                has_take_profit = $true
                take_profit_price = 1.65
            }
        }
        
        Mock Start-Sleep {}
        
        It "Deve executar workflow completo" {
            $result = Invoke-OrderWithValidation `
                -Market "TESTUSDT" `
                -Side "buy" `
                -Amount 100 `
                -StopLoss 1.35 `
                -TakeProfit 1.65 `
                -Leverage 5
            
            $result.success | Should Be $true
            $result.order_id | Should Be "12345"
            $result.stop_loss_configured | Should Be $true
            $result.take_profit_configured | Should Be $true
        }
    }
    
    Context "Quando leverage falha" {
        Mock CoinEx-AdjustPositionLeverage {
            return [PSCustomObject]@{
                success = $false
                error_msg = "Invalid leverage"
            }
        }
        
        It "Deve retornar erro no stage leverage" {
            $result = Invoke-OrderWithValidation `
                -Market "TESTUSDT" `
                -Side "buy" `
                -Amount 100 `
                -Leverage 5
            
            $result.success | Should Be $false
            $result.stage | Should Be "leverage"
            $result.error | Should Match "Invalid leverage"
        }
    }
    
    Context "Quando stop loss falha apos ordem executada" {
        Mock CoinEx-AdjustPositionLeverage {
            return [PSCustomObject]@{ success = $true }
        }
        
        Mock CoinEx-PlaceOrder {
            return [PSCustomObject]@{ order_id = "12345" }
        }
        
        Mock Set-PositionStopLossFallback {
            return [PSCustomObject]@{
                success = $false
                error = "Failed after 3 attempts"
            }
        }
        
        Mock Start-Sleep {}
        
        It "Deve retornar warning de posicao sem protecao" {
            $result = Invoke-OrderWithValidation `
                -Market "TESTUSDT" `
                -Side "buy" `
                -Amount 100 `
                -StopLoss 1.35 `
                -Leverage 5
            
            $result.success | Should Be $false
            $result.order_id | Should Be "12345"
            $result.stage | Should Be "stop_loss"
            $result.warning | Should Match "WITHOUT STOP LOSS"
        }
    }
}

Describe "lib_order_validation - Cenario Real NEAR" {
    
    Context "Bug NEAR: Ordem executada mas stop loss nao configurado" {
        Mock CoinEx-AdjustPositionLeverage {
            return [PSCustomObject]@{ success = $true }
        }
        
        Mock CoinEx-PlaceOrder {
            # Ordem executada mas stop loss ignorado (bug)
            return [PSCustomObject]@{ order_id = "208413685330" }
        }
        
        Mock Set-PositionStopLossFallback {
            # Fallback funciona
            return [PSCustomObject]@{
                success = $true
                method_used = "set-position-stop-loss"
                stop_loss_price = 2.35
                attempts = 1
            }
        }
        
        Mock Set-PositionTakeProfitFallback {
            return [PSCustomObject]@{
                success = $true
                method_used = "set-position-take-profit"
                take_profit_price = 2.469
                attempts = 1
            }
        }
        
        Mock Test-PositionHasStopLoss {
            return [PSCustomObject]@{
                success = $true
                has_stop_loss = $true
                stop_loss_price = 2.35
                has_take_profit = $true
                take_profit_price = 2.469
            }
        }
        
        Mock Start-Sleep {}
        
        It "Deve detectar e corrigir com fallback" {
            $result = Invoke-OrderWithValidation `
                -Market "NEARUSDT" `
                -Side "buy" `
                -Amount 209 `
                -StopLoss 2.35 `
                -TakeProfit 2.469 `
                -Leverage 5
            
            $result.success | Should Be $true
            $result.order_id | Should Be "208413685330"
            $result.stop_loss_configured | Should Be $true
            $result.stop_loss_price | Should Be 2.35
            $result.take_profit_configured | Should Be $true
        }
    }
}
