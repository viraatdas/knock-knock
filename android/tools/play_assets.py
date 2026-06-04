#!/usr/bin/env python3
"""
Generate Google Play store graphic assets for the Slide Android app.

Brand (see AGENTS.md / store/assets.md):
  - Pure white background (#FFFFFF), every surface.
  - Thin near-black type (#0A0A0A), generous whitespace.
  - One restrained accent: accent == text == #0A0A0A; danger #E5484D is the only red.
  - Hairlines #ECECEC for dividers, secondary gray #6B7280.
  - Thin line icons (~1.5px stroke), 12-16px corner radius, calm/premium.

Outputs (reproducible — re-run to regenerate):
  android/fastlane/metadata/android/en-US/images/featureGraphic/feature.png   1024x500  RGB  (no alpha)
  android/fastlane/metadata/android/en-US/images/phoneScreenshots/01-welcome.png      1080x1920 RGB
  android/fastlane/metadata/android/en-US/images/phoneScreenshots/02-enter-phone.png  1080x1920 RGB
  android/fastlane/metadata/android/en-US/images/phoneScreenshots/03-recents.png       1080x1920 RGB
  android/fastlane/metadata/android/en-US/images/phoneScreenshots/04-contact.png        1080x1920 RGB
  android/fastlane/metadata/android/en-US/images/phoneScreenshots/05-incall.png         1080x1920 RGB
  android/fastlane/metadata/android/en-US/images/icon/icon.png                 512x512   RGBA (32-bit w/ alpha)

Usage: python3 android/tools/play_assets.py
"""

import os
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------- paths
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
IMG_DIR = os.path.join(
    REPO, "android", "fastlane", "metadata", "android", "en-US", "images"
)
FEATURE_DIR = os.path.join(IMG_DIR, "featureGraphic")
PHONE_DIR = os.path.join(IMG_DIR, "phoneScreenshots")
ICON_DIR = os.path.join(IMG_DIR, "icon")
SRC_SHOTS = os.path.join(REPO, "android", "screenshots")

# ---------------------------------------------------------------- tokens
BG = (255, 255, 255)
BG_GROUPED = (250, 250, 250)
TEXT = (10, 10, 10)
TEXT_SECONDARY = (107, 114, 128)
HAIRLINE = (236, 236, 236)
ACCENT = (10, 10, 10)
DANGER = (229, 72, 77)
WHITE = (255, 255, 255)

PHONE_W, PHONE_H = 1080, 1920

# ---------------------------------------------------------------- fonts
HN = "/System/Library/Fonts/HelveticaNeue.ttc"
IDX = {"thin": 12, "ultralight": 5, "light": 7, "regular": 0, "medium": 10}


def font(weight, size):
    return ImageFont.truetype(HN, size, index=IDX[weight])


def text_w(draw, s, fnt):
    box = draw.textbbox((0, 0), s, font=fnt)
    return box[2] - box[0]


def centered(draw, cx, y, s, fnt, fill, tracking=0):
    """Draw text horizontally centered at cx (supports letter tracking)."""
    if tracking == 0:
        w = text_w(draw, s, fnt)
        draw.text((cx - w / 2, y), s, font=fnt, fill=fill)
        return
    widths = [text_w(draw, ch, fnt) for ch in s]
    total = sum(widths) + tracking * (len(s) - 1)
    x = cx - total / 2
    for ch, w in zip(s, widths):
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += w + tracking


