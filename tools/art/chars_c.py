"""V4 见证人条带：尼希米 / 以斯帖 / 但以理 / 施洗约翰 / 彼得 / 保罗。

只产出 tools/out/wit_<id>.png（48x384，8 帧横排）+ 预览图，不写 assets/。
几何：脚底 y=44，一律朝右，1px 描边 OUTLINE（artbase.outline(diag=False)）。
8 帧：0-3 站立呼吸（+-1px），4-7 走路（腿 2px 错位 + 手臂反向摆）。
"""
import os
import sys

from PIL import Image, ImageDraw

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(os.path.dirname(_HERE))
sys.path.insert(0, os.path.join(_ROOT, "tools"))

from artbase import (  # noqa: E402
    OUTLINE, SKIN, SKIN_L, SKIN_D, SKIN_S, SKIN_OLIVE, SKIN_PALE, SKIN_DARK,
    HAIR_BLK, HAIR_BRN, HAIR_AUB, HAIR_WHT, HAIR_GRY, HAIR_GLD,
    PURPLE, PURPLE_D, ROYAL, RED, RED_D, CRIMSON, BLUE, BLUE_D, SKY, TEAL,
    GREEN, OLIVE, BROWN, BROWN_D, TAN, SAND, LINEN, LINEN_D, GREY, GREY_D,
    GOLD, GOLD_L, GOLD_D, BRONZE, IRON, IRON_D, STEEL, LEATHER, LEATHER_L,
    FLAME, FLAME_O, HOLY,
    rct, ell, ln, poly, px, dark, light, mix, hx, new_cell,
    outline, save_strip, validate, CELL, FEET,
)

OUT = os.path.join(_ROOT, "tools", "out")

# ---------------------------------------------------------------- 额外色
STONE = hx("#7F8898")
STONE_D = dark(STONE, 0.66)
STONE_L = light(STONE, 1.26)
APRON = hx("#8A6438")
APRON_D = dark(APRON, 0.62)
APRON_L = light(APRON, 1.30)
PARCH = hx("#EADCBA")
PARCH_D = dark(PARCH, 0.66)
PARCH_L = light(PARCH, 1.10)
INK = hx("#43332C")
CHAIN = hx("#C6CED8")
CHAIN_D = hx("#636C79")
CAMEL = hx("#8E6C46")
CAMEL_D = hx("#42301F")
CAMEL_L = hx("#BC9668")
ASH = hx("#9AA0A6")
NETC = hx("#AFC1CD")
NETD = hx("#56697A")
KEYG = hx("#F4D57E")
KEYD = hx("#B08A2E")
LIONC = hx("#C08A3A")
LION_L = hx("#EAC87E")
LION_D = hx("#7A5320")
VEILB = hx("#39527A")
NETB = hx("#26323E")
CORK = hx("#A5763E")
SKIN_WILD = hx("#B27C50")
ROBE_P = hx("#6E3038")
ROBE_PD = hx("#481F26")

# ---------------------------------------------------------------- 骨架
POSES = [
    dict(bob=0, step=0, arm=0),
    dict(bob=1, step=0, arm=0),
    dict(bob=1, step=0, arm=1),
    dict(bob=0, step=0, arm=0),
    dict(bob=0, step=2, arm=-2),
    dict(bob=1, step=0, arm=0),
    dict(bob=0, step=-2, arm=2),
    dict(bob=1, step=0, arm=0),
]


def anchor(p):
    bob = p["bob"]
    return dict(
        bob=bob, step=p["step"], arm=p["arm"],
        cx=24, fy=FEET,
        head_t=6 + bob, head_b=16 + bob,
        neck=17 + bob, torso_t=18 + bob, torso_b=31 + bob,
        waist=28 + bob,
        hand_r=(31 + p["arm"], 27 + bob),
        hand_l=(17 - p["arm"], 27 + bob),
    )


# ---------------------------------------------------------------- 通用绘制
def limb(d, x, y0, y1, c, w=2):
    """竖条肢体（带右亮左暗）。"""
    rct(d, x, y0, x + w - 1, y1, c)
    rct(d, x, y0, x, y1, dark(c, 0.78))
    if w > 2:
        rct(d, x + w - 1, y0, x + w - 1, y1, light(c, 1.16))


def legs(d, P, c_leg, c_boot, wide=3, sole=None, bare=False):
    """走路 2px 错位。返回 (后腿x0, 前腿x0)。"""
    so = P["step"]
    top = P["torso_b"] - 1
    lx, rx = 19 - so, 26 + so
    rct(d, lx, top, lx + wide, FEET - 2, dark(c_leg, 0.82))
    rct(d, lx, top, lx, FEET - 2, dark(c_leg, 0.66))
    rct(d, rx, top, rx + wide, FEET - 2, c_leg)
    rct(d, rx + wide, top, rx + wide, FEET - 2, light(c_leg, 1.14))
    # 脚
    rct(d, lx, FEET - 2, lx + wide + 1, FEET, dark(c_boot, 0.8))
    rct(d, rx, FEET - 2, rx + wide + 1, FEET, c_boot)
    rct(d, rx, FEET - 2, rx + wide + 1, FEET - 2, light(c_boot, 1.22))
    if sole:
        rct(d, lx, FEET, lx + wide + 1, FEET, dark(sole, 0.75))
        rct(d, rx, FEET, rx + wide + 1, FEET, sole)
    return lx, rx


def torso_block(d, P, x0, x1, c, kd=0.70):
    """躯干：1px 肩帽外扩 + 5 阶横向圆柱明暗 + 腰部以下压暗。"""
    y0, y1, wy = P["torso_t"], P["torso_b"], P["waist"]
    rct(d, x0, y0, x1, y1, c)
    rct(d, x0 - 1, y0, x1 + 1, y0, c)
    px(d, x0 - 1, y0, dark(c, kd))
    px(d, x1 + 1, y0, light(c, 1.24))
    rct(d, x0 - 1, y0 + 1, x0, y0 + 1, c)
    rct(d, x1, y0 + 1, x1 + 1, y0 + 1, c)
    px(d, x0 - 1, y0 + 1, dark(c, 0.80))
    px(d, x1 + 1, y0 + 1, light(c, 1.16))
    rct(d, x0, y0 + 1, x0, y1, dark(c, kd))
    rct(d, x0 + 1, y0 + 1, x0 + 1, y1, dark(c, 0.86))
    rct(d, x0 + 2, y0 + 2, x0 + 2, wy - 1, c)
    rct(d, x1, y0 + 1, x1, y1, light(c, 1.22))
    rct(d, x1 - 1, y0 + 2, x1 - 1, y1, mix(c, light(c, 1.22), 0.42))
    rct(d, x0 + 2, wy + 1, x1 - 2, y1, dark(c, 0.93))
    rct(d, x0 + 2, y1, x1 - 2, y1, dark(c, 0.86))


def shoulder_hi(d, P, x0, x1, c):
    rct(d, x0, P["torso_t"], x0 + 2, P["torso_t"], light(c, 1.15))
    rct(d, x1 - 2, P["torso_t"], x1, P["torso_t"], light(c, 1.22))


# ---------------------------------------------------------------- 头 / 脸
HEAD_X0, HEAD_X1 = 19, 28


