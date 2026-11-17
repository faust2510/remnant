#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4 见证人像素行走图 · 伊甸组（adam / eve）

《余民》的见证人序列从伊甸园开始（创 2-3），亚当与夏娃是这条线的第一组。
本文件为新增两人，风格严格对齐 chars_a / chars_b：
  48x48 手绘单格、朝右、脚底 y=44、1px 深色外描边（artbase.outline 统一加）、
  单侧主光（光从右上来）、每块布/叶 3 阶明暗、禁渐变禁抗锯齿。

1x 辨认要点
  亚当：小麦色裸上身 + 深褐短发 + 草叶短裙 + 右手托一枚高饱和红果（禁果）
  夏娃：长褐发（左侧一大块垂到腰）+ 月白披帛 + 草叶长裙 + 胸前月白花

产出：tools/out/wit_adam.png / wit_eve.png（384x48，8 帧）
预览：tools/out/prev_adam.png / prev_eve.png（4x，深底）
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from artbase import (  # noqa: E402
    new_cell, rct, ell, ln, poly, px, outline, save_strip, validate, hx, dark, light, mix,
    OUTLINE, SKIN, SKIN_D, SKIN_L, SKIN_OLIVE, SKIN_PALE,
    HAIR_BRN, HAIR_AUB, BROWN, BROWN_D, TAN, SAND, LINEN, LINEN_D, LEATHER, LEATHER_L,
    GREEN, OLIVE, GOLD, GOLD_L, RED, RED_D, CRIMSON, GREY, STEEL, FLAME, HOLY,
)
from PIL import Image, ImageDraw  # noqa: E402

CELL = 48
FOOT = 44
OUT = os.path.join(ROOT, "tools", "out")

# ---------------------------------------------------------------- 专属配色
# 亚当：暖棕 + 草绿
AD_SKIN = SKIN_OLIVE            # 小麦色肌肤（暖棕）
AD_HAIR = hx("#4A3524")         # 深褐短发
AD_HAIR_L = hx("#6B4E35")
AD_HAIR_D = hx("#2C1E13")
FRUIT = hx("#C24228")           # 禁果：全图唯一高饱和色（身份道具）
FRUIT_L = hx("#E0713F")
FRUIT_D = hx("#7A2418")
# 草叶（两人共用同一套 3 阶）
LF = hx("#3E6B4F")
LF_L = hx("#5C8C58")
LF_D = hx("#26432E")
LF_V = hx("#82A96C")
# 夏娃：暖棕 + 月白 + 草绿
EV_SKIN = SKIN
EV_HAIR = hx("#5A3B22")
EV_HAIR_L = hx("#7C5730")
EV_HAIR_D = hx("#38240F")
MOON = hx("#EDE8F2")            # 月白
MOON_L = hx("#FCFAFF")
MOON_D = hx("#BEB7CC")
LIP = hx("#B5695E")

BG = (24, 29, 39, 255)


# ---------------------------------------------------------------- 基元
def geo(bob=0, sway=0):
    cx = 23 + sway
    return dict(cx=cx, hl=cx - 4, hr=cx + 4, ht=8 + bob, hb=17 + bob,
                neck=18 + bob, sh=19 + bob, waist=27 + bob, hip=31, foot=FOOT)


def tor(d, cx, prof, col, dl=0.82, lt=1.13):
    """躯干：按 (y, hw) 逐行画；左 2px 暗 / 右 2px 亮（单侧主光在右）。"""
    for (y, hw) in prof:
        rct(d, cx - hw, y, cx + hw, y, col)
        rct(d, cx - hw, y, cx - hw, y, dark(col, dl))
        rct(d, cx - hw + 1, y, cx - hw + 1, y, dark(col, (dl + 1) / 2.0))
        rct(d, cx + hw - 1, y, cx + hw, y, light(col, lt))


def hand2(d, x, y, col):
    """2x2 手（掌心受光）。"""
    rct(d, x, y, x + 1, y + 1, col)
    px(d, x, y + 1, dark(col, 0.82))
    px(d, x + 1, y, light(col, 1.14))


