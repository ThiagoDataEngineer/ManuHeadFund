"""Shared utilities for CoinEx AI Agent GIF generation."""
from PIL import Image, ImageDraw, ImageFont
import os

ROOT     = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOCS_DIR = os.path.join(ROOT, "docs")
os.makedirs(DOCS_DIR, exist_ok=True)

W        = 680
HEADER_H = 54
PAD      = 16

# ── VS Code dark theme ────────────────────────────────────────────────────────
C_BG     = (30,  30,  30)
C_CARD   = (37,  37,  38)
C_BORDER = (62,  62,  66)
C_FG     = (204, 204, 204)
C_MUTED  = (107, 107, 107)
C_WHITE  = (255, 255, 255)
C_GREEN  = ( 34, 197,  94)
C_RED    = (239,  68,  68)
C_ORANGE = (245, 158,  11)
C_BLUE   = ( 59, 130, 246)
C_PURPLE = (124,  58, 237)
C_PURP_L = (168,  85, 247)
C_TEAL   = ( 20, 184, 166)
C_GOLD   = (234, 179,   8)

def tint(c, alpha=0.15):
    """Dark tint of color c — for badge backgrounds."""
    return tuple(int(C_BG[i] * (1 - alpha) + c[i] * alpha) for i in range(3))

def border_of(c, alpha=0.35):
    return tuple(int(C_BG[i] * (1 - alpha) + c[i] * alpha) for i in range(3))

# ── Font loading ──────────────────────────────────────────────────────────────
def _font(name, size):
    for p in [
        f"C:/Windows/Fonts/{name}.ttf",
        f"C:/Windows/Fonts/{name.lower()}.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()

def _mono(size):
    for p in [
        "C:/Windows/Fonts/consola.ttf",
        "C:/Windows/Fonts/cour.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    ]:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()

F_TITLE = _font("segoeuib", 13)
F_BOLD  = _font("segoeuib", 11)
F_BODY  = _font("segoeui",  11)
F_SMALL = _font("segoeui",  10)
F_TINY  = _font("segoeui",   9)
F_MONO  = _mono(10)
F_BIG   = _font("segoeuib", 16)
F_HUGE  = _font("segoeuib", 22)

# ── Primitive helpers ─────────────────────────────────────────────────────────
def tw(d, text, font):
    bb = d.textbbox((0, 0), text, font=font)
    return bb[2] - bb[0]

def th(d, text, font):
    bb = d.textbbox((0, 0), text, font=font)
    return bb[3] - bb[1]

def rrect(d, xy, r, fill=None, outline=None, width=1):
    d.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)

def centered(d, text, font, color, box):
    x0, y0, x1, y1 = box
    d.text(
        (x0 + (x1 - x0 - tw(d, text, font)) // 2,
         y0 + (y1 - y0 - th(d, text, font)) // 2),
        text, fill=color, font=font,
    )

def dot(d, x, cy, color, r=4):
    """Draw status dot at (x, cy) and return new x cursor."""
    d.ellipse((x, cy - r, x + r * 2, cy + r), fill=color)
    return x + r * 2 + 7

def progress_bar(d, x0, y, x1, h, pct, fill=C_PURPLE):
    rrect(d, (x0, y, x1, y + h), 2, fill=(33, 38, 45))
    fx1 = int(x0 + (x1 - x0) * max(0.0, min(1.0, pct)))
    if fx1 > x0:
        rrect(d, (x0, y, fx1, y + h), 2, fill=fill)

def badge(d, x, y, text, font, bg, bd, fg):
    """Draw inline pill badge, return its width."""
    bw = tw(d, text, font) + 14
    bh = th(d, text, font) + 6
    rrect(d, (x, y, x + bw, y + bh), 4, fill=bg, outline=bd, width=1)
    d.text((x + 7, y + 3), text, fill=fg, font=font)
    return bw

def signal_badge(d, x, y, text, color):
    """Colored signal badge (LONG / SHORT / BULLISH / etc.)."""
    return badge(d, x, y, text, F_BOLD, tint(color, 0.25), border_of(color, 0.5), color)

def score_badge(d, x, y, score):
    color = C_GREEN if score >= 65 else (C_ORANGE if score >= 45 else C_RED)
    return badge(d, x, y, f"{score}", F_BOLD, tint(color, 0.2), border_of(color, 0.4), color)

def separator(d, y, x0=PAD, x1=None):
    if x1 is None:
        x1 = W - PAD
    d.line([(x0, y), (x1, y)], fill=(50, 50, 55), width=1)

# ── Canvas and header ─────────────────────────────────────────────────────────
def make_canvas(H):
    return Image.new("RGB", (W, H), C_BG)

def draw_header(img, title, subtitle, right_text=None):
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, HEADER_H), fill=C_CARD)
    d.line([(0, HEADER_H), (W, HEADER_H)], fill=C_BORDER, width=1)
    cy = HEADER_H // 2
    cx = dot(d, PAD, cy, C_GREEN)
    d.text((cx, cy - th(d, title, F_TITLE) // 2), title, fill=C_WHITE, font=F_TITLE)
    tx = cx + tw(d, title, F_TITLE) + 12
    d.text((tx, cy - th(d, subtitle, F_SMALL) // 2 + 1), subtitle, fill=C_MUTED, font=F_SMALL)
    if right_text:
        rw = tw(d, right_text, F_SMALL)
        d.text((W - PAD - rw, cy - th(d, right_text, F_SMALL) // 2), right_text, fill=C_MUTED, font=F_SMALL)

def card(d, x0, y0, x1, y1, r=6, fill=C_CARD, outline=C_BORDER):
    rrect(d, (x0, y0, x1, y1), r, fill=fill, outline=outline, width=1)

# ── Save GIF ──────────────────────────────────────────────────────────────────
def save_gif(frames_durations, out_path, colors=128):
    gif_frames, gif_durations = [], []
    for img, dur in frames_durations:
        gif_frames.append(img.convert("P", palette=Image.Palette.ADAPTIVE, colors=colors))
        gif_durations.append(dur)
    gif_frames[0].save(
        out_path,
        save_all=True,
        append_images=gif_frames[1:],
        loop=0,
        duration=gif_durations,
        disposal=2,
        optimize=False,
    )
    kb = os.path.getsize(out_path) // 1024
    print(f"OK  {os.path.basename(out_path)}  ({kb} KB, {len(gif_frames)} frames)")
