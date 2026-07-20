# lib_spot_stop_guard.Tests.ps1 -- Pester 3.x
# TDD Fix #1 (2026-06-23): SPOT stop fail-closed.
# Hoje position_watcher SO alerta no SL do SPOT, nunca vende. OPN foi a -69% com daemon morto.
# Resolve-SpotStopActions decide (PURO, sem API) quais stop-orders COLOCAR na corretora
# (fail-closed: sobrevive daemon caido) sem RECRIAR o bug das 178 duplicatas (2026-06-20).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_spot_stop_guard.ps1")

Describe "Resolve-SpotStopActions - fail-closed (coloca o que falta)" {
    It "Posicao SEM stop na corretora -> PLACE" {
        $pos = @([pscustomobject]@{ market="OPNUSDT"; qty=75.6; stop_price=0.1215 })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops @()
        $place = @($r | Where-Object { $_.action -eq "PLACE" })
        $place.Count | Should Be 1
        $place[0].market | Should Be "OPNUSDT"
        $place[0].trigger_price | Should Be 0.1215
        $place[0].amount | Should Be 75.6
    }

    It "Posicao COM stop correto na corretora -> OK (idempotente, NAO duplica)" {
        $pos = @([pscustomobject]@{ market="UBUSDT"; qty=355; stop_price=0.0905 })
        $ex  = @([pscustomobject]@{ market="UBUSDT"; side="sell"; trigger_price=0.0905; amount=355; order_id="A1" })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops $ex
        @($r | Where-Object { $_.action -eq "PLACE" }).Count | Should Be 0
        @($r | Where-Object { $_.action -eq "OK" }).Count | Should Be 1
    }

    It "Stop dentro da tolerancia (0.5%) -> OK, nao recoloca" {
        $pos = @([pscustomobject]@{ market="XRPUSDT"; qty=22; stop_price=1.013 })
        $ex  = @([pscustomobject]@{ market="XRPUSDT"; side="sell"; trigger_price=1.0135; amount=22; order_id="A1" })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops $ex
        @($r | Where-Object { $_.action -eq "OK" }).Count | Should Be 1
        @($r | Where-Object { $_.action -eq "PLACE" }).Count | Should Be 0
    }
}

Describe "Resolve-SpotStopActions - auto-upgrade limit agressivo (self-heal)" {
    It "Stop casa no trigger MAS limit colado no trigger -> UPDATE (re-poe c/ limit agressivo)" {
        $pos = @([pscustomobject]@{ market="FIROUSDT"; qty=23; stop_price=0.3872 })
        $ex  = @([pscustomobject]@{ market="FIROUSDT"; side="sell"; trigger_price=0.3872; limit_price=0.3872; amount=23; order_id="OLD" })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops $ex
        @($r | Where-Object { $_.action -eq "UPDATE" }).Count | Should Be 1
    }
    It "Stop com limit JA agressivo (abaixo do trigger) -> OK (nao churn)" {
        $pos = @([pscustomobject]@{ market="FIROUSDT"; qty=23; stop_price=0.3872 })
        $ex  = @([pscustomobject]@{ market="FIROUSDT"; side="sell"; trigger_price=0.3872; limit_price=0.3755; amount=23; order_id="OK1" })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops $ex
        @($r | Where-Object { $_.action -eq "OK" }).Count | Should Be 1
        @($r | Where-Object { $_.action -eq "UPDATE" }).Count | Should Be 0
    }
    It "Sem campo limit_price -> OK (backward compat, nao churn)" {
        $pos = @([pscustomobject]@{ market="FIROUSDT"; qty=23; stop_price=0.3872 })
        $ex  = @([pscustomobject]@{ market="FIROUSDT"; side="sell"; trigger_price=0.3872; amount=23; order_id="A1" })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops $ex
        @($r | Where-Object { $_.action -eq "OK" }).Count | Should Be 1
    }
}