def head_base(d, P, skin):
    """头底：后脑 2 阶暗 → 右侧受光 → 额头高光 → 下颌 2 阶压暗。"""
    ht, hb = P["head_t"], P["head_b"]
    x0, x1 = HEAD_X0, HEAD_X1
    rct(d, x0, ht, x1, hb, skin)
    rct(d, x0, ht, x0, hb, dark(skin, 0.70))
    rct(d, x0 + 1, ht, x0 + 1, hb, dark(skin, 0.86))
    rct(d, x1, ht, x1, hb, light(skin, 1.12))
    rct(d, x1 - 1, ht + 2, x1 - 1, hb - 2, light(skin, 1.05))
    rct(d, x0 + 2, ht + 2, x1 - 2, ht + 2, light(skin, 1.08))
    px(d, x1 - 2, ht + 5, light(skin, 1.16))
    rct(d, x0 + 2, hb - 1, x1, hb - 1, dark(skin, 0.93))
    rct(d, x0 + 2, hb, x1, hb, dark(skin, 0.82))


def head_hair(d, P, col, rows=2, back=True, hi=None, lo=None):
    """发块：顶受光 + 发际暗线 + 刘海尖；back 时脑后垂到下颌。"""
    ht, hb = P["head_t"], P["head_b"]
    x0, x1 = HEAD_X0, HEAD_X1
    hi = hi if hi is not None else light(col, 1.30)
    lo = lo if lo is not None else dark(col, 0.68)
    for k in range(rows):
        rct(d, x0, ht + k, x1, ht + k, col)
    rct(d, x0 + 1, ht, x1 - 2, ht, hi)
    rct(d, x0, ht + rows - 1, x1, ht + rows - 1, lo)
    px(d, x0 + 3, ht + rows, col)
    px(d, x1 - 2, ht + rows, col)
    px(d, x1 - 1, ht + 1, lo)
    if back:
        rct(d, x0, ht + rows, x0 + 1, hb, col)
        rct(d, x0, ht + rows, x0, hb, lo)


def face(d, P, skin, brow, mouth=None, mrow=6, lash=False, nose=True):
    """眉 ht+3 / 眼 ht+4（1px）/ 侧脸鼻突出 / 口 ht+mrow。"""
    ht = P["head_t"]
    x0, x1 = HEAD_X0, HEAD_X1
    px(d, 20, ht + 3, dark(skin, 0.86))
    if brow is not None:
        rct(d, 21, ht + 3, 22, ht + 3, brow)
        rct(d, 25, ht + 3, 26, ht + 3, brow)
    px(d, 23, ht + 2, dark(skin, 0.92))
    px(d, 22, ht + 4, OUTLINE)
    px(d, 26, ht + 4, OUTLINE)
    if lash:
        px(d, 21, ht + 4, OUTLINE)
        px(d, 27, ht + 4, OUTLINE)
    px(d, 21, ht + 5, dark(skin, 0.94))
    px(d, 22, ht + 5, light(skin, 1.14))
    px(d, 26, ht + 5, light(skin, 1.18))
    if nose:
        px(d, x1 + 1, ht + 4, dark(skin, 0.88))
        px(d, x1 + 1, ht + 5, light(skin, 1.02))
        px(d, x1, ht + mrow, dark(skin, 0.76))
    if mouth is not None:
        rct(d, 24, ht + mrow, 25, ht + mrow, mouth)
        px(d, 23, ht + mrow, dark(skin, 0.90))
    return ht + mrow


def beard(d, P, col, low=3, spread=4, top=None, must=False, side=2, hi=None, lo=None):
    """络腮胡：默认 ht+7 起铺满下颌，1px 须丝 + 下缘碎须 + 鬓角。"""
    ht, hb = P["head_t"], P["head_b"]
    hi = hi if hi is not None else light(col, 1.28)
    lo = lo if lo is not None else dark(col, 0.66)
    y0 = top if top is not None else ht + 7
    y1 = hb + low
    rows = y1 - y0 + 1
    for k in range(rows):
        yy = y0 + k
        ins = 0
        if k >= rows - 2:
            ins = 2
        elif k >= rows - 4:
            ins = 1
        xa, xb = 24 - spread + ins, 24 + spread - ins
        rct(d, xa, yy, xb, yy, col)
        px(d, xa, yy, lo)
        px(d, xb, yy, hi)
        for xx in range(xa + 2, xb - 1, 3):
            px(d, xx, yy, lo if ((xx * 3 + yy * 5) % 7) < 4 else hi)
    if side:
        rct(d, 20, ht + 5, 20 + side - 1, ht + 6, col)
        rct(d, 28, ht + 5, 28, ht + 6, dark(col, 0.92))
    if must:
        rct(d, 23, ht + 6, 26, ht + 6, col)
        px(d, 23, ht + 6, lo)
        px(d, 26, ht + 6, hi)
    for xx in range(24 - spread, 24 + spread):
        if (xx * 5) % 3 == 0:
            px(d, xx, y1 + 1, col)
        elif (xx * 7) % 5 == 0:
            px(d, xx, y1 + 1 + (1 if xx % 2 else 0), lo)
    return y1


def hand(d, x, y, c, w=2):
    rct(d, x, y, x + w - 1, y + w - 1, c)
    rct(d, x, y + w - 1, x + w - 1, y + w - 1, dark(c, 0.76))
    px(d, x + w - 1, y, light(c, 1.1))


def arm(d, p0, elbow, p1, c_sleeve, c_skin, w=2):
    ln(d, p0[0], p0[1], elbow[0], elbow[1], c_sleeve, w)
    ln(d, p0[0], p0[1], elbow[0], elbow[1], dark(c_sleeve, 0.7), 1)
    ln(d, elbow[0], elbow[1], p1[0], p1[1], c_skin, w)
    ln(d, elbow[0] + 1, elbow[1], p1[0] + 1, p1[1], dark(c_skin, 0.74), 1)


# ---------------------------------------------------------------- 纹理 / 网格
def mask_poly(im, pts):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).polygon([(int(a), int(b)) for a, b in pts], fill=255)
    return m


def lattice(d, im, pts, col, edge=None, step=3, fill=None):
    m = mask_poly(im, pts)
    mp = m.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            if mp[x, y] and fill is not None:
                px(d, x, y, fill)
    for y in range(h):
        for x in range(w):
            if mp[x, y] and ((x + y) % step == 0 or (x - y) % step == 0):
                px(d, x, y, col)
    if edge:
        for y in range(1, h - 1):
            for x in range(1, w - 1):
                if mp[x, y] and (not mp[x - 1, y] or not mp[x + 1, y] or
                                 not mp[x, y - 1] or not mp[x, y + 1]):
                    px(d, x, y, edge)
    return m


def fur(d, im, pts, base, hi, lo):
    """毛质笔触：底 + 1px 竖毛 + 交错短刷。"""
    m = mask_poly(im, pts)
    mp = m.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            if mp[x, y]:
                px(d, x, y, base)
    for y in range(0, h, 2):
        for x in range(0, w):
            if not mp[x, y]:
                continue
            v = (x * 13 + y * 29) % 5
            if v == 0:
                px(d, x, y, hi)
            elif v <= 2:
                px(d, x, y, lo)
    for x in range(0, w, 2):
        for y in range(0, h):
            if not mp[x, y]:
                continue
            v = (x * 7 + y * 11) % 6
            if v == 0:
                ln(d, x, y, x, min(h - 1, y + 2), hi, 1)
            elif v == 1:
                ln(d, x, y, x, min(h - 1, y + 1), lo, 1)


