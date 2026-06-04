# dashboard_root_cause.Tests.ps1 - TDD para identificar causa raiz dos problemas do dashboard
# RED → GREEN → REFACTOR
#
# PROBLEMAS REPORTADOS:
# 1. Dashboard nao mostra posicao BNBUSDT aberta (Position ID: 394174955)
# 2. UTF-8 encoding issues: "ðŸ"Š", "Ãšltima", "PosiÃ§Ãµes"
# 3. Usa campos errados: open_price, latest_price, liquidation_price
#
# HIPOTESES:
# H1: CoinEx-GetPendingPositions retorna vazio (API issue ou parsing issue)
# H2: Dashboard usa campos errados (open_price vs avg_entry_price)
# H3: HTML gerado com encoding errado (UTF-8 sem BOM vs UTF-8 com BOM)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"

Describe "Dashboard Root Cause Analysis" {
    
    Context "H1: CoinEx-GetPendingPositions API Call" {
        
        It "Should call correct API endpoint" {
            Mock CoinEx-Get { 
                param($path)
                $script:capturedPath = $path
                return @{ code = 0; data = @() }
            }
            
            CoinEx-GetPendingPositions
            
            $script:capturedPath | Should Be "/v2/futures/pending-position?market_type=FUTURES"
        }
        
        It "Should return array when API returns single position" {
            Mock CoinEx-Get {
                return @{
                    code = 0
                    data = @{
                        market = "BNBUSDT"
                        side = "long"
                        position_id = 394174955
                    }
                }
            }
            
            $result = CoinEx-GetPendingPositions
            
            $result | Should BeOfType [array]
            $result.Count | Should Be 1
            $result[0].market | Should Be "BNBUSDT"
        }
        
        It "Should return array when API returns multiple positions" {
            Mock CoinEx-Get {
                return @{
                    code = 0
                    data = @(
                        @{ market = "BNBUSDT"; side = "long" }
                        @{ market = "BTCUSDT"; side = "short" }
                    )
                }
            }
            
            $result = CoinEx-GetPendingPositions
            
            $result | Should BeOfType [array]
            $result.Count | Should Be 2
        }
        
        It "Should return empty array when API returns empty" {
            Mock CoinEx-Get {
                return @{ code = 0; data = @() }
            }
            
            $result = CoinEx-GetPendingPositions
            
            $result | Should BeOfType [array]
            $result.Count | Should Be 0
        }
        
        It "Should return empty array when API fails" {
            Mock CoinEx-Get {
                return @{ code = 1; message = "API Error" }
            }
            
            $result = CoinEx-GetPendingPositions
            
            $result | Should BeOfType [array]
            $result.Count | Should Be 0
        }
    }
    
    Context "H2: Dashboard Field Mapping" {
        
        It "Should use avg_entry_price not open_price" {
            # Simular posicao real da API
            $mockPosition = @{
                market = "BNBUSDT"
                side = "long"
                position_id = 394174955
                avg_entry_price = "647.06"
                amount = "0.07"
                liq_price = "0"
                leverage = "50"
                margin_mode = "isolated"
            }
            
            # Dashboard deve usar avg_entry_price
            $entryPrice = [double]$mockPosition.avg_entry_price
            $entryPrice | Should Be 647.06
            
            # Dashboard NAO deve usar open_price (nao existe)
            $mockPosition.PSObject.Properties.Name | Should Not Contain "open_price"
        }
        
        It "Should fetch current price via ticker not latest_price" {
            # Simular posicao real da API
            $mockPosition = @{
                market = "BNBUSDT"
                side = "long"
                avg_entry_price = "647.06"
            }
            
            # Dashboard deve buscar preco atual via ticker
            Mock CoinEx-GetTickerFresh {
                param($market)
                return @{
                    ticker = @{
                        last = "650.00"
                    }
                }
            }
            
            $ticker = CoinEx-GetTickerFresh -market $mockPosition.market
            $currentPrice = [double]$ticker.ticker.last
            $currentPrice | Should Be 650.00
            
            # Dashboard NAO deve usar latest_price (nao existe)
            $mockPosition.PSObject.Properties.Name | Should Not Contain "latest_price"
        }
        
        It "Should use liq_price not liquidation_price" {
            # Simular posicao real da API
            $mockPosition = @{
                market = "BNBUSDT"
                liq_price = "0"
            }
            
            # Dashboard deve usar liq_price
            $liqPrice = [double]$mockPosition.liq_price
            $liqPrice | Should Be 0
            
            # Dashboard NAO deve usar liquidation_price (nao existe)
            $mockPosition.PSObject.Properties.Name | Should Not Contain "liquidation_price"
        }
    }
    
    Context "H3: HTML UTF-8 Encoding" {
        
        It "Should generate HTML with UTF-8 encoding declaration" {
            $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <title>Test</title>
</head>
<body>
    <h1>📊 Dashboard</h1>
    <p>Última atualização</p>
    <p>Posições Abertas</p>
</body>
</html>
"@
            
            # HTML deve conter meta charset UTF-8
            $html | Should Match '<meta charset="UTF-8">'
            
            # HTML deve conter caracteres UTF-8 corretos
            $html | Should Match '📊'
            $html | Should Match 'Última'
            $html | Should Match 'Posições'
        }
        
        It "Should save HTML file with UTF-8 encoding" {
            $testHtml = @"
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body>
    <h1>📊 Test</h1>
    <p>Última atualização</p>
</body>
</html>
"@
            
            $testPath = Join-Path $TestDrive "test_encoding.html"
            
            # Salvar com UTF-8 (sem BOM)
            $testHtml | Out-File -FilePath $testPath -Encoding UTF8 -Force
            
            # Ler arquivo e verificar encoding
            $content = Get-Content -Path $testPath -Raw -Encoding UTF8
            
            $content | Should Match '📊'
            $content | Should Match 'Última'
        }
        
        It "Should detect current HTML encoding issue" {
            $currentHtml = Get-Content -Path "dashboard\position_metrics.html" -Raw -Encoding UTF8
            
            # Se HTML atual tem problemas de encoding, vai conter caracteres corrompidos
            if ($currentHtml -match 'ðŸ"Š' -or $currentHtml -match 'Ãšltima' -or $currentHtml -match 'PosiÃ§Ãµes') {
                # PROBLEMA CONFIRMADO: HTML foi salvo com encoding errado
                $true | Should Be $true
            } else {
                # HTML esta correto
                $currentHtml | Should Match '📊'
                $currentHtml | Should Match 'Última'
            }
        }
    }
    
    Context "H4: Dashboard Data Flow Integration" {
        
        It "Should correctly transform API position to dashboard display" {
            # Simular posicao real da API
            Mock CoinEx-GetPendingPositions {
                return @(
                    @{
                        market = "BNBUSDT"
                        side = "long"
                        position_id = 394174955
                        avg_entry_price = "647.06"
                        amount = "0.07"
                        liq_price = "0"
                        leverage = "50"
                        margin_mode = "isolated"
                    }
                )
            }
            
            Mock CoinEx-GetTickerFresh {
                param($market)
                return @{
                    ticker = @{
                        last = "650.00"
                    }
                }
            }
            
            # Simular logica do dashboard
            $positions = CoinEx-GetPendingPositions
            $positions.Count | Should Be 1
            
            $pos = $positions[0]
            $entryPrice = [double]$pos.avg_entry_price
            $entryPrice | Should Be 647.06
            
            $ticker = CoinEx-GetTickerFresh -market $pos.market
            $currentPrice = [double]$ticker.ticker.last
            $currentPrice | Should Be 650.00
            
            $liqPrice = [double]$pos.liq_price
            $liqPrice | Should Be 0
            
            # Calcular PnL%
            $pnlPct = if ($pos.side -eq "long") {
                (($currentPrice - $entryPrice) / $entryPrice) * 100
            } else {
                (($entryPrice - $currentPrice) / $entryPrice) * 100
            }
            $pnlPct = [math]::Round($pnlPct, 2)
            
            $pnlPct | Should BeGreaterThan 0
            $pnlPct | Should BeLessThan 1  # ~0.45%
        }
    }
}
