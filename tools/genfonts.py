#!/usr/bin/env python3
"""Generate Connect IQ bitmap fonts (BMFont .fnt + .png) and the launcher icon.

Run from anywhere:  python3 tools/genfonts.py
Needs Pillow. Re-run after changing sizes or character sets.
"""
import os
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TTF = os.path.join(ROOT, "tools", "ttf")

DIGITS = "0123456789"
MONO_CHARS = (
    " abcdefghijklmnopqrstuvwxyz"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789"
    "[]#-%|_.$~:/+°"
)

# screen size -> (big digit px, mono px, outline stroke px)
SIZES = {
    "454x454": (130, 19, 2),
    "390x390": (112, 16, 2),
}


def load(name, size, weight=None):
    font = ImageFont.truetype(os.path.join(TTF, name), size)
    if weight is not None:
        font.set_variation_by_axes([weight])
    return font


def render(font, ch, outline=0):
    """Return (image, left, top) for one glyph, cropped to its ink."""
    pad = outline + 2
    l, t, r, b = font.getbbox(ch)
    w, h = r + pad * 2 + 4, b + pad * 2 + 4
    img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(img).text((pad, pad), ch, font=font, fill=255)
    if outline:
        fat = Image.new("L", (w, h), 0)
        ImageDraw.Draw(fat).text(
            (pad, pad), ch, font=font, fill=255,
            stroke_width=outline, stroke_fill=255)
        img = ImageChops.subtract(fat, img)
    box = img.getbbox()
    if box is None:
        return None, 0, 0
    return img.crop(box), box[0] - pad, box[1] - pad


def build(out_dir, name, font, chars, outline=0, tight=False, atlas_w=512, bearing=0):
    glyphs = []
    for ch in chars:
        img, left, top = render(font, ch, outline)
        adv = round(font.getlength(ch))
        if img is not None and bearing:
            # Give narrow glyphs (the "1") the same side room as the others,
            # so neighbouring digits never touch.
            ink_left, ink_right = left + outline, adv - (left + img.width - outline)
            grow_left = max(0, bearing - ink_left)
            left += grow_left
            adv += grow_left + max(0, bearing - ink_right)
        glyphs.append((ch, img, left, top, adv))

    inked = [g for g in glyphs if g[1] is not None]
    if tight:
        # Line box hugs the glyphs, so drawText(y) is the top of the digits.
        y0 = min(g[3] for g in inked)
        line_h = max(g[3] + g[1].height for g in inked) - y0
        base = line_h
    else:
        ascent, descent = font.getmetrics()
        y0 = 0
        line_h = ascent + descent
        base = ascent

    x = y = row_h = 0
    placed = []
    for ch, img, left, top, adv in glyphs:
        if img is None:
            placed.append((ch, None, 0, 0, 0, 0, adv))
            continue
        if x + img.width + 1 > atlas_w:
            x, y, row_h = 0, y + row_h + 1, 0
        placed.append((ch, img, x, y, left, top - y0, adv))
        x += img.width + 1
        row_h = max(row_h, img.height)
    atlas_h = y + row_h

    atlas = Image.new("L", (atlas_w, atlas_h), 0)
    lines = [
        f'info face="{name}" size={font.size} bold=0 italic=0 charset="" unicode=1 '
        'stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1 outline=0',
        f'common lineHeight={line_h} base={base} scaleW={atlas_w} scaleH={atlas_h} '
        'pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0',
        f'page id=0 file="{name}.png"',
        f'chars count={len(placed)}',
    ]
    for ch, img, px, py, xo, yo, adv in placed:
        w = h = 0
        if img is not None:
            atlas.paste(img, (px, py))
            w, h = img.size
        lines.append(
            f'char id={ord(ch)} x={px} y={py} width={w} height={h} '
            f'xoffset={xo} yoffset={yo} xadvance={adv} page=0 chnl=15')

    os.makedirs(out_dir, exist_ok=True)
    atlas.save(os.path.join(out_dir, name + ".png"))
    with open(os.path.join(out_dir, name + ".fnt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{out_dir[len(ROOT) + 1:]}/{name}: {atlas_w}x{atlas_h}, line {line_h}px")


def icon():
    size = 65
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    font = load("Orbitron.ttf", 34, 900)
    for dx, col in ((-2, (255, 43, 214)), (2, (0, 229, 255)), (0, (255, 255, 255))):
        d.text((size / 2 + dx, 28), "21", font=font, fill=col, anchor="mm")
    d.rectangle((0, 24, size, 28), fill=(0, 0, 0))
    for dx, col in ((2, (255, 43, 214)), (6, (0, 229, 255)), (4, (255, 255, 255))):
        tmp = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(tmp).text((size / 2 + dx, 28), "21", font=font, fill=col, anchor="mm")
        img.paste(tmp.crop((0, 24, size, 29)), (0, 24), tmp.crop((0, 24, size, 29)))
    mono = load("ShareTechMono.ttf", 15)
    d.text((size / 2, 52), "~$ _", font=mono, fill=(57, 255, 136), anchor="mm")
    out = os.path.join(ROOT, "resources", "drawables", "launcher_icon.png")
    img.save(out)
    print("resources/drawables/launcher_icon.png")


def main():
    for screen, (big_px, mono_px, stroke) in SIZES.items():
        out = os.path.join(ROOT, f"resources-round-{screen}", "fonts")
        big = load("Orbitron.ttf", big_px, 900)
        gap = round(big_px * 0.05)
        build(out, "big", big, DIGITS, tight=True, bearing=gap)
        build(out, "big_outline", big, DIGITS, outline=stroke, tight=True, bearing=gap)
        build(out, "mid", load("Orbitron.ttf", round(big_px * 0.26), 700), DIGITS,
              tight=True, atlas_w=256)
        build(out, "mono", load("ShareTechMono.ttf", mono_px), MONO_CHARS, atlas_w=256)
    icon()


if __name__ == "__main__":
    main()
