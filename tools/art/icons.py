#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4 图标 / 道具 / 弹道图集生成器（icons agent）。

产出（尺寸必须精确，直接写 assets/）：
    assets/icons/weapons.png        160x128   5 列 x 4 行 32x32，顺序 = data/weapons.json
    assets/icons/passives.png       160x128   5 列 x 4 行 32x32，顺序 = data/passives.json
    assets/sprites/props.png        128x16    8 格 16x16（gem0-3 / coin / coal / 空 / 空）
    assets/sprites/projectiles.png  128x128   8 行 x 8 帧 16x16
                                （stone/arrow/flame/blade/note/water/shock/spark）

预览（tools/out/，验收用）：
    prev_icons.png   4x 拼图（四张图集全在里面）
    prev_w.png / prev_p.png / prev_proj.png / prev_props.png  单图 4x/8x
    prev_1x.png      1x 实际大小，深色地面

跑法：cd 项目根 && python3 tools/art/icons.py
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from artbase import *  # noqa: E402,F401,F403  rct/ell/ln/poly/outline/validate/hx/dark/light/mix

CLEAR = (0, 0, 0, 0)
ICON = 32
PROP = 16
OUT = os.path.join(ROOT, "tools", "out")

# ------------------------------------------------------------------ 追加调色
STONE = hx("#A8B2BE"); STONE_D = hx("#5E6876"); STONE_L = hx("#E4ECF4")
CYAN = hx("#7FD9F2"); CYAN_D = hx("#2E7E9E"); CYAN_L = hx("#DFF7FF")
VIO = hx("#B98CE8"); VIO_D = hx("#6B4A9E"); VIO_L = hx("#EBDCFF")
BLOOD2 = hx("#A83232"); BLOOD_L = hx("#D4634C"); BLOOD_D = hx("#6E1E1E")
GEMS = [hx("#3F7FD9"), hx("#8E4FD9"), hx("#D9B45A"), hx("#E2622F")]
GEM_D = [dark(c, 0.60) for c in GEMS]
GEM_L = [light(c, 1.55) for c in GEMS]
NETC = hx("#CBD9E4")
WOOD = hx("#7A5738")
GREEN_D = dark(hx("#3E6B4F"), 0.55)
STEEL_L = light(hx("#C0C8D2"), 1.22)
WHITE = hx("#F8FCFF")

# ------------------------------------------------------------------ 基础工具
def C(w=ICON, h=ICON):
    """新建一格画布，返回 (Image, Draw)。"""
    im = Image.new("RGBA", (w, h), CLEAR)
    return im, ImageDraw.Draw(im)


def erct(d, x0, y0, x1, y1):
    d.rectangle([int(x0), int(y0), int(x1), int(y1)], fill=CLEAR)


def eell(d, x0, y0, x1, y1):
    d.ellipse([int(x0), int(y0), int(x1), int(y1)], fill=CLEAR)


def ring(d, cx, cy, r, col, th=1):
    ell(d, cx - r, cy - r, cx + r, cy + r, col)
    eell(d, cx - r + th, cy - r + th, cx + r - th, cy + r - th)


def taper(d, pts, r0, r1, col):
    """沿折线画渐细的管（用一串圆填）。"""
    n = max(1, len(pts) - 1)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[i + 1]
        steps = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) * 2))
        for s in range(steps + 1):
            t = s / steps
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            r = r0 + (r1 - r0) * ((i + t) / n)
            if r < 0.45:
                px(d, round(x), round(y), col)
            else:
                ell(d, x - r, y - r, x + r, y + r, col)


def tube(d, pts, r0, r1, base, hi=None):
    """三阶管：右下暗边 + 本体 + 左上高光。"""
    taper(d, [(x + 0.85, y + 0.85) for x, y in pts], r0, r1, dark(base, 0.62))
    taper(d, pts, r0, r1, base)
    hi = hi or light(base, 1.32)
    taper(d, [(x - 0.7, y - 0.7) for x, y in pts],
          max(0.35, r0 * 0.42), max(0.35, r1 * 0.42), hi)


def ball(d, cx, cy, r, base, hi=None, dk=None):
    """三阶球：光来自左上。"""
    ell(d, cx - r, cy - r, cx + r, cy + r, base)
    hi = hi or light(base, 1.4)
    dk = dk or dark(base, 0.60)
    lx, ly = -0.62, -0.78
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            dd = math.hypot(x - cx, y - cy)
            if dd > r + 0.15:
                continue
            t = ((x - cx) * lx + (y - cy) * ly) / max(0.7, r)
            if t > 0.34:
                px(d, x, y, hi)
            elif t < -0.50:
                px(d, x, y, dk)


def crescent(d, cx, cy, r, w, a0, a1, col, steps=26):
    """月牙带：两端收尖。"""
    out, inn = [], []
    for k in range(steps + 1):
        t = k / steps
        a = a0 + (a1 - a0) * t
        ww = w * (math.sin(math.pi * t) ** 0.55)
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        inn.append((cx + (r - ww) * math.cos(a), cy + (r - ww) * math.sin(a)))
    poly(d, out + inn[::-1], col)


def arc_band(d, cx, cy, r, w, a0, a1, col, steps=18):
    o, i = [], []
    for k in range(steps + 1):
        a = a0 + (a1 - a0) * k / steps
        o.append((cx + (r + w / 2.0) * math.cos(a), cy + (r + w / 2.0) * math.sin(a)))
        i.append((cx + (r - w / 2.0) * math.cos(a), cy + (r - w / 2.0) * math.sin(a)))
    poly(d, o + i[::-1], col)


def star(d, x, y, r, col, core=None):
    ln(d, x - r, y, x + r, y, col)
    ln(d, x, y - r, x, y + r, col)
    if r >= 3:
        for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
            px(d, x + dx, y + dy, col)
    if core:
        px(d, x, y, core)


def glow_ring(im, col=GOLD_L):
    """沿外轮廓再垫 1px 亮环（果子的光晕）。"""
    a = im.split()[3]
    dil = a.filter(ImageFilter.MaxFilter(3))
    base = Image.new("RGBA", im.size, col)
    base.putalpha(dil)
    out = Image.new("RGBA", im.size, CLEAR)
    out.alpha_composite(base)
    out.alpha_composite(im)
    return out


def fit_cell(im, size, margin):
    """把描边前的内容平移进安全区；放不下就报 TOO_BIG。"""
    bb = im.getbbox()
    if bb is None:
        return im, None
    lo, hi = margin, size - 1 - margin
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    if w > hi - lo + 1 or h > hi - lo + 1:
        return im, ("TOO_BIG", bb, w, h)
    ox = oy = 0
    if bb[0] < lo:
        ox = lo - bb[0]
    elif bb[2] > hi + 1:
        ox = hi + 1 - bb[2]
    if bb[1] < lo:
        oy = lo - bb[1]
    elif bb[3] > hi + 1:
        oy = hi + 1 - bb[3]
    if ox or oy:
        out = Image.new("RGBA", im.size, CLEAR)
        out.alpha_composite(im, (ox, oy))
        return out, None
    return im, None


def layers(fns, size=ICON):
    """多层：每层单独描边后叠加（交叉物体之间才分得开）。"""
    out = Image.new("RGBA", (size, size), CLEAR)
    for fn in fns:
        ci, d = C(size, size)
        fn(d)
        out.alpha_composite(outline(ci, diag=False))
    return out


