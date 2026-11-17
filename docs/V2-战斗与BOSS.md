# V2 · 战斗与 BOSS（第 1 波）

> 负责人：combat。写作用域：`src/combat/weapon_runner.gd`、`src/sim/enemy_sim.gd`、
> `src/sim/projectile_sim.gd`、`src/sim/boss_ai.gd`、`data/enemies.json`、`data/bosses.json`。
> 设计依据：`docs/设计圣典-v0.6.md` + `v2_0.md` 第 9 节（BOSS 技能）、武器契约第 5/6 节。
> `src/run.gd` 与 `src/ui/**` 归别的代理，本波一行未改。

---

## 0. 改动清单

| 文件 | 改动 | 目的 |
| --- | --- | --- |
| `src/sim/boss_ai.gd`（新建） | `class_name BossAI`，8 技能 + 三阶段 + 站位 | 契约第 9 节的 BOSS 控制器落地 |
| `src/sim/enemy_sim.gd` | 挂载 BossAI、精英词条位掩码、危害场 `hazards`、图腾、分裂、光环、远程齐射参数、灼烧上限可配 | 敌人行为五原子 + 12 精英真机制 |
| `src/sim/projectile_sim.gd` | 穿透弹同目标去重（`last_hit`）、负击退 | 修掉 BOSS 每帧挨一次穿透伤害的虚高 |
| `src/combat/weapon_runner.gd` | `evolves_to.overrides`、homing 穿透、zone `center:self`/`throw_dist`、负击退、`duration`/`melee_only_bonus`/`burn_stack_max`/`extra_projectile` | data-weapons 的 7 条接口需求 + engine-core 第 3 节三个新 stat |
| `data/enemies.json` | 未改结构；本轮无需调数值（行为参数全部走代码默认值，见 §5） | — |
| `data/bosses.json` | **未改**（曲线一位没动） | 实测证明打不死的根因不是 hp，见 §6.1 |

---

## 1. BOSS 三阶段控制器（src/sim/boss_ai.gd）

### 1.1 生命周期（run 侧零接线）

```gdscript
class_name BossAI extends RefCounted
func setup(enemies: EnemySim, idx: int, def: Dictionary, shots: ProjectileSim, rng: RandomNumberGenerator) -> void
func tick(delta: float, ppos: Vector2) -> void
```

- `EnemySim.spawn()` 在 `behavior == "boss"` 时自动 `BossAI.new()` 并 `setup(self, i, type_def, null, rng)`；
  `EnemySim.update()` 的 boss 分支每帧调 `boss_ai.tick(delta, ppos)`。**run.gd 不需要手动创建**。
- `_swap_remove()` 维护索引：BOSS 被移除时清空 `boss_ai/boss_idx`；别的敌人被移除且搬动了 BOSS 时，
  同步 `boss_idx` 与 `boss_ai.idx`（否则技能会打到错的敌人槽位）。
- `shots` 允许为 `null`：为 null 时弹幕走 `enemies._emit_shot()` 进 shot_queue，由 run 统一成弹；
  非 null 时直接 `shots.spawn(friendly=false)`。两条路都能跑，谁先接线都不冲突。
- 随机数只用 `setup()` 传入的 `rng`（即 `EnemySim.rng`，run 侧已按 seed 播种），同 seed 完全可复现。

### 1.2 阶段

| 阶段 | at_hp | 进入动作 | 可选键 |
| --- | --- | --- | --- |
| 0 | 1.00 | 开场技能冷却 ×0.5（蓄力） | `speed_mult` / `dr` |
| 1 | 0.66 | 换阶段时放一圈 12 发慢速环弹宣告 + 技能冷却 ×0.3 | 同上 |
| 2 | 0.33 | 同上，站位压到 92px（狂暴） | 同上 |

- `dr` 走 `EnemySim.damage()` 的统一减伤：`1 - clamp(dr + shield_dr, 0, 0.85)`。
- `shield_dr()`：场上还有 BOSS 图腾时额外 20% 减伤（打掉图腾才恢复输出）。

