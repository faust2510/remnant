# V2 UI / 图鉴 / 营地 实现说明

> 归属：UI / 图鉴 / 营地负责人。写作用域：`src/ui/`、`src/camp_screen.gd`、`src/title_screen.gd`、`scenes/*.tscn`、`src/render/world_renderer.gd`、本文件。
> 视口固定 640×360，全部界面用 `_draw()` 程序化绘制（系统中文字体 GameFont），不引入美术资源。

## 1. 文件清单

| 文件 | 作用 |
| --- | --- |
| `src/title_screen.gd` | 标题页 + 20 位见证人卡片（2×3 滚动窗口）、图鉴入口 |
| `src/camp_screen.gd` | 营地：强化 / 会幕 两页签 + 常驻试炼行与出发行 + 灾变阶面板 |
| `src/ui/codex_screen.gd` | 图鉴：圣物 12 / 成就 40 / 见证人 20，左列表右详情 |
| `src/ui/ui_text.gd` | 纯函数文案层：角色解锁判定、perk 文案、成就条件/奖励文案、章节名 |
| `src/ui/hud.gd` | 局内 HUD：BOSS 名、约卡牌、机制行、圣物图标、结算成就与银两明细 |
| `src/render/world_renderer.gd` | 世界渲染：机关可视化（冷却带/雷击圈/陨星/城墙/玻璃海）、敌人按 behavior 分型 |
| `scenes/codex.tscn` | 图鉴独立场景（`--codex-selftest` 用） |

## 2. 页面与导航

```
title.tscn ──Enter 整备出发──> camp.tscn ──出发──> main.tscn（单局）
   │  V                            │  V / 第 3 页签         │ 结算
   └────────────> codex.tscn <─────┘                        │
                      │ Esc/V 返回来源                      │
                      └────────────────────────────────────┘
```

- 图鉴返回地址用 `CodexScreen.back_scene` 静态变量传递（`RunCfg` 只有 character_id / stage_id / skip_title 三个字段）。
- 单局结算 `Esc` 再来一局、`R` 回营地（原有逻辑保留）。

## 3. 标题页 / 见证人选择

布局：标题区 0–100，卡片区 `Y0=120`，2 列 × 3 行可见窗口，每卡 276×58，横向间距 16、纵向 8。

- 20 位见证人来自 `data/characters.json`，卡片内容：名字（觉醒者带 ★）/ 经文 / 起始武器 / 首条 perk 文案。
- 未解锁：整卡灰化（alpha 0.45），名字前置「锁」，显示 `UIText.character_unlock_text()` 的条件；Enter 会被拦截并播放失败音 + 顶部提示，不会进入营地。
- 解锁判定 `UIText.character_unlocked()` 优先级：`Meta.is_character_unlocked()`（若存在）→ `unlock.note` 中的 `ach_*` 成就 → `unlock.stage` 对应章节首通成就 → `Meta.wins >= 该章 unlock_wins` → note 含「默认」直接解锁。
- 顶部显示「见证人 · 已解锁 n/20」与「第 x/y 页」；`window_start` 偶数对齐并随选中项滚动。

| 按键 | 行为 |
| --- | --- |
| ← / → 或 A / D | 选中 ±1 |
| ↑ / ↓ 或 W / S | 选中 ±2（行） |
| PgUp / PgDn | 选中 ±6（翻页） |
| Home / End | 首位 / 末位 |
| Enter / KP_Enter / Space | 已解锁则进入营地；未解锁则提示条件 |
| V | 打开图鉴（back_scene = title） |
| Esc | 退出游戏 |
| 鼠标 | 左键点卡选人；滚轮翻页 |

`_go(i, direct)` 把 `RunCfg.character_id` 设为所选 id；`--sim / --shot / --char=*` 直连单局（`direct=true`），其余经营地。

## 4. 营地

布局：页签条 `y=52`（每个 88×22）；左栏 6 行 `ROW_X=28, ROW_W=344, ROW_H=25, ROW_STEP=27, ROW_Y0=80`；试炼行 `(28,244,344,30)`；出发行 `(28,278,344,26)`；右栏灾变阶面板 `(384,54,228,100)`、详情面板 `(384,160,228,140)`；生涯两行 `y=314/328`；底部提示 `y=350`。

### 4.1 页签

| 页签 | 内容 |
| --- | --- |
| 强化（默认） | `Meta.UPGRADES` 6 项：名称、说明、等级点 ×5、价格；满级显示「已满」，买不起价格转暗红 |
| 会幕 | `GameData.store_buildings()` 6 座建筑：名称、说明、右侧 `Lv n · 价格` 或状态、第二行小字解锁条件 |
| 图鉴 | 打开 `scenes/codex.tscn`（back_scene = camp） |

