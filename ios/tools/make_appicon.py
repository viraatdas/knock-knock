#!/usr/bin/env python3
"""Knock Knock app icon — two overlapping speech bubbles "knocking" into each
other, with a cream heart cut into the overlap. Warm palette: eggshell
ground, espresso bubble, terracotta bubble, cream heart.
Writes ios/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png,
web/public/apple-touch-icon.png (180x180), and web/public/icon-512.png.

Renders at 4x supersampling then downsamples with LANCZOS. The heart is
built as ONE anti-aliased filled polygon (sampled from a parametric heart
curve) rather than a union of separately-drawn ellipses + triangle, so
there is no interior seam where the pieces used to meet. Speech-bubble
tails are rounded triangles (sharp triangle mask, blurred, then
re-thresholded) instead of hard-cornered polygons.
"""
import math

from PIL import Image, ImageDraw, ImageFilter

# Palette (matches Theme.swift: eggshell ground, espresso ink, terracotta accent)
EGGSHELL = (250, 246, 239)
EGGSHELL_DEEP = (241, 231, 214)
ESPRESSO = (42, 33, 27)
TERRACOTTA = (212, 105, 79)
CREAM = (250, 246, 239)

SIZE = 1024
SS = 4  # supersample factor
BIG = SIZE * SS


def rounded_triangle_mask(size, points, blur_radius):
    """Return an "L" mask of a triangle with softened (rounded) corners.

    Drawn sharp at full opacity, blurred, then re-thresholded at the
    midpoint. Blurring a hard-edged shape and cutting it back at 50%
    coverage rounds every convex corner uniformly without changing the
    shape's overall extent, and produces a single clean alpha edge (no
    double anti-aliased boundaries to create seams).
    """
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.polygon(points, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(blur_radius))
    mask = mask.point(lambda v: 255 if v >= 128 else 0)
    return mask


def make_speech_bubble(w, h, radius, tail_size, tail_side="left"):
    """Return an RGBA image of a rounded-rect speech bubble with a small
    rounded-triangle tail pointing down-out on the given side.

    The rect and the tail are combined on a single alpha mask using
    "lighter" (max) compositing rather than drawing two independently
    anti-aliased colored shapes on top of each other, so there is no
    hairline seam where their edges meet.
    """
    pad = tail_size + 4
    size = (w + pad * 2, h + pad * 2)
    x0, y0 = pad, pad
    x1, y1 = pad + w, pad + h

    body_mask = Image.new("L", size, 0)
    ImageDraw.Draw(body_mask).rounded_rectangle(
        [x0, y0, x1, y1], radius=radius, fill=255
    )

    if tail_side == "left":
        tx = x0 + w * 0.22
        pts = [
            (tx, y1 - h * 0.06),
            (tx - tail_size * 0.9, y1 + tail_size),
            (tx + tail_size * 0.85, y1 - h * 0.02),
        ]
    else:
        tx = x1 - w * 0.22
        pts = [
            (tx, y1 - h * 0.06),
            (tx + tail_size * 0.9, y1 + tail_size),
            (tx - tail_size * 0.85, y1 - h * 0.02),
        ]
    tail_mask = rounded_triangle_mask(size, pts, blur_radius=tail_size * 0.16)

    from PIL import ImageChops

    combined = ImageChops.lighter(body_mask, tail_mask)

    img = Image.new("RGBA", size, (0, 0, 0, 0))
    solid = Image.new("RGBA", size, (255, 255, 255, 255))
    solid.putalpha(combined)
    img = Image.alpha_composite(img, solid)
    return img


def vertical_gradient_tint(img, top_color, bottom_color):
    w, h = img.size
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(top_color[0] + (bottom_color[0] - top_color[0]) * t)
        g = int(top_color[1] + (bottom_color[1] - top_color[1]) * t)
        b = int(top_color[2] + (bottom_color[2] - top_color[2]) * t)
        grad.putpixel((0, y), (r, g, b))
    grad = grad.resize((w, h))
    grad = grad.convert("RGBA")
    grad.putalpha(img.split()[3])
    return grad


def heart_path_points(n=240):
    """Sample a classic parametric heart curve, normalized to a unit box
    centered at the origin (x in roughly [-0.5, 0.5], y scaled to match).
    """
    xs, ys = [], []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        xs.append(x)
        ys.append(-y)  # flip: image y grows downward, heart tip should point down
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    cx0 = (min_x + max_x) / 2
    cy0 = (min_y + max_y) / 2
    scale = 1.0 / (max_x - min_x)
    return [((x - cx0) * scale, (y - cy0) * scale) for x, y in zip(xs, ys)]


