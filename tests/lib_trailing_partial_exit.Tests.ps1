# lib_trailing_partial_exit.Tests.ps1 -- TDD de Register-PartialExitLadder
# (agents/lib_trailing_partial_exit.ps1)
#
# 2026-07-31: owner pediu execucao REAL de PARTIAL/EXIT -- ate agora
# Resolve-TrailingDecision so LOGAVA a recomendacao (size_pct=0.75 etc),
# nunca executava venda de verdade. Achado critico durante o design:
# Get-ExitDecision (lib_trailing_policy.ps1) e STATELESS -- size_pct e
# "quanto deveria sobrar", nao "quanto vender agora". Executar isso
# ingenuamente a cada ciclo de 5min venderia repetidamente sobre o que
# sobrou, esvaziando a posicao de forma descontrolada (confirmado real:
# DOGEUSDT recomendou size_pct=0.75 continuamente por >1h sem mudar).
#
# Solucao: em vez de "vender agora", registra um LADDER de saida
# escalonada NATIVO na corretora (CoinEx-PlaceMultiExitLadder, ja usado
# em producao na abertura de posicoes novas, suporta ate 20 TPs com
# quantidade parcial real -- confirmado real: DOGEUSDT hoje tem
# take_profit_list com is_all=true, ou seja, SUBSTITUI um TP "cobre tudo"
# por multiplos niveis parciais). A corretora executa cada nivel sozinha
# quando o preco bate -- resolve o problema "stateless" de raiz, nao
# depende do pipeline rodar no momento exato. Idempotencia via Supabase
# (registra 1x por posicao, nao repete a cada ciclo).
#
# NOTA DE TESTE: "function global:X {...}" declarado DENTRO de um bloco It
# NAO sobrescreve uma funcao ja definida no escopo do script (confirmado
# via debug isolado: Pester 3.4 nao propaga essa redefinicao pro escopo
# em que a funcao sob teste roda). O padrao correto e' "Set-Item -Path
# function:X -Value {...}", que funciona de dentro do It. Usado em todo
# mock que precisa variar entre testes; mocks que sao IGUAIS pro arquivo
# inteiro ficam como "function X {...}" normal no topo (funciona porque
# e a UNICA definicao, nunca precisa sobrescrever nada).
#
# Pester 3.4 (motor real de producao/CI) / ASCII-only.

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

# _MultiLadder-ResolvePrice (usado pela validacao local de preco antes de
# cancelar o TP antigo, 2026-07-31 FIX) vive em lib_coinex.ps1 -- dot-source
# ANTES dos mocks abaixo pra pegar essa dependencia real, mas os mocks de
# CoinEx-CancelPositionTakeProfit/CoinEx-PlaceMultiExitLadder (que TAMBEM
# vivem em lib_coinex.ps1) precisam ser definidos DEPOIS pra sobrescrever
# as versoes reais (que chamam CoinEx-Post de verdade e exigem credenciais).
. (Join-Path $agentsDir "lib_coinex.ps1")

# Mocks fixos (nao variam entre testes -- ficam como definicao normal, sem
# global:, no escopo do script, ANTES do dot-source real).
function CoinEx-CancelPositionTakeProfit {
    param([string]$Market)
    $global:__cancel_called = $true
    $global:__cancel_market = $Market
    [PSCustomObject]@{ success = $true }
}
function CoinEx-PlaceMultiExitLadder {
    param($Market, $PositionSide, $TotalAmount, $Entry, $Ladder)
    $global:__ladder_called = $true
    $global:__ladder_market = $Market
    $global:__ladder_side = $PositionSide
    $global:__ladder_total = $TotalAmount
    $global:__ladder_levels = $Ladder.tp_levels
    [PSCustomObject]@{
        tp_orders = @($Ladder.tp_levels | ForEach-Object {
            [PSCustomObject]@{ level_index = 1; trigger_price = 0.05; qty = ($TotalAmount * $_.qty_pct / 100); response = [PSCustomObject]@{ code = 0 } }
        })
    }
}
function Get-PartialExitLadderRegistered { param($Market) $false }
function Save-PartialExitLadderRegistered { param($Market, $Details) $true }

