"""V4 见证人行走图 · B 组（7 位）。

只产出 tools/out/wit_<id>.png（48x384，8 帧横排）与 tools/out/prev_<id>.png（4x 预览）。
不碰 tools/artbase.py / assets/ / src/ / data/。

设计要点（V4 契约第 2、3 节）
* 自建骨架，不走 artbase._body：剪影、道具、配色逐角色定制。
* 每块布料 3 阶明暗（base / dark0.74 / light1.18），衣褶用 1px 深色斜线。
* 道具一律举到身体轮廓外 2-6px，外轮廓描边后仍可辨。
* 眼睛 1px；行走帧双腿 2px 错位 + 手臂反向摆。
* 描边 1px：artbase.outline(diag=False)（默认 diag=True 会膨胀到 3px）。
"""
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_TOOLS = os.path.dirname(_HERE)
if _TOOLS not in sys.path:
    sys.path.insert(0, _TOOLS)

from artbase import *                     # noqa: F401,F403
from PIL import Image, ImageDraw

OUT = os.path.join(_TOOLS, "out")
G = 44          # 脚底
CX = 23         # 身体中线
BRICK = hx("#B0663E")     # 陶罐

# bob, 左腿 dx, 右腿 dx, 左手 dy, 右手 dy
POSES = [
    (0, 0, 0, 0, 0),
    (1, 0, 0, 0, 0),
    (1, 0, 0, -1, 1),
    (0, 0, 0, 0, 0),
    (0, -2, 0, -2, 2),
    (1, -1, 1, -1, 1),
    (0, 0, 2, 2, -2),
    (1, 1, 1, 1, -1),
]


def S_of(i):
    bob, lL, lR, aL, aR = POSES[i]
    return dict(i=i, idle=i < 4, bob=bob, lL=lL, lR=lR, aL=aL, aR=aR,
                cx=CX, g=G, sh=17 + bob, ht=5 + bob, hb=15 + bob,
                waist=27 + bob, tb=31 + bob, hip=29 + bob)


# ------------------------------------------------------------------ 通用零件
def cap(d, x0, y0, x1, y1, c):
    """上排收窄 1px 的圆顶矩形（头盔/头巾/斗篷顶）。"""
    rct(d, x0, y0 + 1, x1, y1, c)
    rct(d, x0 + 1, y0, x1 - 1, y0, c)


def vsh(d, x0, y0, x1, y1, base, lt=1.18, dk=0.74):
    """竖三阶：左暗 / 中基 / 右亮（圆柱感）。"""
    rct(d, x0, y0, x1, y1, base)
    if x1 - x0 >= 4:
        rct(d, x0, y0, x0, y1, dark(base, dk))
        rct(d, x0 + 1, y0, x0 + 1, y1, dark(base, 0.88))
        rct(d, x1 - 1, y0, x1 - 1, y1, light(base, lt))
        rct(d, x1, y0, x1, y1, dark(base, 0.84))
    elif x1 - x0 == 3:
        rct(d, x0, y0, x0, y1, dark(base, dk))
        rct(d, x1 - 1, y0, x1 - 1, y1, light(base, lt))
        rct(d, x1, y0, x1, y1, dark(base, 0.84))
    elif x1 - x0 == 2:
        rct(d, x0, y0, x0, y1, dark(base, dk))
        rct(d, x1, y0, x1, y1, light(base, lt))
    else:
        rct(d, x0, y0, x0, y1, dark(base, dk))


def folds(d, x0, y0, x1, y1, base, xs, k=0.74):
    """1px 深色衣褶斜线。"""
    for x in xs:
        ln(d, x, y0, x + 1, y1 - 1, dark(base, k))


def torso(d, S, col, dk=0.74, lt=1.18, top=0, bot=0):
    """收腰躯干：肩 13 宽 → 腰 9 宽，左右各 1px 明暗。"""
    sh, w, cx = S["sh"] - top, S["waist"] + bot, S["cx"]
    n = max(1, w - sh)
    for i in range(n + 1):
        hw = 6 if i < 3 else (5 if i < n * 0.72 else 4)
        rct(d, cx - hw, sh + i, cx + hw, sh + i, col)
        rct(d, cx - hw, sh + i, cx - hw, sh + i, dark(col, dk))
        rct(d, cx + hw, sh + i, cx + hw, sh + i, light(col, lt))
        if i == 0:
            rct(d, cx - hw + 1, sh + i, cx + hw - 1, sh + i, light(col, 1.1))
    return w


def legs(d, S, cloth, boot, thick=4, boot_h=4, lift_back=True):
    """双腿：走帧水平错位 2px，后腿脚掌抬 1px。"""
    hip, g = S["hip"], S["g"]
    for x0, off in ((CX - 5, S["lL"]), (CX + 1, S["lR"])):
        x0 += off
        x1 = x0 + thick - 1
        lift = 1 if (off < 0 and lift_back) else 0
        bot = g - boot_h - lift
        rct(d, x0, hip - 1, x1, bot, cloth)
        rct(d, x0, hip - 1, x0, bot, dark(cloth, 0.76))
        rct(d, x1, hip - 1, x1, bot, light(cloth, 1.12))
        rct(d, x0 + 1, hip + 3, x1 - 1, hip + 3, dark(cloth, 0.86))
        # 靴
        bx0, bx1 = x0 - 1, x1
        rct(d, bx0, bot + 1, bx1, g - lift, boot)
        rct(d, bx0, bot + 1, bx1, bot + 1, light(boot, 1.22))
        rct(d, bx0, g - lift, bx1, g - lift, dark(boot, 0.58))
        rct(d, bx0, bot + 1, bx0, g - lift, dark(boot, 0.8))
        px(d, bx1, bot + 2, light(boot, 1.15))


def feet(d, S, col):
    """裙下露脚：脚踝 + 鞋底三阶，走帧 2px 错位。"""
    g = S["g"]
    for x0, off in ((CX - 5, S["lL"]), (CX + 1, S["lR"])):
        x0 += off
        lift = 1 if off < 0 else 0
        rct(d, x0 + 1, g - 4 - lift, x0 + 2, g - 3 - lift, dark(col, 0.86))
        rct(d, x0, g - 2 - lift, x0 + 3, g - lift, col)
        rct(d, x0, g - 2 - lift, x0 + 3, g - 2 - lift, light(col, 1.2))
        rct(d, x0 + 1, g - 1 - lift, x0 + 3, g - 1 - lift, light(col, 1.06))
        rct(d, x0, g - lift, x0 + 3, g - lift, dark(col, 0.55))


def arm(d, S, side, col, skin=SKIN, bare=False, cuff=None):
    """side=-1 左（身后）/+1 右（身前）；返回手部左上角。"""
    sh = S["sh"]
    a = S["aL"] if side < 0 else S["aR"]
    x0 = CX + (-8 if side < 0 else 6)
    if a < 0:
        x0 += 1 if side > 0 else -1
    y0 = sh + 1
    y1 = y0 + 6
    c = skin if bare else col
    vsh(d, x0, y0, x0 + 2, y1, c)
    if not bare and cuff is not None:
        rct(d, x0, y0 + 5, x0 + 2, y1, cuff)
        rct(d, x0, y0 + 5, x0 + 2, y0 + 5, light(cuff, 1.15))
    hy = y1 + 1 + a
    rct(d, x0, hy, x0 + 1, hy + 1, skin)
    px(d, x0 + 1, hy, light(skin, 1.12))
    px(d, x0, hy + 1, dark(skin, 0.82))
    return (x0, hy)


