# ✅ Checklist — Sistema Auto-Diagnóstico Está Rodando?

## 🟢 Status Rápido (Roda isto quando quiser "avaliar")

```bash
# Copie e rode tudo junto
Write-Host "🔍 CHECKLIST AUTO-DIAGNOSTICO" -ForegroundColor Green

# 1. Guardian rodando?
$guardian = Get-Process powershell | Where-Object { $_.CommandLine -match 'self_heal_guardian' }
if ($guardian) {
  Write-Host "✅ Guardian VIVO (PID=$($guardian.Id))" -ForegroundColor Green
} else {
  Write-Host "❌ Guardian MORTO — reinicie: .\scripts\start_fleet.ps1" -ForegroundColor Red
}

# 2. Frota completa?
$procs = @('scan_master', 'sentinel_movers', 'collect_1h_klines', 'self_heal_guardian')
$found = 0
foreach ($p in $procs) {
  $proc = Get-Process powershell -ErrorAction SilentlyContinue | 
    Where-Object { $_.CommandLine -match $p }
  if ($proc) { $found++ }
}
Write-Host "📊 Frota: $found/4 daemons vivos" -ForegroundColor $(if ($found -eq 4) { 'Green' } else { 'Red' })

# 3. Logs frescos?
$logs = @(
  "logs/master_$(Get-Date -Format 'yyyyMMdd').log",
  "journal/self_heal_guardian.log",
  "journal/sentinel.log"
)
foreach ($log in $logs) {
  if (Test-Path $log) {
    $age = ((Get-Date) - (Get-Item $log).LastWriteTime).TotalMinutes
    $fresh = if ($age -lt 30) { '✅' } else { '⚠️' }
    Write-Host "$fresh $(Split-Path $log -Leaf): ${age}min atrás" -ForegroundColor $(if ($age -lt 30) { 'Green' } else { 'Yellow' })
  }
}

# 4. Incidentes registrados?
$inc = "journal/self_heal_incidents.jsonl"
if (Test-Path $inc) {
  $lines = (Get-Content $inc).Count
  Write-Host "📝 Incidentes: $lines registrados" -ForegroundColor Gray
}

# 5. Alertas Telegram?
$cfg = "config/alerts_config.json"
if (Test-Path $cfg) {
  $config = Get-Content $cfg | ConvertFrom-Json
  $tgOk = if ($config.alerting.telegram.botToken -and $config.alerting.telegram.botToken -ne "YOUR_BOT_TOKEN_HERE") {
    "✅ CONFIGURADO"
  } else {
    "⚠️  PENDENTE (edite config/alerts_config.json)"
  }
  Write-Host "📱 Telegram: $tgOk" -ForegroundColor $(if ($tgOk -match "CONFIGURADO") { 'Green' } else { 'Yellow' })
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Se tudo verde: App está 100% auto-diagnosticando 24/7" -ForegroundColor Green
Write-Host "Se algo amarelo/vermelho: Veja a seção abaixo" -ForegroundColor Yellow
```

---

## 🟡 Problema: Guardian Morto

**Solução rápida**:
```powershell
.\scripts\start_fleet.ps1
# Aguarde 30seg
Get-Process powershell | Where-Object { $_.CommandLine -match 'guardian' }
```

---

## 🟡 Problema: Logs Velhos (>30min)

**Significa**: Daemon parou de escrever (zumbi)

**Solução**:
```powershell
# Guardian vai detectar em 10min e reiniciar
# Ou reinicie manualmente
.\scripts\start_fleet.ps1
```

---

## 🟡 Problema: Telegram Não Configurado

**Solução** (5 minutos):

1. Abra Telegram → busque `@BotFather`
2. Mande `/newbot` → copia o token
3. Abra Telegram → busque `@userinfobot`
4. Mande qualquer mensagem → copia o Chat ID
5. Edite `config/alerts_config.json`:

```json
{
  "alerting": {
    "telegram": {
      "enabled": true,
      "botToken": "COLE_AQUI_O_TOKEN",
      "chatId": "COLE_AQUI_O_CHAT_ID"
    }
  }
}
```

6. Salve e você receberá alertas!

---

## 🟢 Leitura: JSONs de Diagnóstico

Se algo deu errado, leia:

```bash
# Ver últimas 5 falhas
tail -5 journal/self_heal_incidents.jsonl | jq '.'

# Ver todos ajustes da evolution engine
cat journal/daily_calibration.jsonl | jq '.[] | {ts, action, param}'

# Ver últimos 10 trades
tail -10 journal/trade_outcomes.jsonl | jq '.'
```

---

## ✅ Checklist Diário (5 min de manhã)

- [ ] Telegram botou alerta? (se não, sistema tá 👍)
- [ ] Se botou: Leia o JSON correspondente
- [ ] Se recorrente 3x: Analyze em docs/ e aprove fix

---

## 🚀 Resumo

| Status | Significa |
|--------|-----------|
| ✅ Tudo verde | Sistema operacional, auto-diagnosticando 24/7 |
| 🟡 Algo amarelo | Configure (Telegram) ou aguarde restart (10min) |
| 🔴 Algo vermelho | Reinicie: `.\scripts\start_fleet.ps1` |

---

**Próxima verificação automática**: +10 minutos (guardian)  
**Próxima auditoria E2E**: Amanhã ~06h00  
**Você não precisa fazer nada**, sistema tá cuidando de si mesmo.
