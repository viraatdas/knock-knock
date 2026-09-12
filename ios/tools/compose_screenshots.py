#!/usr/bin/env python3
"""Compose captioned App Store screenshots for Knock Knock - 5 Minute Dates.

Takes one raw simulator screenshot per scene (produced by
capture_screenshots.sh) and composites it below a caption band: eggshell
ground (#FAF6EF, the app's own background), one short line of light espresso
text (#2A211B) per scene, and the raw shot placed full-bleed underneath
(scaled to cover and center-cropped, never distorted or letterboxed).

Writes the App Store 6.9-inch size (1320x2868) plus 6.5-inch (1242x2688)
resized variants, named 01..06_APP_IPHONE_6_9_<scene>.png /
01..06_APP_IPHONE_65_<scene>.png in scene order.

Usage:
    python3 compose_screenshots.py [--raw-dir DIR] [--out-dir DIR]

Defaults:
    --raw-dir  /tmp/knock-shots/raw          (one <scene>.png per scene below)
    --out-dir  ios/fastlane/screenshots/en-US (resolved relative to this file)
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_RAW = "/tmp/knock-shots/raw"
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, "..", "fastlane", "screenshots", "en-US"))

W69, H69 = 1320, 2868   # App Store 6.9-inch (iPhone 17 Pro Max class)
W65, H65 = 1242, 2688   # 6.5-inch variant, a straight resize of the 6.9 canvas
BAND_H = 360            # caption band height

EGGSHELL = (0xFA, 0xF6, 0xEF)
ESPRESSO = (0x2A, 0x21, 0x1B)

# Preferred first; each entry is (font path, face index within the file).
FONT_CANDIDATES = [
    ("/System/Library/Fonts/HelveticaNeue.ttc", 7),   # "Light" face
    ("/System/Library/Fonts/SFNS.ttf", 0),
]

# Scene order == App Store screenshot order (01..06). Plain voice, no em dashes.
SCENES = [
    ("tonightClosed", "Doors open at 7. Every night."),
    ("lobby", "Someone nearby, in seconds."),
    ("date", "Five minutes. Then decide."),
    ("decision", "Keep talking, or pass."),
    ("match", "It's a match."),
    ("chat", "Text only. Keep it simple."),
]


def load_font(size):
    for path, index in FONT_CANDIDATES:
        if not os.path.exists(path):
            continue
        try:
            return ImageFont.truetype(path, size, index=index)
        except OSError:
            continue
    return ImageFont.load_default()


def fit_font(draw, text, max_width, start_size=88, min_size=40, step=2):
    """Largest font (from start_size down) whose single-line width fits."""
    size = start_size
    while size > min_size:
        font = load_font(size)
        left, _, right, _ = draw.textbbox((0, 0), text, font=font)
        if (right - left) <= max_width:
            return font
        size -= step
    return load_font(min_size)


def contain_fit(img, target_w, target_h):
    """Scale img to fit inside target_w x target_h (whole screen visible,
    including the tab bar / composer), returning the resized image."""
    src_w, src_h = img.size
    scale = min(target_w / src_w, target_h / src_h)
    return img.resize((max(1, round(src_w * scale)), max(1, round(src_h * scale))), Image.LANCZOS)


def cover_crop(img, target_w, target_h):
    """Scale img to fully cover target_w x target_h, then center-crop.

    This is the standard full-bleed "aspect fill": no distortion, no
    letterboxing, whatever doesn't fit is cropped evenly from the edges.
    """
    src_w, src_h = img.size
    scale = max(target_w / src_w, target_h / src_h)
    new_w, new_h = max(1, round(src_w * scale)), max(1, round(src_h * scale))
    resized = img.resize((new_w, new_h), Image.LANCZOS)
    left = (new_w - target_w) // 2
    top = (new_h - target_h) // 2
    return resized.crop((left, top, left + target_w, top + target_h))


def compose_one(raw_path, caption):
    shot = Image.open(raw_path).convert("RGB")
    canvas = Image.new("RGB", (W69, H69), EGGSHELL)

    shot_h = H69 - BAND_H
    fitted = contain_fit(shot, W69, shot_h)
    canvas.paste(fitted, ((W69 - fitted.width) // 2, BAND_H))

    draw = ImageDraw.Draw(canvas)
    margin = 110
    font = fit_font(draw, caption, W69 - 2 * margin)
    left, top, right, bottom = draw.textbbox((0, 0), caption, font=font)
    text_w, text_h = right - left, bottom - top
    x = (W69 - text_w) // 2 - left
    y = (BAND_H - text_h) // 2 - top
    draw.text((x, y), caption, font=font, fill=ESPRESSO)
    return canvas


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--raw-dir", default=DEFAULT_RAW, help="directory of raw <scene>.png shots")
    ap.add_argument("--out-dir", default=DEFAULT_OUT, help="directory to write composed screenshots into")
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)

    missing = []
    written = []
    for i, (scene, caption) in enumerate(SCENES, start=1):
        raw_path = os.path.join(args.raw_dir, f"{scene}.png")
        if not os.path.exists(raw_path):
            missing.append(raw_path)
            continue

        canvas = compose_one(raw_path, caption)

        name69 = f"{i:02d}_APP_IPHONE_6_9_{scene}.png"
        canvas.save(os.path.join(args.out_dir, name69))

        canvas65 = canvas.resize((W65, H65), Image.LANCZOS)
        name65 = f"{i:02d}_APP_IPHONE_65_{scene}.png"
        canvas65.save(os.path.join(args.out_dir, name65))

        written.append((name69, name65))
        print(f"  wrote {name69} + {name65}")

    if missing:
        raise SystemExit(
            "compose_screenshots: missing raw screenshot(s):\n  " + "\n  ".join(missing)
        )
    print(f"done: {len(written)} scene(s) -> {args.out_dir}")


if __name__ == "__main__":
    main()
