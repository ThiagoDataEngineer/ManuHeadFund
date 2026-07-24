# lib_coinex.Tests.ps1 - Pester 3.x tests para lib_coinex.ps1
# Foco: CoinEx-GetMarketInfo, CoinEx-GetFundingRate, CoinEx-GetFeeContext
# Rodar: Invoke-Pester .\tests\lib_coinex.Tests.ps1 -Verbose

$global:COINEX_BASE_URL               = "https://api.coinex.com"
$global:COINEX_FEE_MAKER_FALLBACK     = 0.002
$global:COINEX_FEE_TAKER_FALLBACK     = 0.002
$global:COINEX_FEE_ROUNDTRIP_FALLBACK = 0.004
$global:COINEX_ACCESS_ID  = $null
$global:COINEX_SECRET_KEY = $null

function Write-Host { param() }
function Write-Warning { param() }

. "$PSScriptRoot\..\agents\lib_coinex.ps1"

Describe "CoinEx-GetMarketInfo - status e campos corretos" {

    It "isSafe=true para mercado normal - status online e leverage correto" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                status              = "online"
                remark              = ""
                leverage            = @("1","2","5","10","20","50","100")
                maint_margin_rate   = 0.005
                maker_fee_rate      = "0.0003"
                taker_fee_rate      = "0.0005"
                min_amount          = "0.0001"
                is_market_available = $true
                delisted_at         = 0
            })}
        }
        $r = CoinEx-GetMarketInfo "BTCUSDT"
        $r.isSafe          | Should Be $true
        $r.status          | Should Be "online"
        $r.maxLeverage     | Should Be 100
        $r.maintMarginRate | Should Be 0.005
    }

    It "isSafe=false quando status nao e online" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                status              = "maintain"
                remark              = ""
                leverage            = @("1","2","5")
                is_market_available = $true
                delisted_at         = 0
            })}
        }
        $r = CoinEx-GetMarketInfo "TESTUSDT"
        $r.isSafe | Should Be $false
        $r.status | Should Be "maintain"
    }

    It "isSafe=false quando is_market_available=false" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                status              = "online"
                remark              = ""
                leverage            = @("1","5","10")
                is_market_available = $false
                delisted_at         = 0
            })}
        }
        $r = CoinEx-GetMarketInfo "SUSPENDUSDT"
        $r.isSafe | Should Be $false
    }

    It "isSafe=false quando delisted_at maior que zero" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                status              = "online"
                remark              = ""
                leverage            = @("1","5")
                is_market_available = $true
                delisted_at         = 1778630400000
            })}
        }
        $r = CoinEx-GetMarketInfo "EXITUSDT"
        $r.isSafe | Should Be $false
    }
}

Describe "CoinEx-GetMarketInfo - deteccao de notices de risco" {

    It "detecta delisting no campo remark" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                status              = "online"
                remark              = "This token will be delisted at 10:05 on 2026-04-22 (UTC)."
                leverage            = @("1","5","10")
                is_market_available = $true
                delisted_at         = 0
            })}
        }
        $r = CoinEx-GetMarketInfo "AIUSDT"
        $r.isSafe  | Should Be $false
        $r.notices | Should Not BeNullOrEmpty
    }

    It "detecta servicos encerrados no campo notice" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                status              = "online"
                notice              = "The deposit and trading services of this token have been terminated."
                leverage            = @("1","5")
                is_market_available = $true
                delisted_at         = 0
            })}
        }
        $r = CoinEx-GetMarketInfo "DEADUSDT"
        $r.isSafe  | Should Be $false
        $r.notices | Should Not BeNullOrEmpty
    }

    It "detecta swap no campo remark" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=0; data=@([PSCustomObject]@{
                status              = "online"
                remark              = "Notice: This token will undergo a swap at a ratio of 1:1."
                leverage            = @("1","5","10")
                is_market_available = $true
                delisted_at         = 0
            })}
        }
        $r = CoinEx-GetMarketInfo "SWAPUSDT"
        $r.isSafe  | Should Be $false
        $r.notices | Should Not BeNullOrEmpty
    }

    It "retorna null em caso de erro de rede" {
        Mock Invoke-RestMethod { throw "Network error" }
        $r = CoinEx-GetMarketInfo "ERRORUSDT"
        $r | Should BeNullOrEmpty
    }

    It "retorna null quando code diferente de zero" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ code=3008; message="market not found"; data=@() }
        }
        $r = CoinEx-GetMarketInfo "FAKUSDT"
        $r | Should BeNullOrEmpty
    }
}

