# Trade Rejection Codes - Referência Rápida

## 📋 Visão Geral

A partir de 2026-05-29, as razões de rejeição de trades foram truncadas no log master para evitar inflação de contexto. As razões completas são armazenadas em `journal/trade_reasons.jsonl`.

## 🔴 Códigos de Rejeição Principais

### Triagem (Tier)

| Código | Significado | Ação |
|--------|-------------|------|
| **Tier A** | Score alto (80+), macro favorável | Pula Mesa, vai direto ao Mentor |
| **Tier B** | Score médio (50-79), análise técnica necessária | Passa por Mesa + Mentor |
| **Tier C** | Score baixo (30-49), rejeição estrutural | Bloqueado em modo STANDARD |
| **Tier D** | Score muito baixo (<30), ruído puro | Bloqueado imediatamente |

### Mesa (Consensus)

| Código | Significado | Ação |
|--------|-------------|------|
| **FORTE_3** | T+R+L alinhados (3/3 votos) | Passa ao Mentor |
| **MEDIO_2** | 2/3 votos alinhados | Requer Mentor para validar |
| **MEDIO_1** | 1/3 votos alinhados | Rejeição provável |
| **CAOS** | Desacordo genuíno (1/1/1) | Bloqueado |
| **MESA_DEGRADED** | Drones LLM falharam | Bloqueado por segurança |

### Mentor (Decision)

| Código | Significado | Ação |
|--------|-------------|------|
| **APROVAR** | Mentor validou o setup | Trade executado (ou paper) |
| **VETAR** | Mentor rejeitou | Trade bloqueado |
| **HARD_VETO** | Red flag extremo | Trade bloqueado + blacklist 24h |

### Regime

| Código | Significado | Impacto |
|--------|-------------|--------|
| **BULL_STRONG** | Uptrend confirmado | LONG favorecido |
| **BULL_WEAK** | Uptrend fraco | LONG com restrições |
| **SIDEWAYS** | Range-bound | Ambos com restrições |
| **BEAR_WEAK** | Downtrend fraco | SHORT favorecido |
| **BEAR_STRONG** | Downtrend confirmado | LONG bloqueado |
| **TRANSITION_UP** | Reversão para cima | Aguardar confirmação |
| **TRANSITION_DOWN** | Reversão para baixo | Aguardar confirmação |

## 🔍 Razões Comuns de Rejeição

### 1. **ALPHA_HIST ABSENT**
- **Significado**: Ativo sem histórico de trades bem-sucedidos
- **Impacto**: Mentor veta em Tier B
- **Solução**: Aguardar 10+ trades para calibração

### 2. **BETA VIOLATION**
- **Significado**: Beta do ativo acima do limite (WARN=1.1, BLOCK=1.4)
- **Impacto**: Bloqueio matemático em fase bear
- **Solução**: Aguardar regime BULL ou redução de beta

### 3. **TORI PROXIMITY**
- **Significado**: Resistência/suporte TORI muito próximo (< 3%)
- **Impacto**: R:R desfavorável
- **Solução**: Aguardar breakout ou movimento de TORI

### 4. **FQS SPECULATIVE**
- **Significado**: Qualidade do ativo abaixo de threshold (< 4/7)
- **Impacto**: Rejeição em Tier B/C
- **Solução**: Aguardar melhoria de volume/liquidez

### 5. **CONSENSUS FRACO**
- **Significado**: Mesa retorna MEDIO_2 ou CAOS
- **Impacto**: Mentor rejeita por falta de confluência
- **Solução**: Aguardar alinhamento de T+R+L

### 6. **REGIME HOSTIL**
- **Significado**: Regime BEAR_STRONG + sinal LONG
- **Impacto**: Contradição estrutural
- **Solução**: Aguardar reversão de regime

## 📊 Estatísticas de Rejeição

### Por Estágio (2026-05-29)

```
Triagem:  ~40% (Tier C/D bloqueados)
Mesa:     ~30% (Consensus fraco)
Mentor:   ~20% (Red flags)
Aprovado: ~10% (Executado ou Paper)
```

### Por Razão (Top 5)

1. **Regime BEAR + LONG**: 25%
2. **Consensus MEDIO_2**: 20%
3. **ALPHA_HIST ABSENT**: 15%
4. **BETA VIOLATION**: 12%
5. **TORI PROXIMITY**: 10%

## 🛠️ Como Usar o Arquivo de Razões

### Consultar Razões Completas

```powershell
# Importar biblioteca
. agents/lib_trade_reason_archive.ps1

# Obter razões de um mercado
$reasons = Get-TradeReasonArchive -Market "INJUSDT" -LastN 10

# Ver estatísticas
$stats = Get-TradeReasonStats
$stats.by_market | Sort-Object Value -Descending | Select-Object -First 5
```

### Analisar Padrões

```powershell
# Razões mais comuns
$reasons = Get-TradeReasonArchive
$reasons | Group-Object { $_.reason.Substring(0, 50) } | Sort-Object Count -Descending
```

## 📝 Exemplo de Razão Truncada vs Completa

### No Log Master (Truncado)
```
[11:29:05] [TRADE] INJUSDT: ABORTAR regime=BULL_STRONG direction=LONG scanner_score=32.66 score_predicted=72 tier=B consensus=FORTE_3 razao=TIER_B exige Mesa consensus FORTE (T+R+L) — confirmado com FORTE_3 — mas phase=h24_p3_bear com bias=BULL_STRONG cria contradição estrutural: comprar bounce em bear phase sem alpha histórico (ALPHA_HIST ABSENT) e TORI LONG apenas em 'watch' (proximity 6.73%, não ripening) não configura capitulação confirmada. Livermore: em bear phase, o ônus da prova é do comprador — 18 confluências macro não substituem ausência de alpha local + TORI não ativado...
```

### Em journal/trade_reasons.jsonl (Completo)
```json
{"timestamp":"2026-05-29 11:29:05","market":"INJUSDT","decision":"ABORTAR","reason":"TIER_B exige Mesa consensus FORTE (T+R+L) — confirmado com FORTE_3 — mas phase=h24_p3_bear com bias=BULL_STRONG cria contradição estrutural: comprar bounce em bear phase sem alpha histórico (ALPHA_HIST ABSENT) e TORI LONG apenas em 'watch' (proximity 6.73%, não ripening) não configura capitulação confirmada. Livermore: em bear phase, o ônus da prova é do comprador — 18 confluências macro não substituem ausência de alpha local + TORI não ativado."}
```

## 🔗 Referências

- **MENTOR.md**: Regras do Mentor
- **CLAUDE.md**: Filosofia de trading
- **lib_trade_reason_archive.ps1**: Funções de arquivo
- **lib_trade_logger.ps1**: Formatação de logs

## 📅 Histórico de Mudanças

- **2026-05-29**: Implementação de truncamento de razões + arquivo JSONL
- **2026-05-23**: Introdução de veredicto_5tier no Mentor
- **2026-05-20**: Adição de mentor_mensagem estruturada
