"""
docs/demo-pipeline.gif
6 frames: Market Scan → TechAgent → All Agents → Orchestrator → MentorAgent → Trade Setup
All drawn programmatically — no screenshots required.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib_gif import *
from PIL import ImageDraw

H   = 420
OUT = os.path.join(DOCS_DIR, "demo-pipeline.gif")

# ── Demo data ─────────────────────────────────────────────────────────────────
MARKET    = "BTCUSDT"
PRICE_STR = "$95,420.00"
CHANGE    = "+2.34%"
VOLUME    = "$892M"
FUNDING   = "+0.012%"

ENTRY  = 95_420.00
STOP   = 94_680.00
TGT1   = 97_800.00
TGT2   = 99_020.00
RR_B   = 3.0       # bruto
RR_EF  = 2.97      # efetivo pós-taxas

CONFLUENCIAS = [
    "EMA 9/21 cross 1H",
    "RSI saindo de sobrevenda (28 → 42)",
    "SMC Bull OB 4H confirmado",
    "Tori: A+ BOUNCE — 3 toques, 4 semanas",
]

AGENTS = [
    ("TechAgent",  C_BLUE,   "LONG",    72, "Setup: B+   Entry: $95,420"),
    ("FundAgent",  C_GREEN,  "BULLISH", 68, "Halving: 13m   BTC dom: 52%"),
    ("SentAgent",  C_ORANGE, "NEUTRO",  55, "F&G: 49   Funding: neutro"),
    ("ChainAgent", C_PURP_L, "BULLISH", 71, "OI↑   Whales acumulando"),
]

WEIGHTS = [
    ("TechAgent",  40, 72, C_BLUE),
    ("ChainAgent", 30, 71, C_PURP_L),
    ("SentAgent",  20, 55, C_ORANGE),
    ("FundAgent",  10, 68, C_GREEN),
]
SCORE_FINAL = 67.9
CAPITAL     = 818.00
RISCO_USD   = 1.23
POSICAO_USD = 158.00

# ── Helpers ───────────────────────────────────────────────────────────────────
def base(title="CoinEx AI Agent", subtitle=f"BTCUSDT  Futures  1H", right=PRICE_STR):
    img = make_canvas(H)
    draw_header(img, title, subtitle, right)
    return img

def y0():
    """First y after header."""
    return HEADER_H + 12

# ── Frame 1 — Market Scan ─────────────────────────────────────────────────────
def frame_market():
    img = base()
    d   = ImageDraw.Draw(img)
    y   = y0()
    x0, x1 = PAD, W - PAD

    card(d, x0, y, x1, y + 68)
    iy = y + 10
    ix = x0 + 10
    cx = dot(d, ix, iy + 5, C_PURPLE)
    d.text((cx, iy), "Iniciando pipeline de análise...", fill=C_FG, font=F_BOLD)
    iy += 20
    progress_bar(d, ix, iy, x1 - 10, 4, 0.18)
    iy += 12
    d.text((ix, iy), "Fase 0 — Verificando segurança do mercado (CoinEx-GetMarketInfo)", fill=C_MUTED, font=F_TINY)
    y += 80

    # Market data grid
    card(d, x0, y, x1, y + 88)
    iy = y + 10
    ix = x0 + 10
    d.text((ix, iy), "Mercado", fill=C_MUTED, font=F_TINY)
    d.text((ix + 68, iy), "Status", fill=C_MUTED, font=F_TINY)
    d.text((ix + 200, iy), "Volume 24h", fill=C_MUTED, font=F_TINY)
    d.text((ix + 340, iy), "Funding", fill=C_MUTED, font=F_TINY)
    d.text((ix + 450, iy), "MaxLev", fill=C_MUTED, font=F_TINY)
    iy += 14
    d.text((ix, iy), MARKET, fill=C_WHITE, font=F_BOLD)
    bx = ix + 68
    bx += badge(d, bx, iy - 2, "online", F_SMALL, tint(C_GREEN, 0.2), border_of(C_GREEN, 0.4), C_GREEN) + 8
    d.text((ix + 200, iy), VOLUME, fill=C_FG, font=F_BODY)
    d.text((ix + 340, iy), FUNDING, fill=C_TEAL, font=F_BODY)
    d.text((ix + 450, iy), "100x", fill=C_FG, font=F_BODY)
    iy += 20
    d.text((ix, iy), "Taxas confirmadas via API:", fill=C_MUTED, font=F_TINY)
    d.text((ix + 160, iy), "Maker: 0.03%", fill=C_GREEN, font=F_SMALL)
    d.text((ix + 270, iy), "Taker: 0.05%", fill=C_GREEN, font=F_SMALL)
    d.text((ix + 380, iy), "Roundtrip: 0.08%", fill=C_MUTED, font=F_SMALL)
    iy += 18
    separator(d, iy, ix, x1 - 10)
    iy += 8
    d.text((ix, iy), "MacroContext (FRED cache 24h):", fill=C_MUTED, font=F_TINY)
    cx = ix + 190
    cx += badge(d, cx, iy - 2, "BULLISH", F_SMALL, tint(C_GREEN, 0.2), border_of(C_GREEN, 0.4), C_GREEN) + 8
    d.text((cx, iy), "DXY↓   M2↑   Yields normais   score: 72", fill=C_MUTED, font=F_TINY)
    y += 100

    # Next step hint
    d.text((x0, y), "Pesos adaptativos selecionados: Regime BULLISH  →  Tech 40%  Chain 30%  Sent 20%  Fund 10%", fill=C_MUTED, font=F_TINY)
    return img

# ── Frame 2 — TechAgent result ────────────────────────────────────────────────
def frame_techagent():
    img = base()
    d   = ImageDraw.Draw(img)
    y   = y0()
    x0, x1 = PAD, W - PAD

    # Header row
    card(d, x0, y, x1, y + 34)
    iy = y + 8
    ix = x0 + 10
    cx = dot(d, ix, iy + 7, C_BLUE)
    d.text((cx, iy), "[1/4] TechAgent", fill=C_WHITE, font=F_BOLD)
    bx = cx + tw(d, "[1/4] TechAgent", F_BOLD) + 10
    bx += signal_badge(d, bx, iy - 1, "LONG", C_GREEN) + 8
    score_badge(d, bx, iy - 1, 72)
    # Right: setup quality
    rtext = "Setup: B+"
    d.text((x1 - 10 - tw(d, rtext, F_BOLD), iy), rtext, fill=C_GOLD, font=F_BOLD)
    y += 46

    # Entry / stop / target grid
    card(d, x0, y, x1, y + 56)
    iy = y + 8
    ix = x0 + 10
    col_w = (x1 - x0 - 20) // 4
    labels = ["Entrada", "Stop", "Alvo 1", "Alvo 2"]
    values = [f"${ENTRY:,.2f}", f"${STOP:,.2f}", f"${TGT1:,.2f}", f"${TGT2:,.2f}"]
    colors = [C_FG, C_RED, C_GREEN, C_GREEN]
    for i, (lbl, val, col) in enumerate(zip(labels, values, colors)):
        cx = ix + i * col_w
        d.text((cx, iy), lbl, fill=C_MUTED, font=F_TINY)
        d.text((cx, iy + 14), val, fill=col, font=F_BOLD)
    iy += 36
    d.text((ix, iy), f"Stop razão: abaixo do OB 4H + Safety Line trendline", fill=C_MUTED, font=F_TINY)
    d.text((x1 - 10 - tw(d, f"R:R bruto: {RR_B:.1f}x", F_SMALL), iy), f"R:R bruto: {RR_B:.1f}x", fill=C_ORANGE, font=F_SMALL)
    y += 68

    # Confluencias
    card(d, x0, y, x1, y + 72)
    iy = y + 8
    ix = x0 + 10
    d.text((ix, iy), "CONFLUÊNCIAS", fill=C_MUTED, font=F_TINY)
    iy += 13
    col1_x = ix
    col2_x = ix + (x1 - x0 - 20) // 2
    for i, conf in enumerate(CONFLUENCIAS):
        cx = col1_x if i % 2 == 0 else col2_x
        row_y = iy + (i // 2) * 17
        d.ellipse((cx, row_y + 4, cx + 5, row_y + 9), fill=C_BLUE)
        d.text((cx + 10, row_y), conf, fill=C_FG, font=F_SMALL)
    y += 84

    # Tori + Weinstein
    card(d, x0, y, x1, y + 36)
    iy = y + 8
    ix = x0 + 10
    d.text((ix, iy), "Tori:", fill=C_MUTED, font=F_SMALL)
    bx = ix + 34
    bx += badge(d, bx, iy - 2, "ENTER", F_SMALL, tint(C_GREEN, 0.2), border_of(C_GREEN, 0.4), C_GREEN) + 6
    badge(d, bx, iy - 2, "A+ BOUNCE", F_SMALL, tint(C_GOLD, 0.2), border_of(C_GOLD, 0.4), C_GOLD)
    d.text((ix + 220, iy), "3 toques   4 semanas   htf_aligned: true", fill=C_MUTED, font=F_TINY)
    iy += 16
    d.text((ix, iy), "Weinstein: Fase 2 — markup", fill=C_MUTED, font=F_TINY)
    d.text((ix + 190, iy), "Elder Triple Screen: ATIVO", fill=C_MUTED, font=F_TINY)
    d.text((ix + 380, iy), "Wyckoff: LPS pós-acumulação", fill=C_MUTED, font=F_TINY)
    return img

# ── Frame 3 — All agents complete ─────────────────────────────────────────────
def frame_all_agents():
    img = base()
    d   = ImageDraw.Draw(img)
    y   = y0()
    x0, x1 = PAD, W - PAD

    # Title
    d.text((x0, y), "Agentes concluídos — aguardando orquestrador", fill=C_MUTED, font=F_SMALL)
    y += 18

    for i, (name, color, sig, score, info) in enumerate(AGENTS):
        card(d, x0, y, x1, y + 44)
        iy = y + 10
        ix = x0 + 10
        # Number + dot + name
        d.text((ix, iy), f"[{i+1}/4]", fill=C_MUTED, font=F_SMALL)
        cx = dot(d, ix + 32, iy + 6, color)
        d.text((cx, iy), name, fill=C_WHITE, font=F_BOLD)
        bx = cx + tw(d, name, F_BOLD) + 10
        bx += signal_badge(d, bx, iy - 1, sig, C_GREEN if sig in ("LONG","BULLISH") else (C_ORANGE if sig == "NEUTRO" else C_RED)) + 8
        score_badge(d, bx, iy - 1, score)
        # Info on right
        rw = tw(d, info, F_SMALL)
        d.text((x1 - 10 - rw, iy), info, fill=C_MUTED, font=F_SMALL)
        iy += 18
        # Mini progress bar showing score
        progress_bar(d, ix, iy, x1 - 10, 3, score / 100, color)
        y += 56

    # Macro row
    y += 4
    card(d, x0, y, x1, y + 34)
    iy = y + 8
    ix = x0 + 10
    cx = dot(d, ix, iy + 5, C_TEAL)
    d.text((cx, iy), "MacroContext (FRED):", fill=C_WHITE, font=F_BOLD)
    bx = cx + tw(d, "MacroContext (FRED):", F_BOLD) + 10
    bx += badge(d, bx, iy - 1, "BULLISH", F_SMALL, tint(C_GREEN, 0.2), border_of(C_GREEN, 0.4), C_GREEN) + 8
    d.text((bx, iy), "score: 72   DXY↓   M2↑   Yields normais   Fed 5.25%", fill=C_MUTED, font=F_SMALL)
    return img

# ── Frame 4 — OrchestratorAgent scoring ───────────────────────────────────────
def frame_orchestrator():
    img = base()
    d   = ImageDraw.Draw(img)
    y   = y0()
    x0, x1 = PAD, W - PAD

    card(d, x0, y, x1, y + 30)
    iy = y + 8
    ix = x0 + 10
    cx = dot(d, ix, iy + 6, C_PURPLE)
    d.text((cx, iy), "OrchestratorAgent — Score consolidado", fill=C_WHITE, font=F_BOLD)
    bx = cx + tw(d, "OrchestratorAgent — Score consolidado", F_BOLD) + 10
    badge(d, bx, iy - 1, "Regime: BULLISH", F_SMALL, tint(C_GREEN, 0.2), border_of(C_GREEN, 0.4), C_GREEN)
    y += 42

    # Weight rows
    bar_x0 = PAD + 200
    bar_x1 = W - PAD - 80
    for name, weight, score, color in WEIGHTS:
        contrib = weight * score / 100
        card(d, x0, y, x1, y + 36)
        iy = y + 8
        ix = x0 + 10
        d.text((ix, iy), name, fill=C_FG, font=F_BODY)
        d.text((ix + 100, iy), f"{weight}%", fill=C_MUTED, font=F_SMALL)
        d.text((ix + 140, iy), f"× {score}", fill=color, font=F_SMALL)
        d.text((ix + 178, iy), f"= {contrib:4.1f}", fill=C_WHITE, font=F_BOLD)
        progress_bar(d, bar_x0, iy + 3, bar_x1, 8, score / 100, color)
        rtext = f"{score}/100"
        d.text((bar_x1 + 8, iy), rtext, fill=color, font=F_TINY)
        y += 46

    # Total
    y += 4
    separator(d, y)
    y += 10
    card(d, x0, y, x1, y + 42)
    iy = y + 8
    ix = x0 + 10
    d.text((ix, iy), "Score consolidado:", fill=C_FG, font=F_BODY)
    sc_str = f"{SCORE_FINAL:.1f} / 100"
    d.text((ix + 160, iy - 2), sc_str, fill=C_WHITE, font=F_BIG)
    iy += 22
    d.text((ix, iy), f"Threshold mínimo: 65   →", fill=C_MUTED, font=F_SMALL)
    bx = ix + 155
    badge(d, bx, iy - 2, "COMPRA  ✓", F_BOLD, tint(C_GREEN, 0.25), border_of(C_GREEN, 0.5), C_GREEN)
    return img

# ── Frame 5 — MentorAgent veto ────────────────────────────────────────────────
def frame_mentor():
    img = base()
    d   = ImageDraw.Draw(img)
    y   = y0()
    x0, x1 = PAD, W - PAD

    card(d, x0, y, x1, y + 30)
    iy = y + 8
    ix = x0 + 10
    cx = dot(d, ix, iy + 6, C_RED)
    d.text((cx, iy), "MentorAgent — Validação final (veto power)", fill=C_WHITE, font=F_BOLD)
    y += 42

    # Metrics row
    card(d, x0, y, x1, y + 36)
    iy = y + 8
    ix = x0 + 10
    items = [
        ("Score",     f"{SCORE_FINAL:.1f}",  C_FG),
        ("Forca TA",  "72",                   C_BLUE),
        ("Setup",     "B+",                   C_GOLD),
        ("R:R bruto", f"{RR_B:.2f}",          C_ORANGE),
        ("R:R efetivo",f"{RR_EF:.2f}",        C_GREEN),
    ]
    col_w = (x1 - x0 - 20) // len(items)
    for i, (lbl, val, col) in enumerate(items):
        cx = ix + i * col_w
        d.text((cx, iy), lbl, fill=C_MUTED, font=F_TINY)
        d.text((cx, iy + 13), val, fill=col, font=F_BOLD)
    y += 48

    # Verdict
    card(d, x0, y, x1, y + 52)
    iy = y + 10
    ix = x0 + 10
    d.text((ix, iy), "Veredicto:", fill=C_MUTED, font=F_BODY)
    bx = ix + 84
    bx += badge(d, bx, iy - 3, "EXECUTAR  ✓", F_BIG, tint(C_GREEN, 0.25), border_of(C_GREEN, 0.5), C_GREEN) + 16
    d.text((bx, iy), "Confiança: 76%", fill=C_FG, font=F_BODY)
    iy += 26
    d.text((ix, iy), "Ponto forte:", fill=C_MUTED, font=F_SMALL)
    d.text((ix + 90, iy), "Trendline A+ + OB 4H — confluência estrutural real", fill=C_FG, font=F_SMALL)
    iy += 14
    d.text((ix, iy), "Ponto fraco:", fill=C_MUTED, font=F_SMALL)
    d.text((ix + 90, iy), f"R:R {RR_EF:.2f} — no limite mínimo aceitável", fill=C_ORANGE, font=F_SMALL)
    y += 64

    # Quote
    card(d, x0, y, x1, y + 40)
    iy = y + 10
    ix = x0 + 10
    d.text((ix, iy), "Qualidade final:", fill=C_MUTED, font=F_SMALL)
    bx = ix + 110
    badge(d, bx, iy - 2, "B+", F_BOLD, tint(C_GOLD, 0.2), border_of(C_GOLD, 0.5), C_GOLD)
    iy += 16
    quote = "\"Always think about losing money, not making money.\"  — Paul Tudor Jones"
    d.text((ix, iy), quote, fill=C_MUTED, font=F_TINY)
    return img

# ── Frame 6 — Trade Setup ─────────────────────────────────────────────────────
def frame_trade_setup():
    img = base()
    d   = ImageDraw.Draw(img)
    y   = y0()
    x0, x1 = PAD, W - PAD

    # Green-bordered card
    rrect(d, (x0, y, x1, y + 30), 6, fill=tint(C_GREEN, 0.08), outline=border_of(C_GREEN, 0.4), width=1)
    iy = y + 8
    ix = x0 + 10
    cx = dot(d, ix, iy + 6, C_GREEN)
    d.text((cx, iy), "SETUP APROVADO", fill=C_GREEN, font=F_BOLD)
    bx = cx + tw(d, "SETUP APROVADO", F_BOLD) + 10
    signal_badge(d, bx, iy - 1, "LONG", C_GREEN)
    rtext = "BTCUSDT  Futures"
    d.text((x1 - 10 - tw(d, rtext, F_BOLD), iy), rtext, fill=C_MUTED, font=F_BOLD)
    y += 42

    # Price grid 2×2
    card(d, x0, y, x1, y + 72)
    iy = y + 8
    ix = x0 + 10
    half = (x1 - x0 - 20) // 2
    grid = [
        ("Entrada",   f"${ENTRY:,.2f}",  C_FG,     ""),
        ("Stop Loss", f"${STOP:,.2f}",   C_RED,    "(-0.78%)"),
        ("Alvo 1",    f"${TGT1:,.2f}",   C_GREEN,  "(+2.49%)"),
        ("Alvo 2",    f"${TGT2:,.2f}",   C_GREEN,  "(+3.78%)"),
    ]
    for i, (lbl, val, col, pct) in enumerate(grid):
        gx = ix + (i % 2) * half
        gy = iy + (i // 2) * 32
        d.text((gx, gy), lbl, fill=C_MUTED, font=F_TINY)
        d.text((gx, gy + 13), val, fill=col, font=F_BOLD)
        if pct:
            d.text((gx + tw(d, val, F_BOLD) + 6, gy + 14), pct, fill=col, font=F_TINY)
    y += 84

    # Sizing row
    card(d, x0, y, x1, y + 36)
    iy = y + 8
    ix = x0 + 10
    items = [
        ("Sizing",      "0.15% capital",       C_FG),
        ("Risco máx",   f"${RISCO_USD:.2f}",   C_RED),
        ("Posição",     f"${POSICAO_USD:.0f}",  C_FG),
        ("Capital",     f"${CAPITAL:.0f}",      C_MUTED),
        ("R:R efetivo", f"{RR_EF:.2f}x",        C_ORANGE),
    ]
    col_w = (x1 - x0 - 20) // len(items)
    for i, (lbl, val, col) in enumerate(items):
        cx = ix + i * col_w
        d.text((cx, iy), lbl, fill=C_MUTED, font=F_TINY)
        d.text((cx, iy + 13), val, fill=col, font=F_BOLD)
    y += 48

    # Stop reason
    card(d, x0, y, x1, y + 28)
    iy = y + 8
    ix = x0 + 10
    d.text((ix, iy), "Stop razão:", fill=C_MUTED, font=F_SMALL)
    d.text((ix + 82, iy), "Abaixo do OB 4H + Safety Line trendline A+ BOUNCE", fill=C_FG, font=F_SMALL)
    y += 40

    # Confirmation prompt
    card(d, x0, y, x1, y + 34)
    iy = y + 8
    ix = x0 + 10
    cx = dot(d, ix, iy + 6, C_ORANGE)
    d.text((cx, iy), "Aguardando confirmação manual:", fill=C_FG, font=F_SMALL)
    d.text((cx + 210, iy), "Digite  EXECUTAR  para confirmar", fill=C_ORANGE, font=F_BOLD)
    iy += 16
    d.text((cx, iy), "Margem isolada obrigatória — confirmar na UI CoinEx antes de operar.", fill=C_MUTED, font=F_TINY)
    return img

# ── Build & save ──────────────────────────────────────────────────────────────
frames = [
    (frame_market(),      2200),
    (frame_techagent(),   3000),
    (frame_all_agents(),  2800),
    (frame_orchestrator(),3000),
    (frame_mentor(),      3500),
    (frame_trade_setup(), 4500),
]

save_gif(frames, OUT)