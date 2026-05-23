# 🚀 GEM_LOOP - Startup & Status Guide

## Quick Start

### Via PowerShell (Windows 5.1+)
```powershell
cd C:\Users\thiag\Coinex_AI_USER_API
.\start_services.ps1
```

### Via CMD
```batch
cd C:\Users\thiag\Coinex_AI_USER_API
start_services.bat
```

### Manual Direto
```powershell
cd C:\Users\thiag\Coinex_AI_USER_API
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\gem_loop.ps1 -Force
```

---

## O que foi Corrigido

### Race Condition Fix ✅
```
ANTES: [WARN] Invoke-GemScan nao disponivel; pulando cycle
AGORA: [INFO] GemLoop iniciado. Interval=60min | Mode=LIVE | PID=XXXX
```

**Mudanças:**
- ✅ Sourcing explícito com error handling
- ✅ Validação early de Invoke-GemScan (startup, não runtime)
- ✅ Ordem de sourcing respeitada (config → core libs → gem agents)
- ✅ Idempotent lock (apenas 1 instância por vez)

### Arquivos Modificados
- `scripts/gem_loop.ps1` — lines 59-102 (sourcing block)
- `scripts/gem_loop.ps1` — line 107 (debug log)
- `scripts/gem_loop.ps1` — line 112 (removed check redundante)

### Novos Scripts
- `start_services.ps1` — inicialização com validação
- `start_services.bat` — versão batch
- `scripts/test_gem_loop_load.ps1` — teste isolado
- `gem_loop_fix_summary.md` — documentação completa

---

## Estrutura gem_loop

```
[Startup - Sequence Crítica]
  1. Set-Location $projectRoot
  2. Load config (com error handling)
  3. Load core libs: coinex → telegram → journal
  4. Load guards: live_guards, quant_whitelist, gem_safety
  5. Load gem agents: gem_agent → gem_executor
  6. VALIDATE Invoke-GemScan available ← NOVO
  7. Log debug info
  
[Main Loop - Continuous]
  While true:
    - Invoke-GemScan -TopN 5
    - Para cada gem encontrado:
      - Invoke-GemExecute (com guards)
      - Log resultado
    - Sleep 60 min (configurável)
```

---

## Monitoramento

### Ver Logs em Tempo Real
```powershell
# PowerShell
Get-Content "C:\Users\thiag\Coinex_AI_USER_API\journal\gem_loop.log" -Wait

# CMD
type C:\Users\thiag\Coinex_AI_USER_API\journal\gem_loop.log
```

### Ver Processo Ativo
```powershell
Get-Process powershell | Where-Object { $_.CommandLine -like "*gem_loop*" } | Format-Table Id, Name, CommandLine
```

### Status Detalhado
```powershell
$gemLog = "C:\Users\thiag\Coinex_AI_USER_API\journal\gem_loop.log"
Get-Content $gemLog -Tail 20
```

---

## Troubleshooting

### Problema: "Invoke-GemScan nao disponivel"
```
✗ BEFORE FIX:
  Script continuava silenciosamente sem a função

✓ AFTER FIX:
  [ERROR] Invoke-GemScan nao esta disponivel apos sourcing
  exit 1
  
  → Script FALHA EXPLICITAMENTE se lib não carrega
  → Log detalhado: qual lib falhou e por quê
```

### Problema: Multiple Instances
```
Idempotent lock (já estava OK):
  if gem_loop JÁ rodando:
    [SKIP] Outro gem_loop VIVO ja rodando (PID=XXX); este PID=YYY exit.
    
  -Force flag bypassa idempotent:
    .\gem_loop.ps1 -Force
```

### Problema: Config Not Loading
```
ANTES: . config.ps1 2>&1 | Out-Null  # silencia tudo

AGORA: . config.ps1 -ErrorAction Stop
       (erro é capturado, loggado, exit 1)
```

---

## Parameters

```powershell
.\gem_loop.ps1 [-CheckInterval <minutes>] [-Once] [-Force]

-CheckInterval     Ciclo em minutos (default: 60)
-Once              Roda 1 cycle e sai (para teste)
-Force             Bypass idempotent lock
```

### Exemplos

```powershell
# Ciclo curto de teste
.\gem_loop.ps1 -CheckInterval 5 -Once

# Modo produção (60 min, contínuo)
.\gem_loop.ps1

# Force restart
.\gem_loop.ps1 -Force

# 30 min ciclo
.\gem_loop.ps1 -CheckInterval 30
```

---

## Integration with scan_master.ps1

| Script | Freq | Propósito |
|--------|------|-----------|
| **gem_loop.ps1** | 1h (configurável) | Caça micro-caps explosivos (INTRADAY) |
| **scan_master.ps1** | 1x/dia | Orchestrator V6: BTC/ETH (DAILY) |

- Rodam **independentemente**
- Mesma conta CoinEx (compartilham capital)
- Logs separados: `gem_loop.log` vs `scan_master.log`

---

## Cycle Flow Detalhado

### Cada Ciclo (padrão 60min)
```
[CYCLE] Iniciando GemScan
  ├─ Get-GemSpotTickers (CoinEx spot universe ~1017 pares)
  ├─ Get-CoinExVolSpike (G1: vol spike ≥ 2.3x)
  ├─ Get-GemCoinGeckoData (G2-G4: mcap, narrative)
  ├─ Get-GemStructureScore (G5: 1H structure)
  ├─ Test-OrganicAccumulation (G6: wash trading detection)
  ├─ Get-GemFingerprintScore (G7: pump pattern match)
  │
  └─ Para cada GEM com score ≥ threshold:
      ├─ Invoke-GemExecute -Gem $gem
      └─ Log resultado (EXEC, BLOCKED, DRY, ERROR)

[INFO] GemScan: N gem(s) encontrados
[INFO] Dormindo 60min ate proximo cycle
```

---

## Log Entry Examples

### SUCCESS
```
[2026-05-18 02:15:45] [CYCLE] Iniciando GemScan (mode=LIVE)
[2026-05-18 02:15:52] [INFO] GemScan: 2 gem(s) encontrados
[2026-05-18 02:15:53] [GEM] SKYAIUSDT score=82 mode=DISCOVERY
[2026-05-18 02:15:54] [EXEC] SKYAIUSDT order=123456789 qty=1.23
[2026-05-18 02:15:54] [INFO] Dormindo 60min ate proximo cycle
```

### ERROR (OLD)
```
[2026-05-18 01:31:35] [WARN] Invoke-GemScan nao disponivel; pulando cycle
```

### ERROR (NEW - FAILS EARLY)
```
[2026-05-18 02:00:00] [ERROR] Falha ao carregar config: Cannot find path...
exit 1
```

---

## Files Changed/Created (2026-05-18)

| File | Type | Change |
|------|------|--------|
| `scripts/gem_loop.ps1` | EDIT | Sourcing + validation fix |
| `start_services.ps1` | NEW | Safe startup wrapper |
| `start_services.bat` | NEW | Batch startup option |
| `scripts/test_gem_loop_load.ps1` | NEW | Validation test |
| `gem_loop_fix_summary.md` | NEW | Technical documentation |

---

## Next Steps

1. ✅ Rodar `start_services.ps1`
2. ✅ Verificar gem_loop.log tem "[INFO] GemLoop iniciado"
3. ✅ Monitorar por 24h: sem "[WARN] nao disponivel"
4. ✅ Validar gems executados: `journal/gem_trades.csv`

---

**Status**: 🟢 **PRONTO PARA PRODUÇÃO**

*Fix implantado 2026-05-18 01:40 BRT*
*Próxima review: 2026-05-19 (depois de 24h operação)*
