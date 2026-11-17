#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4 敌人条带生成：8 种 x 32x32 x 6 帧（tools/out/enemy_<id>.png）。

几何契约（docs/V4-美术重制契约.md 第 1/4 节）
    * 单格 32x32，脚底 y=28，一律朝右绘制，运行期按格镜像。
    * 1px 描边 #0A0E14（artbase.outline diag=False），全整数坐标、硬边。
    * 敌人整体比见证人暗、冷（低明度），亮点只给红眼 / 金属边 / 铜盔。
    * 6 帧必须真动画：走 / 扑 / 飘 至少 2px 位移或形变。

画法约定
    * artbase 的 rct/ell/ln/poly 第一参数是 ImageDraw.Draw。
    * 每帧先画远端肢体 / 背后道具，再画躯干，再画近端肢体 / 手持道具。
    * 绘制区域控制在 x 1..30 / y 1..29（描边后仍在格内，不会被裁切）。
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)

import artbase as A
from PIL import Image, ImageDraw

CELL = 32
FEET = 28
OUT = os.path.join(TOOLS, "out")

# ------------------------------------------------------------------ 冷色调色板
OUTL = A.hx("#0A0E14")
IRON_D = A.hx("#1E242D")
IRON = A.hx("#333C49")
IRON_L = A.hx("#525E6E")
STEEL = A.hx("#7C8A9C")
GLINT = A.hx("#B9C6D6")
CLOTH_D = A.hx("#141920")
CLOTH = A.hx("#212832")
CLOTH_L = A.hx("#333D4B")
CLOAK_D = A.hx("#181D26")
CLOAK = A.hx("#262D3A")
CLOAK_L = A.hx("#39424F")
RED_D = A.hx("#3B1614")
RED = A.hx("#5E2420")
RED_L = A.hx("#85392E")
LEATHER_D = A.hx("#1E1811")
LEATHER = A.hx("#33271B")
LEATHER_L = A.hx("#4C3A27")
BOW = A.hx("#5A4632")
BOW_L = A.hx("#7A6042")
GOLD_D = A.hx("#5A471B")
GOLD = A.hx("#8A6C2A")
GOLD_L = A.hx("#B89543")
BONE_D = A.hx("#565246")
BONE = A.hx("#7E7867")
BONE_L = A.hx("#A8A18D")
EYE = A.hx("#D93A2A")
EYE_H = A.hx("#FF8055")
SKIN = A.hx("#7E5D41")
SKIN_L = A.hx("#96714C")
SKIN_D = A.hx("#5C422C")
ASH = A.hx("#4E4A44")
ASH_L = A.hx("#67625A")
ASH_D = A.hx("#2E2B26")
BRONZE_D = A.hx("#43321A")
BRONZE = A.hx("#624926")
BRONZE_L = A.hx("#836331")
SNAKE_D = A.hx("#28331F")
SNAKE = A.hx("#3F5030")
SNAKE_L = A.hx("#5E7544")
VOID = A.hx("#03050A")
OLIVE_D = A.hx("#2A3120")
OLIVE = A.hx("#3C472B")
OLIVE_L = A.hx("#55633A")
BLUE_D = A.hx("#151F29")
BLUE = A.hx("#24374A")
BLUE_L = A.hx("#3A566F")
RAVEN_D = A.hx("#0C0F14")
RAVEN = A.hx("#171C24")
RAVEN_L = A.hx("#252E3A")
RAVEN_B = A.hx("#2C4864")
FUR = A.hx("#3A342C")
FUR_L = A.hx("#4E4639")

ORDER = ["soldier", "archer", "raven", "beast", "scorpion",
         "six_finger_giant", "goliath", "the_tempter"]


def cell():
    return Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))


def col(d, x0, y0, x1, y1, c, dk=0.72, lt=1.24):
    """竖条三阶：左暗 / 中基色 / 右亮（圆柱体积感）。"""
    A.rct(d, x0, y0, x1, y1, c)
    A.rct(d, x0, y0, x0, y1, A.dark(c, dk))
    A.rct(d, x1, y0, x1, y1, A.light(c, lt))


def leg(d, x, dx, lift, pant, boot, w=3):
    """一条腿 + 靴；脚底压 y=28。"""
    A.rct(d, x + dx, 20, x + w - 1 + dx, 25, pant)
    A.rct(d, x + dx, 20, x + dx, 25, A.dark(pant, 0.66))
    A.rct(d, x + w - 2 + dx, 20, x + w - 1 + dx, 25, A.light(pant, 1.15))
    A.rct(d, x - 1 + dx, 26 - lift, x + w + dx, 28 - lift, boot)
    A.rct(d, x - 1 + dx, 26 - lift, x + w + dx, 26 - lift, A.light(boot, 1.18))


def seq(d, pts, c, w=1):
    """折线（逐段直线，硬边）。"""
    for i in range(len(pts) - 1):
        A.ln(d, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], c, w)