建筑状态由 `_building_status()` 统一计算：

- `ok=true`：`Meta.building_next()` 非空且 `Meta.building_cost()` 付得起 → Enter 调 `Meta.buy_building()`（内部 `buy()` + `_sync_buildings()` + 存档）。
- `pending=true`：建筑登记的所有强化都未实装（`faith / prayer / sanctuary`，`store.upgrades.live=false`）→ 显示「待实装」，不拦截为满级。
- `maxed`：所有登记强化都满级 → 显示「已满级」。
- 未开放：`unlocks` 文本解析「累计 N 局 / 通关 N 印 / 初始」与 `Meta.runs`、`max(Meta.seals, Meta.effective_tier())` 比较。

### 4.2 试炼（24 章）

- 章节来自 `data/stages.json`（数组顺序 = 第 1–24 章），显示「试炼 · 第 N 章《名称》」+ 经文 + 首通奖励（`UIText.stage_achievement()` → `achievement_reward_text()`，已领取加「已领取」前缀）。
- ← → 在**全部 24 章**之间循环；锁定章节只提示「需得胜 N 次（当前 M）」并播放失败音，不写存档；已解锁才写 `Meta.stage_id` 并 `save_save()`。
- 解锁口径：`Meta.wins >= stages[i].unlock_wins`；`elah_valley=0`、`judea_wilderness=1` 保持初始可达。
- Enter 在试炼行直接出发（锁定章节会提示并拦下）；下方另有常驻出发行，作用相同。
- 出发前校验所选角色解锁状态，未解锁回退 `david`；写入 `Meta.stage_id / RunCfg.stage_id / RunCfg.character_id` 后进 `main.tscn`。

### 4.3 灾变阶（21 阶）

右栏显示 21 个刻度，可用性按 `Meta.max_tier_allowed()`（持 `seven_seals_scroll` 或 `R11` 开放 8–21），当前值 `Meta.effective_tier()`。← → 在非试炼行调整，`Meta.set_tier(clamp(1..max))` 后立即存档；面板显示 `Meta.tier_name()`、`tier_enemy_hp/dmg/spawn_rate`、`silver_mult`。

| 按键 | 行为 |
| --- | --- |
| ↑ / ↓ 或 W / S | 8 行环走（6 强化/建筑 + 试炼 + 出发） |
| ← / → 或 A / D | 试炼行切章节；其它行调灾变阶 |
| Tab | 强化 ↔ 会幕 切页 |
| 1 / 2 | 直接选页 |
| 3 或 V | 打开图鉴 |
| Enter / KP_Enter / Space | 购买 / 试炼行提示 / 出发 |
| Esc | 返回标题页 |
| 鼠标 | 点页签、点行购买、点试炼左右箭头切章、滚轮在试炼行切章 |

自检：`scenes/camp.tscn -- --camp-selftest` 打印强化购买、bonus、灾变阶、6 建筑状态、rows/stages/unlocked、8 次下键回环、page1、24 次章节循环。可选 `--camp-page=0|1`、`--camp-stage=<id>`。

## 5. 图鉴（scenes/codex.tscn）

三页签（`y=52`，每页 92×22）：圣物 / 成就 / 见证人。左列表 `(28,80,300,236)` 每行 22px、可见 10 行；右详情 `(336,80,276,236)`。

| 页签 | 数据 | 列表行 | 右详情 |
| --- | --- | --- | --- |
| 圣物 | `GameData.relics`（12） | ✓/锁 + 名称 + 效果短句 | 名称、经文、解锁条件、效果、说明、slug |
| 成就 | `GameData.achievements`（40） | ✓/空框 + 名称 + 奖励 | 名称、说明、条件文案、奖励（银两/圣物）、note |
| 见证人 | `GameData.characters`（20） | 头像框首字 + 名称 + HP | 名字、经文、起始武器、perk 全列、觉醒、解锁条件/状态 |

- 未解锁行整体暗色 + 锁形方框；已解锁成就有 ✓。
- 数据全部实时读 `data/*.json` 与 `Meta`，不写死数量；表为空时显示「暂无数据」空态。
- 返回按 `CodexScreen.back_scene`；键 `V` 或 `Esc`。

| 按键 | 行为 |
| --- | --- |
| 1 / 2 / 3 或 Tab / A / D | 切页签 |
| ↑ / ↓ | 列表逐行 |
| PgUp / PgDn | 翻 10 行 |
| Home / End | 首 / 末 |
| Esc / V | 返回来源页 |
| 鼠标 | 点页签、点行、滚轮滚动 |

