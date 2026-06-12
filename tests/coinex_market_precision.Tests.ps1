# coinex_market_precision.Tests.ps1 -- TDD para Get-MarketPrecision (cache + sub-dollar)
# Pester 3.x compatible -- sem acentos
#
# Cobre root cause bug AIUSDT (2026-05-14):
#   - SPOT nao tem tick_size, apenas quote_ccy_precision/base_ccy_precision
#   - Sem cachear precision, codigo pode tentar ler tick_size e cair em default 0
#   - Sub-dollar tokens precisam de >=6 casas decimais (precision do quote)
#
# Esta suite valida:
#   1. Get-MarketPrecision para spot retorna quote/base ccy precision
#   2. Get-MarketPrecision para futures retorna tick_size + precisions
#   3. Cache evita chamadas duplicadas a Invoke-RestMethod
#   4. TTL expira corretamente
#   5. Par inexistente retorna $null (graceful)
#   6. Response sem precision retorna default seguro (8)
#   7. Sub-dollar (AIUSDT) retorna quote_ccy_precision >= 6
#   8. Clear-MarketPrecisionCache funciona per-process

$global:COINEX_BASE_URL               = "https://api.coinex.com"
$global:COINEX_FEE_MAKER_FALLBACK     = 0.002
$global:COINEX_FEE_TAKER_FALLBACK     = 0.002
$global:COINEX_FEE_ROUNDTRIP_FALLBACK = 0.004
$global:COINEX_ACCESS_ID  = $null
$global:COINEX_SECRET_KEY = $null

function Write-Host { param() }
function Write-Warning { param() }

. "$PSScriptRoot\..\agents\lib_coinex.ps1"

Describe "Get-MarketPrecision -- SPOT" {

    BeforeEach {
        Clear-MarketPrecisionCache
    }

    It "retorna quote_ccy_precision e base_ccy_precision do response /spot/market" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                market              = "BTCUSDT"
                base_ccy            = "BTC"
                quote_ccy           = "USDT"
                base_ccy_precision  = 8
                quote_ccy_precision = 2
                min_amount          = "0.0005"
                status              = "online"
            })}
        }
        $r = Get-MarketPrecision -Market "BTCUSDT" -MarketType "spot"
        $r              | Should Not Be $null
        $r.market       | Should Be "BTCUSDT"
        $r.market_type  | Should Be "spot"
        $r.quote_ccy_precision | Should Be 2
        $r.base_ccy_precision  | Should Be 8
    }

    It "sub-dollar token (AIUSDT) retorna quote_ccy_precision >= 6" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                market              = "AIUSDT"
                base_ccy            = "AI"
                quote_ccy           = "USDT"
                base_ccy_precision  = 2
                quote_ccy_precision = 6
                min_amount          = "0.01"
                status              = "online"
            })}
        }
        $r = Get-MarketPrecision -Market "AIUSDT" -MarketType "spot"
        $r.quote_ccy_precision | Should BeGreaterThan 5
    }

    It "edge: response sem quote_ccy_precision retorna default seguro 8" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                market              = "WEIRDUSDT"
                base_ccy            = "WEIRD"
                quote_ccy           = "USDT"
                min_amount          = "0.01"
                status              = "online"
            })}
        }
        $r = Get-MarketPrecision -Market "WEIRDUSDT" -MarketType "spot"
        $r                       | Should Not Be $null
        $r.quote_ccy_precision   | Should Be 8
        $r.base_ccy_precision    | Should Be 8
    }

    It "retorna `$null se par nao existe (graceful)" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=3001; message="market not found"; data=@() }
        }
        $r = Get-MarketPrecision -Market "FAKEUSDT" -MarketType "spot"
        $r | Should Be $null
    }
}

Describe "Get-MarketPrecision -- FUTURES" {

    BeforeEach {
        Clear-MarketPrecisionCache
    }

    It "futures usa /futures/market e retorna tick_size + precisions" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                market              = "BTCUSDT"
                base_ccy            = "BTC"
                quote_ccy           = "USDT"
                base_ccy_precision  = 8
                quote_ccy_precision = 2
                tick_size           = "0.5"
                min_amount          = "0.0001"
                status              = "online"
            })}
        }
        $r = Get-MarketPrecision -Market "BTCUSDT" -MarketType "futures"
        $r.market_type         | Should Be "futures"
        $r.tick_size           | Should Be "0.5"
        $r.quote_ccy_precision | Should Be 2
    }
}

Describe "Get-MarketPrecision -- cache" {

    BeforeEach {
        Clear-MarketPrecisionCache
    }

    It "cacheia resultado por par (mesma chamada 2x nao bate API)" {
        $script:_callCount = 0
        Mock Invoke-RestMethod {
            $script:_callCount++
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                market              = "BTCUSDT"
                base_ccy_precision  = 8
                quote_ccy_precision = 2
                status              = "online"
            })}
        }
        $r1 = Get-MarketPrecision -Market "BTCUSDT" -MarketType "spot"
        $r2 = Get-MarketPrecision -Market "BTCUSDT" -MarketType "spot"
        $r1.quote_ccy_precision | Should Be 2
        $r2.quote_ccy_precision | Should Be 2
        $script:_callCount      | Should Be 1
    }

    It "cache expira apos TTL configuravel" {
        $script:_callCount = 0
        Mock Invoke-RestMethod {
            $script:_callCount++
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                market              = "ETHUSDT"
                base_ccy_precision  = 6
                quote_ccy_precision = 2
                status              = "online"
            })}
        }
        # TTL = 0 forca expiracao imediata (cada chamada bate API)
        $r1 = Get-MarketPrecision -Market "ETHUSDT" -MarketType "spot" -TTLSeconds 0
        Start-Sleep -Milliseconds 50
        $r2 = Get-MarketPrecision -Market "ETHUSDT" -MarketType "spot" -TTLSeconds 0
        $script:_callCount | Should Be 2
    }

    It "cache e per-process (Clear-MarketPrecisionCache esvazia)" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                market              = "SOLUSDT"
                base_ccy_precision  = 4
                quote_ccy_precision = 3
                status              = "online"
            })}
        }
        $r1 = Get-MarketPrecision -Market "SOLUSDT" -MarketType "spot"
        Clear-MarketPrecisionCache
        # apos clear, proxima chamada bate API de novo (refletida por novo valor mockado)
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                market              = "SOLUSDT"
                base_ccy_precision  = 4
                quote_ccy_precision = 5
                status              = "online"
            })}
        }
        $r2 = Get-MarketPrecision -Market "SOLUSDT" -MarketType "spot"
        $r2.quote_ccy_precision | Should Be 5
    }
}