# ------------------------------------------------------------------ soldier
def soldier(d, f):
    fstep = [0, 2, 2, 0, -1, 0][f]
    bstep = [0, -1, -2, 0, 2, 0][f]
    bob = [0, 0, 1, 1, 0, 0][f]

    # 远侧腿（后，暗）
    leg(d, 9, bstep, 1 if f == 4 else 0, CLOTH_D, LEATHER_D)
    # 近侧腿（前）
    leg(d, 14, fstep, 1 if f == 1 else 0, CLOTH, LEATHER)

    # 短剑（举在身后侧，刀尖朝上）
    A.rct(d, 4, 4, 5, 12, STEEL)
    A.rct(d, 4, 4, 4, 12, A.dark(STEEL, 0.72))
    A.rct(d, 5, 5, 5, 12, A.light(STEEL, 1.08))
    A.px(d, 4, 3, GLINT)
    A.px(d, 5, 4, GLINT)
    A.rct(d, 2, 13, 7, 13, GOLD)
    A.px(d, 2, 13, GOLD_D)
    A.px(d, 7, 13, GOLD_L)
    A.rct(d, 4, 14, 5, 16, LEATHER_L)
    A.rct(d, 3, 17, 6, 18, SKIN_D)          # 握拳
    A.px(d, 3, 17, SKIN)
    A.ln(d, 7, 17, 8, 16, CLOTH_L, 2)       # 小臂

    # 躯干（束腰军袍，暗红）
    col(d, 8, 13 + bob, 18, 22 + bob, RED, 0.66, 1.42)
    A.rct(d, 9, 13 + bob, 17, 14 + bob, RED_L)
    A.rct(d, 9, 15 + bob, 17, 16 + bob, RED)
    A.rct(d, 9, 16 + bob, 10, 18 + bob, A.dark(RED, 0.7))   # 胸甲阴影
    # 皮带 + 金扣
    A.rct(d, 8, 19 + bob, 18, 20 + bob, LEATHER_D)
    A.rct(d, 8, 19 + bob, 18, 19 + bob, LEATHER_L)
    A.rct(d, 11, 19 + bob, 13, 20 + bob, GOLD_D)
    A.px(d, 12, 19 + bob, GOLD_L)
    # 皮条裙（pteruges）
    for k in range(4):
        x = 9 + k * 3
        A.rct(d, x, 21 + bob, x + 1, 23 + bob, A.dark(RED, 0.9) if k % 2 else RED_D)
        A.px(d, x, 23 + bob, A.dark(LEATHER_D, 0.9))

    # 大盾（身前）：铁边 + 红漆面 + 金盾脐 + 双加强筋，宽度约占 1/3 格
    sy = bob
    A.rct(d, 17, 9 + sy, 27, 26 + sy, IRON_D)
    A.rct(d, 18, 10 + sy, 26, 25 + sy, RED_D)
    A.rct(d, 19, 11 + sy, 25, 24 + sy, RED)
    A.rct(d, 19, 11 + sy, 19, 24 + sy, A.dark(RED, 0.72))
    A.rct(d, 25, 11 + sy, 25, 24 + sy, A.light(RED, 1.45))
    A.rct(d, 18, 12 + sy, 26, 12 + sy, IRON)
    A.rct(d, 18, 12 + sy, 26, 12 + sy, IRON_L)
    A.rct(d, 18, 23 + sy, 26, 23 + sy, IRON_L)
    A.rct(d, 26, 10 + sy, 27, 25 + sy, IRON)
    A.rct(d, 27, 11 + sy, 27, 24 + sy, IRON_L)
    A.px(d, 26, 10 + sy, STEEL)
    A.px(d, 26, 25 + sy, A.dark(IRON, 0.7))
    A.ell(d, 20, 15 + sy, 24, 20 + sy, GOLD_D)
    A.ell(d, 21, 16 + sy, 23, 19 + sy, GOLD)
    A.px(d, 22, 16 + sy, GOLD_L)
    A.px(d, 21, 18 + sy, A.dark(GOLD, 0.72))
    # 盾背握把
    A.rct(d, 17, 16 + sy, 18, 19 + sy, LEATHER_D)

    # 头 + 罗马盔（红缨）
    A.rct(d, 11, 8 + bob, 17, 13 + bob, SKIN_D)
    A.rct(d, 11, 8 + bob, 11, 13 + bob, A.dark(SKIN_D, 0.78))
    A.rct(d, 16, 8 + bob, 17, 12 + bob, SKIN)
    A.px(d, 15, 10 + bob, A.hx("#E8C58A"))   # 眼
    A.px(d, 15, 10 + bob, OUTL)
    A.px(d, 16, 12 + bob, A.dark(SKIN_D, 0.66))
    A.px(d, 14, 12 + bob, A.dark(SKIN_D, 0.66))
    # 盔壳
    A.rct(d, 10, 6 + bob, 18, 8 + bob, IRON)
    A.rct(d, 11, 5 + bob, 17, 5 + bob, IRON_L)
    A.rct(d, 12, 5 + bob, 15, 5 + bob, A.light(IRON, 1.75))
    A.rct(d, 9, 8 + bob, 10, 11 + bob, IRON_D)     # 护颈
    A.rct(d, 18, 8 + bob, 19, 11 + bob, IRON_L)    # 前护颊
    A.px(d, 18, 8 + bob, STEEL)
    A.rct(d, 18, 10 + bob, 19, 10 + bob, GLINT)
    # 红缨（拱起 + 后垂）
    A.poly(d, [(11, 4 + bob), (12, 2 + bob), (15, 1 + bob), (18, 3 + bob),
               (18, 5 + bob), (15, 3 + bob), (12, 4 + bob)], RED)
    A.px(d, 12, 2 + bob, RED_L)
    A.px(d, 13, 2 + bob, RED_L)
    A.px(d, 14, 2 + bob, A.light(RED, 1.7))
    A.rct(d, 9, 4 + bob, 10, 8 + bob, RED_D)
    A.px(d, 9, 4 + bob, RED)