Describe "CoinEx-GetFundingRate - campo correto da API real" {

    It "le latest_funding_rate do primeiro elemento do array data" {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                code = 0
                data = @([PSCustomObject]@{
                    latest_funding_rate = "0.00015"
                    mark_price          = "95000"
                    market              = "BTCUSDT"
                })
            }
        }
        $r = CoinEx-GetFundingRate "BTCUSDT"
        $r | Should Be 0.00015
    }

    It "retorna null quando API falha" {
        Mock Invoke-RestMethod { throw "Network error" }
        $r = CoinEx-GetFundingRate "BTCUSDT"
        $r | Should BeNullOrEmpty
    }
}

Describe "CoinEx-GetFeeContext - fallback e calculo de holdCost" {

    It "usa fallback quando sem credenciais" {
        $global:COINEX_ACCESS_ID  = $null
        $global:COINEX_SECRET_KEY = $null
        Mock CoinEx-GetFundingRate { return 0.0001 }

        $r = CoinEx-GetFeeContext "BTCUSDT"
        $r.makerRate | Should Be 0.002
        $r.takerRate | Should Be 0.002
        $r.roundTrip | Should Be 0.4
        $r.source    | Should Be "fallback"
    }

    It "le maker_rate e taker_rate da API autenticada" {
        $global:COINEX_ACCESS_ID  = "FAKEID"
        $global:COINEX_SECRET_KEY = "FAKEKEY"
        Mock CoinEx-Get {
            [PSCustomObject]@{
                code = 0
                data = [PSCustomObject]@{
                    market     = "BTCUSDT"
                    maker_rate = "0.0003"
                    taker_rate = "0.0005"
                }
            }
        }
        Mock CoinEx-GetFundingRate { return $null }

        $r = CoinEx-GetFeeContext "BTCUSDT"
        $global:COINEX_ACCESS_ID  = $null
        $global:COINEX_SECRET_KEY = $null
        $r.makerRate | Should Be 0.0003
        $r.takerRate | Should Be 0.0005
        $r.roundTrip | Should Be 0.08
        $r.source    | Should Be "api"
    }

    It "holdCost24h = roundTrip + funding24h" {
        $global:COINEX_ACCESS_ID  = $null
        $global:COINEX_SECRET_KEY = $null
        Mock CoinEx-GetFundingRate { return 0.0002 }

        $r = CoinEx-GetFeeContext "BTCUSDT"
        $r.funding24h  | Should Be 0.06
        $r.holdCost24h | Should Be 0.46
    }

    It "holdCost24h = roundTrip quando funding indisponivel" {
        $global:COINEX_ACCESS_ID  = $null
        $global:COINEX_SECRET_KEY = $null
        Mock CoinEx-GetFundingRate { return $null }

        $r = CoinEx-GetFeeContext "BTCUSDT"
        $r.holdCost24h | Should Be 0.4
    }

    It "funding zero e valor valido — funding8h deve ser 0 nao null" {
        $global:COINEX_ACCESS_ID  = $null
        $global:COINEX_SECRET_KEY = $null
        Mock CoinEx-GetFundingRate { return 0.0 }

        $r = CoinEx-GetFeeContext "BTCUSDT"
        $r.funding8h   | Should Be 0.0
        $r.funding24h  | Should Be 0.0
        $r.holdCost24h | Should Be 0.4
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  CoinEx-GetTotalCapitalUSDT
# ─────────────────────────────────────────────────────────────────────────────

Describe "CoinEx-GetTotalCapitalUSDT" {

    It "soma spot USDT + futuros USDT" {
        $global:COINEX_ACCESS_ID  = "FAKE_ID"
        $global:COINEX_SECRET_KEY = "FAKE_SECRET"
        $global:CAPITAL_TOTAL     = 1000.0
        Mock CoinEx-Get {
            param($path)
            if ($path -match "spot") {
                return [PSCustomObject]@{ code=0; data=@(
                    [PSCustomObject]@{ ccy="USDT"; available="300" }
                    [PSCustomObject]@{ ccy="BTC";  available="0.001" }
                )}
            } else {
                return [PSCustomObject]@{ code=0; data=@(
                    [PSCustomObject]@{ ccy="USDT"; available="518.29" }
                )}
            }
        }

        $c = CoinEx-GetTotalCapitalUSDT
        $c | Should Be 818.29
    }

    It "usa fallback quando sem credenciais" {
        $global:COINEX_ACCESS_ID  = $null
        $global:COINEX_SECRET_KEY = $null
        $global:CAPITAL_SPOT      = 100.0
        $global:CAPITAL_FUTURES   = 718.0

        $c = CoinEx-GetTotalCapitalUSDT
        $c | Should Be 818.0
    }

    It "usa fallback quando API falha" {
        $global:COINEX_ACCESS_ID  = "FAKE_ID"
        $global:COINEX_SECRET_KEY = "FAKE_SECRET"
        $global:CAPITAL_SPOT      = 100.0
        $global:CAPITAL_FUTURES   = 718.0
        Mock CoinEx-Get { throw "network error" }

        $c = CoinEx-GetTotalCapitalUSDT
        $c | Should Be 818.0
    }

    It "ignora ativos nao-USDT no calculo" {
        $global:COINEX_ACCESS_ID  = "FAKE_ID"
        $global:COINEX_SECRET_KEY = "FAKE_SECRET"
        $global:CAPITAL_TOTAL     = 1000.0
        Mock CoinEx-Get {
            return [PSCustomObject]@{ code=0; data=@(
                [PSCustomObject]@{ ccy="BTC";  available="1" }
                [PSCustomObject]@{ ccy="USDT"; available="200" }
                [PSCustomObject]@{ ccy="ETH";  available="5" }
            )}
        }

        $c = CoinEx-GetTotalCapitalUSDT
        $c | Should Be 400.0  # 200 spot + 200 futuros
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  CoinEx-PlaceOrder — body construido corretamente (fix "Invalid Parameter")
#  Bug: stop_loss_price sem stop_loss_type causa rejeicao pela API V2.
#  Pattern: mockar CoinEx-Post para capturar o body que SERIA enviado.
# ─────────────────────────────────────────────────────────────────────────────

Describe "CoinEx-PlaceOrder - construcao do body" {

    BeforeEach {
        $global:COINEX_ACCESS_ID  = "FAKE_ID"
        $global:COINEX_SECRET_KEY = "FAKE_SECRET"
        $script:CapturedBody = $null
        $script:CapturedPath = $null
    }

    It "PlaceOrder com stopLoss inclui stop_loss_type='mark_price' no body" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            $script:CapturedPath = $path
            return [PSCustomObject]@{ code=0; data=@{ order_id=12345 } }
        }
        CoinEx-PlaceOrder "BTCUSDT" "buy" "market" 0.01 $null 90000 $null | Out-Null
        $script:CapturedBody.stop_loss_price | Should Be "90000"
        $script:CapturedBody.stop_loss_type  | Should Be "mark_price"
    }

    It "PlaceOrder com takeProfit inclui take_profit_type='mark_price' no body" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "BTCUSDT" "buy" "market" 0.01 $null $null 110000 | Out-Null
        $script:CapturedBody.take_profit_price | Should Be "110000"
        $script:CapturedBody.take_profit_type  | Should Be "mark_price"
    }

    It "PlaceOrder com stop E takeProfit inclui ambos types" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "BTCUSDT" "buy" "market" 0.01 $null 90000 110000 | Out-Null
        $script:CapturedBody.stop_loss_type    | Should Be "mark_price"
        $script:CapturedBody.take_profit_type  | Should Be "mark_price"
        $script:CapturedBody.stop_loss_price   | Should Be "90000"
        $script:CapturedBody.take_profit_price | Should Be "110000"
    }

    It "PlaceOrder sem stop nem TP NAO inclui stop_loss_type nem take_profit_type" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "BTCUSDT" "buy" "market" 0.01 | Out-Null
        $script:CapturedBody.ContainsKey("stop_loss_type")   | Should Be $false
        $script:CapturedBody.ContainsKey("take_profit_type") | Should Be $false
        $script:CapturedBody.ContainsKey("stop_loss_price")  | Should Be $false
        $script:CapturedBody.ContainsKey("take_profit_price")| Should Be $false
    }

    It "PlaceOrder LONG envia side='buy'" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "ETHUSDT" "buy" "market" 0.5 | Out-Null
        $script:CapturedBody.side | Should Be "buy"
    }

    It "PlaceOrder SHORT envia side='sell'" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "ETHUSDT" "sell" "market" 0.5 | Out-Null
        $script:CapturedBody.side | Should Be "sell"
    }

    It "PlaceOrder com market_type='FUTURES' presente" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            $script:CapturedPath = $path
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "BTCUSDT" "buy" "market" 0.01 | Out-Null
        $script:CapturedBody.market_type | Should Be "FUTURES"
        $script:CapturedBody.market      | Should Be "BTCUSDT"
        $script:CapturedPath             | Should Be "/v2/futures/order"
    }

    It "PlaceOrder amount e stringificado (nao enviado como numero)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "BTCUSDT" "buy" "market" 0.01 | Out-Null
        ($script:CapturedBody.amount -is [string]) | Should Be $true
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  CoinEx-PlaceSpotOrder — fix bug "SpotOrder error [3639]: Invalid Parameter"
#  Root cause: CoinEx V2 /v2/spot/order EXIGE o campo "ccy" em ordens MARKET
#  para indicar se "amount" refere-se a base ou quote currency. Sem ccy a API
#  rejeita com codigo 3639. Em market BUY usamos quote (USDT, amount em USD);
#  em market SELL usamos base (token, amount em qty).
# ─────────────────────────────────────────────────────────────────────────────