### 1.3 站位（本轮新增的平衡关键）

BOSS 不再"一路贴脸"，也不再生生地追不上玩家：

| 条件 | 行为 |
| --- | --- |
| `dist > pref + 22` | 以 `max(1.35×速度, 110)` 逼近（速度下限，见下） |
| `dist < pref - 26` | 以 0.9× 速度后撤（负速度） |
| 中间地带 | 以 0.55× 速度侧移绕圈 |
| `pref` | `clamp(118 - 12*phase, 92, 125)`：P0 118px → P2 92px |

**速度下限 110 是必须的**：`data/bosses.json` 里 BOSS 的 `speed` 只有 40~60，玩家绕圈时距离会被拉到
200px 开外，长枪（range 200）与追踪（range 220）全部打空——2026-11 实测 ch01 的 BOSS 在 90 秒里只被
打出 3045 伤害就再也不掉血。给了下限之后追击速度约 110~160，站位才真正稳定在 92~125px。

这样近战（`arc_melee`/`orbit`）武器打不到站桩 BOSS，玩家必须主动进内圈换输出窗口；
BOSS 的冲撞（`charge`）与硬直会打破站位，形成"进—退—闪"的循环。

### 1.4 八种技能（契约第 9 节，全部实现）

| id | 参数（data/bosses.json） | 判定 / 表现 | 代码 |
| --- | --- | --- | --- |
| `ring_burst` | `count` `damage` `speed` | 以自身为圆心均分一圈，起始角 `rng` 随机 | `_ring_burst()` |
| `aimed_shot` | `count` `damage` `speed`（可带 `spread_deg`） | 朝玩家连发，每发间隔 0.09s、带小扇角（进 `burst` 队列延时出膛） | `_aimed_shot()` / `_tick_burst()` |
| `summon` | `enemy` `n` | 在自身周围 40~70px 召 `n` 只指定 id 的小怪（id 不存在则静默跳过） | `_summon()` |
| `charge` | `damage` `speed` `count` | 分 `count` 段冲撞，每段 0.42s、间隔 0.26s；冲撞期间临时把接触伤害改成 `damage`，结束后恢复 0.42s 硬直 | `_charge()` / `_start_charge()` / `_restore_charge_damage()` |
| `zone_denial` | `radius` `damage` `duration` `tick` `count` | 在玩家脚下落 `count` 片危害场，0.5s 预警后按 `tick` 周期结算 | `_zone_denial()` |
| `heal_self` | `pct` | 回 `pct`×最大血量（上限回满），并留 0.7s 治疗特效 | `_heal_self()` |
| `spawn_totem` | `hp` `count` `duration` | 召 `count` 根图腾柱（可被打碎，期间 BOSS 减伤 20%，到期自灭） | `_spawn_totem()` |
| `nova` | `radius` `damage` | 以自身为圆心的大范围爆发，0.35s 预警 | `_nova()` |

- 冷却：每条技能独立计时器（`cd[]` 与 `phases[phase].skills` 下标对齐），到点重置为 `skill.cd`。
- 未识别的技能 id 退化为 `ring_burst`，不崩。
- 遥测：`REMNANT_BOSS_TRACE=1` 时每 2 秒打印 `[boss] t hp/max pct phase dmgtaken`，供无头标定。

---

## 2. 武器六种原子补完（data-weapons 的 7 条接口需求）

