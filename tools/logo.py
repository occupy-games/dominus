#!/usr/bin/env python3
"""Lay out the startup branding and convert the supplied logo to a macOS icon."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def build_splash():
    # Godot's boot splash precedes the scene tree, so its UI text must be baked
    # into the boot image. Reuse the supplied logo and the game's existing font.
    from PIL import Image, ImageDraw, ImageFont

    original = ROOT / 'game/assets/dominus.png'
    font_path = ROOT / 'game/assets/fonts/RobotoCondensed-Regular.ttf'
    target = ROOT / 'game/assets/dominus-splash.png'
    splash = Image.new('RGBA', (1000, 680), 'white')
    logo = Image.open(original).convert('RGBA')
    logo.thumbnail((560, 560), Image.Resampling.LANCZOS)
    splash.alpha_composite(logo, ((1000 - logo.width) // 2, 8))
    draw = ImageDraw.Draw(splash)
    font = ImageFont.truetype(str(font_path), 84)
    draw.text((500, 588), 'Dominus', font=font, anchor='mm', fill='#354452')
    splash.convert('RGB').save(target)
    provenance = {
        'logo': original.name,
        'logo_sha256': hashlib.sha256(original.read_bytes()).hexdigest(),
        'font': 'fonts/' + font_path.name,
        'font_sha256': hashlib.sha256(font_path.read_bytes()).hexdigest(),
        'font_provenance': 'fonts/provenance.json',
        'text': 'Dominus',
        'conversion': 'Startup UI layout: supplied logo and existing game font on white.',
        'output': target.name,
        'output_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
    }
    target.with_suffix('.json').write_text(json.dumps(provenance, indent=2) + '\n')


def build():
    original = ROOT / 'game/assets/dominus.png'
    target = ROOT / 'game/assets/dominus.icns'
    with tempfile.TemporaryDirectory(prefix='dominus-logo-') as temporary:
        iconset = Path(temporary) / 'Dominus.iconset'
        iconset.mkdir()
        for size in [16, 32, 128, 256, 512]:
            for scale in [1, 2]:
                name = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
                subprocess.run(['sips', '-z', str(size*scale), str(size*scale), str(original),
                                '--out', str(iconset / name)], check=True, capture_output=True)
        subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(target)], check=True)
    provenance = {'source': 'dominus.png', 'source_sha256': hashlib.sha256(original.read_bytes()).hexdigest(),
                  'authorization': 'User explicitly supplied this logo for Dominus branding, game icon and start buttons on 2026-11-09.',
                  'conversion': 'sips resizes to standard macOS icon dimensions; iconutil packages unchanged artwork and transparency.',
                  'native_icon': 'dominus.icns', 'native_icon_sha256': hashlib.sha256(target.read_bytes()).hexdigest()}
    (target.parent / 'dominus-logo.json').write_text(json.dumps(provenance, indent=2)+'\n')


if __name__ == '__main__':
    build()
    build_splash()