# ================================================================== 武器（20）
def w_sling(d):
    # 顶部指环
    ring(d, 16, 4, 2, LEATHER_L, 1)
    # 两根皮绳张开成 V
    tube(d, [(15, 6), (12, 13), (9, 20)], 0.5, 0.5, LEATHER_L)
    tube(d, [(17, 6), (20, 13), (23, 20)], 0.5, 0.5, LEATHER_L)
    # 皮兜（浅碗）
    poly(d, [(9, 19), (23, 19), (21, 25), (16, 27), (11, 25)], LEATHER)
    rct(d, 10, 19, 22, 20, LEATHER_L)
    rct(d, 12, 24, 20, 25, dark(LEATHER, 0.62))
    px(d, 10, 21, light(LEATHER, 1.35))
    px(d, 22, 21, dark(LEATHER, 0.8))
    # 兜里的石弹（压在碗沿上）
    ball(d, 16, 16, 3.2, STONE, STONE_L, STONE_D)
    px(d, 14, 14, WHITE)


def w_staff(d):
    pts = [(16, 28), (16, 22), (15, 16), (15, 11), (14, 8), (12, 5), (9, 4),
           (7, 6), (7, 9), (9, 11), (11, 10)]
    tube(d, pts, 1.0, 1.0, BROWN, TAN)
    rct(d, 14, 18, 16, 20, GOLD)
    px(d, 15, 19, GOLD_L)
    px(d, 16, 26, TAN)


def w_torch(d):
    rct(d, 14, 15, 16, 29, BROWN)
    rct(d, 14, 15, 14, 29, dark(BROWN, 0.62))
    rct(d, 16, 15, 16, 29, TAN)
    rct(d, 13, 14, 17, 16, BRONZE)
    px(d, 13, 15, GOLD_L)
    # 火焰
    poly(d, [(15, 15), (11, 12), (12, 8), (15, 6), (14, 2), (17, 3), (19, 6),
             (21, 9), (20, 13), (17, 15)], FLAME_R)
    poly(d, [(15, 14), (13, 12), (14, 9), (16, 7), (17, 9), (18, 11), (17, 14)], FLAME_O)
    poly(d, [(15, 13), (14, 11), (16, 9), (16, 12)], FLAME)
    px(d, 16, 10, HOLY)


def w_horn(d):
    pts = [(7, 27), (8, 23), (11, 19), (15, 15), (19, 11), (21, 8)]
    tube(d, pts, 0.9, 2.6, BRONZE, GOLD_L)
    # 喇叭口：金圈 + 朝右上的暗内腔
    ell(d, 17, 2, 27, 11, GOLD)
    ell(d, 20, 4, 26, 9, dark(BRONZE, 0.38))
    px(d, 21, 5, dark(BRONZE, 0.24))
    # 口沿高光
    px(d, 18, 3, GOLD_L); px(d, 19, 2, GOLD_L); px(d, 17, 5, GOLD_L)
    px(d, 18, 10, light(GOLD, 1.2))
    # 羊角箍（三道金环）
    taper(d, [(8.6, 22.6), (10.2, 21.4)], 1.5, 1.5, GOLD_D)
    taper(d, [(12.4, 18.4), (14.0, 17.2)], 1.8, 1.8, GOLD_D)
    taper(d, [(16.4, 14.0), (18.2, 12.8)], 2.1, 2.1, GOLD_D)
    px(d, 8, 25, light(BRONZE, 1.2))
    # 吹口
    px(d, 6, 28, GOLD_D)


def w_censer(d):
    # 顶环 + 三条吊链
    ring(d, 16, 4, 2.2, GOLD, 1)
    ln(d, 15, 6, 9, 15, GOLD_D)
    ln(d, 16, 6, 16, 14, GOLD_D)
    ln(d, 17, 6, 23, 15, GOLD_D)
    px(d, 10, 13, GOLD_L)
    # 香炉碗（上宽下收 + 尖底）
    poly(d, [(8, 15), (24, 15), (21, 24), (16, 26), (11, 24)], GOLD)
    rct(d, 8, 15, 24, 16, GOLD_L)
    poly(d, [(12, 23), (20, 23), (16, 26)], GOLD_D)
    px(d, 9, 17, light(GOLD, 1.20))
    px(d, 23, 18, dark(GOLD, 0.80))
    # 碗中炭火
    ell(d, 11, 12, 21, 15, FLAME_O)
    px(d, 13, 14, FLAME)
    px(d, 16, 14, HOLY)
    px(d, 19, 14, FLAME_R)
    # 金烟（左侧升起）
    for x, y in ((8, 10), (6, 7), (7, 4)):
        ell(d, x - 1, y - 1, x + 1, y + 1, light(GOLD, 1.5))
    px(d, 5, 3, HOLY)


def w_harp(d):
    poly(d, [(8, 22), (24, 22), (22, 29), (10, 29)], BROWN)
    rct(d, 9, 22, 23, 23, TAN)
    rct(d, 10, 28, 22, 29, dark(BROWN, 0.6))
    tube(d, [(10, 22), (11, 17), (13, 11), (14, 6)], 0.9, 0.9, BROWN, TAN)
    tube(d, [(22, 22), (21, 17), (19, 11), (18, 6)], 0.9, 0.9, BROWN, TAN)
    rct(d, 13, 5, 19, 6, GOLD)
    px(d, 14, 5, GOLD_L)
    for x, c in ((14, GOLD_L), (16, GOLD_L), (18, GOLD_L), (15, GOLD_D), (17, GOLD_D)):
        ln(d, x, 7, x, 21, c)


def w_olive(d):
    tube(d, [(6, 27), (11, 22), (16, 17), (21, 12), (25, 7)], 0.55, 0.55, GREEN_D)
    for x, y, s in ((9, 25, -1), (13, 25, 1), (12, 20, -1), (16, 21, 1),
                    (16, 15, -1), (20, 16, 1), (20, 11, -1), (24, 12, 1)):
        ox = 0 if s < 0 else 1
        ell(d, x - 2 + ox, y - 1, x + 1 + ox, y + 2, OLIVE)
        px(d, x + ox, y, light(OLIVE, 1.35))
    ell(d, 6, 16, 10, 21, hx("#3A3A22"))
    px(d, 7, 17, hx("#8A8550"))
    ell(d, 21, 3, 25, 8, hx("#3A3A22"))
    px(d, 22, 4, hx("#8A8550"))


def w_jawbone(d):
    # 骨体：斜向弯管
    pts = [(9, 9), (13, 13), (18, 17), (23, 20)]
    tube(d, pts, 1.9, 1.6, mix(LINEN, TAN, 0.18), HOLY)
    # 关节头
    ball(d, 7, 7, 2.6, LINEN, HOLY, dark(LINEN, 0.78))
    # 一排牙（朝下）
    for i in range(5):
        t = 0.14 + i * 0.19
        x = 9 + (23 - 9) * t
        y = 9 + (20 - 9) * t
        poly(d, [(x, y + 1), (x + 2, y + 1), (x + 1, y + 5)], light(LINEN, 1.04))
        px(d, x + 1, y + 4, light(LINEN, 0.9))
        px(d, x + 1, y + 2, dark(LINEN, 0.7))
    # 齿根缝
    ln(d, 12, 12, 13, 13, dark(LINEN, 0.72))
    ln(d, 18, 16, 19, 17, dark(LINEN, 0.72))
    px(d, 8, 6, WHITE)
    # 下颌末端
    ball(d, 24, 21, 1.8, LINEN, HOLY, dark(LINEN, 0.7))


