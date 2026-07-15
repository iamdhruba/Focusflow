"""
focusflow/tool/generate_app_icon.py

Render the FocusFlow launcher-icon PNG (1024×1024) so that it visually
matches the BrandLogo widget rendered on the Get Started welcome screen.

Composition
-----------

Layer 1 — diagonal gradient rounded square.

* Fill colour : linear gradient
                AppColors.primary          = #004AC6  (begin: top-left)
                AppColors.primaryContainer = #2563EB  (end:   bottom-right)
                The diagonal matches `AppColors.primaryGradient` from
                `focusflow/lib/core/theme/app_theme.dart`, which declares
                `LinearGradient(begin: topLeft, end: bottomRight)`. We
                project each pixel onto the (TL→BR) direction and sample
                the stops at that t.
* Corner radius: 28 % of side length           (matches `BrandLogo.size * 0.28`).

Layer 2 — Material glyph centered at 53.125 % of side length.

* Source : Flutter SDK's bundled `MaterialIcons-Regular.otf`.
* Glyph  : `Icons.self_improvement_rounded` is `IconData(0xE96F)` in
           Flutter; we resolve the unicode codepoint via `cmap` first,
           then fall back to a `_rounded` suffix search, then to a
           literal name match.
* Tessellation : walk `RecordingPen` output, expanding TrueType
                 quadratic Béziers (with implicit-on-curve midpoint
                 for odd-length `qCurveTo` tails) and cubic Béziers
                 into line segments.
* Colour : white (opaque).
* Antialiasing : painted at 4× (4096×4096) and downsampled with
                 LANCZOS so the icon edges sit softly against the
                 smooth gradient — matching the on-screen rendering
                 rather than chiseled polygon edges.
* Drop shadow from `BrandLogo` is intentionally OMITTED — launcher
  icons need crisp edges and the 32 px blur used at 64 px on-screen
  would smear badly at 1024 px.

Output
------

`focusflow/assets/images/app_icon.png` — the source `flutter_launcher_icons`
repaints into Android's launcher assets.

Run from the repo root::

    python focusflow/tool/generate_app_icon.py
"""

import os
import sys
from typing import List, Optional, Sequence, Tuple

from PIL import Image, ImageDraw
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import RecordingPen


# ── Paths & constants ────────────────────────────────────────────────────────
TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
FLUTTER_ROOT = r"C:\flutter"
DEFAULT_FONT_PATH = os.path.join(
    FLUTTER_ROOT,
    "bin", "cache", "dart-sdk", "bin", "resources",
    "devtools", "assets", "fonts", "MaterialIcons-Regular.otf",
)
ICON_OUT = os.path.normpath(
    os.path.join(TOOL_DIR, "..", "assets", "images", "app_icon.png")
)

# `Icons.self_improvement_rounded` → `IconData(0xE96F)` (Flutter SDK).
# We resolve via cmap first so we never pick the wrong filled/outlined
# variant by accident.
PREFERRED_CP = 0xE96F
GLYPH_NAME_HINT = "self_improvement_rounded"

# BrandLogo defaults: `size: 64, iconSize: 34`, corner radius `size * 0.28`.
SIZE = 1024
ICON_SCALE = 34 / 64
CORNER_RADIUS_FRAC = 0.28
SUPERSAMPLE = 4  # 4× gives 4096² — fast on a one-shot generator, good AA.

# In sync with AppColors.primaryGradient in
# focusflow/lib/core/theme/app_theme.dart.
GRAD_TOP_RGB = 0x00, 0x4A, 0xC6  # AppColors.primary          = #004AC6
GRAD_BOT_RGB = 0x25, 0x63, 0xEB  # AppColors.primaryContainer = #2563EB

WHITE = (255, 255, 255, 255)
TRANSPARENT = (0, 0, 0, 0)


# ── Glyph-name lookup ────────────────────────────────────────────────────────
def _resolve_glyph_name(font: TTFont) -> Optional[str]:
    """Resolve the `self_improvement_rounded` glyph robustly.

    Resolution priority:
      1. cmap lookup against Flutter's known `0xE96F` codepoint.
      2. Exact glyph name `self_improvement_rounded`.
      3. Any glyph name containing `_self_improvement` `rounded`,
         in case the font split names on word boundaries.
      4. Any glyph whose name contains `self_improvement_rounded`.
    """
    glyph_order = set(font.getGlyphOrder())

    # (1) cmap — preference to the canonical Flutter codepoint.
    cmap = font.getBestCmap()
    if cmap and PREFERRED_CP in cmap:
        candidate = cmap[PREFERRED_CP]
        if candidate in glyph_order:
            return candidate

    # (2..4) substring fallbacks, in order of increasing looseness.
    for needle in (
        "self_improvement_rounded",
        "_self_improvement_rounded_",
        "_self_improvement_rounded",
    ):
        for name in font.getGlyphOrder():
            if needle in name:
                return name

    return None


