# lib_whale_detection.ps1 - Whale Detection para ChainAgent
# TDD: Implementação para passar em whale_detection.Tests.ps1
# Refs: MANIPULATION.md, ONCHAIN_ANALYSIS.md

# Exchange addresses conhecidos (top 20 exchanges)
$EXCHANGE_ADDRESSES = @{
    # Binance
    "34xp4vRoCGJym3xR7yCVPFHoCNxv4Twseo" = "binance_cold_1"
    "bc1qm34lsc65zpw79lxes69zkqmk6ee3ewf0j77s3h" = "binance_cold_2"
    
    # Coinbase
    "3Cbq7aT1tY8kMxWLbitaG7yT6bPbKChq64" = "coinbase_cold"
    "bc1qgdjqv0av3q56jvd82tkdjpy7gdp9ut8tlqmgrpmv24sq90ecnvqqjwvw97" = "coinbase_hot"
    
    # Kraken
    "3Q3hfr5vJVGFJJa7TFpRqvvYjHjvPs7YeK" = "kraken_cold"
    
    # Bitfinex
    "3D2oetdNuZUqQHPJmcMDDHYoqkyNVsFk9r" = "bitfinex_cold"
    
    # Huobi
    "3JZq4atUahhuA9rLhXLMhhTo133J9rF97j" = "huobi_cold"
    
    # OKEx
    "1PzQ2W1qhKSZbYKqUipJXvKqxKPHvLmPqy" = "okex_cold"
}

# ═══════════════════════════════════════════════════════════════════════════
# Test-WhaleTransaction - Classifica uma transaction como whale ou não
# ═══════════════════════════════════════════════════════════════════════════
function Test-WhaleTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Transaction,
        [int] $MinBtc = 100
    )
    
    # Calcular BTC amount (satoshis → BTC)
    $satoshis = 0
    if ($Transaction.inputs -and $Transaction.inputs.Count -gt 0) {
        foreach ($input in $Transaction.inputs) {
            if ($input.prev_out -and $input.prev_out.value) {
                $satoshis += [long]$input.prev_out.value
            }
        }
    } elseif ($Transaction.out -and $Transaction.out.Count -gt 0) {
        foreach ($output in $Transaction.out) {
            if ($output.value) {
                $satoshis += [long]$output.value
            }
        }
    } elseif ($Transaction.btcAmount) {
        # Dados reais já em BTC
        $btcAmount = [double]$Transaction.btcAmount
        $satoshis = [long]($btcAmount * 100000000)
    }
    
    $btcAmount = [math]::Round($satoshis / 100000000.0, 4)
    
    # Verificar se é whale
    $isWhale = $btcAmount -ge $MinBtc
    
    if (-not $isWhale) {
        return [PSCustomObject]@{
            isWhale = $false
            btcAmount = $btcAmount
            signal = "NEUTRAL"
            reason = "below_threshold"
            scoreImpact = 0
        }
    }
    
    # Classificar direção (exchange deposit/withdrawal)
    $fromAddr = if ($Transaction.inputs -and $Transaction.inputs[0].prev_out) {
        $Transaction.inputs[0].prev_out.addr
    } else { $null }
    
    $toAddr = if ($Transaction.out -and $Transaction.out[0]) {
        $Transaction.out[0].addr
    } else { $null }
    
    $fromExchange = ($null -ne $fromAddr) -and $EXCHANGE_ADDRESSES.ContainsKey($fromAddr)
    $toExchange   = ($null -ne $toAddr)   -and $EXCHANGE_ADDRESSES.ContainsKey($toAddr)
    
    $signal = "NEUTRAL"
    $reason = "whale_to_whale_transfer"
    $scoreImpact = 0
    
    if ($toExchange -and -not $fromExchange) {
        # Whale → Exchange = dump signal (BEARISH)
        $signal = "BEARISH"
        $reason = "exchange_deposit_${btcAmount}BTC"
        # Score impact: -5 a -15 pts baseado no tamanho
        $scoreImpact = [math]::Max(-15, [math]::Min(-5, -($btcAmount / 50)))
    } elseif ($fromExchange -and -not $toExchange) {
        # Exchange → Whale = accumulation signal (BULLISH)
        $signal = "BULLISH"
        $reason = "exchange_withdrawal_${btcAmount}BTC"
        # Score impact: +5 a +15 pts baseado no tamanho
        $scoreImpact = [math]::Min(15, [math]::Max(5, $btcAmount / 50))
    }
    
    return [PSCustomObject]@{
        isWhale = $true
        btcAmount = $btcAmount
        signal = $signal
        reason = $reason
        scoreImpact = [math]::Round($scoreImpact, 1)
        txHash = $Transaction.hash
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Get-WhaleSignals - Agrega múltiplas whale transactions
# ═══════════════════════════════════════════════════════════════════════════
function Get-WhaleSignals {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [array] $Transactions = @()
    )
    
    if (-not $Transactions -or $Transactions.Count -eq 0) {
        return [PSCustomObject]@{
            netSignal = "NEUTRAL"
            totalBtc = 0
            scoreImpact = 0
            count = 0
        }
    }
    
    $totalBtc = 0
    $totalImpact = 0
    $bullishCount = 0
    $bearishCount = 0
    
    foreach ($tx in $Transactions) {
        $totalBtc += $tx.btcAmount
        $totalImpact += $tx.scoreImpact
        
        if ($tx.signal -eq "BULLISH") { $bullishCount++ }
        elseif ($tx.signal -eq "BEARISH") { $bearishCount++ }
    }
    
    # Net signal: maioria vence
    $netSignal = if ($bullishCount -gt $bearishCount) { "BULLISH" }
                 elseif ($bearishCount -gt $bullishCount) { "BEARISH" }
                 else { "NEUTRAL" }
    
    return [PSCustomObject]@{
        netSignal = $netSignal
        totalBtc = [math]::Round($totalBtc, 2)
        scoreImpact = [math]::Round($totalImpact, 1)
        count = $Transactions.Count
        bullishCount = $bullishCount
        bearishCount = $bearishCount
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Get-RecentWhaleActivity - Busca whale transactions via Blockchain.info
# ═══════════════════════════════════════════════════════════════════════════
function Get-RecentWhaleActivity {
    [CmdletBinding()]
    param(
        [int] $MinBtc = 100,
        [int] $LastHours = 24
    )
    
    try {
        # Blockchain.info unconfirmed transactions (free, sem API key)
        $url = "https://blockchain.info/unconfirmed-transactions?format=json"
        $response = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 10 -ErrorAction Stop
        
        $whaleTxs = @()
        
        if ($response.txs) {
            foreach ($tx in $response.txs) {
                $result = Test-WhaleTransaction -Transaction $tx -MinBtc $MinBtc
                
                if ($result.isWhale) {
                    $whaleTxs += $result
                }
            }
        }
        
        return Get-WhaleSignals -Transactions $whaleTxs
        
    } catch {
        Write-Warning "Get-RecentWhaleActivity falhou: $_"
        return [PSCustomObject]@{
            netSignal = "NEUTRAL"
            totalBtc = 0
            scoreImpact = 0
            count = 0
            error = $_.Exception.Message
        }
    }
}

Write-Host "[lib_whale_detection] Loaded - TDD implementation" -ForegroundColor DarkGreen