def head(d, S, skin, hair, hair_len=1, turn=0, jaw_w=3):
    """朝右 3/4 脸：颅顶收窄、眼 1px、右侧鼻影。"""
    cx, ht, hb = S["cx"], S["ht"], S["hb"]
    hair_lo = dark(hair, 0.66)
    hair_hi = light(hair, 1.24)
    # 颅顶（收窄）
    rct(d, cx - 3, ht - 1, cx + 2, ht - 1, hair)
    rct(d, cx - 5, ht, cx + 4, ht + 1, hair)
    rct(d, cx - 4, ht - 1, cx + 1, ht - 1, hair_hi)
    rct(d, cx - 5, ht + 1, cx - 5, hb + hair_len, hair_lo)
    # 脸
    rct(d, cx - 4, ht + 2, cx + 4, hb, skin)
    rct(d, cx - 4, ht + 2, cx - 4, hb, dark(skin, 0.82))
    rct(d, cx + 4, ht + 2, cx + 4, hb - 1, light(skin, 1.1))
    rct(d, cx - 3, ht + 2, cx + 3, ht + 2, dark(skin, 0.88))
    rct(d, cx - jaw_w, hb, cx + jaw_w - 1, hb, dark(skin, 0.88))
    # 鬓 / 后脑发
    rct(d, cx - 5, ht + 1, cx - 4, hb + hair_len, hair)
    px(d, cx - 5, ht + 1, hair_hi)
    rct(d, cx + 4, ht + 1, cx + 4, ht + 3, hair)
    # 眼（1px）
    px(d, cx - 2 + turn, ht + 5, OUTLINE)
    px(d, cx + 2 + turn, ht + 5, OUTLINE)
    rct(d, cx - 3 + turn, ht + 4, cx - 2 + turn, ht + 4, dark(skin, 0.72))
    rct(d, cx + 1 + turn, ht + 4, cx + 3 + turn, ht + 4, dark(skin, 0.72))
    # 鼻 / 嘴
    px(d, cx + 3, ht + 6, dark(skin, 0.8))
    px(d, cx + 4, ht + 6, dark(skin, 0.68))
    px(d, cx + 4, ht + 7, dark(skin, 0.85))
    rct(d, cx + 1 + turn, ht + 8, cx + 3 + turn, ht + 8, dark(skin, 0.66))
    px(d, cx - 2, ht + 7, light(skin, 1.05))


def beard(d, S, col, length=3, moustache=True):
    cx, hb = S["cx"], S["hb"]
    rct(d, cx - 3, hb - 1, cx + 3, hb + length, col)
    rct(d, cx - 3, hb - 1, cx - 3, hb + length, dark(col, 0.78))
    rct(d, cx + 3, hb - 1, cx + 3, hb + length, light(col, 1.12))
    rct(d, cx - 2, hb + length + 1, cx + 2, hb + length + 1, dark(col, 0.8))
    for k in range(hb + 1, hb + length):
        ln(d, cx - 2, k, cx + 2, k, dark(col, 0.7))
    if moustache:
        rct(d, cx - 2, hb - 2, cx + 4, hb - 2, col)


def collar(d, S, col):
    """脖子 + 衣领。"""
    cx, hb, sh = S["cx"], S["hb"], S["sh"]
    rct(d, cx - 2, hb, cx + 2, sh, SKIN)
    rct(d, cx - 2, hb, cx - 2, sh, dark(SKIN, 0.8))
    rct(d, cx - 5, sh - 1, cx + 5, sh, col)
    rct(d, cx - 5, sh - 1, cx + 5, sh - 1, light(col, 1.15))


# ------------------------------------------------------------------ 道具
def shofar(d, x, y, big=1):
    """羊角号：手 → 下弯 → 上翻喇叭口。"""
    pts = [(x, y), (x + 4, y + 2), (x + 7, y - 1), (x + 7, y - 5)]
    for i in range(len(pts) - 1):
        ln(d, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], TAN, 3)
    for i in range(len(pts) - 1):
        ln(d, pts[i][0], pts[i][1] + 1, pts[i + 1][0], pts[i + 1][1] + 1, dark(TAN, 0.62), 1)
    for i in range(len(pts) - 1):
        ln(d, pts[i][0], pts[i][1] - 1, pts[i + 1][0], pts[i + 1][1] - 1, light(TAN, 1.22), 1)
    # 喇叭口
    poly(d, [(x + 6, y - 5), (x + 10, y - 9), (x + 11, y - 6), (x + 7, y - 3)], TAN)
    poly(d, [(x + 7, y - 6), (x + 9, y - 8), (x + 10, y - 7), (x + 8, y - 5)], light(TAN, 1.2))
    px(d, x + 10, y - 9, GOLD_L)
    px(d, x + 11, y - 8, GOLD)
    px(d, x + 9, y - 4, dark(TAN, 0.6))
    px(d, x + 1, y - 1, GOLD_L)


def torch(d, x, y):
    """火把：缠布柄 + 三层火焰。"""
    rct(d, x - 1, y - 8, x + 1, y + 6, LEATHER)
    rct(d, x - 1, y - 8, x - 1, y + 6, dark(LEATHER, 0.66))
    rct(d, x + 1, y - 8, x + 1, y + 6, LEATHER_L)
    for k in (-6, -3, 0, 3):
        rct(d, x - 1, y + k, x + 1, y + k, dark(LEATHER, 0.5))
    rct(d, x - 2, y - 9, x + 2, y - 8, dark(LEATHER, 0.55))
    # 火焰
    ell(d, x - 2, y - 15, x + 3, y - 8, FLAME_R)
    ell(d, x - 1, y - 15, x + 2, y - 9, FLAME_O)
    ell(d, x, y - 14, x + 1, y - 10, FLAME)
    px(d, x, y - 15, HOLY)
    px(d, x - 2, y - 12, FLAME_O)
    px(d, x + 3, y - 11, FLAME_O)


def palm_fire(d, x, y):
    """掌心的火。"""
    ell(d, x - 2, y - 8, x + 3, y - 1, FLAME_R)
    ell(d, x - 2, y - 7, x + 2, y - 1, FLAME_O)
    ell(d, x - 1, y - 6, x + 1, y - 1, FLAME)
    px(d, x, y - 7, HOLY)
    px(d, x, y - 6, HOLY)
    px(d, x - 3, y - 4, FLAME_O)
    px(d, x + 3, y - 3, FLAME_O)
    px(d, x + 2, y - 6, FLAME)
    px(d, x - 1, y - 8, FLAME_R)