def w_tambourine(d):
    skin = hx("#D9C08C")
    # 木框（外暗内亮三层）
    ell(d, 4, 4, 28, 28, dark(BROWN, 0.80))
    ell(d, 5, 5, 27, 27, BROWN)
    # 皮面
    ell(d, 8, 8, 24, 24, skin)
    ell(d, 9, 9, 23, 23, light(skin, 1.06))
    # 皮面高光 & 钉帽
    px(d, 11, 10, light(skin, 1.30)); px(d, 12, 11, light(skin, 1.18))
    px(d, 10, 12, light(skin, 1.12))
    for x, y in ((16, 12), (16, 20), (12, 16), (20, 16)):
        px(d, x, y, dark(skin, 0.86))
    # 四对铃片（金，压在框上）
    for x, y in ((16, 5), (16, 26), (5, 16), (26, 16)):
        rct(d, x - 2, y - 1, x + 2, y + 1, GOLD)
        px(d, x, y, dark(GOLD_D, 0.82))
        px(d, x - 1, y - 1, GOLD_L)
        px(d, x - 2, y, GOLD_L)
    # 框上高光（左上）
    px(d, 8, 7, light(BROWN, 1.4)); px(d, 7, 8, light(BROWN, 1.4))
    px(d, 6, 10, light(BROWN, 1.15))


def w_sickle(d):
    # 木柄（从左下伸出）
    tube(d, [(9, 21), (7, 24), (6, 27)], 1.5, 1.2, BROWN, TAN)
    px(d, 6, 25, light(TAN, 1.1))
    px(d, 8, 22, dark(BROWN, 0.7))
    # 弯刃：外缘 r=10 的内弧刀，开口朝左
    crescent(d, 17, 15, 10.0, 4.6, -0.60, 2.65, STEEL)
    crescent(d, 17, 15, 9.5, 1.8, -0.45, 2.50, HOLY)
    crescent(d, 17, 15, 5.7, 1.1, -0.15, 2.25, dark(STEEL, 0.68))
    px(d, 25, 9, WHITE)
    px(d, 26, 11, STEEL_L)


def w_spirit_blade(d):
    poly(d, [(16, 2), (18, 6), (18, 19), (16, 22), (14, 19), (14, 6)], STEEL)
    rct(d, 14, 6, 14, 19, light(STEEL, 1.14))
    rct(d, 18, 6, 18, 19, dark(STEEL, 0.76))
    rct(d, 16, 4, 16, 20, HOLY)
    px(d, 16, 3, HOLY_B)
    rct(d, 9, 21, 23, 22, GOLD)
    rct(d, 9, 21, 23, 21, GOLD_L)
    rct(d, 9, 19, 10, 22, GOLD)
    rct(d, 22, 19, 23, 22, GOLD)
    rct(d, 15, 23, 17, 26, LEATHER)
    px(d, 16, 24, BROWN)
    px(d, 16, 25, BROWN)
    ell(d, 14, 26, 18, 29, GOLD)
    px(d, 15, 27, GOLD_L)


def w_menorah(d):
    poly(d, [(10, 29), (22, 29), (20, 26), (12, 26)], GOLD)
    rct(d, 11, 28, 21, 29, GOLD_D)
    rct(d, 15, 14, 16, 26, GOLD)
    rct(d, 15, 14, 15, 26, GOLD_L)
    tube(d, [(4, 18), (8, 19.6), (12, 20), (16, 20), (20, 20), (24, 19.6), (28, 18)],
         0.75, 0.75, GOLD_D, GOLD)
    for x in (4, 8, 12, 20, 24, 28):
        rct(d, x, 13, x, 19, GOLD)
        px(d, x, 13, GOLD_L)
    rct(d, 15, 12, 16, 13, GOLD_L)
    for x in (4, 8, 12, 16, 20, 24, 28):
        rct(d, x - 1, 11, x, 12, FLAME_O)
        px(d, x, 10, FLAME)
        px(d, x, 9, HOLY)


def w_serpent(d):
    rct(d, 15, 10, 17, 29, BROWN)
    rct(d, 15, 10, 15, 29, dark(BROWN, 0.62))
    rct(d, 17, 10, 17, 29, TAN)
    poly(d, [(11, 29), (21, 29), (19, 26), (13, 26)], BROWN)
    pts = [(13, 26), (10, 22), (12, 18), (16, 16), (20, 13), (22, 9), (19, 5), (16, 6)]
    tube(d, pts, 0.85, 1.5, BRONZE, GOLD_L)
    ell(d, 13, 2, 19, 8, BRONZE)
    ell(d, 14, 3, 18, 7, light(BRONZE, 1.18))
    px(d, 15, 4, OUTLINE)
    px(d, 16, 4, GOLD_L)
    ln(d, 12, 6, 9, 7, RED_D)


def w_chariot(d):
    # 车轮（左下，四辐 + 金毂；右半被车厢压住）
    ring(d, 11, 20, 6.2, IRON, 2)
    for a in (0, 45, 90, 135):
        r = math.radians(a)
        ln(d, 11 + 1.4 * math.cos(r), 20 + 1.4 * math.sin(r),
           11 + 4.6 * math.cos(r), 20 + 4.6 * math.sin(r), IRON_D)
    ball(d, 11, 20, 1.8, GOLD, GOLD_L, GOLD_D)
    # 轮缘受光
    for x, y in ((6, 15), (7, 14), (9, 13), (5, 18), (5, 20)):
        px(d, x, y, STEEL_L)
    px(d, 6, 25, STEEL)
    px(d, 15, 26, STEEL)
    # 车厢（盖住轮的右半）
    poly(d, [(14, 11), (27, 10), (27, 20), (14, 21)], CRIMSON)
    rct(d, 14, 11, 27, 12, light(CRIMSON, 1.34))
    rct(d, 14, 19, 27, 21, dark(CRIMSON, 0.62))
    rct(d, 14, 15, 27, 15, GOLD_D)
    px(d, 17, 13, GOLD_L)
    px(d, 22, 13, GOLD_L)
    px(d, 25, 13, GOLD)
    px(d, 15, 17, light(CRIMSON, 1.20))
    # 车辕
    rct(d, 27, 17, 29, 18, WOOD)
    # 车头火（三舌）
    poly(d, [(15, 11), (17, 3), (19, 7), (21, 2), (23, 6), (25, 4), (26, 11)], FLAME_O)
    poly(d, [(17, 11), (19, 6), (21, 8), (22, 5), (24, 11)], FLAME)
    px(d, 20, 6, HOLY)
    px(d, 22, 9, HOLY)


def w_hammer(d):
    # 铁锤头（八角形）
    poly(d, [(8, 5), (24, 5), (26, 7), (26, 13), (24, 15), (8, 15), (6, 13), (6, 7)], IRON)
    rct(d, 8, 5, 24, 6, STEEL)
    rct(d, 7, 13, 25, 14, dark(IRON, 0.64))
    rct(d, 6, 7, 7, 13, dark(IRON, 0.76))
    rct(d, 23, 6, 25, 8, light(IRON, 1.10))
    # 铆钉
    rct(d, 10, 9, 11, 11, STEEL_L)
    rct(d, 19, 9, 20, 11, STEEL_L)
    px(d, 10, 9, WHITE)
    px(d, 19, 9, WHITE)
    # 木柄
    rct(d, 14, 14, 17, 28, LEATHER_L)
    rct(d, 14, 14, 14, 28, LEATHER)
    rct(d, 17, 14, 17, 28, light(LEATHER_L, 1.20))
    rct(d, 13, 26, 18, 28, LEATHER)
    px(d, 15, 17, LEATHER)
    px(d, 15, 20, LEATHER)
    px(d, 15, 23, LEATHER)


