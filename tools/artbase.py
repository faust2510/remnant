"""像素角色生成基座（V4 美术线）。

约定
----
* 单格 48x48；脚底踩在 y=44（44 这一行是鞋底）。
* 一行 8 帧：0-3 站立呼吸，4-7 走路。
* 一律朝右绘制；运行期按 48px 单元格镜像得到朝左（不要整图翻转）。
* 全整数坐标、硬边，禁止抗锯齿与半透明描边。
* 描边统一 1px，颜色 OUTLINE。

用法
----
    from artbase import *
    cfg = dict(skin=SKIN, hair=HAIR_WHT, beard=True, head="crown", robe=PURPLE,
               robe2=GOLD, trim=GOLD_L, metal=GOLD, cape=ROYAL, build="normal")
    frames = render(cfg)
    save_strip("tools/out/wit_david.png", frames)

cfg 字段（缺省全部可用）
    skin, hair, beard(bool 或 "long"/"short"), robe, robe2, trim, belt, metal, boot,
    cape(str|None), head("none|crown|hood|helmet|turban|veil|wreath|mitre"),
    hair_len(0..3), build("slim|normal|broad"), skirt(bool), glow(str|None),
    shoulder(str|None), sash(str|None), detail(callable)  # detail(d, ctx)

detail(d, ctx) 在最后一步调用，可以继续往 d 上画道具：
    ctx = {"pose": pose, "kind": "idle"/"walk", "frame": i,
           "x": cx, "y": fy, "colors": cfg, "mk": mk}
    常用锚点见 ctx["mk"]：head_t/head_b/waist/foot_l/foot_r/hand_r/hand_l/shoulder_r
"""
import os
import math
from PIL import Image, ImageDraw, ImageFilter

CELL = 48
FEET = 44
FRAMES = 8

# ------------------------------------------------------------------ 调色板
def _h(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)

OUTLINE = _h("#0A0E14")
DEEP = _h("#141A26")

SKIN = _h("#D9AE86"); SKIN_L = _h("#F2D3B0"); SKIN_D = _h("#B98A63"); SKIN_S = _h("#8E6547")
SKIN_PALE = _h("#E6C6A6"); SKIN_OLIVE = _h("#C9A075"); SKIN_DARK = _h("#9C6F4E")

HAIR_BLK = _h("#1E1C24"); HAIR_BRN = _h("#4A3524"); HAIR_AUB = _h("#8A4A2A")
HAIR_WHT = _h("#E8E4D8"); HAIR_GRY = _h("#B4AE9E"); HAIR_GLD = _h("#D9B45A")

PURPLE = _h("#6B3E78"); PURPLE_D = _h("#4A2A54"); ROYAL = _h("#7E4C9A")
RED = _h("#9E3B34"); RED_D = _h("#6E2824"); CRIMSON = _h("#C0493A")
BLUE = _h("#2F4E7A"); BLUE_D = _h("#20344F"); SKY = _h("#5C82A8")
TEAL = _h("#2E6B63"); GREEN = _h("#3E6B4F"); OLIVE = _h("#6E7A3E")
BROWN = _h("#6B4E32"); BROWN_D = _h("#4A3524"); TAN = _h("#A8845C")
SAND = _h("#C7AE86"); LINEN = _h("#DCD6C4"); LINEN_D = _h("#B4AD98")
GREY = _h("#6B7280"); GREY_D = _h("#464C58")

GOLD = _h("#D9B45A"); GOLD_L = _h("#F2DFA6"); GOLD_D = _h("#9E7C34")
BRONZE = _h("#B08A4A"); IRON = _h("#8A94A2"); IRON_D = _h("#4E5766"); STEEL = _h("#C0C8D2")

LEATHER = _h("#5A3E28"); LEATHER_L = _h("#7A5738")
FLAME = _h("#F6D27A"); FLAME_O = _h("#F2A03C"); FLAME_R = _h("#D9602A")
HOLY = _h("#F6EFC8"); HOLY_B = _h("#A8C8F0")
BLOOD_D = _h("#7A2A22")

# ------------------------------------------------------------------ 基础绘制
def hx(s):
    return _h(s)

def mul(c, k, a=1.0):
    return (max(0, min(255, int(c[0] * k))), max(0, min(255, int(c[1] * k))),
            max(0, min(255, int(c[2] * k))), int(255 * a) if a < 1.0 else c[3])

