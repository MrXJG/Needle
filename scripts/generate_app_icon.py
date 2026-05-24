#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "Packaging" / "AppIcon.iconset"


SIZES = {
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


def rounded_rect_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def draw_icon(size: int) -> Image.Image:
    scale = size / 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    inset = int(56 * scale)
    radius = int(222 * scale)
    shadow_draw.rounded_rectangle(
        (inset, inset + int(18 * scale), size - inset, size - inset + int(18 * scale)),
        radius=radius,
        fill=(0, 0, 0, 70),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(22 * scale)))
    image.alpha_composite(shadow)

    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    base_mask = rounded_rect_mask(size - inset * 2, radius)
    base_gradient = Image.new("RGBA", (size - inset * 2, size - inset * 2), (0, 0, 0, 0))
    gradient_draw = ImageDraw.Draw(base_gradient)
    h = base_gradient.height
    for y in range(h):
        t = y / max(h - 1, 1)
        r = int(244 * (1 - t) + 207 * t)
        g = int(250 * (1 - t) + 225 * t)
        b = int(253 * (1 - t) + 237 * t)
        gradient_draw.line((0, y, base_gradient.width, y), fill=(r, g, b, 255))
    base.alpha_composite(base_gradient, (inset, inset))
    base.putalpha(Image.composite(base.getchannel("A"), Image.new("L", (size, size), 0), Image.new("L", (size, size), 255)))
    masked_base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    masked_base.paste(base_gradient, (inset, inset), base_mask)
    image.alpha_composite(masked_base)

    draw = ImageDraw.Draw(image)
    stroke = int(26 * scale)
    lens_box = (
        int(264 * scale),
        int(252 * scale),
        int(720 * scale),
        int(708 * scale),
    )
    draw.ellipse(lens_box, outline=(36, 74, 105, 232), width=stroke)

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.line(
        (
            int(356 * scale),
            int(662 * scale),
            int(694 * scale),
            int(324 * scale),
        ),
        fill=(35, 132, 196, 105),
        width=int(54 * scale),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(int(18 * scale)))
    image.alpha_composite(glow)

    needle_width = int(34 * scale)
    draw.line(
        (
            int(352 * scale),
            int(668 * scale),
            int(704 * scale),
            int(316 * scale),
        ),
        fill=(12, 50, 76, 245),
        width=needle_width,
    )
    draw.line(
        (
            int(384 * scale),
            int(636 * scale),
            int(728 * scale),
            int(292 * scale),
        ),
        fill=(111, 196, 232, 235),
        width=max(2, int(8 * scale)),
    )

    tip = [
        (int(724 * scale), int(294 * scale)),
        (int(762 * scale), int(236 * scale)),
        (int(704 * scale), int(274 * scale)),
    ]
    draw.polygon(tip, fill=(10, 44, 68, 248))

    eye_box = (
        int(312 * scale),
        int(622 * scale),
        int(406 * scale),
        int(716 * scale),
    )
    draw.ellipse(eye_box, fill=(245, 250, 252, 255), outline=(14, 56, 84, 245), width=max(2, int(12 * scale)))
    draw.ellipse(
        (
            int(345 * scale),
            int(655 * scale),
            int(373 * scale),
            int(683 * scale),
        ),
        fill=(35, 132, 196, 245),
    )

    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.rounded_rectangle(
        (
            inset + int(26 * scale),
            inset + int(20 * scale),
            size - inset - int(26 * scale),
            inset + int(238 * scale),
        ),
        radius=int(128 * scale),
        fill=(255, 255, 255, 58),
    )
    image.alpha_composite(highlight)

    return image


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    master = draw_icon(1024)
    for name, size in SIZES.items():
        resized = master.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(ICONSET / name)


if __name__ == "__main__":
    main()