def rounded(draw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


# ---------------------------------------------------------------- mark
def draw_slide_mark(draw, cx, cy, size, color=TEXT, stroke=None):
    """A subtle forward-slide glyph: a thin upward-right chevron (a fast 'slide').

    Two parallel hairline strokes leaning forward, evoking motion / a stylised S
    movement, kept minimal and centered.
    """
    if stroke is None:
        stroke = max(2, round(size * 0.07))
    half = size / 2
    # forward-leaning diagonal: bottom-left -> top-right
    dx = size * 0.34
    dy = size * 0.46
    # primary stroke
    draw.line(
        [(cx - dx, cy + dy), (cx + dx, cy - dy)],
        fill=color, width=stroke, joint="curve",
    )
    # short trailing stroke beneath, slightly offset -> the "slide" trail
    off = size * 0.30
    draw.line(
        [(cx - dx, cy + dy + off * 0.0 + off), (cx - dx + dx * 0.9, cy + dy + off - dy * 0.9)],
        fill=color, width=stroke, joint="curve",
    )
    return stroke


# ---------------------------------------------------------------- status bar
def draw_status_bar(draw, dark=False):
    col = WHITE if dark else TEXT
    f = font("regular", 30)
    draw.text((54, 40), "4:06", font=f, fill=col)
    # right side: wifi triangle, signal, battery (simple thin glyphs)
    x = PHONE_W - 60
    # battery
    draw.rounded_rectangle([x - 44, 44, x - 6, 70], radius=4, outline=col, width=3)
    draw.rectangle([x - 4, 52, x - 1, 62], fill=col)
    draw.rounded_rectangle([x - 41, 47, x - 14, 67], radius=2, fill=col)
    # signal bars
    bx = x - 92
    for i in range(4):
        h = 8 + i * 7
        draw.rectangle([bx + i * 11, 70 - h, bx + i * 11 + 7, 70], fill=col)
    # wifi (small arc-ish triangle)
    wx = x - 150
    draw.polygon([(wx, 70), (wx + 34, 70), (wx + 17, 44)], fill=col)


def gesture_bar(draw, dark=False):
    col = (60, 60, 60) if not dark else (210, 210, 210)
    cx = PHONE_W / 2
    draw.rounded_rectangle([cx - 90, PHONE_H - 26, cx + 90, PHONE_H - 18], radius=4, fill=col)


def avatar(draw, cx, cy, r, initials, bg=BG_GROUPED, ring=HAIRLINE):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=bg, outline=ring, width=2)
    f = font("regular", int(r * 0.8))
    centered(draw, cx, cy - r * 0.55, initials, f, TEXT_SECONDARY)


# ================================================================ FEATURE
def make_feature():
    W, H = 1024, 500
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    cx = W / 2

    # wordmark "Slide", thin, tracked ~0.04em
    f = font("thin", 150)
    tracking = int(150 * 0.04)
    centered(d, cx, H / 2 - 110, "Slide", f, TEXT, tracking=tracking)

    # restrained subline
    fs = font("light", 34)
    centered(d, cx, H / 2 + 70, "Calls, quietly.", fs, TEXT_SECONDARY, tracking=2)

    os.makedirs(FEATURE_DIR, exist_ok=True)
    out = os.path.join(FEATURE_DIR, "feature.png")
    img.convert("RGB").save(out, "PNG")
    return out


# ================================================================ ICON
def make_icon():
    S = 512
    img = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    d = ImageDraw.Draw(img)
    # >=20% padding; mark small & centered. Use the thin "S" wordmark glyph.
    f = font("thin", 300)
    s = "S"
    box = d.textbbox((0, 0), s, font=f)
    w = box[2] - box[0]
    h = box[3] - box[1]
    d.text((S / 2 - w / 2 - box[0], S / 2 - h / 2 - box[1]), s, font=f, fill=TEXT)
    os.makedirs(ICON_DIR, exist_ok=True)
    out = os.path.join(ICON_DIR, "icon.png")
    img.save(out, "PNG")  # keeps RGBA / 32-bit alpha
    return out


# ================================================================ SCREENSHOTS
def new_screen(dark=False):
    img = Image.new("RGB", (PHONE_W, PHONE_H), TEXT if dark else BG)
    return img, ImageDraw.Draw(img)


def tab_bar(d, active):
    """Bottom nav: Calls, Contacts, Profile."""
    y0 = PHONE_H - 150
    d.line([(0, y0), (PHONE_W, y0)], fill=HAIRLINE, width=2)
    tabs = ["Calls", "Contacts", "Profile"]
    f = font("regular", 28)
    n = len(tabs)
    for i, t in enumerate(tabs):
        cx = PHONE_W * (i + 0.5) / n
        col = TEXT if i == active else TEXT_SECONDARY
        # thin icon dot/line placeholder above label
        iy = y0 + 38
        if i == 0:  # calls - phone
            d.arc([cx - 16, iy - 16, cx + 16, iy + 16], 200, 340, fill=col, width=3)
        elif i == 1:  # contacts - person
            d.ellipse([cx - 9, iy - 18, cx + 9, iy], outline=col, width=3)
            d.arc([cx - 18, iy - 2, cx + 18, iy + 30], 180, 360, fill=col, width=3)
        else:  # profile - circle
            d.ellipse([cx - 16, iy - 16, cx + 16, iy + 16], outline=col, width=3)
        centered(d, cx, y0 + 66, t, f, col)


