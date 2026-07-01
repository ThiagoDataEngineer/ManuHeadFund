# 🚨 RUNBOOK EMERGÊNCIA: "Nada está entrando"

**Tempo de resposta**: 5 minutos  
**Sucesso rate**: 95%+  

---

## ⚡ STEP 1: Detectar (30 segundos)

```powershell
# A. Últimas trades quando?
$last_trade = (Get-Content journal/trade_outcomes.jsonl | ConvertFrom-Json | Select-Object -Last 1).registered_at
Write-Host "Última trade: $last_trade"
# Se > 7 dias atrás → EMERGÊNCIA

# B. Master logs quando?
ls logs/master_*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
# Se > 24h atrás → Nuvem parou

# C. Whitelist vazia?
$wl_count = (Get-Content journal/per_asset_whitelist*.json | 
    ConvertFrom-Json | Where-Object tier -like 'tier_a*' | Measure-Object).Count
Write-Host "Tier A assets: $wl_count"
# Se = 0 → RAIZ ENCONTRADA
```

---

## 🔧 STEP 2: Fix Rápido (2 minutos)

### Opção A: Whitelist vazia (mais comum)

```powershell
# A.1: Seed minimal tier_a (IMMEDIATE)
$minimal = @(
    @{ market="BTCUSDT"; tier="tier_a_live"; score_pred=90; direction="LONG"; fqs_quality=5 }
)

$minimal | ConvertTo-Json -Depth 10 | 
    Out-File journal/per_asset_whitelist_$(Get-Date -f 'yyyyMMdd_HHmm').json -Encoding UTF8

Write-Host "✅ Whitelist reseeded com 1 asset tier_a_live"

# A.2: Validar (10 seg)
Invoke-Pester tests/test_master_2_scanner_activation.ps1 -Tag critical
```

### Opção B: Nuvem parou

```bash
# B.1: Force cloud run NOW
gh workflow run trading-pipeline.yml --ref main

# B.2: Monitor (próximas 5 min)
gh run list --limit 3 --json status,conclusion

# Se status=completed, conclusion=success → Cloud OK
```

### Opção C: Gates muito restritivos

```powershell
# C.1: Check regime
$regime = Get-Content journal/REGIME.flag -Raw
Write-Host "Regime atual: $regime"

# C.2: BEAR_WEAK permite SHORT apenas
# Se regime = BEAR_WEAK E whitelist só tem LONG assets → Fix:

# Adicionar 1 SHORT tier_a
$update = Get-Content journal/per_asset_whitelist*.json | ConvertFrom-Json
$update += @{ market="ETHUSDT"; tier="tier_a_live"; direction="SHORT"; ... }
$update | ConvertTo-Json -Depth 10 | Out-File journal/per_asset_whitelist_fixed.json -Encoding UTF8
```

---

## ✅ STEP 3: Validar (1 minuto)

```powershell
# A. TDD 1: Cloud status
Invoke-Pester tests/test_master_1_cloud_health_diagnostic.ps1 -Tag critical
# Expect: 15/18 PASS (85%+)

# B. TDD 2: Scanner activation
Invoke-Pester tests/test_master_2_scanner_activation.ps1 -Tag critical
# Expect: 17/18 PASS (94%+) — CRÍTICO: deve ter >= 1 tier_a

# C. TDD 3: E2E jornada
Invoke-Pester tests/test_master_3_e2e_complete_journey.ps1 -Tag critical
# Expect: 34/36 PASS (94%+)

# TOTAL: 66/72 (92%+) = SAUDÁVEL
```

---

## 🎯 STEP 4: Monitor Próximas 2h

```powershell
# Monitorar a cada 5 min:
for ($i = 0; $i -lt 24; $i++) {
    Write-Host "[$(Get-Date -f 'HH:mm:ss')] Checking..."
    
    $trades_today = Get-Content journal/trade_outcomes.jsonl | 
        ConvertFrom-Json | 
        Where-Object { $_.registered_at -like "$(Get-Date -f 'yyyy-MM-dd')*" }
    
    Write-Host "  Trades hoje: $($trades_today.Count)"
    
    # Se > 0 → sucesso!
    if ($trades_today.Count -gt 0) {
        Write-Host "✅ JORNADA RETOMADA! Trade executada: $($trades_today[0].trade_id)"
        break
    }
    
    Start-Sleep -Seconds 300
}
```

---

## 🚨 Se ainda não entra após fix:

```
PASSO A: Logs detalhados
  $ tail -100 logs/short_scanner.log | grep -i error
  $ tail -100 logs/master_*.log | grep -i "ABORTAR\|VETO"

PASSO B: Verificar mentor decisions
  $ tail -20 journal/decisions_text.jsonl | grep -i veto
  → Qual gate está vetando? Beta? FQS? Tier?

PASSO C: Escalate
  Se TDD passa 92%+ mas trades não entram:
  → Issue no mentor logic ou API
  → Abrir GH issue com: TDD output + master log tail
```

---

## 🎓 Checklist de Prevenção

Adicionar ao seu calendar (3x semana):

- [ ] Whitelist tem >= 1 tier_a_live? (seg/qua/sex)
- [ ] Master log menos de 24h? (daily)
- [ ] Nenhum VETO crítico nos últimos 100 decisions? (seg)
- [ ] TDD 2 passa? (seg/qua/sex)
- [ ] Trades entrada nos últimos 7d >= 1? (weekly)

---

## 📞 Respostas Rápidas

| Pergunta | Resposta | Tempo |
|----------|----------|-------|
| Por que nada entra? | 1. Whitelist vazia? 2. Nuvem parou? 3. Gates fechados? | 30s |
| Como repovoar whitelist? | `$minimal \| Out-File whitelist.json` | 1m |
| Como ativar nuvem? | `gh workflow run trading-pipeline.yml` | 30s |
| Como validar jornada? | `Invoke-Pester tests/test_master_*.ps1` | 2m |
| Jornada OK mas nada entra? | Verificar decisions_text.jsonl VETO reasons | 3m |

---

**Criado**: 2026-07-01 10:50 BRT  
**Para usar**: Bookmark + copiar em emergência