| # | 需求 | 实现 |
| --- | --- | --- |
| 1 | 被动 `stat2` 双效果 | **代码层未做**：`_apply_passive_def` 在 `src/core/game_state.gd`（engine-core 名下）。已写入 `docs/V2-接口需求-combat.md` |
| 2 | `extra_projectile` / `iframe` stat | `extra_projectile` 已在武器层消费：`stats.extra_projectile` + `state.get_meta("extra_projectile")` 相加，line/homing/zone/orbit 的 `count` 全部生效；`iframe` 属 run 侧（冲刺无敌） |
| 3 | 成全吃 `evolves_to.overrides` | `_ascend_params(entry, params)` 读 `state.weapon_def(entry).evolves_to.overrides` 做**绝对覆写**；只有数据没写的键才走旧的倍率兜底（伤害×1.25 / 弹数+1 / 半径·射程×1.12 / 弧角×1.1）。`_tick_orbit` 与 `orbit_points` 同样走这条路径，视觉与结算一致 |
| 4 | 14 个圣典专属 modifier | 本轮不做（枚举只允许 6 种），保持 `modifier` 只认 shockwave_on_hit / tidal_push / wall_push / trail_fire / holy_smoke / echo_blade |
| 5 | 负击退（`sickle.knockback = -40` 回拉） | `_arc_hit` 与 `damage_in_circle` 的 `if kb > 0` 改成 `absf(kb) > 0.01`；`EnemySim.knockback()` 本来就按方向施力，负值即反拉 |
| 6 | `zone` 的 `center:"self"` 与 `throw_dist` | `center == "self"` 或 `range <= 8` → 以玩家为圆心；否则落目标脚下；`throw_dist > 0` 时朝目标方向只扔这么远（目标更近则落目标处，无目标则朝瞄准方向扔） |
| 7 | `homing` 硬编码 `pierce: 0` | 改读 `params.pierce`（`heaven_keys` 2 / `key_of_david` 4 现在真的会穿透） |

### 2.1 BOSS 优先索敌（`_pick_target`）

`_pick_target(ppos, range)` 原来只返回**最近**的敌人。站位拉开后 BOSS 永远不是最近的（周围几十只杂兵），
于是四把武器全打杂兵、BOSS 一发不吃。现在改成：**射程内只要有 BOSS，就锁定 BOSS**；
没有 BOSS 时行为与原来逐字节一致。这也是 ch01 从"90 秒 0 伤害"变成"12 秒击杀"的直接原因。

### 2.2 穿透弹去重（本轮修的硬 bug）

`projectile_sim.gd` 的命中循环原来**不记录本弹已命中过谁**：一颗 `pierce: 7` 的弹进入 BOSS
那 26~30px 的碰撞半径后，会在其内部飞行 8~10 帧，于是每帧结算一次穿透伤害 ——
单目标 DPS 被放大快一个数量级（实测 ch01 BOSS 8.6 秒被打空 9374 血）。

现新增 `last_hit: PackedInt32Array`：同一条弹对同一个敌人只结算一次，穿透继续飞行后可以命中别的敌人。
修完 ch01 BOSS 的单目标 DPS 从 ~2000 降到 ~1000 量级（见 §6 实测）。

---

## 3. 新 stat 消费（engine-core 契约第 3 节）

| stat | 语义 | 落地 |
| --- | --- | --- |
| `duration`（默认 1.0） | 持续乘区 | `line_projectile` 存活 ×dur、`homing` 存活 ×dur、`zone.life` ×dur |
| `melee_only_bonus`（默认 0.0） | 仅近战加成 | 只乘 `arc_melee` 的伤害（`1 + bonus`）；不改枪弹/环绕 |
| `burn_stack_max`（默认 1.0） | 灼烧最大层数 | `WeaponRunner.tick()` 每帧下发 `enemies.burn_cap = max(5, round(burn_stack_max))`。**默认 1.0 视为"未配置"，保留引擎基准 5 层**；角色/被动给 ≥5 时按其值生效 |
| `extra_projectile`（默认 0） | 额外投射物 | §2 第 2 条 |

---

## 4. 精英词条（12 种 → 8 个真实机制）

`data/enemies.json` 的 `elite_affix` 是中文描述，不改结构，`_decode_affix()` 按关键词解成位掩码：

