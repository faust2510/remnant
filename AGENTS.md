# 余民 The Remnant · 项目铁律

本文件只写「每次开工都必须知道、且只对本项目成立」的约定。通用 Godot 流程见技能 `godot-game-workflow`。

## 一句话

圣经题材类幸存者。设计唯一权威是 [docs/设计圣典-v0.6.md](docs/设计圣典-v0.6.md)，实现与它冲突时改实现，不改圣典；要改圣典先问用户。

## 三条内容红线（不可协商）

1. 玩家绝不扮演耶稣或三位格；见证人只能是受造的人。
2. 敌人永远是属灵军兵与试炼意象，不影射现实族群、教会或教派。
3. 不血腥、不抽卡、不赌博式随机奖励。

## 技术约定

- 引擎 Godot 4.7 稳定版，纯 GDScript（本机没有 .NET）。
- 模拟层（`src/sim`、`src/combat`、`src/core`）**不得**引用场景树节点 API，必须能在 `--headless` 下独立跑完一局。
- 敌人与弹幕一律 SoA 数组 + 空间哈希；新增实体类型只加数据，不改循环结构。
- 武器行为只有五类原子（line_projectile / arc_melee / orbit / zone / homing）；祝圣、合鸣、成全都是参数组合，禁止为单个武器写专用分支。
- 所有平衡数值放 `data/*.json`，代码里不写死伤害、冷却、血量。

## 本机跑法与坑

```bash
# 导入（新增 class_name 后必须先跑）
HOME="$PWD/.godot_home" /Applications/Godot.app/Contents/MacOS/Godot --headless --import > /tmp/import.log 2>&1

# 无头平衡模拟
HOME="$PWD/.godot_home" /Applications/Godot.app/Contents/MacOS/Godot --headless -- --sim --sim-speed=60 > /tmp/sim.log 2>&1

# 截图自查
HOME="$PWD/.godot_home" /Applications/Godot.app/Contents/MacOS/Godot -- --shot --shot-at=50
```

- HOME 必须重定向到 `.godot_home`，否则会污染用户目录。
- **Godot 输出不能接管道**（EPIPE 会直接杀进程），一律重定向到文件再 grep。
- 中文路径：先 `cd` 进项目再用相对路径。
- 新增 `class_name` 后不跑 `--import` 会报 `Identifier "X" not declared`。
- macOS 无 `timeout` 命令（是 `gtimeout`）。

## 验收标准

「编译通过」不算完成。必须做到：
1. 无头模拟跑通一局并给出数值报告（`--sim`）；
2. 截图亲眼看过画面（`--shot`），确认 HUD、敌人、弹幕、UI 都正常显示。