def jawbone(d, x, y):
    """驴腮骨：骨白，带牙。"""
    iv = mix(LINEN, SAND, 0.3)
    hi, lo = light(iv, 1.12), dark(iv, 0.74)
    arc = [(0, 3), (1, 4), (2, 5), (3, 5), (4, 5), (5, 4), (6, 3), (7, 2)]
    for (dx, dy) in arc:
        px(d, x + dx, y + dy, iv)
        px(d, x + dx, y + dy - 1, hi)
        px(d, x + dx, y + dy + 1, lo)
    # 关节端（右侧上翘）
    rct(d, x + 7, y - 2, x + 8, y + 1, iv)
    rct(d, x, y + 2, x + 2, y + 3, iv)
    px(d, x + 8, y - 2, hi)
    px(d, x + 7, y + 1, lo)
    # 牙列
    for k in (2, 4, 6):
        px(d, x + k, y + 6, hi)
    px(d, x + 3, y + 6, iv)
    px(d, x + 5, y + 6, iv)


def wheat(d, x, y):
    """麦穗束：三支扇形麦穗 + 麻绳捆扎。"""
    for dx, dy in ((-3, -6), (0, -10), (3, -6)):
        ln(d, x, y, x + dx, y + dy + 2, dark(BRONZE, 0.82))
        ex, ey = x + dx, y + dy
        rct(d, ex - 1, ey, ex + 1, ey + 3, GOLD)
        rct(d, ex - 1, ey, ex + 1, ey, GOLD_L)
        px(d, ex, ey + 1, light(GOLD, 1.2))
        px(d, ex - 1, ey + 2, dark(GOLD, 0.7))
        px(d, ex + 1, ey + 3, dark(GOLD, 0.66))
        px(d, ex, ey + 3, dark(GOLD, 0.8))
        ln(d, ex, ey - 1, ex, ey - 4, GOLD_D)
        ln(d, ex - 1, ey - 2, ex - 2, ey - 4, GOLD_D)
    rct(d, x - 2, y, x + 2, y + 1, BROWN)
    px(d, x, y, light(BROWN, 1.4))
    px(d, x - 1, y + 1, dark(BROWN, 0.66))
    px(d, x + 1, y + 1, dark(BROWN, 0.7))


def sickle(d, hx, hy, h=8):
    """镰刀：竖木柄 + 顶端向左勾的弯刃。"""
    ln(d, hx, hy, hx, hy + h, LEATHER)
    ln(d, hx + 1, hy + 1, hx + 1, hy + h - 1, dark(LEATHER, 0.72))
    px(d, hx, hy + h + 1, BRONZE)
    px(d, hx + 1, hy + h + 1, dark(BRONZE, 0.7))
    arc = [(0, 0), (-2, -2), (-4, -3), (-5, -2), (-6, 0), (-6, 2)]
    for k in range(len(arc) - 1):
        ln(d, hx + arc[k][0], hy + arc[k][1], hx + arc[k + 1][0], hy + arc[k + 1][1], IRON, 2)
    ln(d, hx - 1, hy - 1, hx - 4, hy - 3, STEEL)
    px(d, hx - 6, hy + 2, STEEL)
    px(d, hx - 6, hy + 1, dark(IRON, 0.6))
    px(d, hx - 3, hy + 1, dark(IRON, 0.66))


def basket(d, x, y, w=8, h=7):
    """拾穗篮：编织网格 + 提手。"""
    rct(d, x, y, x + w, y + h, TAN)
    rct(d, x, y, x + w, y, light(TAN, 1.15))
    rct(d, x, y + h, x + w, y + h, dark(TAN, 0.6))
    rct(d, x, y, x, y + h, dark(TAN, 0.72))
    rct(d, x + w, y, x + w, y + h, dark(TAN, 0.5))
    for j, yy in enumerate(range(y + 1, y + h, 2)):
        for xx in range(x + (1 if j % 2 else 0), x + w, 2):
            px(d, xx, yy, dark(TAN, 0.62))
    # 提手
    ln(d, x + 1, y - 1, x + 2, y - 4, BROWN)
    ln(d, x + 2, y - 4, x + w - 2, y - 4, BROWN)
    ln(d, x + w - 2, y - 4, x + w - 1, y - 1, BROWN)
    # 篮沿麦穗
    px(d, x + 1, y - 1, GOLD)
    px(d, x + 3, y - 2, GOLD_L)
    px(d, x + 5, y - 1, GOLD)


def scroll(d, x, y):
    """书卷：展开的羊皮纸 + 两端金轴。"""
    rct(d, x + 1, y, x + 8, y + 5, LINEN)
    rct(d, x + 1, y, x + 8, y, light(LINEN, 1.12))
    rct(d, x + 1, y + 5, x + 8, y + 5, dark(LINEN, 0.7))
    ln(d, x + 2, y + 1, x + 6, y + 1, dark(LINEN, 0.58))
    ln(d, x + 2, y + 3, x + 6, y + 3, dark(LINEN, 0.58))
    px(d, x + 7, y + 2, dark(LINEN, 0.62))
    rct(d, x, y - 1, x + 1, y + 6, GOLD)
    rct(d, x + 8, y - 1, x + 9, y + 6, GOLD)
    px(d, x, y - 1, GOLD_L)
    px(d, x + 9, y - 1, GOLD_L)
    px(d, x, y + 6, GOLD_D)
    px(d, x + 9, y + 6, GOLD_D)


def palm_frond(d, x, y0, y1):
    """棕榈枝：茎 + 双侧羽叶。"""
    ln(d, x, y0, x, y1, dark(LEATHER, 0.78))
    ln(d, x + 1, y0 + 1, x + 1, y1 - 1, LEATHER)
    for k in range(y0 + 2, y1, 2):
        ln(d, x, k, x + 4, k - 2, OLIVE)
        ln(d, x + 1, k + 1, x + 3, k - 1, dark(OLIVE, 0.78))
        ln(d, x, k, x - 3, k - 2, GREEN)
        px(d, x - 4, k - 2, dark(GREEN, 0.85))
        px(d, x + 4, k - 2, light(OLIVE, 1.2))
    px(d, x, y0, GREEN)
    px(d, x + 1, y0 - 1, light(GREEN, 1.3))


def clay_jar(d, x, y):
    """陶罐：鼓腹 + 双耳 + 高光。"""
    ell(d, x, y + 2, x + 7, y + 10, BRICK)
    rct(d, x + 1, y + 2, x + 6, y + 9, BRICK)
    rct(d, x + 2, y, x + 5, y + 2, BRICK)
    rct(d, x + 2, y, x + 5, y, dark(BRICK, 0.7))
    rct(d, x + 1, y - 1, x + 6, y, dark(BRICK, 0.82))
    rct(d, x + 2, y + 4, x + 2, y + 7, light(BRICK, 1.3))
    rct(d, x + 5, y + 4, x + 6, y + 8, dark(BRICK, 0.68))
    rct(d, x, y + 3, x, y + 5, dark(BRICK, 0.75))     # 左耳
    rct(d, x + 7, y + 3, x + 7, y + 5, dark(BRICK, 0.75))
    ln(d, x + 2, y + 6, x + 5, y + 6, dark(BRICK, 0.6))
    ln(d, x + 1, y + 8, x + 6, y + 8, dark(BRICK, 0.62))
    px(d, x + 3, y + 9, dark(BRICK, 0.55))