def w_scepter(d):
    # 长杆
    tube(d, [(9, 28), (13, 22), (17, 17), (21, 12)], 0.95, 0.85, GOLD, GOLD_L)
    # 缠金握把
    ln(d, 11, 22, 13, 24, GOLD_D)
    ln(d, 14, 19, 16, 21, GOLD_D)
    # 顶端圆球
    ball(d, 23, 7, 4.2, GOLD, GOLD_L, GOLD_D)
    px(d, 21, 4, WHITE)
    # 球下托盘
    rct(d, 19, 11, 22, 12, GOLD_D)
    px(d, 20, 11, GOLD_L)
    # 底部小坠
    ball(d, 8, 28, 1.5, GOLD_D, GOLD, dark(GOLD, 0.62))
    px(d, 7, 27, GOLD)


def w_blood(d):
    poly(d, [(16, 3), (20, 10), (22, 15), (22, 19), (19, 24), (16, 26), (13, 24),
             (10, 19), (10, 15), (13, 10)], BLOOD2)
    rct(d, 12, 12, 13, 22, BLOOD_L)
    px(d, 13, 10, BLOOD_L)
    px(d, 14, 8, BLOOD_L)
    rct(d, 21, 14, 22, 21, BLOOD_D)
    rct(d, 18, 22, 20, 24, BLOOD_D)
    ell(d, 8, 24, 24, 28, hx("#7A1E1E"))
    rct(d, 9, 26, 23, 27, hx("#8E2626"))
    px(d, 12, 25, hx("#B03A3A"))
    # 两颗小血滴
    poly(d, [(7, 12), (9, 16), (7, 19), (5, 16)], BLOOD2)
    poly(d, [(25, 5), (27, 8), (25, 10), (23, 8)], BLOOD2)


def w_voice(d):
    for r, w, col in ((5, 2.2, CYAN_L), (10, 2.2, CYAN), (15.5, 2.2, CYAN_D)):
        arc_band(d, 9, 16, r, w, -0.86, 0.86, col)
    ell(d, 4, 14, 7, 18, CYAN_L)
    px(d, 5, 15, WHITE)
    px(d, 4, 16, CYAN)


def w_net(d):
    ring(d, 16, 16, 11, TAN, 1)
    for off in (-6, -3, 0, 3, 6):
        dx = math.sqrt(max(0.2, (121.0 - off * off / 2.0) / 2.0))
        ln(d, 16 + off - dx, 16 - dx, 16 + off + dx, 16 + dx, NETC)
        ln(d, 16 + off - dx, 16 + dx, 16 + off + dx, 16 - dx, NETC)
    for x, y in ((16, 5), (5, 16), (27, 16)):
        rct(d, x - 1, y - 1, x + 1, y + 1, GOLD_D)
        px(d, x, y, GOLD_L)
    # 底坠
    for x in (10, 16, 22):
        rct(d, x, 26, x, 28, IRON_D)
        px(d, x, 29, IRON)


def _key(d, bx, by, tx, ty, col, hi):
    ring(d, bx, by, 3, col, 1)
    tube(d, [(bx, by), (tx, ty)], 0.85, 0.85, col, hi)
    dx, dy = tx - bx, ty - by
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    nx, ny = -uy, ux
    for t, k in ((0.70, 3.2), (0.86, 2.4)):
        sx, sy = bx + dx * t, by + dy * t
        tube(d, [(sx, sy), (sx + nx * k, sy + ny * k)], 0.6, 0.6, col, hi)
    px(d, tx, ty, hi)


def w_keys(d):
    return layers([
        lambda dd: _key(dd, 21, 6, 12, 26, GOLD_D, GOLD),
        lambda dd: _key(dd, 11, 6, 20, 26, GOLD, GOLD_L),
    ])


# ================================================================== 被动（20）
def p_love(d):
    ball(d, 16, 18, 8, hx("#C0392E"), hx("#E8705C"), hx("#7A1F18"))
    ln(d, 16, 8, 17, 11, BROWN)
    ell(d, 17, 6, 22, 9, GREEN)
    px(d, 18, 7, light(GREEN, 1.4))
    px(d, 11, 13, hx("#F2A090"))


def p_joy(d):
    ln(d, 16, 5, 16, 10, BROWN)
    ell(d, 17, 4, 22, 7, GREEN)
    for x, y in ((13, 12), (18, 12), (11, 16), (16, 16), (21, 16), (13, 21), (18, 21), (16, 25)):
        ball(d, x, y, 2.6, GOLD, GOLD_L, GOLD_D)


def p_peace(d):
    body = hx("#C2CB72")
    ell(d, 8, 14, 24, 28, body)
    ell(d, 12, 7, 20, 19, body)
    rct(d, 10, 16, 10, 26, light(body, 1.10))
    rct(d, 22, 16, 23, 26, dark(body, 0.86))
    ln(d, 16, 6, 16, 9, BROWN)
    ell(d, 16, 5, 21, 8, GREEN)


def p_patience(d):
    tube(d, [(6, 27), (12, 21), (18, 14), (24, 8)], 0.55, 0.55, GREEN_D)
    for x, y in ((10, 15), (17, 21)):
        ball(d, x, y, 3, hx("#6E7A3A"), hx("#B0B67A"), hx("#414A22"))
    for x, y in ((14, 25), (20, 11)):
        ell(d, x - 2, y - 1, x + 1, y + 2, OLIVE)
        px(d, x, y, light(OLIVE, 1.3))


def p_kindness(d):
    # 石榴：红皮 + 顶冠 + 剖开的籽
    ball(d, 16, 20, 8, hx("#B0453A"), hx("#DE7A62"), hx("#6E2018"))
    poly(d, [(13, 12), (14, 7), (16, 10), (18, 7), (19, 12)], hx("#8E3028"))
    px(d, 16, 8, hx("#C05A48"))
    ell(d, 11, 16, 21, 25, hx("#F2C6AE"))
    for x, y in ((13, 18), (16, 17), (19, 18), (14, 21), (18, 21), (16, 23)):
        px(d, x, y, hx("#C02828"))
        px(d, x, y + 1, hx("#8E1A1A"))
        px(d, x + 1, y, hx("#E85A4A"))
    px(d, 11, 13, hx("#E89A82"))


def p_goodness(d):
    ball(d, 16, 18, 8, hx("#D9A83C"), hx("#F8DE92"), hx("#8E6418"))
    ln(d, 16, 8, 17, 11, BROWN)
    ell(d, 17, 6, 22, 9, GREEN)
    ln(d, 16, 12, 16, 24, hx("#B0821E"))
    px(d, 11, 13, hx("#FCEFC0"))


def p_faithfulness(d):
    # 无花果（对剖，露出瓤与籽）
    skin = hx("#5A3468")
    poly(d, [(16, 7), (21, 10), (23, 16), (21, 23), (16, 27), (11, 23), (9, 16),
             (11, 10)], skin)
    rct(d, 10, 12, 11, 21, hx("#7E4E8E"))
    rct(d, 21, 15, 22, 23, hx("#3E2050"))
    ell(d, 11, 11, 21, 25, hx("#D0685E"))
    ln(d, 16, 12, 16, 23, hx("#A8403C"))
    for x, y in ((13, 14), (18, 14), (12, 18), (16, 17), (20, 18), (14, 22), (18, 22)):
        px(d, x, y, hx("#F2C0AE"))
    px(d, 15, 6, GREEN)
    px(d, 16, 5, GREEN)
    px(d, 14, 11, hx("#9E76AE"))


