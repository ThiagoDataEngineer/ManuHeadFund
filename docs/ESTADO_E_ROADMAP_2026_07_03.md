# ESTADO E ROADMAP — 2026-07-03

> Organizador único pós-sessão de estudo. O que está rodando, o que sabemos, o que falta.

---

## 1. SISTEMA (rodando e íntegro)

| Componente | Estado | Referência |
|---|---|---|
| scan_master daemon | ✅ vivo, ciclando (PS 5.1 compat total) | commits cc92c86, e17cd82 |
| 260 libs auto-load | ✅ 260/260, guard de reentrância | lib_loader_auto.ps1 v3 |
| Self-recovery | ✅ wired, agiu sozinho 03/07 07:45 | scan_master:94 |
| Telegram + dedup | ✅ fluindo (alertou ZKP 65) | lib_telegram.ps1 (-join fix) |
| CONVICTION_GATE → Tori override | ✅ wired no pre-check GemScan | commit 43d6634 |
| Learning engine | ✅ coletando (2010 snaps, 20 outcomes) | reliable=0 — falta amostra |
| Trailing spot | ⚠️ stops exchange-side OK; watcher local OFF (nuvem JOB1, 5-30min) | decisão pendente |
| Posições | 0 futures abertas; BREV fechou +5.15, RAY -0.81, DYDX +24.58 | trade_outcomes.jsonl |
| Quality gates | SCORE_MINIMO=75, G8 block, BETA 1.4 — INTACTOS | nada foi afrouxado |

## 2. CONHECIMENTO NOVO (validado por dados — knowledge/UNIVERSE_PHYSICS.md)

**As 4 leis** (921 pares, 15m→anual, commit ad61d3c):

1. **Dissipação fractal**: pump grande → reversão; momentum morre em <4h; vale de 15m a 1w
2. **Assimetria**: fade-the-pump paga; knife-catching não (bounce só em 4h, fino demais p/ fees)
3. **W(t)** = EWMA(pump_rate, hl=2d): ondas de 2-3d, corr +0.56 amanhã, AMPLIFICA o short
4. **Drift estrutural**: microcap = -41%/ano mediano (survivors); mensal negativo em todo bin

**Anatomia da ignição** (1h, n=663): aviso pré-pump = 1-2 HORAS (vol 1.26x em H-1);
pico 12h BRT, janela quente 05-14 BRT; ressaca inicia h+1; 46% têm saída +5% em h+1.

## 3. AUDITORIA (persona HeadFund, López de Prado/Simons)

| Achado | Veredicto |
|---|---|
| Lei de dissipação | ✅ PASSA: OOS 4 regimes (2023 bull -3.1% → 2026 bear -7.5%), effective-N 919 dias, 70% win POR DIA |
| W(t) | ✅ passa c/ ressalva (in-sample leve) |
| **Shortability** | ❌ **CRÍTICO: só 7% dos pumps ≥30% têm futures (0.4/dia, não 5/dia)**; edge nos shortáveis: -7.4%, 60% |
| Custos (fees/funding/slippage/gaps) | ⚠️ NÃO modelados ainda |
| Assinatura H-1 (long) | ⚠️ sem precision/recall — não é gatilho ainda |
| Anatomia horária | ⚠️ 41 dias, 1 regime — revalidar |
| Sazonalidade mensal | ❌ descartada (2-3 obs/mês; regime do ano domina) |
| Fingerprint diária LONG | ❌ não existe (honesto: reportado) |

**Insight arquitetural (do usuário):** o alfa é EVENT-DRIVEN (eventos de meia-vida curta);
o sistema é polling (30-120min). Gap = latência evento→reação. Trigger-bus fase 1 existe;
produtores de evento por mercado nunca concluídos.

## 4. BACKLOG PRIORIZADO (nada implementado sem GO do dono)

| # | Evolução | Fundamento | Esforço | Status |
|---|---|---|---|---|
| 1 | **Regra de SAÍDA spot no clímax** (bag pumpou ≥20-30% → harvest; mediana -8% amanhã) | Lei 1+2; monetiza SEM futures; zero risco novo | baixo | aguarda GO |
| 2 | **Backtest c/ custos dos 45 shortáveis reais** (fees+funding+slippage+gaps) | auditoria exige antes de short live | médio | aguarda GO |
| 3 | Precision/recall da assinatura H-1 (viabilidade do LONG intraday) | sem isso, long não tem gatilho | médio | aguarda GO |
| 4 | W(t) como indicador live (regime-amplificador no journal) | Lei 3; leitura diária barata | baixo | aguarda GO |
| 5 | Time-stop para LONGs de microcap | Lei 4 (drift -41%/ano) | baixo | aguarda GO |
| 6 | Arquitetura event-driven completa (detectores 15m → fila → reação em min) | anatomia (aviso 1-2h); trigger-bus fase 2 | alto | aguarda GO |
| 7 | Scheduler: intensificar 05-14 BRT (pico 12h) | anatomia horária | baixo | revalidar anatomia antes |
| — | Baixar SCORE_MINIMO / relaxar gates SHORT | rejeitado pelo dono 03/07 | — | DESCARTADO |
| — | Sazonalidade mensal como sinal | não sobreviveu à auditoria | — | DESCARTADO |

## 5. PENDÊNCIAS TÉCNICAS MENORES

- 3 CLIs manuais com parse error 5.1 (setup_telegram, start_services, trailing_long) — mojibake antigo, nenhum daemon usa
- position_watcher local: religar ou não (nuvem cobre com latência)
- Learning: 20 outcomes; Kelly precisa 10+ graduados
- Anatomia 1h: recoletar em regime diferente (daqui ~2-3 meses)
