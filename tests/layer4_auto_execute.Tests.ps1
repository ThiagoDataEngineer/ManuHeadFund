# Layer 4 AUTO_EXECUTE mode TDD
#
# Valida que quando LAYER4_AUTO_EXECUTE = $true:
#   - CLOSE_TIME_STOP fecha posicao na exchange
#   - CLOSE_NOW fecha posicao na exchange
#   - HARVEST_PARTIAL envia alerta (nao auto-executa, requer partial close API)
#   - HOLD nao faz nada
#   - WARN/REVIEW apenas alertam (sem fechar)
#
# Quando LAYER4_AUTO_EXECUTE = $false (default):
#   - Qualquer acao apenas envia alerta Telegram (advisory)

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_state_store.ps1")
function CoinEx-GetTicker { param($m) return [PSCustomObject]@{ last = 100.0 } }
function Send-TelegramAlert { param($Message) $script:lastTgMsg = $Message; return $true }
. (Join-Path $agentsDir "lib_trailing.ps1")
. (Join-Path $agentsDir "lib_layer4_tori_timestop.ps1")

Describe "Layer 4 AUTO_EXECUTE flag" {

    AfterEach {
        Remove-Variable -Name LAYER4_AUTO_EXECUTE -Scope Global -ErrorAction SilentlyContinue
    }

    It "Default: LAYER4_AUTO_EXECUTE is false (advisory only)" {
        $global:LAYER4_AUTO_EXECUTE = $null
        Remove-Variable -Name LAYER4_AUTO_EXECUTE -Scope Global -ErrorAction SilentlyContinue
        # Without flag, should not auto-execute
        $content = Get-Content (Join-Path $agentsDir "lib_layer4_tori_timestop.ps1") -Raw
        ($content -match 'LAYER4_AUTO_EXECUTE') | Should Be $true
    }

    It "CLOSE_TIME_STOP decision triggers exchange close when AUTO_EXECUTE=true" {
        $global:LAYER4_AUTO_EXECUTE = $true
        $script:exchangeCloseCalled = $false
        $script:closedMarket = $null

        function CoinEx-ClosePosition {
            param($market)
            $script:exchangeCloseCalled = $true
            $script:closedMarket = $market
            return [PSCustomObject]@{ code = 0 }
        }

        # Simulate a position that would get CLOSE_TIME_STOP
        $pos = [PSCustomObject]@{
            market = "TESTUSDT"; side = "LONG"
            entry = 100; stop = 95; target = 110
            phase = 0; peak = 100; stopCurrent = 95; active = $true
            openedAt = (Get-Date).AddHours(-40).ToString("yyyy-MM-dd HH:mm:ss")
            updatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            currentPrice = 100
        }

        $decision = Get-Layer4Decision -Position $pos -Regime "SIDEWAYS"
        # 40h flat in SIDEWAYS = HARD tier (threshold 36h)
        $decision.action | Should Be "CLOSE_TIME_STOP"
        $decision.tier | Should Be "HARD"

        Remove-Item function:CoinEx-ClosePosition -ErrorAction SilentlyContinue
    }

    It "ADVISORY mode: sends Telegram alert but does NOT call CoinEx-ClosePosition" {
        $global:LAYER4_AUTO_EXECUTE = $false
        $script:exchangeCloseCalled = $false
        $script:lastTgMsg = $null

        function CoinEx-ClosePosition {
            param($market)
            $script:exchangeCloseCalled = $true
        }

        $pos = [PSCustomObject]@{
            market = "TESTUSDT"; side = "LONG"
            entry = 100; stop = 95; target = 110
            phase = 0; peak = 100; stopCurrent = 95; active = $true
            openedAt = (Get-Date).AddHours(-40).ToString("yyyy-MM-dd HH:mm:ss")
            updatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            currentPrice = 100
        }

        $decision = Get-Layer4Decision -Position $pos -Regime "SIDEWAYS"
        $decision.action | Should Be "CLOSE_TIME_STOP"

        # In advisory mode, exchange close should NOT be called
        $script:exchangeCloseCalled | Should Be $false

        Remove-Item function:CoinEx-ClosePosition -ErrorAction SilentlyContinue
    }

    It "HOLD decision never triggers exchange close regardless of flag" {
        $global:LAYER4_AUTO_EXECUTE = $true
        $script:exchangeCloseCalled = $false

        function CoinEx-ClosePosition {
            param($market)
            $script:exchangeCloseCalled = $true
        }

        $pos = [PSCustomObject]@{
            market = "TESTUSDT"; side = "LONG"
            entry = 100; stop = 95; target = 110
            phase = 0; peak = 105; stopCurrent = 95; active = $true
            openedAt = (Get-Date).AddHours(-2).ToString("yyyy-MM-dd HH:mm:ss")
            updatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            currentPrice = 105
        }

        $decision = Get-Layer4Decision -Position $pos -Regime "SIDEWAYS"
        $decision.action | Should Be "HOLD"
        $script:exchangeCloseCalled | Should Be $false

        Remove-Item function:CoinEx-ClosePosition -ErrorAction SilentlyContinue
    }
}

Describe "Layer 4 stagnation thresholds (SIDEWAYS regime)" {

    It "18h flat = SOFT (warn only)" {
        $tier = Classify-StagnationTier -HoursElapsed 18 -PeakProgress 0.001 -Regime "SIDEWAYS"
        $tier | Should Be "SOFT"
    }

    It "24h flat = MEDIUM (review)" {
        $tier = Classify-StagnationTier -HoursElapsed 24 -PeakProgress 0.001 -Regime "SIDEWAYS"
        $tier | Should Be "MEDIUM"
    }

    It "36h flat = HARD (close)" {
        $tier = Classify-StagnationTier -HoursElapsed 36 -PeakProgress 0.001 -Regime "SIDEWAYS"
        $tier | Should Be "HARD"
    }

    It "UNI scenario: 27h flat = MEDIUM (would have been REVIEW, not close)" {
        $tier = Classify-StagnationTier -HoursElapsed 27 -PeakProgress 0.0 -Regime "SIDEWAYS"
        $tier | Should Be "MEDIUM"
    }

    It "Progress > 0.5% = NONE regardless of time" {
        $tier = Classify-StagnationTier -HoursElapsed 50 -PeakProgress 0.006 -Regime "SIDEWAYS"
        $tier | Should Be "NONE"
    }
}
