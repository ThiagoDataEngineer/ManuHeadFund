# lib_trailing_spot_partial_exit.Tests.ps1 -- TDD de Register-SpotPartialExit
# (agents/lib_trailing_spot_partial_exit.ps1)
#
# 2026-08-26: fecha o gap real "Resolve-TrailingDecision recomenda PARTIAL
# em SPOT mas nunca executa" (owner: "vejo +10%, +30%, e volta pro stop").
# Diferente do ladder de FUTURES (nativo, registra 1x, corretora executa
# sozinha), SPOT vende a mercado AGORA -- idempotencia por FRACAO ACUMULADA
# (nao repete venda ja coberta por um size_pct anterior igual/maior).
#
# Pester 3.4 (motor real de producao/CI). Padrao de mock: Set-Item -Path
# function:X -Value {...} dentro de It quando precisa variar entre testes
# (ver nota em lib_trailing_partial_exit.Tests.ps1).

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

# Stubs base (sobrescritos por Set-Item dentro de cada It quando precisam
# variar) -- evita depender de credenciais reais/Supabase.
function Get-StateRecords { param($Table, $Filter) @() }
function Save-StateRecords { param($Table, $Records, $PrimaryKey) $true }
function CoinEx-PlaceSpotOrder { param($Market, $Side, $Type, $Amount) [PSCustomObject]@{ filled_amount = $Amount } }

. (Join-Path $agentsDir "lib_trailing_spot_partial_exit.ps1")

Describe "Get-SpotPartialExitState / Save-SpotPartialExitState" {
    It "sem registro previo retorna 0.0" {
        Set-Item -Path function:Get-StateRecords -Value { param($Table, $Filter) @() }
        (Get-SpotPartialExitState -Market "XUSDT") | Should Be 0.0
    }
    It "com registro ativo retorna cumulative_pct" {
        Set-Item -Path function:Get-StateRecords -Value {
            param($Table, $Filter)
            @([PSCustomObject]@{ market = "XUSDT"; active = $true; cumulative_pct = 0.30 })
        }
        (Get-SpotPartialExitState -Market "XUSDT") | Should Be 0.30
    }
    It "com multiplos registros retorna o MAIOR cumulative_pct (mais recente/avancado)" {
        Set-Item -Path function:Get-StateRecords -Value {
            param($Table, $Filter)
            @(
                [PSCustomObject]@{ market = "XUSDT"; active = $true; cumulative_pct = 0.30 },
                [PSCustomObject]@{ market = "XUSDT"; active = $true; cumulative_pct = 0.75 }
            )
        }
        (Get-SpotPartialExitState -Market "XUSDT") | Should Be 0.75
    }
    It "Get-StateRecords indisponivel: fail-soft retorna 0.0" {
        Remove-Item function:Get-StateRecords -ErrorAction SilentlyContinue
        (Get-SpotPartialExitState -Market "XUSDT") | Should Be 0.0
        function Get-StateRecords { param($Table, $Filter) @() }
    }
}