def wheel(d, cx, cy, r=3):
    """战车轮纹：圆轮圈 + 斜辐条 + 轮毂（小到 7x7 仍读作车轮）。"""
    ring = []
    for yy in range(-r, r + 1):
        xx = int((r * r - yy * yy) ** 0.5 + 0.5)
        ring.append((cx + xx, cy + yy))
        ring.append((cx - xx, cy + yy))
    ring = sorted(set(ring))
    for (x, y) in ring:
        px(d, x, y, GOLD)
    for (x, y) in ring:
        if y < cy or (y == cy and x < cx):
            px(d, x, y, GOLD_L)
        elif y > cy and abs(x - cx) <= 1:
            px(d, x, y, GOLD_D)
    for k in (1, 2):
        for (sx, sy) in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            tgt = (cx + sx * k, cy + sy * k)
            if tgt not in ring:
                px(d, tgt[0], tgt[1], GOLD)
    px(d, cx, cy, GOLD_L)
    px(d, cx - 1, cy - 1, GOLD_D)


def scales(d, x0, y0, x1, y1, base=IRON, hi=STEEL, lo=IRON_D):
    """鳞甲：错位鳞片行，上亮下暗。"""
    rct(d, x0, y0, x1, y1, base)
    for r, yy in enumerate(range(y0 + 1, y1 - 1, 2)):
        off = 0 if r % 2 == 0 else 2
        for xx in range(x0 + off, x1 - 2, 4):
            rct(d, xx, yy, min(xx + 2, x1 - 1), yy, hi)
            px(d, xx, yy + 1, lo)
            px(d, min(xx + 2, x1 - 1), yy + 1, lo)
            px(d, xx + 1, yy + 1, base)

def short_sword(d, hx, hy):
    """短剑：柄在手，刃上挑出轮廓。"""
    rct(d, hx, hy + 1, hx + 1, hy + 3, LEATHER)
    rct(d, hx, hy + 3, hx + 1, hy + 3, dark(LEATHER, 0.6))
    rct(d, hx - 2, hy - 1, hx + 3, hy - 1, GOLD)
    px(d, hx, hy - 1, GOLD_L)
    ln(d, hx + 1, hy - 2, hx - 2, hy - 8, STEEL, 2)
    ln(d, hx + 2, hy - 2, hx - 1, hy - 8, light(STEEL, 1.12), 1)
    ln(d, hx + 1, hy - 3, hx - 2, hy - 9, light(STEEL, 1.05), 1)
    px(d, hx - 3, hy - 9, HOLY)
    px(d, hx - 3, hy - 8, STEEL)


# =============================================================== joshua
def draw_joshua(d, S):
    cx, sh, ht, hb, tb, g, w = S["cx"], S["sh"], S["ht"], S["hb"], S["tb"], S["g"], S["waist"]
    sw = -1 if S["aL"] > 0 else (1 if S["aL"] < 0 else 0)
    hemy = g - 9
    # --- 蓝白披风（身后）：蓝面 + 白衬里下摆 + 竖褶
    cl, cr = cx - 14 + sw, cx + 13 + sw
    poly(d, [(cx - 8, sh - 2), (cx + 8, sh - 2), (cr, hemy), (cl, hemy)], BLUE_D)
    poly(d, [(cx - 7, sh - 1), (cx + 7, sh - 1), (cr - 1, hemy - 1), (cl + 2, hemy - 1)], BLUE)
    poly(d, [(cl + 2, hemy - 2), (cr - 2, hemy - 2), (cr, hemy), (cl, hemy)], LINEN_D)
    rct(d, cl, hemy, cr, hemy, dark(LINEN_D, 0.6))
    rct(d, cl + 2, hemy - 2, cr - 2, hemy - 2, LINEN)
    rct(d, cl + 1, hemy, cr - 1, hemy, LINEN)
    for x in (cl + 3, cl + 7, cr - 6, cr - 2):
        ln(d, x, sh + 3, x, hemy - 4, dark(BLUE, 0.74))
    ln(d, cl + 1, sh + 1, cl + 1, hemy - 2, light(BLUE, 1.22))
    ln(d, cr - 1, sh + 1, cr - 1, hemy - 2, dark(BLUE, 0.66))
    px(d, cx - 6, sh, light(BLUE, 1.3))
    # --- 腿
    legs(d, S, IRON_D, LEATHER)
    # --- 左臂 + 短剑
    hL = arm(d, S, -1, BLUE_D, cuff=IRON)
    short_sword(d, hL[0], hL[1])
    # --- 躯干：鳞甲胸铠
    torso(d, S, IRON, dk=0.7, lt=1.14)
    scales(d, cx - 4, sh + 2, cx + 4, w - 3)
    rct(d, cx - 6, sh, cx - 6, w, dark(IRON, 0.7))
    rct(d, cx + 5, sh, cx + 6, w, light(IRON, 1.12))
    # 肩甲
    for sx0 in (cx - 7, cx + 3):
        rct(d, sx0, sh - 1, sx0 + 3, sh + 2, STEEL)
        rct(d, sx0, sh + 2, sx0 + 3, sh + 2, IRON_D)
        rct(d, sx0, sh - 1, sx0 + 3, sh - 1, light(STEEL, 1.1))
        px(d, sx0 + 1, sh + 1, dark(STEEL, 0.8))
    # 腰带 + 甲裙
    rct(d, cx - 6, w, cx + 6, w + 2, LEATHER)
    rct(d, cx - 6, w, cx + 6, w, LEATHER_L)
    rct(d, cx - 6, w + 2, cx + 6, w + 2, dark(LEATHER, 0.6))
    rct(d, cx - 1, w, cx + 1, w + 2, GOLD)
    px(d, cx, w + 1, GOLD_L)
    rct(d, cx - 6, w + 3, cx + 6, w + 5, IRON)
    rct(d, cx - 6, w + 3, cx + 6, w + 3, light(IRON, 1.16))
    for k in (cx - 5, cx - 2, cx + 1, cx + 4):
        ln(d, k, w + 3, k, w + 5, dark(IRON, 0.62))
    rct(d, cx - 6, w + 5, cx + 6, w + 5, dark(IRON, 0.55))
    # --- 颈 + 头 + 无面甲头盔
    collar(d, S, IRON_D)
    head(d, S, SKIN, HAIR_BRN, hair_len=0)
    cap(d, cx - 6, ht - 3, cx + 6, ht + 2, IRON)
    rct(d, cx - 6, ht - 2, cx + 6, ht - 2, STEEL)
    rct(d, cx - 5, ht - 3, cx + 5, ht - 3, light(IRON, 1.18))
    rct(d, cx - 6, ht + 1, cx + 6, ht + 1, dark(IRON, 0.8))
    rct(d, cx - 6, ht + 2, cx + 6, ht + 2, IRON_D)
    rct(d, cx - 7, ht + 3, cx + 7, ht + 3, IRON_D)
    rct(d, cx - 7, ht + 4, cx - 6, ht + 9, IRON_D)
    rct(d, cx + 6, ht + 4, cx + 7, ht + 9, IRON_D)
    px(d, cx - 7, ht + 5, IRON)
    px(d, cx + 7, ht + 5, IRON)
    rct(d, cx - 1, ht - 5, cx + 1, ht - 4, IRON)
    px(d, cx - 1, ht - 5, STEEL)
    rct(d, cx - 5, ht - 1, cx + 5, ht - 1, GOLD_D)
    px(d, cx - 3, ht - 1, GOLD)
    px(d, cx + 2, ht - 1, GOLD)
    px(d, cx + 2, ht - 2, light(STEEL, 1.15))
    # --- 右臂 + 羊角号
    hR = arm(d, S, 1, BLUE_D, cuff=IRON)
    shofar(d, hR[0] + 1, hR[1] + 1)


