# lib_multi_tp_ladder.Tests.ps1 - Testes para Multi-TP Ladder Exits
# Rodar: Invoke-Pester .\tests\lib_multi_tp_ladder.Tests.ps1 -Verbose

$global:COINEX_BASE_URL   = "https://api.coinex.com"
$global:COINEX_ACCESS_ID  = "test_access_id"
$global:COINEX_SECRET_KEY = "test_secret_key"

function Write-Host { param() }
function Write-Warning { param() }

. "$PSScriptRoot\..\agents\lib_coinex.ps1"
. "$PSScriptRoot\..\agents\lib_coinex_position_management.ps1"
. "$PSScriptRoot\..\agents\lib_multi_tp_ladder.ps1"

# ============================================================================
# Get-LadderExitLevels - Cálculo de níveis de TP
# ============================================================================

Describe "Get-LadderExitLevels - calculo de niveis de TP" {

    It "calcula 4 niveis de TP para LONG com ATR 800" {
        $result = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 0.01
        
        # TP1: 2x ATR
        $result.tp1.price | Should Be 101600
        $result.tp1.pct | Should Be 0.25
        $result.tp1.atr_mult | Should Be 2.0
        
        # TP2: 4x ATR
        $result.tp2.price | Should Be 103200
        $result.tp2.pct | Should Be 0.35
        $result.tp2.atr_mult | Should Be 4.0
        
        # TP3: 6x ATR
        $result.tp3.price | Should Be 104800
        $result.tp3.pct | Should Be 0.25
        $result.tp3.atr_mult | Should Be 6.0
        
        # TP4: 10x ATR
        $result.tp4.price | Should Be 108000
        $result.tp4.pct | Should Be 0.15
        $result.tp4.atr_mult | Should Be 10.0
    }

    It "calcula 4 niveis de TP para SHORT com ATR 800" {
        $result = Get-LadderExitLevels -EntryPrice 100000 -Side "short" -AtrValue 800 -TotalQty 0.01
        
        # SHORT: preços abaixo do entry
        $result.tp1.price | Should Be 98400
        $result.tp2.price | Should Be 96800
        $result.tp3.price | Should Be 95200
        $result.tp4.price | Should Be 92000
    }

    It "distribui quantidade corretamente (25% + 35% + 25% + 15% = 100%)" {
        $result = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 1.0
        
        $totalQty = $result.tp1.qty + $result.tp2.qty + $result.tp3.qty + $result.tp4.qty
        
        # Deve somar 1.0 (com tolerância de arredondamento)
        [math]::Abs($totalQty - 1.0) | Should BeLessThan 0.00000001
        
        # TP2 deve ter maior quantidade (35%)
        $result.tp2.qty | Should BeGreaterThan $result.tp1.qty
        $result.tp2.qty | Should BeGreaterThan $result.tp3.qty
        $result.tp2.qty | Should BeGreaterThan $result.tp4.qty
    }

    It "funciona com ATR pequeno (sub-dollar tokens)" {
        $result = Get-LadderExitLevels -EntryPrice 0.5 -Side "long" -AtrValue 0.02 -TotalQty 1000
        
        $result.tp1.price | Should Be 0.54
        $result.tp2.price | Should Be 0.58
        $result.tp3.price | Should Be 0.62
        $result.tp4.price | Should Be 0.70
    }

    It "funciona com ATR grande (BTC)" {
        $result = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 5000 -TotalQty 0.01
        
        $result.tp1.price | Should Be 110000
        $result.tp2.price | Should Be 120000
        $result.tp3.price | Should Be 130000
        $result.tp4.price | Should Be 150000
    }

    It "rejeita side invalido" {
        { Get-LadderExitLevels -EntryPrice 100000 -Side "invalid" -AtrValue 800 -TotalQty 0.01 } | Should Throw
    }
}

# ============================================================================
# Place-LadderExitOrders - Colocação de ordens
# ============================================================================

