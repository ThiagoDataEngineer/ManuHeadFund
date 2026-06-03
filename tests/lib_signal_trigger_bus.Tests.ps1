# lib_signal_trigger_bus.Tests.ps1 -- TDD do trigger-bus event-driven.
#
# Sinais-lider (whale/faro/cold_wallet/funding/vol_climax/news) enfileiram um
# trigger quando cruzam o limiar de conviccao; o scan_master consome e dispara
# analise imediata e direcionada (fast path) em vez de esperar o ciclo de 30min.
#
# Contrato testado:
#   - Add-SignalTrigger: gate de conviccao + dedupe/cooldown por market+signal
#   - Get-PendingSignalTriggers: pendentes nao-expirados, ordenados por conviccao
#   - Set-SignalTriggerProcessed: lifecycle pending -> processed
#   - Get-SignalConvictionThreshold: limiar por sinal + default
#
# Pester 3.x. UTF-8 BOM. Sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_signal_trigger_bus.ps1")

$mockDir = Join-Path $env:TEMP ("trigbus_" + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $mockDir -Force | Out-Null
$mockPath = Join-Path $mockDir "signal_triggers.jsonl"

function Reset-Bus {
    if (Test-Path $mockPath) { Remove-Item $mockPath -Force }
    Set-TriggerBusConfig -Path $mockPath -CooldownMin 20 -ExpireMin 60
}


Describe "Get-SignalConvictionThreshold" {
    It "retorna limiar especifico por sinal" {
        (Get-SignalConvictionThreshold -Signal "whale") | Should Be 70
    }
    It "retorna default para sinal desconhecido" {
        (Get-SignalConvictionThreshold -Signal "xyz_inexistente") | Should Be 60
    }
}


Describe "Add-SignalTrigger -- gate de conviccao" {
    BeforeEach { Reset-Bus }

    It "enfileira quando conviccao >= limiar" {
        $r = Add-SignalTrigger -Market "WIFUSDT" -Signal "whale" -Conviction 80 -Direction "long"
        $r.enqueued | Should Be $true
        $r.reason   | Should Be "enqueued"
        (Test-Path $mockPath) | Should Be $true
    }

    It "bloqueia quando conviccao < limiar (nada escrito)" {
        $r = Add-SignalTrigger -Market "WIFUSDT" -Signal "whale" -Conviction 50
        $r.enqueued | Should Be $false
        $r.reason   | Should Be "below_conviction"
        (Test-Path $mockPath) | Should Be $false
    }
}


Describe "Add-SignalTrigger -- dedupe/cooldown" {
    BeforeEach { Reset-Bus }

    It "bloqueia 2o trigger do mesmo market+signal dentro do cooldown" {
        (Add-SignalTrigger -Market "PEPEUSDT" -Signal "whale" -Conviction 75).enqueued | Should Be $true
        $r2 = Add-SignalTrigger -Market "PEPEUSDT" -Signal "whale" -Conviction 90
        $r2.enqueued | Should Be $false
        $r2.reason   | Should Be "cooldown"
    }

    It "permite market diferente com mesmo signal" {
        (Add-SignalTrigger -Market "PEPEUSDT" -Signal "whale" -Conviction 75).enqueued | Should Be $true
        (Add-SignalTrigger -Market "WIFUSDT"  -Signal "whale" -Conviction 75).enqueued | Should Be $true
    }

    It "permite mesmo market+signal apos cooldown expirar" {
        # injeta evento antigo (alem do cooldown) direto no arquivo
        $old = [ordered]@{
            id=[Guid]::NewGuid().ToString().Substring(0,8); event="created"
            ts=(Get-Date).AddMinutes(-120).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            market="BONKUSDT"; signal="whale"; conviction=80; direction="long"
            cluster=""; status="pending"
            expires_at=(Get-Date).AddMinutes(-60).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        ($old | ConvertTo-Json -Compress) | Add-Content -Path $mockPath -Encoding UTF8
        $r = Add-SignalTrigger -Market "BONKUSDT" -Signal "whale" -Conviction 80
        $r.enqueued | Should Be $true
    }

    It "dedupe respeita ClusterKey (mesmo cluster bloqueia)" {
        (Add-SignalTrigger -Market "WIFUSDT" -Signal "whale" -Conviction 75 -ClusterKey "tx_abc").enqueued | Should Be $true
        (Add-SignalTrigger -Market "WIFUSDT" -Signal "whale" -Conviction 75 -ClusterKey "tx_abc").enqueued | Should Be $false
    }
}


Describe "Get-PendingSignalTriggers" {
    BeforeEach { Reset-Bus }

    It "retorna pendentes ordenados por conviccao desc" {
        Add-SignalTrigger -Market "AUSDT" -Signal "whale" -Conviction 72 | Out-Null
        Add-SignalTrigger -Market "BUSDT" -Signal "faro"  -Conviction 95 | Out-Null
        Add-SignalTrigger -Market "CUSDT" -Signal "vol_climax" -Conviction 80 | Out-Null
        $p = @(Get-PendingSignalTriggers)
        $p.Count | Should Be 3
        $p[0].market | Should Be "BUSDT"
        $p[0].conviction | Should Be 95
    }

    It "exclui triggers expirados" {
        $exp = [ordered]@{
            id="expired01"; event="created"
            ts=(Get-Date).AddMinutes(-120).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            market="OLDUSDT"; signal="whale"; conviction=99; direction="long"
            cluster=""; status="pending"
            expires_at=(Get-Date).AddMinutes(-30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        ($exp | ConvertTo-Json -Compress) | Add-Content -Path $mockPath -Encoding UTF8
        @(Get-PendingSignalTriggers).Count | Should Be 0
    }

    It "ignora linha malformada (fail-safe)" {
        Add-SignalTrigger -Market "AUSDT" -Signal "whale" -Conviction 75 | Out-Null
        "{lixo nao json" | Add-Content -Path $mockPath -Encoding UTF8
        @(Get-PendingSignalTriggers).Count | Should Be 1
    }
}


Describe "Get-NextTriggerScan -- consumer" {
    BeforeEach { Reset-Bus }

    It "retorna null quando nao ha pendentes" {
        Get-NextTriggerScan | Should BeNullOrEmpty
    }

    It "retorna o de maior conviccao e o marca processado" {
        Add-SignalTrigger -Market "AUSDT" -Signal "whale" -Conviction 72 | Out-Null
        Add-SignalTrigger -Market "BUSDT" -Signal "faro"  -Conviction 95 | Out-Null
        $n = Get-NextTriggerScan
        $n.market     | Should Be "BUSDT"
        $n.conviction | Should Be 95
        # marcado processado -> nao volta
        $n2 = Get-NextTriggerScan
        $n2.market | Should Be "AUSDT"
        # esvaziou
        Get-NextTriggerScan | Should BeNullOrEmpty
    }
}


Describe "Set-SignalTriggerProcessed" {
    BeforeEach { Reset-Bus }

    It "remove o trigger dos pendentes apos processar" {
        Add-SignalTrigger -Market "ZUSDT" -Signal "whale" -Conviction 80 | Out-Null
        $id = (Get-PendingSignalTriggers)[0].id
        Set-SignalTriggerProcessed -Id $id -Result "scan_dispatched" | Out-Null
        @(Get-PendingSignalTriggers).Count | Should Be 0
    }
}