# ── Bézier tessellation ──────────────────────────────────────────────────────
def _tessellate_quadratic(
    p0: Tuple[float, float],
    p1: Tuple[float, float],
    p2: Tuple[float, float],
    samples: int = 32,
) -> List[Tuple[float, float]]:
    """Sample a quadratic Bézier at `samples + 1` evenly spaced t values."""
    return [
        (
            (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0],
            (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1],
        )
        for t in (i / samples for i in range(samples + 1))
    ]


def _tessellate_cubic(
    p0: Tuple[float, float],
    p1: Tuple[float, float],
    p2: Tuple[float, float],
    p3: Tuple[float, float],
    samples: int = 32,
) -> List[Tuple[float, float]]:
    out: List[Tuple[float, float]] = []
    for i in range(samples + 1):
        t = i / samples
        u = 1 - t
        out.append(
            (
                u ** 3 * p0[0]
                + 3 * u ** 2 * t * p1[0]
                + 3 * u * t ** 2 * p2[0]
                + t ** 3 * p3[0],
                u ** 3 * p0[1]
                + 3 * u ** 2 * t * p1[1]
                + 3 * u * t ** 2 * p2[1]
                + t ** 3 * p3[1],
            )
        )
    return out


# ── TrueType outline walk ────────────────────────────────────────────────────
def _extract_outline(font: TTFont, glyph_name: str):
    """Walk the glyph into a list of closed polygons (in glyph units, +y down).

    TrueType semantics we follow:
      * `moveTo(pt)`           — start a subpath at `pt` (on-curve).
      * `lineTo(pt)`           — straight segment to on-curve `pt`.
      * `qCurveTo(*pts)`       — even count: alternating off/on pairs
                                 ending on-curve. Odd count: trailing
                                 off-curve control for an implicit on-
                                 curve endpoint at the midpoint between
                                 the current pen position and that last
                                 off-curve point.
      * `curveTo(*pts)`        — triples of (cp1, cp2, endpoint) on-curve.
      * `closePath`            — close subpath (already made implicit by
                                 the last on-curve point).
      * `endPath`              — we ignore this; TrueType-only hint and
                                 not used by Material icons' static outlines.
    Returns (polys, None) where each poly is a list of (x, y) tuples.
    """
    glyph_set = font.getGlyphSet()
    if glyph_name in glyph_set:
        pen = RecordingPen()
        glyph_set[glyph_name].draw(pen)
    else:
        return None

    polys: List[List[Tuple[float, float]]] = []
    current: List[Tuple[float, float]] = []

    for cmd, args in pen.value:
        if cmd == "moveTo":
            current = [args[0]]
        elif cmd == "lineTo":
            current.append(args[0])
        elif cmd == "qCurveTo":
            start = current[-1]
            pts = list(args)
            if not pts:
                continue
            # Odd-length pts → trailing off-curve for implicit endpoint.
            implicit_end = None
            if len(pts) % 2 == 1:
                last_off = pts[-1]
                pts = pts[:-1]
                implicit_end = (
                    (start[0] + last_off[0]) / 2.0,
                    (start[1] + last_off[1]) / 2.0,
                )
            # Walk the (off, on, off, on …) pairs.
            for i in range(0, len(pts), 2):
                ctrl = pts[i]
                end = pts[i + 1]
                current.extend(_tessellate_quadratic(start, ctrl, end)[1:])
                start = end
            if implicit_end is not None:
                current.append(implicit_end)
        elif cmd == "curveTo":
            start = current[-1]
            for p1, p2, p3 in zip(args[0::3], args[1::3], args[2::3]):
                current.extend(_tessellate_cubic(start, p1, p2, p3)[1:])
                start = p3
        elif cmd == "closePath":
            if current:
                polys.append(current)
            current = []
        # `endPath` is intentionally ignored — see docstring.

    if current:
        polys.append(current)
    return polys


