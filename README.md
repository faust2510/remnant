# 余民 The Remnant

圣经启示录题材的类幸存者（Survivor-like）动作游戏。Godot 4.7 / GDScript / 像素风。

当前版本：**v2.0 编年史** —— 按 [圣典 v2.0](docs/设计圣典-v0.6.md) 重做的完整数据层与局内系统：**24 章编年史**（一章一机关一 BOSS）· **20 位见证人** · **20 件基础武器 + 26 条祝圣/合鸣** · 20 件被动（果子 / 宝物）· **12 圣物** · **16 约** · **40 成就** · 会幕局外建筑 6 栋 · **21 阶灾变**（七印 1–7 / 七号 8–14 / 七碗 15–21）。整体仍保持「标题 → 营地 → 单局」的骨架与可复现的无头模拟。

> 数据全部在 `data/*.json`，代码只做解释；`elah_valley` 与 `judea_wilderness` 两个旧 id 原样保留，老存档可直接读。

## 桌面启动（双击即玩）

`dist/余民.app` 是一个 macOS 启动器：双击就会用 `/Applications/Godot.app` 打开本项目，`Info.plist` 里配了名字「余民 The Remnant」和自绘图标（金十字 + 火炭，`tools/` 之外由 PIL 生成）。

```
dist/余民.app/Contents/MacOS/run   ← 启动脚本（PROJ / GODOT 两个路径写死，搬家要改）
dist/余民.app/Contents/Info.plist   ← 显示名、图标、版本
dist/余民.app/Contents/Resources/icon.icns
安装到桌面.command                  ← 双击把 dist/余民.app 拷到桌面（macOS 授权一次即可）
```

- **放到桌面**：双击项目根目录的 `安装到桌面.command`；系统第一次会问「终端想访问桌面」，允许即可。也可以直接把 `dist/余民.app` 拖到桌面。
- **看日志**：启动器会把 Godot 的输出写到 `/tmp/remnant-launch.log`。打不开时先看它——最常见的原因是 `Godot.app` 被移动或项目目录改名，此时启动器会弹窗说明。
- **加进 Dock**：先放到桌面并双击打开一次，再右键 Dock 上的图标 → 选项 → 在 Dock 中保留。
- **换参数启动**：`open dist/余民.app --args --char=moses`（参数会原样传给 Godot）。
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

# 指定随机种子（默认 20261116；换种子等于换一整局的抽卡与刷怪序列）
HOME="$PWD/.godot_home" /Applications/Godot.app/Contents/MacOS/Godot --headless -- --sim --sim-speed=900 --seed=3302

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

## v2.0 一览

| 内容 | 数量 | 文件 |
|---|---|---|
| 章节（一章一机关、一章一 BOSS） | 24 | `data/stages.json` |
| 普通敌人 / 精英 | 24 + 12 | `data/enemies.json` |
| 关底 BOSS（三阶段、8 种技能） | 24 | `data/bosses.json` + `src/sim/boss_ai.gd` |
| 基础武器 | 20 | `data/weapons.json` |
| 祝圣 / 双武合鸣 | 20 + 6 | `data/fusions.json` |
| 被动（圣灵果子 15 / 宝物 5） | 20 | `data/passives.json` |
| 见证人（各带起始武器 + perk + 3 印觉醒） | 20 | `data/characters.json` |
| 圣物 | 12 | `data/relics.json` |
| 约（局内抽卡） | 16 | `data/covenants.json` |
| 成就 | 40 | `data/achievements.json` |
| 会幕建筑 / 强化项 / 灾变阶 | 6 / 9 / 21 | `data/store.json` |

### 24 章编年史

