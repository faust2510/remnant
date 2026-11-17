import os, sys, math
sys.path.insert(0, "tools")
from artbase import *
from PIL import Image

def david_detail(d, ctx):
    mk = ctx["mk"]; cx = mk["cx"]; bob = mk["head_t"] - 6
    # 投石索（右手）
    hx_, hy = mk["hand_r"]
    ln(d, hx_, hy, hx_ + 4, hy + 3, LEATHER_L, 1)
    ell(d, hx_ + 3, hy + 2, hx_ + 6, hy + 5, LEATHER_L)
    # 竖琴（左手侧）
    lx, ly = mk["hand_l"]
    lyre(d, lx - 1, ly - 3)

moses_detail = None
def moses_fn(d, ctx):
    mk = ctx["mk"]; cx = mk["cx"]
    # 双石版（左臂）
    tablets(d, cx - 11, mk["torso_t"] + 3)
    # 蛇杖（右）
    serpent_staff(d, cx + 13, 12, 43)
    # 面光
    halo(d, cx, mk["head_t"] - 6, 8, HOLY, 120)

david = dict(skin=SKIN, hair=HAIR_AUB, beard=False, robe=PURPLE, robe2=PURPLE_D,
             trim=GOLD, belt=LEATHER, metal=GOLD, boot=LEATHER, cape=ROYAL,
             head="crown", hair_len=1, build="slim", skirt=False, detail=david_detail)
moses = dict(skin=SKIN_OLIVE, hair=HAIR_WHT, beard="long", robe=LINEN, robe2=SAND,
             trim=GOLD_D, belt=LEATHER, metal=GOLD, boot=LEATHER, cape=RED,
             head="none", hair_len=2, build="normal", skirt=True, glow=GOLD_L,
             detail=moses_fn)

fa = render(david); fb = render(moses)
save_strip("tools/out/_test_david.png", fa)
save_strip("tools/out/_test_moses.png", fb)

# 预览：4 倍放大并排
rows = [fa, fb]
W = CELL * 8 * 4
im = Image.new("RGBA", (W, CELL * 2 * 4), (24, 30, 42, 255))
for r, frames in enumerate(rows):
    for i, fr in enumerate(frames):
        big = fr.resize((CELL * 4, CELL * 4), Image.NEAREST)
        im.alpha_composite(big, (i * CELL * 4, r * CELL * 4))
im.save("tools/out/_preview.png")
print("ok", validate("tools/out/_test_david.png"), validate("tools/out/_test_moses.png"))