def p_gentleness(d):
    ball(d, 16, 19, 8, hx("#E8A08C"), hx("#FAC8B8"), hx("#A85A48"))
    ln(d, 16, 11, 16, 27, hx("#C87A66"))
    ell(d, 16, 6, 22, 10, GREEN)
    px(d, 17, 7, light(GREEN, 1.4))
    px(d, 11, 14, hx("#FCE0D4"))


def p_self_control(d):
    # 紫李：圆果 + 果沟 + 白霜 + 叶
    ball(d, 16, 19, 8, hx("#6A3E8E"), hx("#A87CC8"), hx("#38204E"))
    ln(d, 16, 12, 15, 26, hx("#3E2450"))
    ln(d, 17, 12, 17, 25, hx("#8A5EA8"))
    ln(d, 16, 8, 17, 12, BROWN)
    ell(d, 17, 5, 22, 9, GREEN)
    px(d, 18, 6, light(GREEN, 1.4))
    px(d, 11, 14, hx("#C8B0DC"))
    px(d, 12, 16, hx("#B8A0C8"))


def p_belt(d):
    tube(d, [(7, 20), (16, 18), (24, 16)], 2.4, 2.4, LEATHER, LEATHER_L)
    # 带尾
    poly(d, [(7, 22), (9, 21), (8, 26), (6, 25)], LEATHER)
    # 金扣
    rct(d, 13, 13, 19, 21, GOLD)
    erct(d, 15, 15, 17, 19)
    rct(d, 13, 13, 19, 14, GOLD_L)
    rct(d, 15, 16, 17, 16, GOLD_D)
    px(d, 16, 18, GOLD_D)


def p_breastplate(d):
    body = mix(BRONZE, GOLD, 0.28)
    # 胸甲本体：宽肩 + 收腰 + 尖下摆
    poly(d, [(9, 9), (13, 7), (16, 10), (19, 7), (23, 9), (25, 16), (22, 24),
             (16, 27), (10, 24), (7, 16)], body)
    # 肩带
    rct(d, 9, 7, 12, 10, dark(body, 0.80))
    rct(d, 20, 7, 23, 10, dark(body, 0.80))
    # 左亮右暗
    rct(d, 8, 16, 9, 21, light(body, 1.20))
    rct(d, 24, 16, 25, 21, dark(body, 0.70))
    rct(d, 10, 25, 22, 26, dark(body, 0.74))
    # 领口
    poly(d, [(13, 8), (16, 14), (19, 8), (16, 10)], dark(body, 0.62))
    # 中缝 + 金铆钉
    ln(d, 16, 15, 16, 25, dark(body, 0.66))
    px(d, 11, 14, GOLD_L)
    px(d, 21, 14, GOLD_L)
    px(d, 12, 21, GOLD)
    px(d, 20, 21, GOLD)
    # 金边
    ln(d, 10, 24, 22, 24, GOLD_D)
    px(d, 11, 12, light(body, 1.32))
    # 反光面（左上受光块）
    poly(d, [(10, 11), (15, 11), (13, 18), (9, 17)], mix(body, WHITE, 0.30))
    px(d, 12, 12, WHITE)
    px(d, 18, 22, dark(body, 0.55))


def p_gospel_shoes(d):
    red = hx("#9E3630")
    # 鞋底（侧视，前尖后厚）
    poly(d, [(5, 21), (9, 18), (22, 18), (27, 20), (28, 23), (24, 24), (8, 24)],
         red)
    rct(d, 7, 23, 24, 24, dark(red, 0.66))
    px(d, 5, 20, hx("#C05A50"))
    px(d, 26, 19, light(red, 1.25))
    # 鞋面（浅皮，前低后高）
    poly(d, [(9, 18), (13, 12), (18, 11), (23, 13), (24, 18)], LEATHER_L)
    # 金绑带两道
    rct(d, 11, 16, 22, 17, GOLD)
    rct(d, 13, 13, 20, 14, GOLD_D)
    px(d, 15, 11, light(LEATHER_L, 1.30))
    px(d, 19, 18, dark(LEATHER_L, 0.78))
    # 鞋带结
    px(d, 12, 15, GOLD_L)
    px(d, 23, 16, GOLD_L)


def p_shield(d):
    ell(d, 4, 4, 28, 28, TAN)
    ell(d, 5, 5, 27, 27, light(TAN, 1.10))
    ring(d, 16, 16, 10, GOLD_D, 1)
    ring(d, 16, 16, 6, GOLD_D, 1)
    ball(d, 16, 16, 3, GOLD, GOLD_L, GOLD_D)
    for x, y in ((8, 8), (24, 8), (8, 24), (24, 24)):
        px(d, x, y, dark(TAN, 0.55))
    for i in range(5):
        px(d, 6 + i, 6 - min(i, 1) + i, light(TAN, 1.3))


def p_helmet(d):
    poly(d, [(8, 21), (8, 15), (11, 10), (16, 8), (21, 10), (24, 15), (24, 21)], STEEL)
    rct(d, 8, 19, 24, 21, IRON)
    rct(d, 8, 12, 9, 19, dark(STEEL, 0.84))
    rct(d, 23, 12, 24, 19, light(STEEL, 1.06))
    rct(d, 8, 19, 11, 26, IRON)
    rct(d, 21, 19, 24, 26, IRON)
    # 红缨
    poly(d, [(13, 9), (16, 3), (19, 9)], hx("#B03A3A"))
    poly(d, [(14, 9), (16, 5), (17, 9)], hx("#D85A4A"))
    px(d, 16, 4, hx("#F09A86"))
    # 面窗（水平暗槽）
    rct(d, 10, 15, 22, 17, dark(STEEL, 0.42))
    rct(d, 15, 17, 17, 25, STEEL)
    rct(d, 15, 17, 15, 25, light(STEEL, 1.14))
    px(d, 9, 20, light(IRON, 1.2))


def p_spirit_sword(d):
    poly(d, [(16, 4), (19, 9), (19, 20), (16, 22), (13, 20), (13, 9)], light(STEEL, 1.10))
    rct(d, 13, 9, 13, 20, light(STEEL, 1.22))
    rct(d, 19, 9, 19, 20, dark(STEEL, 0.8))
    rct(d, 16, 5, 16, 21, WHITE)
    # 火舌
    poly(d, [(12, 12), (9, 10), (11, 15), (8, 14), (11, 17), (12, 16)], FLAME_O)
    poly(d, [(20, 13), (23, 11), (21, 16), (24, 15), (21, 18), (20, 17)], FLAME_O)
    px(d, 10, 12, FLAME)
    px(d, 22, 14, FLAME)
    rct(d, 10, 21, 22, 22, GOLD)
    rct(d, 10, 21, 22, 21, GOLD_L)
    rct(d, 15, 23, 17, 25, RED_D)
    ell(d, 14, 24, 18, 28, GOLD)
    px(d, 15, 25, GOLD_L)


def p_frankincense(d):
    poly(d, [(9, 22), (23, 22), (21, 27), (11, 27)], GOLD)
    rct(d, 8, 21, 24, 22, GOLD_L)
    rct(d, 11, 25, 21, 27, GOLD_D)
    px(d, 12, 21, HOLY)
    px(d, 16, 20, GOLD_L)
    px(d, 20, 21, HOLY)
    for x, y in ((14, 18), (13, 14), (15, 10), (14, 6), (17, 4)):
        ell(d, x - 1, y - 1, x + 1, y + 1, mix(HOLY, GOLD_L, 0.35))
    px(d, 16, 3, WHITE)