Describe "Resolve-SpotStopActions - dedup (anti bug 178 stops)" {
    It "DOIS stops iguais -> mantem 1 (OK) e CANCEL o resto" {
        $pos = @([pscustomobject]@{ market="BASEDUSDT"; qty=124; stop_price=0.0366 })
        $ex  = @(
            [pscustomobject]@{ market="BASEDUSDT"; side="sell"; trigger_price=0.0366; amount=124; order_id="A1" }
            [pscustomobject]@{ market="BASEDUSDT"; side="sell"; trigger_price=0.0366; amount=124; order_id="A2" }
        )
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops $ex
        @($r | Where-Object { $_.action -eq "OK" }).Count | Should Be 1
        $cancel = @($r | Where-Object { $_.action -eq "CANCEL" })
        $cancel.Count | Should Be 1
        $cancel[0].order_id | Should Be "A2"
    }

    It "Stop DESATUALIZADO mais baixo (trail subiu) -> UPDATE p/ o nivel novo" {
        $pos = @([pscustomobject]@{ market="AINUSDT"; qty=100; stop_price=0.0451 })
        $ex  = @([pscustomobject]@{ market="AINUSDT"; side="sell"; trigger_price=0.030; amount=100; order_id="OLD" })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops $ex
        $upd = @($r | Where-Object { $_.action -eq "UPDATE" })
        $upd.Count | Should Be 1
        $upd[0].order_id | Should Be "OLD"
        $upd[0].trigger_price | Should Be 0.0451
    }
}

Describe "Resolve-SpotStopActions - UPDATE quando trailing subiu (nao so pular)" {
    It "Stop desejado MAIOR que o da corretora (trail subiu) -> UPDATE (cancela velho + poe novo)" {
        # COAI correu: trailing moveu stopCurrent de 0.1546 -> 0.339 (breakeven+). Exchange ainda no velho.
        $pos = @([pscustomobject]@{ market="COAIUSDT"; qty=58; stop_price=0.339 })
        $ex  = @([pscustomobject]@{ market="COAIUSDT"; side="sell"; trigger_price=0.1546; amount=58; order_id="OLD" })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops $ex
        $upd = @($r | Where-Object { $_.action -eq "UPDATE" })
        $upd.Count | Should Be 1
        $upd[0].trigger_price | Should Be 0.339
        $upd[0].order_id | Should Be "OLD"   # qual cancelar
        @($r | Where-Object { $_.action -eq "OK" }).Count | Should Be 0
    }

    It "Stop da corretora JA MAIOR/igual que o desejado -> OK (nao afrouxa, ratchet)" {
        # nunca baixar o stop: se a corretora ja esta mais protegida, mantem.
        $pos = @([pscustomobject]@{ market="BASEDUSDT"; qty=124; stop_price=0.090 })
        $ex  = @([pscustomobject]@{ market="BASEDUSDT"; side="sell"; trigger_price=0.098; amount=124; order_id="HI" })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops $ex
        @($r | Where-Object { $_.action -eq "OK" }).Count | Should Be 1
        @($r | Where-Object { $_.action -eq "UPDATE" }).Count | Should Be 0
    }

    It "UPDATE tambem limpa duplicatas (mantem so o novo)" {
        $pos = @([pscustomobject]@{ market="XUSDT"; qty=10; stop_price=2.0 })
        $ex  = @(
            [pscustomobject]@{ market="XUSDT"; side="sell"; trigger_price=1.0; amount=10; order_id="OLD1" }
            [pscustomobject]@{ market="XUSDT"; side="sell"; trigger_price=1.1; amount=10; order_id="OLD2" }
        )
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops $ex
        @($r | Where-Object { $_.action -eq "UPDATE" }).Count | Should Be 1
        @($r | Where-Object { $_.action -eq "CANCEL" }).Count | Should Be 1
    }
}