# ---------------------------------------------------------------- 道具
def goblet(d, x, y):
    """金杯 6x8：杯口 / 梯形杯身 / 细柄 / 底座，竖条高光。"""
    rct(d, x, y, x + 5, y, GOLD_L)
    rct(d, x, y, x, y, GOLD)
    px(d, x + 2, y, light(GOLD_L, 1.05))
    rct(d, x, y + 1, x + 5, y + 1, GOLD)
    rct(d, x, y + 1, x, y + 3, dark(GOLD, 0.76))
    rct(d, x + 1, y + 2, x + 4, y + 2, GOLD)
    rct(d, x + 1, y + 3, x + 4, y + 3, dark(GOLD, 0.88))
    rct(d, x + 2, y + 4, x + 3, y + 4, dark(GOLD, 0.78))
    rct(d, x + 4, y + 1, x + 5, y + 3, light(GOLD, 1.22))
    px(d, x + 2, y + 1, GOLD_L)
    px(d, x + 1, y + 2, light(GOLD, 1.10))
    rct(d, x + 2, y + 5, x + 3, y + 6, GOLD)
    px(d, x + 3, y + 5, dark(GOLD, 0.80))
    px(d, x + 2, y + 5, GOLD_L)
    rct(d, x, y + 7, x + 5, y + 7, GOLD)
    rct(d, x + 1, y + 7, x + 4, y + 7, GOLD_D)
    px(d, x + 1, y + 7, light(GOLD, 1.20))


def stone_block(d, x, y, w=7, h=6):
    poly(d, [(x, y + 1), (x + 2, y), (x + w - 1, y), (x + w - 2, y + 1)], STONE_L)
    rct(d, x, y + 2, x + w - 1, y + h - 2, STONE)
    rct(d, x, y + 2, x, y + h - 2, STONE_D)
    rct(d, x + w - 1, y + 2, x + w - 1, y + h - 2, light(STONE, 1.24))
    rct(d, x, y + h - 1, x + w - 1, y + h - 1, STONE_D)
    ln(d, x + 1, y + 3, x + 3, y + h - 2, STONE_D, 1)
    ln(d, x + 4, y + 3, x + 5, y + 4, light(STONE, 1.18), 1)
    px(d, x + 3, y + 2, STONE_L)


def hammer(d, hd_, hy, tip):
    """石匠锤：木柄 + 铁头（6x4）。"""
    ln(d, hd_, hy, tip[0], tip[1], LEATHER_L, 2)
    ln(d, hd_ + 1, hy, tip[0] + 1, tip[1], dark(LEATHER_L, 0.72), 1)
    x, y = tip[0] - 4, tip[1] - 2
    rct(d, x, y, x + 7, y + 3, IRON)
    rct(d, x, y, x + 7, y, STEEL)
    rct(d, x, y + 3, x + 7, y + 3, IRON_D)
    rct(d, x, y + 1, x + 1, y + 2, IRON_D)
    rct(d, x + 6, y + 1, x + 6, y + 2, light(STEEL, 1.12))
    px(d, x + 3, y + 1, light(STEEL, 1.16))
    px(d, x + 4, y + 2, dark(STEEL, 0.9))


def crown_gold(d, ht, gem=RED, spikes=3):
    x = 24
    rct(d, x - 5, ht - 2, x + 5, ht, GOLD)
    rct(d, x - 5, ht - 2, x + 5, ht - 2, GOLD_L)
    rct(d, x - 5, ht, x + 5, ht, GOLD_D)
    for k, hh in ((-4, 2), (0, 3), (4, 2))[:spikes]:
        poly(d, [(x + k - 1, ht - 2), (x + k, ht - 2 - hh), (x + k + 1, ht - 2)], GOLD)
        px(d, x + k, ht - 2 - hh, GOLD_L)
        px(d, x + k + 1, ht - 2 - hh, GOLD_D)
    rct(d, x - 1, ht - 1, x + 1, ht - 1, gem)
    px(d, x - 1, ht - 1, light(gem, 1.3))
    px(d, x - 5, ht - 1, GOLD_D)
    px(d, x + 5, ht - 1, GOLD_D)


def scepter(d, x, y0, y1):
    rct(d, x, y0, x + 1, y1, GOLD)
    rct(d, x, y0, x, y1, GOLD_D)
    rct(d, x + 1, y0, x + 1, y1, GOLD_L)
    for yy in range(y0 + 5, y1, 8):
        rct(d, x, yy, x + 1, yy, GOLD_D)
    ell(d, x - 3, y0 - 7, x + 4, y0 - 1, GOLD)
    ell(d, x - 2, y0 - 6, x + 2, y0 - 3, GOLD_L)
    px(d, x + 3, y0 - 3, GOLD_D)
    px(d, x - 3, y0 - 2, GOLD_D)
    px(d, x + 4, y0 - 5, GOLD_L)


def scroll_v(d, x, y, h=10):
    """立卷：上下木轴头（左右各出头 1px）+ 纸面 + 墨行。"""
    rct(d, x + 1, y + 2, x + 4, y + h - 2, PARCH)
    rct(d, x + 1, y + 2, x + 1, y + h - 2, PARCH_L)
    rct(d, x + 4, y + 2, x + 4, y + h - 2, PARCH_D)
    # 上下卷轴（木色，比纸暗 3 阶）
    rct(d, x, y, x + 5, y + 1, LEATHER_L)
    rct(d, x, y, x + 5, y, light(LEATHER_L, 1.35))
    rct(d, x, y + 1, x + 5, y + 1, dark(LEATHER_L, 0.72))
    rct(d, x, y + h - 1, x + 5, y + h, LEATHER_L)
    rct(d, x, y + h - 1, x + 5, y + h - 1, light(LEATHER_L, 1.2))
    rct(d, x, y + h, x + 5, y + h, dark(LEATHER_L, 0.62))
    for yy in range(y + 3, y + h - 2, 2):
        rct(d, x + 2, yy, x + 3, yy, INK)
        px(d, x + 4, yy, PARCH_D)
    px(d, x + 5, y, GOLD_D)
    px(d, x, y + h, GOLD_D)


def scroll_h(d, x, y, w=10, h=5):
    rct(d, x + 1, y, x + w - 1, y + h - 1, PARCH)
    rct(d, x + 1, y, x + w - 1, y, PARCH_L)
    rct(d, x + 1, y + h - 1, x + w - 1, y + h - 1, PARCH_D)
    rct(d, x, y - 1, x + 1, y + h, PARCH_D)
    rct(d, x, y - 1, x, y + h, light(PARCH_D, 1.2))
    rct(d, x + w - 1, y - 1, x + w, y + h, PARCH_D)
    for k in range(2):
        for xx in range(x + 2, x + w - 1, 2):
            px(d, xx, y + 1 + k * 2, INK)


def quill(d, hd_, hy, tip):
    ln(d, hd_, hy, tip[0], tip[1], dark(LINEN, 0.55), 1)
    for k in range(1, 8):
        t = k / 8.0
        xx = int(hd_ + (tip[0] - hd_) * t)
        yy = int(hy + (tip[1] - hy) * t)
        ww = 3 if 1 < k < 6 else 2
        rct(d, xx - ww, yy, xx + ww - (1 if k % 2 else 0), yy, LINEN)
        px(d, xx - ww, yy, LINEN_D)
        px(d, xx + ww - (1 if k % 2 else 0), yy, PARCH_D if k % 2 else LINEN_D)
    px(d, tip[0], tip[1], PARCH)
    px(d, tip[0] + 1, tip[1] - 1, LINEN)
    px(d, hd_, hy, INK)


def key_one(d, x0, y0, x1, y1):
    ln(d, x0, y0, x1, y1, KEYG, 1)
    rct(d, x0 - 1, y0 - 1, x0 + 1, y0 + 1, KEYG)
    px(d, x0, y0, (0, 0, 0, 0))
    px(d, x0, y0 - 1, light(KEYG, 1.1))
    px(d, x0 + 1, y0 + 1, KEYD)
    dx = 1 if x1 >= x0 else -1
    dy = 1 if y1 >= y0 else -1
    px(d, x1 - dx, y1, KEYG)
    px(d, x1, y1 - dy, KEYG)
    px(d, x1 + dx, y1, KEYD)


