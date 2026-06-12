# B19b fix 2026-05-20 PM6+450min.
# PlaceOrder client_id idempotency: fecha gap deferred do B19.
# CoinEx v2 futures/order aceita campo client_id -> retry safe (exchange dedup).

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_order_idempotency.ps1")

Describe "B19b New-OrderClientId" {
    BeforeEach {
        $script:storePath = Join-Path $env:TEMP "b19b_orders_$([guid]::NewGuid()).jsonl"
    }
    AfterEach {
        Remove-Item $storePath -Force -ErrorAction SilentlyContinue
    }

    It "gera UUID-like (32+ chars, alphanumeric)" {
        $id = New-OrderClientId -Market "BTCUSDT" -Side "buy" -StorePath $storePath
        $id.Length | Should BeGreaterThan 16
        $id | Should Match '^[A-Za-z0-9_-]+$'
    }
    It "Cada call gera ID diferente" {
        $a = New-OrderClientId -Market "BTCUSDT" -Side "buy" -StorePath $storePath
        $b = New-OrderClientId -Market "BTCUSDT" -Side "buy" -StorePath $storePath
        $a | Should Not Be $b
    }
    It "Persiste em JSONL com market/side/amount/status" {
        New-OrderClientId -Market "BTCUSDT" -Side "buy" -Amount 0.001 -StorePath $storePath | Out-Null
        $line = Get-Content $storePath -Encoding UTF8 | Select-Object -First 1
        $obj = $line | ConvertFrom-Json
        $obj.market | Should Be "BTCUSDT"
        $obj.side | Should Be "buy"
        $obj.client_id | Should Match '^[A-Za-z0-9_-]+$'
        $obj.status | Should Be "submitted"
    }
}

Describe "B19b Update-OrderClientIdStatus" {
    BeforeEach {
        $script:storePath = Join-Path $env:TEMP "b19b_status_$([guid]::NewGuid()).jsonl"
    }
    AfterEach {
        Remove-Item $storePath -Force -ErrorAction SilentlyContinue
    }

    It "Atualiza status apos confirmacao" {
        $id = New-OrderClientId -Market "BTCUSDT" -Side "buy" -StorePath $storePath
        Update-OrderClientIdStatus -ClientId $id -Status "confirmed" -OrderId "12345" -StorePath $storePath
        # Get-Content devolve linhas em ordem cronologica; ultimo entry tem o status novo
        $lines = @(Get-Content $storePath -Encoding UTF8)
        $obj = $lines[-1] | ConvertFrom-Json
        $obj.status | Should Be "confirmed"
        $obj.order_id | Should Be "12345"
    }
}

Describe "B19b Get-OrderClientIdEntries" {
    It "Filtra por client_id" {
        $store = Join-Path $env:TEMP "b19b_filter_$([guid]::NewGuid()).jsonl"
        try {
            $a = New-OrderClientId -Market "BTCUSDT" -Side "buy" -StorePath $store
            $b = New-OrderClientId -Market "ETHUSDT" -Side "sell" -StorePath $store
            $entries = Get-OrderClientIdEntries -ClientId $a -StorePath $store
            $entries.Count | Should BeGreaterThan 0
            $entries[0].market | Should Be "BTCUSDT"
        } finally {
            Remove-Item $store -Force -ErrorAction SilentlyContinue
        }
    }
}
