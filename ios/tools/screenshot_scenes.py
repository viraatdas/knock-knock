#!/usr/bin/env python3
"""Generate App Store screenshot scenes for Slide.

On-brand: bright, minimal, near-black thin text. Builds real video-call
scenes (1:1 video, group grid, incoming) with diverse illustrated avatars
(no real people). Run from repo root: python3 ios/tools/screenshot_scenes.py
"""
from PIL import Image, ImageDraw, ImageFont
import os

W, H = 1206, 2622
OUT = "ios/fastlane/screenshots/en-US"
FONTS = {
    "reg": "/System/Library/Fonts/Helvetica.ttc",
    "neue": "/System/Library/Fonts/HelveticaNeue.ttc",
}

def font(size, light=False):
    return ImageFont.truetype(FONTS["reg"], size)

NEAR_BLACK = (0x11, 0x11, 0x11)
GRAY = (0x8A, 0x8A, 0x90)
RED = (0xF4, 0x5B, 0x57)

# Diverse avatar palettes: skin, hair, cloth, two-stop soft bg
PEOPLE = {
    "daniela": dict(skin=(0xF2,0xC9,0xA8), hair=(0x3A,0x2E,0x2A), cloth=(0x5B,0x6B,0x86),
                    bg=((0xEC,0xF1,0xF6),(0xF6,0xEC,0xF0)), style="bob"),
    "alex":    dict(skin=(0xC8,0x8E,0x66), hair=(0x20,0x18,0x14), cloth=(0x2E,0x3A,0x33),
                    bg=((0xEE,0xF3,0xEC),(0xE8,0xEE,0xF4)), style="short"),
    "grace":   dict(skin=(0xF6,0xD7,0xBC), hair=(0x14,0x12,0x12), cloth=(0xB0,0x6A,0x5A),
                    bg=((0xF6,0xEF,0xE8),(0xF0,0xE8,0xF2)), style="long"),
    "isla":    dict(skin=(0x8A,0x5A,0x3C), hair=(0x1A,0x12,0x10), cloth=(0x6A,0x5A,0x86),
                    bg=((0xEF,0xEC,0xF6),(0xEC,0xF2,0xF2)), style="curly"),
    "ben":     dict(skin=(0xE8,0xBC,0x98), hair=(0x4A,0x33,0x22), cloth=(0x36,0x4A,0x60),
                    bg=((0xEC,0xF0,0xF5),(0xF1,0xF1,0xEC)), style="short"),
}

def vgrad(w, h, c0, c1):
    img = Image.new("RGB", (w, h), c0)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(c0[i] + (c1[i]-c0[i])*t) for i in range(3)))
    return img

FACES_DIR = os.path.join(os.path.dirname(__file__), "faces")
_face_cache = {}

def face_photo(box_w, box_h, key):
    """Return a real AI-generated (StyleGAN) face photo cropped to fill the box.
    Falls back to the illustrated portrait if the photo isn't on disk."""
    path = os.path.join(FACES_DIR, f"{key}.jpg")
    if not os.path.exists(path):
        return None
    src = _face_cache.get(key) or Image.open(path).convert("RGB")
    _face_cache[key] = src
    sw, sh = src.size
    scale = max(box_w/sw, box_h/sh)
    rw, rh = int(sw*scale), int(sh*scale)
    r = src.resize((rw, rh), Image.LANCZOS)
    # center-crop, biased slightly up so faces sit nicely
    left = (rw - box_w)//2
    top = max(0, int((rh - box_h)*0.40))
    return r.crop((left, top, left+box_w, top+box_h))