def p_myrrh(d):
    ell(d, 9, 13, 23, 27, hx("#5A3A5A"))
    rct(d, 13, 8, 19, 14, hx("#5A3A5A"))
    rct(d, 13, 8, 13, 14, hx("#8A6A8A"))
    rct(d, 14, 4, 18, 8, TAN)
    rct(d, 13, 8, 19, 9, GOLD)
    rct(d, 11, 16, 12, 24, hx("#9A7A9A"))
    rct(d, 20, 18, 21, 25, hx("#3E2240"))
    px(d, 17, 3, light(TAN, 1.25))


def p_olive_oil(d):
    clay = hx("#A85A32")
    ell(d, 9, 13, 23, 27, clay)
    rct(d, 13, 8, 19, 14, clay)
    rct(d, 12, 7, 20, 8, hx("#8E4626"))
    ell(d, 6, 12, 11, 19, hx("#8E4626"))
    eell(d, 7, 13, 10, 18)
    ell(d, 21, 12, 26, 19, hx("#8E4626"))
    eell(d, 22, 13, 25, 18)
    rct(d, 11, 15, 12, 25, hx("#D08A5A"))
    rct(d, 20, 17, 21, 25, hx("#7A3A20"))
    px(d, 16, 6, GOLD_L)
    ell(d, 15, 4, 17, 7, GOLD)


def p_fine_linen(d):
    poly(d, [(5, 27), (27, 27), (25, 21), (7, 21)], LINEN)
    poly(d, [(7, 21), (25, 21), (23, 15), (9, 15)], light(LINEN, 1.06))
    poly(d, [(9, 15), (23, 15), (21, 9), (11, 9)], LINEN)
    ln(d, 7, 20, 25, 20, dark(LINEN, 0.82))
    ln(d, 9, 14, 23, 14, dark(LINEN, 0.82))
    ln(d, 11, 8, 21, 8, GOLD)
    ln(d, 13, 16, 13, 26, dark(LINEN, 0.9))
    ln(d, 19, 16, 19, 26, dark(LINEN, 0.9))
    px(d, 12, 10, light(LINEN, 1.12))


def p_ephod(d):
    ln(d, 9, 4, 11, 12, GOLD_D)
    ln(d, 23, 4, 21, 12, GOLD_D)
    px(d, 9, 4, GOLD_L)
    px(d, 23, 4, GOLD_L)
    rct(d, 9, 12, 23, 27, GOLD)
    rct(d, 9, 12, 23, 13, GOLD_L)
    rct(d, 9, 26, 23, 27, GOLD_D)
    cols = [RED, BLUE, GREEN, PURPLE, TEAL, CRIMSON, GOLD_L, hx("#7FD9F2"),
            hx("#E8A08C"), STEEL, OLIVE, VIO]
    for r in range(3):
        for c in range(4):
            x = 11 + c * 3
            y = 15 + r * 3
            rct(d, x, y, x + 1, y + 1, cols[r * 4 + c])
    px(d, 16, 14, GOLD_L)


# ================================================================== props（16）
def pr_gem(i):
    def fn(d):
        base, dk, lt = GEMS[i], GEM_D[i], GEM_L[i]
        # 整体轮廓：平顶台面 + 腰线 + 亭部尖底
        poly(d, [(5, 3), (10, 3), (13, 7), (8, 14), (3, 7)], base)
        # 台面（最亮）
        poly(d, [(5, 3), (10, 3), (10, 4), (6, 4)], lt)
        # 左上冠面（亮） / 右上冠面（中）
        poly(d, [(5, 3), (3, 7), (8, 7), (6, 4)], mix(base, WHITE, 0.34))
        poly(d, [(10, 3), (13, 7), (8, 7)], base)
        # 亭部：左亮右暗
        poly(d, [(3, 7), (8, 7), (8, 14)], lt)
        poly(d, [(13, 7), (8, 7), (8, 14)], dk)
        # 腰线
        ln(d, 3, 7, 13, 7, dark(base, 0.60))
        # 3 条高光
        ln(d, 6, 3, 9, 3, WHITE)
        px(d, 5, 5, WHITE)
        ln(d, 4, 8, 6, 11, light(lt, 1.15))
    return fn


def pr_coin(d):
    # 罗马银币（舍客勒）：银盘 + 内圈 + 凸起的杯形浮雕
    ball(d, 8, 8, 5.6, hx("#7C8896"), hx("#A6B2C0"), hx("#4C5664"))
    ring(d, 8, 8, 4.9, hx("#C4D0DE"), 1)
    sh, li = hx("#333A46"), hx("#F8FCFF")
    # 浮雕杯（投影 → 亮面）
    poly(d, [(7, 5), (12, 5), (11, 8), (8, 8)], sh)
    rct(d, 9, 8, 9, 11, sh)
    rct(d, 7, 11, 11, 12, sh)
    poly(d, [(6, 4), (11, 4), (10, 7), (7, 7)], li)
    rct(d, 8, 7, 8, 10, li)
    rct(d, 6, 10, 10, 11, li)
    # 杯口暗槽 + 高光
    rct(d, 7, 5, 10, 5, hx("#7C8896"))
    px(d, 7, 4, WHITE)
    px(d, 5, 3, WHITE)
    px(d, 4, 10, hx("#C8D2DE"))
    px(d, 12, 12, hx("#5A6472"))


def pr_coal(d):
    # 燃烧的火炭：暗红块体 + 亮橙裂芯
    poly(d, [(2, 10), (3, 6), (6, 3), (10, 2), (13, 5), (14, 9), (11, 13), (6, 13)],
         hx("#2A1C1A"))
    poly(d, [(3, 6), (6, 3), (10, 2), (12, 4), (10, 6), (6, 7)], hx("#3E2A26"))
    # 从核心透出的裂缝
    for (x0, y0, x1, y1) in ((5, 9, 8, 8), (8, 8, 10, 11), (8, 8, 12, 6), (8, 8, 6, 5)):
        ln(d, x0, y0, x1, y1, FLAME_R)
    # 橙芯
    rct(d, 7, 7, 9, 9, FLAME_O)
    px(d, 8, 8, FLAME)
    px(d, 8, 7, HOLY)
    # 受光棱面
    px(d, 4, 5, hx("#5A3A30"))
    px(d, 11, 3, hx("#4A3028"))
    px(d, 3, 11, FLAME_R)
    px(d, 12, 11, FLAME_R)


# ================================================================== 弹道（8 行）
def pj_stone(d, i):
    k = i % 4
    ball(d, 8, 8, 4.2, STONE, STONE_L, STONE_D)
    # 两个大凹坑随翻滚旋转
    base = k * (math.pi / 4)
    for rr, off in ((2.0, 0.0), (2.6, 2.6)):
        a = base + off
        x = int(round(8 + rr * math.cos(a)))
        y = int(round(8 + rr * math.sin(a)))
        rct(d, x - 0, y - 0, x + 1, y + 1, STONE_D)
        px(d, x - 1, y - 1, STONE_L)
        px(d, x, y - 1, STONE_L)
        px(d, x + 1, y - 1, STONE_L)
    # 高光棱 + 底缘暗弧
    px(d, 4, 4, WHITE)
    px(d, 5, 4, WHITE)
    px(d, 4, 5, STONE_L)
    for x in (6, 7, 9):
        px(d, x, 12, STONE_D)
    px(d, 5, 5, WHITE)
    px(d, 6, 4, STONE_L)


