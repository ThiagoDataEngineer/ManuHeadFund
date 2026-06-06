# 📊 Monitor 24h — Dashboard em Tempo Real

> **Objetivo**: Verificar saúde do sistema a cada hora  
> **Métrica Principal**: Win rate + Gates performance  
> **Ação**: Detectar anomalias ANTES de perder $$$

---

## 🎯 Checklist Horário (faça a cada hora)

### ✅ 11h BRT — MANHÃ

```powershell
# 1. Listar trades executados
Get-Content "journal/trade_audit_records.jsonl" | `
    ConvertFrom-Json | `
    Where-Object { $_.timestamp -ge (Get-Date).AddHours(-1) }

# 2. Win rate últimas 24h
$trades = @(Get-Content "journal/trade_audit_records.jsonl" | ConvertFrom-Json)
$wins = ($trades | Where-Object { $_.is_live_execution -and $_.win_loss -eq "WIN" }).Count
$total = ($trades | Where-Object { $_.is_live_execution }).Count
"Win rate (live): $($wins)/$($total) = $([Math]::Round(($wins/$total)*100, 0))%"

# 3. Verificar gate blocks
Get-Content "journal/performance_gate_audit.jsonl" | `
    ConvertFrom-Json | `
    Where-Object { $_.timestamp -ge (Get-Date).AddHours(-1) -and -not $_.passes_performance_gate } | `
    Select-Object market, reason

# 4. Última entrada (para revisar)
Get-Content "journal/trade_audit_records.jsonl" | `
    ConvertFrom-Json | `
    Sort-Object timestamp -Descending | `
    Select-Object -First 1 | `
    Format-List market, entry_price, direction, decision_reasoning, trading_mode
```

**Esperado:**
- ✅ Win rate >= 40%
- ✅ Gate blocks < 20% de decisões
- ✅ Última entrada com reasoning claro
- ⚠️ Trading mode = LIVE (se ativo)

---

### ✅ 14h BRT — MEIO DO DIA

```powershell
# Mesmos checks + análise de volatilidade

# Volatilidade média nas últimas 3h
$volLogs = @(Get-Content "journal/volatility_filter_audit.jsonl" | ConvertFrom-Json | `
    Where-Object { $_.timestamp -ge (Get-Date).AddHours(-3) })

$avgVol = ($volLogs | Measure-Object -Property volatility_5m_pct -Average).Average
$blockedByVol = ($volLogs | Where-Object { $_.action -eq "BLOCK" }).Count

"Volatilidade média: $([Math]::Round($avgVol, 2))%"
"Bloqueados por vol: $blockedByVol"

# Position sizes executados
$sizes = @(Get-Content "journal/position_sizing_audit.jsonl" | ConvertFrom-Json | `
    Where-Object { $_.timestamp -ge (Get-Date).AddHours(-3) })

$avgSize = ($sizes | Measure-Object -property final_size_pct -Average).Average
"Size médio: $([Math]::Round($avgSize, 2))% da conta"

# Confluência média
$confluence = @(Get-Content "journal/performance_gate_audit.jsonl" | ConvertFrom-Json | `
    Where-Object { $_.timestamp -ge (Get-Date).AddHours(-3) })

$avgConf = ($confluence | Measure-Object -property confluence_count -Average).Average
"Confluência média: $([Math]::Round($avgConf, 1))/5"
```

**Esperado:**
- ✅ Volatilidade <= 3% (bom) ou 3-5% (reduzido)
- ✅ Size médio 0.5-1.5% (não oversized)
- ✅ Confluência >= 3.5/5

---

### ✅ 18h BRT — FIM DO PREGÃO

```powershell
# Resumo diário

# 1. Trades do dia
$today = (Get-Date).Date
$tradesToday = @(Get-Content "journal/trade_audit_records.jsonl" | ConvertFrom-Json | `
    Where-Object { ([datetime]$_.timestamp).Date -eq $today })

"📊 RESUMO DO DIA:"
"  Total trades: $($tradesToday.Count)"
"  Live trades: $($tradesToday | Where-Object { $_.is_live_execution }).Count"
"  Paper trades: $($tradesToday | Where-Object { -not $_.is_live_execution }).Count"

# 2. PnL do dia
$pnl = ($tradesToday | Measure-Object -Property pnl_usd -Sum).Sum
"  PnL: $$([Math]::Round($pnl, 2))"

# 3. Win rate
$wins = ($tradesToday | Where-Object { $_.pnl_usd -gt 0 }).Count
$rate = if ($tradesToday.Count -gt 0) { ($wins / $tradesToday.Count) * 100 } else { 0 }
"  Win rate: $($wins)/$($tradesToday.Count) = $([Math]::Round($rate, 0))%"

# 4. Capital safety (nenhum trade > 2%?)
$oversized = @($tradesToday | Where-Object { $_.position_size_pct -gt 2.0 })
"  Oversized trades (>2%): $($oversized.Count)"