| 章 | 名称 | BOSS | 地图机关 | id |
|---|---|---|---|---|
| 1 | 伊甸与东门 | 火焰剑基路伯幻象 | eden_fall | ch01_eden |
| 2 | 大洪水与方舟 | 深渊大水利维坦 | flood_tide | ch02_flood |
| 3 | 巴别高塔之下 | 宁录通天塔巨像 | babel_confusion | ch03_babel |
| 4 | 摩利亚与雅各坛 | 毗努伊勒摔跤天使影 | altar_charge | ch04_moriah |
| 5 | 埃及十灾荒野 | 长子灭命黑影 | plague_cycle | ch05_plagues |
| 6 | 红海海底走廊 | 法老铁车战灵 | sea_walls | ch06_red_sea |
| 7 | 西乃雷轰山麓 | 熔金牛犊巨兽 | lightning_zones | ch07_sinai |
| 8 | 苦水与铜蛇旷野 | 旷野火蛇之王 | bitter_water | ch08_wilderness_serpent |
| 9 | 耶利哥外城环道 | 耶利哥坚固营垒铁卫 | wall_ring | ch09_jericho |
| 10 | 基甸深夜营盘 | 米甸双王（俄立与西伊伯） | darkness_lamp | ch10_gideon_camp |
| 11 | 亭拿麦田与利希 | 大衮神庙巨柱统领 | burnable_field | ch11_timnah |
| 12 | 亚杜兰洞掩体 | 扫罗幽暗追兵统领 | cave_choke | ch12_adullam |
| 13 | 以拉谷 | 歌利亚 | dry_creek | elah_valley |
| 14 | 迦密山祭坛巅 | 巴力伪坛四柱巨像 | drought_fire | ch14_carmel |
| 15 | 尼尼微与鱼腹 | 深渊大鱼幻影 | belly_shade | ch15_nineveh |
| 16 | 巴比伦火窑狮坑 | 尼布甲尼撒四段金像 | furnace_rings | ch16_babylon_furnace |
| 17 | 犹大旷野 | 旷野的试探者 | temptation_choice | judea_wilderness |
| 18 | 加利利狂风海 | 格拉森群鬼聚合体 | storm_push | ch18_galilee |
| 19 | 耶路撒冷五旬节 | 律法铁轭巨像 | pentecost_rush | ch19_pentecost |
| 20 | 腓立比地牢震动 | 铁链狱卒统领 | prison_quake | ch20_philippi |
| 21 | 七教会金灯台 | 失落灯台黑影 | seven_lamps | ch21_seven_churches |
| 22 | 无底坑与蝗虫海 | 无底坑王亚巴顿 | abyss_vents | ch22_abyss |
| 23 | 大巴比伦与白马 | 巴比伦朱红兽幻象 | meteor_horde | ch23_babylon_fall |
| 24 | 哈米吉多顿玻璃海 | 海中七头十角兽 | glass_sea | ch24_armageddon |

主线仍是「撑到 BOSS、把它打倒才算通关」：BOSS 一旦登场，计时结束不再判定胜利；撑满时长后还有 150 秒宽限，打不动就判负（避免旧版「白拿通关」）。

### 门禁（每次改动都跑这五条，全部 headless）

```bash
export HOME="$PWD/.godot_home"; G=/Applications/Godot.app/Contents/MacOS/Godot
"$G" --headless --path . --import                       # 导入 / 解析检查：0 SCRIPT ERROR
"$G" --headless --path . --quit-after 120               # 冒烟：跑 120 帧退出
"$G" --headless --path . -- --camp-selftest            # 营地：rows / stages / 购买 / 导航
"$G" --headless --path . -- --title-selftest           # 标题：witnesses=20 unlocked=1
"$G" --headless --path . res://scenes/codex.tscn -- --codex-selftest   # 图鉴：relics=12 achievements=40
```

平衡回归用 24 章横扫（约 20 分钟，后台跑）：`for id in 24 个 stage id; do --sim --sim-speed=900 --no-meta --seal=1 --stage=$id; done`，判定看 `[sim] victory=` 与 `[sim] boss_killed`。

数据契约、施工路线与实装细节：[docs/V2-数据契约.md](docs/V2-数据契约.md) · [docs/V2-施工路线.md](docs/V2-施工路线.md) · [docs/V2-实装报告.md](docs/V2-实装报告.md)
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

标题页：方向键 / WASD / 鼠标在 20 位见证人里选（2×3 滚动），Enter 进入营地，Esc 退出。
营地：↑↓ 选行，Enter 购买 / 出发，←→ 在「灾变阶」行调阶、在「试炼」行切章节，Tab / 1 / 2 切「强化 ↔ 会幕」页签，V 打开图鉴，Esc 回标题。
图鉴：←→ / Tab 切三页签（圣物 12 / 成就 40 / 见证人 20），↑↓ 滚动，PageUp / PageDown 翻页，Esc 返回。

## 目录

