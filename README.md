# 余民 The Remnant

圣经启示录题材的类幸存者（Survivor-like）动作游戏。Godot 4.7 / GDScript / 像素风。

当前版本：**P4 双地图** —— 标题选人 · **营地（舍客勒 / 六项永久强化 / 七印难度 / 试炼地图）** · 4 位见证人 · 以拉谷 + 犹大旷野两张地图 · 6 件基础武器 · 6 条固定祝圣 · 1 对双武合鸣 · 歌利亚 BOSS · 程序化音效。

## 运行

```bash
# 正常游玩
/Applications/Godot.app/Contents/MacOS/Godot --path .

# 无头平衡模拟（自动驾驶，跑完自动退出并打印报告）
HOME="$PWD/.godot_home" /Applications/Godot.app/Contents/MacOS/Godot --headless -- --sim --sim-speed=60

# 指定见证人（跳过标题画面）：david / moses / gideon / joshua
HOME="$PWD/.godot_home" /Applications/Godot.app/Contents/MacOS/Godot --headless -- --sim --sim-speed=900 --char=moses

# 截标题画面 / 营地画面
/Applications/Godot.app/Contents/MacOS/Godot -- --shot-title --shot-path=docs/shots/title.png
/Applications/Godot.app/Contents/MacOS/Godot -- --shot-camp --shot-path=docs/shots/camp.png

# 指定地图：elah_valley（以拉谷）/ judea_wilderness（犹大旷野）
HOME="$PWD/.godot_home" /Applications/Godot.app/Contents/MacOS/Godot --headless -- --sim --sim-speed=900 --stage=judea_wilderness

# 指定七印难度（1–7，不写则用营地里选的那一印）
HOME="$PWD/.godot_home" /Applications/Godot.app/Contents/MacOS/Godot --headless -- --sim --sim-speed=900 --seal=5

# 让模拟结果写入存档（默认模拟不写档；正常游玩总是写档）
HOME="$PWD/.godot_home" /Applications/Godot.app/Contents/MacOS/Godot --headless -- --sim-god --sim-speed=900 --save

# 截结算画面（自动驾驶跑完一局后定格）
/Applications/Godot.app/Contents/MacOS/Godot -- --shot-end --shot-path=docs/shots/end.png

# 营地购买逻辑自检（读档 → 逐项购买 → 打印加成）
HOME="$PWD/.godot_home" /Applications/Godot.app/Contents/MacOS/Godot --headless -- --camp-selftest

# 无敌模式跑满 13 分钟，验证 BOSS 与胜利流程
HOME="$PWD/.godot_home" /Applications/Godot.app/Contents/MacOS/Godot --headless -- --sim-god --sim-speed=600

# 自动游玩并截图（用于验收画面）
/Applications/Godot.app/Contents/MacOS/Godot -- --shot --shot-at=90
# 加 --shot-fast=40 先快进到目标时间附近；加 --shot-modal 截「领受/祭坛」面板；
# 用 --shot-path=/tmp/a.png 指定输出路径（默认 user://shot.png）
```

> 本机注意事项：HOME 必须指向项目内的 .godot_home；Godot 输出不要接管道（EPIPE 会杀进程），一律重定向到文件再 grep。

## 操作

| 键 | 作用 |
|---|---|
| WASD / 方向键 | 移动 |
| 鼠标右键（按住） | 圣灵引导 · 锁定方向，暴击率 +10%、弹速 +15% |
| 空格 | 信心跨步（闪避）。闪避中被打中触发「守望者时刻」：敌人减速 70%，持续 1.5 秒 |
| E | 在祭坛前使用火炭祝圣 |
| 1 / 2 / 3 | 领受与祭坛面板选择 |
| R（领受面板） | 重新求问 · 重掷本次三选一（每局 2 次） |
| Esc | 结算后重开 |
| R（结算后） | 返回营地 |

标题页：方向键 / WASD / 鼠标选见证人，Enter 进入营地，Esc 退出。
营地：↑↓ 选行，Enter 购买 / 出发，←→ 调七印或切换试炼地图，Esc 回标题。

## 目录

