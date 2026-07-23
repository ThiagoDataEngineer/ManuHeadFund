# lib_entry_lock.ps1 -- Lock distribuido de curta duracao pra evitar 2 dos 3
# motores de execucao real (gem_scanner_executor_live, gem_loop, faro_v3_entry)
# tentarem abrir a MESMA posicao ao mesmo tempo.
#
# 2026-07-23 (auditoria "100% integro"): cada motor ja checa
# CoinEx-GetPendingPositions (exchange real) antes de abrir, mas ha uma
# janela real entre esse check e o PlaceOrder -- jobs GH Actions distintos
# rodam em paralelo, sem lock compartilhado. Fecha essa janela via um
# INSERT puro (sem upsert) na tabela manuheadfund.entry_locks: como market
# e PRIMARY KEY, um 2o INSERT pro mesmo market enquanto o lock existir
# falha com 23505 (unique violation) -- exclusao mutua real garantida pelo
# Postgres, nao uma corrida "check-then-write" no lado do cliente.
#
# TTL curto (default 30s): cobre o tempo real entre check e ordem, mas
# expira sozinho se o job travar/crashar -- nunca fica "preso" bloqueando
# o market indefinidamente. PS 5.1, UTF-8 BOM.

function Lock-EntryMarket {
    <#
    .SYNOPSIS
        Tenta adquirir lock exclusivo pro market antes de abrir posicao.
    .PARAMETER Market
        Symbol (ex: BTCUSDT)
    .PARAMETER LockedBy
        Identificador do motor/job que esta tentando (ex: "faro_v3", "gem_loop")
    .PARAMETER TtlSeconds
        Duracao do lock antes de expirar sozinho. Default 30s.
    .OUTPUTS
        $true se adquiriu o lock (pode prosseguir); $false se outro motor ja
        segura o lock (nao expirado) -- caller deve abortar a entrada.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string] $Market,
        [Parameter(Mandatory=$true)] [string] $LockedBy,
        [int] $TtlSeconds = 30
    )

    if (-not (Get-Command Get-SupabaseRequestHeaders -ErrorAction SilentlyContinue)) {
        # Sem state_store disponivel (ex: teste local sem Supabase) -- fail-open,
        # nao trava a entrada por falta de infraestrutura de lock.
        Write-Warning "[entry_lock] Get-SupabaseRequestHeaders indisponivel -- lock pulado (fail-open)"
        return $true
    }

    $now = (Get-Date).ToUniversalTime()
    $nowStr = $now.ToString("o")
    $expiresStr = $now.AddSeconds($TtlSeconds).ToString("o")

    try {
        $cfg = Get-SupabaseRequestHeaders -Method "POST"
        $schema = if (Get-Command Get-StateStoreSchema -ErrorAction SilentlyContinue) { Get-StateStoreSchema } else { "manuheadfund" }
        $url = "$($cfg.url)/rest/v1/entry_locks"
        $body = @{ market = $Market; locked_by = $LockedBy; locked_at = $nowStr; expires_at = $expiresStr } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri $url -Method POST -Headers $cfg.headers -Body "[$body]" -TimeoutSec 10 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        $msg = "$($_.Exception.Message)"
        if ($msg -match "23505|duplicate key|already exists") {
            # Lock ja existe -- checa se esta expirado (job anterior travou/crashou)
            try {
                $existing = @(Get-StateRecords -Table "entry_locks" -Filter @{ market = $Market })
                if ($existing.Count -gt 0) {
                    $exp = [datetimeoffset]::Parse($existing[0].expires_at).UtcDateTime
                    if ($exp -lt $now) {
                        # Lock expirado -- remove e tenta de novo (1x, evita loop infinito)
                        try { Remove-StateRecord -Table "entry_locks" -PrimaryKey "market" -Value $Market } catch {}
                        return (Lock-EntryMarket -Market $Market -LockedBy $LockedBy -TtlSeconds $TtlSeconds)
                    }
                }
            } catch {}
            Write-Host "  [ENTRY LOCK] ${Market}: ja bloqueado por outro motor -- abortando entrada (evita duplicata)" -ForegroundColor Yellow
            return $false
        }
        # Erro diferente (rede, tabela ausente, etc) -- fail-open, nao bloqueia
        # entrada por falha de infraestrutura (mesmo padrao dos outros gates
        # do projeto: erro de sistema != veto de negocio).
        Write-Warning "[entry_lock] Falha ao adquirir lock (fail-open): $msg"
        return $true
    }
}

function Unlock-EntryMarket {
    <#
    .SYNOPSIS
        Libera o lock do market apos a entrada (sucesso ou falha). Sempre
        chamar num finally/catch -- lock tambem expira sozinho via TTL se
        isso nao acontecer.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string] $Market
    )
    if (-not (Get-Command Remove-StateRecord -ErrorAction SilentlyContinue)) { return }
    try {
        Remove-StateRecord -Table "entry_locks" -PrimaryKey "market" -Value $Market
    } catch {}
}
