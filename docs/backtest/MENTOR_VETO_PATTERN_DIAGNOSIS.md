# Mentor 96% Veto Rate — Diagnosis (2026-05-23)

> Pattern: doc-alongside-TDD. Investigation completa do 96% veto pattern visto em
> logs. Conclusao: feature, nao bug.

## Trigger

User flagou em log TG: "7/7 ABORTAR ()" — Mentor parecia over-cautious. Suspeita inicial:
regressao das wires E2/E3/E1 deployed em 22/05 02:00 UTC.

## Investigation method

Parse `journal/decisions.csv` (212 entries totais, 142 Mentor invocations excluindo
whitelist SKIPs). Split PRE-deploy vs POST-deploy + breakdown por abort_stage.

## Findings

### Distribution PRE-deploy (until 22/05 02:00 UTC)
- 136 Mentor calls
- **130 ABORTAR (96%)**
- 6 PAPER (4%) — todas via MCE_PAPER flag (paper-trade observatory, nao Mentor APROVAR)
- **0 EXECUTAR**

### Distribution POST-deploy (22/05 02:00 UTC onwards)
- 6 Mentor calls
- 6 ABORTAR (100%)
- 0 PAPER, 0 EXECUTAR

### Abort stages breakdown (136 ABORTARs total)
| Stage | Count | % | Significa |
|---|---|---|---|
| mesa | 44 | 32% | Mesa consensus weak (MEDIO_2 quando Tier B exige FORTE) |
| triagem | 40 | 29% | Tier C/D rejected antes do Mentor |
| mce | 21 | 15% | Market Conditions Engine score baixo |
| other | 15 | 11% | Gates ortogonais (BETA cap, drawdown, etc) |
| **mentor** | **15** | **11%** | **Mentor LLM proprio vetou** |
| whitelist | 1 | 1% | Blacklist hit |

### Mesa consensus distribution
- 54 calls sem mesa (Tier A pre-validado, Mesa skip by design)
- 47 MEDIO_2 (frequentemente leva a abort em Tier B/C)
- 41 FORTE_3 (maior probabilidade pass)

## Conclusao senior

**96% veto rate eh FEATURE, nao regressao das wires.**

Evidence:
1. Padrao **pre-deploy era ja 96%** (130/136) — wires nao causaram
2. **Mentor isolado** veta apenas 11% (15/136) — outros 89% sao gates upstream
3. **POST-deploy** so tem 6 calls — sample estatisticamente insignificante pra inferencia
4. Regime atual: BEAR_STRONG/BEAR_WEAK presentes, transition zone — alto reject rate esperado

System eh **intencionalmente conservador**. Sem trade > trade ruim (regra de ouro #6
"Aguardar e uma posicao").

## Implications

### Para deploy decisions
Nao ha acao corretiva needed. Sistema funciona como projetado.

### Para forward validation (Caminho 2)
- 0 EXECUTAR significa lib_wss_forward_tracker nao captura ainda (signals Tier S
  raros + Mentor veto downstream)
- WSS Tier S detection independente de Mentor veto: scanner trigger captura
  signal mesmo se Mentor depois veta downstream
- Forward validation continua valido como observatory

### Para regime detection
54 calls sem mesa (Tier A pre-validated) eh GRANDE proporcao. Indica que
maioria dos signals chegam via Tier A direto. Mentor vetar Tier A LIVE
deve ser rare event (e indica algo errado com signal source).

## Skill insight permanente

> **"High veto rate sozinho nao indica bug — verifique abort_stage distribution antes
> de assumir regressao"**.
>
> Pattern: 96% veto poderia ser:
> (a) Pipeline funcionando corretamente (gates upstream filtrando) — usual case
> (b) Mentor over-cautious (LLM proprio rejeitando demais) — rare
> (c) Setup data ruim (entry=0/stop=0 trigger veto automatico) — caso de bug
>
> Sempre **drill down em abort_stage** antes de mudar prompt/lib. Se mentor < 30% dos
> aborts, gates upstream sao a causa real.

## Artefatos

- Doc: este arquivo
- Source data: [journal/decisions.csv](../../journal/decisions.csv) (212 rows analyzed)
- Wires deployment: [project_session_2026_05_23_complete.md](../../../.claude/projects/c--Users-thiag-Coinex-AI-USER-API/memory/project_session_2026_05_23_complete.md)