自检：`Godot --headless --path . scenes/codex.tscn -- --codex-selftest`，打印三页签数量/解锁数/首条/back。

## 6. HUD 扩展（src/ui/hud.gd）

| 元素 | 位置 | 数据源与降级 |
| --- | --- | --- |
| BOSS 名 | 血条 `(160,12,320,8)` 下方 `(160,34)` | `type_ids[typ[boss_index]]` → `GameData.enemies` → `GameData.boss_def()` → 「首领」 |
| 约卡牌 | 左上 `y=56` 起每 18px | `run.covenants.draw_data()` 的 `{name,color,rarity}`；无则读数组/字典；再缺则整行不画 |
| 机制状态行 | `y≈76` | `run.mechanics.hint()` + `_hazard_short()`（雷击数/危险区数/城墙已塌）；字段缺失跳过 |
| 圣物图标 | 左下 `y=314`，每 11px | `state.relic_defs()` → `run.relics` → `run.relic_ids`；空则不画 |
| 结算成就 | `y=220` 起 | `run.achievements.newly`（`{id,name,reward}`）→ 旧字段回退；无则「本局无新增成就」 |
| 银两明细 | `y=182/194/204` | 复算 `int(秒/8)+int(击杀/3)+120`、`Meta.seal_mult(seal)`、`run.stage_coin`、`run.reward`、`run.rewards.silver_run` |

结算版式：标题 106、战绩 136、祝圣/七印/圣物 154、明细 182/194、合计 204、成就 220 起（最多 3 条）、圣物解锁 262、按键提示 306。

## 7. 世界渲染（src/render/world_renderer.gd）

绘制顺序：地面 → 祭坛 → 宝石 → 武器区 → **机制层** → 敌人 → 弹幕 → 特效 → **机关命中闪光** → 玩家。

### 7.1 机制层

优先消费系统侧 `RunMechanics.draw_data()`（正式接口），逐条按 `kind` 绘制；无 `draw_data()` 时退回 `run.hazards / mechanics_zones / wall_ring / glass_sea / meteor_warning` 旧字段。

| kind | 画法 |
| --- | --- |
| `band` | 读 `color/alpha`：矩形冷却带或圆环；可带 `frac` 进度弧 |
| `circle` | 填充淡圆 + 描边 + `label` 小字；若为城市内城墙色 `#8A8378` 且 r≥80 → 改画三圈石带 + 垛口 + 塌陷缺口 |
| `wall` | 海墙：竖向蓝色水墙 + 流动波纹 |
| `prop` | 按 label：`torch/campfire` 火苗、`pillar` 石柱、`snake` 蛇形折线、`door` 门框、`lantern` 灯、`stone/bread` 圆石、其余方块 |
| `hazard` | 按本图 `mechanics.id` 选样式：`meteor_horde` → 陨星预警；`lightning_zones/furnace_rings/drought_fire/abyss_vents/plague_cycle` → 雷击圈；其余通用红圈。进度 `progress=1-t/1.5` 驱动收缩弧 |
| `pickup` | 菱形光点 + 脉动光圈 |
| `overlay` | 全屏染色（玻璃海 `#8FC8E0`，alpha 0.10） |
| `vision` | 暂不绘制（留给暗角/帷幕逻辑） |

机关视觉要点：雷击圈黄色收缩弧 + 落雷折线；陨星橙红瞄准环 + 右上划落轨迹 + 命中爆点；城墙三圈石带 + 48 垛口 + 塌陷尘裂；玻璃海淡蓝全屏 + 14 道裂纹 + 6 处火点。命中闪光由 `_draw_hazard_fx()` 画在敌人/弹幕之上，不遮 HUD。

### 7.2 敌人分型

- `behavior`：`chaser` 方身 + 头 + 朝玩家线；`charger` 方身 + 双角；`ranged` 方身 + 头 + 弧；`dive` 三角翼 + 滑线。
- 附加字段（有则叠加）：`flying` 翅膀线、`armored` 弧甲、`summoner` 三点环绕、`exploder` 脉冲圈。
- 精英：按 `elite_affix/name/id` 关键词着色（火橙/毒绿/雷黄/冰蓝/甲银/召唤紫/疾青/圣金），红框改为对应色 + 菱形角标。
- BOSS：阶段光环（>66% 暗红、33–66% 橙、<33% 金红）+ 两圈刻度。

## 8. 数据来源对照