```
project.godot          引擎配置（autoload GameData / RunCfg / Meta；主场景 = 标题页）
scenes/title.tscn      标题与见证人选择（20 位 2×3 滚动）
src/title_screen.gd    标题页绘制与输入（键盘 / 鼠标）+ --title-selftest
scenes/camp.tscn       营地（局外成长）
src/camp_screen.gd     营地：强化页签 / 会幕页签 / 试炼地图 / 出发；--camp-selftest
src/ui/codex_screen.gd 图鉴三页签（12 圣物 / 40 成就 / 20 见证人）；--codex-selftest
src/ui/ui_text.gd      字体与文本折行工具
src/core/meta.gd       局外存档：舍客勒、强化、会幕、圣物、成就、灾变阶、生涯统计（user://save.json）
src/core/run_cfg.gd    跨场景传参：选中的见证人 / 地图 / 灾变阶
data/                  纯数据：武器 / 被动 / 祝圣 / 敌人 / BOSS / 见证人 / 地图 / 圣物 / 约 / 成就 / 会幕
src/core/game_data.gd  载入全部 JSON 并建索引（weapons/fusions/... /bosses/relics/covenants/achievements/store）
src/core/game_state.gd 构筑状态：槽位、属性、经验、祝圣、成全、军装、圣物、觉醒
src/core/game_font.gd  取系统 CJK 字体
src/core/sfx.gd        音效池（14 个 AudioStreamPlayer，同名冷却）
assets/sfx/*.wav       8 个程序化合成音效（无第三方版权）
src/systems/mechanics.gd   24 章地图机关（一章一个 mechanic_id）
src/systems/covenants.gd   约卡抽取与条款结算（16 条约）
src/systems/rewards.gd     宝箱三档 / 9 种奇物 / 宝石合并
src/systems/achievements.gd 40 成就的 9 种 cond 判定
src/systems/stat_patch.gd  阶段属性补丁
src/sim/spatial_grid.gd  静态链表空间哈希（零分配）
src/sim/enemy_sim.gd   敌人 SoA 模拟（行为 / 状态 / 精英词条 / 危害区 / 图腾 / 分裂）
src/sim/projectile_sim.gd  弹幕模拟（玩家与敌人共用；含折返弹）
src/sim/boss_ai.gd     BOSS 三阶段 AI（8 种技能 / 回血上限 / 召唤）
src/combat/weapon_runner.gd  五类行为原子：直线弹 / 扇形近战 / 环绕 / 区域 / 追踪 + 六种 modifier
src/render/world_renderer.gd 单节点批量绘制（地面 / 敌人 / 弹幕 / 宝石 / 机关层 / 特效）
src/ui/hud.gd          HUD 与结算（BOSS 名 / 约卡 / 机制提示 / 圣物图标 / 军装行）
src/ui/chooser.gd      领受 / 祭坛 / 约卡三选一面板
src/run.gd             单局流程：刷怪、掉落、祭坛、BOSS、面板调度、地图修饰、机关、约卡
scenes/main.tscn       单局场景（只有一个挂 run.gd 的 Node2D）
```

## 营地与局外成长（P2）

流程：标题（选见证人）→ **营地** → 以拉谷。结算后按 R 回营地。

- **舍客勒**：舍客勒 = int(存活秒 / 8) + int(击杀 / 3) + (120 若通关)，再乘七印系数 = 1 + 0.3 × (印 − 1)（系数按**本局实际所选的印**算，不是存档里那一印）。
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
3. **配材之光** —— 抵达祭坛时若无可祝圣组合，祭坛赠予等级最高那件武器缺失的配材（限 Lv3+ 武器、受被动位上限约束）。
4. **重新求问** —— 领受面板按 R 重掷，每局 2 次。

治理后自动驾驶实测见下文「数值基线」。完整数据见 [docs/P3-营地与七印.md](docs/P3-营地与七印.md)。

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
- **祝圣三层结构（P5 补完）**：
  1. **祝圣**（合成）：基础武器 Lv5 + 指定圣灵果子 + 1 颗火炭 → 固定祝圣武器，各自带一种真实机制（见下表）。
  2. **成全**：祝圣武器 Lv5 + **成圣之后**累计 500 击杀 → 永久改造：伤害 ×1.25、弹数 +1、范围 ×1.12、冷却 ×0.82（环绕武器另加一圈轨道），并放一次成全 nova。
  3. **双武合鸣**：两件 Lv5 基础武器 → 单件传奇武器（占 1 槽），与单武祝圣构成真实取舍。
