#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4 见证人像素行走图 · A 组 (v4)
david / noah / abraham / jacob / miriam / moses / john_patmos

自绘 48x48 单格（不用 artbase.render 的方块身体），只复用 artbase 的绘制基元。

v4 相比 v3 的修正：
  1. 大卫的「竖琴」改成三角轮廓的真竖琴（立柱/琴颈/音箱/弦），v3 的方框像窗户。
  2. 摩西的铜蛇杖重画：蛇身 2px 缠绕 + 抬头 + 眼 + 分叉舌；石版改灰石 + 深色边。
  3. 挪亚：围裙改浅皮色（与深棕袍拉开），锤加大，木板去条纹。
  4. 亚伯拉罕：星空披风加宽加暗 + 金星 5 颗；腰带/头巾加蓝。
  5. 雅各：前开襟加宽到 3px，露出深褐内层，层次可读。
  6. 米利暗：举铃鼓的手臂加粗到 3px + 蓝袖口。
  7. 约翰：鹰重画（白头+褐身+展开的翅尖+尾羽），站在左肩。
  8. 全角色躯干加一道内侧暗带 + 内侧亮带（四段明暗），衣褶对比加深。

产出：tools/out/wit_<id>.png  (384x48, 8 帧)
预览：tools/out/prev_<id>.png  (4x)

