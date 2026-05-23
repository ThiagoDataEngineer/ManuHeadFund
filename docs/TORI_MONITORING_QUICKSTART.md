# TORI MONITORING - QUICKSTART

## Status
✅ **Análise completa** das jornadas (GEM + COMUM) - DONE  
✅ **Script de monitoring** criado - DONE  
🔄 **Próximo passo**: Testar e ativar

---

## Execução Rápida

### Teste Manual (1 ciclo)
```powershell
cd c:\Users\thiag\Coinex_AI_USER_API
.\scripts\tori_monitoring_cron.ps1 -Once -Verbose
```

### Execução Contínua (foreground)
```powershell
.\scripts\tori_monitoring_cron.ps1 -IntervalMinutes 60 -Verbose
```

### Execução Background (recomendado)
```powershell
# Iniciar
$job = Start-Job -FilePath ".\scripts\tori_monitoring_cron.ps1" -ArgumentList 60

# Ver output
Receive-Job -Job $job -Keep

# Parar
Stop-Job -Job $job
Remove-Job -Job $job
```

---

## Outputs

### Telegram Alerts
Quando `setup_ripening = true`:
```
🎯 TORI SIGNAL: BTCUSDT
━━━━━━━━━━━━━━━━━━━━
Side: LONG
Proximity: 2.3%
Action Line: 94250.50
RSI: 45.2
Vol Drying: true
Reason: 3_touches_slope_15deg_rsi_ok_vol_drying
━━━━━━━━━━━━━━━━━━━━
⏰ 2026-05-23 15:30:00
```

### CSV Log
`journal/tori_signals.csv`:
```csv
timestamp,market,side,proximity_pct,action_line,rsi,vol_drying,setup_ripening
2026-05-23 15:30:00,BTCUSDT,LONG,2.3,94250.50,45.2,true,true
2026-05-23 15:30:30,ETHUSDT,LONG,8.5,3250.00,52.1,false,false
```

---

## Próximos Passos (Plano 7 dias)

### ✅ Dia 1 (Hoje)
- [x] Análise completa jornadas
- [x] Criar monitoring script
- [ ] Testar monitoring (1h)

### 🔥 Dia 2
- [ ] Pre-Mentor Skip (tier=C+observe) - 2h
- [ ] Scanner Vol Component - 3h

### 🔥 Dia 3
- [ ] Tori Gate Fallback (2 touches) - 4h

### ⚡ Dia 4
- [ ] Mesa Lidar Simplify - 2h
- [ ] ChainAgent Full Data - 2h

### ⚡ Dia 5-7
- [ ] Whale Detection Fase 1 - 2 dias
- [ ] Exit Ladder Trailing Stop - 1 dia

---

## ROI Esperado (30 dias)

| Métrica | Antes | Depois | Delta |
|---------|-------|--------|-------|
| Tori signals detectados | 0% (manual) | 100% | +100% |
| Entry timing | Manual check | -2h | -2h |
| Profit capture | Sem trailing | +15% | +15% |
| Risk mitigation | Nenhum | Invaluable | ∞ |

---

## Documentos Relacionados

- **Análise Completa**: `docs/JOURNEY_DEEP_ANALYSIS_COMPLETE_2026_05_23.md`
- **Tori Validado**: `docs/TORI_FINAL_VALIDATED_2026_05_23.md`
- **Config**: `agents/config.ps1` (`$TORI_ENABLED = $true`)

---

**EXECUTE AGORA**: `.\scripts\tori_monitoring_cron.ps1 -Once -Verbose`
