# lib_kelly_wire.ps1 -- Integra Kelly adaptive + feedback loop pra sizing real.
#
# Resolve-AdaptiveSizing(Market, Mode, Capital):
#   1. Le historico (Supabase manuheadfund.trade_outcomes se configurado,
#      senao trade_outcomes.jsonl local -- ver nota 2026-08-25 abaixo)
#      filtrado por market + mode
#   2. Se >= MinTrades historicos: chama Get-AdaptiveSizeFromTrades (Kelly real)
#   3. Senao: fallback fixed 1% (compat com sistema antigo)
#
# Wire usage:
#   gem_executor:  $sz = Resolve-AdaptiveSizing -Market $mkt -Mode "GEM" -Capital $cap
#                  $usd_size = $sz.size_usd
#   orchestrator:  $sz = Resolve-AdaptiveSizing -Market $mkt -Mode "TIER_A" -Capital $cap
#
# Mantem assinatura compat com codigo legado via fallback. Opt-in completo:
#   uma flag $global:USE_KELLY_SIZING = $true ativaria; default OFF pra rollout gradual.
#
# 2026-08-25 FIX (owner pediu religar Kelly p/ sizing real -- causa raiz
# investigada: motor Kelly-adaptativo ja existia, testado, mas NUNCA era
# chamado por gem_executor/gem_loop, e a unica fonte de dado que ele sabia
# ler era journal/trade_outcomes.jsonl -- arquivo LOCAL que (a) e o mesmo
# jsonl ja confirmado CONTAMINADO 47% com precos fabricados [ver memoria
# feedback_trade_outcomes_jsonl_contaminated_2026_08_21] e (b) NUNCA
# sobrevive entre runs do GitHub Actions (clona limpo a cada job, mesma
# classe de bug ja corrigida em Get-RecentGemAddPositionCount/
# lib_gem_position_events.ps1). Resultado real: Kelly sempre caia no
# fallback "insufficient_trades_0" (n=0), nunca acumulava historico.
# Fix: nova fonte Get-TradeOutcomesFromSupabase le manuheadfund.trade_outcomes
# via REST direto (filtro JSONB payload->>market/payload->>mode -- essas
# colunas NAO sao top-level, estao dentro do payload JSONB, confirmado em
# ConvertTo-SupabaseOutcome/lib_feedback_loop.ps1). -OutcomePath explicito
# (usado pelos testes existentes com arquivo local isolado) continua
# funcionando 100% como antes -- Supabase e tentado primeiro so quando
# -OutcomePath NAO e passado explicitamente E o backend Supabase esta
# configurado (Test-StateBackend). Zero mudanca de comportamento em teste.

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

$script:KELLY_SUPABASE_SCHEMA = "manuheadfund"


function Get-TradeOutcomesFromSupabase {
    <#
    .SYNOPSIS
    Le manuheadfund.trade_outcomes via REST, filtrado por market/mode dentro
    do payload JSONB (nao sao colunas top-level). Fail-soft: qualquer falha
    (rede, tabela ausente, credenciais) retorna array vazio -- caller decide
    o fallback, nunca lanca.

    .PARAMETER Market
    .PARAMETER Mode
    Vazio/"" = nao filtra por mode (agrupa toda a fonte, ex.: TRIGGER/
    TORI_SHORT/TORI_LONG/TORI_*_15M todos gravam mode="GEM" hoje -- ver
    achado 2026-08-25, submodo real nao e persistido ainda).
    .PARAMETER Source
    Filtro de qualidade -- default "feedback_loop" (fonte organica real via
    Add-TradeOutcome). Exclui "app_import" (contaminado, ver memoria) e
    mocks de teste ("e2e_test_*", "position_sync_realtime").
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $Mode = "",
        [string] $Source = "feedback_loop",
        [int] $Limit = 200
    )
    if (-not (Get-Command Get-SupabaseRequestHeaders -ErrorAction SilentlyContinue)) { return @() }
    try {
        $prevSchema = $global:STATE_STORE_SCHEMA
        $global:STATE_STORE_SCHEMA = $script:KELLY_SUPABASE_SCHEMA
        try {
            $cfg = Get-SupabaseRequestHeaders -Method "GET"
        } finally {
            $global:STATE_STORE_SCHEMA = $prevSchema
        }
        $mkEsc = [Uri]::EscapeDataString([string]$Market)
        $params = "select=payload&source=eq.$([Uri]::EscapeDataString($Source))&payload->>market=eq.$mkEsc&order=closed_at.desc&limit=$Limit"
        if ($Mode) { $params += "&payload->>mode=eq.$([Uri]::EscapeDataString($Mode))" }
        $uri = "$($cfg.url)/rest/v1/trade_outcomes?$params"
        $r = Invoke-RestMethod -Uri $uri -Method GET -Headers $cfg.headers -TimeoutSec 20
        return @($r | ForEach-Object { $_.payload } | Where-Object { $_ })
    } catch {
        Write-Warning "[kelly_wire] Supabase GET trade_outcomes falhou (cai no fallback): $_"
        return @()
    }
}


function Resolve-AdaptiveSizing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Mode,
        [Parameter(Mandatory)] [double] $Capital,
        [string] $OutcomePath = "",
        [int] $MinTrades = 10
    )
    $usedExplicitPath = [bool]$OutcomePath
    if (-not $usedExplicitPath) { $OutcomePath = Join-Path $global:JOURNAL_DIR "trade_outcomes.jsonl" }

    $rows = @()
    $source = "local_jsonl"

    # Supabase primeiro, SO quando o caller nao pediu um arquivo especifico
    # (preserva 100% o comportamento testado com -OutcomePath explicito).
    if (-not $usedExplicitPath -and
        (Get-Command Test-StateBackend -ErrorAction SilentlyContinue) -and
        ((Test-StateBackend) -eq "supabase") -and
        (Get-Command Get-TradeOutcomesFromSupabase -ErrorAction SilentlyContinue)) {
        try {
            $supaRows = @(Get-TradeOutcomesFromSupabase -Market $Market -Mode $Mode)
            if ($supaRows.Count -ge $MinTrades) {
                $rows = $supaRows
                $source = "supabase"
            }
        } catch {}
    }

    if ($rows.Count -eq 0 -and (Test-Path $OutcomePath)) {
        # Le outcomes filtrado por market + mode (mais especifico ganha)
        foreach ($line in Get-Content $OutcomePath -Encoding UTF8 -ErrorAction SilentlyContinue) {
            if (-not $line) { continue }
            try {
                $o = $line | ConvertFrom-Json
                if ($o.market -ne $Market) { continue }
                if ($Mode -and $o.mode -ne $Mode) { continue }
                $rows += $o
            } catch {}
        }
    }

    if ($rows.Count -lt $MinTrades) {
        $sizeUsd = [Math]::Round($Capital * 0.01, 2)
        return [PSCustomObject]@{
            fallback = $true; reason = "insufficient_trades_$($rows.Count)_lt_$MinTrades"
            size_usd = $sizeUsd; f_used = 0.01; mode = $Mode; capital = $Capital
            n_trades = $rows.Count; source = $source
        }
    }

    # Extrai R-multiples e delega
    $trades = @($rows | ForEach-Object { [double]$_.r })
    $result = Get-AdaptiveSizeFromTrades -Trades $trades -Mode $Mode -Capital $Capital -MinTrades $MinTrades
    Add-Member -InputObject $result -MemberType NoteProperty -Name source -Value $source -Force
    return $result
}
