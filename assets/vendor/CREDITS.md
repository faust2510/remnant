# 资源署名

## 本项目自有资源（CC0 / 公共领域，作者：本项目团队）

`assets/sprites/`、`assets/icons/` 下的像素图集全部由项目自有的生成脚本绘制，无第三方素材、无 AI 图库来源：

| 资源 | 尺寸 | 内容 | 生成脚本 |
|---|---|---|---|
| `sprites/witnesses.png` | 128×128 | 4 见证人 × 4 帧 | `tools/gen_art.py` |
| `sprites/enemies.png` | 128×256 | 8 种敌人 × 4 帧 | `tools/gen_art.py` |
| `sprites/props.png` | 96×16 | 4 档宝石 / 银币 / 火炭 | `tools/gen_art.py` |
| `icons/weapons.png` | 160×128 | 20 把武器图标 | `tools/gen_art.py` |
| `icons/passives.png` | 160×128 | 20 个被动图标 | `tools/gen_art.py` |

生成方式：Pillow 逐像素绘制 + 1px 描边（MaxFilter 膨胀）+ 固定 20 色调色板量化，无外部图像输入。
重新生成：`python3 tools/gen_art.py`（幂等，覆盖同名文件）。

未收录的敌人（24 普通 + 12 精英中的其余 28 种）在运行时回退为程序化几何绘制，不涉及第三方素材。

## 音频

`assets/sfx/*.wav` 由 Python `wave` 模块程序化合成（正弦/噪声包络），无第三方版权。

## 字体

字体使用系统字体（macOS STHeiti / Songti，Windows 微软雅黑，Linux 文泉驿），不随项目分发。正式发行前必须替换为可再分发的开源字体（如思源黑体 / 霞鹜文楷，SIL OFL）并在此登记。

## 后续接入第三方资源时的登记格式

| 资源 | 来源 | 许可 | 是否需署名 | 用途 |
|---|---|---|---|---|
| （待填） | （待填） | （CC0 / CC-BY / OFL） | （是/否） | （待填） |

红线：NC（非商用）、ND（禁止演绎）、许可不明一律不用；CC-BY 必须在本文件署名。