def chain(d, x, y, n=5, dy=3):
    """锁链：3x2 环（中间 1x2 环孔 + 1px 连接节），垂直连续不留透明缝。"""
    yy = y
    for i in range(n):
        rct(d, x - 1, yy, x + 1, yy + 1, CHAIN)          # 3x2 环体
        px(d, x, yy, CHAIN_D)                             # 环孔上
        px(d, x, yy + 1, dark(CHAIN, 0.26))               # 环孔下
        px(d, x - 1, yy, dark(CHAIN, 0.80))
        px(d, x - 1, yy + 1, dark(CHAIN, 0.66))
        px(d, x + 1, yy, light(CHAIN, 1.12))              # 右缘受光
        px(d, x + 1, yy + 1, CHAIN)
        px(d, x, yy + 2, CHAIN_D)                         # 连接节 → 下一环
        yy += dy
    return yy - dy


def lion_small(d, x, y):
    """8x6 小狮剪影（脚边，朝右）：身 + 鬃毛 + 头 + 四腿 + 尾。"""
    # 身（背亮腹暗）
    rct(d, x + 1, y + 2, x + 5, y + 3, LIONC)
    rct(d, x + 1, y + 2, x + 5, y + 2, LION_L)
    rct(d, x + 1, y + 3, x + 5, y + 3, LION_D)
    # 鬃毛（暗块）+ 脸
    rct(d, x + 5, y, x + 7, y + 3, LION_D)
    rct(d, x + 6, y + 1, x + 7, y + 2, LIONC)
    px(d, x + 7, y + 2, LION_L)
    px(d, x + 6, y + 1, LION_L)
    px(d, x + 5, y, LION_L)
    # 尾
    px(d, x, y + 1, LIONC)
    px(d, x, y + 2, LION_D)
    # 四腿
    rct(d, x + 1, y + 4, x + 2, y + 4, LION_D)
    rct(d, x + 4, y + 4, x + 5, y + 4, LION_D)
    px(d, x + 1, y + 5, LION_D)
    px(d, x + 4, y + 5, LION_D)


def staff_reed(d, x, y0, y1, c=CAMEL_D):
    rct(d, x, y0, x + 1, y1, c)
    rct(d, x, y0, x, y1, dark(c, 0.66))
    rct(d, x + 1, y0, x + 1, y1, light(c, 1.35))
    for yy in range(y0 + 4, y1, 6):
        rct(d, x, yy, x + 1, yy, dark(c, 0.5))
    return x


def waterskin(d, x, y):
    ell(d, x, y, x + 5, y + 5, BROWN)
    ell(d, x + 1, y + 1, x + 3, y + 3, light(BROWN, 1.25))
    rct(d, x, y + 5, x + 5, y + 5, dark(BROWN, 0.62))
    rct(d, x + 2, y - 2, x + 3, y - 1, LEATHER_L)
    px(d, x + 2, y - 2, GOLD_D)
    ln(d, x + 4, y + 2, x + 6, y + 6, LEATHER, 1)


# ---------------------------------------------------------------- 尼希米
def ch_nehemiah(im, d, P, fi):
    c_t = STONE
    y0, y1 = P["torso_t"], P["torso_b"]
    legs(d, P, SKIN_OLIVE, LEATHER, sole=dark(LEATHER, 0.7))
    torso_block(d, P, 18, 30, c_t)
    # 衣褶
    ln(d, 19, y0 + 2, 19, y1 - 1, dark(c_t, 0.8), 1)
    ln(d, 29, y0 + 3, 29, y1 - 1, light(c_t, 1.12), 1)
    # ---- 皮围裙：胸兜 + 下摆
    poly(d, [(21, y0 + 2), (27, y0 + 2), (28, P["waist"] + 1), (20, P["waist"] + 1)], APRON)
    poly(d, [(20, P["waist"] + 1), (28, P["waist"] + 1), (30, 39), (18, 39)], APRON)
    # 明暗：左暗右亮
    poly(d, [(20, P["waist"] + 1), (21, P["waist"] + 1), (19, 39), (18, 39)], APRON_D)
    rct(d, 29, P["waist"] + 2, 30, 38, light(APRON, 1.16))
    rct(d, 18, 39, 30, 39, APRON_D)
    for yy in range(y0 + 3, P["waist"], 2):
        px(d, 21, yy, APRON_D)
        px(d, 27, yy, light(APRON, 1.12))
    for yy in range(P["waist"] + 3, 38, 2):
        px(d, 20, yy, APRON_D)
        px(d, 29, yy, light(APRON, 1.12))
    # 口袋 + 石屑
    rct(d, 21, 33, 27, 33, APRON_D)
    px(d, 22, 32, STONE_L)
    px(d, 24, 32, STONE)
    px(d, 26, 31, STONE_L)
    px(d, 23, 35, STONE_L)
    px(d, 25, 36, STONE)
    px(d, 28, 34, STONE_L)
    # 肩带（跨过肩膀）
    rct(d, 20, y0 - 1, 21, y0 + 2, APRON)
    rct(d, 26, y0 - 1, 27, y0 + 2, APRON)
    rct(d, 20, y0 - 1, 20, y0 + 2, APRON_D)
    px(d, 26, y0 - 1, light(APRON, 1.15))
    # 腰带
    rct(d, 17, P["waist"], 31, P["waist"] + 1, LEATHER)
    rct(d, 17, P["waist"], 31, P["waist"], LEATHER_L)
    rct(d, 23, P["waist"], 25, P["waist"] + 1, GOLD)
    px(d, 24, P["waist"], GOLD_L)
    px(d, 23, P["waist"] + 1, GOLD_D)
    # ---- 头
    ht = P["head_t"]
    head_base(d, P, SKIN_OLIVE)
    head_hair(d, P, HAIR_BRN, rows=2)
    # 皮额巾（比头发亮 2 阶，压在眉上）
    rct(d, 19, ht + 2, 28, ht + 2, LEATHER_L)
    rct(d, 20, ht + 2, 27, ht + 2, light(LEATHER_L, 1.18))
    px(d, 19, ht + 2, dark(LEATHER_L, 0.70))
    px(d, 28, ht + 2, GOLD_D)
    face(d, P, SKIN_OLIVE, dark(HAIR_BRN, 0.85))
    # 两鬓星白
    px(d, 20, ht + 3, HAIR_GRY)
    px(d, 20, ht + 4, HAIR_GRY)
    px(d, 27, ht + 3, light(HAIR_GRY, 1.02))
    beard(d, P, HAIR_BRN, low=2, spread=3, must=True, hi=light(HAIR_BRN, 1.38))
    px(d, 22, P["head_b"] + 2, HAIR_GRY)
    px(d, 26, P["head_b"] + 1, light(HAIR_BRN, 1.3))
    # ---- 左臂：提石块
    lx, ly = 15, 28 + P["bob"]
    arm(d, (19, y0 + 2), (18, 24 + P["bob"]), (lx, ly), c_t, SKIN_OLIVE, 2)
    hand(d, lx, ly, SKIN_OLIVE)
    stone_block(d, 8, 26 + P["bob"], 8, 7)
    # ---- 右臂：举锤
    arm(d, (30, y0 + 2), (33, 25 + P["bob"]), (33, 19 + P["bob"]), c_t, SKIN_OLIVE, 2)
    hand(d, 32, 18 + P["bob"], SKIN_OLIVE)
    hammer(d, 33, 19 + P["bob"], (38, 11 + P["bob"]))
    # ---- 酒政金杯（挂在腰带右端）
    gx, gy = 32, 29 + P["bob"]
    ln(d, 31, P["waist"], gx + 1, gy - 1, GOLD_D, 1)
    goblet(d, gx, gy)
    px(d, gx + 1, gy - 1, GOLD_L)


