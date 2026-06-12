# telegram_gem_dedup_crossproc.Tests.ps1 -- TDD dedup cross-processo de alerta gem
#
# Incidente 2026-06-05: gem_loop E scan_master rodam Invoke-GemScan; ambos chamam
# Send-GemAlert -> mesmo gem alertado 2x no Telegram (Size:$0, so notificacao).
# Send-GemAlert nao tinha dedup. Fix: Test-TelegramGemDedup file-based (cross-proc).

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
function Write-Host { param() }
. (Join-Path $agentsDir "lib_telegram.ps1")

$script:store = Join-Path $env:TEMP ("gem_dedup_test_" + [Guid]::NewGuid().ToString('N') + ".json")

Describe "Test-TelegramGemDedup - cross-processo" {

    AfterEach { if (Test-Path $script:store) { Remove-Item $script:store -Force -ErrorAction SilentlyContinue } }

    It "primeira chamada NAO e' dup; segunda identica E' dup (dentro do TTL)" {
        $k = "PEPE2USDT:85:DISCOVERY"
        (Test-TelegramGemDedup -Key $k -StorePath $script:store -TtlSeconds 300) | Should Be $false
        (Test-TelegramGemDedup -Key $k -StorePath $script:store -TtlSeconds 300) | Should Be $true
    }

    It "chaves diferentes sao independentes" {
        (Test-TelegramGemDedup -Key "AUSDT:80:DISCOVERY" -StorePath $script:store -TtlSeconds 300) | Should Be $false
        (Test-TelegramGemDedup -Key "BUSDT:80:DISCOVERY" -StorePath $script:store -TtlSeconds 300) | Should Be $false
    }

    It "persiste entre 'processos' (re-le o arquivo, nao memoria)" {
        $k = "FIROUSDT:75:DISCOVERY"
        (Test-TelegramGemDedup -Key $k -StorePath $script:store -TtlSeconds 300) | Should Be $false
        # Simula outro processo: store carregado do disco de novo internamente
        (Test-TelegramGemDedup -Key $k -StorePath $script:store -TtlSeconds 300) | Should Be $true
    }

    It "TTL=0 desativa dedup (sempre false)" {
        $k = "XUSDT:90:MOMENTUM"
        (Test-TelegramGemDedup -Key $k -StorePath $script:store -TtlSeconds 0) | Should Be $false
        (Test-TelegramGemDedup -Key $k -StorePath $script:store -TtlSeconds 0) | Should Be $false
    }

    It "expira apos TTL (entry antiga nao bloqueia)" {
        $k = "EXPUSDT:70:DISCOVERY"
        # grava manualmente um timestamp velho (600s atras)
        $old = [int]((([datetime]::UtcNow).AddSeconds(-600)) - [datetime]'1970-01-01').TotalSeconds
        (@{ $k = $old } | ConvertTo-Json -Compress) | Out-File -FilePath $script:store -Encoding utf8 -Force
        (Test-TelegramGemDedup -Key $k -StorePath $script:store -TtlSeconds 300) | Should Be $false
    }
}