| UI 元素 | 来源 |
| --- | --- |
| 20 见证人 / perk / 觉醒 | `data/characters.json` + `Meta.is_awakened` |
| 24 章节 / 解锁 / 经文 / 首通奖励 | `data/stages.json` + `Meta.wins` + `data/achievements.json` |
| 6 建筑 / 价格 / 解锁 | `data/store.json` + `Meta.building_*` |
| 12 圣物 | `data/relics.json` + `Meta.has_relic` |
| 40 成就 | `data/achievements.json` + `Meta.has_achievement` |
| 21 灾变阶 | `GameData.store_row` + `Meta.effective_tier/max_tier_allowed` |
| 约卡 / BOSS 名 | `run.covenants.draw_data()` / `data/bosses.json` |
| 银两 | `Meta.reward_for` 公式 + `run.reward` + `run.rewards.silver_run` |

## 9. 截图描述（供 `--shot` 后续自查，当前未跑窗口命令）

- **标题页**：深棕竖纹底，顶部金色「余 民」与「T H E   R E M N A N T」；中部 2×3 灰金卡片，首卡高亮；右下角「第 1/4 页 · 已解锁 1/20」；底部键位提示。
- **营地·强化**：左侧 6 行，选中行金色左条与底色，名字/说明/5 个等级点/右侧价格；下方绿色「出发 → 第 13 章《以拉谷》」；右栏 21 刻度灾变阶 + 详情卡。
- **营地·会幕**：6 座建筑行，右侧「Lv 0 · 50」；未开放行灰色显示「未开放 · 累计 3 局后」；「待实装」行黄色。
- **图鉴**：三页签，左列 10 行（✓/锁），右详情经文与效果；选中行金框。
- **HUD**：顶部 BOSS 名与血条；左上约卡 2 格；机制行黄字；左下 12 枚圣物小方块；左下 HP 条。
- **结算**：暗幕，中央金色「约柜得胜」，银两三行明细，成就最多 3 条 ✓，圣物解锁一行。
- **世界**：干涸河床青绿色横带；雷击圈黄色收缩弧；城墙石环；玻璃海淡蓝全屏；敌人按 behavior 形状区分。

## 10. 验证

```bash
HOME=$PWD/.godot_home /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
HOME=$PWD/.godot_home /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 120
HOME=$PWD/.godot_home /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 1200 scenes/camp.tscn -- --camp-selftest
HOME=$PWD/.godot_home /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 1200 scenes/codex.tscn -- --codex-selftest
HOME=$PWD/.godot_home /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 600 scenes/title.tscn -- --title-selftest
HOME=$PWD/.godot_home /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 1500 scenes/title.tscn -- --camp-selftest   # 标题→营地链路
HOME=$PWD/.godot_home /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --sim --sim-speed=900 --no-meta --seal=1 --stage=elah_valley
HOME=$PWD/.godot_home /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --sim --sim-speed=900 --no-meta --seal=1 --stage=ch07_sinai
```

结果（2026-11-17 终验）：

- `--import` 与 `--quit-after 120`：exit 0，0 SCRIPT ERROR。
- 营地自检：`rows=8 stages=24 unlocked=2`、`page1 rows=6 first=燔祭铜坛`、`stage_cycle_back=true cursor=12`、`SELFTEST_DONE`；6 建筑状态含 3 个可买（50/45/35）、1 个未开放、2 个待实装。
- 标题自检：`witnesses=20 unlocked=1 first=david last=john_patmos`、滚动窗口 `0/6/12` 正常；标题→营地链路进入 camp 自检并 `SELFTEST_DONE`。
- 图鉴自检：`relics=12 unlocked=4`、`achievements=40 done=0`、`witnesses=20 unlocked=1`、三页签首条正常、`back=res://scenes/camp.tscn`。
- `--sim --sim-speed=900 --no-meta --seal=1`：`elah_valley victory=true t=780.0 level=41 kills=8952`；`judea_wilderness victory=true t=750.0 level=45 kills=8225`；`ch07_sinai --sim-god victory=true t=702.5 level=44`（非 god 模式在 t=208 阵亡，属雷击机制强度问题，交数值侧）。
- 三个 sim 均 0 SCRIPT ERROR；图鉴必须显式传 `scenes/codex.tscn`，否则会先加载主场景 title 并挂住。

## 11. 未完成 / 依赖

- `prayer / sanctuary` 强化未实装，香坛与约柜显示「待实装」；实装后无需改 UI（自动走 `building_next/cost`）。
- 结算成就与局内拾取银两依赖局内系统在 `_finish` 调用 `RunAchievements.evaluate()` 并把 `rewards.silver_run` 计入存档；UI 已做空态降级。
- 未见 `docs/V2-跑局接口.md`，字段契约暂以 `docs/V2-接口需求-ui.md` 为准。
- 真窗口截图未跑（本波只用 headless）；截图描述见第 9 节。