| 掩码 | 机制 | 数值 | 触发它的精英 |
| --- | --- | --- | --- |
| `AFFIX_ARMOR` | 受伤 ×0.7（正面护甲近似） | 30% 减伤 | anakim_giant |
| `AFFIX_SUMMON` | 召 2 只 brick_golem | 每 6.0s | babel_overseer |
| `AFFIX_QUAKE` | 8 向震地弹 | 每 4.5s，62px/s，5 伤 | nephilim_shade |
| `AFFIX_AURA` | 170px 内普通怪加速 | +25%，离开即失效 | pharaoh_sorcerer |
| `AFFIX_SPLIT` | 死亡分裂 4 只 drowned_shade | 死亡时 | possessed_brute |
| `AFFIX_TELEPORT` | 90px 内瞬移贴身突刺 | 34px 身侧，2.5s 冷却 | midian_prowler |
| `AFFIX_RING` | 6 发环形巨石弹 | 每 4.0s，80px/s，6 伤 | six_finger_giant |
| `AFFIX_PILLAR` | 玩家脚下火柱 | 每 5.0s，44px，7 伤，0.65s 预警 | baal_zealot |

其余 4 位（chariot_captain / dune_scorpion_king / horsemen_vanguard / false_idol）
保持"数值强化 + 已有行为原子"：
- chariot_captain / possessed_brute 是 `charger`（数据 `charge_speed` 可调）；
- dune_scorpion_king 是 `charger` + 扇形齐射（行为参数）；
- horsemen_vanguard / false_idol 的"环绕骑射 / 禁武器"需要 run 侧接口（见 `docs/V2-接口需求-combat.md`）。

---

## 5. 敌人行为五原子 + 通用参数

36 个敌人的 behavior 分布：chaser 15 / ranged 7 / charger 9 / dive 5（+ bosses.json 的 24 个 boss）。
新增敌人（蜗牛、蛙群、蝗虫等）不需要新代码，只用下列**通用数据键**：

| behavior | 可调键 | 默认 |
| --- | --- | --- |
| `chaser` | 无（`speed` / `rad` / `damage`） | — |
| `ranged` | `keep_dist` `shoot_cd` `shot_speed` `shot_damage` `count` `spread_deg` | 110 / 2.6 / 150 / 7 / 1 / 12° |
| `dive` | `dive_freq` `dive_wobble`（正弦摆动） | 4.0 / 0.35 |
| `charger` | `charge_speed` `charge_time` `charge_cd` | 200 / 0.55 / 3.0 |
| `boss` | 见 `data/bosses.json` 的 `phases` | — |

- `ranged` 的 `count/spread_deg` 是本轮新增：蝗虫群、蛙群这种"扇形齐射"只加数据即可，
  `count` 缺省为 1 → 与老的直射行为逐字节等价。
- `blind` 状态下远程怪停火、`tremor` 减速 30%、`wet` 受电系加成、`fear` 反向逃跑（BOSS 免疫 fear）。

---

## 6. BOSS 数值校准

### 6.1 血量曲线（data/bosses.json）

| 章节 | 1 | 2 | 3 | 4 | 5 | 6 | 7–12 | 13 | 14–17 | 18–22 | 23 | 24 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hp | 4000 | 4400 | 4800 | 5200 | 5600 | 6000 | 6400–8800 | 9500 | 9800–10500 | 12700–27400 | 33200 | 40000 |

`run.gd` 的 `hp_scale` 在 BOSS 生成时（660s）约 2.34×，所以 ch01 的实际血量 ≈ 9374。
本轮**没有下调前六章 hp**：BOSS 打不死的根因不是血量，而是旧逻辑里 BOSS 只以 46 的移速直线追、
被玩家走位甩开、武器自动索敌只打最近的杂兵（见 §1.3 站位与 §6.2 实测）。

### 6.2 实测（`--sim --sim-speed=900 --no-meta --seal=1`）

