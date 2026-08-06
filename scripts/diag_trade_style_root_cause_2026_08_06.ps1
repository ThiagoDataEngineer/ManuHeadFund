# diag_trade_style_root_cause_2026_08_06.ps1 -- ONE-SHOT, so leitura.
#
# Achado de ontem: ARBUSDT/NEARUSDT/OPUSDT ficam em HOLD permanente no
# motor unificado (Resolve-TrailingDecision) por "trade_style_desconhecido"
# -- so aceita "SCALP"|"SWING" (lib_trailing_unified.ps1 ATR_PERIOD_BY_STYLE).
# Mas lib_trailing_orphan_detection.ps1 (unico caller com mode=ORPHAN_AUTO)
# JA passa -Origin @{asset_class="FUTURES"; trade_style="SWING"} explicito
# -- entao a hipotese de "origin=UNKNOWN" nao bate com o codigo real. Este
# script puxa o valor CRU e real de origin.trade_style gravado no Supabase
# pra essas 3 posicoes, pra achar a causa raiz de verdade antes de corrigir
# qualquer coisa (owner pediu calma + mapear TODOS os tipos de causa antes
# do fix, vai ser TDD + live trading).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: valor CRU real de origin.trade_style (causa raiz do HOLD travado) ===" -ForegroundColor Cyan

$cfg = Get-SupabaseRequestHeaders -Method "GET"
foreach ($mkt in @("ARBUSDT", "NEARUSDT", "OPUSDT", "SOONUSDT", "PIPPINUSDT")) {
    try {
        $uri = "$($cfg.url)/rest/v1/trailing_state?select=*&market=eq.$mkt&active=eq.true"
        $rows = @(Invoke-RestMethod -Uri $uri -Method GET -Headers $cfg.headers -TimeoutSec 30)
        Write-Host "--- $mkt ---" -ForegroundColor Yellow
        if ($rows.Count -eq 0) {
            Write-Host "  Nenhum registro ativo encontrado." -ForegroundColor Red
            continue
        }
        $r = $rows[0]
        Write-Host "  origin (raw): $($r.origin | ConvertTo-Json -Compress -Depth 5)"
        if ($null -eq $r.origin) {
            Write-Host "  [ATENCAO] origin e NULL (nem o fallback UNKNOWN foi gravado)" -ForegroundColor Red
        } elseif ($r.origin -is [string]) {
            Write-Host "  [ATENCAO] origin veio como STRING, nao objeto -- Resolve-TrailingDecision espera .asset_class/.trade_style direto" -ForegroundColor Red
            try {
                $parsed = $r.origin | ConvertFrom-Json
                Write-Host "  parsed.trade_style = $($parsed.trade_style)"
            } catch {
                Write-Host "  FALHOU ao fazer ConvertFrom-Json do origin: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "  origin.trade_style = '$($r.origin.trade_style)'"
            Write-Host "  origin.asset_class = '$($r.origin.asset_class)'"
        }
        Write-Host "  mode=$($r.mode) source=$($r.source) phase=$($r.phase)"
        Write-Host ""
    } catch {
        Write-Host "  ERRO em ${mkt}: $_" -ForegroundColor Red
    }
}

Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