# ── Painting ─────────────────────────────────────────────────────────────────
def _draw_gradient_rounded(
    canvas: Image.Image,
    size: int,
    radius: int,
    top_rgb: Sequence[int],
    bot_rgb: Sequence[int],
) -> None:
    """Diagonal TL→BR gradient inside a rounded-square mask.

    For an `app icon.Painter`'s `LinearGradient(begin, end)` with `begin`
    at `(0, 0)` and `end` at `(S-1, S-1)`, each pixel's progress `t` is
    the projection of its coordinate onto that unit vector::

        t = ((x - 0) * dx + (y - 0) * dy) / (dx*dx + dy*dy)
          = (x + y) / (2 * (S - 1))   for `dx == dy == S - 1`.
    """
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=radius, fill=255
    )

    grad = Image.new("RGB", (size, size))
    px = grad.load()
    denom = 2.0 * (size - 1)
    dr = float(bot_rgb[0] - top_rgb[0])
    dg = float(bot_rgb[1] - top_rgb[1])
    db = float(bot_rgb[2] - top_rgb[2])
    for y in range(size):
        for x in range(size):
            t = (x + y) / denom
            px[x, y] = (
                int(top_rgb[0] + dr * t),
                int(top_rgb[1] + dg * t),
                int(top_rgb[2] + db * t),
            )
    canvas.paste(grad, (0, 0), mask)


def _paint_icon_glyph(
    canvas: Image.Image,
    polys: List[List[Tuple[float, float]]],
    icon_size_px: float,
) -> None:
    """Draw the glyph centred inside `canvas` at `icon_size_px` size."""
    if not polys:
        return
    # Flip TrueType y-axis (origin at font baseline, +y up) to PIL y-axis
    # (origin at top, +y down) so the orientation matches the screen.
    flipped: List[List[Tuple[float, float]]] = [
        [(x, -y) for x, y in contour] for contour in polys
    ]
    xs = [p[0] for c in flipped for p in c]
    ys = [p[1] for c in flipped for p in c]
    bbox_w = max(xs) - min(xs)
    bbox_h = max(ys) - min(ys)
    if bbox_w <= 0 or bbox_h <= 0:
        return
    scale = icon_size_px / max(bbox_w, bbox_h)
    offset_x = (canvas.width - bbox_w * scale) / 2 - min(xs) * scale
    offset_y = (canvas.height - bbox_h * scale) / 2 - min(ys) * scale

    draw = ImageDraw.Draw(canvas)
    for contour in flipped:
        scaled = [(x * scale + offset_x, y * scale + offset_y) for x, y in contour]
        draw.polygon(scaled, fill=WHITE)


# ── Entry point ──────────────────────────────────────────────────────────────
def render(font_path: str = DEFAULT_FONT_PATH, out_path: str = ICON_OUT) -> int:
    if not os.path.exists(font_path):
        print(
            f"[generate_app_icon] MaterialIcons font not found at {font_path}",
            file=sys.stderr,
        )
        return 2

    font = TTFont(font_path)
    glyph_name = _resolve_glyph_name(font)
    if glyph_name is None:
        print(
            f"[generate_app_icon] glyph '{GLYPH_NAME_HINT}' not found in font "
            f"(order preview: {font.getGlyphOrder()[:5]} …)",
            file=sys.stderr,
        )
        return 3

    polys = _extract_outline(font, glyph_name)
    if not polys:
        print(
            f"[generate_app_icon] extracted no contours for '{glyph_name}'",
            file=sys.stderr,
        )
        return 4

    # ── Render at SUPERSAMPLE× for clean AA ──────────────────────────────────
    big = SUPERSAMPLE * SIZE
    canvas = Image.new("RGBA", (big, big), TRANSPARENT)
    _draw_gradient_rounded(
        canvas, big,
        int(big * CORNER_RADIUS_FRAC),
        GRAD_TOP_RGB, GRAD_BOT_RGB,
    )
    _paint_icon_glyph(canvas, polys, big * ICON_SCALE)

    # Downsample to final size with LANCZOS for smooth edges.
    final = canvas.resize((SIZE, SIZE), Image.LANCZOS)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    final.save(out_path, "PNG")
    size = os.path.getsize(out_path)
    print(
        f"[generate_app_icon] wrote {out_path} "
        f"({size} bytes / {size / 1024:.1f} KB / mode={final.mode}) "
        f"glyph='{glyph_name}' supersample={SUPERSAMPLE}×"
    )
    return 0


if __name__ == "__main__":
    sys.exit(render())
