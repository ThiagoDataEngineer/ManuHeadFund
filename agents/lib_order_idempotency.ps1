# lib_order_idempotency.ps1 -- B19b fix 2026-05-20 PM6+450min.
#
# Fecha gap deferred do B19: PlaceOrder com client_id idempotency key.
# CoinEx v2 futures/order aceita campo client_id (ate ~32 chars). Mesmo client_id
# em request duplicada -> exchange retorna ordem existente, nao cria nova.
#
# Persiste em journal/order_client_ids.jsonl pra audit + recovery.
#
# Schema JSONL:
#   {"ts":"...","client_id":"abc123","market":"BTCUSDT","side":"buy","amount":0.001,"status":"submitted"}
#   {"ts":"...","client_id":"abc123","status":"confirmed","order_id":"12345"}
#
# PS 5.1, UTF-8 BOM.

function _Order-GenerateClientId {
    # UUID v4 sem hifens (32 chars) com prefix 'c' (CoinEx limit ~32, prefix evita leading-digit issues)
    return "c" + ([guid]::NewGuid().ToString("N").Substring(0, 30))
}

function New-OrderClientId {
    <#
    .SYNOPSIS
        Gera client_id unico + persiste no store JSONL. Caller usa o ID retornado
        no body da PlaceOrder. Retry safe: mesmo client_id reproduzido -> exchange dedup.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Side,
        [double] $Amount = 0,
        [string] $StorePath = (Join-Path $global:JOURNAL_DIR "order_client_ids.jsonl")
    )
    $clientId = _Order-GenerateClientId

    $dir = Split-Path $StorePath -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $entry = [ordered]@{
        ts        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        client_id = $clientId
        market    = $Market
        side      = $Side
        amount    = $Amount
        status    = "submitted"
    }
    $line = ($entry | ConvertTo-Json -Compress -Depth 3)
    Add-Content -Path $StorePath -Value $line -Encoding UTF8
    return $clientId
}

function Update-OrderClientIdStatus {
    <#
    .SYNOPSIS
        Append atualizacao de status (confirmed/failed) — append-only (nao overwrite linha original).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ClientId,
        [Parameter(Mandatory)] [string] $Status,   # submitted | confirmed | failed | duplicated_by_exchange
        [string] $OrderId = "",
        [string] $StorePath = (Join-Path $global:JOURNAL_DIR "order_client_ids.jsonl")
    )
    $entry = [ordered]@{
        ts        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        client_id = $ClientId
        status    = $Status
        order_id  = $OrderId
    }
    $line = ($entry | ConvertTo-Json -Compress -Depth 3)
    Add-Content -Path $StorePath -Value $line -Encoding UTF8
}

function Get-OrderClientIdEntries {
    <#
    .SYNOPSIS
        Retorna todas entries pra um client_id (submit + status updates).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ClientId,
        [string] $StorePath = (Join-Path $global:JOURNAL_DIR "order_client_ids.jsonl")
    )
    if (-not (Test-Path $StorePath)) { return ,@() }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($l in @(Get-Content $StorePath -Encoding UTF8)) {
        $trim = $l.Trim()
        if (-not $trim) { continue }
        try {
            $obj = $trim | ConvertFrom-Json -ErrorAction Stop
            if ($obj.client_id -eq $ClientId) { [void]$out.Add($obj) }
        } catch {}
    }
    return ,$out.ToArray()
}