坐标约定：脚底（鞋底）y=44；一律朝右；1px 描边 #0A0E14。
"""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from artbase import (  # noqa: E402
    new_cell, rct, ell, ln, poly, px, outline, save_strip, validate, hx, dark, light, mix,
    OUTLINE, SKIN, SKIN_D, SKIN_L, SKIN_OLIVE, SKIN_PALE,
    HAIR_BRN, HAIR_AUB, HAIR_WHT, HAIR_GRY,
    PURPLE, PURPLE_D, ROYAL, RED, RED_D, CRIMSON,
    BLUE, BLUE_D, SKY, TEAL, GREEN, OLIVE,
    BROWN, BROWN_D, TAN, SAND, LINEN, LINEN_D,
    GREY, GREY_D, GOLD, GOLD_L, GOLD_D, BRONZE, IRON, IRON_D, STEEL,
    LEATHER, LEATHER_L, FLAME, FLAME_O, FLAME_R, HOLY, HOLY_B, BLOOD_D,
)
from PIL import Image, ImageDraw  # noqa: E402

CELL = 48
FOOT = 44
OUT = os.path.join(ROOT, "tools", "out")

# ---------------------------------------------------------------- 专属配色
AUB = hx("#AA5028")
AUB_D = hx("#7A3520")
AUB_L = hx("#CC7136")
WHT = hx("#EEEADD")
WHT_D = hx("#BEB7A3")
WHT_L = hx("#FFFBEF")
SND = hx("#CBB287")
SND_D = hx("#96794F")
SND_L = hx("#E8D6B2")
NGT = hx("#2C4569")
NGT_L = hx("#40628F")
NGT_D = hx("#182742")
WOOD = hx("#9A7549")
WOOD_D = hx("#5C4227")
WOOD_L = hx("#C09A68")
BLOODC = hx("#9B3630")
BLOODC_L = hx("#BC4E3E")
BLOODC_D = hx("#5C1C1C")
FLEECE = hx("#E4DDC8")
FLEECE_D = hx("#A79E82")
SMOKE = hx("#EFE6CC")
TAN_SKIN = hx("#C99A6A")
STONE = hx("#A29C8C")
STONE_D = hx("#6E6858")
STONE_L = hx("#C6C0AE")
APRON = hx("#C08F55")
APRON_L = hx("#E0B478")
APRON_D = hx("#8A6032")
CAVE = hx("#241A2E")

BG = (24, 29, 39, 255)


# ---------------------------------------------------------------- 基元
def geo(bob=0, sway=0):
    cx = 23 + sway
    return dict(cx=cx, hl=cx - 4, hr=cx + 4, ht=8 + bob, hb=17 + bob,
                neck=18 + bob, sh=19 + bob, waist=27 + bob, hip=31, foot=FOOT)


def tline(d, x0, y0, x1, y1, c, w=2):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        t = i / float(n)
        rct(d, int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t)),
            int(round(x0 + (x1 - x0) * t)) + w - 1, int(round(y0 + (y1 - y0) * t)) + w - 1, c)


def body(d, cx, profile, c, dl=0.72, lt=1.20, hi=True):
    """四段明暗：左缘暗 / 内侧暗 / base / 内侧亮 / 右缘亮。"""
    for (y, hw) in profile:
        rct(d, cx - hw, y, cx + hw, y, c)
    for i, (y, hw) in enumerate(profile):
        px(d, cx - hw, y, dark(c, dl))
        px(d, cx - hw + 1, y, dark(c, dl + 0.10))
        px(d, cx + hw, y, light(c, lt))
        px(d, cx + hw - 1, y, light(c, lt - 0.06))
        if hi and i < len(profile) - 4:
            px(d, cx + hw - 3, y, light(c, 1.06))
            px(d, cx - hw + 3, y, dark(c, dl + 0.18))
    y0 = profile[0][0]
    ln(d, cx - profile[0][1] + 1, y0 + 1, cx + profile[0][1] - 1, y0 + 1, dark(c, 0.82), 1)


def taper(d, cx, y0, y1, hw0, hw1, c, dl=0.76, lt=1.16):
    for y in range(int(y0), int(y1) + 1):
        t = 0.0 if y1 == y0 else (y - y0) / float(y1 - y0)
        hw = int(round(hw0 + (hw1 - hw0) * t))
        rct(d, cx - hw, y, cx + hw, y, c)
        px(d, cx - hw, y, dark(c, dl))
        px(d, cx - hw + 2, y, dark(c, dl + 0.16))
        px(d, cx + hw, y, light(c, lt))
        px(d, cx + hw - 2, y, light(c, lt - 0.06))


def limb(d, x0, y0, x1, y1, c, w=2, dl=0.80):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        t = i / float(n)
        x = int(round(x0 + (x1 - x0) * t))
        y = int(round(y0 + (y1 - y0) * t))
        rct(d, x, y, x + w - 1, y + 1, c)
        px(d, x + w - 1, y + 1, dark(c, dl))
        px(d, x, y, light(c, 1.12))


def hand(d, x, y, c=SKIN):
    rct(d, x, y, x + 1, y + 1, c)
    px(d, x + 1, y + 1, dark(c, 0.82))
    px(d, x, y, light(c, 1.10))


def arm_far(d, cx, sh, c, dy, hc):
    x = cx - 7
    rct(d, x, sh + 1, x + 1, sh + 8 + dy, dark(c, 0.72))
    px(d, x + 1, sh + 1, dark(c, 0.86))
    px(d, x, sh + 2, dark(c, 0.80))
    hand(d, x, sh + 9 + dy, hc)


def arm_near(d, cx, sh, c, dy, hc, dk=0.84):
    x = cx + 6
    rct(d, x, sh + 1, x + 1, sh + 8 + dy, dark(c, dk))
    px(d, x + 1, sh + 1, dark(c, min(1.14, dk + 0.22)))
    px(d, x + 1, sh + 2, dark(c, min(1.10, dk + 0.16)))
    px(d, x, sh + 1, dark(c, dk + 0.04))
    rct(d, x, sh + 8 + dy, x + 1, sh + 8 + dy, dark(c, dk - 0.06))
    hand(d, x, sh + 9 + dy, hc)
    return (x, sh + 9 + dy)


def face(d, g, skin, old=False, lip=None, eye=OUTLINE):
    cx, ht, hb, hl, hr = g["cx"], g["ht"], g["hb"], g["hl"], g["hr"]
    rct(d, cx - 3, ht, cx + 3, ht, skin)
    rct(d, hl, ht + 1, hr, hb - 2, skin)
    rct(d, cx - 3, hb - 1, cx + 3, hb - 1, skin)
    rct(d, cx - 2, hb, cx + 2, hb, skin)
    rct(d, hl, ht + 1, hl, hb - 2, dark(skin, 0.82))
    rct(d, hl + 1, ht + 1, hl + 1, hb - 2, dark(skin, 0.90))
    rct(d, hr, ht + 1, hr, hb - 2, light(skin, 1.12))
    px(d, hl, hb - 1, dark(skin, 0.82))
    px(d, hl, ht, dark(skin, 0.86))
    px(d, hr, hb - 1, light(skin, 1.06))
    px(d, hr + 1, ht + 5, light(skin, 1.08))
    px(d, hr + 1, ht + 6, dark(skin, 0.84))
    px(d, hr, ht + 4, light(skin, 1.16))
    px(d, cx - 2, ht + 4, eye)
    px(d, cx + 2, ht + 4, eye)
    px(d, cx - 3, ht + 3, dark(skin, 0.70))
    px(d, cx + 3, ht + 3, dark(skin, 0.56))
    if lip:
        rct(d, cx, ht + 7, cx + 2, ht + 7, lip)
        px(d, cx + 2, ht + 7, dark(lip, 0.80))
    else:
        rct(d, cx + 1, ht + 7, cx + 2, ht + 7, dark(skin, 0.60))
        px(d, cx, ht + 7, dark(skin, 0.84))
    if old:
        ln(d, cx - 3, ht + 2, cx, ht + 2, dark(skin, 0.72), 1)
        px(d, cx - 3, ht + 5, dark(skin, 0.74))


def beard(d, g, col, length=6, w=3, mustache=True):
    cx, hb = g["cx"], g["hb"]
    top = hb - 1
    bot = hb + length
    for y in range(top, bot + 1):
        t = (y - top) / float(max(1, bot - top))
        hw = int(round(w - t * 1.2))
        rct(d, cx - hw, y, cx + hw, y, col)
        px(d, cx - hw, y, dark(col, 0.82))
        px(d, cx + hw, y, light(col, 1.10))
        if (y - top) % 2 == 1:
            px(d, cx - hw + 1, y, dark(col, 0.78))
            px(d, cx + hw - 1, y, dark(col, 0.86))
    ln(d, cx - w + 1, top + 2, cx + w - 1, top + 2, dark(col, 0.70), 1)
    if mustache:
        rct(d, cx - 2, hb - 2, cx + 2, hb - 2, col)
        px(d, cx - 2, hb - 2, light(col, 1.12))
        px(d, cx + 2, hb - 2, dark(col, 0.88))


def hair_long(d, cx, ht, col, rows, cap_rows=(0, 1)):
    for (dy, x0, x1) in rows:
        y = ht + dy
        rct(d, cx + x0, y, cx + x1, y, col)
        px(d, cx + x0, y, dark(col, 0.78))
        if x1 > x0:
            px(d, cx + x1, y, light(col, 1.08))
    y0, y1 = cap_rows
    for y in range(ht + y0, ht + y1 + 1):
        rct(d, cx - 4, y, cx + 3, y, col)
    rct(d, cx - 4, ht + y0, cx + 3, ht + y0, light(col, 1.18))
    px(d, cx + 3, ht + y1, dark(col, 0.86))


def leg(d, x, fwd, lift, pants, boot, toe=True):
    cx = x + fwd
    y1 = 40 - lift
    rct(d, cx - 1, 30, cx + 1, y1, pants)
    rct(d, cx - 1, 30, cx - 1, y1, dark(pants, 0.78))
    rct(d, cx + 1, 30, cx + 1, y1, light(pants, 1.12))
    rct(d, cx - 1, 41 - lift, cx + 1, 43 - lift, boot)
    rct(d, cx - 1, 41 - lift, cx + 1, 41 - lift, light(boot, 1.24))
    if toe:
        rct(d, cx + 2, 41 - lift, cx + 2, 43 - lift, boot)
        px(d, cx + 2, 41 - lift, light(boot, 1.08))
        px(d, cx + 2, 43 - lift, dark(boot, 0.72))
        rct(d, cx - 1, 44 - lift, cx + 2, 44 - lift, dark(boot, 0.58))
    else:
        rct(d, cx - 1, 44 - lift, cx + 1, 44 - lift, dark(boot, 0.58))


def legs(d, p, cx, near, far, boot):
    # 远腿靴不伸鞋尖，保证两靴之间留 3px 缝（描边吃掉 2px，还剩 1px 暗缝）
    leg(d, cx - 4, p["lf"], p["lfl"], dark(far, 0.82), dark(boot, 0.88), toe=False)
    leg(d, cx + 2, p["rf"], p["rfl"], near, boot, toe=True)


def prop_staff(d, x, y_top, wood=WOOD, bot=44):
    rct(d, x, y_top, x + 1, bot, wood)
    rct(d, x, y_top, x, bot, light(wood, 1.14))
    rct(d, x + 1, y_top, x + 1, bot, dark(wood, 0.74))


# ---------------------------------------------------------------- 姿态
def P(**kw):
    p = dict(bob=0, sway=0, lf=0, rf=0, lfl=0, rfl=0, alx=0, aly=0, arx=0, ary=0,
             t=0, kind="idle", ex=0)
    p.update(kw)
    return p


IDLE = [
    P(t=0),
    P(t=1, bob=-1, aly=-1, ary=-1),
    P(t=2, bob=-1, sway=1, ary=-1),
    P(t=3, aly=1, ary=1, ex=1),
]
WALK = [
    P(t=4, kind="walk", bob=-1, rf=4, lf=-3, alx=1, aly=-2, arx=-1, ary=2, ex=1),
    P(t=5, kind="walk", bob=0, rf=2, lf=-2, lfl=2, alx=0, aly=0, arx=0, ary=0, ex=0),
    P(t=6, kind="walk", bob=-1, rf=-3, lf=4, alx=-1, aly=3, arx=1, ary=-2, ex=-1),
    P(t=7, kind="walk", bob=0, rf=3, lf=1, rfl=2, ex=0),
]
POSES = IDLE + WALK


# ---------------------------------------------------------------- 道具
def harp(d, x, y):
    """金竖琴 12x13：双立柱 + 顶横梁 + 深色内腔 + 3 弦 + 木音箱。"""
    X, Y = x, y
    # 顶横梁 + 宝石
    rct(d, X, Y, X + 9, Y + 1, GOLD)
    rct(d, X, Y, X + 9, Y, GOLD_L)
    rct(d, X, Y + 1, X + 9, Y + 1, GOLD_D)
    px(d, X + 4, Y, HOLY)
    px(d, X + 5, Y + 1, CRIMSON)
    # 双立柱（各 2px：外亮内暗）
    rct(d, X, Y + 2, X + 1, Y + 11, GOLD)
    rct(d, X, Y + 2, X, Y + 11, GOLD_L)
    rct(d, X + 1, Y + 2, X + 1, Y + 11, GOLD_D)
    rct(d, X + 8, Y + 2, X + 9, Y + 11, GOLD)
    rct(d, X + 9, Y + 2, X + 9, Y + 11, GOLD_L)
    rct(d, X + 8, Y + 2, X + 8, Y + 11, GOLD_D)
    # 柱头外卷
    px(d, X - 1, Y + 3, GOLD)
    px(d, X - 1, Y + 4, GOLD_D)
    px(d, X + 10, Y + 3, GOLD_L)
    px(d, X + 10, Y + 4, GOLD)
    # 深色内腔（实心填，1px 缝交给描边也不会糊）
    rct(d, X + 2, Y + 2, X + 7, Y + 10, CAVE)
    # 3 根弦（画在实色腔体上，不会被描边吃掉）
    ln(d, X + 2, Y + 2, X + 2, Y + 9, HOLY, 1)
    ln(d, X + 4, Y + 2, X + 4, Y + 9, HOLY, 1)
    ln(d, X + 6, Y + 2, X + 6, Y + 9, HOLY, 1)
    ln(d, X + 3, Y + 3, X + 3, Y + 8, GOLD_D, 1)
    ln(d, X + 5, Y + 3, X + 5, Y + 8, GOLD_D, 1)
    # 音箱（下缘木色 + 金饰条）
    rct(d, X, Y + 11, X + 9, Y + 12, WOOD)
    rct(d, X, Y + 11, X + 9, Y + 11, WOOD_L)
    rct(d, X, Y + 12, X + 9, Y + 12, WOOD_D)
    rct(d, X + 3, Y + 11, X + 6, Y + 12, GOLD)
    px(d, X + 4, Y + 11, GOLD_L)


def sling(d, hx, hy, sw=0):
    cx, cy = hx + 2, hy + 1
    ln(d, cx, cy, cx + 5, cy + 1 + sw, LEATHER_L, 1)
    ln(d, cx + 5, cy + 1 + sw, cx + 4, cy + 5 + sw, LEATHER_L, 1)
    ell(d, cx + 1, cy + 4 + sw, cx + 5, cy + 7 + sw, LEATHER)
    ell(d, cx + 2, cy + 5 + sw, cx + 4, cy + 6 + sw, dark(LEATHER, 0.82))
    rct(d, cx + 2, cy + 5 + sw, cx + 3, cy + 6 + sw, GREY)
    px(d, cx + 3, cy + 5 + sw, STEEL)
    px(d, cx + 1, cy + 4 + sw, LEATHER_L)


def censer(d, hx, hy, t=0):
    ln(d, hx + 1, hy, hx + 5, hy + 5, GOLD_D, 1)
    ln(d, hx + 2, hy, hx + 6, hy + 6, GOLD_D, 1)
    ln(d, hx + 3, hy, hx + 7, hy + 5, GOLD, 1)
    rct(d, hx + 4, hy + 6, hx + 9, hy + 7, GOLD)
    rct(d, hx + 4, hy + 6, hx + 9, hy + 6, HOLY)
    rct(d, hx + 4, hy + 8, hx + 9, hy + 8, GOLD)
    rct(d, hx + 4, hy + 9, hx + 9, hy + 9, GOLD_D)
    rct(d, hx + 5, hy + 10, hx + 8, hy + 10, GOLD_D)
    px(d, hx + 9, hy + 7, GOLD_L)
    px(d, hx + 6, hy + 7, GOLD_L)
    off = t % 3
    px(d, hx + 8, hy + 4, HOLY)
    px(d, hx + 9, hy + 2 - off, SMOKE)
    px(d, hx + 8, hy - off, light(SMOKE, 1.08))
    px(d, hx + 9, hy - 3 - off, HOLY)


def olive_branch(d, hx, hy, sw=0):
    ln(d, hx + 2, hy, hx + 9, hy - 4 + sw, OLIVE, 2)
    for (lx, ly) in ((hx + 3, hy - 3), (hx + 5, hy - 5), (hx + 7, hy - 4), (hx + 9, hy - 8)):
        rct(d, lx, ly + sw, lx + 1, ly + 1 + sw, GREEN)
        px(d, lx, ly + sw, light(GREEN, 1.22))
        px(d, lx + 1, ly + 1 + sw, dark(GREEN, 0.74))
    rct(d, hx + 10, hy - 9 + sw, hx + 11, hy - 8 + sw, GREEN)
    px(d, hx + 10, hy - 9 + sw, light(GREEN, 1.22))


def hammer(d, x, y):
    rct(d, x, y, x + 1, y + 8, WOOD)
    rct(d, x, y, x, y + 8, WOOD_L)
    px(d, x + 1, y + 8, WOOD_D)
    rct(d, x - 3, y + 6, x + 4, y + 9, IRON)
    rct(d, x - 3, y + 6, x + 4, y + 6, STEEL)
    rct(d, x - 3, y + 9, x + 4, y + 9, IRON_D)
    px(d, x - 3, y + 7, light(STEEL, 1.08))
    px(d, x - 3, y + 8, STEEL)
    px(d, x + 4, y + 7, dark(IRON, 0.78))
    px(d, x + 4, y + 8, dark(IRON, 0.78))


def tambourine(d, cx, cy, r=5):
    ell(d, cx - r, cy - r, cx + r, cy + r, WOOD)
    ell(d, cx - r, cy - r, cx + r, cy + r - 1, WOOD_L)
    ell(d, cx - r + 1, cy - r + 1, cx + r - 1, cy + r - 1, LINEN)
    ell(d, cx - r + 2, cy - r + 2, cx + r - 2, cy + r - 2, light(LINEN, 1.12))
    ln(d, cx - 2, cy - r + 2, cx - 2, cy + r - 2, LINEN_D, 1)
    ln(d, cx + 2, cy - r + 2, cx + 2, cy + r - 2, LINEN_D, 1)
    ln(d, cx - r + 2, cy, cx + r - 2, cy, LINEN_D, 1)
    for (bx, by) in ((cx - r, cy), (cx + r, cy), (cx, cy + r), (cx - 3, cy + r), (cx + 3, cy + r)):
        rct(d, bx, by, bx + 1, by, GOLD)
        px(d, bx, by, GOLD_L)
    px(d, cx - r + 1, cy - r + 2, HOLY)


def menorah(d, gx, by):
    rct(d, gx - 5, by, gx + 5, by, GOLD_D)
    rct(d, gx - 4, by - 1, gx + 4, by - 1, GOLD)
    rct(d, gx - 4, by - 1, gx + 4, by - 1, GOLD_L)
    rct(d, gx - 3, by - 2, gx + 3, by - 2, GOLD_D)
    rct(d, gx - 1, by - 3, gx + 1, by - 2, GOLD)
    rct(d, gx, by - 22, gx + 1, by - 3, GOLD)
    rct(d, gx, by - 22, gx, by - 3, GOLD_L)
    rct(d, gx + 1, by - 22, gx + 1, by - 3, GOLD_D)
    rct(d, gx - 7, by - 23, gx + 8, by - 22, GOLD)
    rct(d, gx - 7, by - 23, gx + 8, by - 23, GOLD_L)
    rct(d, gx - 7, by - 22, gx + 8, by - 22, GOLD_D)
    for k, sy in ((1, by - 15), (2, by - 12), (3, by - 9)):
        ln(d, gx, sy, gx - 2 * k, sy - 4, GOLD, 1)
        ln(d, gx - 2 * k, sy - 4, gx - 2 * k, by - 24, GOLD, 1)
        px(d, gx - 2 * k, sy - 4, GOLD_D)
    for k, sy in ((1, by - 15), (2, by - 12), (3, by - 9)):
        ln(d, gx + 1, sy, gx + 1 + 2 * k, sy - 4, GOLD, 1)
        ln(d, gx + 1 + 2 * k, sy - 4, gx + 1 + 2 * k, by - 24, GOLD, 1)
        px(d, gx + 1 + 2 * k, sy - 4, GOLD_D)
    cols = [gx - 6, gx - 4, gx - 2, gx, gx + 2, gx + 4, gx + 6]
    for i, col in enumerate(cols):
        rct(d, col, by - 25, col, by - 24, GOLD_L)
        h = 2 + (i % 3)
        px(d, col, by - 26, FLAME_O)
        px(d, col, by - 27 - (h - 2), FLAME)
        px(d, col, by - 28 - (h - 2), HOLY)


def eagle(d, x, y):
    """白头海雕：白头+钩喙、褐翅展开、深色尾羽。x,y = 左上。"""
    # 身体
    ell(d, x, y + 5, x + 5, y + 11, BROWN)
    ell(d, x + 1, y + 6, x + 5, y + 10, dark(BROWN, 0.86))
    # 头（白）
    ell(d, x + 2, y + 1, x + 6, y + 6, WHT)
    rct(d, x + 3, y + 1, x + 5, y + 5, WHT)
    px(d, x + 4, y + 2, WHT_L)
    px(d, x + 6, y + 3, GOLD)              # 喙
    px(d, x + 7, y + 4, GOLD_D)
    px(d, x + 5, y + 2, OUTLINE)           # 眼
    # 翅（向后上方展开）
    tline(d, x + 1, y + 7, x - 3, y + 4, BROWN_D, 2)
    tline(d, x + 2, y + 8, x - 2, y + 6, dark(BROWN, 0.92), 1)
    px(d, x - 4, y + 3, BROWN_D)
    px(d, x - 3, y + 2, dark(BROWN_D, 0.86))
    tline(d, x + 5, y + 7, x + 8, y + 5, dark(BROWN, 0.90), 1)
    px(d, x + 9, y + 4, BROWN_D)
    # 尾羽（短，别压到手臂）
    tline(d, x + 3, y + 11, x + 2, y + 13, WHT_D, 2)
    px(d, x + 1, y + 14, dark(WHT_D, 0.84))
    px(d, x + 4, y + 13, dark(WHT_D, 0.84))
    # 爪
    px(d, x + 2, y + 12, GOLD_D)
    px(d, x + 5, y + 12, GOLD_D)


def halo(d, cx, cy, r=8):
    pts = []
    for k in range(120):
        a = k * math.pi / 60.0
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.94))
    for i in range(len(pts) - 1):
        x0, y0 = pts[i]
        x1, y1 = pts[i + 1]
        ln(d, int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1)),
           GOLD_L if y0 < cy else GOLD, 1)
    for (dx, dy) in ((-10, -2), (10, -2), (-6, -9), (6, -9), (-10, 3), (10, 3)):
        px(d, cx + dx, cy + dy, HOLY)
    for (dx, dy) in ((-11, 0), (11, 0)):
        px(d, cx + dx, cy + dy, GOLD)


# ---------------------------------------------------------------- 1 大卫
def david(p):
    im = new_cell()
    d = ImageDraw.Draw(im)
    g = geo(p["bob"], p["sway"])
    cx, sh, ht = g["cx"], g["sh"], g["ht"]
    e = p["ex"]
    CAPE = mix(ROYAL, OUTLINE, 0.40)
    poly(d, [(cx - 4, sh), (cx + 2, sh + 2), (cx + 3, 33), (cx - 8 - e, 41), (cx - 3, 41)], CAPE)
    poly(d, [(cx - 4, sh + 1), (cx + 1, sh + 3), (cx + 1, 32), (cx - 6 - e, 39)], light(CAPE, 1.18))
    ln(d, cx - 8 - e, 41, cx - 3, 41, GOLD_D, 1)
    ln(d, cx - 6 - e, 26, cx - 7 - e, 38, dark(CAPE, 0.70), 1)
    px(d, cx - 7 - e, 36, GOLD)
    legs(d, p, cx, TAN_SKIN, TAN_SKIN, LEATHER)
    prof = [(sh, 5), (sh + 1, 5), (sh + 2, 5), (sh + 3, 5), (sh + 4, 5), (sh + 5, 4),
            (sh + 6, 4), (sh + 7, 4), (sh + 8, 4), (sh + 9, 5), (sh + 10, 5), (sh + 11, 5)]
    body(d, cx, prof, PURPLE, 0.68, 1.20)
    taper(d, cx, sh + 12, 35, 5, 6, PURPLE, 0.68, 1.18)
    ln(d, cx - 3, sh + 2, cx - 2, sh + 10, dark(PURPLE, 0.54), 1)
    ln(d, cx + 1, sh + 4, cx + 2, sh + 10, dark(PURPLE, 0.58), 1)
    ln(d, cx - 2, 24, cx + 1, 31, dark(PURPLE, 0.60), 1)
    ln(d, cx + 2, 33, cx + 4, 34, dark(PURPLE, 0.60), 1)
    rct(d, cx - 1, sh, cx - 1, sh + 9, GOLD_D)
    px(d, cx - 1, sh, GOLD_L)
    rct(d, cx - 6, 34, cx + 6, 35, GOLD)
    rct(d, cx - 6, 35, cx + 6, 35, GOLD_D)
    rct(d, cx - 6, 34, cx - 4, 34, GOLD_L)
    rct(d, cx - 6, 28, cx + 6, 29, GOLD)
    rct(d, cx - 6, 28, cx + 6, 28, GOLD_L)
    rct(d, cx - 6, 29, cx + 6, 29, GOLD_D)
    rct(d, cx - 1, 28, cx + 1, 29, light(GOLD, 1.12))
    arm_far(d, cx, sh, PURPLE, p["aly"], SKIN)
    nx, ny = arm_near(d, cx, sh, PURPLE, p["ary"], SKIN, dk=0.82)
    face(d, g, SKIN)
    hair_long(d, cx, ht, AUB, [(2, -5, -4), (3, -5, -3), (4, -5, -3), (5, -5, -4),
                               (6, -5, -4), (7, -5, -4), (8, -6, -4), (9, -6, -5),
                               (10, -6, -5), (11, -6, -6), (12, -6, -6), (13, -6, -5)],
              cap_rows=(-1, 0))
    rct(d, cx - 5, ht + 2, cx - 4, ht + 4, light(AUB, 1.14))
    px(d, cx - 3, ht + 3, AUB_L)
    px(d, cx + 3, ht + 2, AUB)
    px(d, cx + 3, ht + 3, AUB_D)
    rct(d, cx - 5, ht - 2, cx + 5, ht, GOLD)
    rct(d, cx - 5, ht - 2, cx + 5, ht - 2, GOLD_L)
    rct(d, cx - 5, ht, cx + 5, ht, GOLD_D)
    for k in (-4, 0, 4):
        rct(d, cx + k, ht - 4, cx + k, ht - 3, GOLD_L)
        px(d, cx + k, ht - 5, GOLD)
    px(d, cx - 2, ht - 1, CRIMSON)
    px(d, cx + 2, ht - 1, CRIMSON)
    px(d, cx, ht - 1, HOLY)
    harp(d, cx - 17, ht + 4)
    hand(d, cx - 9, ht + 13, SKIN)
    sling(d, nx, ny, sw=e)
    hand(d, nx, ny, SKIN)
    return im


# ---------------------------------------------------------------- 2 挪亚
def noah(p):
    im = new_cell()
    d = ImageDraw.Draw(im)
    g = geo(p["bob"], p["sway"])
    cx, sh, ht = g["cx"], g["sh"], g["ht"]
    e = p["ex"]
    # 肩扛木板：从左肩斜向上（整根在头左侧，绝不从脸前面过去）
    bx, by = cx - 5, 20
    fx, fy = 1, 9
    poly(d, [(bx, by), (bx + 2, by - 3), (fx + 2, fy - 3), (fx, fy)], WOOD)
    tline(d, bx + 1, by - 3, fx + 1, fy - 3, WOOD_L, 1)
    tline(d, bx, by - 1, fx, fy - 1, WOOD_D, 1)
    px(d, bx, by, dark(WOOD, 0.62))
    ln(d, bx - 4, by - 4, bx - 1, by - 7, dark(WOOD, 0.70), 1)
    ln(d, bx - 9, by - 8, bx - 6, by - 11, dark(WOOD, 0.70), 1)
    ln(d, bx - 10, by - 4, bx - 6, by - 8, light(WOOD_L, 1.02), 1)
    rct(d, fx, fy - 3, fx + 1, fy, light(WOOD_L, 1.10))
    rct(d, fx, fy - 3, fx + 1, fy - 3, light(WOOD_L, 1.22))
    px(d, bx - 1, by - 3, LEATHER_L)
    px(d, bx - 2, by - 4, LEATHER_L)
    legs(d, p, cx, BROWN, BROWN, LEATHER)
    body(d, cx, [(sh, 6), (sh + 1, 6), (sh + 2, 6), (sh + 3, 5), (sh + 4, 5), (sh + 5, 5),
                 (sh + 6, 5), (sh + 7, 5), (sh + 8, 5), (sh + 9, 6), (sh + 10, 6), (sh + 11, 6)],
         BROWN, 0.68, 1.18)
    taper(d, cx, sh + 12, 38, 6, 6, BROWN, 0.68, 1.16)
    ln(d, cx - 5, sh + 2, cx - 3, 37, dark(BROWN, 0.52), 1)
    ln(d, cx + 3, sh + 4, cx + 2, 37, dark(BROWN, 0.60), 1)
    rct(d, cx - 6, 28, cx + 6, 29, OLIVE)
    rct(d, cx - 6, 28, cx + 6, 28, light(OLIVE, 1.22))
    rct(d, cx - 6, 29, cx + 6, 29, dark(OLIVE, 0.64))
    ln(d, cx - 5, 30, cx - 3, 34, OLIVE, 1)
    px(d, cx - 3, 35, OLIVE)
    # 皮围裙：上窄下宽梯形 + 肩带 + 口袋（浅皮色 vs 深棕袍）
    for y in range(19, 35):
        t = (y - 19) / 15.0
        hw = 2 + int(round(t * 3))
        rct(d, cx - hw, y, cx + hw, y, APRON)
        px(d, cx - hw, y, APRON_D)
        px(d, cx + hw, y, APRON_L)
        px(d, cx + hw - 1, y, dark(APRON, 1.06))
        if y % 4 == 1:
            px(d, cx - 1, y, dark(APRON, 0.86))
            px(d, cx + 2, y, dark(APRON, 0.90))
    ln(d, cx - 3, 28, cx - 2, 33, dark(APRON, 0.80), 1)
    ln(d, cx + 1, 30, cx + 2, 33, dark(APRON, 0.84), 1)
    rct(d, cx - 2, 19, cx + 2, 19, APRON_L)
    rct(d, cx - 5, 34, cx + 5, 34, APRON_D)
    rct(d, cx - 5, 33, cx + 5, 33, dark(APRON, 1.08))
    ln(d, cx - 3, 19, cx - 2, 22, dark(APRON_D, 0.88), 1)
    ln(d, cx + 3, 19, cx + 2, 22, dark(APRON_D, 0.88), 1)
    rct(d, cx - 2, 26, cx + 2, 28, dark(APRON, 0.86))
    rct(d, cx - 2, 26, cx + 2, 26, APRON_L)
    px(d, cx - 1, 24, BRONZE)
    px(d, cx + 1, 24, BRONZE)
    arm_far(d, cx, sh, BROWN, p["aly"], SKIN_OLIVE)
    nx, ny = arm_near(d, cx, sh, BROWN, p["ary"], SKIN_OLIVE, dk=0.82)
    face(d, g, SKIN_OLIVE, old=True)
    hair_long(d, cx, ht, WHT, [(2, -5, -4), (3, -5, -4), (4, -5, -4), (5, -5, -5),
                               (6, -5, -5), (7, -6, -5), (8, -6, -6), (9, -6, -6),
                               (10, -6, -6)], cap_rows=(-1, 0))
    beard(d, g, WHT, length=10, w=3)
    px(d, cx - 6, ht + 1, WHT_L)
    rct(d, cx - 5, ht + 8, cx - 5, ht + 13, WHT_D)
    ln(d, cx - 3, ht + 11, cx - 3, 20, LEATHER_L, 1)
    ln(d, cx + 3, ht + 11, cx + 3, 20, LEATHER_L, 1)
    olive_branch(d, nx, ny, sw=e)
    hand(d, nx, ny, SKIN_OLIVE)
    hx2 = cx - 9
    hammer(d, hx2, sh + 7 + p["aly"])
    hand(d, hx2, sh + 9 + p["aly"], SKIN_OLIVE)
    return im


# ---------------------------------------------------------------- 3 亚伯拉罕
def abraham(p):
    im = new_cell()
    d = ImageDraw.Draw(im)
    g = geo(p["bob"], p["sway"])
    cx, sh, ht = g["cx"], g["sh"], g["ht"]
    e = p["ex"]
    legs(d, p, cx, SND, SND_D, LEATHER)
    body(d, cx, [(sh, 5), (sh + 1, 5), (sh + 2, 5), (sh + 3, 5), (sh + 4, 5), (sh + 5, 4),
                 (sh + 6, 4), (sh + 7, 4), (sh + 8, 4), (sh + 9, 5), (sh + 10, 5), (sh + 11, 5)],
         SND, 0.70, 1.18)
    taper(d, cx, sh + 12, 42, 5, 7, SND, 0.70, 1.16)
    ln(d, cx - 4, sh + 2, cx - 3, 40, dark(SND, 0.52), 1)
    ln(d, cx + 1, sh + 4, cx + 2, 40, dark(SND, 0.58), 1)
    ln(d, cx - 2, 25, cx + 2, 39, dark(SND, 0.62), 1)
    ln(d, cx + 3, 32, cx + 5, 40, dark(SND, 0.66), 1)
    rct(d, cx - 6, 28, cx + 6, 29, BLUE_D)
    rct(d, cx - 6, 28, cx + 6, 28, NGT_L)
    rct(d, cx - 6, 29, cx + 6, 29, dark(BLUE_D, 0.68))
    rct(d, cx - 1, 28, cx + 1, 29, GOLD)
    px(d, cx, 28, GOLD_L)
    rct(d, cx - 8, 41, cx + 8, 42, BLUE_D)
    rct(d, cx - 8, 42, cx + 8, 42, dark(BLUE_D, 0.62))
    ln(d, cx - 7, 40, cx + 7, 40, NGT_L, 1)
    # 星空披风：盖过双肩，两侧垂到 37，缀金星
    for y in range(sh, 38):
        lw = 8 if y > sh + 10 else 7
        rct(d, cx - lw, y, cx - 4, y, NGT)
        px(d, cx - lw, y, NGT_D)
        px(d, cx - lw + 1, y, dark(NGT, 0.84))
        px(d, cx - 4, y, dark(NGT, 0.72))
        rct(d, cx + 4, y, cx + 7, y, NGT)
        px(d, cx + 7, y, dark(NGT, 0.80))
        px(d, cx + 4, y, dark(NGT, 0.66))
        if y == 30:
            rct(d, cx - lw, y, cx - 4, y, dark(NGT, 0.62))
            rct(d, cx + 4, y, cx + 7, y, dark(NGT, 0.62))
    rct(d, cx - 7, sh - 1, cx + 7, sh, NGT)
    rct(d, cx - 7, sh - 1, cx + 7, sh - 1, NGT_L)
    px(d, cx - 6, sh, dark(NGT, 0.74))
    px(d, cx + 6, sh, dark(NGT, 0.74))
    rct(d, cx - 8, 37, cx + 7, 37, NGT_L)
    rct(d, cx - 8, 38, cx + 7, 38, NGT_D)
    px(d, cx, sh - 1, GOLD)
    for (sx, sy) in ((cx - 6, sh + 4), (cx - 7, sh + 9), (cx - 6, sh + 14),
                     (cx + 6, sh + 3), (cx + 5, sh + 10)):
        px(d, sx, sy, HOLY)
        px(d, sx, sy - 1, GOLD_L)
        px(d, sx, sy + 1, GOLD_L)
    # 胸前斜挎的蓝布
    ln(d, cx - 4, sh + 1, cx + 4, 20, BLUE_D, 2)
    px(d, cx - 1, sh + 2, NGT_L)
    arm_far(d, cx, sh, SND, p["aly"], SKIN_OLIVE)
    nx, ny = arm_near(d, cx, sh, SND, p["ary"], SKIN_OLIVE, dk=0.86)
    face(d, g, SKIN_OLIVE, old=True)
    hair_long(d, cx, ht, WHT, [(2, -5, -4), (3, -5, -4)], cap_rows=(-1, 0))
    beard(d, g, WHT, length=9, w=3)
    for k, yy in enumerate((ht - 4, ht - 3, ht - 2, ht - 1)):
        c = SND_L if k % 2 == 0 else SND
        ins = 0 if k % 2 == 0 else 1
        rct(d, cx - 5 + ins, yy, cx + 5 - ins, yy, c)
    rct(d, cx - 5, ht - 4, cx + 5, ht - 4, light(SND, 1.20))
    rct(d, cx - 5, ht - 1, cx + 5, ht - 1, dark(SND, 0.62))
    rct(d, cx - 5, ht - 3, cx - 5, ht - 2, SND_D)
    px(d, cx + 4, ht - 3, GOLD_L)
    px(d, cx + 3, ht - 2, GOLD)
    px(d, cx + 4, ht - 2, GOLD_L)
    poly(d, [(cx - 5, ht - 1), (cx - 3, ht), (cx - 5 - e, 22), (cx - 8 - e, 20)], SND)
    ln(d, cx - 5, ht - 1, cx - 8 - e, 20, dark(SND, 0.60), 1)
    px(d, cx - 6 - e, 21, light(SND, 1.08))
    censer(d, nx, ny, t=p["t"])
    hand(d, nx, ny, SKIN_OLIVE)
    return im


# ---------------------------------------------------------------- 4 雅各
def jacob(p):
    im = new_cell()
    d = ImageDraw.Draw(im)
    g = geo(p["bob"], p["sway"])
    cx, sh, ht = g["cx"], g["sh"], g["ht"]
    e = p["ex"]
    prop_staff(d, 34, 5)
    rct(d, 33, 4, 35, 5, WOOD)
    rct(d, 32, 3, 34, 4, WOOD_L)
    px(d, 32, 2, WOOD_L)
    px(d, 31, 3, WOOD)
    px(d, 31, 2, light(WOOD_L, 1.08))
    rct(d, 35, 4, 35, 5, WOOD_D)
    for (by, bh) in ((9, 2), (14, 2), (19, 1), (25, 2)):
        rct(d, 33, by, 35, by + bh - 1, LINEN)
        rct(d, 33, by, 35, by, light(LINEN, 1.12))
        rct(d, 35, by, 35, by + bh - 1, LINEN_D)
        px(d, 34, by + bh - 1, LINEN_D)
        px(d, 33, by + bh - 1, dark(LINEN, 0.84))
    ln(d, 34, 16, 33 + e, 21, LINEN, 1)
    ln(d, 34, 27, 33 + e, 32, LINEN_D, 1)
    legs(d, p, cx, BROWN, BROWN, LEATHER)
    body(d, cx, [(sh, 5), (sh + 1, 5), (sh + 2, 5), (sh + 3, 5), (sh + 4, 5), (sh + 5, 4),
                 (sh + 6, 4), (sh + 7, 4), (sh + 8, 4), (sh + 9, 5), (sh + 10, 5), (sh + 11, 5)],
         BROWN, 0.66, 1.14)
    taper(d, cx, sh + 12, 39, 5, 6, BROWN, 0.66, 1.12)
    ln(d, cx - 1, sh + 1, cx + 1, 36, dark(BROWN, 0.52), 1)
    ln(d, cx + 1, sh + 3, cx + 1, 36, dark(BROWN, 0.60), 1)
    # 外层米色罩袍：肩部整片盖住，胸下开襟露 4px 深褐内层
    for y in range(sh, 38):
        if y < sh + 5:
            rct(d, cx - 6, y, cx + 6, y, SND)
            px(d, cx - 6, y, dark(SND, 0.66))
            px(d, cx + 6, y, light(SND, 1.20))
            px(d, cx + 5, y, light(SND, 1.10))
        else:
            rct(d, cx - 6, y, cx - 2, y, SND)
            px(d, cx - 6, y, dark(SND, 0.66))
            px(d, cx - 2, y, light(SND, 1.10))
            rct(d, cx + 3, y, cx + 6, y, SND)
            px(d, cx + 6, y, light(SND, 1.20))
            px(d, cx + 3, y, dark(SND, 0.72))
            px(d, cx + 5, y, light(SND, 1.08))
    rct(d, cx - 6, sh, cx + 6, sh, light(SND, 1.20))
    ln(d, cx - 5, sh + 5, cx - 5, 36, dark(SND, 0.60), 1)
    ln(d, cx + 5, sh + 5, cx + 5, 36, dark(SND, 0.74), 1)
    ln(d, cx - 4, 23, cx - 3, 30, dark(SND, 0.64), 1)
    rct(d, cx - 7, 37, cx + 7, 38, SND)
    rct(d, cx - 7, 37, cx + 7, 37, light(SND, 1.18))
    rct(d, cx - 7, 38, cx + 7, 38, dark(SND, 0.56))
    rct(d, cx - 6, 39, cx + 6, 39, dark(BROWN, 0.78))
    rct(d, cx - 6, 28, cx + 6, 29, LEATHER)
    rct(d, cx - 6, 28, cx + 6, 28, LEATHER_L)
    rct(d, cx - 6, 29, cx + 6, 29, dark(LEATHER, 0.64))
    arm_far(d, cx, sh, SND, p["aly"], SKIN)
    fx = cx - 7
    fy = sh + 6 + p["aly"]
    ell(d, fx - 3, fy - 4, fx + 2, fy + 1, FLEECE)
    ell(d, fx - 4, fy - 2, fx, fy, FLEECE)
    ell(d, fx - 2, fy - 5, fx + 1, fy - 2, light(FLEECE, 1.14))
    px(d, fx - 4, fy - 1, FLEECE_D)
    px(d, fx - 2, fy - 3, FLEECE_D)
    px(d, fx - 1, fy + 1, FLEECE_D)
    px(d, fx + 1, fy - 2, FLEECE_D)
    ln(d, fx - 2, fy - 1, fx - 1, fy + 1, FLEECE_D, 1)
    ln(d, fx - 4, fy - 3, fx - 3, fy - 2, FLEECE_D, 1)
    hand(d, fx - 1, sh + 9 + p["aly"], SKIN)
    nx, ny = arm_near(d, cx, sh, SND, p["ary"], SKIN, dk=0.86)
    rct(d, 32, ny - 2, 33, ny - 1, SND)
    rct(d, 32, ny - 2, 33, ny - 2, light(SND, 1.14))
    hand(d, 33, ny - 2, SKIN)
    face(d, g, SKIN, old=True)
    hair_long(d, cx, ht, HAIR_BRN, [(2, -5, -4), (3, -5, -4), (4, -5, -5), (5, -5, -5),
                                    (6, -6, -5), (7, -6, -5)], cap_rows=(-1, 0))
    beard(d, g, HAIR_BRN, length=4, w=2)
    rct(d, cx - 4, ht - 1, cx + 4, ht - 1, LINEN)
    rct(d, cx - 4, ht - 1, cx, ht - 1, light(LINEN, 1.08))
    px(d, cx + 4, ht - 1, LINEN_D)
    px(d, cx - 1, ht - 1, LINEN_D)
    return im


# ---------------------------------------------------------------- 5 米利暗
def miriam(p):
    im = new_cell()
    d = ImageDraw.Draw(im)
    g = geo(p["bob"], p["sway"])
    cx, sh, ht = g["cx"], g["sh"], g["ht"]
    e = p["ex"]
    poly(d, [(cx - 5, ht + 1), (cx - 2, ht + 2), (cx - 6 - e, 26), (cx - 10 - e, 23)], LINEN_D)
    ln(d, cx - 5, ht + 1, cx - 10 - e, 23, dark(LINEN_D, 0.74), 1)
    legs(d, p, cx, SKIN, SKIN, LEATHER)
    body(d, cx, [(sh, 5), (sh + 1, 5), (sh + 2, 5), (sh + 3, 5), (sh + 4, 5), (sh + 5, 4),
                 (sh + 6, 4), (sh + 7, 4), (sh + 8, 4), (sh + 9, 5), (sh + 10, 5), (sh + 11, 5)],
         LINEN, 0.70, 1.16)
    taper(d, cx, sh + 12, 41, 5, 7, LINEN, 0.70, 1.14)
    ln(d, cx - 4, sh + 2, cx - 3, 40, LINEN_D, 1)
    ln(d, cx + 1, sh + 4, cx + 2, 40, LINEN_D, 1)
    ln(d, cx - 2, 26, cx + 3, 40, dark(LINEN, 0.76), 1)
    ln(d, cx + 4, 33, cx + 6, 40, dark(LINEN, 0.80), 1)
    rct(d, cx - 6, 28, cx + 6, 29, BLUE)
    rct(d, cx - 6, 28, cx + 6, 28, SKY)
    rct(d, cx - 6, 29, cx + 6, 29, dark(BLUE, 0.64))
    rct(d, cx + 3, 29, cx + 5, 31, BLUE)
    px(d, cx + 5, 31, SKY)
    ln(d, cx + 5, 32, cx + 4 + e, 37, BLUE, 1)
    rct(d, cx - 7, 41, cx + 7, 42, BLUE)
    rct(d, cx - 7, 41, cx + 7, 41, SKY)
    rct(d, cx - 7, 42, cx + 7, 42, dark(BLUE, 0.64))
    ln(d, cx - 6, 40, cx + 6, 40, GOLD, 1)
    # 左臂叉腰
    limb(d, cx - 4, sh + 1, cx - 8, sh + 5 + p["aly"], LINEN)
    limb(d, cx - 8, sh + 5 + p["aly"], cx - 4, sh + 8 + p["aly"], LINEN)
    hand(d, cx - 4, sh + 8 + p["aly"], SKIN)
    # 右臂高举（3px 粗 + 蓝袖口）
    limb(d, cx + 4, sh, cx + 9, ht - 3 + p["ary"], LINEN, w=3)
    rct(d, cx + 8, ht - 5 + p["ary"], cx + 11, ht - 3 + p["ary"], LINEN)
    px(d, cx + 8, ht - 5 + p["ary"], LINEN_D)
    rct(d, cx + 4, sh + 2, cx + 6, sh + 3, BLUE)
    px(d, cx + 6, sh + 2, SKY)
    face(d, g, SKIN, lip=CRIMSON)
    hair_long(d, cx, ht, HAIR_BRN, [(2, -5, -5), (3, -5, -5), (4, -5, -4), (5, -5, -4)],
              cap_rows=(-1, 0))
    rct(d, g["hl"] - 1, ht - 3, g["hr"], ht - 1, LINEN)
    rct(d, g["hl"] - 1, ht - 3, g["hr"], ht - 3, light(LINEN, 1.18))
    rct(d, g["hl"] - 1, ht - 2, g["hr"], ht - 2, dark(LINEN, 0.88))
    rct(d, g["hl"] - 1, ht + 1, g["hl"] - 1, ht + 8, LINEN)
    rct(d, g["hl"] - 1, ht + 5, g["hl"] - 1, ht + 5, BLUE)
    rct(d, g["hl"] - 1, ht + 8, g["hl"] + 2, ht + 10, LINEN)
    rct(d, g["hl"], ht + 9, g["hl"] + 1, ht + 9, LINEN_D)
    px(d, g["hl"] + 1, ht + 10, GOLD)
    px(d, g["hl"] - 1, ht + 10, GOLD_D)
    rct(d, g["hr"] - 1, ht - 1, g["hr"] - 1, ht + 3, LINEN)
    ln(d, g["hl"] - 1, ht, g["hr"] - 1, ht, LINEN_D, 1)
    rct(d, g["hl"], ht - 1, g["hr"] - 1, ht - 1, BLUE)
    rct(d, g["hl"], ht - 1, g["hl"] + 2, ht - 1, SKY)
    px(d, g["hr"] - 2, ht - 1, GOLD)
    tcy = ht - 1 + p["ary"]
    tambourine(d, cx + 15, tcy, 5)
    hand(d, cx + 10, ht + p["ary"], SKIN)
    return im


# ---------------------------------------------------------------- 6 摩西
def moses(p):
    im = new_cell()
    d = ImageDraw.Draw(im)
    g = geo(p["bob"], p["sway"])
    cx, sh, ht = g["cx"], g["sh"], g["ht"]
    e = p["ex"]
    poly(d, [(cx - 4, sh), (cx + 3, sh + 1), (cx + 4, 38), (cx - 12 - e, 42), (cx - 3, 42)], BLOODC_D)
    poly(d, [(cx - 4, sh + 1), (cx + 2, sh + 3), (cx + 2, 36), (cx - 10 - e, 41)], BLOODC)
    ln(d, cx - 9 - e, 35, cx - 11 - e, 41, BLOODC_L, 1)
    ln(d, cx - 12 - e, 42, cx - 3, 42, dark(BLOODC_D, 0.62), 1)
    ln(d, cx - 7 - e, 24, cx - 9 - e, 39, dark(BLOODC, 0.68), 1)
    # 铜蛇杖
    rct(d, 34, 12, 35, 44, BRONZE)
    rct(d, 34, 12, 34, 44, light(BRONZE, 1.16))
    rct(d, 35, 12, 35, 44, dark(BRONZE, 0.70))
    # 缠绕蛇身（2px）
    rct(d, 36, 30, 37, 32, BRONZE)
    rct(d, 36, 30, 37, 30, light(BRONZE, 1.14))
    rct(d, 32, 26, 33, 29, BRONZE)
    rct(d, 32, 26, 33, 26, light(BRONZE, 1.14))
    rct(d, 36, 22, 37, 25, BRONZE)
    rct(d, 36, 22, 37, 22, light(BRONZE, 1.14))
    rct(d, 32, 18, 33, 21, BRONZE)
    rct(d, 32, 18, 33, 18, light(BRONZE, 1.14))
    rct(d, 36, 15, 37, 17, BRONZE)
    # 蛇头（朝右，抬在杖顶上方）
    rct(d, 33, 11, 36, 13, BRONZE)
    rct(d, 33, 11, 36, 11, light(BRONZE, 1.22))
    rct(d, 36, 12, 37, 13, BRONZE)
    px(d, 37, 13, dark(BRONZE, 0.68))
    px(d, 35, 12, FLAME_O)                 # 眼
    px(d, 38, 13, FLAME_R)                 # 舌
    px(d, 38, 14, FLAME_R)
    px(d, 33, 14, dark(BRONZE, 0.64))
    legs(d, p, cx, SND, SND, LEATHER)
    body(d, cx, [(sh, 5), (sh + 1, 5), (sh + 2, 5), (sh + 3, 5), (sh + 4, 5), (sh + 5, 4),
                 (sh + 6, 4), (sh + 7, 4), (sh + 8, 4), (sh + 9, 5), (sh + 10, 5), (sh + 11, 5)],
         LINEN, 0.68, 1.20)
    taper(d, cx, sh + 12, 42, 5, 7, LINEN, 0.68, 1.18)
    ln(d, cx - 4, sh + 2, cx - 3, 41, LINEN_D, 1)
    ln(d, cx + 1, sh + 4, cx + 2, 41, LINEN_D, 1)
    ln(d, cx - 2, 26, cx + 3, 41, dark(LINEN, 0.74), 1)
    rct(d, cx - 6, 28, cx + 6, 29, GOLD)
    rct(d, cx - 6, 28, cx + 6, 28, GOLD_L)
    rct(d, cx - 6, 29, cx + 6, 29, GOLD_D)
    rct(d, cx - 7, 41, cx + 7, 42, GOLD_D)
    rct(d, cx - 7, 42, cx + 7, 42, dark(GOLD_D, 0.74))
    ln(d, cx - 6, 40, cx + 6, 40, GOLD, 1)
    # 双石版（灰石，左臂外侧）
    tx = cx - 17
    for k in (0, 5):
        rct(d, tx + k, 18, tx + k + 3, 29, STONE)
        rct(d, tx + k, 18, tx + k, 29, STONE_D)
        rct(d, tx + k + 3, 18, tx + k + 3, 29, STONE_L)
        rct(d, tx + k, 18, tx + k + 3, 18, STONE_L)
        rct(d, tx + k, 29, tx + k + 3, 29, dark(STONE_D, 0.80))
        ell(d, tx + k, 17, tx + k + 3, 19, STONE)
        ell(d, tx + k, 17, tx + k + 3, 18, STONE_L)
        for r in range(4):
            ln(d, tx + k + 1, 20 + r * 2, tx + k + 2, 20 + r * 2, dark(STONE_D, 0.86), 1)
        px(d, tx + k + 1, 20, light(STONE_L, 1.06))
    arm_far(d, cx, sh, LINEN, p["aly"], SKIN_OLIVE)
    hand(d, tx + 4, 24, SKIN_OLIVE)
    halo(d, cx, ht + 4)
    face(d, g, hx("#E8BE92"), old=True)
    px(d, cx - 1, ht + 1, HOLY)
    px(d, cx + 1, ht + 2, light(hx("#E8BE92"), 1.22))
    hair_long(d, cx, ht, WHT, [(2, -5, -4), (3, -5, -4), (4, -5, -4), (5, -5, -5),
                               (6, -5, -5), (7, -6, -5), (8, -6, -6), (9, -6, -6)],
              cap_rows=(-1, 0))
    beard(d, g, WHT, length=10, w=4)
    px(d, cx - 6, ht + 1, WHT_L)
    rct(d, cx + 6, sh + 1, cx + 7, 26 + p["ary"], LINEN)
    rct(d, cx + 7, sh + 1, cx + 7, 26 + p["ary"], light(LINEN, 1.16))
    rct(d, 33, 26 + p["ary"], 34, 27 + p["ary"], LINEN)
    hand(d, 35, 26 + p["ary"], SKIN_OLIVE)
    return im


# ---------------------------------------------------------------- 7 拔摩岛约翰
def john_patmos(p):
    im = new_cell()
    d = ImageDraw.Draw(im)
    g = geo(p["bob"], p["sway"])
    cx, sh, ht = g["cx"], g["sh"], g["ht"]
    e = p["ex"]
    menorah(d, 38, 43)
    legs(d, p, cx, LINEN, LINEN, LEATHER)
    body(d, cx, [(sh, 5), (sh + 1, 5), (sh + 2, 5), (sh + 3, 5), (sh + 4, 5), (sh + 5, 4),
                 (sh + 6, 4), (sh + 7, 4), (sh + 8, 4), (sh + 9, 5), (sh + 10, 5), (sh + 11, 5)],
         LINEN, 0.68, 1.20)
    taper(d, cx, sh + 12, 41, 5, 6, LINEN, 0.68, 1.18)
    ln(d, cx - 4, sh + 2, cx - 3, 40, LINEN_D, 1)
    ln(d, cx + 1, sh + 4, cx + 2, 40, LINEN_D, 1)
    ln(d, cx - 2, 26, cx + 2, 40, dark(LINEN, 0.78), 1)
    rct(d, cx - 6, 28, cx + 6, 29, GOLD)
    rct(d, cx - 6, 28, cx + 6, 28, GOLD_L)
    rct(d, cx - 6, 29, cx + 6, 29, GOLD_D)
    ln(d, cx - 6, 40, cx + 6, 40, GOLD, 1)
    ln(d, cx - 3, sh, cx + 2, sh + 1, GOLD, 1)
    ln(d, cx - 1, sh, cx - 1, sh + 3, GOLD_D, 1)
    arm_far(d, cx, sh, LINEN, p["aly"], SKIN_PALE)
    # 鹰（左肩，站在披肩上）
    eagle(d, cx - 15, sh - 8)
    limb(d, cx + 5, sh, cx + 8, sh + 4 + p["ary"], LINEN)
    hand(d, cx + 8, sh + 5 + p["ary"], SKIN_PALE)
    px(d, cx + 8, sh + 4 + p["ary"], SKIN_PALE)
    face(d, g, SKIN_PALE, old=True)
    hair_long(d, cx, ht, WHT, [(2, -5, -4), (3, -5, -4), (4, -5, -4), (5, -5, -5),
                               (6, -5, -5), (7, -6, -5), (8, -6, -6), (9, -6, -6)],
              cap_rows=(-1, 0))
    beard(d, g, WHT, length=8, w=3)
    px(d, cx - 6, ht + 1, WHT_L)
    return im


# ---------------------------------------------------------------- 构建
CHARS = [
    ("david", david),
    ("noah", noah),
    ("abraham", abraham),
    ("jacob", jacob),
    ("miriam", miriam),
    ("moses", moses),
    ("john_patmos", john_patmos),
]
BY = dict(CHARS)


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