def portrait(box_w, box_h, p, head_scale=1.0, key=None):
    """Real AI face photo when available; else an illustrated head+shoulders."""
    if key is not None:
        photo = face_photo(box_w, box_h, key)
        if photo is not None:
            return photo
    img = vgrad(box_w, box_h, *p["bg"])
    d = ImageDraw.Draw(img)
    cx = box_w // 2
    S = int(min(box_w, box_h) * 0.52 * head_scale)   # head diameter
    cy = int(box_h * 0.46)
    skin, hair, cloth, style = p["skin"], p["hair"], p["cloth"], p["style"]

    # shoulders
    sh_w = int(S * 2.0); sh_top = cy + int(S*0.42)
    d.pieslice((cx-sh_w//2, sh_top, cx+sh_w//2, sh_top+int(S*1.7)), 180, 360, fill=cloth)
    # hair back mass
    if style in ("long", "curly", "bob"):
        hw = int(S*0.78)
        d.ellipse((cx-hw, cy-int(S*0.55), cx+hw, cy+int(S*0.75)), fill=hair)
    # neck
    d.rectangle((cx-int(S*0.16), cy+int(S*0.20), cx+int(S*0.16), cy+int(S*0.55)), fill=skin)
    # face
    d.ellipse((cx-S//2, cy-S//2, cx+S//2, cy+S//2), fill=skin)
    # fringe / top hair
    if style == "short":
        d.pieslice((cx-int(S*0.55), cy-int(S*0.62), cx+int(S*0.55), cy+int(S*0.10)), 180, 360, fill=hair)
    elif style == "curly":
        for dx in range(-3, 4):
            d.ellipse((cx+dx*int(S*0.16)-int(S*0.20), cy-int(S*0.62),
                       cx+dx*int(S*0.16)+int(S*0.20), cy-int(S*0.18)), fill=hair)
        d.ellipse((cx-int(S*0.54), cy-int(S*0.45), cx+int(S*0.54), cy-int(S*0.02)), fill=hair)
    else:  # bob / long fringe
        d.pieslice((cx-int(S*0.52), cy-int(S*0.60), cx+int(S*0.52), cy-int(S*0.02)), 180, 360, fill=hair)
        if style in ("bob", "long"):
            d.ellipse((cx-int(S*0.58), cy-int(S*0.30), cx-int(S*0.30), cy+int(S*0.45)), fill=hair)
            d.ellipse((cx+int(S*0.30), cy-int(S*0.30), cx+int(S*0.58), cy+int(S*0.45)), fill=hair)
            # redraw face to sit in front of side hair
            d.ellipse((cx-int(S*0.46), cy-int(S*0.46), cx+int(S*0.46), cy+int(S*0.46)), fill=skin)
            d.pieslice((cx-int(S*0.50), cy-int(S*0.58), cx+int(S*0.50), cy-int(S*0.04)), 180, 360, fill=hair)
    # eyes + smile
    eye = (0x33,0x2A,0x26)
    er = max(4, int(S*0.035))
    d.ellipse((cx-int(S*0.20)-er, cy-int(S*0.02)-er, cx-int(S*0.20)+er, cy-int(S*0.02)+er), fill=eye)
    d.ellipse((cx+int(S*0.20)-er, cy-int(S*0.02)-er, cx+int(S*0.20)+er, cy-int(S*0.02)+er), fill=eye)
    d.arc((cx-int(S*0.16), cy+int(S*0.04), cx+int(S*0.16), cy+int(S*0.22)),
          20, 160, fill=(0xC0,0x6E,0x5E), width=max(3,int(S*0.03)))
    return img

def status_bar(d, time="4:25", dark=False):
    col = (255,255,255) if dark else NEAR_BLACK
    d.text((96, 70), time, font=font(58), fill=col, anchor="lm")
    # dynamic island
    d.rounded_rectangle((W//2-150, 40, W//2+150, 100), radius=30, fill=(0,0,0))
    # wifi + battery (simple)
    bx = W-150
    d.rounded_rectangle((bx, 56, bx+96, 90), radius=10, outline=col, width=4)
    d.rounded_rectangle((bx+6, 62, bx+78, 84), radius=5, fill=col)

def round_avatar(canvas, center, r, p, key=None):
    av = portrait(2*r, 2*r, p, head_scale=1.15, key=key)
    mask = Image.new("L", (2*r, 2*r), 0)
    ImageDraw.Draw(mask).ellipse((0,0,2*r,2*r), fill=255)
    canvas.paste(av, (center[0]-r, center[1]-r), mask)

def _handset(size, col):
    """A clean solid telephone-handset glyph (earpiece + handle + mouthpiece),
    centered in a size×size RGBA tile. Drawn upright; the caller rotates it
    (135° for the classic red hang-up look). Supersampled for smooth edges."""
    SS = 4
    big = size*SS
    img = Image.new("RGBA", (big, big), (0,0,0,0))
    d = ImageDraw.Draw(img)
    c = big//2
    sc = big/100.0
    # vertical handle (the grip)
    d.rounded_rectangle((c-8*sc, c-26*sc, c+8*sc, c+26*sc), radius=8*sc, fill=col)
    # earpiece (top) + mouthpiece (bottom): wide rounded caps
    d.rounded_rectangle((c-24*sc, c-40*sc, c+24*sc, c-22*sc), radius=10*sc, fill=col)
    d.rounded_rectangle((c-24*sc, c+22*sc, c+24*sc, c+40*sc), radius=10*sc, fill=col)
    return img.resize((size, size), Image.LANCZOS)

def ctrl_button(d, center, r, fill, icon, icon_col=(255,255,255), base=None):
    cx, cy = center
    # soft drop shadow for depth
    d.ellipse((cx-r, cy-r+4, cx+r, cy+r+4), fill=(0,0,0,30) if False else None)
    d.ellipse((cx-r, cy-r, cx+r, cy+r), fill=fill)
    if icon == "end":
        # rotated handset (classic red hang-up). Composite onto base if given.
        size = int(r*1.5)
        hs = _handset(size, (255,255,255,255)).rotate(135, resample=Image.BICUBIC, expand=False)
        if base is not None:
            base.paste(hs, (cx-size//2, cy-size//2), hs)
        else:
            d.bitmap((cx-size//2, cy-size//2), hs.convert("1"), fill=(255,255,255))
    elif icon == "video":
        d.rounded_rectangle((cx-30, cy-18, cx+8, cy+18), radius=10, fill=icon_col)
        d.polygon([(cx+12,cy-12),(cx+30,cy-22),(cx+30,cy+22),(cx+12,cy+12)], fill=icon_col)
    elif icon == "mic":
        d.rounded_rectangle((cx-12, cy-26, cx+12, cy+8), radius=12, fill=icon_col)
        d.arc((cx-22, cy-12, cx+22, cy+24), 0, 180, fill=icon_col, width=6)
        d.line((cx, cy+24, cx, cy+38), fill=icon_col, width=6)
        d.line((cx-12, cy+38, cx+12, cy+38), fill=icon_col, width=6)
    elif icon == "flip":
        d.arc((cx-24, cy-24, cx+24, cy+24), 40, 300, fill=icon_col, width=7)
        d.polygon([(cx+18,cy-26),(cx+32,cy-10),(cx+8,cy-10)], fill=icon_col)
    elif icon == "speaker":
        d.polygon([(cx-22,cy-10),(cx-6,cy-10),(cx+6,cy-22),(cx+6,cy+22),(cx-6,cy+10),(cx-22,cy+10)], fill=icon_col)
        d.arc((cx+2, cy-18, cx+30, cy+18), 300, 60, fill=icon_col, width=6)


def scene_incall_video(person_key="daniela", name="Daniela Wu", time="12:04", you="alex"):
    base = portrait(W, H, PEOPLE[person_key], head_scale=1.35, key=person_key)
    d = ImageDraw.Draw(base)
    # top scrim for legibility
    scrim = Image.new("RGBA", (W, 360), (255,255,255,0))
    sd = ImageDraw.Draw(scrim)
    for y in range(360):
        a = int(150 * (1 - y/360))
        sd.line([(0,y),(W,y)], fill=(255,255,255,a))
    base.paste(scrim, (0,0), scrim)
    d = ImageDraw.Draw(base)
    status_bar(d, time="4:25")
    d.text((W//2, 200), name, font=font(70), fill=NEAR_BLACK, anchor="mm")
    d.text((W//2, 270), time, font=font(44), fill=GRAY, anchor="mm")
    # self-view PIP
    pw, ph = 300, 410
    px, py = W-pw-60, 360
    pip = portrait(pw, ph, PEOPLE[you], head_scale=1.2, key=you)
    rr = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(rr).rounded_rectangle((0,0,pw,ph), radius=44, fill=255)
    base.paste(pip, (px, py), rr)
    d.rounded_rectangle((px,py,px+pw,py+ph), radius=44, outline=(255,255,255), width=6)
    # bottom control bar
    by = H - 360
    d.rounded_rectangle((90, by, W-90, by+220), radius=110, fill=(255,255,255))
    cxs = [W*0.27, W*0.5, W*0.73]
    cy = by+110
    ctrl_button(d, (int(cxs[0]),cy), 70, (0xF0,0xF0,0xF2), "mic", NEAR_BLACK)
    ctrl_button(d, (int(cxs[1]),cy), 70, (0xF0,0xF0,0xF2), "flip", NEAR_BLACK)
    ctrl_button(d, (int(cxs[2]),cy), 70, RED, "end", base=base)
    base.save(f"{OUT}/05_APP_IPHONE_6_9_06-incall-video.png")
    print("wrote 05 incall-video")

def scene_group(time="08:31"):
    base = Image.new("RGB", (W, H), (255,255,255))
    d = ImageDraw.Draw(base)
    status_bar(d, time="4:25")
    d.text((W//2, 220), "Group call", font=font(64), fill=NEAR_BLACK, anchor="mm")
    d.text((W//2, 292), "4 people", font=font(44), fill=GRAY, anchor="mm")
    # 2x2 grid
    # Names chosen to match each AI face's apparent gender.
    keys = ["daniela","isla","grace","ben"]
    names = ["Sofia","Isla","Mia","Ben"]
    gx, gy = 70, 400
    gw = (W - 3*70)//2
    gh = int(gw*1.18)
    gap = 70
    for i,(k,nm) in enumerate(zip(keys,names)):
        r, c = divmod(i, 2)
        x = gx + c*(gw+gap)
        y = gy + r*(gh+gap)
        tile = portrait(gw, gh, PEOPLE[k], head_scale=1.05, key=k)
        rr = Image.new("L",(gw,gh),0)
        ImageDraw.Draw(rr).rounded_rectangle((0,0,gw,gh), radius=40, fill=255)
        base.paste(tile,(x,y),rr)
        d.rounded_rectangle((x,y,x+gw,y+gh), radius=40, outline=(0xEC,0xEC,0xEE), width=3)
        # name chip
        d.rounded_rectangle((x+24, y+gh-66, x+24+len(nm)*26+40, y+gh-22), radius=22, fill=(255,255,255))
        d.text((x+44, y+gh-44), nm, font=font(34), fill=NEAR_BLACK, anchor="lm")
    # end button
    cy = gy + 2*gh + gap + 130
    ctrl_button(d, (W//2, cy), 78, RED, "end", base=base)
    base.save(f"{OUT}/06_APP_IPHONE_6_9_07-incall-audio.png")
    print("wrote 06 group call")

def scene_incoming(person_key="grace", name="Grace Lin", time="4:25"):
    base = Image.new("RGB", (W, H), (255,255,255))
    d = ImageDraw.Draw(base)
    status_bar(d, time=time)
    # big round portrait
    r = 230
    round_avatar(base, (W//2, 760), r, PEOPLE[person_key], key=person_key)
    d.ellipse((W//2-r, 760-r, W//2+r, 760+r), outline=(0xEC,0xEC,0xEE), width=3)
    d = ImageDraw.Draw(base)
    d.text((W//2, 1130), name, font=font(86), fill=NEAR_BLACK, anchor="mm")
    d.text((W//2, 1230), "Incoming video call", font=font(50), fill=GRAY, anchor="mm")
    # decline / accept
    cy = H - 560
    ctrl_button(d, (int(W*0.30), cy), 95, RED, "end", base=base)
    ctrl_button(d, (int(W*0.70), cy), 95, NEAR_BLACK, "video")
    d.text((int(W*0.30), cy+150), "DECLINE", font=font(38), fill=GRAY, anchor="mm")
    d.text((int(W*0.70), cy+150), "ACCEPT", font=font(38), fill=GRAY, anchor="mm")
    base.save(f"{OUT}/07_APP_IPHONE_6_9_08-incoming.png")
    print("wrote 07 incoming")

def regen_variants():
    """For each base 6.9 shot, regenerate the 6.5 and iPad 12.9 variants."""
    import glob
    for f in glob.glob(f"{OUT}/*_APP_IPHONE_6_9_*.png"):
        im = Image.open(f).convert("RGB")
        b = os.path.basename(f)
        im.resize((1242,2688), Image.LANCZOS).save(f"{OUT}/{b.replace('APP_IPHONE_6_9','APP_IPHONE_65')}")
        IW,IH = 2048,2732
        th = int(IH*0.88); ratio = th/im.height; tw = int(im.width*ratio)
        if tw > int(IW*0.92):
            tw = int(IW*0.92); ratio = tw/im.width; th = int(im.height*ratio)
        ph = im.resize((tw,th), Image.LANCZOS)
        cv = Image.new("RGB",(IW,IH),(255,255,255)); cv.paste(ph,((IW-tw)//2,(IH-th)//2))
        cv.save(f"{OUT}/{b.replace('APP_IPHONE_6_9','APP_IPAD_PRO_3GEN_129')}")
    print("regenerated all 6.5 + iPad variants")

if __name__ == "__main__":
    # person_key picks the AI face; name matches its apparent gender.
    scene_incall_video(person_key="daniela", name="Sofia Reyes", you="alex")
    scene_group()
    scene_incoming(person_key="grace", name="Mia Carter")
    regen_variants()
    print("done")