Describe "CoinEx-PlaceSpotOrder - construcao do body (fix code 3639)" {

    BeforeEach {
        $global:COINEX_ACCESS_ID  = "FAKE_ID"
        $global:COINEX_SECRET_KEY = "FAKE_SECRET"
        $script:CapturedBody = $null
        $script:CapturedPath = $null
    }

    It "PlaceSpotOrder envia market_type='SPOT' no body e path '/v2/spot/order'" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            $script:CapturedPath = $path
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotOrder -Market "AIUSDT" -Side "buy" -Type "market" -Amount 100 -QuoteAmountUsd 10 | Out-Null
        $script:CapturedBody.market_type | Should Be "SPOT"
        $script:CapturedBody.market      | Should Be "AIUSDT"
        $script:CapturedPath             | Should Be "/v2/spot/order"
    }

    It "PlaceSpotOrder MARKET BUY inclui ccy='USDT' (quote) e amount em USDT" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotOrder -Market "AIUSDT" -Side "buy" -Type "market" -Amount 100 -QuoteAmountUsd 9.50 | Out-Null
        $script:CapturedBody.ccy    | Should Be "USDT"
        $script:CapturedBody.amount | Should Be "9.5"
    }

    It "PlaceSpotOrder MARKET SELL inclui ccy=base (AI) e amount em base qty" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotOrder -Market "AIUSDT" -Side "sell" -Type "market" -Amount 100 | Out-Null
        $script:CapturedBody.ccy    | Should Be "AI"
        $script:CapturedBody.amount | Should Be "100"
    }

    It "PlaceSpotOrder LIMIT BUY inclui price e NAO precisa de ccy" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotOrder -Market "AIUSDT" -Side "buy" -Type "limit" -Amount 100 -Price 0.095 | Out-Null
        $script:CapturedBody.type    | Should Be "limit"
        $script:CapturedBody.price   | Should Be "0.095"
        $script:CapturedBody.amount  | Should Be "100"
        $script:CapturedBody.ContainsKey("ccy") | Should Be $false
    }

    It "PlaceSpotOrder side LONG -> 'buy'" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotOrder -Market "AIUSDT" -Side "buy" -Type "market" -Amount 100 -QuoteAmountUsd 10 | Out-Null
        $script:CapturedBody.side | Should Be "buy"
    }

    It "PlaceSpotOrder side SHORT -> 'sell'" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotOrder -Market "AIUSDT" -Side "sell" -Type "market" -Amount 100 | Out-Null
        $script:CapturedBody.side | Should Be "sell"
    }

    It "PlaceSpotOrder amount sempre stringificado (nunca numero)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotOrder -Market "AIUSDT" -Side "buy" -Type "market" -Amount 100 -QuoteAmountUsd 10 | Out-Null
        ($script:CapturedBody.amount -is [string]) | Should Be $true
    }

    It "PlaceSpotOrder MARKET BUY sem QuoteAmountUsd lanca erro (proteccao)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        $threw = $false
        try { CoinEx-PlaceSpotOrder -Market "AIUSDT" -Side "buy" -Type "market" -Amount 100 } catch { $threw = $true }
        $threw | Should Be $true
    }

    It "PlaceSpotOrder erro propaga codigo da API (3639)" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{ code=3639; message="Invalid Parameter"; data=$null }
        }
        { CoinEx-PlaceSpotOrder -Market "AIUSDT" -Side "buy" -Type "market" -Amount 100 -QuoteAmountUsd 10 } | Should Throw "3639"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  CoinEx-PlaceSpotStopOrder — fix InvariantCulture (mesmo bug 3639 latente)