def make_recents():
    img, d = new_screen()
    draw_status_bar(d)
    M = 56
    # Large thin title
    d.text((M, 150), "Calls", font=font("thin", 84), fill=TEXT)

    rows = [
        ("Maya Chen", "Incoming", "9:41 AM", "video", False),
        ("Devin Park", "Outgoing", "Yesterday", "audio", False),
        ("Aria Solis", "Missed", "Yesterday", "video", True),
        ("Theo Marsh", "Incoming", "Mon", "audio", False),
        ("Noor Hassan", "Outgoing", "Sun", "video", False),
        ("Eli Rivera", "Missed", "Mar 28", "audio", True),
        ("Priya Nair", "Incoming", "Mar 26", "video", False),
    ]
    initials = {
        "Maya Chen": "MC", "Devin Park": "DP", "Aria Solis": "AS",
        "Theo Marsh": "TM", "Noor Hassan": "NH", "Eli Rivera": "ER",
        "Priya Nair": "PN",
    }
    y = 300
    row_h = 168
    fn = font("regular", 42)
    fsub = font("regular", 30)
    for name, kind, when, media, missed in rows:
        cy = y + row_h / 2 - 24
        avatar(d, M + 44, cy, 44, initials[name])
        d.text((M + 120, cy - 42), name, font=fn, fill=TEXT)
        subcol = DANGER if missed else TEXT_SECONDARY
        # direction glyph + label
        d.text((M + 120, cy + 8), f"{kind} · {media.capitalize()}", font=fsub, fill=subcol)
        # right: time + media glyph
        tw = text_w(d, when, fsub)
        d.text((PHONE_W - M - tw, cy - 8), when, font=fsub, fill=TEXT_SECONDARY)
        # hairline divider
        d.line([(M + 120, y + row_h - 12), (PHONE_W - M, y + row_h - 12)], fill=HAIRLINE, width=2)
        y += row_h

    tab_bar(d, active=0)
    gesture_bar(d)
    out = os.path.join(PHONE_DIR, "03-recents.png")
    img.save(out, "PNG")
    return out


def make_contact():
    img, d = new_screen()
    draw_status_bar(d)
    cx = PHONE_W / 2

    # back chevron, thin
    d.line([(70, 140), (44, 166)], fill=TEXT, width=4, joint="curve")
    d.line([(44, 166), (70, 192)], fill=TEXT, width=4, joint="curve")

    # large avatar
    ay = 470
    avatar(d, cx, ay, 150, "MC", bg=BG_GROUPED)

    # name + number
    centered(d, cx, ay + 210, "Maya Chen", font("light", 72), TEXT)
    centered(d, cx, ay + 310, "+1 415 555 0137", font("regular", 38), TEXT_SECONDARY, tracking=1)

    # two thin call buttons: audio (outline) / video (filled accent)
    by = ay + 470
    bw, bh, gap = 360, 132, 48
    x0 = cx - bw - gap / 2
    x1 = cx + gap / 2
    # Audio — outlined hairline pill
    rounded(d, [x0, by, x0 + bw, by + bh], radius=24, outline=TEXT, width=3)
    # phone glyph
    pcx, pcy = x0 + 110, by + bh / 2
    d.arc([pcx - 22, pcy - 22, pcx + 22, pcy + 22], 200, 340, fill=TEXT, width=4)
    d.text((x0 + 150, by + bh / 2 - 30), "Audio", font=font("medium", 42), fill=TEXT)
    # Video — filled accent pill
    rounded(d, [x1, by, x1 + bw, by + bh], radius=24, fill=ACCENT)
    vcx, vcy = x1 + 110, by + bh / 2
    d.rounded_rectangle([vcx - 26, vcy - 16, vcx + 8, vcy + 16], radius=6, outline=WHITE, width=4)
    d.polygon([(vcx + 14, vcy - 12), (vcx + 28, vcy - 20), (vcx + 28, vcy + 20), (vcx + 14, vcy + 12)], outline=WHITE, width=4)
    d.text((x1 + 150, by + bh / 2 - 30), "Video", font=font("medium", 42), fill=WHITE)

    # small "On Slide" hairline tag under buttons
    tag = "On Slide"
    ft = font("regular", 30)
    tw = text_w(d, tag, ft)
    ty = by + bh + 70
    rounded(d, [cx - tw / 2 - 30, ty, cx + tw / 2 + 30, ty + 56], radius=28, outline=HAIRLINE, width=2)
    centered(d, cx, ty + 12, tag, ft, TEXT_SECONDARY, tracking=2)

    gesture_bar(d)
    out = os.path.join(PHONE_DIR, "04-contact.png")
    img.save(out, "PNG")
    return out