# =============================================================== gideon
def draw_gideon(d, S):
    cx, sh, ht, hb, tb, g, w = S["cx"], S["sh"], S["ht"], S["hb"], S["tb"], S["g"], S["waist"]
    tun, tun_d = TAN, dark(TAN, 0.74)
    hem = w + 9
    # --- 麻袍下摆
    poly(d, [(cx - 6, w - 1), (cx + 6, w - 1), (cx + 8, hem), (cx - 8, hem)], tun_d)
    rct(d, cx - 6, w, cx + 6, hem - 1, tun)
    rct(d, cx + 5, w, cx + 6, hem - 1, light(tun, 1.16))
    rct(d, cx - 6, w, cx - 6, hem - 1, dark(tun, 0.8))
    for x in (cx - 4, cx - 1, cx + 2):
        ln(d, x, w + 2, x + 1, hem - 1, dark(tun, 0.72))
    rct(d, cx - 8, hem, cx + 8, hem, dark(tun, 0.58))
    for x in range(cx - 8, cx + 9, 2):
        px(d, x, hem + 1, dark(tun, 0.66))
    # --- 腿
    legs(d, S, BROWN, LEATHER)
    # --- 左臂（身后）
    hL = arm(d, S, -1, tun, bare=True, skin=SKIN_OLIVE)
    # 羊毛挂肩：蓬松的白羊毛盖住左肩
    fl = LINEN
    puffs = [(cx - 6, sh - 2, 3), (cx - 10, sh, 2), (cx - 7, sh, 3), (cx - 5, sh + 3, 2),
             (cx - 9, sh + 4, 2), (cx - 7, sh + 7, 3), (cx - 10, sh + 8, 1),
             (cx - 5, sh + 9, 2), (cx - 8, sh + 11, 2)]
    for (qx, qy, rr) in puffs:
        ell(d, qx - rr, qy - rr, qx + rr, qy + rr, fl)
    for i, (qx, qy, rr) in enumerate(puffs):
        px(d, qx, qy - rr, light(fl, 1.14))
        px(d, qx - rr, qy + rr - 1, dark(fl, 0.74))
        if i % 2:
            px(d, qx + rr, qy + 1, dark(fl, 0.8))
        else:
            px(d, qx + 1, qy + rr, dark(fl, 0.78))
    px(d, cx - 6, sh - 5, light(fl, 1.1))
    px(d, cx - 8, sh - 4, fl)
    px(d, cx - 4, sh - 4, dark(fl, 0.82))
    # --- 躯干
    torso(d, S, tun)
    ln(d, cx + 1, sh + 2, cx + 1, w - 2, dark(tun, 0.68))
    ln(d, cx - 2, sh + 3, cx - 2, w - 2, dark(tun, 0.78))
    rct(d, cx - 2, sh, cx + 2, sh + 1, light(tun, 1.1))
    # 腰带
    rct(d, cx - 6, w, cx + 6, w + 2, BROWN_D)
    rct(d, cx - 6, w, cx + 6, w, LEATHER)
    rct(d, cx - 6, w + 2, cx + 6, w + 2, dark(BROWN_D, 0.66))
    rct(d, cx, w, cx + 1, w + 2, BRONZE)
    px(d, cx, w + 1, GOLD_L)
    # --- 头
    collar(d, S, tun)
    head(d, S, SKIN_OLIVE, HAIR_BRN, hair_len=1)
    rct(d, cx - 5, ht - 2, cx + 4, ht, HAIR_BRN)
    rct(d, cx - 4, ht - 2, cx + 2, ht - 2, light(HAIR_BRN, 1.25))
    rct(d, cx - 5, ht - 2, cx - 5, hb + 1, HAIR_BRN)
    beard(d, S, HAIR_BRN, 2)
    px(d, cx - 1, hb + 1, light(HAIR_BRN, 1.4))
    px(d, cx + 1, hb + 2, light(HAIR_BRN, 1.3))
    # --- 右臂 + 火把
    hR = arm(d, S, 1, tun, bare=True, skin=SKIN_OLIVE)
    torch(d, hR[0] + 1, hR[1] - 3)
    # --- 腰间陶罐（左侧）
    clay_jar(d, cx - 13, w + 2)
    ln(d, cx - 11, w, cx - 10, w + 2, LEATHER)
    # --- 腰后皮水囊（右侧）
    ell(d, cx + 8, w + 1, cx + 12, w + 6, BROWN)
    rct(d, cx + 8, w + 2, cx + 12, w + 4, BROWN)
    rct(d, cx + 8, w + 2, cx + 9, w + 5, light(BROWN, 1.22))
    rct(d, cx + 11, w + 3, cx + 12, w + 6, dark(BROWN, 0.68))
    rct(d, cx + 9, w, cx + 11, w, LEATHER)
    px(d, cx + 10, w - 1, BRONZE)