def pj_arrow(d, i):
    k = i % 4
    # 尾羽（红，斜飞向上）
    poly(d, [(4, 12), (2, 10), (3, 8), (5, 11)], hx("#C0493A"))
    poly(d, [(4, 12), (2, 13), (4, 14), (5, 12)], hx("#C0493A"))
    px(d, 3, 10, hx("#E87A66"))
    # 箭杆（斜 45°）
    ln(d, 3, 13, 10, 6, TAN)
    ln(d, 3, 12, 10, 5, light(TAN, 1.30))
    # 箭镞
    poly(d, [(13, 3), (12, 9), (6, 4)], STEEL)
    px(d, 11, 5, STEEL_L)
    px(d, 9, 6, STEEL_L)
    px(d, 11, 7, dark(STEEL, 0.72))
    if k % 2:
        px(d, 12, 4, WHITE)
    else:
        px(d, 10, 6, WHITE)
    # 飞行拖影（4 帧变化）
    if k in (1, 2):
        for n in range(1, 4 - (k % 2)):
            px(d, 2 - n + 1, 13 + n, dark(TAN, 0.9))
        px(d, 1, 14, hx("#C0493A"))
    elif k == 3:
        px(d, 2, 14, dark(TAN, 0.85))
        px(d, 1, 15, dark(TAN, 0.6))


def pj_flame(d, i):
    k = i % 4
    # 慧尾（拉长，随时间抖动）
    poly(d, [(8, 5), (5, 5 + k % 2), (1, 8), (5, 11 - k % 2), (8, 11)], FLAME_R)
    # 泪滴焰身（前尖后宽）
    poly(d, [(13, 8), (10, 4), (7, 6), (6, 8), (7, 10), (10, 12)], FLAME_O)
    poly(d, [(12, 8), (10, 5), (8, 6), (7, 8), (8, 10), (10, 11)], FLAME)
    px(d, 10, 7, HOLY)
    px(d, 9, 8, HOLY)
    # 火星
    if k % 2:
        px(d, 3, 4, FLAME_O)
        px(d, 6, 13, FLAME_R)
    else:
        px(d, 3, 12, FLAME_O)
        px(d, 7, 3, FLAME_R)


def pj_blade(d, i):
    ang = (i % 8) * math.pi / 4.0 - math.pi / 2
    a0, a1 = ang - 0.90, ang + 0.90
    # 薄刃：两端收尖的月牙 + 白刃口 + 暗内背
    def _arc(rr, n):
        a = ang - 0.95 + 1.90 * (n / 8.0)
        return (8 + rr * math.cos(a), 8 + rr * math.sin(a))
    # 刃身：起端粗、末端收成针（钢）
    taper(d, [_arc(5.0, n) for n in range(9)], 2.0, 0.45, STEEL)
    taper(d, [_arc(5.0, n) for n in range(9)], 1.1, 0.25, mix(STEEL, WHITE, 0.45))
    # 外缘白刃口
    taper(d, [_arc(6.0, n) for n in range(8)], 0.75, 0.25, WHITE)
    # 内缘暗背
    taper(d, [_arc(4.0, n) for n in range(6)], 0.45, 0.20, dark(CYAN, 0.6))


def pj_note(d, i):
    k = i % 4
    r0 = 2.2 + k * 0.40
    # 同心音波弧（由内向外变暗）
    arc_band(d, 3.5, 8, r0, 1.4, -1.00, 1.00, CYAN_L)
    arc_band(d, 3.5, 8, r0 + 2.6, 1.3, -0.95, 0.95, CYAN)
    if k < 3:
        arc_band(d, 3.5, 8, r0 + 5.2, 1.1, -0.90, 0.90, CYAN_D)
    px(d, 3, 7, WHITE)
    px(d, 3, 8, CYAN_L)


def pj_water(d, i):
    k = i % 4
    # 尾迹先画，水珠压在上面
    tail = 2 + (k % 3)
    poly(d, [(7, 5), (tail, 7 - k % 2), (1, 8), (tail, 9 + k % 2), (7, 11)], hx("#54C6EE"))
    poly(d, [(6, 7), (tail + 1, 8), (6, 9)], hx("#9CE4FF"))
    ball(d, 9, 8, 4, hx("#5ACBF0", ), hx("#DFF9FF"), hx("#1E7AAE"))
    px(d, 7, 6, WHITE)
    px(d, 8, 5, hx("#DFF8FF"))
    px(d, 11, 9, hx("#2E86B8"))
    px(d, 12, 7, hx("#BFEFFF"))


def pj_shock(d, i):
    k = i % 4
    r = 2.4 + k * 1.15
    g = k * (math.pi / 2)
    # 开口环：缺口随时间转动
    arc_band(d, 8, 8, r, 1.8, g + 0.50, g + 2 * math.pi - 0.50, VIO_L, steps=26)
    arc_band(d, 8, 8, max(0.9, r - 0.95), 0.8, g + 0.85, g + 2 * math.pi - 0.85,
             WHITE, steps=26)
    if k == 0:
        px(d, 8, 8, WHITE)
    # 环口亮点
    for s in (-1, 1):
        px(d, int(round(8 + r * math.cos(g + s * (math.pi - 0.5)))),
           int(round(8 + r * math.sin(g + s * (math.pi - 0.5)))), WHITE)


def pj_spark(d, i):
    k = i % 4
    r = 5 - (k % 2)
    star(d, 8, 8, r, GOLD_L, HOLY)
    if k % 2:
        px(d, 8, 3, WHITE)
        px(d, 12, 8, FLAME)
        px(d, 8, 13, FLAME_O)
    else:
        px(d, 4, 8, FLAME)
        px(d, 11, 11, FLAME_O)
    px(d, 8, 8, WHITE)


PROJ_ROWS = [
    ("stone", pj_stone), ("arrow", pj_arrow), ("flame", pj_flame), ("blade", pj_blade),
    ("note", pj_note), ("water", pj_water), ("shock", pj_shock), ("spark", pj_spark),
]

# ================================================================== 合成
def w_list():
    return [
        ("sling", w_sling), ("staff", w_staff), ("torch", w_torch), ("horn", w_horn),
        ("censer", w_censer), ("harp", w_harp), ("olive_branch", w_olive), ("jawbone", w_jawbone),
        ("tambourine", w_tambourine), ("sickle", w_sickle), ("spirit_blade", w_spirit_blade),
        ("menorah", w_menorah), ("bronze_serpent", w_serpent), ("chariot", w_chariot),
        ("hammer", w_hammer), ("scepter", w_scepter), ("abel_blood", w_blood),
        ("voice", w_voice), ("fishing_net", w_net), ("heaven_keys", w_keys),
    ]


def p_list():
    return [
        ("love", p_love), ("joy", p_joy), ("peace", p_peace), ("patience", p_patience),
        ("kindness", p_kindness), ("goodness", p_goodness), ("faithfulness", p_faithfulness),
        ("gentleness", p_gentleness), ("self_control", p_self_control),
        ("belt_of_truth", p_belt), ("breastplate", p_breastplate),
        ("gospel_shoes", p_gospel_shoes), ("shield_of_faith", p_shield),
        ("helmet", p_helmet), ("spirit_sword", p_spirit_sword),
        ("frankincense", p_frankincense), ("myrrh", p_myrrh), ("olive_oil", p_olive_oil),
        ("fine_linen", p_fine_linen), ("ephod", p_ephod),
    ]