_HEART_UNIT = heart_path_points()


def draw_heart(canvas, cx, cy, size, color):
    """Paste a single anti-aliased filled heart onto `canvas`, built from
    ONE polygon path (a parametric heart curve) drawn on its own mask
    layer and composited once — no separate ellipses/triangle to leave a
    seam where they used to join.
    """
    pad = int(size * 0.12) + 2
    dim = int(size) + pad * 2
    mask = Image.new("L", (dim, dim), 0)
    mid = dim / 2
    pts = [(mid + x * size, mid + y * size) for x, y in _HEART_UNIT]
    ImageDraw.Draw(mask).polygon(pts, fill=255)

    solid = Image.new("RGBA", (dim, dim), color + (255,))
    solid.putalpha(mask)

    paste_x = int(cx - dim / 2)
    paste_y = int(cy - dim / 2)
    canvas.paste(solid, (paste_x, paste_y), solid)


def render_icon():
    canvas = Image.new("RGB", (BIG, BIG), EGGSHELL)

    # Subtle vertical gradient ground (eggshell -> deeper eggshell), very soft
    grad = Image.new("RGB", (1, BIG))
    for y in range(BIG):
        t = y / (BIG - 1)
        r = int(EGGSHELL[0] + (EGGSHELL_DEEP[0] - EGGSHELL[0]) * t * 0.55)
        g = int(EGGSHELL[1] + (EGGSHELL_DEEP[1] - EGGSHELL[1]) * t * 0.55)
        b = int(EGGSHELL[2] + (EGGSHELL_DEEP[2] - EGGSHELL[2]) * t * 0.55)
        grad.putpixel((0, y), (r, g, b))
    grad = grad.resize((BIG, BIG))
    canvas.paste(grad, (0, 0))

    # Bubble geometry: two large rounded-rect speech bubbles overlapping in
    # the center, each rotated slightly toward the other (like they're
    # leaning in to "knock").
    bw, bh = int(BIG * 0.60), int(BIG * 0.52)
    radius = int(bh * 0.40)
    tail = int(BIG * 0.10)

    left_bubble = make_speech_bubble(bw, bh, radius, tail, tail_side="left")
    left_bubble = vertical_gradient_tint(left_bubble, ESPRESSO, (30, 23, 18))
    left_bubble = left_bubble.rotate(-10, resample=Image.BICUBIC, expand=True)

    right_bubble = make_speech_bubble(bw, bh, radius, tail, tail_side="right")
    right_bubble = vertical_gradient_tint(right_bubble, TERRACOTTA, (196, 88, 64))
    right_bubble = right_bubble.rotate(10, resample=Image.BICUBIC, expand=True)

    # Position: left bubble sits upper-left-of-center, right bubble sits
    # lower-right-of-center, overlapping in the middle third. Shifted so the
    # combined silhouette is centered in the frame with even margins.
    cx, cy = int(BIG * 0.50), int(BIG * 0.47)

    lw, lh = left_bubble.size
    left_pos = (int(cx - lw * 0.66), int(cy - lh * 0.60))

    rw, rh = right_bubble.size
    right_pos = (int(cx - rw * 0.34), int(cy - rh * 0.40))

    # Paste terracotta bubble first (behind), then espresso bubble in front,
    # so the espresso one visually "knocks" onto the terracotta one and the
    # overlap area is clearly espresso-on-top with a cream heart cut into it.
    canvas.paste(right_bubble, right_pos, right_bubble)
    canvas.paste(left_bubble, left_pos, left_bubble)

    # Heart at the point of contact between the two bubbles' inner edges.
    # Sized up slightly from the original draft (0.19 -> 0.215 of BIG) so it
    # stays legible against the espresso bubble at 60px home-screen size.
    heart_cx = cx + int(BIG * 0.02)
    heart_cy = cy + int(BIG * 0.015)
    heart_size = BIG * 0.215
    draw_heart(canvas, heart_cx, heart_cy, heart_size, CREAM)

    return canvas


def downsample(img, size):
    return img.resize((size, size), Image.LANCZOS)


def main():
    icon = render_icon()

    icon_1024 = downsample(icon, 1024)
    out = "ios/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
    icon_1024.save(out)

    touch_icon = downsample(icon, 180)
    touch_out = "web/public/apple-touch-icon.png"
    touch_icon.save(touch_out)

    icon_512 = downsample(icon, 512)
    icon_512_out = "web/public/icon-512.png"
    icon_512.save(icon_512_out)

    print(f"wrote {out}")
    print(f"wrote {touch_out}")
    print(f"wrote {icon_512_out}")


if __name__ == "__main__":
    main()
