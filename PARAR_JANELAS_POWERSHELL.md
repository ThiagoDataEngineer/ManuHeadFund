# 🔇 PARAR JANELAS DO POWERSHELL

## ⚠️ PROBLEMA

PowerShell continua abrindo janelas para várias tasks agendadas.

---

## ✅ SOLUÇÃO (1 Comando)

### Clique direito → **Executar como Administrador**:

```
OCULTAR_TODAS_TASKS.ps1
```

**IMPORTANTE**: Clique em **"Sim"** na janela de UAC que vai aparecer!

---

## 📋 O que vai acontecer:

O script vai reconfigurar **TODAS** as 19 tasks CoinEx para rodar **OCULTAS**:

1. CoinExDaemonRestart
2. CoinExDailyDigest
3. CoinExHourlyHeartbeat
4. CoinExKellyGraduation
5. CoinExLogRotation
6. CoinExParallelGraduation
7. CoinExPromotionCron
8. CoinExShortScanner
9. CoinExStalenessAudit
10. CoinExToriProximity
11. CoinExVolClimax
12. CoinExWeeklyCostReport
13. CoinExWeeklyDataRefresh
14. CoinExWhaleWatcher
15. CoinExWssForwardResolve
16. CoinEx_Dashboard_Elite
17. CoinEx_PositionRisk
18. CoinEx_ToriMonitoring
19. CoinEx_Update_Dashboard_HTML

---

## 🎯 Depois de executar:

✅ **TODAS as tasks rodam OCULTAS**
✅ **PowerShell NÃO aparece mais**
✅ **Tudo continua funcionando em background**

---

## 🔧 Como Executar:

### Opção 1: Clique Direito
1. Clique direito em `OCULTAR_TODAS_TASKS.ps1`
2. Escolha **"Executar como Administrador"**
3. Clique em **"Sim"** na janela de UAC
4. Aguarde o script terminar
5. Pressione Enter para fechar

### Opção 2: PowerShell Admin
1. Abra PowerShell como Administrador
2. Execute:
```powershell
cd "C:\Users\thiag\Coinex_AI_USER_API"
.\OCULTAR_TODAS_TASKS.ps1
```

---

## ✅ Verificar se Funcionou:

Depois de executar, aguarde 5-10 minutos.

Se PowerShell **NÃO abrir mais**, funcionou! ✅

---

## 📊 Dashboard HTML

Enquanto isso, use o Dashboard HTML:

1. Clique no atalho **"CoinEx Dashboard"** na área de trabalho
2. Dashboard abre no navegador
3. Atualiza automaticamente a cada 5 minutos

---

## 🚨 Se Ainda Aparecer Janelas:

Execute o script novamente:
```
OCULTAR_TODAS_TASKS.ps1
```

(Como Administrador)

---

## 📝 Logs (Se Precisar):

```powershell
# Ver logs do trailing stop
Get-Content logs\trailing_stop_monitor.log -Tail 50

# Ver todas as tasks
Get-ScheduledTask | Where-Object { $_.TaskName -like "*CoinEx*" }
```

---

**EXECUTE AGORA: Clique direito em `OCULTAR_TODAS_TASKS.ps1` → Executar como Administrador** 🚀