# 5. Confluência média
$avgConf = if ($tradesToday.Count -gt 0) {
    ($tradesToday | Measure-Object -Property confluence_score -Average).Average
} else { 0 }
"  Confluência média: $([Math]::Round($avgConf, 1))/100"
```

**Esperado:**
- ✅ PnL >= $0 (break even é OK)
- ✅ Win rate >= 40%
- ✅ Oversized = 0
- ✅ Confluência >= 60/100

---

## 🚨 ALERTAS — O que investigar

| Alerta | Causa | Ação |
|--------|-------|------|
| Win rate < 30% | Entradas fracas ou modelo descalibrado | Re-calibra sinais (opção C) |
| Gate blocks > 40% | Confluência muito exigente (5/5) | Reduz threshold pra 3/5 |
| Vol blocks > 30% | Mercado muito barulhento | Espera janela melhor (próxima dia) |
| Size médio > 2% | Risk management falhou | Reduz base_pct em config |
| Oversized trades = 1+ | Capital safety quebrou | IMEDIATAMENTE revisa position_sizing_audit.jsonl |
| Traders em PAPER quando deveria LIVE | Whitelist/regime mismatch | Verifica orchestrator_v6 whitelist |

---

## 📈 Métrica de Decisão (FIM DE DIA)

Após 8h de trading (11h-19h BRT), decida:

```
IF win_rate >= 50% AND pnl > 0 AND no_oversized THEN
  ✅ SISTEMA OK — continua
ELSE IF win_rate 30-50% AND pnl >= 0 THEN
  🟡 AMARELO — monitora próximas 12h, pronto pra ajuste
ELSE IF win_rate < 30% OR pnl < -50 THEN
  🔴 VERMELHO — PARE trading, revisa calibração
```

---

## 📋 Script Consolidado (rodar 1x/dia)

```powershell
# DAILY_MONITOR.ps1

$journalDir = "journal"
$today = (Get-Date).Date

# Carrega logs
$trades = @(Get-Content "$journalDir/trade_audit_records.jsonl" | ConvertFrom-Json | `
    Where-Object { ([datetime]$_.timestamp).Date -eq $today })
$gates = @(Get-Content "$journalDir/performance_gate_audit.jsonl" | ConvertFrom-Json)
$sizes = @(Get-Content "$journalDir/position_sizing_audit.jsonl" | ConvertFrom-Json)
$vols = @(Get-Content "$journalDir/volatility_filter_audit.jsonl" | ConvertFrom-Json)

# Calcula métricas
$liveCount = ($trades | Where-Object { $_.is_live_execution }).Count
$winCount = ($trades | Where-Object { $_.pnl_usd -gt 0 }).Count
$winRate = if ($liveCount -gt 0) { ($winCount / $liveCount) * 100 } else { 0 }
$pnl = ($trades | Measure-Object -Property pnl_usd -Sum).Sum
$blockRate = if ($gates.Count -gt 0) { 
    (($gates | Where-Object { -not $_.passes_performance_gate }).Count / $gates.Count) * 100 
} else { 0 }
$oversized = ($trades | Where-Object { $_.position_size_pct -gt 2.0 }).Count

# Output
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "DAILY MONITOR — $(Get-Date -Format 'yyyy-MM-dd')" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""
Write-Host "📊 PERFORMANCE:" -ForegroundColor Yellow
Write-Host "  Trades (live): $liveCount"
Write-Host "  Win rate: $winCount/$liveCount = $([Math]::Round($winRate, 0))%"
Write-Host "  PnL: $$([Math]::Round($pnl, 2))"
Write-Host ""
Write-Host "🛡️  RISK:" -ForegroundColor Yellow
Write-Host "  Gate block rate: $([Math]::Round($blockRate, 0))%"
Write-Host "  Oversized trades: $oversized"
Write-Host "  Avg size: $([Math]::Round(($sizes | Measure-Object -Property final_size_pct -Average).Average, 2))%"
Write-Host ""

# Decisão
$status = if ($winRate -ge 50 -and $pnl -gt 0 -and $oversized -eq 0) {
    "✅ GREEN — Sistema OK"
} elseif ($winRate -ge 30 -and $pnl -ge 0 -and $oversized -eq 0) {
    "🟡 YELLOW — Monitor próximas 12h"
} else {
    "🔴 RED — PAUSE trading, revisit calibration"
}

Write-Host "STATUS: $status" -ForegroundColor $(
    if ($status -match "GREEN") { "Green" }
    elseif ($status -match "YELLOW") { "Yellow" }
    else { "Red" }
)
```

---

## 📱 Telegram Alert (opcional)

Integrar com seu Telegram pra alertas:

```powershell
# Se win_rate < 30%, notifica:
if ($winRate -lt 30) {
    $msg = "🔴 ALERT: Win rate $([Math]::Round($winRate, 0))% — revisar calibração"
    # Use seu Telegram bot aqui
}
```

---

## ✅ Checklist — O que fazer

- [ ] Criar arquivo `DAILY_MONITOR.ps1` (copie script acima)
- [ ] Executar a cada hora (ou a cada 3h mínimo)
- [ ] Revisar logs se algum alerta dispara
- [ ] Manter histórico de métricas (excel ou gráfico)
- [ ] Comparar: hoje vs semana passada

---

**Próximo**: Após 24h de monitoring, você terá dados pra decidir se precisa re-calibrar sinais ou está pronto pros 10 trades (opção 3).
