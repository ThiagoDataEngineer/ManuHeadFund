# cleanup_trade_outcomes_duplicates_2026_07_29.ps1 -- one-shot, workflow_dispatch.
# Achado real (auditoria 2026-07-29): ConvertTo-SupabaseOutcome gerava um id com
# GUID aleatorio, mesmo trade fisico (mesmo market+side+entry+exit+ts) virava
# linha NOVA a cada reconciliacao/reprocesso -- confirmado via IDs reais
# (639198913001440000|ADAUSDT|LONG|<guid-diferente-a-cada-vez>). Fix real ja
# aplicado em agents/lib_feedback_loop.ps1 (id agora deterministico, hash SHA256
# sem componente aleatorio) -- previne duplicacao NOVA. Este script remove os
# duplicados JA EXISTENTES no Supabase (dedup por conteudo: market+side+
# pnl_percent+entry+exit identicos = mesmo trade fisico, mantem so 1).
#
# So leitura por default (-DryRun). Passe -DryRun:$false pra de fato deletar.

param(
    [Parameter(Mandatory=$false)][string]$SupabaseUrl = $env:SUPABASE_URL,
    [Parameter(Mandatory=$false)][string]$ServiceKey = $env:SUPABASE_SERVICE_KEY,
    [switch]$DryRun = $true
)

if (-not $SupabaseUrl) { throw "SUPABASE_URL environment variable not set" }
if (-not $ServiceKey) { throw "SUPABASE_SERVICE_KEY environment variable not set" }

$restHeaders = @{
    "Authorization"   = "Bearer $ServiceKey"
    "apikey"          = $ServiceKey
    "Accept-Profile"  = "manuheadfund"
    "Content-Profile" = "manuheadfund"
    "Content-Type"    = "application/json"
}

Write-Host "=== CLEANUP trade_outcomes duplicates (source=app_import) ===" -ForegroundColor Cyan
Write-Host "Mode: $(if ($DryRun) { 'DRY RUN (so leitura, nada sera deletado)' } else { 'LIVE (vai deletar duplicados)' })" -ForegroundColor $(if ($DryRun) { "Yellow" } else { "Red" })

try {
    $url = "$SupabaseUrl/rest/v1/trade_outcomes?source=eq.app_import&select=id,market,side,entry_price,exit_price,pnl_percent,close_reason"
    $rows = Invoke-RestMethod -Uri $url -Headers $restHeaders -Method Get -ErrorAction Stop

    Write-Host "Total app_import: $($rows.Count)"

    # Agrupa por "assinatura" do trade fisico (market+side+entry+exit+pnl) --
    # registros com a MESMA assinatura sao o mesmo trade real duplicado.
    $groups = $rows | Group-Object { "{0}|{1}|{2}|{3}|{4}" -f $_.market, $_.side, $_.entry_price, $_.exit_price, $_.pnl_percent }

    $toDelete = @()
    foreach ($g in $groups) {
        if ($g.Count -gt 1) {
            # Mantem o primeiro id (ordem estavel), marca os demais pra delete
            $sorted = $g.Group | Sort-Object id
            $keep = $sorted[0]
            $dupes = $sorted | Select-Object -Skip 1
            Write-Host "  Grupo '$($g.Name)': $($g.Count) registros -- mantendo id=$($keep.id), removendo $($dupes.Count)" -ForegroundColor Yellow
            $toDelete += $dupes
        }
    }

    Write-Host "`nTotal de duplicados a remover: $($toDelete.Count)" -ForegroundColor $(if ($toDelete.Count -gt 0) { "Red" } else { "Green" })

    if ($toDelete.Count -eq 0) {
        Write-Host "Nada a fazer -- sem duplicados detectados." -ForegroundColor Green
        exit 0
    }

    if ($DryRun) {
        Write-Host "`nDRY RUN -- nenhum registro foi deletado. Rode com -DryRun:`$false pra aplicar." -ForegroundColor Yellow
        exit 0
    }

    $deleted = 0
    $errors = 0
    foreach ($d in $toDelete) {
        try {
            $delUrl = "$SupabaseUrl/rest/v1/trade_outcomes?id=eq.$([uri]::EscapeDataString($d.id))"
            Invoke-RestMethod -Uri $delUrl -Headers $restHeaders -Method Delete -ErrorAction Stop | Out-Null
            $deleted++
        } catch {
            Write-Host "  ERRO ao deletar id=$($d.id): $_" -ForegroundColor Red
            $errors++
        }
    }
    Write-Host "`nDeletados: $deleted | Erros: $errors" -ForegroundColor $(if ($errors -eq 0) { "Green" } else { "Red" })
} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
    throw
}

Write-Host "`n=== FIM ===" -ForegroundColor Cyan