Describe "Place-LadderExitOrders - colocacao de ordens" {

    BeforeEach {
        Mock CoinEx-PlaceFuturesOrder {
            param($Market, $Side, $Type, $Amount, $Price)
            return [PSCustomObject]@{
                order_id = "mock_order_$(Get-Random)"
                market = $Market
                side = $Side
                amount = $Amount
                price = $Price
            }
        }
    }

    It "coloca 4 ordens de TP para LONG" {
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 0.01
        
        $result = Place-LadderExitOrders -Market "BTCUSDT" -Side "long" -Ladder $ladder
        
        $result.success | Should Be $true
        $result.orders.Count | Should Be 4
        
        # Verificar que CoinEx-PlaceFuturesOrder foi chamado 4 vezes
        Assert-MockCalled CoinEx-PlaceFuturesOrder -Times 4
    }

    It "usa side correto (sell para LONG, buy para SHORT)" {
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 0.01
        
        Place-LadderExitOrders -Market "BTCUSDT" -Side "long" -Ladder $ladder
        
        # LONG deve usar sell para fechar
        Assert-MockCalled CoinEx-PlaceFuturesOrder -Times 4 -ParameterFilter { $Side -eq "sell" }
    }

    It "dry run nao coloca ordens reais" {
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 0.01
        
        $result = Place-LadderExitOrders -Market "BTCUSDT" -Side "long" -Ladder $ladder -DryRun
        
        $result.success | Should Be $true
        $result.dry_run | Should Be $true
        $result.orders.Count | Should Be 0
        
        # Não deve chamar API
        Assert-MockCalled CoinEx-PlaceFuturesOrder -Times 0
    }

    It "retorna erro quando API falha" {
        Mock CoinEx-PlaceFuturesOrder {
            throw "API Error: Rate limit exceeded"
        }
        
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 0.01
        
        $result = Place-LadderExitOrders -Market "BTCUSDT" -Side "long" -Ladder $ladder
        
        $result.success | Should Be $false
        $result.error | Should Match "Rate limit"
    }
}

# ============================================================================
# Monitor-LadderExecution - Monitoramento e ajuste de SL
# ============================================================================

