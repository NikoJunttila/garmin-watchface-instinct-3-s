#!/usr/bin/env python3
"""Faithful static preview of the Nordic face (sanity check; not the CIQ sim).

Renders the ACTUAL bitmap-font glyphs by parsing each resources/fonts/*.fnt and
blitting glyph rects from its .png atlas, positioned with the same lineHeight-box
math Connect IQ uses for TEXT_JUSTIFY_VCENTER. This matches on-device spacing far
better than drawing with a substitute TTF, so layout coordinates can be tuned here
before opening the simulator.

Edit the LAYOUT block below, run `python3 tools/preview_face.py`, inspect
/tmp/nordic_preview.png. The numbers here mirror the constants in NordicView.mc.
"""
import os
import subprocess
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(ROOT, "resources", "fonts")
DRAW = os.path.join(ROOT, "resources", "drawables")
S = 176
SC = 4
WHITE = (255, 255, 255)
GREY = (70, 70, 70)   # reference-only (e.g. the physical sub-window bezel); not drawn by the face

# ---- LAYOUT (mirror of the constants in NordicView.mc) -------------------------
CX = 88
STAT_X_ICON = 22
STAT_X_VAL = 42
STAT_Y1 = 30      # steps (left)
STAT_Y2 = 52      # body battery (left)
STAT_Y3 = 74      # distance (left) — in line with the others
TIME_Y = 108
DATE_Y = 146
STATUS_Y = 167
# --------------------------------------------------------------------------------


def parse_fnt(prefix):
    """Return (atlas_image, common, chars{codepoint:dict})."""
    fnt = os.path.join(FONTS, prefix + ".fnt")
    common = {}
    chars = {}
    png_name = None
    with open(fnt) as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            tag = parts[0]
            kv = {}
            for p in parts[1:]:
                if "=" in p:
                    k, v = p.split("=", 1)
                    kv[k] = v.strip('"')
            if tag == "common":
                common = {k: int(v) for k, v in kv.items() if v.lstrip("-").isdigit()}
            elif tag == "page":
                png_name = kv.get("file")
            elif tag == "char":
                c = {k: int(v) for k, v in kv.items()}
                chars[c["id"]] = c
    atlas = Image.open(os.path.join(FONTS, png_name)).convert("L")
    return atlas, common, chars


def text_width(chars, s):
    return sum(chars[ord(c)]["xadvance"] for c in s if ord(c) in chars)


def draw_text(canvas, font, x, y, s, justify="left"):
    atlas, common, chars = font
    line_h = common["lineHeight"]
    box_top = y - line_h / 2.0            # VCENTER: lineHeight box centered on y
    if justify == "center":
        pen = x - text_width(chars, s) / 2.0
    elif justify == "right":
        pen = x - text_width(chars, s)
    else:
        pen = x
    for ch in s:
        c = chars.get(ord(ch))
        if c is None:
            continue
        if c["width"] > 0 and c["height"] > 0:
            glyph = atlas.crop((c["x"], c["y"], c["x"] + c["width"], c["y"] + c["height"]))
            pos = (int(round(pen + c["xoffset"])), int(round(box_top + c["yoffset"])))
            canvas.paste(Image.new("RGB", glyph.size, WHITE), pos, glyph)
        pen += c["xadvance"]


def load_icon(name, size=18):
    """Rasterize a white SVG icon to an L mask, or return None."""
    src = os.path.join(DRAW, name)
    if not os.path.isfile(src):
        return None
    out = "/tmp/_icon.png"
    try:
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), src, "-o", out],
                       check=True, capture_output=True)
        return Image.open(out).convert("RGBA").split()[3]  # alpha as mask
    except Exception:
        return None


def main():
    hero = parse_fnt("nordic_hero")
    label = parse_fnt("nordic_label")
    small = parse_fnt("nordic_small")

    img = Image.new("RGB", (S, S), (0, 0, 0))
    d = ImageDraw.Draw(img)

    # HR sub-window (top-right): heart + bpm only, no drawn ring. The gray circle is
    # just a REFERENCE for the physical window bezel (not drawn by the face).
    sx, sy, sr = 145, 31, 31   # 144 + HR_DX(1)
    d.ellipse([sx-sr, sy-sr, sx+sr, sy+sr], outline=GREY, width=1)
    heart = load_icon("ic_heart.svg", 14)
    if heart:
        img.paste(Image.new("RGB", heart.size, WHITE), (sx-7, sy-16), heart)
    draw_text(img, label, sx, sy + 8, "80", justify="center")

    # Stats left column (3 rows): icon + value, all left-justified and in line.
    rows = [(STAT_Y1, "ic_steps.svg", "8,431"),
            (STAT_Y2, "ic_body.svg", "64%"),
            (STAT_Y3, "ic_distance.svg", "3.21")]
    for (y, icon, val) in rows:
        ic = load_icon(icon, 18)
        if ic:
            img.paste(Image.new("RGB", ic.size, WHITE), (STAT_X_ICON-9, y-9), ic)
        else:
            d.rectangle([STAT_X_ICON-9, y-9, STAT_X_ICON+9, y+9], outline=(90,90,90))
        draw_text(img, label, STAT_X_VAL, y, val, justify="left")

    # Hero time, date.
    draw_text(img, hero, CX, TIME_Y, "16:26", justify="center")
    draw_text(img, label, CX, DATE_Y, "SAT 27.06", justify="center")

    # Bottom status row: battery cell + "NN%", then sample icons, centered by width.
    BATTERY_W, GAP_PCT, GAP_ICON, ICON_W = 16, 4, 10, 18
    pct, pct_text = 85, "85%"
    pct_w = text_width(small[2], pct_text)
    extras = ["ic_bluetooth.svg"]   # sample active icon
    total = BATTERY_W + GAP_PCT + pct_w + len(extras) * (GAP_ICON + ICON_W)
    x = CX - total / 2
    bx = x + BATTERY_W / 2           # battery cell center
    d.rectangle([bx-8, STATUS_Y-4, bx+6, STATUS_Y+4], outline=WHITE)   # body
    d.rectangle([bx+6, STATUS_Y-2, bx+8, STATUS_Y+2], fill=WHITE)      # nub
    fw = int(10 * pct / 100)
    if fw > 0:
        d.rectangle([bx-6, STATUS_Y-2, bx-6+fw, STATUS_Y+2], fill=WHITE)  # fill
    draw_text(img, small, x + BATTERY_W + GAP_PCT, STATUS_Y, pct_text, justify="left")
    x += BATTERY_W + GAP_PCT + pct_w
    for e in extras:
        x += GAP_ICON
        ic = load_icon(e, ICON_W)
        if ic:
            img.paste(Image.new("RGB", ic.size, WHITE), (int(x + ICON_W/2 - 9), STATUS_Y - 9), ic)
        x += ICON_W

    img.resize((S*SC, S*SC), Image.NEAREST).save("/tmp/nordic_preview.png")
    print("wrote /tmp/nordic_preview.png  (layout: TIME_Y=%d DATE_Y=%d stats=%d,%d)"
          % (TIME_Y, DATE_Y, STAT_Y1, STAT_Y2))


if __name__ == "__main__":
    main()