# ------------------------------------------------------------------ archer
def archer(d, f):
    pull = [0, 1, 2, 3, 2, 0][f]        # 拉弦量：弦中点左移 0..3px
    bob = [0, 0, 1, 1, 0, 0][f]
    step = [0, 1, 1, 0, -1, 0][f]
    rel = 1 if f == 3 else 0            # 释放帧：箭已离弦

    # 箭袋（背后，左）+ 三支露出的箭杆
    A.rct(d, 3, 11 + bob, 7, 20 + bob, LEATHER_D)
    A.rct(d, 4, 11 + bob, 7, 20 + bob, LEATHER)
    A.rct(d, 4, 11 + bob, 4, 20 + bob, A.dark(LEATHER, 0.58))
    A.rct(d, 3, 15 + bob, 7, 16 + bob, LEATHER_L)
    A.px(d, 3, 15 + bob, A.dark(LEATHER, 0.6))
    for k, ax in enumerate((4, 5, 6)):
        top = 5 + bob + k
        A.rct(d, ax, top, ax, 11 + bob, A.dark(BONE, 0.66))
        A.px(d, ax, top, BONE_L)
        A.px(d, ax + 1, top + 1, RED)                # 羽尾
        A.px(d, ax - 1, top + 1, A.dark(RED, 0.78))

    # 远侧腿
    leg(d, 9, -step, 1 if f == 2 else 0, CLOTH_D, LEATHER_D)

    # 斗篷下摆（后）
    A.poly(d, [(8, 16 + bob), (18, 16 + bob), (19, 22 + bob), (14, 23 + bob),
               (7, 21 + bob)], OLIVE_D)
    A.ln(d, 10 + step, 18 + bob, 9 + step, 22 + bob, A.dark(OLIVE_D, 0.7), 1)

    # 躯干（猎装）
    col(d, 9, 13 + bob, 18, 21 + bob, OLIVE, 0.66, 1.4)
    A.rct(d, 10, 13 + bob, 17, 13 + bob, OLIVE_L)
    A.rct(d, 12, 15 + bob, 13, 17 + bob, A.dark(OLIVE_D, 0.8))
    A.rct(d, 9, 18 + bob, 18, 19 + bob, LEATHER)
    A.rct(d, 9, 19 + bob, 18, 19 + bob, LEATHER_D)
    A.rct(d, 9, 18 + bob, 18, 18 + bob, LEATHER_L)
    A.rct(d, 12, 18 + bob, 13, 18 + bob, GOLD_D)

    # 近侧腿
    leg(d, 14, step, 0, CLOTH, LEATHER)

    # 尖兜帽（尖顶略后倾，罩住整个头）
    A.poly(d, [(14, 3 + bob), (10, 6 + bob), (8, 10 + bob), (8, 14 + bob),
               (19, 14 + bob), (19, 7 + bob), (16, 4 + bob)], CLOTH_D)
    A.poly(d, [(14, 4 + bob), (10, 7 + bob), (9, 10 + bob), (9, 13 + bob),
               (18, 13 + bob), (18, 7 + bob), (15, 5 + bob)], CLOTH)
    A.ln(d, 10, 5 + bob, 9, 10 + bob, CLOTH_L, 1)
    A.px(d, 14, 3 + bob, A.light(CLOTH, 1.4))
    A.px(d, 15, 4 + bob, CLOTH_L)
    # 兜帽内：脸（只露右半，压在阴影里）
    A.poly(d, [(15, 7 + bob), (18, 8 + bob), (18, 12 + bob), (13, 12 + bob),
               (13, 9 + bob)], SKIN_D)
    A.rct(d, 17, 8 + bob, 18, 11 + bob, SKIN)
    A.px(d, 16, 9 + bob, A.hx("#100C08"))     # 眼窝
    A.px(d, 17, 9 + bob, A.hx("#C79A5E"))     # 眼
    A.px(d, 17, 11 + bob, A.dark(SKIN, 0.72))
    A.rct(d, 13, 7 + bob, 18, 7 + bob, A.dark(CLOTH_D, 0.92))   # 帽檐投影
    A.rct(d, 18, 8 + bob, 19, 11 + bob, CLOTH_D)                # 前檐压边

    # 持弓臂（前伸，压住弓把）
    A.ln(d, 17, 14 + bob, 26, 15 + bob, CLOTH_L, 2)
    A.px(d, 26, 16 + bob, A.dark(CLOTH, 0.7))

    # 长弓（竖立，弓梢高出兜帽尖端）
    path = [(25, 1), (26, 3), (27, 6), (28, 9), (29, 12), (29, 16),
            (28, 20), (27, 23), (26, 26), (25, 28)]
    seq(d, path, BOW, 2)
    seq(d, [(x - 1, y) for (x, y) in path], A.dark(BOW, 0.6), 1)
    seq(d, [(x + 1, y - 1) for (x, y) in path[1:]], BOW_L, 1)
    A.px(d, 25, 1, BONE)
    A.px(d, 26, 2, BONE_L)
    A.px(d, 25, 28, BONE_D)
    # 弓弦（拉满时呈 V，弦色压暗免得压过弓身）
    sx = 24 - pull
    string = A.dark(BONE, 0.62)
    A.ln(d, 25, 2, sx, 13 + bob, string, 1)
    A.ln(d, sx, 13 + bob, 25, 27, string, 1)

    # 搭在弦上的箭（f3 已离弦）
    if not rel:
        ax0 = 14 - pull
        A.rct(d, ax0, 13 + bob, 27, 13 + bob, BONE)
        A.rct(d, ax0, 13 + bob, ax0 + 2, 13 + bob, A.dark(BONE, 0.7))
        A.px(d, ax0, 12 + bob, RED_L)
        A.px(d, ax0, 14 + bob, RED_L)
        A.px(d, ax0 + 2, 12 + bob, A.dark(RED, 0.9))
        A.poly(d, [(27, 12 + bob), (30, 13 + bob), (27, 14 + bob)], STEEL)
        A.px(d, 28, 13 + bob, GLINT)
    else:
        A.px(d, 25, 13, BONE_L)                  # 弦震
        A.px(d, 26, 12, A.dark(BONE, 0.8))

    # 拉弦手（在弦上，随 pull 左移）
    A.rct(d, sx - 1, 12 + bob, sx, 14 + bob, SKIN_D)
    A.px(d, sx - 1, 12 + bob, SKIN)
    # 握弓手
    A.rct(d, 27, 14 + bob, 28, 16 + bob, SKIN_D)
    A.px(d, 28, 14 + bob, SKIN)
    A.px(d, 27, 16 + bob, A.dark(SKIN_D, 0.72))