```
project.godot          引擎配置（autoload GameData / RunCfg / Meta；主场景 = 标题页）
scenes/title.tscn      标题与见证人选择
src/title_screen.gd    标题页绘制与输入（键盘 / 鼠标）
scenes/camp.tscn       营地（局外成长）
src/camp_screen.gd     营地绘制 / 购买 / 七印选择
src/core/meta.gd       局外存档：舍客勒、强化等级、七印、生涯统计（user://save.json）
src/core/run_cfg.gd    跨场景传参：选中的见证人与地图
data/                  纯数据：武器 / 被动 / 祝圣 / 敌人 / 见证人 / 地图
src/core/game_data.gd  载入 JSON 并建索引
src/core/game_state.gd 构筑状态：槽位、属性、经验、祝圣、成全
src/core/game_font.gd  取系统 CJK 字体
src/core/sfx.gd        音效池（14 个 AudioStreamPlayer，同名冷却）
assets/sfx/*.wav       8 个程序化合成音效（无第三方版权）
src/sim/spatial_grid.gd  静态链表空间哈希（零分配）
src/sim/enemy_sim.gd   敌人 SoA 模拟（行为 / 状态 / 投射物请求队列）
src/sim/projectile_sim.gd  弹幕模拟（玩家与敌人共用）
src/combat/weapon_runner.gd  五类行为原子：直线弹 / 扇形近战 / 环绕 / 区域 / 追踪
src/render/world_renderer.gd 单节点批量绘制（地面 / 敌人 / 弹幕 / 宝石 / 特效）
src/ui/hud.gd          HUD 与结算
src/ui/chooser.gd      领受 / 祭坛三选一面板
src/run.gd             单局流程：刷怪、掉落、祭坛、BOSS、面板调度、地图修饰
scenes/main.tscn       单局场景（只有一个挂 run.gd 的 Node2D）
```

## 营地与局外成长（P2）

流程：标题（选见证人）→ **营地** → 以拉谷。结算后按 R 回营地。

- **舍客勒**：舍客勒 = int(存活秒 / 8) + int(击杀 / 3) + (120 若通关)，再乘七印系数 = 1 + 0.3 × (印 − 1)。
- **六项永久强化**（每项 5 级，价格 = 起始价 + 递增 × 已买级数）：

| 强化 | 效果 / 级 | 起始价 | 递增 |
|---|---|---|---|
| 刚强 | 全伤害 +4% | 50 | 35 |
| 壮胆 | 生命上限 +12 | 45 | 30 |
| 快跑 | 移动速度 +3% | 40 | 30 |
| 恩典 | 拾取范围 +10% | 35 | 25 |
| 智慧 | 经验获取 +5% | 55 | 40 |
| 怜恤 | 领受回血 +3% | 60 | 45 |

- **七印**（难度阶梯，通关当前印才解锁下一印）：敌人生命 +9%/印、伤害 +6%/印、刷怪量 +4%/印（常量在 src/core/meta.gd 的 SEAL_HP/SEAL_DMG/SEAL_RATE；刷怪加成前 5 分钟线性渐入），舍客勒收益 ×(1 + 0.3×印差)。
- 存档 user://save.json（本机 = .godot_home/Library/Application Support/Godot/app_userdata/余民 The Remnant/save.json），记录舍客勒 / 六项等级 / 已解锁印 / 局数胜场 / 最佳击杀与存活。
- 加成经 GameState.setup(character_id, Meta.bonus()) 注入 recompute()，模拟层不直接依赖存档。

## 方差治理（P3.1）

目标是「别让开局抽卡决定生死」，四条改动都不加数值：

1. **武器保底** —— 只要池里还有武器可选，三选一至少有一张武器（新武器 / 强化）。
2. **祝圣的预备** —— 某件基础武器已差一级满级、且配材（圣灵的果子）在手，该强化必定出现在本次领受。
3. **配材之光** —— 抵达祭坛时若无可祝圣组合，祭坛赠予等级最高那件武器缺失的配材（受被动位上限约束）。
4. **重新求问** —— 领受面板按 R 重掷，每局 2 次。

治理后自动驾驶实测（`--sim --sim-speed=900 --no-meta`）：1 印 2/2 通关、4 印通关、7 印 2/3 通关（唯一败局 511s）。详细数据见 [docs/P3-营地与七印.md](docs/P3-营地与七印.md)。

## 试炼地图（P4）

两张地图共用一套规则，差异全部来自 `data/stages.json`：刷怪配比、精英时间表、BOSS、地面三色、`mods` 系数。

| 地图 | 经文 | 时长 / BOSS | 特点 | 解锁 |
|---|---|---|---|---|
| 以拉谷 `elah_valley` | 撒上 17 | 780s / 歌利亚 | 基准图：士兵、弓手、乌鸦、野兽、六指巨人；武器冷却 -10% | 默认 |
| 犹大旷野 `judea_wilderness` | 太 4 | 750s / 旷野的试探者 | 毒蝎为主（高速贴身）、敌人速度 ×1.12、舍客勒 ×1.25、石灰岩荒原 | 通关以拉谷 1 次 |

- 营地「试炼」行 ←→ 切换，`出发 → <地图名>` 进对应地图；未解锁的地图会提示「有未解锁」。
- 地图选择存进存档（`stage_id` 字段），下次进营地自动沿用。
- 命令行 `--stage=judea_wilderness` 可跳过营地直接进图。

详细数据见 [docs/P4-第二张地图.md](docs/P4-第二张地图.md)。
## 已完成（P1）