# ---------------------------------------------------------------- 以斯帖
def ch_esther(im, d, P, fi):
    so = P["step"]
    ht, hb = P["head_t"], P["head_b"]
    y0, y1 = P["torso_t"], P["torso_b"]
    top = P["waist"] + 1
    # ---- 钟形长裙
    poly(d, [(19, top), (29, top), (32, 42), (16, 42)], PURPLE)
    poly(d, [(19, top), (21, top), (18, 42), (16, 42)], PURPLE_D)
    poly(d, [(27, top), (29, top), (32, 42), (30, 42)], light(PURPLE, 1.24))
    for k in range(3):
        xx = 20 + k * 3
        ln(d, xx, top + 2, xx - 1, 41, dark(PURPLE, 0.76), 1)
    ln(d, 26, top + 3, 27, 41, light(PURPLE, 1.16), 1)
    ln(d, 28, top + 2, 29, 41, light(PURPLE, 1.10), 1)
    # 金裙边
    poly(d, [(16, 41), (32, 41), (32, 42), (16, 42)], GOLD)
    rct(d, 16, 41, 20, 41, GOLD_L)
    rct(d, 16, 42, 18, 42, GOLD_D)
    # 鞋
    rct(d, 23 + (1 if so > 0 else 0), 43, 27 + (1 if so > 0 else 0), 44, PURPLE_D)
    rct(d, 26 + (1 if so > 0 else 0), 43, 27 + (1 if so > 0 else 0), 43, ROYAL)
    # ---- 上身
    torso_block(d, P, 19, 29, PURPLE)
    rct(d, 19, y0, 19, P["waist"], PURPLE_D)
    rct(d, 29, y0, 29, P["waist"], light(PURPLE, 1.30))
    ln(d, 23, y0 + 2, 23, P["waist"] - 1, dark(PURPLE, 0.82), 1)
    # 金领口 + 珠宝
    rct(d, 20, y0, 28, y0, GOLD)
    rct(d, 21, y0, 27, y0, GOLD_L)
    px(d, 21, y0 + 1, GOLD)
    px(d, 27, y0 + 1, GOLD)
    px(d, 24, y0 + 1, RED)          # 项坠
    px(d, 24, y0, GOLD_L)
    # 金腰带 + 垂饰
    rct(d, 19, P["waist"], 29, P["waist"] + 1, GOLD)
    rct(d, 20, P["waist"], 28, P["waist"], GOLD_L)
    px(d, 21, P["waist"] + 1, GOLD_D)
    ln(d, 24, P["waist"] + 2, 23, P["waist"] + 5, GOLD, 1)
    px(d, 23, P["waist"] + 6, GOLD_L)
    # ---- 头
    head_base(d, P, SKIN_PALE)
    # 长发：脑后垂下（左）
    rct(d, 17, ht + 1, 20, hb + 7, HAIR_BLK)
    rct(d, 17, ht + 1, 17, hb + 7, dark(HAIR_BLK, 0.72))
    rct(d, 18, ht + 2, 18, hb + 6, light(HAIR_BLK, 1.55))
    ln(d, 19, ht + 4, 19, hb + 6, dark(HAIR_BLK, 0.82), 1)
    px(d, 17, hb + 8, dark(HAIR_BLK, 0.8))
    px(d, 20, hb + 8, HAIR_BLK)
    # 头顶（冠下露发）
    rct(d, 19, ht, 28, ht, HAIR_BLK)
    rct(d, 19, ht + 1, 21, ht + 1, HAIR_BLK)
    px(d, 22, ht, light(HAIR_BLK, 1.6))
    px(d, 26, ht, light(HAIR_BLK, 1.35))
    # 右颊前发绺（包住脸侧）
    rct(d, 27, ht + 2, 28, hb + 5, HAIR_BLK)
    rct(d, 27, ht + 2, 27, hb + 5, dark(HAIR_BLK, 0.82))
    px(d, 28, ht + 3, light(HAIR_BLK, 1.6))
    px(d, 28, ht + 7, light(HAIR_BLK, 1.35))
    px(d, 26, hb + 5, HAIR_BLK)
    px(d, 28, hb + 5, dark(HAIR_BLK, 0.8))
    px(d, 27, hb + 6, HAIR_BLK)
    # 脸（无胡）
    face(d, P, SKIN_PALE, None, mrow=7, lash=True, nose=False)
    px(d, 27, ht + 6, dark(SKIN_PALE, 0.82))
    rct(d, 23, ht + 7, 25, ht + 7, RED)
    px(d, 22, ht + 7, dark(RED, 0.8))
    px(d, 26, ht + 7, light(RED, 1.18))
    px(d, 24, ht + 8, dark(SKIN_PALE, 0.88))
    # 金冠 + 耳环
    crown_gold(d, ht)
    px(d, 19, ht + 5, GOLD_L)
    px(d, 20, ht + 6, GOLD)
    px(d, 21, ht + 7, GOLD_D)
    # ---- 右臂（持王杖）
    rx = 31 + P["arm"]
    arm(d, (28, y0 + 2), (31, 24 + P["bob"]), (rx, 27 + P["bob"]), PURPLE, SKIN_PALE, 2)
    rct(d, 27, y0 + 1, 30, y0 + 6, ROYAL)     # 宽袖
    rct(d, 27, y0 + 1, 27, y0 + 6, PURPLE_D)
    px(d, 30, y0 + 6, GOLD)
    scepter(d, rx + 1, 15 + P["bob"], 38 + P["bob"])
    hand(d, rx, 27 + P["bob"], SKIN_PALE)
    px(d, rx + 1, 27 + P["bob"], SKIN_PALE)      # 拇指压在杖上
    px(d, rx + 2, 27 + P["bob"], dark(SKIN_PALE, 0.82))
    px(d, rx + 1, 28 + P["bob"], dark(SKIN_PALE, 0.86))
    # ---- 左臂
    arm(d, (21, y0 + 2), (18, 24 + P["bob"]), (16, 26 + P["bob"]), PURPLE, SKIN_PALE, 2)
    rct(d, 19, y0 + 1, 21, y0 + 5, dark(PURPLE, 0.85))
    hand(d, 16, 26 + P["bob"], SKIN_PALE)