def dark(c, k=0.72):
    return mul(c, k)

def light(c, k=1.28):
    return mul(c, k)

def mix(a, b, t):
    return (int(a[0] + (b[0] - a[0]) * t), int(a[1] + (b[1] - a[1]) * t),
            int(a[2] + (b[2] - a[2]) * t), 255)

def new_cell(w=CELL, h=CELL):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def px(d, x, y, c):
    d.point((int(x), int(y)), c)

def rct(d, x0, y0, x1, y1, c):
    """闭区间矩形（含 x1/y1）。"""
    if x1 < x0:
        x0, x1 = x1, x0
    if y1 < y0:
        y0, y1 = y1, y0
    d.rectangle([int(x0), int(y0), int(x1), int(y1)], fill=c)

def ell(d, x0, y0, x1, y1, c):
    if x1 < x0:
        x0, x1 = x1, x0
    if y1 < y0:
        y0, y1 = y1, y0
    d.ellipse([int(x0), int(y0), int(x1), int(y1)], fill=c)

def ln(d, x0, y0, x1, y1, c, w=1):
    d.line([int(x0), int(y0), int(x1), int(y1)], fill=c, width=int(w))

def poly(d, pts, c):
    d.polygon([(int(x), int(y)) for x, y in pts], fill=c)

def vgrad(d, x0, y0, x1, y1, c_dark, c_base, c_light, split=(0.30, 0.78)):
    """竖条三阶明暗：左侧暗、右侧亮，做出圆柱感。"""
    h = y1 - y0
    a = y0 + int(h * split[0])
    b = y0 + int(h * split[1])
    rct(d, x0, y0, x0, y1, dark(c_base, 0.78))
    rct(d, x1, y0, x1, y1, dark(c_base, 0.86))
    rct(d, x0 + 1, y0, x1 - 1, y1, c_base)
    rct(d, x1 - 1, y0, x1 - 1, y1, c_light)
    rct(d, x0 + 1, a, x1 - 1, b, c_base)

def outline(img, col=OUTLINE, diag=True):
    """1px 外描边：膨胀 alpha 后垫底。"""
    a = img.split()[3]
    f = ImageFilter.MaxFilter(3)
    dil = a.filter(f)
    # 仅一次 3x3 膨胀 = 1px 描边（旧版又叠加两次 → 6px 实心黑框，人物像站在黑墓碑里）
    base = Image.new("RGBA", img.size, col)
    base.putalpha(dil)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(base)
    out.alpha_composite(img)
    return out

