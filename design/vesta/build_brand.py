#!/usr/bin/env python3
"""Regenerate every Vesta Cloud brand asset in the fork from one source SVG.

Inputs (this folder):
  vesta-mark-source.svg   the house-and-flame mark, as exported from Inkscape

Outputs: overwrites the upstream Immich asset files in place (same paths and
pixel sizes) so upstream merges keep working, and writes the cleaned masters
to this folder.

Requirements: python3 with Pillow, fonttools and uharfbuzz; node with
playwright + Chromium (used to rasterise SVG); the Inter font (SIL OFL) at
INTER_PATH.

Run from the repository root:  python3 design/vesta/build_brand.py
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

import uharfbuzz as hb
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
INTER_PATH = os.environ.get('INTER_PATH', '/usr/share/fonts/opentype/inter/Inter-SemiBold.otf')

MOBILE = ROOT / 'mobile'
RES = MOBILE / 'android/app/src/main/res'
IOS = MOBILE / 'ios/Runner/Assets.xcassets'
WEB_STATIC = ROOT / 'web/static'
WEB_BRAND = ROOT / 'web/src/lib/assets/vesta'

# Brand palette (from the logo gradient and the vesta-vault-web design tokens)
GRAD_TOP = '#d65400'
GRAD_BOTTOM = '#ffba1c'
INK_LIGHT = '#0a0b0d'  # wordmark "Vesta" on light backgrounds
INK_DARK = '#e6e8eb'  # wordmark "Vesta" on dark backgrounds
ACCENT_LIGHT = '#d65400'  # wordmark "Cloud" on light backgrounds
ACCENT_DARK = '#f07328'  # wordmark "Cloud" on dark backgrounds
SPLASH_BG_LIGHT = '#ffffff'
SPLASH_BG_DARK = '#0a0b0d'

# Mark bounding box in the source path's own coordinates (measured from a render).
MARK_X, MARK_Y, MARK_W, MARK_H = 577.0, 104.0, 378.5, 329.0


def mark_path_d() -> str:
    src = (HERE / 'vesta-mark-source.svg').read_text()
    return re.search(r'id="path15".*?\sd="([^"]+)"', src, re.S).group(1)


D = mark_path_d()


def gradient_def(gid: str) -> str:
    # Same gradient as the Inkscape file, in the path's coordinate space.
    return (
        f'<linearGradient id="{gid}" x1="766.27148" y1="79.217987" x2="766.27148" y2="457.21799" '
        f'gradientUnits="userSpaceOnUse"><stop offset="0.34940916" stop-color="{GRAD_TOP}"/>'
        f'<stop offset="1" stop-color="{GRAD_BOTTOM}"/></linearGradient>'
    )


def mark(cx: float, cy: float, width: float, fill: str | None = None, gid: str = 'vg') -> tuple[str, str]:
    """Return (defs, element) placing the mark centred on (cx, cy) at the given width."""
    s = width / MARK_W
    tx = cx - (MARK_X + MARK_W / 2) * s
    ty = cy - (MARK_Y + MARK_H / 2) * s
    defs = '' if fill else gradient_def(gid)
    paint = fill or f'url(#{gid})'
    return defs, f'<path transform="matrix({s:.6f} 0 0 {s:.6f} {tx:.4f} {ty:.4f})" fill="{paint}" d="{D}"/>'


def svg_doc(w: float, h: float, body: str, defs: str = '', bg: str | None = None) -> str:
    rect = f'<rect width="{w}" height="{h}" fill="{bg}"/>' if bg else ''
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:g}" height="{h:g}" viewBox="0 0 {w:g} {h:g}">'
        f'<defs>{defs}</defs>{rect}{body}</svg>'
    )


# ---------------------------------------------------------------- wordmark

def shape_text(text: str, size: float, tracking_em: float = -0.02) -> tuple[list[tuple[str, float]], float]:
    """Shape `text` with HarfBuzz; return ([(svg path d, x offset)], advance width) at `size` px."""
    blob = hb.Blob.from_file_path(INTER_PATH)
    font = hb.Font(hb.Face(blob))
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf, {'kern': True, 'liga': True})

    tt = TTFont(INTER_PATH)
    glyphs = tt.getGlyphSet()
    order = tt.getGlyphOrder()
    upem = tt['head'].unitsPerEm
    scale = size / upem
    out, x = [], 0.0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        pen = SVGPathPen(glyphs)
        # flip y (font units are y-up), scale to px, baseline at y=0
        glyphs[order[info.codepoint]].draw(TransformPen(pen, (scale, 0, 0, -scale, x + pos.x_offset * scale, 0)))
        d = pen.getCommands()
        if d:
            out.append((d, x))
        x += pos.x_advance * scale + tracking_em * size
    return out, x - tracking_em * size


def wordmark(x: float, baseline: float, size: float, ink: str, accent: str) -> tuple[str, float]:
    """'Vesta Cloud' as outlined paths; returns (svg body, width)."""
    vesta, w1 = shape_text('Vesta ', size)
    cloud, w2 = shape_text('Cloud', size)
    parts = [f'<g transform="translate({x:.3f} {baseline:.3f})" fill="{ink}">']
    parts += [f'<path d="{d}"/>' for d, _ in vesta]
    parts.append(f'</g><g transform="translate({x + w1:.3f} {baseline:.3f})" fill="{accent}">')
    parts += [f'<path d="{d}"/>' for d, _ in cloud]
    parts.append('</g>')
    return ''.join(parts), w1 + w2


CAP = 1490 / 2048  # Inter cap height / em


def inline_logo(height: float, ink: str, accent: str) -> str:
    """Mark + wordmark on one line, sized by height, transparent background."""
    mark_w = height * MARK_W / MARK_H * 0.96
    defs, m = mark(mark_w / 2, height / 2, mark_w)
    size = height * 0.62 / CAP  # cap height = 62% of logo height
    gap = height * 0.22
    baseline = height / 2 + size * CAP / 2
    body, text_w = wordmark(mark_w + gap, baseline, size, ink, accent)
    w = mark_w + gap + text_w + height * 0.02
    return svg_doc(round(w, 2), height, m + body, defs)


def fit_svg(svg: str, w: float, h: float) -> str:
    """Re-frame an svg document onto a w x h canvas, scaled to fit and centred."""
    vw, vh = (float(v) for v in re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg).groups())
    s = min(w / vw, h / vh)
    inner = re.sub(r'^<svg[^>]*>|</svg>$', '', svg)
    tx, ty = (w - vw * s) / 2, (h - vh * s) / 2
    return svg_doc(w, h, f'<g transform="translate({tx:.3f} {ty:.3f}) scale({s:.6f})">{inner}</g>')


def text_logo(w: float, h: float, ink: str, accent: str) -> str:
    """Wordmark alone, fitted to the width of an existing canvas and centred."""
    _, natural = wordmark(0, 0, 100, ink, accent)
    size = 100 * (w * 0.96) / natural
    size = min(size, h * 0.9 / CAP)
    _, tw = wordmark(0, 0, size, ink, accent)
    body, _ = wordmark((w - tw) / 2, h / 2 + size * CAP / 2, size, ink, accent)
    return svg_doc(w, h, body)


# ---------------------------------------------------------------- rendering

RENDER_JS = r"""
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const jobs = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const browser = await chromium.launch();
  const page = await browser.newPage();
  for (const job of jobs) {
    await page.setViewportSize({ width: job.w, height: job.h });
    await page.goto('file://' + job.svg);
    await page.screenshot({ path: job.out, omitBackground: true });
  }
  await browser.close();
})();
"""


class Renderer:
    def __init__(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix='vesta-brand-'))
        self.jobs: list[dict] = []
        self.post: list[tuple[Path, bool]] = []

    def add(self, svg: str, out: Path, w: int, h: int, opaque: bool = False) -> None:
        f = self.tmp / f'{len(self.jobs)}.svg'
        f.write_text(svg)
        out.parent.mkdir(parents=True, exist_ok=True)
        self.jobs.append({'svg': str(f), 'out': str(out), 'w': w, 'h': h})
        self.post.append((out, opaque))

    def run(self) -> None:
        (self.tmp / 'jobs.json').write_text(json.dumps(self.jobs))
        (self.tmp / 'render.js').write_text(RENDER_JS)
        subprocess.run(['node', str(self.tmp / 'render.js'), str(self.tmp / 'jobs.json')], check=True)
        for out, opaque in self.post:
            im = Image.open(out)
            im = im.convert('RGB') if opaque else im.convert('RGBA')
            im.save(out, optimize=True)


def png_size(p: Path) -> tuple[int, int]:
    return Image.open(p).size


def icon_on_white(n: int, frac: float = 0.70) -> str:
    defs, m = mark(n / 2, n / 2 + n * 0.01, n * frac)
    return svg_doc(n, n, m, defs, bg='#ffffff')


def mark_only(w: int, h: int, frac: float, fill: str | None = None) -> str:
    defs, m = mark(w / 2, h / 2, w * frac, fill)
    return svg_doc(w, h, m, defs)


def one_pixel(path: Path, color: str) -> None:
    Image.new('RGB', (1, 1), color).save(path)


# ---------------------------------------------------------------- Android vector drawables

def android_vector(mono: bool) -> str:
    # 108dp adaptive-icon canvas; the mark stays inside the 66dp safe circle.
    s = 48 / MARK_W
    tx = 54 - (MARK_X + MARK_W / 2) * s
    ty = 54 - (MARK_Y + MARK_H / 2) * s
    if mono:
        fill = 'android:fillColor="#FFFFFFFF"'
        grad = ''
    else:
        fill = ''
        grad = (
            '\n      <aapt:attr name="android:fillColor">\n'
            '        <gradient android:type="linear" android:startX="766.27" android:startY="79.22"'
            ' android:endX="766.27" android:endY="457.22">\n'
            f'          <item android:offset="0.3494" android:color="#FF{GRAD_TOP[1:].upper()}"/>\n'
            f'          <item android:offset="1" android:color="#FF{GRAD_BOTTOM[1:].upper()}"/>\n'
            '        </gradient>\n      </aapt:attr>\n    '
        )
    d = re.sub(r'\s+', ' ', D).strip()
    # Write exponent numbers (e.g. -4.8e-4) as plain decimals for Android's path parser
    d = re.sub(r'-?\d*\.?\d+e[-+]?\d+', lambda m: f'{float(m.group(0)):.6f}', d)
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Generated by design/vesta/build_brand.py. Do not edit by hand. -->\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '  xmlns:aapt="http://schemas.android.com/aapt"\n'
        '  android:width="108dp"\n  android:height="108dp"\n'
        '  android:viewportWidth="108"\n  android:viewportHeight="108">\n'
        f'  <group android:scaleX="{s:.6f}" android:scaleY="{s:.6f}"'
        f' android:translateX="{tx:.4f}" android:translateY="{ty:.4f}">\n'
        f'    <path {fill}\n      android:pathData="{d}">{grad}</path>\n'
        '  </group>\n</vector>\n'
    )


# ---------------------------------------------------------------- main

def main() -> None:
    r = Renderer()

    # Masters kept in design/vesta for reuse (site, store listings, docs)
    defs, m = mark(MARK_W / 2, MARK_H / 2, MARK_W)
    (HERE / 'vesta-mark.svg').write_text(svg_doc(MARK_W, MARK_H, m, defs))
    _, m = mark(MARK_W / 2, MARK_H / 2, MARK_W, fill='#000000')
    (HERE / 'vesta-mark-mono.svg').write_text(svg_doc(MARK_W, MARK_H, m))
    (HERE / 'vesta-logo-inline-light.svg').write_text(inline_logo(266.25, INK_LIGHT, ACCENT_LIGHT))
    (HERE / 'vesta-logo-inline-dark.svg').write_text(inline_logo(266.25, INK_DARK, ACCENT_DARK))
    r.add(icon_on_white(1024), HERE / 'vesta-app-icon-1024.png', 1024, 1024, opaque=True)

    # ---- mobile/assets (same file names as upstream so code references stay untouched)
    a = MOBILE / 'assets'
    w, h = png_size(a / 'immich-logo.png')
    r.add(mark_only(w, h, 0.97), a / 'immich-logo.png', w, h)
    w, h = png_size(a / 'immich-logo-w-bg.png')
    defs, m = mark(w / 2, h / 2, w * 0.70)
    r.add(svg_doc(w, h, m, defs, bg='#ffffff'), a / 'immich-logo-w-bg.png', w, h)
    n, _ = png_size(a / 'immich-logo-w-bg-android.png')
    r.add(icon_on_white(n), a / 'immich-logo-w-bg-android.png', n, n)
    n, _ = png_size(a / 'immich-logo-android-adaptive-icon.png')
    r.add(mark_only(n, n, 0.48), a / 'immich-logo-android-adaptive-icon.png', n, n)
    n, _ = png_size(a / 'immich-splash.png')
    r.add(mark_only(n, n, 0.97), a / 'immich-splash.png', n, n)
    n, _ = png_size(a / 'immich-splash-android12.png')
    r.add(mark_only(n, n, 0.45), a / 'immich-splash-android12.png', n, n)
    for theme, ink, accent in (('light', INK_LIGHT, ACCENT_LIGHT), ('dark', INK_DARK, ACCENT_DARK)):
        svg = inline_logo(266.25, ink, accent)
        (a / f'immich-logo-inline-{theme}.svg').write_text(svg)
        # Keep the upstream canvas size (a mobile test decodes this file and checks its aspect ratio)
        w, h = png_size(a / f'immich-logo-inline-{theme}.png')
        r.add(fit_svg(inline_logo(266.25, ink, accent), w, h), a / f'immich-logo-inline-{theme}.png', w, h)
        w, h = png_size(a / f'immich-text-{theme}.png')
        r.add(text_logo(w, h, ink, accent), a / f'immich-text-{theme}.png', w, h)

    # ---- Android launcher, adaptive, notification and splash resources
    for dpi, n in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
        r.add(icon_on_white(n), RES / f'mipmap-{dpi}/ic_launcher.png', n, n)
    (RES / 'drawable/ic_launcher_foreground.xml').write_text(android_vector(mono=False))
    (RES / 'drawable/ic_launcher_monochrome.xml').write_text(android_vector(mono=True))
    for p in sorted(RES.glob('drawable*/notification_icon.png')):
        n, _ = png_size(p)
        r.add(mark_only(n, n, 0.92, fill='#ffffff'), p, n, n)
    for p in sorted(RES.glob('drawable*/splash.png')):
        n, _ = png_size(p)
        r.add(mark_only(n, n, 0.97), p, n, n)
    for p in sorted(RES.glob('drawable*/android12splash.png')):
        n, _ = png_size(p)
        r.add(mark_only(n, n, 0.45), p, n, n)
    for p in RES.glob('drawable*/background.png'):
        one_pixel(p, SPLASH_BG_DARK if 'night' in p.parent.name else SPLASH_BG_LIGHT)

    # ---- iOS app icon (opaque) and launch image
    for p in sorted((IOS / 'AppIcon.appiconset').glob('*.png')):
        n, _ = png_size(p)
        r.add(icon_on_white(n), p, n, n, opaque=True)
    for p in sorted((IOS / 'LaunchImage.imageset').glob('*.png')):
        n, _ = png_size(p)
        r.add(mark_only(n, n, 0.97), p, n, n)
    one_pixel(IOS / 'LaunchBackground.imageset/background.png', SPLASH_BG_LIGHT)
    one_pixel(IOS / 'LaunchBackground.imageset/darkbackground.png', SPLASH_BG_DARK)

    # ---- Web: favicons, touch icon, installable-app icons, in-app logos
    for name in ('favicon-16', 'favicon-32', 'favicon-48', 'favicon-96', 'favicon-144', 'favicon'):
        p = WEB_STATIC / f'{name}.png'
        n, _ = png_size(p)
        r.add(mark_only(n, n, 0.96), p, n, n)
    r.add(icon_on_white(180), WEB_STATIC / 'apple-icon-180.png', 180, 180)
    for n in (192, 512):  # maskable: keep the mark inside the 80% safe circle
        r.add(icon_on_white(n, 0.56), WEB_STATIC / f'manifest-icon-{n}.maskable.png', n, n)
    WEB_BRAND.mkdir(parents=True, exist_ok=True)
    (WEB_BRAND / 'vesta-mark.svg').write_text((HERE / 'vesta-mark.svg').read_text())
    (WEB_BRAND / 'vesta-logo-inline-light.svg').write_text((HERE / 'vesta-logo-inline-light.svg').read_text())
    (WEB_BRAND / 'vesta-logo-inline-dark.svg').write_text((HERE / 'vesta-logo-inline-dark.svg').read_text())

    r.run()

    # favicon.ico (48, 32, 16) from the rendered PNGs
    ico = Image.open(WEB_STATIC / 'favicon-48.png')
    ico.save(WEB_STATIC / 'favicon.ico', sizes=[(48, 48), (32, 32), (16, 16)])
    print(f'rendered {len(r.jobs)} images')


if __name__ == '__main__':
    main()
