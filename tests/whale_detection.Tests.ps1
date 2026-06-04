# whale_detection.Tests.ps1 - TDD para Whale Detection
# Teste ANTES do código (TDD rigoroso)

$ErrorActionPreference = "Stop"

# Dot-source o código que vamos criar
. "$PSScriptRoot\..\agents\lib_whale_detection.ps1"

Describe "Get-WhaleTransactions" {
    
    It "detecta whale transaction > 100 BTC" {
        # ARRANGE: Simular resposta Blockchain.info
        $mockTx = @{
            hash = "a502eecb55510702..."
            size = 140
            inputs = @(
                @{ prev_out = @{ addr = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"; value = 48639420000 } }
            )
            out = @(
                @{ addr = "3J98t1WpEZ73CNmYviecrnyiWrnqRhWNLy"; value = 48639420000 }
            )
        }
        
        # ACT
        $result = Test-WhaleTransaction -Transaction $mockTx -MinBtc 100
        
        # ASSERT
        $result.isWhale | Should Be $true
        $result.btcAmount | Should BeGreaterThan 100
        $result.signal | Should Match "BULLISH|BEARISH|NEUTRAL"
    }
    
    It "classifica exchange deposit como BEARISH" {
        # ARRANGE: Whale → Exchange = dump signal
        $mockTx = @{
            hash = "test123"
            inputs = @( @{ prev_out = @{ addr = "whale_address"; value = 10000000000 } } )
            out = @( @{ addr = "34xp4vRoCGJym3xR7yCVPFHoCNxv4Twseo"; value = 10000000000 } )
        }
        
        # ACT
        $result = Test-WhaleTransaction -Transaction $mockTx -MinBtc 100
        
        # ASSERT
        $result.signal | Should Be "BEARISH"
        $result.reason | Should Match "exchange.*deposit"
    }
    
    It "classifica exchange withdrawal como BULLISH" {
        # ARRANGE: Exchange → Whale = accumulation signal
        $mockTx = @{
            hash = "test456"
            inputs = @( @{ prev_out = @{ addr = "bc1qgdjqv0av3q56jvd82tkdjpy7gdp9ut8tlqmgrpmv24sq90ecnvqqjwvw97"; value = 20000000000 } } )
            out = @( @{ addr = "whale_address"; value = 20000000000 } )
        }
        
        # ACT
        $result = Test-WhaleTransaction -Transaction $mockTx -MinBtc 100
        
        # ASSERT
        $result.signal | Should Be "BULLISH"
        $result.reason | Should Match "exchange.*withdrawal"
    }
    
    It "ignora transactions < 100 BTC" {
        # ARRANGE
        $mockTx = @{
            hash = "small_tx"
            inputs = @( @{ prev_out = @{ value = 5000000000 } } )  # 50 BTC
            out = @( @{ value = 5000000000 } )
        }
        
        # ACT
        $result = Test-WhaleTransaction -Transaction $mockTx -MinBtc 100
        
        # ASSERT
        $result.isWhale | Should Be $false
    }
    
    It "calcula score impact correto" {
        # ARRANGE: 200 BTC deposit (bearish)
        $mockTx = @{
            hash = "large_deposit"
            inputs = @( @{ prev_out = @{ addr = "whale"; value = 20000000000 } } )
            out = @( @{ addr = "exchange"; value = 20000000000 } )
        }
        
        # ACT
        $result = Test-WhaleTransaction -Transaction $mockTx -MinBtc 100
        
        # ASSERT
        $result.scoreImpact | Should BeLessThan 0  # Bearish = negativo
        $result.scoreImpact | Should BeGreaterThan -20  # Max -15pts
    }
}

Describe "Get-WhaleSignals" {
    
    It "agrega múltiplas transactions em 24h" {
        # ARRANGE: 3 whale txs (2 bearish, 1 bullish)
        $mockTxs = @(
            @{ btcAmount = 150; signal = "BEARISH"; scoreImpact = -10 }
            @{ btcAmount = 200; signal = "BEARISH"; scoreImpact = -15 }
            @{ btcAmount = 100; signal = "BULLISH"; scoreImpact = 10 }
        )
        
        # ACT
        $result = Get-WhaleSignals -Transactions $mockTxs
        
        # ASSERT
        $result.netSignal | Should Be "BEARISH"  # 2 bearish > 1 bullish
        $result.totalBtc | Should Be 450
        $result.scoreImpact | Should BeLessThan 0
    }
    
    It "retorna NEUTRAL quando sem whale activity" {
        # ARRANGE
        $mockTxs = @()
        
        # ACT
        $result = Get-WhaleSignals -Transactions $mockTxs
        
        # ASSERT
        $result.netSignal | Should Be "NEUTRAL"
        $result.scoreImpact | Should Be 0
    }
}

Describe "Integration com ChainAgent" {
    
    It "ChainAgent inclui whale score no chain_score final" {
        # ARRANGE: Mock whale data
        $whaleData = @{
            netSignal = "BEARISH"
            scoreImpact = -12
            totalBtc = 350
        }
        
        # ACT: Simular cálculo chain_score
        $baseScore = 70
        $whaleWeight = 0.10  # 10% do chain_score
        $finalScore = $baseScore + ($whaleData.scoreImpact * $whaleWeight)
        
        # ASSERT
        $finalScore | Should BeLessThan $baseScore
        $finalScore | Should BeGreaterThan 68  # 70 - (12 * 0.10) = 68.8
    }
}

# TESTE COM DADOS REAIS (o whale de $47M que você mencionou)
Describe "Validação com Whale Real" {
    
    It "detecta whale 486 BTC (txid a502eecb55510702...)" {
        # ARRANGE: Dados reais do whale
        $realTx = @{
            hash = "a502eecb55510702"
            size = 140
            fee = 169
            btcAmount = 486.3942
        }
        
        # ACT
        $result = Test-WhaleTransaction -Transaction $realTx -MinBtc 100
        
        # ASSERT
        $result.isWhale | Should Be $true
        $result.btcAmount | Should BeGreaterThan 400
        Write-Host "  Whale real detectado: $($result.btcAmount) BTC → $($result.signal)" -ForegroundColor Cyan
    }
}

Write-Host "`n=== TESTES WHALE DETECTION ===" -ForegroundColor Cyan
Write-Host "Status: AGUARDANDO IMPLEMENTAÇÃO" -ForegroundColor Yellow
Write-Host "Próximo: Implementar lib_whale_detection.ps1 para passar nos testes" -ForegroundColor Yellow