- 五大状态与减速/灼烧/致盲结算；接触伤害按敌人独立冷却 + 玩家整体无敌帧。
- 领受三选一、祭坛面板、结算面板、完美闪避的守望者时刻。
- 无头模拟：同一套 run.gd 走 --sim 自动驾驶，可直接跑数值回归。

## 祝圣武器：六种 modifier 全部生效（P5）

此前只有投石索那条线真的读了 `modifier`，其余五把祝圣后只是数值变大。现在六种机制都落在 `src/combat/weapon_runner.gd` 的具体结算点上：

| 祝圣武器 | 配方 | modifier | 实际机制 |
|---|---|---|---|
| 歌利亚的丧钟 | 投石索 + 良善 | `shockwave_on_hit` | 命中点 34×area 半径溅射，45% 伤害 |
| 摩西分海杖 | 牧杖 + 忍耐 | `tidal_push` | 击退 ×1.6（把怪推成一条缝） |
| 耶利哥的号角 | 号角 + 节制 | `wall_push` | 击退 ×1.9（整面推走） |
| 燃烧的荆棘 | 火把 + 信实 | `trail_fire` | 每次环绕结算在轨道落 1.1 秒燃烧区（半径 22×area） |
| 金香坛 | 香炉 + 和平 | `holy_smoke` | 区域持续治疗 0.7 HP/s |
| 锡安的诗篇 | 大卫的琴 + 喜乐 | `echo_blade` | 主弹后 0.22 秒复奏一轮 55% 伤害齐射 |

成全后的武器在 HUD 里显示 ★，成全瞬间浮字显示 `evolves_to.name`（如「成全 · 五块光滑石子」）。

## 全副军装：精英掉落（P5）

9 颗圣灵果子 + 6 件全副军装原本混在同一个升级池里，4 个被动槽被军装占掉后，祝圣配方就永远凑不齐。现在：
- 军装**不进升级池、不占被动槽**，改由击杀精英（六指巨人等）自动掉落并穿戴，附带金色 nova、浮字与音效。
- 军装属性照常计入 `recompute()`，HUD 右下角多一行金色小字显示已获军装。
- 一局最多 6 件，先到先得；同一件不会重复掉。

## 确定性模拟（P5）

为了能真的用无头模拟做数值回归，随机源已经收口：
- `EnemySim` 与 `WeaponRunner` 各自持有 `rng: RandomNumberGenerator`，由 `src/run.gd` 的主 rng 播种；`EnemySim` 用 `sim_time` 累加替代 `Time.get_ticks_msec()`（后者在 900 倍速下几乎不走，导致乌鸦摆动与真实游玩不一致）。
- 同一条命令跑两次，结果逐位相同（实测 7 印三次都是 `215.4s / 27 级 / 1338 杀`）。
- 需要换样本时用 `--seed=N`；`--seed` 不改代码路径，只换序列。
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

## 数值基线（v2.0，来自 --sim 自动驾驶）

| 项目 | 数值 |
|---|---|
| BOSS 血量 | 按章定标 `target_hp = 9000 + 1250 × (章 − 1)`：ch01 9000 · ch13 24000 · ch24 37750。**不吃时间成长、不吃印的血量系数** |
| 普通 / 精英敌人 HP | 基础值 × 时间成长 `1 + (t/60)^0.85 × 0.175` × 阶的血量系数（前 3 分钟按 25%→100% 渐入） |
| 刷怪 | 每章在 `data/stages.json` 的 `budget` 里：以拉谷 210/分钟起、+76/分钟、同屏 620；犹大旷野 230/+70/560；后期章 250~280 起 |
| 玩家受击 | 无敌帧 0.65s；单次接触上限 16、单发弹幕上限 18（机关 DoT 绕开无敌帧） |
| 升级回复 | 每次领受回复 15% 生命上限 |
| 接触伤害（抽样） | 军兵 3 · 弓手 4 · 乌鸦 3 · 毒蝎 3 · 野兽 6 · 六指巨人 7 · 歌利亚 14 · 试探者 16 |
| 敌人速度（抽样） | 军兵 58 · 弓手 52 · 乌鸦 100 · 毒蝎 86 · 野兽 66 · 六指巨人 64 · BOSS 44/52 |
| 成就 / 圣物 / 约 | 40 / 12 / 16，全部进局外存档 |