def head(d, g, skin, lip=None):
    """朝右的少年/少女脸：额头 7 宽、两颊 9 宽、下颌收窄；眼在 ht+4。"""
    cx, ht, hb = g["cx"], g["ht"], g["hb"]
    rct(d, cx - 3, ht, cx + 3, ht, skin)
    rct(d, cx - 4, ht + 1, cx + 4, hb - 2, skin)
    rct(d, cx - 3, hb - 1, cx + 3, hb - 1, skin)
    rct(d, cx - 2, hb, cx + 2, hb, skin)
    rct(d, cx - 4, ht + 1, cx - 4, hb - 2, dark(skin, 0.82))
    px(d, cx - 3, ht, dark(skin, 0.86))
    rct(d, cx + 4, ht + 1, cx + 4, hb - 2, light(skin, 1.12))
    px(d, cx + 4, ht + 4, light(skin, 1.20))
    px(d, cx + 4, ht + 6, dark(skin, 0.86))
    px(d, cx - 2, ht + 4, OUTLINE)          # 眼
    px(d, cx + 2, ht + 4, OUTLINE)
    px(d, cx - 3, ht + 3, dark(skin, 0.74))  # 眉/眼窝
    px(d, cx + 3, ht + 3, dark(skin, 0.60))
    px(d, cx + 3, ht + 6, dark(skin, 0.82))  # 鼻
    if lip:
        rct(d, cx + 1, ht + 7, cx + 2, ht + 7, lip)
        px(d, cx, ht + 7, dark(skin, 0.84))
    else:
        rct(d, cx + 1, ht + 7, cx + 2, ht + 7, dark(skin, 0.62))
        px(d, cx + 2, ht + 8, light(skin, 1.08))        # 下巴高光，免得嘴唇读成胡子


