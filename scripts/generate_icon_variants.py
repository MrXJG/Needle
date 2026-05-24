#!/usr/bin/env python3
from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
VARIANTS_DIR = ROOT / "Packaging" / "IconVariants"
ICONSET_NAMES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


VARIANTS = [
    ("01-needle-lens", "针 + 搜索镜", (244, 250, 253), (204, 224, 236), (18, 61, 90), (44, 152, 214)),
    ("02-finder-radar", "Finder 雷达", (239, 248, 255), (197, 224, 244), (20, 84, 126), (55, 161, 216)),
    ("03-minimal-pin", "极简定位针", (248, 249, 247), (219, 226, 220), (42, 64, 61), (74, 143, 124)),
    ("04-dark-precision", "深色精密感", (37, 46, 55), (14, 20, 27), (226, 239, 245), (79, 177, 222)),
    ("05-paper-trail", "纸面轨迹", (250, 247, 239), (226, 218, 201), (73, 62, 49), (198, 126, 60)),
    ("06-orbit-index", "索引轨道", (246, 249, 252), (213, 221, 231), (34, 59, 86), (93, 122, 214)),
]


def gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / max(size - 1, 1)
        color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        draw.line((0, y, size, y), fill=(*color, 255))
    return img


def rounded_square(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    scale = size / 1024
    inset = int(56 * scale)
    radius = int(222 * scale)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((inset, inset + int(18 * scale), size - inset, size - inset + int(18 * scale)), radius=radius, fill=(0, 0, 0, 65))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(max(1, int(22 * scale)))))

    mask = Image.new("L", (size - inset * 2, size - inset * 2), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, mask.width, mask.height), radius=radius, fill=255)
    base = gradient(mask.width, top, bottom)
    img.paste(base, (inset, inset), mask)
    return img


def draw_needle(draw: ImageDraw.ImageDraw, s: float, dark, accent, start=(350, 675), end=(725, 300), width=34):
    sx, sy = start[0] * s, start[1] * s
    ex, ey = end[0] * s, end[1] * s
    draw.line((sx, sy, ex, ey), fill=(*dark, 245), width=max(2, int(width * s)))
    draw.line((sx + 34 * s, sy - 34 * s, ex + 24 * s, ey - 24 * s), fill=(*accent, 235), width=max(2, int(8 * s)))
    draw.polygon([(ex, ey), (ex + 48 * s, ey - 68 * s), (ex - 24 * s, ey - 20 * s)], fill=(*dark, 248))


def variant_01(size, top, bottom, dark, accent):
    s = size / 1024
    img = rounded_square(size, top, bottom)
    d = ImageDraw.Draw(img)
    d.ellipse((264*s, 252*s, 720*s, 708*s), outline=(*dark, 232), width=max(2, int(26*s)))
    draw_needle(d, s, dark, accent)
    d.ellipse((312*s, 622*s, 406*s, 716*s), fill=(245, 250, 252, 255), outline=(*dark, 245), width=max(2, int(12*s)))
    d.ellipse((345*s, 655*s, 373*s, 683*s), fill=(*accent, 245))
    return img


def variant_02(size, top, bottom, dark, accent):
    s = size / 1024
    img = rounded_square(size, top, bottom)
    d = ImageDraw.Draw(img)
    for r, a in [(350, 95), (250, 135), (145, 180)]:
        box = (512*s-r*s, 512*s-r*s, 512*s+r*s, 512*s+r*s)
        d.arc(box, start=205, end=505, fill=(*dark, a), width=max(2, int(18*s)))
    d.line((236*s, 636*s, 760*s, 328*s), fill=(*accent, 235), width=max(2, int(34*s)))
    d.polygon([(760*s, 328*s), (805*s, 262*s), (733*s, 312*s)], fill=(*dark, 245))
    d.rounded_rectangle((265*s, 600*s, 472*s, 685*s), radius=int(42*s), fill=(255, 255, 255, 230), outline=(*dark, 190), width=max(2, int(10*s)))
    return img


def variant_03(size, top, bottom, dark, accent):
    s = size / 1024
    img = rounded_square(size, top, bottom)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((314*s, 236*s, 710*s, 780*s), radius=int(198*s), outline=(*dark, 230), width=max(2, int(34*s)))
    d.ellipse((420*s, 342*s, 604*s, 526*s), fill=(*accent, 235))
    d.line((512*s, 520*s, 512*s, 765*s), fill=(*dark, 230), width=max(2, int(28*s)))
    d.line((392*s, 720*s, 632*s, 720*s), fill=(*dark, 105), width=max(2, int(20*s)))
    return img


