"""
Generate the 1024x1024 App Store icon for Woodlands Trail Guide.

Design philosophy — Quiet Water (mirrors the WoodlandsFishing icon spec):
  - One confident silhouette: a winding pathway flowing diagonally up into
    the frame, tapering toward a vanishing point — the trail itself is the
    sole protagonist (analogous to the fish in WoodlandsFishing). No tree,
    no secondary forms — just the path and the forest that holds it.
  - Limited palette: deep forest green at top, warmer pine green at bottom,
    one warm cream tone for the path (the "life" the cool greens cradle)
  - Implied light: a soft upper-right wash suggests morning sun
  - Small dark anchor: the path's own narrow taper edge / shadow provides
    the dark notes the eye lands on — no separate element competing for
    attention
  - No text, no ornament, no rounded corners (Apple's pipeline applies the mask)

Render strategy:
  Supersampled 4x (4096px), then bicubic downsample to 1024px so curves and
  gradients are clean. Pure PIL, no font dependencies.
"""

from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT_PATH = (
    Path(__file__).resolve().parent.parent
    / "WoodlandsTrailGuide" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
)

FINAL = 1024
SS = 4
W = FINAL * SS  # 4096

# Palette
DEEP_FOREST = (20, 45, 33)
MID_FOREST  = (34, 73, 52)
WARM_PINE   = (52, 92, 64)
PATH_CREAM  = (238, 224, 190)
PATH_SHADOW = (170, 156, 122)
TREE_DARK   = (12, 28, 20)
LIGHT_WASH  = (255, 244, 215)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw_vertical_gradient(img: Image.Image):
    px = img.load()
    h = img.height
    for y in range(h):
        t = y / (h - 1)
        if t < 0.5:
            color = lerp(DEEP_FOREST, MID_FOREST, t / 0.5)
        else:
            color = lerp(MID_FOREST, WARM_PINE, (t - 0.5) / 0.5)
        for x in range(img.width):
            px[x, y] = color


def draw_light_wash(img: Image.Image):
    """Radial cream wash anchored upper-right. Stronger than the first pass —
    we want the implied light to actually be visible at thumbnail size."""
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    cx, cy = img.width * 0.84, img.height * 0.16
    rmax = img.width * 0.62
    steps = 80
    for i in range(steps, 0, -1):
        t = i / steps
        r = rmax * t
        alpha = int(115 * (1 - t) ** 2)
        if alpha <= 0:
            continue
        draw.ellipse(
            (cx - r, cy - r, cx + r, cy + r),
            fill=LIGHT_WASH + (alpha,),
        )
    # Soft blur to dissolve the concentric ring artifacts
    overlay = overlay.filter(ImageFilter.GaussianBlur(radius=img.width * 0.012))
    img.alpha_composite(overlay)


def path_centerline(width: int, height: int):
    """A cubic-Bezier-ish curve that enters at the bottom-left, sweeps right,
    then bends back toward the upper-center vanishing point. Returns
    (x, y, t) samples — t=0 at the near end, t=1 at the far end."""
    # Cubic Bezier P0 -> P1 -> P2 -> P3
    p0 = (width * 0.08, height * 1.05)
    p1 = (width * 0.55, height * 0.85)
    p2 = (width * 0.72, height * 0.40)
    p3 = (width * 0.50, height * 0.16)
    samples = 320
    pts = []
    for i in range(samples + 1):
        t = i / samples
        x = ((1 - t) ** 3 * p0[0]
             + 3 * (1 - t) ** 2 * t * p1[0]
             + 3 * (1 - t) * t ** 2 * p2[0]
             + t ** 3 * p3[0])
        y = ((1 - t) ** 3 * p0[1]
             + 3 * (1 - t) ** 2 * t * p1[1]
             + 3 * (1 - t) * t ** 2 * p2[1]
             + t ** 3 * p3[1])
        pts.append((x, y, t))
    return pts


def draw_path(img: Image.Image):
    """Cream pathway as overlapping circles. Radius tapers smoothly from
    near to far. A subtle darker shadow underneath separates it from the
    forest gradient."""
    draw = ImageDraw.Draw(img)
    pts = path_centerline(img.width, img.height)
    base_r = img.width * 0.072
    tip_r = img.width * 0.005
    # Shadow pass first
    for x, y, t in pts:
        # ease-in-out the taper for a calmer curve of radii
        ease = t * t * (3 - 2 * t)
        r = base_r + (tip_r - base_r) * ease
        offset = r * 0.22
        sr = r * 1.12
        draw.ellipse(
            (x - sr, y + offset - sr, x + sr, y + offset + sr),
            fill=PATH_SHADOW,
        )
    # Cream pass
    for x, y, t in pts:
        ease = t * t * (3 - 2 * t)
        r = base_r + (tip_r - base_r) * ease
        draw.ellipse((x - r, y - r, x + r, y + r), fill=PATH_CREAM)


def draw_anchor_pine(img: Image.Image):
    """A single dark pine silhouette near the upper third — the visual
    anchor that lets the eye rest after following the path.

    Drawn with continuous curves (overlapping ellipses for crown layers
    blended into a soft silhouette), not stair-step triangles."""
    w = img.width
    h = img.height
    # Render the tree onto an alpha layer so we can blur the silhouette
    # very slightly for a softer edge.
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    cx = w * 0.26
    base_y = h * 0.42  # where the trunk meets the ground
    tree_h = h * 0.20
    crown_w = w * 0.058

    # Trunk: a thin vertical sliver
    trunk_w = crown_w * 0.18
    draw.rectangle(
        (cx - trunk_w, base_y - tree_h * 0.10,
         cx + trunk_w, base_y + tree_h * 0.06),
        fill=TREE_DARK + (255,),
    )

    # Crown: three soft elliptical tiers that interpenetrate, each tier
    # narrower and higher than the last. Smooth, not stair-step.
    tiers = [
        (0.05, 0.55, 1.00),
        (0.30, 0.45, 0.82),
        (0.55, 0.36, 0.65),
        (0.78, 0.27, 0.48),
    ]
    apex_y = base_y - tree_h
    for cy_frac, height_frac, width_frac in tiers:
        cy = base_y - tree_h * cy_frac - tree_h * 0.05
        th = tree_h * height_frac
        tw = crown_w * width_frac
        draw.ellipse(
            (cx - tw, cy - th * 0.6, cx + tw, cy + th * 0.4),
            fill=TREE_DARK + (255,),
        )
    # Apex point — a small triangular cap
    draw.polygon(
        [
            (cx - crown_w * 0.18, apex_y + tree_h * 0.05),
            (cx + crown_w * 0.18, apex_y + tree_h * 0.05),
            (cx, apex_y - tree_h * 0.05),
        ],
        fill=TREE_DARK + (255,),
    )

    # Whisper of softening on the edges — keeps it grounded as a silhouette
    # rather than a sticker.
    layer = layer.filter(ImageFilter.GaussianBlur(radius=w * 0.0015))
    img.alpha_composite(layer)


def main():
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    img = Image.new("RGB", (W, W), DEEP_FOREST)
    draw_vertical_gradient(img)
    img = img.convert("RGBA")
    draw_light_wash(img)
    draw_path(img)

    img = img.convert("RGB").resize((FINAL, FINAL), Image.LANCZOS)
    img.save(OUT_PATH, "PNG", optimize=True)
    print(f"Wrote {OUT_PATH}  ({OUT_PATH.stat().st_size/1024:.0f} KB)")


if __name__ == "__main__":
    main()