# ---------------------------------------------------------------- 但以理
def ch_daniel(im, d, P, fi):
    so = P["step"]
    ht, hb = P["head_t"], P["head_b"]
    y0, y1 = P["torso_t"], P["torso_b"]
    # ---- 长袍
    poly(d, [(20, 30), (28, 30), (30, 42), (18, 42)], BLUE_D)
    poly(d, [(20, 30), (22, 30), (20, 42), (18, 42)], dark(BLUE_D, 0.72))
    poly(d, [(26, 30), (28, 30), (30, 42), (28, 42)], light(BLUE_D, 1.32))
    for k in range(3):
        xx = 21 + k * 2
        ln(d, xx, 32, xx - 1, 41, dark(BLUE_D, 0.8), 1)
    ln(d, 27, 32, 28, 41, light(BLUE_D, 1.2), 1)
    rct(d, 18, 42, 30, 42, dark(BLUE_D, 0.62))
    # 金中缝
    rct(d, 23, 30, 24, 42, GOLD)
    rct(d, 23, 30, 23, 42, GOLD_L)
    rct(d, 24, 30, 24, 42, GOLD_D)
    # 鞋
    rct(d, 23 + (1 if so > 0 else 0), 43, 28 + (1 if so > 0 else 0), 44, LEATHER)
    rct(d, 27 + (1 if so > 0 else 0), 43, 28 + (1 if so > 0 else 0), 43, LEATHER_L)
    # ---- 上身朝服
    torso_block(d, P, 18, 30, BLUE_D)
    poly(d, [(18, y0), (22, y0), (23, y1), (19, y1)], dark(BLUE_D, 0.84))
    rct(d, 23, y0, 24, y1, GOLD)
    rct(d, 23, y0, 23, y1, GOLD_L)
    # 高领
    rct(d, 20, y0 - 1, 28, y0, GOLD)
    rct(d, 20, y0 - 1, 28, y0 - 1, GOLD_L)
    rct(d, 22, y0 + 1, 26, y0 + 1, GOLD_D)
    # 官链（胸前 U 形）
    for xx, yy in [(20, y0 + 3), (21, y0 + 5), (23, y0 + 6), (26, y0 + 5), (28, y0 + 3)]:
        px(d, xx, yy, GOLD)
    px(d, 24, y0 + 6, GOLD_L)
    px(d, 22, y0 + 6, GOLD_L)
    # 腰带
    rct(d, 18, P["waist"], 30, P["waist"] + 1, GOLD_D)
    rct(d, 18, P["waist"], 30, P["waist"], GOLD)
    rct(d, 23, P["waist"], 25, P["waist"] + 1, GOLD_L)
    px(d, 24, P["waist"], HOLY)
    # ---- 头
    head_base(d, P, SKIN_OLIVE)
    # 波斯官帽：顶金沿(ht-5) + 冠(ht-5..ht-4) + 金箍(ht-4) + 蓝筒(ht-3..ht-2) + 宽金檐(ht-1)
    # 顶部从 ht-5 起，行 0 留给 1px 描边，不再被单元格裁掉
    rct(d, 21, ht - 5, 25, ht - 4, BLUE_D)              # 冠
    rct(d, 21, ht - 5, 21, ht - 4, dark(BLUE_D, 0.72))
    rct(d, 25, ht - 5, 25, ht - 4, light(BLUE_D, 1.38))
    rct(d, 20, ht - 5, 26, ht - 5, GOLD)                # 顶沿
    rct(d, 21, ht - 5, 25, ht - 5, GOLD_L)
    px(d, 23, ht - 5, light(GOLD_L, 1.10))
    rct(d, 18, ht - 4, 28, ht - 4, GOLD_D)              # 金箍（比冠宽，肩住冠）
    rct(d, 20, ht - 4, 26, ht - 4, GOLD)
    rct(d, 18, ht - 3, 28, ht - 2, BLUE_D)              # 筒
    rct(d, 18, ht - 3, 18, ht - 2, dark(BLUE_D, 0.78))
    rct(d, 28, ht - 3, 28, ht - 2, light(BLUE_D, 1.34))
    rct(d, 22, ht - 3, 22, ht - 2, light(BLUE_D, 1.16))
    rct(d, 18, ht - 1, 28, ht - 1, GOLD_L)              # 宽金檐
    px(d, 18, ht - 1, GOLD_D)
    px(d, 19, ht - 1, light(GOLD_L, 1.08))
    px(d, 26, ht - 2, RED)                              # 红宝石
    px(d, 26, ht - 2, CRIMSON)
    px(d, 24, ht - 3, GOLD_D)
    # 帽下鬓发
    rct(d, 19, ht, 28, ht, HAIR_BLK)
    rct(d, 18, ht + 1, 18, ht + 2, HAIR_BLK)
    px(d, 19, ht, light(HAIR_BLK, 2.2))
    px(d, 24, ht, light(HAIR_BLK, 1.6))
    rct(d, 27, ht + 1, 27, ht + 2, HAIR_BLK)
    face(d, P, SKIN_OLIVE, HAIR_BLK)
    px(d, 28, ht + 3, light(SKIN_OLIVE, 1.18))
    beard(d, P, HAIR_BLK, low=2, spread=3, must=True, top=ht + 8,
          hi=light(HAIR_BLK, 2.4), lo=light(HAIR_BLK, 1.3))
    rct(d, 21, hb + 2, 26, hb + 2, HAIR_BLK)
    px(d, 23, hb + 2, light(HAIR_BLK, 1.7))
    # ---- 左臂：举卷轴
    scroll_v(d, 9, 16 + P["bob"], 11)          # 先画卷，手压右轴 = 握住
    lx, ly = 14, 23 + P["bob"]
    arm(d, (19, y0 + 2), (18, 21 + P["bob"]), (lx, ly), BLUE_D, SKIN_OLIVE, 2)
    hand(d, lx, ly, SKIN_OLIVE)
    px(d, lx + 1, ly, light(SKIN_OLIVE, 1.12))
    px(d, lx + 1, ly + 1, dark(SKIN_OLIVE, 0.82))
    # ---- 右臂：前指
    rx = 29 + P["arm"]
    arm(d, (29, y0 + 2), (31, 23 + P["bob"]), (rx + 2, 26 + P["bob"]), BLUE_D, SKIN_OLIVE, 2)
    rct(d, 29, 23 + P["bob"], 31, 24 + P["bob"], GOLD)
    hand(d, rx + 1, 25 + P["bob"], SKIN_OLIVE)
    # ---- 脚边小狮
    lion_small(d, 4, 37)


# ---------------------------------------------------------------- 施洗约翰
def ch_john_baptist(im, d, P, fi):
    ht, hb = P["head_t"], P["head_b"]
    y0, y1 = P["torso_t"], P["torso_b"]
    legs(d, P, SKIN_DARK, SKIN_DARK, sole=dark(BROWN, 0.7))
    # ---- 骆驼毛衣
    fur(d, im, [(18, y0), (30, y0), (31, y1 + 7), (18, y1 + 7)], CAMEL_L,
        light(CAMEL_L, 1.16), CAMEL)
    # 下摆碎毛
    for xx in range(17, 32):
        hsh = (xx * 7) % 3
        ln(d, xx, y1 + 6, xx, y1 + 7 + hsh, CAMEL_D if xx % 2 else dark(CAMEL, 0.8), 1)
    # 肩线
    for xx in range(18, 31):
        px(d, xx, y0 - 1, CAMEL_D if xx % 3 else CAMEL_L)
    # 皮腰带
    rct(d, 17, P["waist"], 31, P["waist"] + 1, LEATHER)
    rct(d, 17, P["waist"], 31, P["waist"], LEATHER_L)
    rct(d, 20, P["waist"] - 1, 21, P["waist"] + 2, LEATHER)
    rct(d, 21, P["waist"] + 1, 23, P["waist"] + 3, dark(LEATHER, 0.78))
    ln(d, 19, P["waist"] + 2, 18, P["waist"] + 8, LEATHER, 1)
    px(d, 18, P["waist"] + 8, dark(LEATHER, 0.7))
    # 水囊
    waterskin(d, 11, 30 + P["bob"])
    # ---- 头
    head_base(d, P, SKIN_WILD)
    head_hair(d, P, HAIR_BRN, rows=2, hi=light(HAIR_BRN, 1.6))
    # 蓬乱长发（到肩，边缘参差）
    rct(d, 17, ht + 1, 19, hb + 3, HAIR_BRN)
    rct(d, 17, ht + 1, 17, hb + 3, dark(HAIR_BRN, 0.78))
    px(d, 18, ht + 2, light(HAIR_BRN, 1.5))
    px(d, 17, hb + 4, HAIR_BRN)
    px(d, 16, hb + 1, dark(HAIR_BRN, 0.9))
    px(d, 18, hb + 5, HAIR_BRN)
    px(d, 19, hb + 4, light(HAIR_BRN, 1.35))
    rct(d, 27, ht, 28, ht + 1, HAIR_BRN)
    px(d, 28, ht + 2, dark(HAIR_BRN, 0.9))
    px(d, 27, ht + 2, HAIR_BRN)
    px(d, 29, ht, dark(HAIR_BRN, 0.85))
    # 脸 + 深眼窝
    face(d, P, SKIN_WILD, dark(HAIR_BRN, 0.8))
    px(d, 21, ht + 5, dark(SKIN_WILD, 0.58))
    # 长须（垂到胸前）
    beard(d, P, HAIR_BRN, low=6, spread=4, must=True, side=2,
          hi=light(HAIR_BRN, 1.55))
    for xx in range(20, 29, 2):
        px(d, xx, hb + 7, light(HAIR_BRN, 1.25) if xx % 4 else dark(HAIR_BRN, 0.9))
    # ---- 左臂
    arm(d, (19, y0 + 2), (18, 24 + P["bob"]), (16, 28 + P["bob"]), CAMEL_D, SKIN_WILD, 2)
    hand(d, 16, 28 + P["bob"], SKIN_WILD)
    # ---- 右臂（握苇杖）
    rx = 31 + P["arm"]
    arm(d, (30, y0 + 2), (32, 22 + P["bob"]), (rx, 26 + P["bob"]), CAMEL_D, SKIN_WILD, 2)
    sx = rx + 2
    staff_reed(d, sx, 8, 44)
    hand(d, rx, 27 + P["bob"], SKIN_WILD)
    px(d, sx + 1, 27 + P["bob"], light(SKIN_WILD, 1.12))     # 手指压在杆上
    px(d, sx + 1, 28 + P["bob"], dark(SKIN_WILD, 0.85))
    px(d, sx, 27 + P["bob"], dark(SKIN_WILD, 0.82))
    ln(d, sx, 9, sx - 2, 5, OLIVE, 1)
    ln(d, sx + 1, 9, sx + 2, 4, OLIVE, 1)
    ln(d, sx, 9, sx, 4, SAND, 1)
    ln(d, sx + 1, 9, sx + 3, 6, dark(OLIVE, 0.85), 1)
    px(d, sx, 4, light(SAND, 1.12))
    px(d, sx + 2, 4, SAND)
    px(d, sx - 2, 5, dark(OLIVE, 0.8))
    px(d, sx + 3, 6, OLIVE)
    px(d, sx - 1, 6, SAND)
    rct(d, sx - 1, 10, sx + 1, 10, LEATHER)
    rct(d, sx - 1, 13, sx + 1, 13, LEATHER)


