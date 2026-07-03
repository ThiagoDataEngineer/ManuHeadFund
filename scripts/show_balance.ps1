#!/usr/bin/env pwsh
# show_balance.ps1 — Mostra saldo SPOT + FUTURES em tempo real
# Usage: .\show_balance.ps1

$balancePath = "journal/balance_snapshot.json"

if (-not (Test-Path $balancePath)) {
    Write-Host "❌ Balance snapshot não encontrado. Aguarde primeiro ciclo de scan_master (5-10min)" -ForegroundColor Red
    exit 1
}

try {
    $balance = Get-Content $balancePath | ConvertFrom-Json

    Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
    Write-Host "SALDO REAL COINEX — $(([datetime]$balance.timestamp).ToLocalTime().ToString('HH:mm:ss'))" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan

    Write-Host "`n[SPOT WALLET]" -ForegroundColor Yellow
    Write-Host "  USDT disponível: $($balance.spot.usdt) R$" -ForegroundColor Green
    Write-Host "  Pares ativos: $($balance.spot.total_pairs)" -ForegroundColor Gray

    Write-Host "`n[FUTURES WALLET]" -ForegroundColor Yellow
    Write-Host "  USDT disponível: $($balance.futures.usdt) R$" -ForegroundColor Green
    Write-Host "  Pares ativos: $($balance.futures.total_pairs)" -ForegroundColor Gray

    Write-Host "`n[ALOCAÇÃO SHORT v2.5]" -ForegroundColor Yellow
    if ($balance.primary_carteira -eq "SPOT") {
        $sizing = $balance.spot.usdt * 0.01
        Write-Host "  Usando: SPOT ($(1.0)% = R$ $sizing)" -ForegroundColor Cyan
    }
    elseif ($balance.primary_carteira -eq "FUTURES") {
        $sizing = $balance.futures.usdt * 0.01
        Write-Host "  Usando: FUTURES (1.0% = R$ $sizing)" -ForegroundColor Cyan
    }
    else {
        Write-Host "  Carteira: DESCONHECIDA (ambas vazias?)" -ForegroundColor Red
    }

    Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
}
catch {
    Write-Host "❌ Erro ao ler balance: $_" -ForegroundColor Red
    exit 1
}