#  Root cause: .ToString() em locale PT-BR/etc usa virgula -> API rejeita.
#  Padrao: forcar pt-BR durante o teste e verificar que body sai com ponto.
# ─────────────────────────────────────────────────────────────────────────────

Describe "CoinEx-PlaceSpotStopOrder - construcao do body (fix InvariantCulture)" {

    BeforeEach {
        $global:COINEX_ACCESS_ID  = "FAKE_ID"
        $global:COINEX_SECRET_KEY = "FAKE_SECRET"
        $script:CapturedBody = $null
        $script:CapturedPath = $null
        $script:OriginalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        [System.Threading.Thread]::CurrentThread.CurrentCulture = `
            [System.Globalization.CultureInfo]::GetCultureInfo("pt-BR")
    }

    AfterEach {
        [System.Threading.Thread]::CurrentThread.CurrentCulture = $script:OriginalCulture
    }

    It "PlaceSpotStopOrder serializa trigger_price com ponto (nao virgula PT-BR)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotStopOrder -Market "AIUSDT" -Side "sell" -TriggerPrice 0.099895 -Amount 100 | Out-Null
        $script:CapturedBody.trigger_price | Should Match "\."
        $script:CapturedBody.trigger_price | Should Not Match ","
    }

    It "PlaceSpotStopOrder serializa amount com ponto (nao virgula PT-BR)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotStopOrder -Market "AIUSDT" -Side "sell" -TriggerPrice 0.099895 -Amount 100.5 | Out-Null
        $script:CapturedBody.amount | Should Match "\."
        $script:CapturedBody.amount | Should Not Match ","
    }

    It "PlaceSpotStopOrder body tem decimais corretos para preco 0.099895 (sub-dollar)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotStopOrder -Market "AIUSDT" -Side "sell" -TriggerPrice 0.099895 -Amount 50 | Out-Null
        $script:CapturedBody.trigger_price | Should Be "0.099895"
    }

    It "PlaceSpotStopOrder body tem decimais corretos para preco 44.46 (HYPE-like)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotStopOrder -Market "HYPEUSDT" -Side "sell" -TriggerPrice 44.46 -Amount 2.5 | Out-Null
        $script:CapturedBody.trigger_price | Should Be "44.46"
        $script:CapturedBody.amount        | Should Be "2.5"
    }

    It "PlaceSpotStopOrder side='sell' (SHORT) preservado" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotStopOrder -Market "AIUSDT" -Side "sell" -TriggerPrice 0.05 -Amount 100 | Out-Null
        $script:CapturedBody.side | Should Be "sell"
    }

    It "PlaceSpotStopOrder side='buy' (LONG) preservado" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotStopOrder -Market "AIUSDT" -Side "buy" -TriggerPrice 0.15 -Amount 100 | Out-Null
        $script:CapturedBody.side | Should Be "buy"
    }

    It "PlaceSpotStopOrder market_type='SPOT' e path '/v2/spot/stop-order'" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            $script:CapturedPath = $path
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceSpotStopOrder -Market "AIUSDT" -Side "sell" -TriggerPrice 0.05 -Amount 100 | Out-Null
        $script:CapturedBody.market_type | Should Be "SPOT"
        $script:CapturedPath             | Should Be "/v2/spot/stop-order"
    }

    It "PlaceSpotStopOrder propaga erro da API (codigo 3639)" {
        Mock CoinEx-Post {
            return [PSCustomObject]@{ code=3639; message="Invalid Parameter"; data=$null }
        }
        { CoinEx-PlaceSpotStopOrder -Market "AIUSDT" -Side "sell" -TriggerPrice 0.05 -Amount 100 } | Should Throw "3639"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  CoinEx-PlaceOrder (FUTURES) — fix InvariantCulture
#  Root cause: $amount.ToString(), $price.ToString(), $stopLoss.ToString(),
#  $takeProfit.ToString() em locale PT-BR/etc usam virgula. API V2 da CoinEx
#  exige ponto decimal -- rejeicao silenciosa com code 3639 "Invalid Parameter".
#  Mesmo bug ja corrigido em CoinEx-PlaceSpotOrder/PlaceSpotStopOrder.
# ─────────────────────────────────────────────────────────────────────────────

Describe "CoinEx-PlaceOrder FUTURES InvariantCulture" {

    BeforeEach {
        $global:COINEX_ACCESS_ID  = "FAKE_ID"
        $global:COINEX_SECRET_KEY = "FAKE_SECRET"
        $script:CapturedBody = $null
        $script:OriginalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        [System.Threading.Thread]::CurrentThread.CurrentCulture = `
            [System.Globalization.CultureInfo]::GetCultureInfo("pt-BR")
    }

    AfterEach {
        [System.Threading.Thread]::CurrentThread.CurrentCulture = $script:OriginalCulture
    }

    It "PlaceOrder FUTURES serializa amount com ponto (sem virgula PT-BR)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "BTCUSDT" "buy" "market" 0.015 | Out-Null
        $script:CapturedBody.amount | Should Match "\."
        $script:CapturedBody.amount | Should Not Match ","
    }

    It "PlaceOrder FUTURES serializa price com ponto (sem virgula PT-BR)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "BTCUSDT" "buy" "limit" 0.015 95123.5 | Out-Null
        $script:CapturedBody.price | Should Match "\."
        $script:CapturedBody.price | Should Not Match ","
    }

    It "PlaceOrder FUTURES serializa stop_loss_price com ponto (sem virgula PT-BR)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "BTCUSDT" "buy" "market" 0.015 $null 89500.25 $null | Out-Null
        $script:CapturedBody.stop_loss_price | Should Match "\."
        $script:CapturedBody.stop_loss_price | Should Not Match ","
    }

    It "PlaceOrder FUTURES serializa take_profit_price com ponto (sem virgula PT-BR)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "BTCUSDT" "buy" "market" 0.015 $null $null 110500.75 | Out-Null
        $script:CapturedBody.take_profit_price | Should Match "\."
        $script:CapturedBody.take_profit_price | Should Not Match ","
    }

    It "Body capturado para HYPEUSDT (price 44.46, stop 22.23) tem decimais corretos" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "HYPEUSDT" "buy" "limit" 2.5 44.46 22.23 88.92 | Out-Null
        $script:CapturedBody.amount            | Should Be "2.5"
        $script:CapturedBody.price             | Should Be "44.46"
        $script:CapturedBody.stop_loss_price   | Should Be "22.23"
        $script:CapturedBody.take_profit_price | Should Be "88.92"
    }

    It "Body capturado para AIUSDT (0.099895) tem decimais corretos (sub-dollar)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        CoinEx-PlaceOrder "AIUSDT" "buy" "limit" 1000 0.099895 0.049948 0.199790 | Out-Null
        $script:CapturedBody.price             | Should Be "0.099895"
        $script:CapturedBody.stop_loss_price   | Should Be "0.049948"
        $script:CapturedBody.take_profit_price | Should Be "0.19979"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  CoinEx-SetStopLoss — fix InvariantCulture