Describe "Resolve-DesiredStop - sempre um stop VALIDO abaixo do preco (nunca morto)" {
    It "Posicao rastreada (CSV stop valido abaixo do preco) -> usa o CSV stop" {
        Resolve-DesiredStop -Last 100 -CsvStop 90 -JournalStop 0 | Should Be 90
    }
    It "Trailing subiu acima do CSV -> usa o maior (ratchet)" {
        Resolve-DesiredStop -Last 100 -CsvStop 90 -JournalStop 95 | Should Be 95
    }
    It "Posicao NAO rastreada (sem CSV/journal) -> default 12% abaixo do preco" {
        Resolve-DesiredStop -Last 100 -CsvStop 0 -JournalStop 0 -DefaultStopPct 0.12 | Should Be 88
    }
    It "Stop planejado ACIMA do preco (posicao furada) -> re-ancora abaixo do preco (nao morto)" {
        # PAXG: CSV stop 4064 mas preco caiu p/ 3988 -> stop acima do mercado NUNCA dispara.
        # Re-ancora em last*(1-buffer) p/ virar stop FUNCIONAL.
        $r = Resolve-DesiredStop -Last 3988 -CsvStop 4064 -JournalStop 0 -MinBufferPct 0.02
        ($r -lt 3988) | Should Be $true
        $r | Should Be ([math]::Round(3988*0.98,8))
    }
    It "Last invalido (<=0) -> 0 (caller ignora)" {
        Resolve-DesiredStop -Last 0 -CsvStop 90 -JournalStop 0 | Should Be 0
    }
}

Describe "Get-SpotStopLimitPrice - limit agressivo abaixo do gatilho (preenche no gap)" {
    It "Limit fica X% abaixo do trigger (preenche mesmo se preco atravessa)" {
        # stop-MARKET spot ja deu problema no passado -> usa stop-LIMIT com price abaixo
        Get-SpotStopLimitPrice -TriggerPrice 0.10 -SlippagePct 0.03 | Should Be 0.097
    }
    It "Default slippage 3%" {
        Get-SpotStopLimitPrice -TriggerPrice 100 | Should Be 97
    }
    It "Trigger invalido -> 0 (caller trata)" {
        Get-SpotStopLimitPrice -TriggerPrice 0 | Should Be 0
    }
    It "Nunca retorna negativo" {
        (Get-SpotStopLimitPrice -TriggerPrice 0.00000001 -SlippagePct 0.03) -ge 0 | Should Be $true
    }
}

Describe "Test-SpotStopFallback - venda a mercado quando o stop-limit nao executa" {
    It "Preco ATRAVESSOU o stop (alem do buffer) + ainda tem posicao -> FIRE" {
        # CoinEx spot stop-limit nao preencheu (preco gapou); daemon executa mercado.
        $r = Test-SpotStopFallback -CurrentPrice 0.090 -StopPrice 0.10 -Qty 100 -BufferPct 0.01
        $r.fire | Should Be $true
    }
    It "Preco no stop (dentro do buffer) -> NAO dispara (deixa o limit da corretora trabalhar)" {
        $r = Test-SpotStopFallback -CurrentPrice 0.0995 -StopPrice 0.10 -Qty 100 -BufferPct 0.01
        $r.fire | Should Be $false
    }
    It "Preco ACIMA do stop -> NAO dispara" {
        $r = Test-SpotStopFallback -CurrentPrice 0.12 -StopPrice 0.10 -Qty 100 -BufferPct 0.01
        $r.fire | Should Be $false
    }
    It "Qty 0 (nada a vender) -> NAO dispara" {
        $r = Test-SpotStopFallback -CurrentPrice 0.05 -StopPrice 0.10 -Qty 0 -BufferPct 0.01
        $r.fire | Should Be $false
    }
    It "Stop 0/invalido -> NAO dispara (nunca vende sem stop definido)" {
        $r = Test-SpotStopFallback -CurrentPrice 0.05 -StopPrice 0 -Qty 100 -BufferPct 0.01
        $r.fire | Should Be $false
    }
    It "Preco <= 0 (ticker furado) -> NAO dispara (fail-safe, nao vende por dado ruim)" {
        $r = Test-SpotStopFallback -CurrentPrice 0 -StopPrice 0.10 -Qty 100 -BufferPct 0.01
        $r.fire | Should Be $false
    }
}

