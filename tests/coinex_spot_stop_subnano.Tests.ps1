# coinex_spot_stop_subnano.Tests.ps1 -- TDD precisao sub-nano em stop spot (2026-06-05)
#
# Incidente: PEPE2USDT (preco ~2e-9) entrou e o stop FALHOU as 2 vezes -> long NU.
# Causa: CoinEx-PlaceSpotStopOrder fazia Round(trigger,8) -> 1.006e-9 virava "0"
# -> API rejeita (code != 0). Fix: decimal+12 casas preserva sub-nano; defensivo
# aborta se trigger formatar para 0 (regra de ouro #1: nunca posicao sem stop).

$global:COINEX_BASE_URL   = "https://api.coinex.com"
$global:COINEX_ACCESS_ID  = "test_access_id"
$global:COINEX_SECRET_KEY = "test_secret_key"

function Write-Host { param() }
function Write-Warning { param() }

. "$PSScriptRoot\..\agents\lib_coinex.ps1"

Describe "CoinEx-PlaceSpotStopOrder - precisao sub-nano" {

    It "preserva trigger_price sub-nano (PEPE2 1.006e-9 NAO vira 0)" {
        $script:capturedTrigger = $null
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:capturedTrigger = $bodyObj.trigger_price
            return [PSCustomObject]@{ code = 0; message = "OK"; data = [PSCustomObject]@{ order_id = "1"; status = "open" } }
        }

        CoinEx-PlaceSpotStopOrder -Market "PEPE2USDT" -Side "sell" -TriggerPrice 1.006e-9 -Amount 17000000000 | Out-Null

        $script:capturedTrigger | Should Not BeNullOrEmpty
        ([double]$script:capturedTrigger) | Should BeGreaterThan 0
        # ~1.006e-9 com tolerancia
        ([math]::Abs([double]$script:capturedTrigger - 1.006e-9) -lt 1e-12) | Should Be $true
    }

    It "formata preco normal (0.3872) sem regressao" {
        $script:capturedTrigger2 = $null
        Mock CoinEx-Post {
            param($path, $bodyObj)
            $script:capturedTrigger2 = $bodyObj.trigger_price
            return [PSCustomObject]@{ code = 0; message = "OK"; data = [PSCustomObject]@{ order_id = "2"; status = "open" } }
        }

        CoinEx-PlaceSpotStopOrder -Market "FIROUSDT" -Side "sell" -TriggerPrice 0.3872 -Amount 23.17 | Out-Null

        ([double]$script:capturedTrigger2) | Should Be 0.3872
    }

    It "ABORTA (throw) se trigger formatar para 0 -- nunca posicao sem stop" {
        Mock CoinEx-Post { return [PSCustomObject]@{ code = 0; data = [PSCustomObject]@{} } }
        # 1e-15 < 1e-12 de precisao -> arredonda pra 0 -> deve abortar em vez de enviar 0
        { CoinEx-PlaceSpotStopOrder -Market "DUSTUSDT" -Side "sell" -TriggerPrice 1e-15 -Amount 100 } | Should Throw
    }
}
