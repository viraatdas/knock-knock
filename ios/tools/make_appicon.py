#!/usr/bin/env python3
"""Knock Knock app icon — a minimal stick figure knocking on a door.
Warm, cozy palette: eggshell ground, espresso ink, terracotta accent.
Writes ios/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""
from PIL import Image, ImageDraw

SS = 4                 # supersample for crisp edges
S = 1024
BIG = S * SS

# Warm palette (matches Theme.swift)
EGG      = (0xFA, 0xF6, 0xEF)
EGG_DEEP = (0xF1, 0xE7, 0xD6)
INK      = (0x2A, 0x21, 0x1B)
DOOR     = (0x7A, 0x5A, 0x3E)   # warm wood door
DOOR_DK  = (0x5A, 0x46, 0x32)   # espresso door edge
ACCENT   = (0xD4, 0x69, 0x4F)   # terracotta (knock marks / knob)

def make():
    img = Image.new("RGB", (BIG, BIG), EGG)
    d = ImageDraw.Draw(img)

    def P(fx, fy):
        return (int(BIG * fx), int(BIG * fy))

    # --- Door on the right ---
    dx0, dy0 = BIG*0.56, BIG*0.20
    dx1, dy1 = BIG*0.86, BIG*0.84
    d.rounded_rectangle((dx0, dy0, dx1, dy1), radius=BIG*0.03, fill=DOOR)
    # door inner panel outline
    d.rounded_rectangle((dx0+BIG*0.03, dy0+BIG*0.04, dx1-BIG*0.03, dy1-BIG*0.05),
                        radius=BIG*0.02, outline=DOOR_DK, width=int(BIG*0.006))
    # door knob (terracotta)
    kx, ky = dx0+BIG*0.045, (dy0+dy1)/2
    d.ellipse((kx-BIG*0.018, ky-BIG*0.018, kx+BIG*0.018, ky+BIG*0.018), fill=ACCENT)

    # --- Stick figure knocking (left of the door) ---
    lw = int(BIG*0.05)
    def limb(a, b):
        d.line([a, b], fill=INK, width=lw)
        for p in (a, b):
            d.ellipse((p[0]-lw//2, p[1]-lw//2, p[0]+lw//2, p[1]+lw//2), fill=INK)

    # head
    hr = int(BIG*0.075)
    hx, hy = P(0.34, 0.34)
    d.ellipse((hx-hr, hy-hr, hx+hr, hy+hr), fill=INK)
    # torso, slight lean toward the door
    neck = P(0.345, 0.415)
    hip  = P(0.33, 0.62)
    limb(neck, hip)
    # legs
    limb(hip, P(0.27, 0.78))
    limb(hip, P(0.39, 0.78))
    # back arm down
    sh = P(0.342, 0.46)
    limb(sh, P(0.27, 0.58))
    # FRONT arm raised, fist near the door (the knock)
    fist = P(0.50, 0.40)
    limb(sh, fist)

    # --- Knock marks (terracotta arcs near the fist) ---
    for i, r in enumerate((0.035, 0.058, 0.082)):
        bb = (fist[0]+BIG*0.02 - BIG*r, fist[1] - BIG*r,
              fist[0]+BIG*0.02 + BIG*r, fist[1] + BIG*r)
        d.arc(bb, -55, 55, fill=ACCENT, width=int(BIG*0.012))

    return img.resize((S, S), Image.LANCZOS)

def main():
    out = "ios/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
    icon = make()
    icon.save(out)
    icon.resize((180, 180)).save("/tmp/icon_knock.png")
    print(f"wrote {out}; preview /tmp/icon_knock.png")

if __name__ == "__main__":
    main()