# ------------------------------------------------------------------ raven
def _wing(d, near, lift):
    """展开的双翼：近翼(左后,亮) / 远翼(右前,暗)。肩固定，翼尖随 lift 下压，
    后缘两道锯齿使三根飞羽在轮廓外可辨。"""
    h = lift // 2
    if near:
        col, edge = RAVEN_L, RAVEN_B
        A.poly(d, [(16, 22), (13, 15), (11, 11), (7, 5 + h),
                   (6, 3 + lift), (9, 6 + lift), (8, 9 + lift), (11, 9 + lift),
                   (10, 13 + lift), (14, 16 + lift // 2), (16, 23)], col)
        A.ln(d, 16, 22, 13, 15, edge, 1)
        A.ln(d, 13, 15, 11, 11, edge, 1)
        A.ln(d, 11, 11, 7, 5 + h, A.light(edge, 1.1), 1)
        A.px(d, 6, 3 + lift, A.light(edge, 1.35))
        A.px(d, 7, 6 + lift, A.light(RAVEN_L, 1.1))
        A.px(d, 9, 8 + lift, RAVEN_B)
    else:
        col, edge = RAVEN_D, A.dark(RAVEN_B, 0.7)
        A.poly(d, [(16, 18), (19, 13), (22, 9), (25, 5 + h),
                   (26, 4 + lift), (24, 7 + lift), (25, 10 + lift), (22, 10 + lift),
                   (23, 14 + lift), (19, 15), (16, 19)], col)
        A.ln(d, 16, 18, 19, 13, edge, 1)
        A.ln(d, 19, 13, 22, 9, edge, 1)
        A.px(d, 26, 4 + lift, edge)


def raven(d, f):
    # 扑翼：翼尖 y 3 -> 9（6px 位移），身体同时起伏
    lift = [0, 2, 4, 6, 5, 2][f]
    bob = [0, -1, -1, 0, 1, 0][f]
    cy = 21 + bob

    # 尾羽（左后，两齿缺口）
    A.poly(d, [(9, cy - 2), (9, cy + 3), (1, cy + 6), (2, cy + 3), (5, cy + 2),
               (2, cy + 1), (7, cy - 2)], RAVEN_D)
    A.poly(d, [(9, cy - 2), (9, cy + 2), (3, cy + 4), (4, cy + 2), (7, cy - 1)], RAVEN)
    A.ln(d, 7, cy + 1, 2, cy + 4, RAVEN_D, 1)
    A.px(d, 4, cy + 2, RAVEN_B)

    # 远翼（前上方，暗一档，先画在身后）
    _wing(d, False, lift)

    # 身体
    A.ell(d, 7, cy - 3, 20, cy + 4, RAVEN)
    A.ell(d, 8, cy - 3, 19, cy + 1, RAVEN_L)
    A.rct(d, 9, cy + 3, 18, cy + 4, RAVEN_D)
    A.ln(d, 9, cy - 3, 18, cy - 3, RAVEN_B, 1)
    A.px(d, 12, cy - 4, A.light(RAVEN_B, 1.25))
    # 颈 -> 头
    A.poly(d, [(16, cy - 3), (21, cy - 7), (22, cy - 1), (17, cy + 2)], RAVEN_L)
    A.ell(d, 18, cy - 8, 24, cy - 1, RAVEN)
    A.ell(d, 19, cy - 8, 23, cy - 4, RAVEN_L)
    A.ln(d, 19, cy - 8, 22, cy - 8, RAVEN_B, 1)
    A.px(d, 20, cy - 8, A.light(RAVEN_B, 1.15))
    # 喙（短粗，带钩）
    A.poly(d, [(23, cy - 5), (27, cy - 3), (26, cy - 1), (23, cy - 1)], BONE_D)
    A.px(d, 23, cy - 5, A.light(BONE, 1.2))
    A.px(d, 24, cy - 4, BONE)
    A.px(d, 27, cy - 3, A.light(BONE, 1.35))
    A.px(d, 25, cy - 2, A.dark(BONE_D, 0.68))
    A.px(d, 23, cy - 1, A.dark(BONE_D, 0.6))
    # 红眼
    A.px(d, 22, cy - 6, EYE_H)
    A.px(d, 22, cy - 5, EYE)
    A.px(d, 21, cy - 6, A.dark(EYE, 0.6))
    # 爪
    A.px(d, 13, cy + 5, BONE_D)
    A.px(d, 15, cy + 5, BONE_D)
    A.px(d, 13, cy + 6, A.dark(BONE_D, 0.6))
    A.px(d, 15, cy + 6, A.dark(BONE_D, 0.6))

    # 近翼（后上方，亮一档，锯齿飞羽在轮廓外可辨）
    _wing(d, True, lift)


# ------------------------------------------------------------------ beast
def _bent_leg(d, hx, hy, kx, ky, px, c, dark_c):
    """两段弯腿：大腿(粗) + 小腿(细) + 爪。"""
    A.ln(d, hx, hy, kx, ky, c, 3)
    A.ln(d, hx, hy, kx, ky, dark_c, 1)
    A.ln(d, kx, ky, px, 25, c, 2)
    A.rct(d, px - 1, 25, px + 2, 27, c)
    A.rct(d, px - 1, 27, px + 2, 27, dark_c)
    A.px(d, px - 1, 27, BONE_D)
    A.px(d, px + 2, 27, BONE_D)


def beast(d, f):
    dx = [0, 1, 0, -1, 0, 1][f]
    dy = [0, 0, -1, 0, 1, 0][f]
    bx = 5 + dx
    by = 19 + dy
    fur = FUR
    fur_d = A.dark(FUR, 0.7)

    # 尾巴（后上翘，骨刺尾端）
    seq(d, [(bx + 2, by - 2), (bx - 2, by - 5), (bx - 3, by - 9)], fur_d, 2)
    A.px(d, bx - 3, by - 10, BONE)
    A.px(d, bx - 2, by - 10, BONE_D)

    # 远侧腿（暗）
    _bent_leg(d, bx + 6, by + 3, bx + 6, by + 7, bx + 7, A.dark(fur, 0.55), A.dark(fur, 0.4))
    _bent_leg(d, bx + 12, by + 3, bx + 12, by + 7, bx + 13, A.dark(fur, 0.55), A.dark(fur, 0.4))

    # 躯干（低伏长身）
    A.ell(d, bx, by - 3, bx + 15, by + 4, fur_d)
    A.ell(d, bx + 1, by - 3, bx + 14, by + 2, fur)
    A.ln(d, bx + 2, by - 3, bx + 13, by - 3, A.light(FUR, 1.35), 1)
    A.ln(d, bx + 1, by + 3, bx + 13, by + 3, A.dark(fur, 0.55), 1)
    for k in range(3):
        A.ln(d, bx + 3 + k * 4, by - 2, bx + 2 + k * 4, by + 2, A.dark(fur, 0.62), 1)

    # 背脊尖刺（骨白，剪影可数）
    for sx, sh in ((bx + 1, 3), (bx + 4, 5), (bx + 8, 6), (bx + 12, 4)):
        A.poly(d, [(sx, by - 3), (sx + 1, by - 3 - sh), (sx + 2, by - 3)], BONE_D)
        A.px(d, sx + 1, by - 3 - sh, BONE_L)
        A.px(d, sx + 1, by - 2, BONE)
        A.px(d, sx + 2, by - 3, fur)

    # 近侧腿
    front = 1 if f in (1, 4) else 0
    _bent_leg(d, bx + 5, by + 3, bx + 3, by + 7 + front, bx + 2, fur, fur_d)
    _bent_leg(d, bx + 13, by + 3, bx + 15, by + 7 - front, bx + 16, fur, fur_d)

    # 头（大、低伏前探、张口露獠牙）
    hx = bx + 13
    A.ell(d, hx, by - 6, hx + 7, by + 2, fur)                 # 颅
    A.ell(d, hx + 1, by - 6, hx + 6, by - 2, A.light(fur, 1.3))
    A.poly(d, [(hx + 1, by - 6), (hx + 2, by - 10), (hx + 4, by - 6)], fur)   # 耳
    A.px(d, hx + 2, by - 9, fur_d)
    # 上颚（前伸，带高光）
    A.rct(d, hx + 3, by - 2, hx + 9, by - 1, fur)
    A.rct(d, hx + 3, by - 2, hx + 9, by - 2, A.light(fur, 1.18))
    A.px(d, hx + 9, by - 2, A.dark(fur, 0.55))                # 鼻头
    # 口腔（2px 深洞）
    A.rct(d, hx + 5, by, hx + 9, by + 1, A.hx("#0B0806"))
    # 下颚
    A.rct(d, hx + 3, by + 2, hx + 8, by + 3, fur)
    A.rct(d, hx + 3, by + 3, hx + 8, by + 3, A.dark(fur, 0.66))
    # 獠牙（上 2 下 2，骨白，不血腥）
    A.px(d, hx + 6, by + 1, BONE_L)
    A.px(d, hx + 8, by + 1, BONE_L)
    A.px(d, hx + 5, by, BONE)
    A.px(d, hx + 7, by, BONE)
    # 红眼 + 眉骨
    A.px(d, hx + 4, by - 4, EYE_H)
    A.px(d, hx + 4, by - 3, EYE)
    A.px(d, hx + 3, by - 4, A.dark(EYE, 0.6))
    A.rct(d, hx + 3, by - 5, hx + 5, by - 5, A.dark(fur, 0.58))


# ------------------------------------------------------------------ scorpion
def scorpion(d, f):
    bob = [0, 0, 1, 1, 0, 0][f]
    tail = [0, 1, 2, 1, 0, -1][f]     # 尾摆 2-3px
    claw = [0, 1, 1, 0, 1, 0][f]      # 钳口开合
    body_d = ASH_D
    body_m = A.mix(ASH_D, ASH, 0.75)
    body_l = ASH

    # 腿（近侧 4 条两段弯腿，远侧 2 条暗腿）
    for lx in (11, 14, 17):
        A.ln(d, lx + 1, 24, lx + 3, 26, A.dark(ASH_D, 0.62), 1)
        A.px(d, lx + 3, 27, A.dark(ASH_D, 0.55))
    for k, lx in enumerate((10, 13, 16, 19)):
        sw = 1 if (f + k) % 2 else 0
        A.ln(d, lx, 24 + bob, lx - 2, 26, body_d, 1)
        A.ln(d, lx - 2, 26, lx - 3 - sw, 27, body_d, 1)
        A.px(d, lx - 3 - sw, 27, A.dark(ASH_D, 0.6))

    # 甲壳（3 片叠压背甲 + 分节暗线）
    A.ell(d, 8, 19 + bob, 19, 25 + bob, body_d)
    A.ell(d, 9, 19 + bob, 18, 23 + bob, body_m)
    for px0 in (10, 13, 16):
        A.ln(d, px0, 19 + bob, px0 - 1, 24 + bob, A.dark(ASH_D, 0.5), 1)
        A.px(d, px0 + 1, 20 + bob, body_l)
    A.rct(d, 9, 24 + bob, 19, 24 + bob, A.dark(ASH_D, 0.5))
    A.px(d, 12, 21 + bob, A.light(ASH, 1.2))
    A.px(d, 15, 21 + bob, ASH)

    # 头（前端小楔）+ 双小眼
    A.poly(d, [(18, 20 + bob), (22, 20 + bob), (22, 24 + bob), (18, 24 + bob)], body_m)
    A.px(d, 21, 21 + bob, EYE)
    A.px(d, 20, 21 + bob, A.hx("#B9A34A"))
    A.px(d, 22, 23 + bob, A.dark(ASH_D, 0.6))

    # 尾（从尾端高翘过背，节节分明，尖高于身体）
    tp = [(8, 20 + bob), (6, 17 + bob), (5 + tail // 2, 13 + bob),
          (7 + tail, 9 + bob), (10 + tail, 6 + bob), (13 + tail, 4 + bob),
          (15 + tail, 2 + bob)]
    for i in range(len(tp) - 1):
        c = body_m if i % 2 == 0 else A.mix(body_d, body_m, 0.5)
        A.ln(d, tp[i][0], tp[i][1], tp[i + 1][0], tp[i + 1][1], c, 2)
    A.ln(d, tp[0][0], tp[0][1] + 1, tp[1][0] + 1, tp[1][1] + 1, body_d, 1)
    for i in range(1, len(tp) - 1):
        A.px(d, tp[i][0], tp[i][1] - 1, body_l)            # 节顶受光
        A.px(d, tp[i][0], tp[i][1] + 1, A.dark(ASH_D, 0.45))  # 节间暗环
    # 尾针（毒囊 + 骨针，指向右下）
    tx, ty = tp[-1]
    A.ell(d, tx - 1, ty - 1, tx + 1, ty + 2, body_m)
    A.px(d, tx, ty - 1, body_l)
    seq(d, [(tx + 1, ty), (tx + 3, ty + 2), (tx + 4, ty + 4)], BONE, 1)
    A.px(d, tx + 4, ty + 4, BONE_L)
    A.px(d, tx + 5, ty + 5, A.hx("#E2DAC2"))

    # 上钳（前上方）：粗掌 + C 形双指（指缝留空，描边成黑缝）
    A.ln(d, 19, 20 + bob, 22, 16 + bob, body_m, 3)
    A.ell(d, 21, 11 + bob, 27, 17 + bob, body_d)
    A.ell(d, 22, 12 + bob, 26, 16 + bob, body_m)
    A.px(d, 24, 12 + bob, body_l)
    A.px(d, 23, 15 + bob, A.dark(ASH_D, 0.6))
    A.rct(d, 26, 11 + bob, 30, 12 + bob, body_m)                 # 固定指
    A.rct(d, 26, 16 + bob - claw, 29, 17 + bob - claw, body_m)   # 可动指
    A.px(d, 30, 11 + bob, BONE_L)
    A.px(d, 29, 17 + bob - claw, BONE_L)
    A.px(d, 26, 12 + bob, body_l)
    A.px(d, 27, 12 + bob, A.light(body_m, 1.2))

    # 下钳（前下方）
    A.ln(d, 19, 23 + bob, 22, 26 + bob, body_m, 3)
    A.ell(d, 21, 21 + bob, 27, 27 + bob, body_d)
    A.ell(d, 22, 22 + bob, 26, 26 + bob, body_m)
    A.px(d, 24, 22 + bob, body_l)
    A.rct(d, 26, 21 + bob, 30, 22 + bob, body_m)
    A.rct(d, 26, 26 + bob + claw, 29, 27 + bob + claw, body_m)
    A.px(d, 30, 21 + bob, BONE_L)
    A.px(d, 29, 27 + bob + claw, BONE_L)
    A.px(d, 27, 22 + bob, body_l)


# ------------------------------------------------------------------ six_finger_giant
def _fan_hand(d, px, py, down, side, skin, skin_l, skin_d):
    """巨手：7x7 厚掌 + 六根扇形张开的手指（指根并拢、指尖散开，可数）。"""
    s = 1 if down else -1          # 手指伸出方向
    pad = py + 6 if down else py   # 掌外缘（指根线）
    A.rct(d, px + 1, py, px + 5, py + 6, skin)
    A.rct(d, px, py + 1, px + 6, py + 5, skin)
    A.rct(d, px + 2, py + 1, px + 5, py + 1, skin_l)
    A.rct(d, px, py + 1, px, py + 5, skin_d)
    A.rct(d, px + 1, py + 3, px + 5, py + 4, A.dark(skin, 0.86))   # 掌心阴影
    # 拇指（掌外侧伸出，2px 粗，与掌分开以免糊进躯干）
    tsx = px if side < 0 else px + 6
    ttx = tsx + side * 2
    A.ln(d, tsx, py + 4, ttx, py + 4 + s * 2, skin, 2)
    A.px(d, ttx, py + 4 + s * 2, BONE_D)
    # 六指：指根并拢在掌缘，越往指尖越散
    roots = (1, 2, 3, 4, 5, 6)
    spread = (-2, -1, 0, 0, 1, 2)
    lens = (3, 4, 5, 5, 4, 3)
    for i in range(6):
        sx = px + roots[i]
        tx = sx + spread[i]
        ty = pad + s * lens[i]
        A.ln(d, sx, pad, tx, ty, skin if i % 2 == 0 else A.dark(skin, 0.92), 1)
        A.px(d, tx, ty, BONE_D)
        A.px(d, tx, ty + s, A.dark(skin, 0.8))


def six_finger_giant(d, f):
    bob = [0, 1, 1, 0, 1, 0][f]
    stomp = [0, 2, 1, 0, -1, 1][f]
    swing = [0, -1, -2, -1, 0, 1][f]

    # 腿（粗腿 + 大脚）
    leg(d, 11, max(0, stomp) // 2, 1 if stomp >= 2 else 0, FUR, LEATHER_D, w=4)
    A.rct(d, 10, 27, 14, 27, A.dark(LEATHER_D, 0.7))
    leg(d, 17, -min(0, stomp), 0, A.dark(FUR, 0.86), LEATHER, w=4)
    A.rct(d, 16, 27, 20, 27, A.dark(LEATHER, 0.75))
    # 腰布
    A.rct(d, 11, 19 + bob, 20, 22 + bob, LEATHER_D)
    A.rct(d, 11, 19 + bob, 20, 19 + bob, LEATHER_L)
    for k in range(4):
        A.rct(d, 11 + k * 3, 22 + bob, 12 + k * 3, 23 + bob,
              LEATHER_D if k % 2 else A.dark(LEATHER, 0.8))

    # 躯干（宽肩厚背，灰皮）
    col(d, 11, 12 + bob, 20, 19 + bob, ASH_D, 0.72, 1.3)
    A.rct(d, 12, 13 + bob, 19, 14 + bob, ASH)
    A.rct(d, 12, 16 + bob, 13, 18 + bob, A.dark(ASH_D, 0.8))
    A.rct(d, 12, 15 + bob, 19, 15 + bob, A.dark(ASH, 0.7))
    # 肩甲（铁片，宽肩）
    A.rct(d, 9, 11 + bob, 22, 13 + bob, IRON_D)
    A.rct(d, 9, 11 + bob, 22, 11 + bob, IRON)
    A.rct(d, 9, 12 + bob, 10, 13 + bob, IRON_L)
    A.px(d, 22, 11 + bob, IRON_L)
    A.px(d, 21, 12 + bob, IRON)

    # 头（小而凶）
    A.rct(d, 13, 3 + bob, 19, 11 + bob, ASH)
    A.rct(d, 13, 3 + bob, 13, 11 + bob, ASH_D)
    A.rct(d, 18, 3 + bob, 19, 9 + bob, ASH_L)
    A.rct(d, 13, 3 + bob, 19, 4 + bob, A.dark(ASH, 0.82))
    A.rct(d, 14, 4 + bob, 18, 4 + bob, A.light(ASH, 1.15))     # 眉骨
    A.px(d, 17, 6 + bob, A.hx("#B33A26"))                      # 红眼
    A.px(d, 16, 6 + bob, OUTL)
    A.px(d, 16, 5 + bob, ASH_D)
    A.rct(d, 19, 5 + bob, 19, 8 + bob, A.dark(ASH, 0.86))      # 鼻
    A.rct(d, 13, 9 + bob, 18, 10 + bob, A.dark(ASH_D, 0.72))   # 下颌
    # 前突的厚颚 + 一颗獠牙（轮廓右侧探出 1px）
    A.rct(d, 18, 8 + bob, 20, 10 + bob, ASH)
    A.rct(d, 18, 8 + bob, 20, 8 + bob, ASH_L)
    A.rct(d, 18, 10 + bob, 20, 10 + bob, A.dark(ASH_D, 0.7))
    A.px(d, 19, 10 + bob, BONE_D)
    A.px(d, 15, 10 + bob, A.dark(ASH_D, 0.6))

    # 左臂 + 左手（垂低，六指张开朝下）
    A.ln(d, 11, 13 + bob, 8, 15 + bob, ASH_D, 3)
    A.px(d, 9, 14 + bob, ASH)
    A.rct(d, 3, 13 + bob + swing, 8, 14 + bob + swing, LEATHER_D)   # 腕带
    _fan_hand(d, 3, 14 + bob + swing, True, -1, ASH, ASH_L, ASH_D)

    # 右臂 + 右手（举起，六指张开朝上）
    A.ln(d, 20, 13 + bob, 23, 12 + bob, ASH, 3)
    A.px(d, 23, 11 + bob, ASH_L)
    _fan_hand(d, 22, 6 + bob - swing, False, 1, ASH, ASH_L, ASH_D)


# ------------------------------------------------------------------ goliath
def _scales(d, x0, y0, x1, y1):
    """鱼鳞甲：暗底 + 交错半圆鳞片（每片只留 1px 亮边）。"""
    A.rct(d, x0, y0, x1, y1, BRONZE_D)
    row = 0
    y = y0 + 1
    while y <= y1 - 1:
        off = 0 if row % 2 == 0 else 2
        x = x0 - 2 + off
        while x <= x1 - 3:
            if x >= x0:
                A.px(d, x, y + 1, BRONZE)
                A.px(d, x + 1, y + 1, BRONZE)
                A.px(d, x + 2, y, BRONZE_L)
                A.px(d, x + 3, y + 1, BRONZE)
                A.px(d, x + 1, y + 2, A.dark(BRONZE_D, 0.8))
                A.px(d, x + 2, y + 2, A.dark(BRONZE_D, 0.7))
            x += 4
        y += 3
        row += 1
    A.rct(d, x0, y1, x1, y1, A.dark(BRONZE_D, 0.7))


def goliath(d, f):
    bob = [0, 0, 1, 1, 0, 1][f]
    sway = [0, 1, 0, -1, 0, 1][f]
    stomp = [0, 2, 1, 0, -1, 1][f]

    # 披风（身后，暗红，下摆随步子摆）
    A.poly(d, [(7, 12 + bob), (19, 12 + bob), (22 + sway, 26), (17 + sway, 28),
               (10 + sway, 27), (4 + sway, 24)], RED_D)
    A.poly(d, [(8, 13 + bob), (18, 13 + bob), (20 + sway, 25), (14 + sway, 26),
               (7 + sway, 24)], A.dark(RED, 0.86))
    A.ln(d, 16, 15 + bob, 18 + sway, 24, A.dark(RED, 0.55), 1)

    # 腿（粗腿 + 铜护胫）
    leg(d, 9, max(0, stomp) // 2, 1 if stomp >= 2 else 0, FUR, LEATHER_D, w=4)
    leg(d, 15, -min(0, stomp), 0, A.dark(FUR, 0.9), LEATHER, w=4)
    A.rct(d, 8, 21, 12, 23, BRONZE_D)
    A.rct(d, 8, 21, 12, 21, BRONZE)
    A.px(d, 9, 22, BRONZE_L)
    A.rct(d, 14, 21, 18, 23, BRONZE_D)
    A.rct(d, 14, 21, 18, 21, A.dark(BRONZE, 0.8))
    A.px(d, 17, 22, BRONZE_L)

    # 鱼鳞甲躯干（肩宽腰窄）
    A.poly(d, [(8, 12 + bob), (20, 12 + bob), (19, 22 + bob), (9, 22 + bob)],
           BRONZE_D)
    _scales(d, 9, 12 + bob, 19, 21 + bob)
    # 甲缘高光（胸线 / 腰线）
    A.rct(d, 9, 12 + bob, 19, 12 + bob, BRONZE_L)
    A.rct(d, 9, 21 + bob, 19, 21 + bob, A.dark(BRONZE, 0.72))
    # 肩甲
    A.ell(d, 16, 10 + bob, 21, 14 + bob, BRONZE_D)
    A.ell(d, 17, 11 + bob, 20, 13 + bob, BRONZE)
    A.px(d, 18, 11 + bob, BRONZE_L)
    A.px(d, 19, 12 + bob, BRONZE_L)
    A.ell(d, 7, 11 + bob, 11, 14 + bob, BRONZE_D)
    A.px(d, 9, 12 + bob, BRONZE)
    # 腰带 + 甲裙
    A.rct(d, 9, 20 + bob, 19, 20 + bob, LEATHER_D)
    A.px(d, 13, 20 + bob, GOLD_D)
    for k in range(4):
        x = 10 + k * 3
        A.rct(d, x, 22 + bob, x + 1, 24 + bob, BRONZE_D if k % 2 else A.dark(BRONZE, 0.8))
        A.px(d, x, 22 + bob, BRONZE)

    # 脸（盔下阴影 + 胡须 + 亮眼）
    A.rct(d, 10, 7 + bob, 17, 12 + bob, SKIN_D)
    A.rct(d, 10, 7 + bob, 10, 12 + bob, A.dark(SKIN_D, 0.72))
    A.rct(d, 17, 7 + bob, 17, 11 + bob, SKIN)
    A.px(d, 16, 9 + bob, A.hx("#E8C070"))
    A.px(d, 15, 9 + bob, OUTL)
    A.rct(d, 10, 11 + bob, 17, 12 + bob, A.hx("#1C1510"))      # 胡须
    A.px(d, 12, 11 + bob, A.hx("#33261A"))
    A.px(d, 15, 11 + bob, A.hx("#33261A"))
    A.rct(d, 13, 7 + bob, 13, 10 + bob, BRONZE_D)              # 鼻梁护

    # 铜盔（带双角）
    A.ell(d, 9, 3 + bob, 19, 9 + bob, BRONZE)
    A.ell(d, 10, 3 + bob, 18, 6 + bob, BRONZE_L)
    A.rct(d, 9, 8 + bob, 19, 8 + bob, BRONZE_D)
    A.rct(d, 10, 7 + bob, 18, 7 + bob, A.dark(BRONZE, 0.85))
    A.rct(d, 9, 5 + bob, 9, 8 + bob, A.dark(BRONZE, 0.62))
    A.px(d, 12, 4 + bob, A.light(BRONZE_L, 1.25))
    A.px(d, 13, 4 + bob, A.light(BRONZE_L, 1.1))
    # 双角（左长右短，尖端骨白）
    seq(d, [(9, 5 + bob), (7, 3 + bob), (4, 2 + bob)], BRONZE_L, 2)
    A.px(d, 4, 2 + bob, BONE_L)
    A.px(d, 3, 2 + bob, BONE)
    seq(d, [(19, 5 + bob), (21, 3 + bob), (24, 3 + bob)], A.dark(BRONZE, 0.9), 1)
    A.px(d, 24, 3 + bob, BONE)

    # 巨矛（tip y=1 高过头顶，尾端 y=29 过脚）
    sh = [0, 0, 1, 1, 0, 1][f]
    A.rct(d, 26, 7 + sh, 27, 29, IRON_D)
    A.rct(d, 27, 7 + sh, 27, 29, LEATHER_L)
    A.px(d, 27, 9 + sh, A.dark(LEATHER_L, 0.7))
    A.px(d, 27, 20 + sh, A.dark(LEATHER_L, 0.7))
    # 矛刃（宽叶 6px）
    A.poly(d, [(26, 1 + sh), (23, 5 + sh), (24, 6 + sh), (26, 8 + sh),
               (28, 6 + sh), (29, 5 + sh)], STEEL)
    A.px(d, 26, 1 + sh, GLINT)
    A.ln(d, 26, 2 + sh, 25, 6 + sh, GLINT, 1)
    A.px(d, 23, 5 + sh, A.dark(STEEL, 0.6))
    A.px(d, 28, 6 + sh, A.dark(STEEL, 0.72))
    A.rct(d, 24, 7 + sh, 28, 7 + sh, GOLD_D)
    # 矛头红系带
    A.px(d, 25, 8 + sh, RED_L)
    A.px(d, 24, 9 + sh, RED)
    A.px(d, 23, 10 + sh, RED_D)

    # 持矛臂
    A.ln(d, 18, 14 + bob, 26, 17 + sh, BRONZE, 3)
    A.ln(d, 19, 14 + bob, 25, 16 + sh, A.dark(BRONZE, 0.66), 1)
    A.rct(d, 25, 16 + sh, 26, 17 + sh, SKIN_D)
    A.px(d, 25, 16 + sh, SKIN)
    A.px(d, 26, 17 + sh, A.dark(SKIN_D, 0.7))


# ------------------------------------------------------------------ the_tempter
def the_tempter(d, f):
    bob = [0, -1, -2, -1, 0, -1][f]
    sway = [0, 1, 2, 1, 0, -1][f]
    drift = [0, 1, 2, 1, 0, -1][f]

    def P(x, y):
        """下摆点：越靠下飘得越远。"""
        k = 0 if y < 20 else (1 if y < 24 else 2)
        return (x + (drift * k) // 2 * (1 if x > 14 else -1), y + bob)

    # 脱离本体的碎屑
    A.px(d, 3 + drift, 22 + bob, A.dark(CLOTH, 0.85))
    A.px(d, 25 - drift, 21 + bob, A.dark(CLOTH, 0.85))
    A.px(d, 7 + drift, 27 + bob, A.dark(CLOTH_D, 0.95))
    A.px(d, 21 + drift, 27 + bob, A.dark(CLOTH_D, 0.95))

    # 长袍（腰收、下摆散成锯齿破布尖）
    body = [P(10, 12), P(18, 12), P(20, 17), P(22, 23), P(19, 27),
            P(17, 22), P(15, 28), P(13, 22), P(10, 27), P(7, 23), P(7, 17)]
    A.poly(d, body, CLOTH_D)
    A.poly(d, [P(12, 13), P(18, 13), P(19, 17), P(21, 22), P(18, 25),
               P(16, 21), P(14, 25), P(11, 21), P(8, 17)], CLOTH)
    # 冷色边光（右侧）+ 衣褶
    A.ln(d, P(7, 16)[0], P(7, 16)[1], P(7, 23)[0], P(7, 23)[1],
         A.dark(CLOTH_L, 0.92), 1)
    A.ln(d, P(19, 17)[0], P(19, 17)[1], P(21, 22)[0], P(21, 22)[1], BLUE_L, 1)
    A.px(d, P(21, 22)[0], P(21, 22)[1], A.light(BLUE_L, 1.2))
    A.ln(d, 11, 14 + bob, 9, 21 + bob, A.dark(CLOTH_D, 0.66), 1)
    A.ln(d, 14, 15 + bob, 13, 22 + bob, A.dark(CLOTH, 0.7), 1)
    A.ln(d, 16, 17 + bob, 17, 21 + bob, A.dark(CLOTH, 0.8), 1)

    # 兜帽（尖顶，内里纯黑无脸）
    A.poly(d, [(14, 1 + bob), (10, 4 + bob), (8, 9 + bob), (8, 13 + bob),
               (19, 13 + bob), (19, 6 + bob), (16, 2 + bob)], CLOTH_D)
    A.poly(d, [(14, 2 + bob), (10, 5 + bob), (9, 9 + bob), (9, 12 + bob),
               (18, 12 + bob), (18, 6 + bob), (15, 3 + bob)], CLOTH)
    A.ln(d, 10, 4 + bob, 9, 9 + bob, CLOTH_L, 1)
    A.px(d, 14, 1 + bob, A.light(CLOTH, 1.35))
    A.px(d, 15, 2 + bob, CLOTH_L)
    # 兜帽内：纯黑（无脸 / 无眼 / 无高光）
    A.poly(d, [(11, 5 + bob), (17, 5 + bob), (17, 10 + bob), (11, 11 + bob)], VOID)
    A.px(d, 11, 5 + bob, A.hx("#0A0F18"))
    A.px(d, 16, 5 + bob, A.hx("#0A0F18"))
    A.px(d, 10, 8 + bob, A.hx("#0A0F18"))
    A.px(d, 18, 8 + bob, A.hx("#0A0F18"))
    # 帽口冷边（把黑洞和兜帽分开）
    A.ln(d, 11, 5 + bob, 17, 5 + bob, A.dark(CLOTH_L, 0.9), 1)
    A.px(d, 17, 10 + bob, A.dark(CLOTH_L, 0.8))

    # 肩披
    A.poly(d, [(7, 12 + bob), (19, 12 + bob), (20, 15 + bob), (14, 16 + bob),
               (6, 15 + bob)], CLOTH_D)
    A.ln(d, 7, 13 + bob, 19, 13 + bob, CLOTH_L, 1)
    A.ln(d, 9, 14 + bob, 16, 15 + bob, A.dark(CLOTH, 0.7), 1)
    A.px(d, 18, 14 + bob, CLOTH_L)

    # 宽袖（垂，袖口空黑）
    A.poly(d, [(8, 13 + bob), (5, 18 + bob), (7, 22 + bob), (11, 19 + bob),
               (11, 15 + bob)], CLOTH_D)
    A.px(d, 6, 18 + bob, CLOTH)
    A.poly(d, [(17, 13 + bob), (19, 16 + bob), (22, 19 + bob), (20, 21 + bob),
               (18, 17 + bob)], CLOTH)
    A.ln(d, 18, 15 + bob, 20, 18 + bob, CLOTH_L, 1)
    A.px(d, 19, 20 + bob, A.dark(CLOTH_D, 0.6))

    # 蛇纹边：下摆连续锯齿（明线）+ 前襟斜行 + 小蛇头
    hem = [P(7, 23), P(9, 25), P(11, 23), P(13, 26), P(15, 23), P(17, 25),
           P(19, 22), P(21, 23)]
    for i in range(len(hem) - 1):
        A.ln(d, hem[i][0], hem[i][1], hem[i + 1][0], hem[i + 1][1],
             SNAKE_L if i % 2 == 0 else SNAKE, 1)
        A.px(d, hem[i][0], hem[i][1] + 1, SNAKE_D)
    hx0, hy0 = hem[-1]
    A.px(d, hx0 + 1, hy0 - 1, SNAKE_L)      # 蛇头
    A.px(d, hx0 + 2, hy0 - 1, SNAKE)
    A.px(d, hx0 + 2, hy0 - 2, EYE)          # 一点红眼
    A.px(d, hx0 + 1, hy0 - 2, SNAKE_D)
    # 前襟斜行蛇纹
    for i, (sx, sy) in enumerate([(18, 15), (19, 17), (20, 19), (21, 21)]):
        A.px(d, sx + (1 if i % 2 else 0), sy + bob, SNAKE_L if i % 2 else SNAKE)
    # 腰间蛇形扣
    A.rct(d, 11, 16 + bob, 16, 17 + bob, A.hx("#2A2319"))
    A.px(d, 17, 16 + bob, SNAKE_L)
    A.px(d, 18, 17 + bob, SNAKE)
    A.px(d, 18, 18 + bob, SNAKE_D)


# ------------------------------------------------------------------ 渲染 / 预览
BUILDERS = {
    "soldier": soldier,
    "archer": archer,
    "raven": raven,
    "beast": beast,
    "scorpion": scorpion,
    "six_finger_giant": six_finger_giant,
    "goliath": goliath,
    "the_tempter": the_tempter,
}


def build(fn):
    frames = []
    for f in range(6):
        im = cell()
        d = ImageDraw.Draw(im)
        fn(d, f)
        frames.append(A.outline(im, OUTL, False))
    return frames


def save_preview(eid, frames, scale=4):
    w = CELL * 6 * scale
    h = CELL * scale
    bg = Image.new("RGBA", (w, h), (20, 24, 32, 255))
    for i, fr in enumerate(frames):
        bg.alpha_composite(fr.resize((CELL * scale, CELL * scale), Image.NEAREST),
                           (i * CELL * scale, 0))
    p = os.path.join(OUT, "prev_%s.png" % eid)
    bg.save(p)
    return p


def main():
    os.makedirs(OUT, exist_ok=True)
    all_frames = []
    for eid in ORDER:
        frames = build(BUILDERS[eid])
        strip = os.path.join(OUT, "enemy_%s.png" % eid)
        A.save_strip(strip, frames, CELL)
        save_preview(eid, frames, 4)
        all_frames.append(frames)
        print("saved", strip)
    sc = 4
    sheet = Image.new("RGBA", (CELL * 6 * sc, CELL * 8 * sc), (20, 24, 32, 255))
    for r, frames in enumerate(all_frames):
        for i, fr in enumerate(frames):
            sheet.alpha_composite(fr.resize((CELL * sc, CELL * sc), Image.NEAREST),
                                  (i * CELL * sc, r * CELL * sc))
    p = os.path.join(OUT, "prev_ALL.png")
    sheet.save(p)
    print("saved", p)
    for eid in ORDER:
        A.validate(os.path.join(OUT, "enemy_%s.png" % eid), CELL, 6)
    print("OK")


if __name__ == "__main__":
    main()