. (Join-Path $agentsDir "lib_trailing_partial_exit.ps1")

function New-TestPosition {
    param(
        [string]$Market = "TESTUSDT",
        [string]$Side = "SHORT",
        [double]$Entry = 0.070985,
        [double]$StopCurrent = 0.071063,
        [double]$OpenInterest = 16577.0
    )
    [PSCustomObject]@{
        market = $Market; side = $Side; entry = $Entry
        stopCurrent = $StopCurrent; open_interest = $OpenInterest
    }
}

function New-TestPartials {
    @(
        @{ at_r = 1.0; pct = 0.5 },
        @{ at_r = 2.0; pct = 0.25 }
    )
}

function Reset-PartialExitMocks {
    # 2026-07-31: CoinEx-PlaceMultiExitLadder/CoinEx-Post precisam ser
    # restaurados aqui tambem -- um teste (restore-on-failure) sobrescreve
    # ambos via Set-Item, e essa redefinicao VAZA pros Describe blocks
    # seguintes no mesmo arquivo/processo Pester 3.4 se nao for resetada
    # explicitamente em todo BeforeEach (mesma classe de bug ja documentada
    # em memory: feedback_pester3_remove_item_function_leaks_across_describe).
    $global:__cancel_called = $false
    $global:__ladder_called = $false
    Set-Item -Path function:Get-PartialExitLadderRegistered -Value { param($Market) $false }
    Set-Item -Path function:CoinEx-CancelPositionTakeProfit -Value {
        param([string]$Market)
        $global:__cancel_called = $true
        $global:__cancel_market = $Market
        [PSCustomObject]@{ success = $true }
    }
    Set-Item -Path function:CoinEx-PlaceMultiExitLadder -Value {
        param($Market, $PositionSide, $TotalAmount, $Entry, $Ladder)
        $global:__ladder_called = $true
        $global:__ladder_market = $Market
        $global:__ladder_side = $PositionSide
        $global:__ladder_total = $TotalAmount
        $global:__ladder_levels = $Ladder.tp_levels
        [PSCustomObject]@{
            tp_orders = @($Ladder.tp_levels | ForEach-Object {
                [PSCustomObject]@{ level_index = 1; trigger_price = 0.05; qty = ($TotalAmount * $_.qty_pct / 100); response = [PSCustomObject]@{ code = 0 } }
            })
        }
    }
}

Describe "Register-PartialExitLadder -- primeira execucao (caminho feliz)" {

    BeforeEach { Reset-PartialExitMocks }

    It "cancela o TP atual (is_all=true) antes de registrar o ladder novo" {
        $pos = New-TestPosition
        $r = Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance 0.000078
        $global:__cancel_called | Should Be $true
        $global:__cancel_market | Should Be "TESTUSDT"
    }

    It "registra o ladder via CoinEx-PlaceMultiExitLadder com side/amount corretos" {
        $pos = New-TestPosition
        $r = Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance 0.000078
        $global:__ladder_called | Should Be $true
        $global:__ladder_market | Should Be "TESTUSDT"
        $global:__ladder_side | Should Be "short"
        $global:__ladder_total | Should Be 16577.0
    }

    It "converte partials (at_r/pct) para tp_levels (absolute price ja resolvido/qty_pct) corretamente" {
        # 2026-07-31 FIX #2: os niveis viram type="absolute" com price JA
        # RESOLVIDO (ancorado no entry ou no preco atual, o que for valido
        # pro lado da posicao) em vez de "rr_multiple" cru -- ver teste de
        # ancoragem abaixo pra cobertura do calculo em si.
        $pos = New-TestPosition
        $r = Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance 0.000078
        $levels = @($global:__ladder_levels)
        $levels.Count | Should Be 2
        $levels[0].type | Should Be "absolute"
        ($levels[0].price -gt 0) | Should Be $true
        $levels[0].qty_pct | Should Be 50
        ($levels[1].price -gt 0) | Should Be $true
        $levels[1].qty_pct | Should Be 25
    }

    It "retorna success=true quando cancel + ladder OK" {
        $pos = New-TestPosition
        $r = Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance 0.000078
        $r.success | Should Be $true
    }
}