def leg(d, x, fwd, lift, col, far=False):
    """赤裸的腿 + 赤脚（脚底 y=44）。

    大腿按 fwd//2、小腿按 fwd 偏移 → 走路时有膝弯，且大腿根部永远留在胯内，
    不会像「整条腿平移」那样和身体断开。
    """
    th = max(-2, min(2, fwd // 2))
    kx = x + th
    ax = x + fwd
    knee = 35
    y1 = 40 - lift
    # 大腿
    rct(d, kx - 1, 31, kx + 1, knee, col)
    rct(d, kx - 1, 31, kx - 1, knee, dark(col, 0.80))
    rct(d, kx + 1, 31, kx + 1, knee, light(col, 1.12))
    # 膝：1 行横桥把两段接死
    rct(d, min(kx - 1, ax - 1), knee, max(kx + 1, ax + 1), knee, col)
    # 小腿
    rct(d, ax - 1, knee + 1, ax + 1, y1, col)
    rct(d, ax - 1, knee + 1, ax - 1, y1, dark(col, 0.80))
    rct(d, ax + 1, knee + 1, ax + 1, y1, light(col, 1.12))
    if not far:
        px(d, ax + 1, knee, light(col, 1.20))
    # 脚
    rct(d, ax - 1, 41 - lift, ax + 1, 43 - lift, col)
    rct(d, ax - 1, 41 - lift, ax + 1, 41 - lift, light(col, 1.16))
    rct(d, ax - 1, 43 - lift, ax + 1, 43 - lift, dark(col, 0.86))
    # 脚尖朝右：两条腿都给脚尖，谁的脚迈到前面都不会缺一块
    rct(d, ax + 2, 42 - lift, ax + 2, 43 - lift, col if not far else dark(col, 0.92))
    px(d, ax + 2, 42 - lift, light(col, 1.14 if not far else 0.96))
    rct(d, ax - 1, 44 - lift, ax + 2, 44 - lift, dark(col, 0.60))


def legs(d, p, cx, col):
    """两条腿按「脚的实际 x」排序后绘制：迈到前面的那条压在上面，交叉步才不会错位。"""
    items = [
        (cx - 3 + p["lf"], cx - 3, p["lf"], p["lfl"], dark(col, 0.90), True),
        (cx + 1 + p["rf"], cx + 1, p["rf"], p["rfl"], col, False),
    ]
    items.sort(key=lambda t: t[0])
    for _, x, fwd, lift, c, far in items:
        leg(d, x, fwd, lift, c, far)


def leaf_skirt(d, cx, y0, y1, hw, jag):
    """草叶裙：逐列不同下摆（jag = 每列额外行数）→ 天然参差，不像短裤。

    y0 = 腰沿行；y1 = 基准下摆行；hw = 半宽；len(jag) 必须 == 2*hw+1。
    """
    n = 2 * hw + 1
    for i in range(n):
        x = cx - hw + i
        yy = y1 + jag[i]
        rct(d, x, y0, x, yy, LF)
        if i == 0:
            rct(d, x, y0, x, yy, LF_D)
        elif i == 1:
            rct(d, x, y0, x, yy, dark(LF, 0.86))
        elif i == n - 1:
            rct(d, x, y0, x, yy, LF_L)
        elif i == n - 2:
            rct(d, x, y0, x, yy, light(LF, 1.10))
    rct(d, cx - hw, y0, cx + hw, y0, LF_D)                     # 腰沿（暗）
    rct(d, cx - hw, y0 + 1, cx + hw, y0 + 1, light(LF, 1.16))  # 腰沿高光
    # 叶脉：只 3 条、走向不一，避免「竖条纹制服感」
    ln(d, cx - 3, y0 + 2, cx - 2, y1 - 1, LF_D, 1)
    ln(d, cx, y0 + 2, cx + 1, y1 - 2, LF_V, 1)
    ln(d, cx + 2, y0 + 2, cx + 1, y1 - 3, LF_D, 1)


def adam(p):
    im = new_cell()
    d = ImageDraw.Draw(im)
    g = geo(p["bob"], p["sway"])
    cx, sh, ht, hb = g["cx"], g["sh"], g["ht"], g["hb"]
    aly, ary = p["aly"], p["ary"]
    SK = AD_SKIN

    # ---- 腿（叶裙下裸腿）
    legs(d, p, cx, SK)

    # ---- 赤裸上身：宽肩 → 窄腰 → 收胯（V 型，和夏娃的直腰区分）
    prof = [(sh, 6), (sh + 1, 6), (sh + 2, 6), (sh + 3, 5), (sh + 4, 5), (sh + 5, 5),
            (sh + 6, 4), (sh + 7, 4), (sh + 8, 4), (sh + 9, 4), (sh + 10, 5),
            (sh + 11, 5)]
    tor(d, cx, prof, SK)
    # 颈 + 颈下阴影
    rct(d, cx - 2, hb, cx + 2, sh - 1, SK)
    px(d, cx - 2, hb, dark(SK, 0.78))
    px(d, cx - 1, hb, dark(SK, 0.88))
    rct(d, cx - 2, sh, cx + 2, sh, dark(SK, 0.80))
    # 胸腹：胸肌 2 团 + 腹中线 + 脐（都靠暗部，不画线条血迹）
    rct(d, cx - 3, sh + 3, cx - 1, sh + 3, dark(SK, 0.91))
    rct(d, cx + 1, sh + 3, cx + 3, sh + 3, dark(SK, 0.88))
    px(d, cx, sh + 2, dark(SK, 0.90))
    px(d, cx, sh + 6, dark(SK, 0.88))
    px(d, cx, sh + 7, dark(SK, 0.88))
    px(d, cx, sh + 8, dark(SK, 0.72))                          # 脐
    rct(d, cx + 4, sh + 1, cx + 4, sh + 2, light(SK, 1.18))    # 三角肌高光

    # ---- 草叶短裙（到股上，右侧多出叶片打破轮廓）
    leaf_skirt(d, cx, sh + 10, sh + 12, 5, [1, 2, 2, 1, 2, 1, 0, 1, 2, 2, 1])
    rct(d, cx + 6, sh + 11, cx + 6, sh + 13, LF_L)             # 右侧叶片
    px(d, cx + 6, sh + 14, LF)
    rct(d, cx - 6, sh + 11, cx - 6, sh + 13, LF_D)             # 左侧叶片
    px(d, cx - 6, sh + 14, dark(LF, 0.80))

    # ---- 远侧手臂（左手垂在体侧）
    axl = cx - 6
    rct(d, axl, sh, axl + 1, sh + 7 + aly, SK)
    rct(d, axl, sh, axl, sh + 7 + aly, dark(SK, 0.84))
    rct(d, axl + 1, sh, axl + 1, sh + 7 + aly, light(SK, 1.12))
    hand2(d, axl, sh + 8 + aly, SK)

    # ---- 近侧手臂：屈肘前伸，掌心托禁果（举到轮廓外，1x 才认得出）
    ax = cx + 6                                                # 29
    rct(d, ax, sh, ax + 1, sh + 2, SK)                         # 上臂
    rct(d, ax, sh, ax, sh + 2, dark(SK, 0.84))
    rct(d, ax + 1, sh, ax + 1, sh + 2, light(SK, 1.12))
    rct(d, ax + 1, sh + 3, ax + 3, sh + 4, SK)                 # 前臂前伸（肘角留空）
    rct(d, ax + 1, sh + 3, ax + 3, sh + 3, light(SK, 1.08))
    rct(d, ax + 1, sh + 4, ax + 3, sh + 4, dark(SK, 0.84))
    hand2(d, ax + 3, sh + 1, SK)                               # 32..33, 20..21

    # ---- 头 + 短褐发
    head(d, g, SK)
    rct(d, cx - 4, ht - 1, cx + 3, ht, AD_HAIR)
    rct(d, cx - 4, ht + 1, cx - 4, ht + 3, AD_HAIR)
    rct(d, cx + 3, ht + 1, cx + 3, ht + 2, AD_HAIR)
    rct(d, cx - 3, ht - 2, cx - 1, ht - 2, AD_HAIR)            # 额前一撮
    px(d, cx + 2, ht - 2, AD_HAIR)
    px(d, cx - 3, ht - 1, AD_HAIR_L)
    px(d, cx - 1, ht - 1, AD_HAIR_L)
    px(d, cx + 2, ht - 1, AD_HAIR)
    px(d, cx + 3, ht, AD_HAIR_D)
    px(d, cx - 4, ht + 2, AD_HAIR_D)
    px(d, cx - 4, ht + 3, AD_HAIR_L)
    px(d, cx + 3, ht + 2, AD_HAIR_D)

    # ---- 禁果（掌心，全图唯一高饱和）
    fx, fy = 32, 17
    rct(d, fx, fy + 1, fx + 2, fy + 2, FRUIT)
    px(d, fx + 1, fy, FRUIT)
    px(d, fx + 2, fy + 1, FRUIT_L)
    px(d, fx + 1, fy + 1, light(FRUIT, 1.30))
    px(d, fx, fy + 2, FRUIT_D)
    px(d, fx + 2, fy + 2, FRUIT_D)
    px(d, fx + 1, fy - 1, LF_V)                                # 果柄小叶
    px(d, fx + 2, fy - 1, LF)
    return im


def eve(p):
    im = new_cell()
    d = ImageDraw.Draw(im)
    g = geo(p["bob"], p["sway"])
    cx, sh, ht, hb = g["cx"], g["sh"], g["ht"], g["hb"]
    aly, ary = p["aly"], p["ary"]
    SK = EV_SKIN

    # ---- 腿
    legs(d, p, cx, SK)

    # ---- 躯干（肩 5 / 腰 3 / 胯 5：比亚当窄、腰线高）
    prof = [(sh, 5), (sh + 1, 5), (sh + 2, 5), (sh + 3, 4), (sh + 4, 4), (sh + 5, 4),
            (sh + 6, 3), (sh + 7, 3), (sh + 8, 4), (sh + 9, 5), (sh + 10, 5),
            (sh + 11, 5)]
    tor(d, cx, prof, SK)
    rct(d, cx - 2, hb, cx + 2, sh - 1, SK)
    px(d, cx - 2, hb, dark(SK, 0.80))
    px(d, cx - 1, hb, dark(SK, 0.90))
    rct(d, cx - 2, sh, cx + 2, sh, dark(SK, 0.84))
    px(d, cx - 1, sh + 8, dark(SK, 0.90))

    # ---- 月白披帛：左肩 → 右胯的 45° 带（上缘亮 / 主体月白 / 下缘暗）
    ln(d, cx - 4, sh + 1, cx + 4, sh + 8, MOON, 2)
    for k in (0, 3, 6):                                        # 受光侧亮点（左肩起）
        px(d, cx - 4 + k, sh + 1 + k, MOON_L)
    for k in (6, 7, 8):                                        # 末端入影
        px(d, cx - 4 + k, sh + 2 + k, MOON_D)
    px(d, cx - 4, sh + 1, MOON_L)

    # ---- 草叶长裙（到膝，比亚当长 + 左右侧叶 = A 字轮廓）
    leaf_skirt(d, cx, sh + 10, sh + 16, 5, [0, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2])
    rct(d, cx + 6, sh + 11, cx + 6, sh + 15, LF_L)
    px(d, cx + 6, sh + 16, LF)
    rct(d, cx - 6, sh + 11, cx - 6, sh + 15, LF_D)
    px(d, cx - 6, sh + 16, dark(LF, 0.78))

    # ---- 远侧手臂
    axl = cx - 6
    rct(d, axl, sh, axl + 1, sh + 7 + aly, SK)
    rct(d, axl, sh, axl, sh + 7 + aly, dark(SK, 0.84))
    rct(d, axl + 1, sh, axl + 1, sh + 7 + aly, light(SK, 1.12))
    hand2(d, axl, sh + 8 + aly, SK)

    # ---- 近侧手臂：垂到体侧、腕前折托花
    ax = cx + 6                                                # 29
    rct(d, ax, sh, ax + 1, sh + 6, SK)
    rct(d, ax, sh, ax, sh + 6, dark(SK, 0.84))
    rct(d, ax + 1, sh, ax + 1, sh + 6, light(SK, 1.12))
    rct(d, ax + 1, sh + 7, ax + 2, sh + 7, SK)                 # 腕
    hand2(d, ax + 2, sh + 6, SK)                               # 31..32, 25..26

    # ---- 头 + 长褐发
    head(d, g, SK, lip=LIP)
    rct(d, cx - 4, ht - 1, cx + 3, ht, EV_HAIR)                # 顶盖
    rct(d, cx - 3, ht - 2, cx - 2, ht - 2, EV_HAIR)
    rct(d, cx + 1, ht - 2, cx + 2, ht - 2, EV_HAIR)
    rct(d, cx - 5, ht + 1, cx - 4, ht + 5, EV_HAIR)            # 左鬓
    rct(d, cx - 6, ht + 6, cx - 5, sh + 8, EV_HAIR)            # 背后长发垂到腰
    rct(d, cx - 6, ht + 6, cx - 6, sh + 8, EV_HAIR_D)
    rct(d, cx - 5, ht + 6, cx - 5, sh + 8, EV_HAIR_L)
    rct(d, cx + 3, ht + 1, cx + 4, ht + 3, EV_HAIR)            # 右鬓
    rct(d, cx + 4, ht + 4, cx + 4, sh + 1, EV_HAIR)            # 右前发绺垂到胸
    px(d, cx + 4, sh + 2, EV_HAIR_D)
    px(d, cx - 3, ht - 1, EV_HAIR_L)
    px(d, cx, ht - 1, EV_HAIR_L)
    px(d, cx + 2, ht - 1, light(EV_HAIR, 1.18))
    px(d, cx - 1, ht - 2, EV_HAIR_D)
    px(d, cx + 3, ht, EV_HAIR_D)
    px(d, cx - 5, ht + 4, EV_HAIR_D)
    px(d, cx - 6, sh + 6, EV_HAIR_D)
    px(d, cx - 5, sh + 7, EV_HAIR_D)
    px(d, cx - 5, ht + 8, EV_HAIR_L)

    # ---- 月白花（掌心捧起：四瓣展开 + 饱和金心 + 绿萼叶）
    fx, fy = 32, 28
    rct(d, fx, fy - 1, fx + 1, fy - 1, MOON)                   # 上两瓣
    rct(d, fx, fy + 1, fx + 1, fy + 1, MOON)                   # 下两瓣
    px(d, fx - 1, fy, MOON)                                    # 左瓣
    px(d, fx + 2, fy, MOON)                                    # 右瓣
    px(d, fx + 1, fy - 1, MOON_L)                              # 受光瓣
    px(d, fx, fy + 1, MOON_D)                                  # 背光瓣
    px(d, fx - 1, fy, MOON_D)                                  # 左瓣背光（读成圆瓣不倒角）
    rct(d, fx, fy, fx + 1, fy, GOLD)                           # 金心（饱和，1x 才认得出是花）
    px(d, fx, fy - 2, LF_D)                                    # 花萼（贴住掌心）
    px(d, fx - 1, fy + 2, LF)                                  # 左下叶
    px(d, fx + 2, fy + 1, LF_L)                                # 右下叶（受光）
    return im


# ---------------------------------------------------------------- 构建
CHARS = [
    ("adam", adam),
    ("eve", eve),
]
BY = dict(CHARS)


def P(**kw):
    p = dict(bob=0, sway=0, lf=0, rf=0, lfl=0, rfl=0, alx=0, aly=0, arx=0, ary=0,
             t=0, kind="idle", ex=0)
    p.update(kw)
    return p


# 时间轴与 chars_a/b 完全一致（8 帧：4 待机 + 4 行走）
IDLE = [
    P(t=0),
    P(t=1, bob=-1, aly=-1, ary=-1),
    P(t=2, bob=-1, sway=1, ary=-1),
    P(t=3, aly=1, ary=1, ex=1),
]
WALK = [
    P(t=4, kind="walk", bob=-1, rf=4, lf=-3, alx=1, aly=-2, arx=-1, ary=2, ex=1),
    P(t=5, kind="walk", bob=0, rf=2, lf=-2, lfl=2, alx=0, aly=0, arx=0, ary=0, ex=0),
    P(t=6, kind="walk", bob=-1, rf=-4, lf=4, alx=-1, aly=3, arx=1, ary=-2, ex=-1),
    P(t=7, kind="walk", bob=0, rf=3, lf=1, rfl=2, ex=0),
]
POSES = IDLE + WALK


def frames_of(fn):
    return [outline(fn(p), OUTLINE, False) for p in POSES]


def build(names=None):
    made = []
    for name, fn in CHARS:
        if names and name not in names:
            continue
        fr = frames_of(fn)
        path = os.path.join(OUT, "wit_%s.png" % name)
        save_strip(path, fr)
        n = validate(path, CELL, 8)
        made.append((name, path, n))
    return made


def _strip(fn, scale=1):
    fr = frames_of(fn)
    s = Image.new("RGBA", (CELL * 8, CELL), (0, 0, 0, 0))
    for i, f in enumerate(fr):
        s.alpha_composite(f, (i * CELL, 0))
    if scale != 1:
        s = s.resize((s.width * scale, s.height * scale), Image.NEAREST)
    return s


def preview(name, scale=4):
    s = _strip(BY[name], scale)
    out = Image.new("RGBA", s.size, BG)
    out.alpha_composite(s)
    p = os.path.join(OUT, "prev_%s.png" % name)
    out.save(p)
    return p


def sheet(names, path, scale=1, pad=2):
    rows = [_strip(BY[n], scale) for n in names]
    W = rows[0].width
    H = sum(r.height + pad for r in rows)
    out = Image.new("RGBA", (W, H), BG)
    y = 0
    for r in rows:
        out.alpha_composite(r, (0, y))
        y += r.height + pad
    out.save(path)
    return path


def main(argv):
    names = argv[1:] or None
    for name, path, n in build(names):
        preview(name, 4)
        print("ok", os.path.basename(path), "frames=%d" % n)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