- 五类行为原子 + 数据驱动参数，祝圣武器与成全武器复用同一套原子，不新增代码路径。
- 祝圣链路：基础武器 Lv5 + 指定被动 + 祭坛 1 火炭 → 固定祝圣武器（消耗基础武器）。
- 双武合鸣链路：两件 Lv5 基础武器 → 单件传奇武器（空出一槽）。
- 成全链路：祝圣武器 Lv5 + 500 击杀 → 自动触发成全爆发（nova）。
- 五大状态与减速/灼烧/致盲结算；接触伤害按敌人独立冷却 + 玩家整体无敌帧。
- 领受三选一、祭坛面板、结算面板、完美闪避的守望者时刻。
- 无头模拟：同一套 run.gd 走 --sim 自动驾驶，可直接跑数值回归。

## 反馈与音效

音效全部由 `python3` 的 wave 模块程序化合成，存放在 assets/sfx/，零第三方版权：
命中 / 拾取 / 升级 / 受伤 / 祝圣 / 闪避 / BOSS 登场 / 阵亡。
`src/core/sfx.gd` 是一个 14 声道的播放池，同名音效有 35~300ms 冷却，高击杀频率下不会糊成噪音。

画面反馈：
- **屏幕震动**：受伤 4.5、祝圣 7、BOSS 登场 9、升级 2，按 26/s 衰减。
- **受伤红闪**（0.3 秒）+ **低血暗角**（HP < 35% 时四边脉动）+ **升级金闪**。
- **击杀爆点**：每 2 只敌人留一个 0.22 秒的金色扩散圈。
- 敌人受击白闪、灼烧变色、首领红冠。

## 节奏控制：敌人回收

类幸存者里玩家移动比大多数敌人快，追不上的敌人会永远滞留在屏幕外，既浪费 CPU 又让画面显得空。
`src/run.gd` 的 `_recycle_far()` 每 0.5 秒把距离超过 700px 的普通敌人重新投放到视野外圈（330~440px，BOSS 除外）。
加入前同屏存活在 2 分钟掉到 85（画面只剩 10 来只），加入后稳定在 300~400，屏幕上始终有 25~40 只。

## 数值基线（2026-11-17，来自 --sim 自动驾驶）

| 项目 | 数值 |
|---|---|
| 单局时长 / BOSS | 以拉谷 780 秒（歌利亚 690s 登场）· 犹大旷野 750 秒（试探者 660s 登场） |
| 刷怪 | 以拉谷 210/分钟起、每分钟 +70、同屏 620；犹大旷野 230/分钟起、每分钟 +66、同屏 560 |
| 升级回复 | 每次领受回复 15% 生命上限 |
| 敌人接触伤害 | 军兵 3 · 弓手 4 · 乌鸦 3 · 旷野毒蝎 3 · 野兽 6 · 六指巨人 7 · 歌利亚 14 · 试探者 16（0.6 秒冷却，单次上限 10） |
| 敌人 | 军兵 9HP/58速 · 弓手 8HP/52速 · 乌鸦 6HP/100速 · 毒蝎 12HP/86速 · 野兽 24HP/66速 · 六指巨人 110HP · 歌利亚 7000HP · 试探者 8200HP |

四位见证人的模拟结果（`--sim --sim-speed=900`，未开无敌，同一套自动驾驶）：

| 见证人 | 结果 | 用时 | 等级 | 击杀 | 起始武器 |
|---|---|---|---|---|---|
| 大卫 | 通关 | 780s | 42 | 7182 | 投石索 |
| 摩西 | 通关 | 780s | 42 | 8548 | 牧杖 |
| 基甸 | 通关 | 780s | 43 | 6021 | 火把 |
| 约书亚 | 通关 | 780s | 43 | 7972 | 号角 |

自动驾驶只会直线逃跑、不会绕圈引怪，真人手感应当比这更宽松；方差主要来自「早期有没有拿到 AOE 武器」。
地图回归（同一套自动驾驶，`--no-meta`）：

| 地图 · 印 | 结果 | 数据 |
|---|---|---|
| 以拉谷 · 1 | 2/2 通关 | 780s，41–49 级，约 8600 杀 |
| 以拉谷 · 7 | 2/3 通关 | 唯一败局 511s |
| 犹大旷野 · 1 | 通关 | 750s，46 级 / 8969 杀，舍客勒 4003 |
| 犹大旷野 · 4 | 3/3 通关 | 750s，44–45 级，剩余 64–140 HP |
| 犹大旷野 · 7 | 通关 | 750s，46 级 / 9725 杀，满血 |

7 印是以拉谷的挑战层：加入地图修饰后再测 4 次 0 通关（164s / 392s / 635s 阵亡），方差极大——第 24 级前后能不能拿到第一件 AOE 武器基本决定生死。这与「七印 = 极限挑战」的定位一致，但还缺真人校准。

## 已知待办

- 两张地图目前只差「配色 + 敌人配比 + 一两个系数」，还没有地图专属机制（如旷野的风暴、以拉谷的河床）。
- 旷野的试探者沿用通用 boss 行为，尚未有自己的技能组。
- 见证人全是解锁状态，没有「以通关解锁新见证人」的内容型成长；红海、摩利亚山两张图待做。
- 只有程序化音效，没有配乐；美术仍是程序化绘制占位。
- 数值基线由无头模拟给出，仍缺真人手感校准。
