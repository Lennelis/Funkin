#!/usr/bin/env python3
"""Builds the editor app's Android icon resources from editor-art/icon.png.

`DataFolderProvider` asks for `R.mipmap.ic_launcher`, so the app has to ship
a real mipmap set rather than the `drawable/icon` lime generates from a lone
image. Run this after changing icon.png; the output is committed.

Requires Pillow.
"""

import os
from collections import deque

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'icon.png')
OUT = os.path.join(HERE, 'android-res')

# Launcher icons are 48dp; an adaptive icon's layers are a 108dp canvas whose
# middle 72dp is all the mask is guaranteed to show.
ICON_DP = 48
LAYER_DP = 108
SAFE_DP = 72
DENSITIES = [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)]

ADAPTIVE_XML = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
'''


def repeat(image, kernel, times):
    for _ in range(times):
        image = image.filter(kernel)
    return image


def largest_blobs(mask, size=600, floor=0.01):
    """The mask's big connected regions, without the flecks of line art."""
    small = mask.resize((size, size), Image.BILINEAR).point(lambda v: 1 if v > 127 else 0)
    pixels = small.tobytes()
    seen = bytearray(size * size)
    blobs = []

    for start in range(size * size):
        if not pixels[start] or seen[start]:
            continue
        queue = deque([start])
        seen[start] = 1
        cells = []
        while queue:
            cell = queue.popleft()
            cells.append(cell)
            y, x = divmod(cell, size)
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < size and 0 <= nx < size:
                    n = ny * size + nx
                    if pixels[n] and not seen[n]:
                        seen[n] = 1
                        queue.append(n)
        blobs.append(cells)

    kept = Image.new('L', (size, size), 0)
    paint = kept.load()
    for cells in blobs:
        if len(cells) >= floor * size * size:
            for cell in cells:
                y, x = divmod(cell, size)
                paint[x, y] = 255
    return kept


def emblem_of(source):
    """The gear and wrench, lifted off the gradient and its faint line art."""
    width = source.size[0]
    dark = source.convert('L').point(lambda v: 255 if v < 140 else 0).convert('L')
    # Opening drops the thin strokes drawn behind the emblem; keeping only the
    # large blobs drops the thick ones.
    opened = repeat(repeat(dark, ImageFilter.MinFilter(9), 5), ImageFilter.MaxFilter(9), 5)
    solid = largest_blobs(opened).resize((width, width), Image.BILINEAR)
    solid = solid.point(lambda v: 255 if v > 127 else 0).convert('L')
    # Grow past the dark shape to pick up the white edging drawn around it.
    alpha = repeat(solid, ImageFilter.MaxFilter(9), 7).filter(ImageFilter.GaussianBlur(2))

    art = source.copy()
    art.putalpha(alpha)
    return art.crop(alpha.getbbox())


def gradient_of(source):
    """The backdrop's diagonal gradient, read off its four corners."""
    width = source.size[0]
    corners = Image.new('RGB', (2, 2))
    for at, pixel in (((0, 0), (0, 0)), ((1, 0), (width - 1, 0)),
                      ((0, 1), (0, width - 1)), ((1, 1), (width - 1, width - 1))):
        corners.putpixel(at, source.getpixel(pixel)[:3])
    return corners


def rounded(image):
    mask = Image.new('L', image.size, 0)
    ImageDraw.Draw(mask).ellipse([0, 0, image.size[0] - 1, image.size[1] - 1], fill=255)
    out = image.convert('RGB')
    out.putalpha(mask)
    return out


def save(image, *parts):
    path = os.path.join(OUT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, optimize=True)


def main():
    source = Image.open(SRC).convert('RGBA')
    emblem = emblem_of(source)
    gradient = gradient_of(source)

    for name, scale in DENSITIES:
        size = int(round(ICON_DP * scale))
        legacy = source.resize((size, size), Image.LANCZOS)
        save(legacy, f'mipmap-{name}', 'ic_launcher.png')
        save(rounded(legacy), f'mipmap-{name}', 'ic_launcher_round.png')

        layer = int(round(LAYER_DP * scale))
        save(gradient.resize((layer, layer), Image.BICUBIC).convert('RGBA'),
             f'drawable-{name}', 'ic_launcher_background.png')

        fitted = emblem.copy()
        fitted.thumbnail((int(round(SAFE_DP * scale)),) * 2, Image.LANCZOS)
        canvas = Image.new('RGBA', (layer, layer), (0, 0, 0, 0))
        canvas.paste(fitted, ((layer - fitted.size[0]) // 2, (layer - fitted.size[1]) // 2), fitted)
        save(canvas, f'drawable-{name}', 'ic_launcher_foreground.png')

    for name in ('ic_launcher.xml', 'ic_launcher_round.xml'):
        path = os.path.join(OUT, 'mipmap-anydpi-v26', name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w') as out:
            out.write(ADAPTIVE_XML)


if __name__ == '__main__':
    main()
