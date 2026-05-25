# 📊 ANÁLISE PROFUNDA: Trailing Stop nas Posições Reais
**Data:** 2026-05-25 12:05  
**Trailing system:** 3 fases (BE → Lock33 → Trail15)

---

## 🔧 Como o trailing atual funciona

| Fase | Gatilho | Ação | Stop após |
|------|---------|------|-----------|
| **0** | Inicial | Stop original (ATR) | Stop original |
| **1** | Preço atinge **+33%** do range entry→target | Move stop para breakeven + buffer 2% | `entry + 2%*range` |
| **2** | Preço atinge **+66%** do range | Lock 33% do ganho | `entry + 33%*range` |
| **3** | Preço **rompe target** | Trailing 15% abaixo do peak | `peak * 0.85` |

---

## 🎯 ESTADO REAL vs ESPERADO

### UNIUSDT — Phase 0 ⚠️ EM PERIGO
| | |
|---|---|
| Entry | $3.46 |
| Atual | $3.39 (**-1.94%**) |
| Stop | $3.30 (**2.74%** do atual) |
| Peak | $3.46 (não passou do entry) |
| Volatilidade | ATR 0.83%/h |

**Diagnóstico:** Posição em prejuízo, trailing inativo (correto). Stop está a apenas **3.3 ATRs** = perigoso.  
**Risco:** Se mover -3% mais, stop fechado. ATR 0.83%/h → pode tocar em ~3-4 horas se continuar caindo.

### LINKUSDT — Phase 0 🟡 NEUTRO
| | |
|---|---|
| Entry | $9.59 |
| Atual | $9.62 (+0.31%) |
| Stop | $9.15 (-4.84%) |
| Peak | $9.59 (não subiu nada) |
| Para Phase 1 | precisa $9.72 (+1.4%) |

**Diagnóstico:** Folga grande até stop. Esperando movimento.  
**Falta para Phase 1:** subir 1.4% para $9.72.

### BNBUSDT — Phase 1 ✅ PROTEGIDO (mas há problema!)
| | |
|---|---|
| Entry | $647.06 |
| Atual | $671.52 (+3.78%) |
| Stop | $647.71 (breakeven+0.1%) |
| Peak bot | $662.24 |
| **Peak real (48h)** | **$672.89** ⚠️ |
| Para Phase 2 | precisa $668.54 |

**🚨 BUG ENCONTRADO:** Peak real é **$672.89** mas peak registrado pelo bot é **$662.24**. 

Se o peak real fosse atualizado:
- $672.89 já passou do gatilho Phase 2 ($668.54) → **deveria estar em Phase 2 com stop em $657.80**
- Atualmente stop está em $647.71 (breakeven+) — **perdeu lock de 33% do ganho**
- $25 de potencial profit travado vs $10 atual

**Causa:** Trailing rodou pela última vez 09:02 (hoje), peak alto foi entre 09-10h.

### SOLUSDT — Phase 0 🟡 NEUTRO
| | |
|---|---|
| Entry | $86.04 |
| Atual | $86.35 (+0.36%) |
| Stop | $82.30 (-4.69%) |
| Peak | $86.04 (não subiu) |
| Para Phase 1 | precisa $87.21 (+1.0%) |

**Diagnóstico:** Idêntico LINK — esperando movimento.

---

## 🚨 PROBLEMAS IDENTIFICADOS

### Problema 1: Trailing não roda no GitHub Actions
- Última atualização: **09:02 UTC** (3h atrás)
- O job `trailing-stop-monitor` roda a cada 5min, mas só atualiza posições do `trailing_positions.json` se conectar ao **detect-orphan + Update-AllTrailingStops**
- Suspeito: a função `Update-AllTrailingStops` pode não estar atualizando peak corretamente

### Problema 2: Phase ranges são muito conservadores
Para BNB com range pequeno ($647 → $680 = $33 = 5.1% gain):
- Phase 1 (BE): em $657 (1.6% gain)
- Phase 2 (lock33): em $668 (3.3% gain)
- Phase 3 (trail): em $680

Isso é **bom para alvo conservador**, mas o trailing 15% é muito agressivo:
- Se BNB tocar $680 e cair, stop fica em $578 (15% abaixo)
- Vai dar **stop com profit baixo** se houver pullback

### Problema 3: Não há trailing baseado em ATR
Trailing atual é baseado em **% do range entry→target**. Mas:
- UNI ATR 0.83%/h × 24h = **~20% volatilidade diária**
- Stop de 4.6% pode ser pouco em mercado volátil
- BNB ATR 0.42%/h × 24h = **~10% volatilidade diária**
- Stop de 3.6% pode ser apertado demais

---

## 💡 RECOMENDAÇÕES

### Curto prazo (agora)
1. **🔥 ATUALIZAR PEAK MANUALMENTE NO BNB** — está perdendo Phase 2
2. **Forçar rodada do trailing** — `Update-AllTrailingStops`
3. **Avaliar UNI** — em -2%, considerar ajustar stop ou aceitar perda parcial

### Médio prazo (esta semana)
4. **Adicionar trailing por ATR** — mais inteligente que % fixo
5. **Reduzir trail Phase 3 de 15% para 8-10%** — proteger lucros melhor
6. **Adicionar buffer de tempo** — não trail em primeiros 30min após entry

### Longo prazo
7. **Trailing adaptativo por volatilidade** (já tem `lib_trailing_stop_adaptive.ps1` mas não está sendo usado!)
8. **Phase 4 — Stop em zonas estruturais** (HH/HL, médias móveis)

---

## ⚙️ Código a investigar/corrigir

`agents/lib_trailing.ps1`:
- `Update-TrailingStops` — verifica se está sendo chamada
- `Get-TrailingNewStop` — verifica se atualiza peak corretamente

`agents/lib_trailing_stop_adaptive.ps1`:
- Existe mas não está integrado ao trailing principal!
