# 🛡️ PROTEÇÃO ANTI-DUPLICAÇÃO

**Problema:** Se rodar local E GitHub Actions ao mesmo tempo, pode dar conflito (execuções duplicadas, ordens duplicadas, etc.)

**Solução:** Sistema inteligente de locks que detecta onde está rodando e evita duplicação.

---

## 🎯 COMO FUNCIONA

### 1. Detecção Automática
O sistema detecta automaticamente onde está rodando:

```powershell
Get-ExecutionMode
# Retorna: "local" ou "github-actions"
```

### 2. Sistema de Locks
Cada job cria um arquivo de lock antes de executar:

```
locks/
├── risk-manager.lock
├── dashboard-generator.lock
└── health-check.lock
```

### 3. Verificação de Duplicação
Antes de executar, verifica:
- ✅ Job já está rodando? → Pula
- ✅ Lock expirado (>5min)? → Remove e executa
- ✅ Livre? → Executa

---

## 📊 CENÁRIOS

### Cenário 1: Apenas Local
```
Máquina Local: ✅ Executa
GitHub Actions: ❌ Desabilitado
Resultado: ✅ Sem conflito
```

### Cenário 2: Apenas GitHub Actions
```
Máquina Local: ❌ Desligada
GitHub Actions: ✅ Executa
Resultado: ✅ Sem conflito
```

### Cenário 3: Ambos Ligados (PROTEGIDO)
```
Máquina Local: ✅ Executa primeiro (14:00:00)
GitHub Actions: ⏳ Tenta executar (14:00:05)
  → Detecta lock ativo
  → Pula execução
  → Aguarda próximo ciclo
Resultado: ✅ Sem duplicação!
```

### Cenário 4: Lock Expirado
```
Máquina Local: ✅ Executa (14:00:00)
  → Trava/Crash (não remove lock)
GitHub Actions: ⏳ Tenta executar (14:06:00)
  → Detecta lock com 6min
  → Lock expirado (>5min)
  → Remove lock
  → Executa normalmente
Resultado: ✅ Sistema se recupera!
```

---

## 🔧 CONFIGURAÇÃO

### Modo Preferido (Opcional)
Você pode forçar um job a rodar apenas em um modo:

```powershell
# Apenas local
Invoke-SafeJob -JobName "risk-manager" -PreferredMode "local" -ScriptBlock { ... }

# Apenas GitHub Actions
Invoke-SafeJob -JobName "dashboard" -PreferredMode "github-actions" -ScriptBlock { ... }

# Ambos (padrão)
Invoke-SafeJob -JobName "health-check" -PreferredMode "both" -ScriptBlock { ... }
```

### Exemplo de Uso Híbrido
```powershell
# Risk Manager: Apenas local (mais rápido, 5min)
Invoke-SafeJob -JobName "risk-manager" -PreferredMode "local" -ScriptBlock {
    # Código crítico que precisa rodar rápido
}

# Dashboard: Apenas GitHub Actions (15min, não crítico)
Invoke-SafeJob -JobName "dashboard" -PreferredMode "github-actions" -ScriptBlock {
    # Código não crítico
}
```

---

## 📝 LOGS

### Execução Normal
```
[local] Iniciando job 'risk-manager'...
[local] Job 'risk-manager' concluído com sucesso
```

### Duplicação Detectada
```
[github-actions] Job 'risk-manager' já está rodando, pulando...
```

### Modo Errado
```
[local] Job 'dashboard' configurado para rodar apenas em 'github-actions', pulando...
```

---

## 🎯 RECOMENDAÇÕES

### Opção A: Apenas Local (Simples)
```
✅ Máquina ligada
✅ Execução a cada 5min
✅ Sem configuração extra
❌ Custo de energia
❌ Sem backup
```

### Opção B: Apenas GitHub Actions (Recomendado)
```
✅ Máquina pode desligar
✅ Grátis (2.000 min/mês)
✅ Backup automático
✅ Dashboard online
❌ Execução a cada 15-30min
```

### Opção C: Híbrido (Avançado)
```
Local:
  ✅ Risk Manager (5min) - Crítico
  
GitHub Actions:
  ✅ Dashboard (15min) - Não crítico
  ✅ Health Check (30min) - Monitoramento
  ✅ Daily Summary (1x/dia) - Relatório

Configuração:
  - Risk Manager: PreferredMode = "local"
  - Dashboard: PreferredMode = "github-actions"
  - Health Check: PreferredMode = "github-actions"
```

---

## 🔍 VERIFICAR STATUS

### Ver Locks Ativos
```powershell
Get-ChildItem locks\*.lock | ForEach-Object {
    $lock = Get-Content $_.FullName | ConvertFrom-Json
    Write-Host "$($lock.job): $($lock.mode) - $($lock.timestamp)"
}
```

### Limpar Locks Manualmente
```powershell
Remove-Item locks\*.lock -Force
```

### Testar Proteção
```powershell
# Terminal 1
.\scripts\position_risk_cron.ps1

# Terminal 2 (ao mesmo tempo)
.\scripts\position_risk_cron.ps1
# Deve mostrar: "Job 'risk-manager' já está rodando, pulando..."
```

---

## ⚠️ IMPORTANTE

### Locks Expiram em 5 Minutos
- ✅ Protege contra travamentos
- ✅ Sistema se recupera automaticamente
- ⚠️ Se job demorar >5min, pode duplicar

### Ajustar Timeout (se necessário)
```powershell
Test-JobRunning -JobName "risk-manager" -MaxAge 600  # 10 minutos
```

### Locks São Locais
- ✅ Local e GitHub Actions têm locks separados
- ✅ Não interferem entre si
- ✅ Proteção funciona em cada ambiente

---

## 🎉 RESULTADO

Com a proteção ativa:

✅ **Pode rodar local E GitHub Actions** sem conflito  
✅ **Sistema detecta duplicação** automaticamente  
✅ **Locks expiram** (recuperação automática)  
✅ **Logs claros** de o que está acontecendo  
✅ **Flexibilidade** para escolher modo preferido  

**Sem risco de ordens duplicadas ou conflitos!** 🛡️

---

## 📚 ARQUIVOS

- `scripts/check_execution_mode.ps1` - Sistema de proteção
- `scripts/position_risk_cron.ps1` - Risk Manager (protegido)
- `scripts/generate_dashboard_elite.ps1` - Dashboard (protegido)
- `locks/*.lock` - Arquivos de lock (criados automaticamente)

---

**ManuHeadFund** - Sistema Protegido Contra Duplicação 🛡️