def make_incall():
    # Full-bleed call screen. Keep brand calm: near-black canvas, white thin type,
    # minimal control row. A small self-view in the corner.
    img, d = new_screen(dark=True)
    draw_status_bar(d, dark=True)
    cx = PHONE_W / 2

    # remote participant avatar large, centered
    ay = 720
    r = 190
    d.ellipse([cx - r, ay - r, cx + r, ay + r], fill=(30, 30, 30), outline=(60, 60, 60), width=2)
    centered(d, cx, ay - r * 0.5, "MC", font("light", 150), (150, 150, 150))

    centered(d, cx, ay + r + 70, "Maya Chen", font("light", 64), WHITE)
    centered(d, cx, ay + r + 170, "00:42", font("regular", 40), (170, 170, 170), tracking=2)

    # self-view thumbnail top-right
    sw, sh = 220, 300
    sx = PHONE_W - sw - 50
    sy = 150
    d.rounded_rectangle([sx, sy, sx + sw, sy + sh], radius=24, fill=(38, 38, 38), outline=(70, 70, 70), width=2)
    centered(d, sx + sw / 2, sy + sh / 2 - 40, "You", font("regular", 34), (150, 150, 150))

    # minimal control row near bottom
    cy = PHONE_H - 320
    ctrl_r = 58
    spacing = 200
    positions = [cx - spacing * 1.5, cx - spacing * 0.5, cx + spacing * 0.5, cx + spacing * 1.5]

    def ctrl(px, glyph):
        d.ellipse([px - ctrl_r, cy - ctrl_r, px + ctrl_r, cy + ctrl_r],
                  fill=(38, 38, 38), outline=(70, 70, 70), width=2)
        glyph(px, cy)

    def g_mic(px, py):
        d.rounded_rectangle([px - 12, py - 26, px + 12, py + 8], radius=12, outline=WHITE, width=4)
        d.arc([px - 22, py - 14, px + 22, py + 26], 0, 180, fill=WHITE, width=4)
        d.line([(px, py + 22), (px, py + 34)], fill=WHITE, width=4)

    def g_video(px, py):
        d.rounded_rectangle([px - 28, py - 16, px + 6, py + 16], radius=6, outline=WHITE, width=4)
        d.polygon([(px + 12, py - 12), (px + 28, py - 20), (px + 28, py + 20), (px + 12, py + 12)], outline=WHITE, width=4)

    def g_flip(px, py):
        d.arc([px - 24, py - 24, px + 24, py + 24], 40, 300, fill=WHITE, width=4)
        d.polygon([(px + 18, py - 26), (px + 30, py - 14), (px + 12, py - 10)], fill=WHITE)

    ctrl(positions[0], g_mic)
    ctrl(positions[1], g_video)
    ctrl(positions[2], g_flip)

    # end call — danger (the only red)
    ep = positions[3]
    d.ellipse([ep - ctrl_r, cy - ctrl_r, ep + ctrl_r, cy + ctrl_r], fill=DANGER)
    # phone glyph rotated (hang up)
    d.arc([ep - 22, cy - 22, ep + 22, cy + 22], 20, 160, fill=WHITE, width=5)

    # labels
    fl = font("regular", 26)
    labels = ["Mute", "Camera", "Flip", "End"]
    for px, lab in zip(positions, labels):
        col = WHITE if lab != "End" else (240, 180, 180)
        centered(d, px, cy + ctrl_r + 24, lab, fl, (180, 180, 180) if lab != "End" else (200, 130, 130))

    gesture_bar(d, dark=True)
    out = os.path.join(PHONE_DIR, "05-incall.png")
    img.save(out, "PNG")
    return out


def fit_existing(src, dst):
    """Resize/pad an existing capture onto a pure-white 1080x1920 canvas."""
    im = Image.open(src).convert("RGB")
    canvas = Image.new("RGB", (PHONE_W, PHONE_H), BG)
    scale = min(PHONE_W / im.width, PHONE_H / im.height)
    nw, nh = round(im.width * scale), round(im.height * scale)
    im = im.resize((nw, nh), Image.LANCZOS)
    canvas.paste(im, ((PHONE_W - nw) // 2, (PHONE_H - nh) // 2))
    canvas.save(dst, "PNG")
    return dst


def main():
    os.makedirs(PHONE_DIR, exist_ok=True)
    outputs = []
    outputs.append(make_feature())
    outputs.append(make_icon())
    # existing captures -> normalized 1080x1920
    outputs.append(fit_existing(os.path.join(SRC_SHOTS, "01-welcome.png"),
                                os.path.join(PHONE_DIR, "01-welcome.png")))
    outputs.append(fit_existing(os.path.join(SRC_SHOTS, "02-enter-phone.png"),
                                os.path.join(PHONE_DIR, "02-enter-phone.png")))
    outputs.append(make_recents())
    outputs.append(make_contact())
    outputs.append(make_incall())

    print("Generated assets:")
    for p in outputs:
        im = Image.open(p)
        print(f"  {os.path.relpath(p, REPO)}  {im.size[0]}x{im.size[1]}  {im.mode}")


if __name__ == "__main__":
    main()