def save_strip(path, frames, cell=CELL):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    w = cell * len(frames)
    sheet = Image.new("RGBA", (w, cell), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.alpha_composite(fr, (i * cell, 0))
    sheet.save(path)
    return path

def validate(path, cell=CELL, expect=None):
    im = Image.open(path).convert("RGBA")
    assert im.height == cell, "height %d != %d" % (im.height, cell)
    assert im.width % cell == 0, "width %d not multiple of %d" % (im.width, cell)
    n = im.width // cell
    if expect is not None:
        assert n == expect, "frames %d != %d" % (n, expect)
    # 每格必须有内容，且不能被裁到边界
    for i in range(n):
        c = im.crop((i * cell, 0, (i + 1) * cell, cell))
        assert c.getbbox() is not None, "frame %d empty" % i
        bb = c.getbbox()
        assert bb[2] - bb[0] >= 6, "frame %d too narrow" % i
    return n

# ------------------------------------------------------------------ 人物
POSES = [
    # (bob, step, arm, lean)
    (0, 0, 0, 0), (1, 0, 1, 0), (1, 0, 0, 1), (0, 0, -1, 0),
    (0, -1, 1, 0), (1, 0, 0, 0), (0, 1, -1, 0), (1, 0, 0, 1),
]

DEFAULTS = dict(
    skin=SKIN, hair=HAIR_BRN, beard=False, robe=LINEN, robe2=TAN, trim=GOLD,
    belt=LEATHER, metal=BRONZE, boot=LEATHER, cape=None, head="none",
    hair_len=1, build="normal", skirt=False, glow=None, shoulder=None,
    sash=None, detail=None, eye=OUTLINE,
)

W_BY_BUILD = {"slim": 11, "normal": 13, "broad": 15}


def _cfg(cfg):
    c = dict(DEFAULTS)
    c.update(cfg or {})
    return c


def render(cfg, frames=FRAMES):
    c = _cfg(cfg)
    out = []
    poses = POSES if frames == 8 else POSES[:frames]
    for i, (bob, step, arm, lean) in enumerate(poses):
        im = new_cell()
        d = ImageDraw.Draw(im)
        kind = "idle" if i < 4 else "walk"
        _body(d, c, bob, step, arm, lean)
        ctx = _ctx(c, i, kind, bob, step, arm)
        if c["detail"] is not None:
            c["detail"](d, ctx)
        im = outline(im)
        if c["glow"]:
            im = _glow(im, c["glow"])
        out.append(im)
    return out


def _mk(bob=0, step=0, arm=0):
    cx = 24
    fy = FEET
    head_t = 6 + bob
    head_b = 16 + bob
    torso_t = 17 + bob
    torso_b = 31 + bob
    return dict(cx=cx, fy=fy, head_t=head_t, head_b=head_b, torso_t=torso_t,
                torso_b=torso_b, waist=30 + bob, hand_r=(cx + 12 + arm, 26 + bob),
                hand_l=(cx - 12 - arm, 26 + bob), shoulder_r=(cx + 7, 19 + bob),
                shoulder_l=(cx - 7, 19 + bob))


def _ctx(c, i, kind, bob, step, arm):
    mk = _mk(bob, step, arm)
    return dict(pose=(bob, step, arm, 0), kind=kind, frame=i, x=mk["cx"], y=mk["fy"],
                colors=c, mk=mk)


def _body(d, c, bob, step, arm, lean):
    mk = _mk(bob, step, arm)
    cx, fy = mk["cx"], mk["fy"]
    w = W_BY_BUILD.get(c["build"], 13)
    hw = w // 2
    # 影子
    ell(d, cx - 8, fy - 1, cx + 8, fy + 2, (0, 0, 0, 70))
    # 披风（身后）
    if c["cape"]:
        cp = c["cape"]
        sway = -1 if step < 0 else (1 if step > 0 else 0)
        poly(d, [(cx - hw - 1, mk["torso_t"] + 1), (cx + hw + 1, mk["torso_t"] + 1),
                 (cx + hw + 2 + sway, fy - 3), (cx - hw - 3 + sway, fy - 3)], dark(cp, 0.92))
        poly(d, [(cx - hw + 1, mk["torso_t"] + 3), (cx + hw - 1, mk["torso_t"] + 3),
                 (cx + hw + 1 + sway, fy - 6), (cx - hw - 2 + sway, fy - 6)], cp)
    if c["skirt"]:
        skirt_col = c["robe"]
        poly(d, [(cx - hw, mk["torso_b"] - 2), (cx + hw, mk["torso_b"] - 2),
                 (cx + hw + 2, fy - 2), (cx - hw - 2, fy - 2)], dark(skirt_col, 0.9))
        rct(d, cx - hw, mk["torso_b"] - 2, cx + hw + 1, fy - 3, skirt_col)
        rct(d, cx - hw - 2, fy - 4, cx + hw + 2, fy - 2, dark(skirt_col, 0.72))
        for k in range(3):
            x = cx - hw + 2 + k * 4
            ln(d, x, mk["torso_b"], x + 1, fy - 4, dark(skirt_col, 0.78), 1)
    # 腿
    lo = 2 if step < 0 else 0
    ro = -2 if step > 0 else 0
    leg = dark(c["robe2"], 0.95) if c["skirt"] else c["robe2"]
    rct(d, cx - 5, mk["torso_b"] - 1, cx - 2, fy - 3 + lo, leg)
    rct(d, cx + 2, mk["torso_b"] - 1, cx + 5, fy - 3 + ro, leg)
    rct(d, cx - 6, fy - 2 + lo, cx - 1, fy, c["boot"])
    rct(d, cx + 1, fy - 2 + ro, cx + 6, fy, c["boot"])
    rct(d, cx - 6, fy - 2 + lo, cx - 1, fy - 1 + lo, light(c["boot"], 1.1))
    rct(d, cx + 1, fy - 2 + ro, cx + 6, fy - 1 + ro, light(c["boot"], 1.1))
    # 躯干
    robe = c["robe"]
    rct(d, cx - hw, mk["torso_t"], cx + hw, mk["torso_b"], robe)
    rct(d, cx - hw, mk["torso_t"], cx - hw + 1, mk["torso_b"], dark(robe, 0.74))
    rct(d, cx + hw - 1, mk["torso_t"], cx + hw, mk["torso_b"], light(robe, 1.18))
    # 袍子的对襟 / 衣褶
    if c["trim"]:
        ln(d, cx + 1, mk["torso_t"] + 1, cx + 1, mk["torso_b"], c["trim"], 1)
        ln(d, cx - 2, mk["torso_t"] + 3, cx - 2, mk["torso_b"] - 1, dark(robe, 0.68), 1)
    # 腰带
    rct(d, cx - hw, mk["waist"], cx + hw + 1, mk["waist"] + 2, c["belt"])
    rct(d, cx - 1, mk["waist"], cx + 1, mk["waist"] + 2, c["metal"])
    if c["sash"]:
        ln(d, cx - hw + 1, mk["torso_t"] + 2, cx + hw - 1, mk["waist"] - 1, c["sash"], 2)
    # 肩
    if c["shoulder"]:
        rct(d, cx - hw - 1, mk["torso_t"] - 1, cx - hw + 2, mk["torso_t"] + 2, c["shoulder"])
        rct(d, cx + hw - 2, mk["torso_t"] - 1, cx + hw + 1, mk["torso_t"] + 2, c["shoulder"])
    # 手臂
    ax_l, ay = cx - hw - 2, mk["torso_t"] + 2
    ax_r = cx + hw + 1
    swing = arm * 2
    rct(d, ax_l, ay, ax_l + 2, ay + 5 + swing, dark(robe, 0.86))
    rct(d, ax_r, ay, ax_r + 2, ay + 5 - swing, robe)
    rct(d, ax_l, ay + 5 + swing, ax_l + 2, ay + 7 + swing, c["skin"])
    rct(d, ax_r, ay + 5 - swing, ax_r + 2, ay + 7 - swing, c["skin"])
    # 头
    _head(d, c, mk)


def _head(d, c, mk):
    cx = mk["cx"]
    ht, hb = mk["head_t"], mk["head_b"]
    skin = c["skin"]
    rct(d, cx - 4, ht + 1, cx + 4, hb, skin)
    rct(d, cx - 4, ht, cx + 3, ht + 1, skin)
    rct(d, cx - 4, ht + 1, cx - 3, hb, dark(skin, 0.82))
    rct(d, cx + 3, ht + 1, cx + 4, hb, light(skin, 1.06))
    # 眼
    px(d, cx - 2, ht + 6, c["eye"])
    px(d, cx + 2, ht + 6, c["eye"])
    # 鼻/嘴
    px(d, cx + 1, ht + 7, dark(skin, 0.78))
    px(d, cx, ht + 9, dark(skin, 0.62))
    # 发
    hl = int(c["hair_len"])
    hair = c["hair"]
    rct(d, cx - 4, ht, cx + 3, ht + 2, hair)
    rct(d, cx - 4, ht + 2, cx - 4, ht + 3 + hl, hair)
    rct(d, cx + 3, ht + 1, cx + 4, ht + 2 + hl, dark(hair, 0.9))
    if c["beard"]:
        bl = 3 if c["beard"] == "long" else 2
        rct(d, cx - 3, hb - 1, cx + 3, hb + bl, hair)
        rct(d, cx - 2, hb + bl, cx + 2, hb + bl, dark(hair, 0.85))
        px(d, cx, hb + bl, dark(hair, 0.75))
    # 头饰
    hd = c["head"]
    if hd == "crown":
        rct(d, cx - 4, ht - 2, cx + 4, ht + 1, GOLD)
        for k in (-3, 0, 3):
            rct(d, cx + k, ht - 4, cx + k, ht - 2, GOLD_L)
        px(d, cx, ht - 1, HOLY)
    elif hd == "hood":
        rct(d, cx - 5, ht - 1, cx + 5, ht + 3, dark(c["robe"], 0.92))
        rct(d, cx - 5, ht + 3, cx - 4, hb, dark(c["robe"], 0.88))
        rct(d, cx + 4, ht + 3, cx + 4, hb, dark(c["robe"], 0.88))
        rct(d, cx - 3, ht + 4, cx + 3, ht + 5, (0, 0, 0, 90))
    elif hd == "helmet":
        rct(d, cx - 5, ht - 2, cx + 5, ht + 4, IRON)
        rct(d, cx - 4, ht - 3, cx + 4, ht - 2, STEEL)
        rct(d, cx - 5, ht + 4, cx - 4, ht + 9, IRON_D)
        rct(d, cx + 4, ht + 4, cx + 5, ht + 9, IRON_D)
        rct(d, cx - 1, ht + 4, cx + 1, ht + 8, IRON_D)
        px(d, cx, ht - 4, GOLD)
    elif hd == "turban":
        for k in range(3):
            rct(d, cx - 5 + (k % 2), ht - 2 + k, cx + 5 - (k % 2), ht - 1 + k, c["robe2"])
        rct(d, cx - 5, ht + 2, cx - 4, ht + 5, c["robe2"])
        px(d, cx + 4, ht + 1, c["trim"])
    elif hd == "veil":
        rct(d, cx - 5, ht - 1, cx - 4, hb + 2, c["robe"])
        rct(d, cx + 4, ht - 1, cx + 5, hb + 2, c["robe"])
        rct(d, cx - 5, ht - 2, cx + 5, ht - 1, light(c["robe"], 1.05))
    elif hd == "wreath":
        for k in (-3, -1, 1, 3):
            px(d, cx + k, ht - 1, OLIVE)
        px(d, cx, ht - 2, GREEN)
    elif hd == "mitre":
        rct(d, cx - 4, ht - 3, cx + 4, ht + 1, LINEN)
        rct(d, cx - 1, ht - 3, cx + 1, ht + 1, GOLD)
        rct(d, cx - 4, ht + 1, cx + 4, ht + 2, GOLD)


def _glow(im, color):
    a = im.split()[3]
    halo = a.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(1.2))
    base = Image.new("RGBA", im.size, color)
    base.putalpha(halo.point(lambda v: int(v * 0.30)))
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.alpha_composite(base)
    out.alpha_composite(im)
    return out