21 阶灾变（`data/store.json` 的 `tier_curve`；8–21 阶需要圣物 `seven_seals_scroll` 解锁）：

| 阶 | 名称 | 敌 HP | 敌伤 | 刷怪 | 银两 |
|---|---|---|---|---|---|
| 1 | 一印 · 白马 | ×1.00 | ×1.00 | ×1.00 | ×1.00 |
| 7 | 七印 · 寂静 | ×1.54 | ×1.36 | ×1.24 | ×2.80 |
| 14 | 七号 · 终响 | ×2.26 | ×1.78 | ×1.52 | ×3.05 |
| 21 | 二十一 · 成了 | ×2.80 | ×2.20 | ×1.80 | ×3.20 |

### 24 章横扫（`--sim --sim-speed=900 --no-meta --seal=1`，默认种子 20261116）

**23 / 24 通关**：唯一失败的是终章 ch24（默认种子下 602s 阵亡，构筑没成型）。同章换种子 3301–3304 则 3/4 通关（704.4s / 692.2s / 724.6s 阵亡 / 703.3s），说明是构筑方差而不是硬墙。

| 章 | id | 通关时刻 | 等级 | 击杀 | 剩余 HP |
|---|---|---|---|---|---|
| 1 | ch01_eden | 672.9s | 36 | 5343 | 153/154 |
| 2 | ch02_flood | 691.9s | 40 | 6141 | 108/154 |
| 3 | ch03_babel | 667.4s | 40 | 5911 | 151/154 |
| 4 | ch04_moriah | 678.1s | 44 | 6312 | 117/154 |
| 5 | ch05_plagues | 672.6s | 38 | 6355 | 154/154 |
| 6 | ch06_red_sea | 669.1s | 42 | 6386 | 116/154 |
| 7 | ch07_sinai | 686.6s | 47 | 6774 | 154/154 |
| 8 | ch08_wilderness_serpent | 677.3s | 43 | 6696 | 151/154 |
| 9 | ch09_jericho | 705.8s | 44 | 7297 | 154/154 |
| 10 | ch10_gideon_camp | 699.5s | 42 | 7241 | 154/154 |
| 11 | ch11_timnah | 702.3s | 50 | 7416 | 154/154 |
| 12 | ch12_adullam | 674.4s | 44 | 7021 | 154/154 |
| 13 | elah_valley | 770.7s | 43 | 8805 | 53/154 |
| 14 | ch14_carmel | 675.8s | 40 | 7174 | 154/154 |
| 15 | ch15_nineveh | 685.7s | 47 | 7417 | 119/154 |
| 16 | ch16_babylon_furnace | 692.4s | 45 | 7626 | 127/154 |
| 17 | judea_wilderness | 688.8s | 42 | 7139 | 152/154 |
| 18 | ch18_galilee | 709.6s | 43 | 8060 | 87/154 |
| 19 | ch19_pentecost | 696.2s | 44 | 7965 | 128/154 |
| 20 | ch20_philippi | 692.0s | 54 | 7807 | 143/154 |
| 21 | ch21_seven_churches | 707.9s | 48 | 8375 | 63/154 |
| 22 | ch22_abyss | 682.8s | 49 | 8963 | 154/154 |
| 23 | ch23_babylon_fall | 717.9s | 54 | 9114 | 154/154 |
| 24 | ch24_armageddon | **阵亡 602.2s** | 50 | 7080 | 0/140 |

> BOSS 击杀时刻晚于 `boss_at` 是正常的（BOSS 719~761 秒才倒下）；「通关时刻」= `[sim] victory=true` 那一行的时间。

### 20 位见证人（以拉谷 · 1 印 · 默认种子）

**19 / 20 通关**。唯一阵亡的是以利亚（749.6s，倒在与歌利亚的收尾阶段）；他靠灼烧叠层（上限 5→11）吃饭，自动驾驶不会刻意把敌人烧满，属于测量口径偏差，不算数值问题。

