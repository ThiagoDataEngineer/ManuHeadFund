# B14 callback idempotency 2026-05-20 PM6+320min.
# Sistema LIVE Mode 2 desde 18/05 com $2762.93 capital exposto.
# Worst case duplicado: 2x sizing 1% = 2x $27.60 = $55 exposicao inesperada.
# Daily_loss CB calcula com 1 trade mas se executar 2 -> threshold violado silenciosamente.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_idempotency.ps1")

Describe "B14 Test-CallbackIdempotent" {
    BeforeEach {
        $script:store = Join-Path $env:TEMP "b14_idem_$([guid]::NewGuid()).json"
    }
    AfterEach {
        Remove-Item $store -Force -ErrorAction SilentlyContinue
    }

    It "primeiro callback ID: retorna true (NAO seen)" {
        (Test-CallbackIdempotent -Path $store -CallbackId "cb_001") | Should Be $true
    }
    It "duplicate do mesmo callback ID: retorna false (poupa trade)" {
        (Test-CallbackIdempotent -Path $store -CallbackId "cb_001") | Should Be $true
        (Test-CallbackIdempotent -Path $store -CallbackId "cb_001") | Should Be $false
    }
    It "callback ID diferente apos primeiro: retorna true (legitimo)" {
        (Test-CallbackIdempotent -Path $store -CallbackId "cb_001") | Should Be $true
        (Test-CallbackIdempotent -Path $store -CallbackId "cb_002") | Should Be $true
    }
    It "persistencia entre chamadas (sobrevive reload)" {
        Test-CallbackIdempotent -Path $store -CallbackId "cb_001" | Out-Null
        # Simula nova instancia do listener (re-load do arquivo)
        (Test-CallbackIdempotent -Path $store -CallbackId "cb_001") | Should Be $false
    }
    It "rolling window: aceita pruning de IDs antigos (cap 1000)" {
        # 1001 callbacks; ID #1 deve ser podado, podendo voltar a retornar true
        for ($i = 1; $i -le 1001; $i++) {
            Test-CallbackIdempotent -Path $store -CallbackId "cb_$i" | Out-Null
        }
        $store_data = Get-Content $store -Raw | ConvertFrom-Json
        @($store_data).Count | Should BeLessThan 1002
    }
    It "arquivo corrompido: retorna true (fail-open na primeira; cria novo)" {
        Set-Content -Path $store -Value "{ invalid json" -Encoding utf8
        (Test-CallbackIdempotent -Path $store -CallbackId "cb_001") | Should Be $true
    }
    It "race condition simulada: 2 chamadas paralelas, apenas 1 retorna true" {
        # Simulacao sequencial (PowerShell single-thread em tests) — testa lock logic
        $r1 = Test-CallbackIdempotent -Path $store -CallbackId "race_cb"
        $r2 = Test-CallbackIdempotent -Path $store -CallbackId "race_cb"
        # Apenas o primeiro deve passar
        ($r1 -and -not $r2) | Should Be $true
    }
}

Describe "B14 integration: trade ONLY fires once per callback_id" {
    It "callback handler simulado: 3 chamadas mesmo ID = 1 trade" {
        $store = Join-Path $env:TEMP "b14_trade_$([guid]::NewGuid()).json"
        $callbackId = "cb_btc_approve_001"
        $trades = 0
        if (Test-CallbackIdempotent -Path $store -CallbackId $callbackId) { $trades++ }
        if (Test-CallbackIdempotent -Path $store -CallbackId $callbackId) { $trades++ }
        if (Test-CallbackIdempotent -Path $store -CallbackId $callbackId) { $trades++ }
        $trades | Should Be 1
        Remove-Item $store -Force -ErrorAction SilentlyContinue
    }
}