# ------------------------------------------------------------------ 道具小工具
def staff(d, x, y0, y1, c_wood=LEATHER):
    rct(d, x, y0, x, y1, c_wood)
    rct(d, x - 1, y0, x - 1, y1, dark(c_wood, 0.7))
    px(d, x, y0, light(c_wood, 1.3))


def serpent_staff(d, x, y0, y1):
    staff(d, x, y0, y1)
    ell(d, x - 2, y0 - 3, x + 2, y0 + 1, BRONZE)
    px(d, x + 2, y0 - 4, BRONZE)
    px(d, x - 2, y0 - 4, dark(BRONZE, 0.8))


def tablets(d, x, y):
    rct(d, x - 1, y, x + 3, y + 6, SAND)
    rct(d, x - 1, y, x + 3, y + 1, light(SAND, 1.1))
    for k in range(3):
        ln(d, x, y + 2 + k, x + 2, y + 2 + k, dark(SAND, 0.55), 1)
    ell(d, x + 1, y, x + 3, y + 1, SAND)


def torch(d, x, y, t=0.0):
    rct(d, x - 1, y, x + 1, y + 8, LEATHER)
    h = 4 + int(1.5 * math.sin(t))
    ell(d, x - 2, y - h, x + 2, y, FLAME_O)
    ell(d, x - 1, y - h + 1, x + 1, y - 1, FLAME)
    px(d, x, y - h + 1, HOLY)


def shofar(d, x, y):
    ln(d, x - 3, y + 3, x + 3, y, TAN, 2)
    ln(d, x + 3, y, x + 5, y - 2, TAN, 2)
    px(d, x + 5, y - 3, GOLD)


def sword(d, x, y0, y1):
    rct(d, x, y0, x, y1, STEEL)
    rct(d, x, y0, x, y1, light(STEEL, 1.05))
    rct(d, x - 2, y1 - 2, x + 2, y1 - 1, GOLD)
    rct(d, x, y1, x, y1 + 2, LEATHER)


def lyre(d, x, y):
    ln(d, x - 3, y, x - 3, y + 5, GOLD, 1)
    ln(d, x + 3, y, x + 3, y + 5, GOLD, 1)
    ln(d, x - 3, y + 5, x + 3, y + 5, GOLD, 1)
    for k in (-2, 0, 2):
        ln(d, x + k, y + 1, x + k, y + 4, GOLD_L, 1)


def halo(d, cx, y, r=7, col=GOLD_L, alpha=110):
    for k in range(16):
        a = k * math.pi / 8.0
        px(d, cx + int(math.cos(a) * r), y + int(math.sin(a) * r * 0.55), col)