def variant_04(size, top, bottom, dark, accent):
    s = size / 1024
    img = rounded_square(size, top, bottom)
    d = ImageDraw.Draw(img)
    for i in range(9):
        x = (260 + i * 62) * s
        d.line((x, 290*s, x, 734*s), fill=(255, 255, 255, 22), width=max(1, int(4*s)))
    d.ellipse((272*s, 268*s, 718*s, 714*s), outline=(*dark, 230), width=max(2, int(24*s)))
    draw_needle(d, s, dark, accent, start=(320, 710), end=(746, 284), width=30)
    d.ellipse((300*s, 690*s, 365*s, 755*s), fill=(*accent, 245))
    return img


def variant_05(size, top, bottom, dark, accent):
    s = size / 1024
    img = rounded_square(size, top, bottom)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((275*s, 240*s, 712*s, 760*s), radius=int(48*s), fill=(255, 253, 247, 225), outline=(*dark, 100), width=max(2, int(10*s)))
    for y in [360, 445, 530, 615]:
        d.line((342*s, y*s, 648*s, y*s), fill=(*dark, 70), width=max(1, int(10*s)))
    d.line((330*s, 700*s, 715*s, 315*s), fill=(*accent, 235), width=max(2, int(34*s)))
    d.polygon([(715*s, 315*s), (765*s, 252*s), (692*s, 292*s)], fill=(*dark, 240))
    return img


def variant_06(size, top, bottom, dark, accent):
    s = size / 1024
    img = rounded_square(size, top, bottom)
    d = ImageDraw.Draw(img)
    for box, start, end, width, alpha in [
        ((230, 326, 790, 698), 192, 530, 24, 205),
        ((306, 242, 690, 782), 22, 350, 18, 125),
    ]:
        d.arc(tuple(v*s for v in box), start=start, end=end, fill=(*dark, alpha), width=max(2, int(width*s)))
    d.ellipse((448*s, 448*s, 576*s, 576*s), fill=(*accent, 240))
    d.ellipse((482*s, 482*s, 542*s, 542*s), fill=(255, 255, 255, 235))
    draw_needle(d, s, dark, accent, start=(340, 670), end=(718, 292), width=24)
    return img


DRAWERS = [variant_01, variant_02, variant_03, variant_04, variant_05, variant_06]


def save_iconset(slug: str, img: Image.Image) -> None:
    iconset = VARIANTS_DIR / f"{slug}.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    for name, size in ICONSET_NAMES.items():
        img.resize((size, size), Image.Resampling.LANCZOS).save(iconset / name)


def make_contact_sheet(items: list[tuple[str, str, Image.Image]]) -> Image.Image:
    thumb = 220
    pad = 34
    label_h = 64
    cols = 3
    rows = math.ceil(len(items) / cols)
    sheet = Image.new("RGBA", (cols * (thumb + pad) + pad, rows * (thumb + label_h + pad) + pad), (246, 247, 249, 255))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/PingFang.ttc", 18)
        small = ImageFont.truetype("/System/Library/Fonts/PingFang.ttc", 13)
    except Exception:
        font = ImageFont.load_default()
        small = ImageFont.load_default()
    for idx, (slug, label, img) in enumerate(items):
        col = idx % cols
        row = idx // cols
        x = pad + col * (thumb + pad)
        y = pad + row * (thumb + label_h + pad)
        sheet.alpha_composite(img.resize((thumb, thumb), Image.Resampling.LANCZOS), (x, y))
        draw.text((x, y + thumb + 10), slug, fill=(30, 35, 40, 255), font=font)
        draw.text((x, y + thumb + 36), label, fill=(92, 98, 105, 255), font=small)
    return sheet


def main() -> None:
    VARIANTS_DIR.mkdir(parents=True, exist_ok=True)
    items = []
    for drawer, (slug, label, top, bottom, dark, accent) in zip(DRAWERS, VARIANTS):
        img = drawer(1024, top, bottom, dark, accent)
        img.save(VARIANTS_DIR / f"{slug}.png")
        save_iconset(slug, img)
        items.append((slug, label, img))
    make_contact_sheet(items).save(VARIANTS_DIR / "contact-sheet.png")


if __name__ == "__main__":
    main()
