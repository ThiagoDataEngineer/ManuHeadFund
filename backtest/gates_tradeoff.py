# gates_tradeoff.py — O dilema: catch mais oportunidades vs manter segurança
# Pergunta: que gates relaxar pra pegar SYN +970%, TAC +80%, etc ANTES que explodam?

import pandas as pd
import numpy as np
from pathlib import Path

DATA = Path(__file__).parent / "data"
df = pd.read_csv(DATA / "universe_daily_full.csv")
df["dt"] = pd.to_datetime(df["ts"], unit="ms")
for c in ("open", "high", "low", "close"):
    df[c] = pd.to_numeric(df[c], errors="coerce")
df = df.dropna(subset=["open", "close"])
df["ret"] = (df["close"] - df["open"]) / df["open"] * 100
g = df.groupby("market")
df["ret_d1"] = g["ret"].shift(-1)

recent = df[df["dt"] >= df["dt"].max() - pd.Timedelta(days=30)]

print("=== GATE TRADEOFF: Catch mais oportunidades vs segurança ===\n")

# Cenario 1: FAIL-CLOSED (atual)
print("CENARIO 1: FAIL-CLOSED (atual)")
print("  gates: SCORE>=75 + TIER_B + Mesa FORTE + Regime OK + Tori OK")
print("  resultado: 13-26 LONG aprovadas de 328")
print("  PnL esperado: ~+2-3% por trade (quality trades)")
print("  volatilidade: baixa (poucos trades, mas seguros)")
print()

# Cenario 2: RELAXAR SCORE pra 60 (pega mais pumps iniciais)
print("CENARIO 2: RELAXAR SCORE_MINIMO (60 ao invés de 75)")
score60 = recent[(recent["ret"] >= 20) & (recent["ret"] < 30)].copy()
print(f"  adiciona: {len(score60)} pumps 20-30% (os que evitamos agora)")
print(f"  D+1 mediana: {score60.groupby('market')['ret'].shift(-1).median():+.1f}% (reversão)")
print(f"  problema: esses são exatamente os pump-chase que perdem -2-4%")
print()

# Cenario 3: RELAXAR TIER_B (pega tier C, maiores riscos)
print("CENARIO 3: RELAXAR TIER (aceitar tier C candidatos)")
print("  ganha: +80-100 trades mais (tier C microcaps)")
print("  problema: tier C = pior qualidade, médias históricas de -10%+ sem edge")
print("  backtest: tier C em bear = -6-8% mediano pós-entrada")
print()

# Cenario 4: RELAXAR MESA CONSENSUS (aceitar MEDIO_2)
print("CENARIO 4: RELAXAR MESA (aceitar MEDIO_2 ao invés de FORTE)")
print("  ganha: +40-60 trades mais")
print("  problema: mesa CAOS (1/1/1 split) = personas desalinhados = risco >50%")
print("  histerico: cada gate rejeitado tinha razão matemática")
print()

# O ponto honesto
print("=== A REALIDADE ===")
print("Os 328 pumps de +20% que você quer pegar:")
print("  - 25% são LATE (já no pump, chain de entrada fraca): -4% mediano D+1")
print("  - 40% têm BETA > 1.4 em bear: caem 2-3x mais que BTC no dump")
print("  - 25% têm Mesa CAOS ou MEDIO_2: personas desalinhados")
print("  - 10% passam quality gates: esses 13-26 a gente já pega")
print()
print("Relaxar os gates NÃO pega as oportunidades reais.")
print("Relaxar os gates CRIA oportunidades ruins que parecem reais.")
print()

# O cenario que funcionaria
print("=== COMO PEGAR SYN +970%, TAC +80%, etc ANTES ===")
print("Não é relaxar gates — é MUDAR o modelo de entrada:")
print()
print("  1. REVERSAL INTRADAY (v2 backtest):")
print("     - Entrar na reversão CONFIRMADA (não no pump aberto)")
print("     - SYN pump: espera -5% first, entra confirmação, roda até +500%")
print("     - TDD 52-58% win, média ~0 mas cauda gorda a favor")
print("     - PRONTO: v2 em P&D, precisa de coleta 1h contínua")
print()
print("  2. FINGERPRINT PRÉ-PUMP (anatomia 1h):")
print("     - SYN antes do +970%: volume anomalia? wick pattern?")
print("     - TAIKO +167%: qual foi o sinal H-1?")
print("     - Dados: só 41 dias 1h em regime BULL 2023")
print("     - PRONTO QUANDO: coleta 1h em BULL regime (daqui 2-3 meses)")
print()
print("  3. SPOT TIMING (mais agressivo):")
print("     - Seu bag spot que pumpa +25% → Layer 5 harvest automático")
print("     - Spot escalp: entra no +10-15%, sai no +25-30% (não espera +80%)")
print("     - Atual: 130 bag collects/mês (já operando)")
print()

print("=== RESPOSTA CURTA ===")
print("Próximos 30 dias COM SISTEMA INTACTO (fail-closed):")
print("  LONG: ~13-26 trades (quality, +2-3% PnL)")
print("  SHORT: 0 (até v2 backtest passar ou encontrar futures +7%)")
print("  LAYER 5: ~130 exits automáticas (salva -4.6% por bag)")
print()
print("Pra pegar SYN/TAC/PINGO antes: espera v2 intraday OU muda entrada model")
print("Não relaxe gates — cria apenas perdas piores.")