| 见证人 | 起始武器 | 通关时刻 | 等级 | 击杀 | 剩余 HP |
|---|---|---|---|---|---|
| 大卫 david | 投石索 | 770.7s | 43 | 8805 | 53/154 |
| 挪亚 noah | 橄榄枝 | 794.9s | 45 | 9080 | 246/246 |
| 亚伯拉罕 abraham | 香炉 | 705.5s | 40 | 7587 | 135/135 |
| 雅各 jacob | 牧杖 | 715.2s | 44 | 7788 | 145/164 |
| 米利暗 miriam | 铃鼓 | 733.9s | 44 | 7678 | 139/139 |
| 摩西 moses | 牧杖 | 715.5s | 42 | 7797 | 134/138 |
| 约书亚 joshua | 号角 | 720.9s | 43 | 7912 | 125/140 |
| 基甸 gideon | 火把 | 748.8s | 47 | 8409 | 57/140 |
| 参孙 samson | 驴腮骨 | 711.9s | 45 | 7732 | 140/174 |
| 底波拉 deborah | 火把 | 724.1s | 47 | 7940 | 132/144 |
| 路得 ruth | 镰刀 | 711.0s | 41 | 7735 | 140/142 |
| 以利亚 elijah | 火把 | **阵亡 749.6s** | 44 | 8447 | 0/146 |
| 以利沙 elisha | 火战车 | 728.1s | 45 | 8025 | 150/150 |
| 尼希米 nehemiah | 泥刀 | 756.1s | 47 | 8574 | 169/169 |
| 以斯帖 esther | 香炉 | 708.3s | 41 | 7661 | 138/138 |
| 但以理 daniel | 香炉 | 700.3s | 39 | 7515 | 148/148 |
| 施洗约翰 john_baptist | 旷野呼声 | 703.8s | 39 | 7597 | 144/144 |
| 彼得 peter | 渔网 | 708.9s | 48 | 7697 | 159/159 |
| 保罗 paul | 圣言利剑 | 719.9s | 40 | 7899 | 150/150 |
| 拔摩岛约翰 john_patmos | 天国钥匙 | 722.9s | 44 | 7899 | 142/142 |

> 余下 HP 差距很大（53 ~ 246）反映的是构筑方差，不是强度排序：自动驾驶只看「离怪最远 + 顺路吃经验」，不会用角色的独有机制（以利亚灼烧、但以理祷告圈、以利沙复活）。

## 已知待办

- **ch24 终章依赖构筑成型**：默认种子 602s 阵亡（23/24），换种子 3/4 通关。它是全篇最后一章，暂时保留这个难度，但需要真人确认是不是「打不动」而不是「抽得差」。
- **以利亚在自动驾驶下打不完以拉谷**（749.6s 阵亡，19/20）：他的灼烧叠层上限 5→11 是真实生效的，但「叠满 10 层降天火」只写在描述里、尚未实现，且自动驾驶不会主动叠层。
- **8–21 阶未端到端验证**：需要用圣物 `seven_seals_scroll`（七印书卷）解锁，该圣物在 24 章通关后掉落，目前只验证了 1–7 阶。
- `iframe`（无敌帧配置项）与 `false_idol`（禁武器）两条接口需求仍未接线；hazards 的渲染层只做了描边，与 combat 的数据结构还没完全对齐。
- **24 个地图机关深度不齐**：全部有实现，但只有 6 个带独立状态机，其余是「定时危险区 / 缩圈 / 场地元素」的变体。
- 会幕 6 建筑 + 9 项强化合计 6275 舍客勒，经济曲线未校准；40 条成就里只有 10 条在模拟中被触发过。
- `gems` 仍是 `Array[Dictionary]`，未做「10 合 1」合并；`step()` 也还没抽成纯 `RefCounted` 的 RunSim（当前 900 倍速单线程够用）。
- 只有程序化音效，没有配乐；美术仍是程序化绘制占位。
- 数值基线全部由无头自动驾驶给出（自动驾驶不会绕圈引怪、不会贴墙走位），仍缺真人手感校准。

历史评审与修复记录：[docs/P5-评审修复.md](docs/P5-评审修复.md) · [docs/P3-营地与七印.md](docs/P3-营地与七印.md) · v2.0 的实装细节 [docs/V2-实装报告.md](docs/V2-实装报告.md)。