#  Root cause: [math]::Round($price,4).ToString() em locale PT-BR usa virgula.
# ─────────────────────────────────────────────────────────────────────────────

Describe "CoinEx-SetStopLoss InvariantCulture" {

    BeforeEach {
        $global:COINEX_ACCESS_ID  = "FAKE_ID"
        $global:COINEX_SECRET_KEY = "FAKE_SECRET"
        $script:CapturedBody = $null
        $script:OriginalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        [System.Threading.Thread]::CurrentThread.CurrentCulture = `
            [System.Globalization.CultureInfo]::GetCultureInfo("pt-BR")
    }

    AfterEach {
        [System.Threading.Thread]::CurrentThread.CurrentCulture = $script:OriginalCulture
    }

    It "SetStopLoss serializa stop_loss_price com ponto (sem virgula PT-BR)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0 }
        }
        CoinEx-SetStopLoss "BTCUSDT" 89500.25 | Out-Null
        $script:CapturedBody.stop_loss_price | Should Match "\."
        $script:CapturedBody.stop_loss_price | Should Not Match ","
    }

    It "SetStopLoss inclui stop_loss_type='mark_price'" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0 }
        }
        CoinEx-SetStopLoss "BTCUSDT" 89500.25 | Out-Null
        $script:CapturedBody.stop_loss_type | Should Be "mark_price"
        $script:CapturedBody.market_type    | Should Be "FUTURES"
        $script:CapturedBody.market         | Should Be "BTCUSDT"
    }

    It "SetStopLoss body para preco sub-dollar (0.099895) e correto" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0 }
        }
        CoinEx-SetStopLoss "AIUSDT" 0.099895 | Out-Null
        # [math]::Round(0.099895, 4) = 0.0999
        $script:CapturedBody.stop_loss_price | Should Be "0.0999"
        $script:CapturedBody.stop_loss_price | Should Not Match ","
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  CoinEx Self-Trade Prevention (stp_mode) — TDD RED phase
#  CoinEx v2 suporta stp_mode="ct" (cancel-taker) por default em /v2/futures/order
#  e /v2/spot/order para evitar auto-execucao de multiplas ordens do mesmo bot.
# ─────────────────────────────────────────────────────────────────────────────

Describe "stp_mode — Self-Trade Prevention" {

    BeforeEach {
        $global:COINEX_ACCESS_ID  = "FAKE_ID"
        $global:COINEX_SECRET_KEY = "FAKE_SECRET"
        $script:CapturedBody = $null
    }

    It "CoinEx-PlaceOrder FUTURES inclui stp_mode='ct' no body por default" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=123 } }
        }
        CoinEx-PlaceOrder "BTCUSDT" "buy" "limit" 0.1 50000 $null $null | Out-Null
        $script:CapturedBody.stp_mode | Should Be "ct"
    }

    It "CoinEx-PlaceSpotOrder inclui stp_mode='ct' por default" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=456 } }
        }
        CoinEx-PlaceSpotOrder -Market "AIUSDT" -Side "buy" -Type "limit" -Amount 100 -Price 0.1 | Out-Null
        $script:CapturedBody.stp_mode | Should Be "ct"
    }

    It "CoinEx-PlaceSpotStopOrder inclui stp_mode='ct' por default" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=789 } }
        }
        CoinEx-PlaceSpotStopOrder -Market "AIUSDT" -Side "sell" -TriggerPrice 0.15 -Amount 100 | Out-Null
        $script:CapturedBody.stp_mode | Should Be "ct"
    }

    It "stp_mode e override-able via param -StpMode 'cm'" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=999 } }
        }
        CoinEx-PlaceOrder "BTCUSDT" "sell" "market" 0.05 $null $null $null -StpMode "cm" | Out-Null
        $script:CapturedBody.stp_mode | Should Be "cm"
    }

    It "stp_mode e override-able via param -StpMode 'both'" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=111 } }
        }
        CoinEx-PlaceSpotOrder -Market "BTCUSDT" -Side "sell" -Type "market" -Amount 1 -StpMode "both" | Out-Null
        $script:CapturedBody.stp_mode | Should Be "both"
    }

    It "stp_mode='none' -> nao inclui field no body (opt-out)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:CapturedBody = $bodyObj
            return [PSCustomObject]@{ code=0; data=@{ order_id=222 } }
        }
        CoinEx-PlaceOrder "AIUSDT" "buy" "limit" 1000 0.1 $null $null -StpMode "none" | Out-Null
        $script:CapturedBody.ContainsKey('stp_mode') | Should Be $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  CoinEx-PlaceMultiExitLadder — multi-TP/SL nativo (ate 20 cada)
#  Itera nos levels do Ladder e chama set-position-take-profit / set-position-stop-loss
# ─────────────────────────────────────────────────────────────────────────────

Describe "Multi Exit Ladder" {

    BeforeEach {
        $global:COINEX_ACCESS_ID  = "FAKE_ID"
        $global:COINEX_SECRET_KEY = "FAKE_SECRET"
        $script:LadderCalls = @()
    }

    It "PlaceMultiExitLadder com 3 TPs chama set-position-take-profit 3 vezes" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:LadderCalls += [PSCustomObject]@{ path=$path; body=$bodyObj }
            return [PSCustomObject]@{ code=0; data=@{ order_id=999 } }
        }
        $ladder = [PSCustomObject]@{
            template_id = "tori"
            tp_levels = @(
                [PSCustomObject]@{ type="price_pct"; price_pct=0.50; qty_pct=30 },
                [PSCustomObject]@{ type="price_pct"; price_pct=1.00; qty_pct=30 },
                [PSCustomObject]@{ type="price_pct"; price_pct=2.00; qty_pct=40 }
            )
            sl_levels = @()
        }
        $r = CoinEx-PlaceMultiExitLadder -Market "AIUSDT" -PositionSide "long" -TotalAmount 100 -Entry 0.10 -Ladder $ladder
        $tpCalls = @($script:LadderCalls | Where-Object { $_.path -like '*take-profit*' })
        $tpCalls.Count        | Should Be 3
        @($r.tp_orders).Count | Should Be 3
    }

    It "amount por TP correto: soma das amounts = TotalAmount" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:LadderCalls += [PSCustomObject]@{ path=$path; body=$bodyObj }
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        $ladder = [PSCustomObject]@{
            template_id = "tori"
            tp_levels = @(
                [PSCustomObject]@{ type="price_pct"; price_pct=0.50; qty_pct=30 },
                [PSCustomObject]@{ type="price_pct"; price_pct=1.00; qty_pct=30 },
                [PSCustomObject]@{ type="price_pct"; price_pct=2.00; qty_pct=40 }
            )
            sl_levels = @()
        }
        $r = CoinEx-PlaceMultiExitLadder -Market "AIUSDT" -PositionSide "long" -TotalAmount 100 -Entry 0.10 -Ladder $ladder
        $sumQty = ($r.tp_orders | Measure-Object -Property qty -Sum).Sum
        # 30 + 30 + 40 = 100
        $sumQty | Should Be 100
    }

    It "trigger price calculado corretamente por type=price_pct em LONG" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:LadderCalls += [PSCustomObject]@{ path=$path; body=$bodyObj }
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        $ladder = [PSCustomObject]@{
            template_id = "tori"
            tp_levels = @(
                [PSCustomObject]@{ type="price_pct"; price_pct=0.50; qty_pct=100 }
            )
            sl_levels = @()
        }
        $r = CoinEx-PlaceMultiExitLadder -Market "AIUSDT" -PositionSide "long" -TotalAmount 100 -Entry 0.10 -Ladder $ladder
        # 0.10 * (1 + 0.50) = 0.15
        [math]::Round($r.tp_orders[0].trigger_price, 4) | Should Be 0.15
    }

    It "SHORT inverte direcao: TP fica abaixo do entry" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:LadderCalls += [PSCustomObject]@{ path=$path; body=$bodyObj }
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        $ladder = [PSCustomObject]@{
            template_id = "tori"
            tp_levels = @(
                [PSCustomObject]@{ type="price_pct"; price_pct=0.50; qty_pct=100 }
            )
            sl_levels = @(
                [PSCustomObject]@{ type="price_pct"; price_pct=0.20; qty_pct=100 }
            )
        }
        $r = CoinEx-PlaceMultiExitLadder -Market "AIUSDT" -PositionSide "short" -TotalAmount 100 -Entry 0.10 -Ladder $ladder
        # SHORT TP: 0.10 * (1 - 0.50) = 0.05
        [math]::Round($r.tp_orders[0].trigger_price, 4) | Should Be 0.05
        # SHORT SL: 0.10 * (1 + 0.20) = 0.12
        [math]::Round($r.sl_orders[0].trigger_price, 4) | Should Be 0.12
    }

    It "falha graceful (throw) se ladder tem mais de 20 TPs" {
        $bigLadder = [PSCustomObject]@{
            template_id = "explode"
            tp_levels = @(1..21 | ForEach-Object {
                [PSCustomObject]@{ type="price_pct"; price_pct=0.10; qty_pct=5 }
            })
            sl_levels = @()
        }
        $threw = $false
        try { CoinEx-PlaceMultiExitLadder -Market "AIUSDT" -PositionSide "long" -TotalAmount 100 -Entry 0.10 -Ladder $bigLadder } catch { $threw = $true }
        $threw | Should Be $true
    }

    It "amount serializado via InvariantCulture (ponto, nao virgula, sub-dollar safe)" {
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:LadderCalls += [PSCustomObject]@{ path=$path; body=$bodyObj }
            return [PSCustomObject]@{ code=0; data=@{ order_id=1 } }
        }
        $ladder = [PSCustomObject]@{
            template_id = "tori"
            tp_levels = @(
                [PSCustomObject]@{ type="price_pct"; price_pct=0.0995; qty_pct=33.5 }
            )
            sl_levels = @()
        }
        $r = CoinEx-PlaceMultiExitLadder -Market "AIUSDT" -PositionSide "long" -TotalAmount 100 -Entry 0.099895 -Ladder $ladder
        $body = $script:LadderCalls[0].body
        $body.take_profit_price | Should Not Match ','
        $body.amount            | Should Not Match ','
    }
}