Describe "Register-PartialExitLadder -- idempotencia (nao repete a cada ciclo)" {

    BeforeEach { Reset-PartialExitMocks }

    It "NAO chama cancel/ladder de novo se ja foi registrado antes para essa posicao" {
        Set-Item -Path function:Get-PartialExitLadderRegistered -Value { param($Market) $true }

        $pos = New-TestPosition
        $r = Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance 0.000078

        $global:__cancel_called | Should Be $false
        $global:__ladder_called | Should Be $false
        $r.success | Should Be $true
        $r.reason | Should Be "already_registered"
    }
}

Describe "Register-PartialExitLadder -- fail-safe (nao registra ladder sem cancelar TP antigo)" {

    BeforeEach { Reset-PartialExitMocks }

    It "se CoinEx-CancelPositionTakeProfit falhar, NAO tenta registrar o ladder (evita 2 TPs conflitantes)" {
        Set-Item -Path function:CoinEx-CancelPositionTakeProfit -Value {
            param([string]$Market)
            [PSCustomObject]@{ success = $false; error_msg = "simulated_failure" }
        }

        $pos = New-TestPosition
        $r = Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance 0.000078

        $global:__ladder_called | Should Be $false
        $r.success | Should Be $false
        $r.reason | Should Be "cancel_tp_failed"
    }

    It "sem Partials (array vazio) -- nao faz nada, retorna reason=no_partials" {
        $pos = New-TestPosition
        $r = Register-PartialExitLadder -Position $pos -Partials @() -StopDistance 0.000078

        $global:__cancel_called | Should Be $false
        $global:__ladder_called | Should Be $false
        $r.success | Should Be $false
        $r.reason | Should Be "no_partials"
    }

    It "2026-07-31 FIX: se o ladder falhar DEPOIS do cancel, restaura o TP original (nao deixa a posicao sem protecao)" {
        Set-Item -Path function:CoinEx-PlaceMultiExitLadder -Value {
            param($Market, $PositionSide, $TotalAmount, $Entry, $Ladder)
            throw "simulated CoinEx-PlaceMultiExitLadder failure"
        }
        $global:__restore_body = $null
        Set-Item -Path function:CoinEx-Post -Value {
            param($path, $bodyObj)
            if ($path -eq "/v2/futures/set-position-take-profit") {
                $global:__restore_body = $bodyObj
            }
            [PSCustomObject]@{ code = 0 }
        }

        $pos = New-TestPosition
        $pos | Add-Member -MemberType NoteProperty -Name take_profit_price -Value "0.068693" -Force
        $r = Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance 0.000078

        $global:__cancel_called | Should Be $true
        $r.success | Should Be $false
        ($r.reason -like "ladder_call_failed*") | Should Be $true
        $global:__restore_body.take_profit_price | Should Be "0.068693"
    }

    It "2026-07-31 FIX #3: se a CoinEx rejeitar TODOS os niveis (ex: preco do lado errado, code=3137), restaura o TP original em vez de reportar success=true" {
        # Achado real (run 30660720356): CoinEx-PlaceMultiExitLadder nao
        # lanca excecao por ordem rejeitada -- so registra o erro dentro de
        # tp_orders[].response e retorna normalmente. Sem essa checagem
        # explicita, Register-PartialExitLadder reportava success=true com
        # a posicao efetivamente sem NENHUM TP novo (o antigo ja cancelado).
        Set-Item -Path function:CoinEx-PlaceMultiExitLadder -Value {
            param($Market, $PositionSide, $TotalAmount, $Entry, $Ladder)
            [PSCustomObject]@{
                tp_orders = @($Ladder.tp_levels | ForEach-Object {
                    [PSCustomObject]@{ level_index = 1; trigger_price = $_.price; qty = 0; response = [PSCustomObject]@{ code = 3137; message = "Take-Profit price cannot be higher than the current price" } }
                })
            }
        }
        $global:__restore_body = $null
        Set-Item -Path function:CoinEx-Post -Value {
            param($path, $bodyObj)
            if ($path -eq "/v2/futures/set-position-take-profit") { $global:__restore_body = $bodyObj }
            [PSCustomObject]@{ code = 0 }
        }

        $pos = New-TestPosition
        $pos | Add-Member -MemberType NoteProperty -Name take_profit_price -Value "0.068693" -Force
        $r = Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance 0.000078

        $r.success | Should Be $false
        ($r.reason -like "ladder_all_levels_rejected*3137*") | Should Be $true
        $global:__restore_body.take_profit_price | Should Be "0.068693"
    }

    It "2026-07-31 FIX #4: se APENAS ALGUNS niveis forem aceitos (nao todos), tambem restaura o TP original em vez de reportar success=true" {
        # Achado real (2026-08-01): mesmo depois do fix #3, o check so exigia
        # tpOrdersOk.Count -gt 0 (PELO MENOS 1 nivel aceito) -- se 1 de 2
        # niveis falhasse, ainda reportava success=true, deixando a posicao
        # com um ladder "pela metade" (ex: so 50% coberto por TP, os outros
        # 50% efetivamente sem protecao de saida parcial planejada, so o
        # SL). Owner pediu: exigir TODOS os niveis aceitos, senao desfaz.
        Set-Item -Path function:CoinEx-PlaceMultiExitLadder -Value {
            param($Market, $PositionSide, $TotalAmount, $Entry, $Ladder)
            $i = 0
            [PSCustomObject]@{
                tp_orders = @($Ladder.tp_levels | ForEach-Object {
                    $i++
                    $resp = if ($i -eq 1) {
                        [PSCustomObject]@{ code = 0; message = "" }
                    } else {
                        [PSCustomObject]@{ code = 3137; message = "Take-Profit price cannot be higher than the current price" }
                    }
                    [PSCustomObject]@{ level_index = $i; trigger_price = $_.price; qty = 100; response = $resp }
                })
            }
        }
        $global:__restore_body = $null
        Set-Item -Path function:CoinEx-Post -Value {
            param($path, $bodyObj)
            if ($path -eq "/v2/futures/set-position-take-profit") { $global:__restore_body = $bodyObj }
            [PSCustomObject]@{ code = 0 }
        }

        $pos = New-TestPosition
        $pos | Add-Member -MemberType NoteProperty -Name take_profit_price -Value "0.068693" -Force
        $r = Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance 0.000078

        $r.success | Should Be $false
        ($r.reason -like "ladder_partial_rejection*") | Should Be $true
        ($r.reason -like "*1/2*" -or $r.reason -like "*aceitos=1*") | Should Be $true
        $global:__restore_body.take_profit_price | Should Be "0.068693"
    }

    It "2026-07-31 FIX #4: se TODOS os niveis forem aceitos, reporta success=true normalmente (nao regride o caminho feliz)" {
        $pos = New-TestPosition
        $r = Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance 0.000078

        $r.success | Should Be $true
        $r.reason | Should Be "ok"
    }
}