Describe "Monitor-LadderExecution - monitoramento e ajuste de SL" {

    BeforeEach {
        Mock CoinEx-GetPendingPositions {
            param($Market)
            return @(
                [PSCustomObject]@{
                    market = "BTCUSDT"
                    side = "long"
                    amount = "0.01"
                    open_price = "100000"
                    latest_price = "102000"
                    stop_loss_price = "95000"
                }
            )
        }
        
        Mock CoinEx-ModifyPositionStopLoss {
            param($Market, $Price)
            return [PSCustomObject]@{
                success = $true
                stop_loss_price = $Price.ToString()
            }
        }
    }

    It "move SL para breakeven quando TP1 hit" {
        # Simular preço em TP1 (101600)
        Mock CoinEx-GetPendingPositions {
            return @(
                [PSCustomObject]@{
                    market = "BTCUSDT"
                    side = "long"
                    latest_price = "101600"
                    stop_loss_price = "95000"
                }
            )
        }
        
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 0.01
        
        $result = Monitor-LadderExecution -Market "BTCUSDT" -EntryPrice 100000 -Ladder $ladder -Side "long"
        
        $result.success | Should Be $true
        $result.tp1_hit | Should Be $true
        $result.new_sl | Should Be 100000  # Breakeven
        $result.reason | Should Match "TP1 hit"
    }

    It "move SL para TP1 quando TP2 hit" {
        # Simular preço em TP2 (103200)
        Mock CoinEx-GetPendingPositions {
            return @(
                [PSCustomObject]@{
                    market = "BTCUSDT"
                    side = "long"
                    latest_price = "103200"
                    stop_loss_price = "100000"
                }
            )
        }
        
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 0.01
        
        $result = Monitor-LadderExecution -Market "BTCUSDT" -EntryPrice 100000 -Ladder $ladder -Side "long"
        
        $result.success | Should Be $true
        $result.tp2_hit | Should Be $true
        $result.new_sl | Should Be 101600  # TP1
        $result.reason | Should Match "TP2 hit"
    }

    It "move SL para TP2 quando TP3 hit" {
        # Simular preço em TP3 (104800)
        Mock CoinEx-GetPendingPositions {
            return @(
                [PSCustomObject]@{
                    market = "BTCUSDT"
                    side = "long"
                    latest_price = "104800"
                    stop_loss_price = "101600"
                }
            )
        }
        
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 0.01
        
        $result = Monitor-LadderExecution -Market "BTCUSDT" -EntryPrice 100000 -Ladder $ladder -Side "long"
        
        $result.success | Should Be $true
        $result.tp3_hit | Should Be $true
        $result.new_sl | Should Be 103200  # TP2
        $result.reason | Should Match "TP3 hit"
    }

    It "nao atualiza SL se ja esta otimizado" {
        # Simular preço em TP1 mas SL já em breakeven
        Mock CoinEx-GetPendingPositions {
            return @(
                [PSCustomObject]@{
                    market = "BTCUSDT"
                    side = "long"
                    latest_price = "101600"
                    stop_loss_price = "100000"  # Já em breakeven
                }
            )
        }
        
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 0.01
        
        $result = Monitor-LadderExecution -Market "BTCUSDT" -EntryPrice 100000 -Ladder $ladder -Side "long"
        
        $result.success | Should Be $false
        $result.reason | Should Match "sl_already_optimal"
    }

    It "retorna erro quando posicao fechada" {
        Mock CoinEx-GetPendingPositions {
            return @()  # Nenhuma posição
        }
        
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 0.01
        
        $result = Monitor-LadderExecution -Market "BTCUSDT" -EntryPrice 100000 -Ladder $ladder -Side "long"
        
        $result.success | Should Be $false
        $result.reason | Should Be "position_closed"
    }

    It "funciona para SHORT (logica invertida)" {
        # SHORT: TP1 abaixo do entry
        Mock CoinEx-GetPendingPositions {
            return @(
                [PSCustomObject]@{
                    market = "BTCUSDT"
                    side = "short"
                    latest_price = "98400"  # TP1 para SHORT
                    stop_loss_price = "105000"
                }
            )
        }
        
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "short" -AtrValue 800 -TotalQty 0.01
        
        $result = Monitor-LadderExecution -Market "BTCUSDT" -EntryPrice 100000 -Ladder $ladder -Side "short"
        
        $result.success | Should Be $true
        $result.tp1_hit | Should Be $true
        $result.new_sl | Should Be 100000  # Breakeven
    }
}

# ============================================================================
# Invoke-LadderExitStrategy - Estratégia completa
# ============================================================================

