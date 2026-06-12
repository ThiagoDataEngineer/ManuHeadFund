# lib_idempotency.ps1 -- B14 fix 2026-05-20 PM6+320min.
#
# Idempotency key pra callback handlers do Telegram. Sistema LIVE Mode 2 desde 18/05
# com $2762.93 capital exposto -- worst case duplicate callback = 2x sizing 1% = 2x $27.60
# de exposicao inesperada por trade. daily_loss CB poderia ser violado silenciosamente.
#
# Surface real: $global:TG_UPDATE_OFFSET compartilhado entre tg_listener.ps1 e
# Wait-TgCallbackApproval = race condition latente. Idempotency check garante apenas
# o primeiro processamento de cada callback_query.id executa.
#
# Schema: journal/telegram_callbacks_processed.json
# {
#   "callbacks": [{"id": "...", "ts": "ISO"}],
#   "max_entries": 1000
# }
#
# PS 5.1, UTF-8 BOM.

$script:IDEM_MAX_ENTRIES = 1000

function _Idem-Load {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return @() }
    try {
        $raw = Get-Content $Path -Raw -Encoding UTF8 -ErrorAction Stop
        if (-not $raw -or $raw.Trim() -eq "") { return @() }
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $data) { return @() }
        # Suporta schema {callbacks:[...]} ou array direto pra back-compat
        if ($data.callbacks) { return @($data.callbacks) }
        return @($data)
    } catch {
        # Corrompido: fail-open (cria novo storage). Risco: 1 callback duplicate
        # passa quando arquivo corrompido — aceitavel vs lock-out total do sistema.
        return @()
    }
}

function _Idem-Save {
    param([string] $Path, [array] $Entries)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    # Rolling: mantem so os ultimos MAX entries
    if ($Entries.Count -gt $script:IDEM_MAX_ENTRIES) {
        $Entries = $Entries[-$script:IDEM_MAX_ENTRIES..-1]
    }
    $payload = [ordered]@{
        callbacks   = $Entries
        max_entries = $script:IDEM_MAX_ENTRIES
        updated_at  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    ($payload | ConvertTo-Json -Depth 4 -Compress) | Out-File -FilePath $Path -Encoding UTF8 -Force
}

function Test-CallbackIdempotent {
    <#
    .SYNOPSIS
        Verifica e marca callback_id como processado. Retorna $true se NOVO (pode
        executar trade); $false se DUPLICATE (skip silencioso, callback ja foi visto).
    .DESCRIPTION
        Race-safe via file write: primeiro Test- com mesmo ID retorna true e persiste;
        chamadas subsequentes retornam false. Rolling window 1000 entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $CallbackId
    )
    $entries = @(_Idem-Load -Path $Path)

    # Check duplicate
    foreach ($e in $entries) {
        if ($e.id -eq $CallbackId) {
            return $false  # duplicate, skip silencioso
        }
    }

    # Novo callback: persiste
    $entries += [PSCustomObject]@{
        id = $CallbackId
        ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    _Idem-Save -Path $Path -Entries $entries
    return $true
}
