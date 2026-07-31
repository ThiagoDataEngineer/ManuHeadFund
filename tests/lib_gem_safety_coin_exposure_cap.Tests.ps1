# lib_gem_safety_coin_exposure_cap.Tests.ps1 -- TDD de Test-CoinExposureCap
# (lib_gem_safety.ps1) e do wiring real em gem_executor.ps1 que soma margem
# FUTURES ao HeldUsd.
#
# 2026-07-30: achado real (owner reportou DOGEUSDT SHORT crescendo de $1097
# para $1165 de margem AO LONGO DO DIA, mesmo com o cascade guard de 07-29
# funcionando). Causa raiz: o cascade guard (gem_executor.ps1 ~893-951) so
# limita 3 "Add Position" por janela de 6h -- depois RESETA e permite mais 3,
# indefinidamente. O UNICO guard de teto absoluto por moeda, Test-
# CoinExposureCap, era chamado com HeldUsd calculado SO do saldo SPOT
# (/v2/assets/spot/balance) -- para um par FUTURES como DOGEUSDT, esse saldo
# e tipicamente zero, entao o cap nunca via a posicao real e nunca bloqueava.
# Fix: gem_executor.ps1 agora soma $existingPosition.cml_position_value
# (margem FUTURES real, ja resolvida pelo cascade guard mais acima na mesma
# funcao) ao heldUsd antes de chamar Test-CoinExposureCap.
#
# Pester 3.4 (motor real de producao/CI) / ASCII-only.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_gem_safety.ps1")

Describe "Test-CoinExposureCap -- funcao pura (contrato)" {

    It "permite quando HeldUsd=0 e trade pequeno" {
        $r = Test-CoinExposureCap -HeldUsd 0.0 -TradeUsd 30.0 -PortfolioUsd 1000.0
        $r.allowed | Should Be $true
    }

    It "bloqueia por 'ja_posicionado' quando HeldUsd >= ReentryBlockUsd (default 5.0)" {
        $r = Test-CoinExposureCap -HeldUsd 50.0 -TradeUsd 30.0 -PortfolioUsd 1000.0
        $r.allowed | Should Be $false
        $r.reason  | Should Be "ja_posicionado"
    }

    It "bloqueia por 'cap_por_moeda' quando projetado >= MaxPerCoinPct (default 10%)" {
        $r = Test-CoinExposureCap -HeldUsd 0.0 -TradeUsd 150.0 -PortfolioUsd 1000.0 -ReentryBlockUsd 200.0
        $r.allowed | Should Be $false
        $r.reason  | Should Be "cap_por_moeda"
    }

    It "caso real DOGEUSDT: margem FUTURES de `$1097 sobre capital de `$1326 -- bloqueia re-entrada" {
        # Dado real observado (print CoinEx 2026-07-30): DOGEUSDT SHORT
        # Position Margin=1097.58 USDT, Available=1326.27 USDT.
        $r = Test-CoinExposureCap -HeldUsd 1097.58 -TradeUsd 100.0 -PortfolioUsd 1326.27
        $r.allowed | Should Be $false
        $r.reason  | Should Be "ja_posicionado"
    }
}

Describe "gem_executor.ps1 -- HeldUsd agora inclui margem FUTURES (fix 2026-07-30)" {

    BeforeAll {
        $script:src = Get-Content (Join-Path $agentsDir "gem_executor.ps1") -Raw
    }

    It "soma existingPosition.cml_position_value ao heldUsd antes do cap" {
        ($script:src -match [regex]::Escape('$heldUsd += [double]$existingPosition.cml_position_value')) | Should Be $true
    }

    It "a soma acontece DENTRO do bloco EXPOSURE CAP (nao em outro lugar desconectado)" {
        $idx = $script:src.IndexOf('COIN EXPOSURE CAP')
        $idxFix = $script:src.IndexOf('$heldUsd += [double]$existingPosition.cml_position_value')
        $idxCall = $script:src.IndexOf('$cap = Test-CoinExposureCap')
        ($idx -ge 0 -and $idxFix -gt $idx -and $idxCall -gt $idxFix) | Should Be $true
    }
}
