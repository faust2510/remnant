#!/usr/bin/env python3
"""V4 图集合成器。

把各 agent 产出的单角色条带合成整张图集：
    tools/out/wit_<id>.png   (48 x 384)  -> assets/sprites/witnesses.png  (384 x 960)
    tools/out/enemy_<id>.png (192 x 32)  -> assets/sprites/enemies.png    (192 x 256) x 8 行 = 192x256? 见下

enemies 每行 6 帧 x 32 = 192 宽，8 行 -> 192 x 256。
props / projectiles / icons 由 icons agent 直接写到 assets/，本脚本只做尺寸校验与缺省兜底。
缺任何一张条带时用 artbase 生成一个可辨认的占位角色，保证门禁永远不崩。
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import artbase  # noqa: E402

ATLAS = ROOT / "assets" / "sprites" / "atlas.json"
OUT = ROOT / "tools" / "out"

# 占位角色的配色（缺条带时用），按行号轮换，避免整张图一个色
PLACEHOLDER = [
    ("#6B3E78", "#D9B45A", "crown"),
    ("#6B4E32", "#C7AE86", "hood"),
    ("#C7AE86", "#20344F", "turban"),
    ("#6B4E32", "#C7AE86", "hood"),
    ("#DCD6C4", "#2F4E7A", "veil"),
    ("#DCD6C4", "#8E2F2F", "hood"),
    ("#2F4E7A", "#C0C8D2", "helmet"),
    ("#A8845C", "#F2A03C", "hood"),
    ("#C9A075", "#6B4E32", "none"),
    ("#7E4C9A", "#D9B45A", "veil"),
    ("#D9B45A", "#8A6B2E", "veil"),
    ("#4A3524", "#F2A03C", "hood"),
    ("#464C58", "#D9B45A", "hood"),
    ("#6B7280", "#D9B45A", "helmet"),
    ("#6B3E78", "#D9B45A", "crown"),
    ("#20344F", "#D9B45A", "turban"),
    ("#6B4E32", "#9AA0A6", "hood"),
    ("#464C58", "#C7AE86", "hood"),
    ("#4A3524", "#D9B45A", "none"),
    ("#D9B45A", "#E8E2D0", "wreath"),
]

warnings: list[str] = []


def load_rgba(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


def make_placeholder(row: int) -> list[Image.Image]:
    robe, accent, head = PLACEHOLDER[row % len(PLACEHOLDER)]
    robe_c = artbase.hx(robe)
    cfg = {
        "robe": robe_c,
        "robe2": artbase.dark(robe_c, 0.82),
        "trim": artbase.hx(accent),
        "head": head,
        "beard": artbase.hx("#D8D2C0") if head in ("hood", "turban", "wreath") else False,
        "cape": artbase.dark(robe_c, 0.72),
        "hair": artbase.hx("#3A2A1E"),
    }
    return artbase.render(cfg)


def check_strip(path: Path, cell: int, frames: int, label: str) -> bool:
    if not path.exists():
        return False
    im = load_rgba(path)
    want = (cell * frames, cell)
    if im.size != want:
        warnings.append(f"{label}: {path.name} 尺寸 {im.size} != {want}")
        return False
    return True


def compose_witnesses() -> None:
    spec = ATLAS_ROWS["witnesses"]
    cell, frames = spec["cell"], spec["frames"]
    rows = []
    for i, wid in enumerate(spec["rows"]):
        src = OUT / f"wit_{wid}.png"
        if check_strip(src, cell, frames, f"witness/{wid}"):
            rows.append(load_rgba(src))
        else:
            if src.exists() or True:
                warnings.append(f"witness/{wid}: 缺 {src.name}，用占位角色")
            im = Image.new("RGBA", (cell * frames, cell), (0, 0, 0, 0))
            for f, c in enumerate(make_placeholder(i)):
                im.paste(c, (f * cell, 0))
            rows.append(im)
    sheet = Image.new("RGBA", (cell * frames, cell * len(rows)), (0, 0, 0, 0))
    for i, r in enumerate(rows):
        sheet.paste(r, (0, i * cell))
    # 条带各自已带 1px 描边，这里不再二次描边（二次会变成 3px 黑框）
    dst = ROOT / "assets" / "sprites" / "witnesses.png"
    sheet.save(dst)
    print(f"witnesses.png {sheet.size} rows={len(rows)}")


def compose_enemies() -> None:
    spec = ATLAS_ROWS["enemies"]
    cell, frames = spec["cell"], spec["frames"]
    rows = []
    for eid in spec["rows"]:
        src = OUT / f"enemy_{eid}.png"
        if check_strip(src, cell, frames, f"enemy/{eid}"):
            rows.append(load_rgba(src))
        else:
            warnings.append(f"enemy/{eid}: 缺 {src.name}，用占位块")
            im = Image.new("RGBA", (cell * frames, cell), (0, 0, 0, 0))
            for f in range(frames):
                c = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
                dc = ImageDraw.Draw(c)
                artbase.rct(dc, 9, 12, 23, 28, artbase.hx("#3A3F4A"))
                artbase.rct(dc, 12, 6, 20, 13, artbase.hx("#5A4048"))
                artbase.px(dc, 14, 9, artbase.hx("#D94A3A"))
                im.paste(c, (f * cell, 0))
            rows.append(im)
    sheet = Image.new("RGBA", (cell * frames, cell * len(rows)), (0, 0, 0, 0))
    for i, r in enumerate(rows):
        sheet.paste(r, (0, i * cell))
    dst = ROOT / "assets" / "sprites" / "enemies.png"
    sheet.save(dst)
    print(f"enemies.png {sheet.size} rows={len(rows)}")


def check_assets() -> None:
    checks = [
        ("assets/sprites/props.png", (128, 16)),
        ("assets/sprites/projectiles.png", (128, 128)),
        ("assets/icons/weapons.png", (160, 128)),
        ("assets/icons/passives.png", (160, 128)),
    ]
    for rel, size in checks:
        p = ROOT / rel
        if not p.exists():
            warnings.append(f"{rel}: 不存在")
            continue
        im = load_rgba(p)
        if im.size != size:
            warnings.append(f"{rel}: 尺寸 {im.size} != {size}")
        else:
            print(f"ok {rel} {im.size}")


def main() -> int:
    global ATLAS_ROWS
    ATLAS_ROWS = json.loads(ATLAS.read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    compose_witnesses()
    compose_enemies()
    check_assets()
    if warnings:
        print("--- warnings")
        for w in warnings:
            print(" !", w)
    print("GEN_ART_DONE warnings=%d" % len(warnings))
    return 0


ATLAS_ROWS: dict = {}

if __name__ == "__main__":
    raise SystemExit(main())