Describe "Register-PartialExitLadder -- ancoragem no preco atual (2026-07-31 FIX #2)" {

    BeforeEach { Reset-PartialExitMocks }

    It "SHORT ja rodou mais que os niveis de R pedidos -- ancora no preco atual em vez do entry (evita TP do lado errado)" {
        # Cenario real DOGEUSDT (run 30660720356): entry=0.070493,
        # StopDistance(1R)=0.0000785 -- rr=1 e rr=2 baseados no entry
        # resolvem pra 0.070415/0.070336, AMBOS ainda ACIMA do preco atual
        # real (~0.069816) porque a posicao SHORT ja rodou ~9x mais que 1R.
        # Mockando CoinEx-GetTicker com esse preco real, o nivel final deve
        # ficar ABAIXO do preco atual (lado correto pra TP de SHORT).
        Set-Item -Path function:CoinEx-GetTicker -Value { param($market) [PSCustomObject]@{ last = "0.069816" } }
        try {
            $pos = New-TestPosition -Market "DOGEUSDT" -Side "SHORT" -Entry 0.07049319659769560234 -OpenInterest 16577.0
            Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance 0.00007850999999999 | Out-Null

            $levels = @($global:__ladder_levels)
            $currentPrice = 0.069816
            foreach ($lvl in $levels) {
                ($lvl.price -lt $currentPrice) | Should Be $true
            }
            # nivel 2 (rr=2, mais distante) deve ficar mais longe do preco atual que o nivel 1
            ($levels[1].price -lt $levels[0].price) | Should Be $true
        } finally {
            Remove-Item -Path function:CoinEx-GetTicker -ErrorAction SilentlyContinue
        }
    }

    It "SHORT ainda NAO rodou alem dos niveis de R pedidos -- usa o preco baseado no entry normalmente (comportamento antigo preservado)" {
        # preco atual ainda proximo do entry (posicao mal abriu) -- os niveis
        # rr=1/rr=2 baseados no entry ja ficam do lado certo (abaixo, pra
        # SHORT), entao NAO precisa ancorar no preco atual.
        Set-Item -Path function:CoinEx-GetTicker -Value { param($market) [PSCustomObject]@{ last = "0.070900" } }
        try {
            $pos = New-TestPosition -Market "DOGEUSDT" -Side "SHORT" -Entry 0.07049319659769560234 -OpenInterest 16577.0
            Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance 0.00007850999999999 | Out-Null

            $levels = @($global:__ladder_levels)
            $entry = 0.07049319659769560234
            $stopDistance = 0.00007850999999999
            $expectedLevel1 = $entry - (1.0 * $stopDistance)
            ([math]::Abs($levels[0].price - $expectedLevel1) -lt 0.0000001) | Should Be $true
        } finally {
            Remove-Item -Path function:CoinEx-GetTicker -ErrorAction SilentlyContinue
        }
    }
}

