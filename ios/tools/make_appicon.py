#!/usr/bin/env python3
"""Slide app icon — a minimal stick figure mid-slide. White bg, near-black,
one restrained accent. Outputs ios/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""
from PIL import Image, ImageDraw

S = 1024
INK = (0x14,0x14,0x16)
ACCENT = (0x3B,0x82,0xF6)   # one calm blue accent (motion lines)
BG = (255,255,255)

img = Image.new("RGB",(S,S),BG)
d = ImageDraw.Draw(img)

# subtle ground line
gy = int(S*0.70)
d.line((int(S*0.16),gy,int(S*0.84),gy), fill=(0xE6,0xE6,0xE8), width=10)

lw = 30  # stroke width for the figure
def limb(p1,p2,w=lw,col=INK):
    d.line([p1,p2], fill=col, width=w)
    for p in (p1,p2):
        d.ellipse((p[0]-w//2,p[1]-w//2,p[0]+w//2,p[1]+w//2), fill=col)

# Figure leaning into a slide (moving right). Coordinates tuned on 1024.
# head
hx,hy,hr = int(S*0.46), int(S*0.30), int(S*0.075)
d.ellipse((hx-hr,hy-hr,hx+hr,hy+hr), fill=INK)
# torso: leaning forward (top-left to lower-right)
neck = (hx+6, hy+hr+6)
hip  = (int(S*0.55), int(S*0.55))
limb(neck, hip)
# back leg extended back, front leg bent forward in a slide
front_knee = (int(S*0.66), int(S*0.585))
front_foot = (int(S*0.74), int(S*0.70))   # sliding foot reaching ground
back_foot  = (int(S*0.40), int(S*0.685))
limb(hip, front_knee); limb(front_knee, front_foot)
limb(hip, back_foot)
# arms: front arm forward, back arm trailing
sh = (int(neck[0]+ (hip[0]-neck[0])*0.18), int(neck[1] + (hip[1]-neck[1])*0.18))
limb(sh, (int(S*0.69), int(S*0.40)))   # front arm up/forward
limb(sh, (int(S*0.30), int(S*0.45)))   # back arm trailing

# motion lines (the slide) — the single accent
for i,yoff in enumerate((-0.05,0.0,0.05)):
    y = int(S*0.50 + S*yoff)
    x0 = int(S*0.12 + i*S*0.02)
    x1 = int(S*0.30 + i*S*0.015)
    d.line((x0,y,x1,y), fill=ACCENT, width=16)

img.save("ios/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
# preview
img.resize((512,512)).save("/tmp/icon_preview.png")
print("wrote icon-1024.png")