Describe "Test-SpotStopPlaceable - filtra poeira/sub-nano/simbolo (anti-spam)" {
    It "Posicao normal -> placeable" {
        $r = Test-SpotStopPlaceable -Market "AINUSDT" -Qty 100 -Price 0.07 -MinNotionalUsd 5
        $r.placeable | Should Be $true
    }
    It "Poeira (notional < min) -> NAO placeable (MET 0.0147*0.16 ~ $0)" {
        $r = Test-SpotStopPlaceable -Market "METUSDT" -Qty 0.0147 -Price 0.16 -MinNotionalUsd 5
        $r.placeable | Should Be $false
        $r.reason | Should Be "poeira"
    }
    It "Preco sub-nano -> NAO placeable (PEPE2 ~9e-10, stop-limit rejeita)" {
        $r = Test-SpotStopPlaceable -Market "PEPE2USDT" -Qty 1e9 -Price 9.66e-10 -MinNotionalUsd 5
        $r.placeable | Should Be $false
        $r.reason | Should Be "preco_sub_nano"
    }
    It "Simbolo sem USDT -> NAO placeable (TNSR)" {
        $r = Test-SpotStopPlaceable -Market "TNSR" -Qty 1499 -Price 0.039 -MinNotionalUsd 5
        $r.placeable | Should Be $false
        $r.reason | Should Be "simbolo_invalido"
    }
    It "Preco <= 0 -> NAO placeable" {
        $r = Test-SpotStopPlaceable -Market "XUSDT" -Qty 100 -Price 0 -MinNotionalUsd 5
        $r.placeable | Should Be $false
    }
}

Describe "Resolve-SpotStopActions - guardas (regra de ouro #1)" {
    It "stop_price <= 0 -> SKIP_INVALID (nunca coloca stop furado)" {
        $pos = @([pscustomobject]@{ market="BADUSDT"; qty=10; stop_price=0 })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops @()
        @($r | Where-Object { $_.action -eq "SKIP_INVALID" }).Count | Should Be 1
        @($r | Where-Object { $_.action -eq "PLACE" }).Count | Should Be 0
    }

    It "qty <= 0 -> SKIP_INVALID" {
        $pos = @([pscustomobject]@{ market="BADUSDT"; qty=0; stop_price=1.0 })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops @()
        @($r | Where-Object { $_.action -eq "SKIP_INVALID" }).Count | Should Be 1
    }

    It "Multiplas posicoes -> resolve cada uma independente" {
        $pos = @(
            [pscustomobject]@{ market="OPNUSDT"; qty=75; stop_price=0.12 }
            [pscustomobject]@{ market="UBUSDT";  qty=355; stop_price=0.0905 }
        )
        $ex  = @([pscustomobject]@{ market="UBUSDT"; side="sell"; trigger_price=0.0905; amount=355; order_id="A1" })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops $ex
        @($r | Where-Object { $_.market -eq "OPNUSDT" -and $_.action -eq "PLACE" }).Count | Should Be 1
        @($r | Where-Object { $_.market -eq "UBUSDT" -and $_.action -eq "OK" }).Count | Should Be 1
    }

    It "Nao confunde TP (sell acima) com SL: so considera stops passados como SL" {
        # contrato: ExistingStops recebe APENAS sell-stops SL (trigger abaixo do preco).
        # wire filtra TP fora. Aqui garantimos que um sell SL legitimo casa.
        $pos = @([pscustomobject]@{ market="COAIUSDT"; qty=58; stop_price=0.1546 })
        $ex  = @([pscustomobject]@{ market="COAIUSDT"; side="sell"; trigger_price=0.1546; amount=58; order_id="SL1" })
        $r = Resolve-SpotStopActions -Positions $pos -ExistingStops $ex
        @($r | Where-Object { $_.action -eq "OK" }).Count | Should Be 1
    }
}