Describe "Register-SpotPartialExit" {
    BeforeEach {
        Set-Item -Path function:Get-StateRecords -Value { param($Table, $Filter) @() }
        Set-Item -Path function:Save-StateRecords -Value { param($Table, $Records, $PrimaryKey) $true }
        Set-Item -Path function:CoinEx-PlaceSpotOrder -Value {
            param($Market, $Side, $Type, $Amount)
            $global:__spot_sell_market = $Market
            $global:__spot_sell_side = $Side
            $global:__spot_sell_amount = $Amount
            [PSCustomObject]@{ filled_amount = $Amount }
        }
    }

    It "SizePct<=0: guard, nao vende nada" {
        $r = Register-SpotPartialExit -Market "XUSDT" -SizePct 0 -RealQty 1000
        $r.success | Should Be $false
        $r.reason | Should Be "size_pct_invalido"
    }

    It "RealQty<=0: guard, nao vende nada" {
        $r = Register-SpotPartialExit -Market "XUSDT" -SizePct 0.75 -RealQty 0
        $r.success | Should Be $false
        $r.reason | Should Be "qty_zero"
    }

    It "primeira execucao (nada coberto ainda): vende exatamente SizePct do saldo real" {
        $global:__spot_sell_amount = $null
        $r = Register-SpotPartialExit -Market "XUSDT" -SizePct 0.75 -RealQty 1000
        $r.success | Should Be $true
        $r.reason | Should Be "ok"
        $expected = [math]::Floor(1000 * 0.75 * 1e6) / 1e6
        $global:__spot_sell_amount | Should Be $expected
        $global:__spot_sell_side | Should Be "sell"
    }

    It "recomendacao repetida (mesmo SizePct, ja coberto): NAO vende de novo -- regressao central do fix DOGEUSDT" {
        Set-Item -Path function:Get-StateRecords -Value {
            param($Table, $Filter)
            @([PSCustomObject]@{ market = "XUSDT"; active = $true; cumulative_pct = 0.75 })
        }
        $global:__spot_sell_amount = $null
        $r = Register-SpotPartialExit -Market "XUSDT" -SizePct 0.75 -RealQty 250
        $r.success | Should Be $true
        $r.reason | Should Be "already_covered"
        $r.sold_qty | Should Be 0.0
        $global:__spot_sell_amount | Should Be $null
    }

    It "recomendacao MAIOR que a ja coberta: vende so a fracao ADICIONAL do saldo atual" {
        # ja vendeu 30% da posicao original (sobrou 70% no saldo real).
        # motor agora recomenda 75% total -> falta 45% da original =
        # 45/70 = ~64.29% do saldo atual restante.
        Set-Item -Path function:Get-StateRecords -Value {
            param($Table, $Filter)
            @([PSCustomObject]@{ market = "XUSDT"; active = $true; cumulative_pct = 0.30 })
        }
        $global:__spot_sell_amount = $null
        $realQtyAtual = 700  # saldo real ja reduzido pela venda anterior de 30%
        $r = Register-SpotPartialExit -Market "XUSDT" -SizePct 0.75 -RealQty $realQtyAtual
        $r.success | Should Be $true
        $expectedFrac = 0.45 / 0.70
        $expected = [math]::Floor($realQtyAtual * $expectedFrac * 1e6) / 1e6
        $global:__spot_sell_amount | Should Be $expected
    }

    It "recomendacao MENOR que a ja coberta (motor recuou): NAO vende (nunca compra de volta)" {
        Set-Item -Path function:Get-StateRecords -Value {
            param($Table, $Filter)
            @([PSCustomObject]@{ market = "XUSDT"; active = $true; cumulative_pct = 0.75 })
        }
        $global:__spot_sell_amount = $null
        $r = Register-SpotPartialExit -Market "XUSDT" -SizePct 0.30 -RealQty 250
        $r.reason | Should Be "already_covered"
        $global:__spot_sell_amount | Should Be $null
    }

    It "CoinEx-PlaceSpotOrder lanca excecao: fail-soft, reporta sell_failed" {
        Set-Item -Path function:CoinEx-PlaceSpotOrder -Value { param($Market, $Side, $Type, $Amount) throw "network error" }
        $r = Register-SpotPartialExit -Market "XUSDT" -SizePct 0.75 -RealQty 1000
        $r.success | Should Be $false
        $r.reason -like "sell_failed*" | Should Be $true
    }

    It "CoinEx-PlaceSpotOrder ausente: reporta indisponivel, nao lanca" {
        Remove-Item function:CoinEx-PlaceSpotOrder -ErrorAction SilentlyContinue
        { $r = Register-SpotPartialExit -Market "XUSDT" -SizePct 0.75 -RealQty 1000 } | Should Not Throw
        $r = Register-SpotPartialExit -Market "XUSDT" -SizePct 0.75 -RealQty 1000
        $r.reason | Should Be "coinex_placespotorder_unavailable"
        function CoinEx-PlaceSpotOrder { param($Market, $Side, $Type, $Amount) [PSCustomObject]@{ filled_amount = $Amount } }
    }

    It "quantidade arredonda pra zero (fracao minuscula sobre saldo pequeno): nao tenta vender poeira" {
        $r = Register-SpotPartialExit -Market "XUSDT" -SizePct 0.0000001 -RealQty 1
        $r.success | Should Be $false
        $r.reason | Should Be "qty_zero_apos_arredondamento"
    }
}

Describe "Remove-SpotPartialExitState" {
    It "sem registro ativo: retorna true (nada pra fazer, nao e erro)" {
        Set-Item -Path function:Get-StateRecords -Value { param($Table, $Filter) @() }
        (Remove-SpotPartialExitState -Market "XUSDT") | Should Be $true
    }
    It "com registro ativo: chama Save-StateRecords desativando (active=false)" {
        Set-Item -Path function:Get-StateRecords -Value {
            param($Table, $Filter)
            @([PSCustomObject]@{ id = "abc"; market = "XUSDT"; active = $true; cumulative_pct = 0.75; reason = "r"; updated_at = "2026-01-01" })
        }
        $global:__saved_active = $null
        Set-Item -Path function:Save-StateRecords -Value {
            param($Table, $Records, $PrimaryKey)
            $global:__saved_active = $Records[0].active
            $true
        }
        (Remove-SpotPartialExitState -Market "XUSDT") | Should Be $true
        $global:__saved_active | Should Be $false
    }
}