Describe "Register-PartialExitLadder -- caso real DOGEUSDT (2026-07-31)" {

    BeforeEach { Reset-PartialExitMocks }

    It "posicao real DOGEUSDT SHORT com partials da policy 'atual' -- ladder registrado corretamente" {
        # Dados reais do diagnostico (2026-07-31): entry=0.070985,
        # stopCurrent=0.07106351, open_interest=16577 DOGE.
        $pos = New-TestPosition -Market "DOGEUSDT" -Side "SHORT" -Entry 0.070985 -StopCurrent 0.07106351 -OpenInterest 16577.0
        $risk = [Math]::Abs($pos.stopCurrent - $pos.entry)  # ~0.0000785

        $r = Register-PartialExitLadder -Position $pos -Partials (New-TestPartials) -StopDistance $risk

        $r.success | Should Be $true
        $global:__ladder_total | Should Be 16577.0
        $global:__ladder_side | Should Be "short"
    }

    It "REGRESSAO 2026-07-31: primeiro deploy real (run 30658447856/30658795216) falhou com ladder_call_failed -- causa raiz era tp_levels como hashtable puro (@{...}), nao PSCustomObject" {
        # _MultiLadder-ResolvePrice (lib_coinex.ps1) le $Level.PSObject.Properties['type']
        # -- em hashtable puro essa colecao expoe membros do PSObject (Keys/Values/
        # Count), NAO as chaves do hashtable, entao $type ficava sempre $null e
        # sempre caia no branch "default" (throw "tipo de level desconhecido").
        # A funcao mock de teste nao chama _MultiLadder-ResolvePrice de verdade,
        # entao este teste usa a funcao REAL (nao mockada) pra garantir que os
        # levels resolvem sem excecao com os numeros reais do DOGEUSDT.
        $pos = New-TestPosition -Market "DOGEUSDT" -Side "SHORT" -Entry 0.070985 -StopCurrent 0.07106351 -OpenInterest 16577.0
        $risk = [Math]::Abs($pos.stopCurrent - $pos.entry)

        foreach ($lvl in (New-TestPartials)) {
            $tpLevel = [PSCustomObject]@{ type = "rr_multiple"; rr_multiple = [double]$lvl.at_r; qty_pct = [double]$lvl.pct * 100 }
            { _MultiLadder-ResolvePrice -Level $tpLevel -Entry $pos.entry -StopDistance $risk -IsLong:$false -IsStop:$false } | Should Not Throw
            $px = _MultiLadder-ResolvePrice -Level $tpLevel -Entry $pos.entry -StopDistance $risk -IsLong:$false -IsStop:$false
            ($px -gt 0) | Should Be $true
        }
    }
}