# ---------------------------------------------------------------- 彼得
def ch_peter(im, d, P, fi):
    ht, hb = P["head_t"], P["head_b"]
    y0, y1 = P["torso_t"], P["torso_b"]
    # ---- 腿（粗壮，草鞋）
    lx, rx = legs(d, P, SKIN_OLIVE, LEATHER, wide=4, sole=dark(LEATHER, 0.72))
    # 脚踝阴影（不做成条纹）
    rct(d, lx, 41, lx + 4, 41, dark(SKIN_OLIVE, 0.78))
    rct(d, rx, 41, rx + 4, 41, dark(SKIN_OLIVE, 0.78))
    px(d, rx + 3, 40, light(SKIN_OLIVE, 1.14))
    # ---- 短袍
    end = 36
    torso_block(d, P, 17, 31, GREY_D)
    poly(d, [(17, 31), (31, 31), (32, end), (16, end)], GREY_D)
    poly(d, [(17, 31), (19, 31), (18, end), (16, end)], dark(GREY_D, 0.7))
    poly(d, [(29, 31), (31, 31), (32, end), (30, end)], light(GREY_D, 1.34))
    ln(d, 20, 32, 19, end - 1, dark(GREY_D, 0.8), 1)
    ln(d, 27, 32, 28, end - 1, light(GREY_D, 1.22), 1)
    ln(d, 23, 32, 22, end - 1, dark(GREY_D, 0.86), 1)
    # 麻布下摆 / 领口
    rct(d, 16, end, 32, end, LINEN_D)
    rct(d, 16, end, 24, end, LINEN)
    rct(d, 21, y0, 27, y0, LINEN)
    px(d, 24, y0 + 1, LINEN)
    px(d, 25, y0 + 1, LINEN_D)
    # 皮腰带 + 绳结
    rct(d, 16, P["waist"], 32, P["waist"] + 1, LEATHER)
    rct(d, 16, P["waist"], 32, P["waist"], LEATHER_L)
    rct(d, 23, P["waist"], 24, P["waist"] + 1, IRON_D)
    ln(d, 22, P["waist"] + 2, 21, P["waist"] + 5, SAND, 1)
    px(d, 21, P["waist"] + 5, SAND)
    # ---- 头
    head_base(d, P, SKIN_OLIVE)
    head_hair(d, P, HAIR_GRY, rows=2, hi=light(HAIR_GRY, 1.16))
    # 卷发/鬓角
    rct(d, 17, ht + 1, 19, hb - 1, HAIR_GRY)
    rct(d, 17, ht + 1, 17, hb - 1, dark(HAIR_GRY, 0.78))
    px(d, 17, hb, HAIR_GRY)
    px(d, 18, ht + 4, light(HAIR_GRY, 1.2))
    rct(d, 26, ht + 1, 28, ht + 2, HAIR_GRY)
    px(d, 28, ht + 3, dark(HAIR_GRY, 0.9))
    face(d, P, SKIN_OLIVE, dark(HAIR_GRY, 0.85))
    # 灰白络腮短须
    beard(d, P, HAIR_GRY, low=3, spread=4, must=True,
          hi=HAIR_WHT, lo=dark(HAIR_GRY, 0.76))
    px(d, 22, hb + 3, HAIR_WHT)
    px(d, 25, hb + 2, HAIR_WHT)
    # ---- 左肩渔网（暗渔兜 + 亮渔线 + 浮子）
    net_pts = [(16, y0 + 5), (13, y0 + 6), (10, y0 + 8), (8, y0 + 11),
               (7, y0 + 13), (9, y0 + 14), (9, y0 + 16), (12, y0 + 15),
               (12, y0 + 17), (15, y0 + 15), (16, y0 + 17), (18, y0 + 14),
               (19, y0 + 11), (17, y0 + 7)]
    lattice(d, im, net_pts, NETC, edge=NETD, step=3, fill=NETB)
    for fx, fy in ((7, y0 + 13), (9, y0 + 15), (12, y0 + 16), (15, y0 + 16)):
        rct(d, fx, fy, fx + 1, fy + 1, CORK)
        px(d, fx, fy, light(CORK, 1.35))
        px(d, fx + 1, fy + 1, dark(CORK, 0.65))
    ln(d, 10, y0 + 8, 16, y0 + 5, NETD, 1)
    # ---- 左臂（抓着渔网顶角）
    arm(d, (18, y0 + 2), (16, y0 + 5), (15, y0 + 8), GREY_D, SKIN_OLIVE, 2)
    hand(d, 15, y0 + 8, SKIN_OLIVE)
    px(d, 15, y0 + 8, light(SKIN_OLIVE, 1.12))
    # ---- 右臂（举双钥匙）
    rx = 30 + P["arm"]
    arm(d, (31, y0 + 2), (33, 23 + P["bob"]), (rx + 1, 26 + P["bob"]), GREY_D, SKIN_OLIVE, 2)
    hand(d, rx, 25 + P["bob"], SKIN_OLIVE)
    key_one(d, rx + 2, 22 + P["bob"], rx + 9, 29 + P["bob"])
    key_one(d, rx + 2, 28 + P["bob"], rx + 9, 21 + P["bob"])
    px(d, rx + 1, 25 + P["bob"], KEYG)
    px(d, rx + 1, 26 + P["bob"], KEYD)
    # ---- 左臂
    arm(d, (18, y0 + 2), (17, 25 + P["bob"]), (15, 30 + P["bob"]), GREY_D, SKIN_OLIVE, 2)
    hand(d, 15, 30 + P["bob"], SKIN_OLIVE)