| 章节 | BOSS | 生成时实际血量 | 击杀耗时 | 结局 / 构筑 |
| --- | --- | --- | --- | --- |
| ch01_eden | cherub_flame_sword | 9374 | **12.0s**（t=660 → 672.0） | victory，Lv38，圣言利剑+筑城锤+摩西铜蛇+歌利亚的丧钟 |
| ch02_flood | leviathan_tide | 10311 | **17.3s**（660 → 677.3） | victory，Lv39，筑城锤+摩西铜蛇+歌利亚的丧钟+燃烧的荆棘 |
| ch06_red_sea | pharaoh_chariot | 14061 | **28.1s**（660 → 688.1，`--sim-god` 跑的） | victory，Lv47；同 seed 不开 god 会在 t=31.3 被开局杂兵打死（见下） |
| elah_valley（ch13） | goliath | 22755 | **26.2s**（690 → 716.2） | victory，Lv40，摩西铜蛇+歌利亚的丧钟+彩虹之约+修直的道路 |
| judea_wilderness（ch17） | the_tempter | 24607 | **70.7s**（660 → 730.7） | victory，Lv45，投石索+摩西铜蛇+筑城锤+彩虹之约（全 zone/line 构筑，DPS 只有 ~300） |
| ch24_armageddon | beast_of_sea | 93739 | **90s 窗口内未死** | 计时胜利 t=750；40000 × 2.34 = 93739，按 ~800 DPS 需要 ~117s |

换算成单目标 DPS：ch01 ≈ 690–780/s、ch13 ≈ 868/s、ch17 ≈ 300/s。**改造前**同一套自动构筑对 ch01 BOSS
90 秒只打出 3045 伤害（dmgtaken 从 t=44 起完全不动），最后是计时胜利——所以打不死的根因是
「BOSS 追不上 + 武器只打最近杂兵」，不是 hp 数值，本轮 hp 曲线一位没动。

### 6.3 精英词条不是开局暴毙的原因（A/B 实测）

`--seed=7` 下把 `REMNANT_NO_AFFIX=1`（关掉全部精英主动机制）与默认设置对跑 ch06 / ch24，
两边结果**逐字节相同**（ch06 均 t=31.3 死、ch24 均 t=750、BOSS 血量均 93739）：因为精英最早 t=150 才刷，
死在前 31 秒的锅在章节开局预算（ch06 `budget.base=215` 且 t=0 就混编 blood_wraith / plague_locust），
不在精英机制。这条留给 data-stages 校准，战斗层不动它。

---

## 7. 验证命令

```bash
cd "/Users/qwe/Documents/文件大总管/10-项目/幸存者游戏"
HOME=$PWD/.godot_home /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
HOME=$PWD/.godot_home /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 120
HOME=$PWD/.godot_home /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- \
  --sim --sim-speed=900 --no-meta --seal=1 --stage=ch01_eden
```

- 新增 `class_name` 后必须先 `--import`（本波新增 `BossAI`）。
- 中文路径：先 `cd` 进项目；Godot 输出不要接管道（EPIPE 会杀进程），一律重定向到文件再 grep。

## 8. 已知限制 / 下一波

1. `hazards`（BOSS 的 zone_denial / nova / 火柱）目前**没有渲染**：world_renderer 只画 `weapons.zones`。
   接口需求已写进 `docs/V2-接口需求-combat.md`。
2. 精英的"环形骑射 / 全屏脉冲禁武器 / 冲锋流沙带"需要 run 侧支持（禁武器要动 run 的 timers）。
3. 被动 `stat2` 双效果在 `game_state.gd`，需 engine-core 接线。
4. ch24 的 BOSS 有效血量 93739，90 秒窗口内打不死（见 §6.2）：要么延长 `duration`/`boss_at` 之间的窗口，
   要么由数据侧决定终章 BOSS 是否下调到 ~30000。本轮按 lead 要求保持 40000 未动。
5. `REMNANT_NO_AFFIX=1` 是给平衡排查用的诊断开关（关掉精英主动机制），不要写进正式配置。