# =============================================================== samson
def draw_samson(d, S):
    cx, sh, ht, hb, tb, g, w = S["cx"], S["sh"], S["ht"], S["hb"], S["tb"], S["g"], S["waist"]
    sk = SKIN_OLIVE
    sk_d, sk_l = dark(sk, 0.78), light(sk, 1.14)
    hair = HAIR_BRN
    hair_hi = light(hair, 1.55)
    hair_lo = dark(hair, 0.44)
    # --- 发幕：颈部向左侧散开（先铺背衬，辫子最后叠上去）
    for y in range(hb - 2, w + 8):
        k = min(1.0, (y - (hb - 2)) / 9.0)
        x0 = cx - 5 - int(round(14 * k))
        x1 = cx + 6 - int(round(3 * k))
        rct(d, x0, y, x1, y, dark(hair, 0.6))
    rct(d, cx - 5, hb - 2, cx + 6, hb - 2, hair)
    rct(d, cx - 6, hb - 1, cx + 6, hb - 1, hair)
    rct(d, cx - 8, hb, cx + 5, hb, hair)
    px(d, cx - 2, hb - 2, hair_hi)
    px(d, cx - 9, hb + 1, dark(hair, 0.78))
    # --- 腿
    legs(d, S, BROWN, LEATHER)
    # 短腰裙
    poly(d, [(cx - 6, w + 2), (cx + 6, w + 2), (cx + 7, w + 9), (cx - 7, w + 9)], dark(BROWN, 0.78))
    rct(d, cx - 5, w + 3, cx + 5, w + 8, BROWN)
    for x in (cx - 3, cx, cx + 3):
        ln(d, x, w + 4, x, w + 8, dark(BROWN, 0.68))
    rct(d, cx - 7, w + 9, cx + 7, w + 9, dark(BROWN, 0.5))
    # --- 左臂
    hL = arm(d, S, -1, sk, bare=True)
    # --- 躯干：赤膊
    torso(d, S, sk, dk=0.8, lt=1.12)
    # 胸肌
    rct(d, cx - 4, sh + 2, cx - 1, sh + 4, light(sk, 1.07))
    rct(d, cx + 1, sh + 2, cx + 4, sh + 4, light(sk, 1.07))
    rct(d, cx - 4, sh + 4, cx - 1, sh + 4, sk_d)
    rct(d, cx + 1, sh + 4, cx + 4, sh + 4, sk_d)
    px(d, cx, sh + 3, sk_d)
    px(d, cx, sh + 4, sk_d)
    # 腹肌
    for yy in (sh + 7, sh + 9):
        ln(d, cx - 2, yy, cx + 2, yy, sk_d)
    px(d, cx - 1, sh + 8, sk_d)
    rct(d, cx - 1, sh + 6, cx - 1, sh + 10, sk_d)
    # --- 七辫：7 条独立辫线（亮节/暗节交替），股间留暗发缝
    tops = [hb + 9, hb + 8, hb + 7, hb + 6, hb + 5, hb + 4, hb + 4]
    bots = [w + 2, w + 2, w + 1, w + 1, w, w - 1, w - 1]
    for i in range(7):
        bx = cx - 18 + i * 2
        for y in range(tops[i], bots[i]):
            m = (y + i) % 3
            if m == 0:
                px(d, bx, y, hair_hi)
            elif m == 1:
                px(d, bx, y, light(hair, 1.12))
            else:
                px(d, bx, y, dark(hair, 0.72))
        px(d, bx, bots[i], hair_lo)
        px(d, bx, bots[i] + 1, dark(hair, 0.46))
        px(d, bx + (1 if i % 2 else -1), bots[i], hair_lo)
    # --- 宽腰带
    rct(d, cx - 6, w - 1, cx + 6, w + 2, BROWN_D)
    rct(d, cx - 6, w - 1, cx + 6, w - 1, LEATHER)
    rct(d, cx - 6, w + 2, cx + 6, w + 2, dark(BROWN_D, 0.66))
    rct(d, cx - 6, w, cx + 6, w, dark(LEATHER, 0.7))
    for k in (cx - 4, cx, cx + 4):
        rct(d, k, w, k + 1, w + 1, GOLD)
    # --- 头
    collar(d, S, sk)
    head(d, S, sk, hair, hair_len=2)
    cap(d, cx - 6, ht - 3, cx + 5, ht + 1, hair)
    rct(d, cx - 5, ht - 3, cx + 3, ht - 3, hair_hi)
    rct(d, cx - 6, ht - 2, cx + 2, ht - 2, light(hair, 1.25))
    rct(d, cx - 6, ht - 3, cx - 6, hb + 2, hair)
    rct(d, cx + 5, ht - 1, cx + 5, hb + 2, dark(hair, 0.92))
    px(d, cx - 4, hb + 1, dark(hair, 0.7))
    rct(d, cx + 4, ht, cx + 5, hb + 2, dark(hair, 0.9))
    beard(d, S, hair, 1, moustache=False)
    # --- 右臂 + 驴腮骨
    hR = arm(d, S, 1, sk, bare=True)
    jawbone(d, hR[0], hR[1] - 1)


# =============================================================== deborah
def draw_deborah(d, S):
    cx, sh, ht, hb, tb, g, w = S["cx"], S["sh"], S["ht"], S["hb"], S["tb"], S["g"], S["waist"]
    dr, dr_d = ROYAL, dark(ROYAL, 0.72)
    hem = g - 3
    # --- 长裙
    poly(d, [(cx - 6, w - 1), (cx + 6, w - 1), (cx + 9, hem), (cx - 9, hem)], dr_d)
    rct(d, cx - 6, w, cx + 6, hem - 1, dr)
    rct(d, cx + 5, w, cx + 6, hem - 1, light(dr, 1.18))
    rct(d, cx - 6, w, cx - 6, hem - 1, dark(dr, 0.8))
    for x in (cx - 4, cx - 1, cx + 2):
        ln(d, x, w + 2, x + 1, hem - 1, dark(dr, 0.7))
    # 金色裙裾
    rct(d, cx - 9, hem - 1, cx + 9, hem - 1, GOLD)
    rct(d, cx - 9, hem, cx + 9, hem, dark(GOLD, 0.6))
    px(d, cx - 6, hem - 2, GOLD_D)
    px(d, cx + 3, hem - 2, GOLD_D)
    # --- 脚
    feet(d, S, SAND)
    # --- 左臂 + 书卷
    hL = arm(d, S, -1, dr, cuff=GOLD_D)
    scroll(d, hL[0] - 6, hL[1] - 2)
    # --- 躯干
    torso(d, S, dr)
    ln(d, cx + 1, sh + 3, cx + 1, w - 2, GOLD)
    ln(d, cx - 3, sh + 3, cx - 3, w - 2, dark(dr, 0.76))
    # 金胸带
    rct(d, cx - 5, sh + 5, cx + 5, sh + 5, GOLD)
    rct(d, cx - 5, sh + 5, cx + 5, sh + 5, GOLD)
    px(d, cx, sh + 5, GOLD_L)
    px(d, cx + 3, sh + 5, GOLD_D)
    # 腰带
    rct(d, cx - 6, w, cx + 6, w + 2, GOLD_D)
    rct(d, cx - 6, w, cx + 6, w, GOLD)
    rct(d, cx - 1, w, cx + 1, w + 2, GOLD_L)
    # --- 头 + 女先知头巾
    collar(d, S, dr)
    head(d, S, SKIN, HAIR_BRN, hair_len=0)
    cap(d, cx - 6, ht - 2, cx + 6, ht + 2, dr)
    rct(d, cx - 6, ht - 2, cx + 5, ht - 2, light(dr, 1.22))
    rct(d, cx - 6, ht + 1, cx + 6, ht + 1, dr_d)
    rct(d, cx - 7, ht + 2, cx + 7, ht + 3, dr_d)
    rct(d, cx - 7, ht + 3, cx - 5, ht + 13, dr)
    rct(d, cx - 7, ht + 3, cx - 7, ht + 13, dr_d)
    rct(d, cx - 7, ht + 6, cx - 5, ht + 6, GOLD)
    rct(d, cx - 7, ht + 13, cx - 5, ht + 13, GOLD)
    rct(d, cx + 5, ht + 3, cx + 6, ht + 10, dr_d)
    rct(d, cx + 6, ht + 10, cx + 6, ht + 10, GOLD)
    px(d, cx + 1, ht - 3, GOLD)
    px(d, cx + 3, ht - 2, GOLD_L)
    # --- 右臂 + 棕榈枝
    hR = arm(d, S, 1, dr, cuff=GOLD_D)
    palm_frond(d, hR[0] + 2, hR[1] - 14, hR[1] + 2)


