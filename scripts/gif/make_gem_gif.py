"""
docs/demo-gem.gif
4 frames: Scanning → Spike detected → Gates passing → DISCOVERY alert
All drawn programmatically — no screenshots required.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib_gif import *
from PIL import ImageDraw

H   = 400
OUT = os.path.join(DOCS_DIR, "demo-gem.gif")

# ── Demo data (SKYAIUSDT — validado historicamente: +441%) ───────────────────
MARKET    = "SKYAIUSDT"
PRICE     = 0.1620
SPIKE     = 4.2
MCAP      = 1_200_000
MODE      = "DISCOVERY"
SCORE     = 82
ENTRY     = 0.1620
STOP      = 0.0810
TARGET    = 0.4860
SIZING    = 0.20
RISCO_USD = 1.64
LISTING_D = 4

GATES = [
    ("G1", "Volume spike",     f"{SPIKE}x média 3 dias",                     True,  25, C_BLUE),
    ("G2", "Range diário",     "38% no dia",                                  True,  15, C_TEAL),
    ("G3", "Mcap tier",        f"${MCAP/1e6:.1f}M  →  DISCOVERY",            True,  15, C_GREEN),
    ("G4", "Narrativa",        "keyword AI (Tier 1) + CoinGecko rank 203",    True,  15, C_GOLD),
    ("G5", "Estrutura 1H",     "preço > VWAP + HH/HL formando",               True,  10, C_PURP_L),
    ("G6", "Orgânico",         "CV=0.73  wash=18%  wicks ok",                 True,  10, C_ORANGE),
    ("G7", "Fingerprint",      "FP-004-SKYAI  similaridade: 78%",             True,  10, C_PURPLE),
]

# ── Header ────────────────────────────────────────────────────────────────────
def base():
    img = make_canvas(H)
    draw_header(img, "GemAgent", "Micro-Cap Scanner  CoinEx  1.017 pares USDT", "DISCOVERY mode")
    return img

def y0():
    return HEADER_H + 12

# ── Frame 1 — Scanning pairs ──────────────────────────────────────────────────
def frame_scanning():
    img = base()
    d   = ImageDraw.Draw(img)
    y   = y0()
    x0, x1 = PAD, W - PAD

    # Status card
    card(d, x0, y, x1, y + 50)
    iy = y + 10
    ix = x0 + 10
    cx = dot(d, ix, iy + 6, C_PURPLE)
    d.text((cx, iy), "Escaneando universo de micro-caps...", fill=C_WHITE, font=F_BOLD)
    iy += 20
    progress_bar(d, ix, iy, x1 - 10, 5, 0.45, C_PURPLE)
    iy += 9
    d.text((ix, iy), "Pares verificados: 462 / 1.017", fill=C_MUTED, font=F_TINY)
    rtext = "Gate G1: vol spike ≥ 2.3x"
    d.text((x1 - 10 - tw(d, rtext, F_TINY), iy), rtext, fill=C_MUTED, font=F_TINY)
    y += 62

    # Strategy summary
    card(d, x0, y, x1, y + 100)
    iy = y + 10
    ix = x0 + 10
    d.text((ix, iy), "CRITÉRIOS DE SELEÇÃO", fill=C_MUTED, font=F_TINY)
    iy += 14
    rows = [
        ("Universo",      "1.017 pares USDT CoinEx  (97.5% com vol < $500K/dia)"),
        ("Gate G1",       "Vol spike ≥ 2.3x média 3 dias  (short-circuit: falha = para)"),
        ("Threshold",     "DISCOVERY ≥ 70pts   MOMENTUM ≥ 60pts"),
        ("Sizing",        "DISCOVERY 0.20%  /  MOMENTUM 0.40%  do capital total"),
        ("Stop / Target", "DISCOVERY -50% / +200%   MOMENTUM -30% / +90%"),
    ]
    for lbl, val in rows:
        d.text((ix, iy), lbl + ":", fill=C_MUTED, font=F_SMALL)
        d.text((ix + 130, iy), val, fill=C_FG, font=F_SMALL)
        iy += 16
    y += 112

    # Recent misses (short-circuit)
    card(d, x0, y, x1, y + 54)
    iy = y + 8
    ix = x0 + 10
    d.text((ix, iy), "Bloqueados no G1 (vol < 2.3x):", fill=C_MUTED, font=F_TINY)
    iy += 13
    misses = [
        ("AIDOGEUSDT", "1.1x", "G1 falhou"),
        ("SDUSDT",     "9.3x", "G4 falhou — sem narrativa"),
        ("XYZUSDT",    "1.8x", "G1 falhou"),
        ("MEMESUSDT",  "2.0x", "G1 falhou"),
    ]
    col_w = (x1 - x0 - 20) // len(misses)
    for i, (name, spike, reason) in enumerate(misses):
        cx = ix + i * col_w
        d.text((cx, iy), name, fill=C_FG, font=F_SMALL)
        d.text((cx, iy + 13), spike, fill=C_RED, font=F_TINY)
        d.text((cx, iy + 23), reason, fill=C_MUTED, font=F_TINY)
    return img

# ── Frame 2 — Spike detected (G1-G3) ─────────────────────────────────────────
def frame_spike():
    img = base()
    d   = ImageDraw.Draw(img)
    y   = y0()
    x0, x1 = PAD, W - PAD

    # Alert card
    rrect(d, (x0, y, x1, y + 34), 6, fill=tint(C_GOLD, 0.12), outline=border_of(C_GOLD, 0.4), width=1)
    iy = y + 8
    ix = x0 + 10
    cx = dot(d, ix, iy + 6, C_GOLD)
    d.text((cx, iy), f"SPIKE DETECTADO:", fill=C_GOLD, font=F_BOLD)
    bx = cx + tw(d, "SPIKE DETECTADO:", F_BOLD) + 10
    d.text((bx, iy), MARKET, fill=C_WHITE, font=F_BOLD)
    bx += tw(d, MARKET, F_BOLD) + 10
    badge(d, bx, iy - 1, f"Listado há {LISTING_D} dias", F_SMALL, tint(C_ORANGE, 0.2), border_of(C_ORANGE, 0.4), C_ORANGE)
    rtext = f"${PRICE:.4f}"
    d.text((x1 - 10 - tw(d, rtext, F_BOLD), iy), rtext, fill=C_WHITE, font=F_BOLD)
    y += 46

    # G1-G3 detail
    for gid, gname, gval, passed, pts, color in GATES[:3]:
        card(d, x0, y, x1, y + 48)
        iy = y + 8
        ix = x0 + 10
        # Gate label
        badge(d, ix, iy, gid, F_BOLD, tint(color, 0.25), border_of(color, 0.5), color)
        d.text((ix + 34, iy + 1), gname, fill=C_FG, font=F_BOLD)
        # Checkmark
        ck = "✓" if passed else "✗"
        ck_c = C_GREEN if passed else C_RED
        d.text((x1 - 60, iy), ck, fill=ck_c, font=F_BOLD)
        pts_str = f"+{pts}pts"
        d.text((x1 - 10 - tw(d, pts_str, F_BOLD), iy), pts_str, fill=ck_c, font=F_BOLD)
        iy += 18
        d.text((ix, iy), gval, fill=C_MUTED, font=F_SMALL)
        iy += 14
        progress_bar(d, ix, iy, x1 - 10, 4, pts / 25, color)
        y += 58

    # Running score
    y += 4
    card(d, x0, y, x1, y + 30)
    iy = y + 8
    ix = x0 + 10
    score_g1_g3 = 25 + 15 + 15
    d.text((ix, iy), "Score parcial G1-G3:", fill=C_MUTED, font=F_BODY)
    d.text((ix + 180, iy), f"{score_g1_g3} / 55", fill=C_WHITE, font=F_BOLD)
    progress_bar(d, ix + 280, iy + 4, x1 - 10, 8, score_g1_g3 / 100, C_GOLD)
    d.text((x1 - 10 - tw(d, "continuando G4-G7...", F_TINY), iy + 2), "continuando G4-G7...", fill=C_MUTED, font=F_TINY)
    return img

# ── Frame 3 — Gates G4-G7 ─────────────────────────────────────────────────────
def frame_gates():
    img = base()
    d   = ImageDraw.Draw(img)
    y   = y0()
    x0, x1 = PAD, W - PAD

    d.text((x0, y), f"{MARKET}  —  Gates G4 a G7", fill=C_MUTED, font=F_SMALL)
    y += 18

    for gid, gname, gval, passed, pts, color in GATES[3:]:
        card(d, x0, y, x1, y + 48)
        iy = y + 8
        ix = x0 + 10
        badge(d, ix, iy, gid, F_BOLD, tint(color, 0.25), border_of(color, 0.5), color)
        d.text((ix + 34, iy + 1), gname, fill=C_FG, font=F_BOLD)
        ck = "✓" if passed else "✗"
        ck_c = C_GREEN if passed else C_RED
        d.text((x1 - 60, iy), ck, fill=ck_c, font=F_BOLD)
        pts_str = f"+{pts}pts"
        d.text((x1 - 10 - tw(d, pts_str, F_BOLD), iy), pts_str, fill=ck_c, font=F_BOLD)
        iy += 18
        d.text((ix, iy), gval, fill=C_MUTED, font=F_SMALL)
        iy += 14
        progress_bar(d, ix, iy, x1 - 10, 4, pts / 25, color)
        y += 58

    # Final score breakdown
    y += 4
    card(d, x0, y, x1, y + 46)
    iy = y + 8
    ix = x0 + 10
    d.text((ix, iy), "Score final:", fill=C_MUTED, font=F_BODY)
    d.text((ix + 95, iy - 4), f"{SCORE}", fill=C_WHITE, font=F_HUGE)
    d.text((ix + 95 + tw(d, f"{SCORE}", F_HUGE) + 6, iy), "/ 100", fill=C_MUTED, font=F_BODY)
    iy += 24
    d.text((ix, iy), f"Threshold DISCOVERY: ≥ 70   →", fill=C_MUTED, font=F_SMALL)
    bx = ix + 210
    badge(d, bx, iy - 2, "APROVADO  ✓", F_BOLD, tint(C_GREEN, 0.25), border_of(C_GREEN, 0.5), C_GREEN)
    progress_bar(d, bx + 130, iy + 2, x1 - 10, 8, SCORE / 100, C_GREEN)
    return img

# ── Frame 4 — DISCOVERY Alert ─────────────────────────────────────────────────
def frame_alert():
    img = base()
    d   = ImageDraw.Draw(img)
    y   = y0()
    x0, x1 = PAD, W - PAD

    # Alert header — green border
    rrect(d, (x0, y, x1, y + 40), 6, fill=tint(C_GREEN, 0.1), outline=border_of(C_GREEN, 0.5), width=2)
    iy = y + 10
    ix = x0 + 10
    cx = dot(d, ix, iy + 8, C_GREEN)
    d.text((cx, iy), f"DISCOVERY ALERT  —  {MARKET}", fill=C_GREEN, font=F_BOLD)
    bx = cx + tw(d, f"DISCOVERY ALERT  —  {MARKET}", F_BOLD) + 10
    score_badge(d, bx, iy, SCORE)
    rtext = f"Listing: dia {LISTING_D}"
    d.text((x1 - 10 - tw(d, rtext, F_SMALL), iy + 2), rtext, fill=C_MUTED, font=F_SMALL)
    iy += 22
    d.text((ix, iy), "AI keyword (Tier 1)   +   CoinGecko rank 203   +   FP-004-SKYAI sim 78%", fill=C_MUTED, font=F_TINY)
    y += 52

    # Price grid
    card(d, x0, y, x1, y + 68)
    iy = y + 8
    ix = x0 + 10
    col_w = (x1 - x0 - 20) // 3
    grid = [
        ("Entrada",         f"${ENTRY:.4f}",         C_FG),
        ("Stop Loss",       f"${STOP:.4f}  (-50%)",  C_RED),
        ("Take Profit 50%", f"${TARGET:.4f}  (+200%)",C_GREEN),
    ]
    for i, (lbl, val, col) in enumerate(grid):
        cx = ix + i * col_w
        d.text((cx, iy), lbl, fill=C_MUTED, font=F_TINY)
        d.text((cx, iy + 14), val, fill=col, font=F_BOLD)
    iy += 38
    separator(d, iy, ix, x1 - 10)
    iy += 8
    d.text((ix, iy), "Moon bag: 50% da posição com trailing 30% do máximo atingido", fill=C_MUTED, font=F_SMALL)
    d.text((ix, iy + 14), f"Prazo máximo: 30 dias  →  saída forçada", fill=C_MUTED, font=F_TINY)
    y += 80

    # Sizing row
    card(d, x0, y, x1, y + 36)
    iy = y + 8
    ix = x0 + 10
    items = [
        ("Modo",     MODE,              C_GOLD),
        ("Sizing",   f"{SIZING:.2f}% capital", C_FG),
        ("Risco",    f"${RISCO_USD:.2f}", C_RED),
        ("Vol spike", f"{SPIKE}x",       C_BLUE),
        ("Mcap",     f"${MCAP/1e6:.1f}M", C_MUTED),
    ]
    col_w = (x1 - x0 - 20) // len(items)
    for i, (lbl, val, col) in enumerate(items):
        cx = ix + i * col_w
        d.text((cx, iy), lbl, fill=C_MUTED, font=F_TINY)
        d.text((cx, iy + 13), val, fill=col, font=F_BOLD)
    y += 48

    # Telegram + journal
    card(d, x0, y, x1, y + 34)
    iy = y + 8
    ix = x0 + 10
    cx = dot(d, ix, iy + 6, C_GREEN)
    d.text((cx, iy), "Telegram alert enviado", fill=C_FG, font=F_SMALL)
    bx = cx + tw(d, "Telegram alert enviado", F_SMALL) + 16
    cx2 = dot(d, bx, iy + 6, C_TEAL)
    d.text((cx2, iy), "Journal registrado", fill=C_FG, font=F_SMALL)
    bx2 = cx2 + tw(d, "Journal registrado", F_SMALL) + 16
    cx3 = dot(d, bx2, iy + 6, C_MUTED)
    d.text((cx3, iy), "gem_signals.csv atualizado", fill=C_MUTED, font=F_SMALL)
    iy += 16
    d.text((ix, iy), f"Validação histórica: SKYAIUSDT entrou em $0.16 → máximo $0.866  (+441%)", fill=C_MUTED, font=F_TINY)
    return img

# ── Build & save ──────────────────────────────────────────────────────────────
frames = [
    (frame_scanning(), 2500),
    (frame_spike(),    3000),
    (frame_gates(),    3000),
    (frame_alert(),    5000),
]

save_gif(frames, OUT)