# ---------------------------------------------------------------- 保罗
def ch_paul(im, d, P, fi):
    so = P["step"]
    ht, hb = P["head_t"], P["head_b"]
    y0, y1 = P["torso_t"], P["torso_b"]
    # ---- 长袍
    # 酒红长袍：与深褐络腮胡分层
    poly(d, [(20, 30), (28, 30), (30, 42), (18, 42)], ROBE_P)
    poly(d, [(20, 30), (22, 30), (20, 42), (18, 42)], ROBE_PD)
    poly(d, [(26, 30), (28, 30), (30, 42), (28, 42)], light(ROBE_P, 1.42))
    for k in range(3):
        xx = 21 + k * 2
        ln(d, xx, 32, xx - 1, 41, dark(ROBE_P, 0.8), 1)
    ln(d, 27, 32, 28, 41, light(ROBE_P, 1.3), 1)
    rct(d, 18, 42, 30, 42, dark(ROBE_P, 0.58))
    # 下摆麻布内衬
    rct(d, 19, 42, 29, 42, LINEN_D)
    rct(d, 19, 43, 29, 43, LINEN)
    rct(d, 21 + (1 if so > 0 else 0), 44, 27 + (1 if so > 0 else 0), 44, LEATHER)
    # ---- 上身（浅麻布内衬 = 第 4 阶）
    torso_block(d, P, 19, 29, ROBE_P)
    poly(d, [(19, y0), (23, y0), (24, y1), (20, y1)], TAN)
    ln(d, 23, y0 + 1, 24, y1 - 1, dark(TAN, 0.60), 1)
    ln(d, 21, y0 + 2, 21, y1 - 2, light(TAN, 1.22), 1)
    px(d, 22, y0 + 3, dark(TAN, 0.86))
    # 金扣
    rct(d, 26, y0 + 1, 27, y0 + 2, GOLD)
    px(d, 26, y0 + 1, GOLD_L)
    px(d, 27, y0 + 2, GOLD_D)
    ln(d, 27, y0 + 3, 27, P["waist"] - 1, dark(BROWN_D, 0.76), 1)
    # 腰带
    rct(d, 19, P["waist"], 29, P["waist"] + 1, LEATHER)
    rct(d, 19, P["waist"], 29, P["waist"], LEATHER_L)
    rct(d, 23, P["waist"], 24, P["waist"] + 1, GOLD_D)
    # ---- 头（秃顶圆穹 + 浓密络腮胡）
    head_base(d, P, SKIN_OLIVE)
    # 秃顶：整块受光，发际退到耳后
    rct(d, 20, ht, 27, ht + 2, light(SKIN_OLIVE, 1.12))
    rct(d, 21, ht, 25, ht + 1, light(SKIN_OLIVE, 1.24))
    px(d, 20, ht, light(SKIN_OLIVE, 1.06))
    px(d, 27, ht + 2, light(SKIN_OLIVE, 1.18))
    px(d, 19, ht, dark(SKIN_OLIVE, 0.92))
    # 后脑/两鬓一圈短毛（低于耳线）
    rct(d, 18, ht + 3, 19, hb, HAIR_BRN)
    rct(d, 18, ht + 3, 18, hb + 1, dark(HAIR_BRN, 0.78))
    px(d, 17, hb, HAIR_BRN)
    px(d, 19, ht + 3, HAIR_GRY)
    rct(d, 27, ht + 3, 28, ht + 4, HAIR_BRN)
    # 抬头纹
    rct(d, 21, ht + 1, 23, ht + 1, dark(SKIN_OLIVE, 0.86))
    px(d, 24, ht + 2, dark(SKIN_OLIVE, 0.9))
    face(d, P, SKIN_OLIVE, dark(HAIR_BRN, 0.9))
    # 浓密络腮胡（盖口，垂到胸前）
    beard(d, P, HAIR_BRN, low=5, spread=5, must=True, side=2,
          hi=light(HAIR_BRN, 1.42))
    for xx in range(20, 30, 2):
        px(d, xx, hb + 6, light(HAIR_BRN, 1.28) if xx % 4 else dark(HAIR_BRN, 0.88))
    # ---- 卷轴（先画，手再压上去 = 真的握住）
    scroll_h(d, 4, 26 + P["bob"], 11, 6)
    # ---- 左臂
    lx, ly = 14, 29 + P["bob"]
    arm(d, (19, y0 + 2), (18, 25 + P["bob"]), (lx, ly), ROBE_P, SKIN_OLIVE, 2)
    hand(d, lx, ly, SKIN_OLIVE)
    px(d, lx + 1, ly, light(SKIN_OLIVE, 1.12))
    px(d, lx + 1, ly + 1, dark(SKIN_OLIVE, 0.82))
    # ---- 右臂（举羽毛笔）+ 腕铐 + 垂链
    rx = 30 + P["arm"]
    arm(d, (29, y0 + 2), (32, 22 + P["bob"]), (rx + 1, 24 + P["bob"]), ROBE_P, SKIN_OLIVE, 2)
    hand(d, rx, 23 + P["bob"], SKIN_OLIVE)
    quill(d, rx + 1, 23 + P["bob"], (39, 12 + P["bob"]))
    # 腕铐（铁环 + 铆钉）
    rct(d, rx - 1, 25 + P["bob"], rx + 2, 26 + P["bob"], IRON_D)
    rct(d, rx - 1, 25 + P["bob"], rx + 2, 25 + P["bob"], IRON)
    px(d, rx - 1, 26 + P["bob"], dark(IRON_D, 0.8))
    px(d, rx + 2, 26 + P["bob"], light(IRON, 1.1))
    px(d, rx, 25 + P["bob"], STEEL)
    # 垂链（从腕铐挂下，链环可辨）
    chain(d, rx + 1, 28 + P["bob"], n=5, dy=3)


CHARS = ["nehemiah", "esther", "daniel", "john_baptist", "peter", "paul"]
FNS = {
    "nehemiah": ch_nehemiah, "esther": ch_esther, "daniel": ch_daniel,
    "john_baptist": ch_john_baptist, "peter": ch_peter, "paul": ch_paul,
}


# ---------------------------------------------------------------- 渲染
def add_shadow(im):
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([13, 44, 35, 46], fill=(10, 14, 22, 96))
    return Image.alpha_composite(sh, im)


def render_one(fn):
    frames = []
    for i, p in enumerate(POSES):
        im = new_cell()
        d = ImageDraw.Draw(im)
        fn(im, d, anchor(p), i)
        frames.append(add_shadow(outline(im, diag=False)))
    return frames


def preview(paths, dst, scale=4, bg=(26, 32, 44, 255)):
    rows = [Image.open(p).convert("RGBA") for p in paths]
    sheet = Image.new("RGBA", (CELL * 8 * scale, CELL * len(rows) * scale), bg)
    d = ImageDraw.Draw(sheet)
    for r, im in enumerate(rows):
        big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        sheet.alpha_composite(big, (0, r * CELL * scale))
        for c in range(1, 8):
            x = c * CELL * scale
            d.line([x, r * CELL * scale, x, (r + 1) * CELL * scale], fill=(40, 48, 64, 255))
    sheet.save(dst)
    return dst


def main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    for cid in CHARS:
        frames = render_one(FNS[cid])
        p = os.path.join(OUT, "wit_%s.png" % cid)
        save_strip(p, frames)
        validate(p, CELL, 8)
        made.append(p)
        print("ok", os.path.basename(p))
    preview(made[0:3], os.path.join(OUT, "prev_a.png"), 4)
    preview(made[3:6], os.path.join(OUT, "prev_b.png"), 4)
    preview(made[0:6], os.path.join(OUT, "prev_1x.png"), 1)
    print("PREVIEW ok")


if __name__ == "__main__":
    main()