Describe "Invoke-LadderExitStrategy - estrategia completa" {

    BeforeEach {
        Mock CoinEx-GetFuturesCandles {
            # Retornar 15 candles com ATR simulado
            $candles = @()
            for ($i = 0; $i -lt 15; $i++) {
                $candles += [PSCustomObject]@{
                    high = 101000 + ($i * 100)
                    low = 99000 + ($i * 100)
                    close = 100000 + ($i * 100)
                }
            }
            return $candles
        }
        
        Mock CoinEx-PlaceFuturesOrder {
            return [PSCustomObject]@{
                order_id = "mock_order_$(Get-Random)"
            }
        }
    }

    It "calcula ATR automaticamente se nao fornecido" {
        $result = Invoke-LadderExitStrategy `
            -Market "BTCUSDT" `
            -EntryPrice 100000 `
            -Side "long" `
            -TotalQty 0.01 `
            -DryRun
        
        $result.success | Should Be $true
        $result.atr_value | Should BeGreaterThan 0
        
        # Verificar que candles foram buscados
        Assert-MockCalled CoinEx-GetFuturesCandles -Times 1
    }

    It "usa ATR fornecido se especificado" {
        $result = Invoke-LadderExitStrategy `
            -Market "BTCUSDT" `
            -EntryPrice 100000 `
            -Side "long" `
            -TotalQty 0.01 `
            -AtrValue 800 `
            -DryRun
        
        $result.success | Should Be $true
        $result.atr_value | Should Be 800
        
        # Não deve buscar candles
        Assert-MockCalled CoinEx-GetFuturesCandles -Times 0
    }

    It "retorna ladder completo com 4 niveis" {
        $result = Invoke-LadderExitStrategy `
            -Market "BTCUSDT" `
            -EntryPrice 100000 `
            -Side "long" `
            -TotalQty 0.01 `
            -AtrValue 800 `
            -DryRun
        
        $result.success | Should Be $true
        $result.ladder.tp1 | Should Not BeNullOrEmpty
        $result.ladder.tp2 | Should Not BeNullOrEmpty
        $result.ladder.tp3 | Should Not BeNullOrEmpty
        $result.ladder.tp4 | Should Not BeNullOrEmpty
    }

    It "dry run nao coloca ordens reais" {
        $result = Invoke-LadderExitStrategy `
            -Market "BTCUSDT" `
            -EntryPrice 100000 `
            -Side "long" `
            -TotalQty 0.01 `
            -AtrValue 800 `
            -DryRun
        
        $result.success | Should Be $true
        $result.dry_run | Should Be $true
        
        # Não deve chamar API de ordens
        Assert-MockCalled CoinEx-PlaceFuturesOrder -Times 0
    }

    It "coloca ordens reais quando nao dry run" {
        $result = Invoke-LadderExitStrategy `
            -Market "BTCUSDT" `
            -EntryPrice 100000 `
            -Side "long" `
            -TotalQty 0.01 `
            -AtrValue 800
        
        $result.success | Should Be $true
        $result.dry_run | Should Be $false
        
        # Deve chamar API 4 vezes (4 TPs)
        Assert-MockCalled CoinEx-PlaceFuturesOrder -Times 4
    }

    It "retorna erro quando dados insuficientes para ATR" {
        Mock CoinEx-GetFuturesCandles {
            return @()  # Sem candles
        }
        
        $result = Invoke-LadderExitStrategy `
            -Market "BTCUSDT" `
            -EntryPrice 100000 `
            -Side "long" `
            -TotalQty 0.01
        
        $result.success | Should Be $false
        $result.error | Should Match "insuficientes"
    }
}

# ============================================================================
# Testes de Integração
# ============================================================================

Describe "Ladder Exits - testes de integracao" {

    It "lucro medio ponderado e maior que TP unico" {
        $entryPrice = 100000
        $atr = 800
        
        # Ladder exits
        $ladder = Get-LadderExitLevels -EntryPrice $entryPrice -Side "long" -AtrValue $atr -TotalQty 0.01
        
        $ladderProfit = (
            ($ladder.tp1.pct * (($ladder.tp1.price - $entryPrice) / $entryPrice)) +
            ($ladder.tp2.pct * (($ladder.tp2.price - $entryPrice) / $entryPrice)) +
            ($ladder.tp3.pct * (($ladder.tp3.price - $entryPrice) / $entryPrice)) +
            ($ladder.tp4.pct * (($ladder.tp4.price - $entryPrice) / $entryPrice))
        ) * 100
        
        # TP único (4x ATR, equivalente a TP2)
        $singleTpPrice = $entryPrice + ($atr * 4)
        $singleTpProfit = (($singleTpPrice - $entryPrice) / $entryPrice) * 100
        
        # Ladder deve ter lucro médio maior
        $ladderProfit | Should BeGreaterThan $singleTpProfit
    }

    It "distribuicao de quantidade soma 100%" {
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 1.0
        
        $totalPct = $ladder.tp1.pct + $ladder.tp2.pct + $ladder.tp3.pct + $ladder.tp4.pct
        
        $totalPct | Should Be 1.0
    }

    It "TPs estao em ordem crescente (LONG)" {
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "long" -AtrValue 800 -TotalQty 0.01
        
        $ladder.tp1.price | Should BeLessThan $ladder.tp2.price
        $ladder.tp2.price | Should BeLessThan $ladder.tp3.price
        $ladder.tp3.price | Should BeLessThan $ladder.tp4.price
    }

    It "TPs estao em ordem decrescente (SHORT)" {
        $ladder = Get-LadderExitLevels -EntryPrice 100000 -Side "short" -AtrValue 800 -TotalQty 0.01
        
        $ladder.tp1.price | Should BeGreaterThan $ladder.tp2.price
        $ladder.tp2.price | Should BeGreaterThan $ladder.tp3.price
        $ladder.tp3.price | Should BeGreaterThan $ladder.tp4.price
    }
}