def build_icon_sheet(items, halo=False):
    im = Image.new("RGBA", (5 * 32, 4 * 32), CLEAR)
    bad = []
    for i, (iid, fn) in enumerate(items):
        ci, d = C(32, 32)
        res = fn(d)
        if isinstance(res, Image.Image):
            ci = res
        ci, err = fit_cell(ci, 32, 3 if halo else 2)
        if err:
            bad.append((iid, err))
        ci = outline(ci, diag=False)
        if halo:
            ci = glow_ring(ci, GOLD_L)
            dd = ImageDraw.Draw(ci)
            star(dd, 5, 6, 2, HOLY)
            star(dd, 27, 22, 2, HOLY)
        im.alpha_composite(ci, ((i % 5) * 32, (i // 5) * 32))
    if bad:
        print("  TOO_BIG:", bad)
    return im


def build_props():
    im = Image.new("RGBA", (8 * 16, 16), CLEAR)
    fns = [pr_gem(0), pr_gem(1), pr_gem(2), pr_gem(3), pr_coin, pr_coal, None, None]
    for i, fn in enumerate(fns):
        if fn is None:
            continue
        ci, d = C(16, 16)
        fn(d)
        ci = outline(ci, diag=False)
        im.alpha_composite(ci, (i * 16, 0))
    return im


def build_projectiles():
    im = Image.new("RGBA", (8 * 16, 8 * 16), CLEAR)
    for r, (rid, fn) in enumerate(PROJ_ROWS):
        for c in range(8):
            ci, d = C(16, 16)
            fn(d, c)
            ci = outline(ci, diag=False)
            im.alpha_composite(ci, (c * 16, r * 16))
    return im


# ---------------------------------------------------------------- 校验 & 预览
def load(rel):
    return Image.open(os.path.join(ROOT, rel)).convert("RGBA")


def check_sheet(path, w, h, cw, ch, allow_empty=(), pad=1):
    im = Image.open(path).convert("RGBA")
    assert im.size == (w, h), "%s 尺寸 %s != %s" % (path, im.size, (w, h))
    cols, rows = w // cw, h // ch
    empties, clipped, lums = [], [], []
    for r in range(rows):
        for c in range(cols):
            idx = r * cols + c
            cell = im.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
            bb = cell.getbbox()
            if bb is None:
                if idx not in allow_empty:
                    empties.append(idx)
                continue
            if bb[0] < pad or bb[1] < pad or bb[2] > cw - pad or bb[3] > ch - pad:
                clipped.append((idx, bb))
            px_list = [(p[0] * 0.299 + p[1] * 0.587 + p[2] * 0.114)
                       for p in cell.getdata() if p[3] > 40]
            lums.append((idx, round(sum(px_list) / max(1, len(px_list)))))
    return dict(size=im.size, cells=rows * cols, empties=empties, clipped=clipped, lums=lums)


def up(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def make_previews():
    os.makedirs(OUT, exist_ok=True)
    ws = load("assets/icons/weapons.png")
    ps = load("assets/icons/passives.png")
    pj = load("assets/sprites/projectiles.png")
    pp = load("assets/sprites/props.png")
    bg = (18, 24, 36, 255)

    # 4x 拼图（含四张图集）
    K = 4
    W = 8 + 160 * K + 8 + 160 * K + 8
    H = 8 + 128 * K + 8 + 128 * K + 8
    canvas = Image.new("RGBA", (W, H), bg)
    canvas.alpha_composite(up(ws, K), (8, 8))
    canvas.alpha_composite(up(ps, K), (16 + 160 * K, 8))
    pj4 = up(pj, K)
    canvas.alpha_composite(pj4, (8, 16 + 128 * K))
    pp4 = up(pp, K)
    canvas.alpha_composite(pp4, (16 + 128 * K, 16 + 128 * K))
    d = ImageDraw.Draw(canvas)
    for i in range(20):
        x = (i % 5) * 32 * K
        y = (i // 5) * 32 * K
        d.text((x + 8 + 3, y + 8 + 2), str(i), fill=(90, 110, 140))
        d.text((x + 16 + 160 * K + 3, y + 8 + 2), str(i), fill=(90, 110, 140))
    canvas.save(os.path.join(OUT, "prev_icons.png"))
    print("preview prev_icons.png", canvas.size)

    # 单图放大
    up(ws, 5).save(os.path.join(OUT, "prev_w.png"))
    up(ps, 5).save(os.path.join(OUT, "prev_p.png"))
    up(pj, 5).save(os.path.join(OUT, "prev_proj.png"))
    up(pp, 8).save(os.path.join(OUT, "prev_props.png"))

    # 1x 实际大小 + 深色地面（可读性判定）
    one = Image.new("RGBA", (352, 352), (16, 20, 28, 255))
    one.alpha_composite(ws, (6, 6))
    one.alpha_composite(ps, (6, 140))
    one.alpha_composite(pj, (6, 274))
    one2 = Image.new("RGBA", (352, 420), (16, 20, 28, 255))
    one2.alpha_composite(ws, (6, 6))
    one2.alpha_composite(ps, (6, 140))
    one2.alpha_composite(pj, (6, 274))
    one2.alpha_composite(pp, (150, 274))
    one2.save(os.path.join(OUT, "prev_1x.png"))
    print("preview prev_1x.png", one2.size)


def main():
    wjson = json.load(open(os.path.join(ROOT, "data", "weapons.json"), encoding="utf-8"))
    pjson = json.load(open(os.path.join(ROOT, "data", "passives.json"), encoding="utf-8"))
    wids = [w["id"] for w in wjson["weapons"]]
    pids = [p["id"] for p in pjson["passives"]]
    wl, pl = w_list(), p_list()
    assert [x[0] for x in wl] == wids, "武器顺序与 data/weapons.json 不一致:\n%s\n%s" % (
        [x[0] for x in wl], wids)
    assert [x[0] for x in pl] == pids, "被动顺序与 data/passives.json 不一致:\n%s\n%s" % (
        [x[0] for x in pl], pids)

    ws = build_icon_sheet(wl)
    ps = build_icon_sheet(pl, halo=True)
    pp = build_props()
    pj = build_projectiles()

    for rel, im in (("assets/icons/weapons.png", ws), ("assets/icons/passives.png", ps),
                    ("assets/sprites/props.png", pp), ("assets/sprites/projectiles.png", pj)):
        im.save(os.path.join(ROOT, rel))
        print("wrote", rel, im.size)

    for rel, w, h, cw, ch, empty in (
            ("assets/icons/weapons.png", 160, 128, 32, 32, ()),
            ("assets/icons/passives.png", 160, 128, 32, 32, ()),
            ("assets/sprites/props.png", 128, 16, 16, 16, (6, 7)),
            ("assets/sprites/projectiles.png", 128, 128, 16, 16, ())):
        r = check_sheet(os.path.join(ROOT, rel), w, h, cw, ch, allow_empty=empty,
                        pad=1 if cw == 32 else 0)
        print("check %-34s cells=%d empty=%s clipped=%s" % (rel, r["cells"], r["empties"], r["clipped"]))
        if cw == 32:
            print("   lum:", " ".join("%d:%d" % t for t in r["lums"]))

    make_previews()
    print("ICONS_DONE")


if __name__ == "__main__":
    main()