# =============================================================== ruth
def draw_ruth(d, S):
    cx, sh, ht, hb, tb, g, w = S["cx"], S["sh"], S["ht"], S["hb"], S["tb"], S["g"], S["waist"]
    dr, dr_d = OLIVE, dark(OLIVE, 0.68)
    hem = g - 3
    # --- 长裙
    poly(d, [(cx - 6, w - 1), (cx + 6, w - 1), (cx + 8, hem), (cx - 8, hem)], dr_d)
    rct(d, cx - 6, w, cx + 6, hem - 1, dr)
    rct(d, cx + 5, w, cx + 6, hem - 1, light(dr, 1.18))
    rct(d, cx - 6, w, cx - 6, hem - 1, dark(dr, 0.8))
    for x in (cx - 4, cx - 1, cx + 2):
        ln(d, x, w + 2, x + 1, hem - 1, dark(dr, 0.72))
    # 亚麻色裙边
    rct(d, cx - 8, hem, cx + 8, hem, LINEN)
    rct(d, cx - 8, hem - 1, cx + 8, hem - 1, dark(LINEN, 0.72))
    px(d, cx - 6, hem, dark(LINEN, 0.62))
    px(d, cx, hem, dark(LINEN, 0.62))
    px(d, cx + 5, hem, dark(LINEN, 0.62))
    # --- 脚
    feet(d, S, BROWN)
    # --- 左臂 + 篮 + 镰刀
    hL = arm(d, S, -1, dr, bare=True)
    sickle(d, hL[0] + 1, hL[1] - 5)
    basket(d, cx - 19, w)
    ln(d, hL[0] - 1, hL[1] + 1, cx - 15, w + 1, LEATHER)
    # --- 躯干 + 麻布披肩
    torso(d, S, dr)
    ln(d, cx + 1, sh + 2, cx + 1, w - 2, dark(dr, 0.7))
    # 披肩（罩住双肩）
    rct(d, cx - 6, sh - 1, cx + 6, sh + 4, LINEN)
    rct(d, cx - 6, sh - 1, cx + 6, sh - 1, light(LINEN, 1.1))
    rct(d, cx - 6, sh + 4, cx + 6, sh + 4, dark(LINEN, 0.76))
    rct(d, cx - 6, sh - 1, cx - 6, sh + 4, dark(LINEN, 0.82))
    rct(d, cx + 6, sh - 1, cx + 6, sh + 4, dark(LINEN, 0.82))
    # 披肩前垂
    rct(d, cx - 5, sh + 4, cx - 3, sh + 11, LINEN)
    rct(d, cx - 5, sh + 4, cx - 5, sh + 11, dark(LINEN, 0.78))
    px(d, cx - 4, sh + 11, light(LINEN, 1.1))
    # 腰带
    rct(d, cx - 6, w, cx + 6, w + 2, BROWN)
    rct(d, cx - 6, w, cx + 6, w, LEATHER)
    rct(d, cx - 6, w + 2, cx + 6, w + 2, dark(BROWN, 0.66))
    rct(d, cx, w, cx + 1, w + 2, BRONZE)
    # --- 头
    collar(d, S, dr)
    head(d, S, SKIN_PALE, HAIR_BRN, hair_len=2)
    rct(d, cx - 5, ht - 2, cx + 3, ht, HAIR_BRN)
    rct(d, cx - 5, ht - 2, cx + 2, ht - 2, light(HAIR_BRN, 1.25))
    rct(d, cx - 5, ht - 2, cx - 5, hb + 2, HAIR_BRN)
    rct(d, cx + 4, ht + 2, cx + 5, hb + 2, dark(HAIR_BRN, 0.85))
    # 布巾包头
    rct(d, cx - 6, ht - 1, cx + 5, ht + 1, LINEN)
    rct(d, cx - 6, ht - 1, cx + 5, ht - 1, light(LINEN, 1.12))
    rct(d, cx - 6, ht + 1, cx + 5, ht + 1, dark(LINEN, 0.78))
    px(d, cx - 2, ht - 2, OLIVE)
    px(d, cx + 1, ht - 2, dark(OLIVE, 0.8))
    # --- 右臂 + 麦穗束
    hR = arm(d, S, 1, dr, bare=True)
    wheat(d, hR[0] + 1, hR[1] + 1)


# =============================================================== elijah
def draw_elijah(d, S):
    cx, sh, ht, hb, tb, g, w = S["cx"], S["sh"], S["ht"], S["hb"], S["tb"], S["g"], S["waist"]
    fu = mix(BROWN, TAN, 0.42)
    fu_d, fu_l = dark(fu, 0.6), light(fu, 1.42)
    hem = g - 6
    # --- 骆驼毛披风：轮廓带毛齿
    poly(d, [(cx - 7, sh - 1), (cx + 7, sh - 1), (cx + 9, hem), (cx - 9, hem)], dark(fu, 0.5))
    rct(d, cx - 6, sh, cx + 6, hem - 1, fu)
    rct(d, cx + 5, sh, cx + 6, hem - 1, light(fu, 1.18))
    rct(d, cx - 6, sh, cx - 6, hem - 1, dark(fu, 0.62))
    # 毛质：竖向鬃毛一束束（错落短划，暗底亮尖）
    for i, x in enumerate(range(cx - 5, cx + 6)):
        y = sh + 1 + (i * 3) % 4
        while y < hem - 2:
            e = min(y + 1 + (i % 2), hem - 2)
            ln(d, x, y, x, e, fu_l if i % 2 else light(fu, 1.2))
            px(d, x, e + 1, dark(fu, 0.62))
            y += 4
    for i, x in enumerate(range(cx - 5, cx + 6)):
        if i % 3 == 1:
            ln(d, x, sh + 3, x, hem - 3, dark(fu, 0.8))
    # 毛边下摆：参差毛齿
    for x in range(cx - 9, cx + 10):
        hh = 1 + (x * 5) % 2
        rct(d, x, hem - 1, x, hem + hh - 1, fu)
        px(d, x, hem + hh, dark(fu, 0.56))
    # --- 腿
    legs(d, S, BROWN_D, LEATHER)
    # --- 左臂
    hL = arm(d, S, -1, dark(fu, 0.72), skin=SKIN_DARK)
    # --- 躯干
    torso(d, S, fu, dk=0.66, lt=1.2)
    # 皮腰带
    rct(d, cx - 6, w, cx + 6, w + 2, LEATHER)
    rct(d, cx - 6, w, cx + 6, w, LEATHER_L)
    rct(d, cx - 6, w + 2, cx + 6, w + 2, dark(LEATHER, 0.55))
    rct(d, cx - 1, w, cx + 1, w + 2, BRONZE)
    px(d, cx, w + 1, GOLD_L)
    rct(d, cx + 4, w + 2, cx + 5, w + 6, LEATHER)
    px(d, cx + 5, w + 6, dark(LEATHER, 0.62))
    # --- 头
    collar(d, S, dark(fu, 0.72))
    head(d, S, SKIN_DARK, HAIR_WHT, hair_len=2)
    rct(d, cx - 4, ht - 2, cx + 3, ht - 2, HAIR_WHT)
    rct(d, cx - 5, ht - 1, cx + 4, ht + 1, HAIR_WHT)
    rct(d, cx - 4, ht - 2, cx + 1, ht - 2, light(HAIR_WHT, 1.12))
    rct(d, cx - 4, ht - 1, cx + 3, ht - 1, light(HAIR_WHT, 1.04))
    rct(d, cx - 5, ht + 1, cx + 4, ht + 1, mix(HAIR_WHT, GREY, 0.44))
    rct(d, cx - 5, ht - 1, cx - 5, hb + 2, HAIR_WHT)
    # 白须：三阶渐层 + 收尖（纯白实心块会读成口罩）
    bw = mix(HAIR_WHT, GREY, 0.34)
    rct(d, cx - 3, hb, cx + 3, hb + 1, bw)
    rct(d, cx - 3, hb + 2, cx + 3, hb + 2, HAIR_WHT)
    rct(d, cx - 3, hb + 3, cx + 3, hb + 3, bw)
    rct(d, cx - 2, hb + 4, cx + 2, hb + 4, bw)
    rct(d, cx - 1, hb + 5, cx + 1, hb + 5, dark(bw, 0.8))
    rct(d, cx - 3, hb, cx - 3, hb + 3, dark(bw, 0.82))
    rct(d, cx + 3, hb, cx + 3, hb + 3, light(bw, 1.1))
    rct(d, cx, hb, cx + 1, hb, bw)
    px(d, cx - 2, hb + 2, HAIR_WHT)
    px(d, cx + 1, hb + 2, HAIR_WHT)
    px(d, cx, hb + 3, dark(bw, 0.72))
    # 毛领
    for x in range(cx - 6, cx + 7, 2):
        px(d, x, sh - 1, fu_l)
        px(d, x + 1, sh - 1, dark(fu, 0.5))
    # --- 右臂 + 掌心火
    hR = arm(d, S, 1, dark(fu, 0.72), skin=SKIN_DARK)
    palm_fire(d, hR[0] + 1, hR[1])


