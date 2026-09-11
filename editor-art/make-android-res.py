#!/usr/bin/env python3
"""Builds the editor app's Android icon resources from the artwork here.

`DataFolderProvider` asks for `R.mipmap.ic_launcher`, so the app has to ship
a real mipmap set rather than the `drawable/icon` lime generates from a lone
image. Run this after changing the artwork; the output is committed.

Requires Pillow.
"""

import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
FOREGROUND = os.path.join(HERE, 'icon-foreground.png')
BACKGROUND = os.path.join(HERE, 'icon-background.png')
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
    foreground = Image.open(FOREGROUND).convert('RGBA')
    background = Image.open(BACKGROUND).convert('RGBA')

    # The emblem is drawn out to the edges of its own canvas, which is wider
    # than the part of a layer a mask is guaranteed to keep, so it is trimmed
    # to what it actually covers and put back inside the safe middle.
    emblem = foreground.crop(foreground.split()[3].getbbox())

    # The whole icon, for the densities that predate adaptive icons and for
    # anywhere else one flat image is what is wanted.
    flat = background.copy()
    flat.alpha_composite(foreground)

    for name, scale in DENSITIES:
        size = int(round(ICON_DP * scale))
        legacy = flat.resize((size, size), Image.LANCZOS)
        save(legacy, f'mipmap-{name}', 'ic_launcher.png')
        save(rounded(legacy), f'mipmap-{name}', 'ic_launcher_round.png')

        layer = int(round(LAYER_DP * scale))
        save(background.resize((layer, layer), Image.LANCZOS),
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