# =============================================================== elisha
def draw_elisha(d, S):
    cx, sh, ht, hb, tb, g, w = S["cx"], S["sh"], S["ht"], S["hb"], S["tb"], S["g"], S["waist"]
    cl = GREY_D
    cl_d, cl_l = dark(cl, 0.68), light(cl, 1.32)
    hem = g - 3
    # --- 大斗篷：外扩 到 22 宽
    poly(d, [(cx - 8, sh - 1), (cx + 8, sh - 1), (cx + 12, hem), (cx - 12, hem)], cl_d)
    poly(d, [(cx - 7, sh), (cx + 7, sh), (cx + 11, hem), (cx - 11, hem)], cl)
    poly(d, [(cx + 2, sh + 3), (cx + 7, sh + 3), (cx + 11, hem - 2), (cx + 4, hem - 2)], cl_l)
    rct(d, cx + 10, sh + 5, cx + 10, hem - 1, light(cl, 1.44))
    for x in (cx - 10, cx - 7, cx - 4, cx + 3, cx + 6, cx + 9):
        ln(d, x, sh + 2, x, hem - 1, dark(cl, 0.7))
    ln(d, cx - 11, sh + 6, cx - 11, hem - 1, dark(cl, 0.58))
    ln(d, cx - 1, sh + 6, cx - 1, hem - 2, dark(cl, 0.78))
    # 金边下摆
    rct(d, cx - 12, hem, cx + 12, hem, GOLD)
    rct(d, cx - 12, hem - 1, cx + 12, hem - 1, dark(GOLD, 0.7))
    # --- 脚
    feet(d, S, GREY)
    # --- 左臂
    hL = arm(d, S, -1, cl)
    # --- 躯干
    torso(d, S, cl)
    # 翻领
    poly(d, [(cx - 6, sh - 1), (cx + 6, sh - 1), (cx + 5, sh + 5), (cx - 5, sh + 5)], cl_l)
    poly(d, [(cx - 6, sh - 1), (cx + 6, sh - 1), (cx, sh + 4)], cl)
    rct(d, cx - 6, sh + 5, cx + 6, sh + 5, cl_d)
    # 承接的外衣：肩背一圈骆驼毛领
    fc = mix(BROWN, TAN, 0.42)
    for x in range(cx - 7, cx + 8):
        hh = 1 + (x * 3) % 2
        rct(d, x, sh - 1, x, sh - 1 + hh, fc)
        px(d, x, sh - 1, light(fc, 1.24))
        px(d, x, sh + hh, dark(fc, 0.68))
    # 腰带
    rct(d, cx - 6, w, cx + 6, w + 2, LEATHER)
    rct(d, cx - 6, w, cx + 6, w, LEATHER_L)
    rct(d, cx - 6, w + 2, cx + 6, w + 2, dark(LEATHER, 0.58))
    rct(d, cx - 1, w, cx + 2, w + 2, GOLD)
    # --- 战车轮纹（披风下摆两枚，叠在斗篷正面）
    wheel(d, cx - 9, hem - 8, 3)
    wheel(d, cx + 8, hem - 8, 3)
    # --- 头
    collar(d, S, cl)
    head(d, S, SKIN_OLIVE, HAIR_BRN, hair_len=1)
    rct(d, cx - 5, ht - 2, cx + 3, ht, HAIR_BRN)
    rct(d, cx - 4, ht - 2, cx + 2, ht - 2, light(HAIR_BRN, 1.2))
    rct(d, cx - 5, ht - 2, cx - 5, hb + 1, HAIR_BRN)
    beard(d, S, HAIR_BRN, 2)
    # --- 右臂
    hR = arm(d, S, 1, cl)
    rct(d, hR[0] - 1, hR[1] + 2, hR[0] + 2, hR[1] + 2, GOLD_D)


# =============================================================== 组装
CHARS = [
    ("joshua", draw_joshua),
    ("gideon", draw_gideon),
    ("samson", draw_samson),
    ("deborah", draw_deborah),
    ("ruth", draw_ruth),
    ("elijah", draw_elijah),
    ("elisha", draw_elisha),
]


def build(fn, frames=8):
    """不出投影层：契约要求脚底正好 y=44，最低不透明像素不能低于 44。"""
    out = []
    for i in range(frames):
        S = S_of(i)
        im = new_cell()
        d = ImageDraw.Draw(im)
        fn(d, S)
        im = outline(im, OUTLINE, diag=False)
        out.append(im)
    return out


def preview(path, frames, scale=4, only=None):
    idx = only if only else range(len(frames))
    w, h = CELL * scale * len(idx), CELL * scale
    im = Image.new("RGBA", (w, h), (18, 22, 30, 255))
    dr = ImageDraw.Draw(im)
    for j, i in enumerate(idx):
        big = frames[i].resize((CELL * scale, CELL * scale), Image.NEAREST)
        im.alpha_composite(big, (j * CELL * scale, 0))
        dr.line([(j * CELL * scale, 0), (j * CELL * scale, h)], fill=(44, 52, 66, 255))
    im.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    for cid, fn in CHARS:
        frames = build(fn)
        strip = os.path.join(OUT, "wit_%s.png" % cid)
        save_strip(strip, frames)
        preview(os.path.join(OUT, "prev_%s.png" % cid), frames)
        preview(os.path.join(OUT, "zoom_%s.png" % cid), frames, 8, [0, 6])
        print(cid, validate(strip, CELL, 8))


if __name__ == "__main__":
    main()


