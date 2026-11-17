# V2 接口需求：武器 / 祝圣 / 宝物（data-weapons → engine-core, combat）

> 数据侧已按契约落地（20 武器 / 20 祝圣 + 6 合鸣 / 20 宝物）。下面 7 条是需要别人配合的地方，按「谁改、改哪、为什么」列。
> 现状校验：`python3 /tmp/v2_weapons_check.py` → ALL CHECKS PASSED。

## 1. engine-core：passives 增加第二属性 `stat2` / `per_level2`（圣典有 5 件是双效果）

`docs/V2-数据契约.md` 第 5 节的 passive 只能写一个 `stat`，但圣典第 5 章这几件宝物的效果是两条：

| 宝物 | 主 stat（已写） | 次要效果（圣典原文） |
|---|---|---|
| `patience` 忍耐 | armor 4/级 | 抗击退 +15%/级 |
| `gospel_shoes` 平安福音鞋 | move_speed 0.06/级 | 闪避冷却 -6%/级 |
| `shield_of_faith` 信德藤牌 | armor 6/级 | 远程格挡率 +6%/级 |
| `ephod` 以弗得胸牌 | crit_damage 0.10/级 | 银两收益 +10%/级 |
| `olive_oil` 纯正橄榄油 | projectile_speed 0.12/级 | Lv.3 起穿透 +1 |

建议：`_apply_passive_def()`（`src/core/game_state.gd:318-335`）里再读一次 `def.get("stat2")`。数据侧我可以立刻补键（**只等你们说支持**，现在没写是怕被忽略）。

## 2. engine-core：passives 需要 `extra_projectile` 与「无敌帧」两种 stat

- **T16 `frankincense` 馨香乳香**：圣典是「投射物数量 +1（上限 2 级，满级 +2）」。契约枚举没有它，我暂用 `projectile_speed: 0.1` 占位（`desc` 已注明原案）。
- **T19 `fine_linen` 细麻衣**：圣典是「闪避无敌帧 +0.03s → +0.15s」。契约里的 `duration` 语义是武器/状态持续时间，我暂用它占位。

需要：`stat: "extra_projectile"`（per_level=1，Lv2 封顶由 `max_effective_level` 或 per_level 曲线控制）与 `stat: "iframe"`（加法秒数）。给了我就换。

## 3. engine-core：成全要吃 `evolves_to.overrides`

契约第 4 节明写 `evolves_to: {..., "overrides": {"damage":1.25, ...}}`，但当前：

- `src/core/game_state.gd:243 try_ascend()` 只做 `w["ascended"] = true`（level 与 kills 判定 OK）；
- `src/combat/weapon_runner.gd:276 _ascend_params()` 用固定倍率（伤害 ×1.25、弹数 +1、半径/射程 ×1.12、arc_deg ×1.1），**完全不读 `evolves_to.overrides`**。

我给每条祝圣都写了成全的第 6 阶永久覆写，例如：

- F01 `goliaths_knell`：`{"count":5,"pierce":7}`（圣典：弹数恒 5、穿透 +4、命中后弹射一次）
- F04 `jericho_horn`：`{"arc_deg":360,"knockback":320}`（城墙倾覆 → 全屏环形音爆）
- F12 `seven_lamps`：`{"radius":220,"count":7}`（玻璃海的烈焰 → 7 道常驻激光）

建议在 `resolved_params()` 里：`if entry.ascended: out.merge(evolves_to.overrides)`，`_ascend_params()` 的固定倍率可作为没有 overrides 时的兜底。

## 4. combat：圣典 14 个专属 modifier 没有物理分支（契约只允许 6 个）

本轮 `modifier` 严格只取契约第 2 节的 6 种，并按原子能力分配（zone→holy_smoke、orbit→trail_fire、homing→echo_blade、arc→tidal_push/wall_push、line→shockwave_on_hit）。这意味着 F07–F20 的**圣典专属机制没有真实代码分支**，只保留在 `desc` 里。缺的 14 个：

`healing_halo`(F07) `spring_burst`(F08) `rhythm_haste`(F09) `harvest_pull`(F10) `word_pierce`(F11) `spirit_beam`(F12) `serpent_totem`(F13) `fire_wake`(F14) `stone_barrier`(F15) `royal_edict`(F16) `blood_cry`(F17) `baptism_wave`(F18) `net_drag`(F19) `gate_of_light`(F20)

若要实现：先扩契约第 2 节枚举 → 我在 `fusions.json` 里把 `modifier` 换成真名（一条 sed 级改动），不需要动参数。

## 5. combat：负击退（回拉）不生效

`src/combat/weapon_runner.gd:209` 是 `if kb > 0.0: enemies.knockback(...)`。拾穗镰 `knockback: -40`（圣典「回拉」）与末后的收割镰 `knockback: 60` 在数据上是回拉意图，负值现在等于不击退。建议：`kb < 0` 时按 `-kb` 把敌人朝玩家方向拉（或加 `pull` 参数）。

## 6. combat：zone 缺「以自身为中心」与 `throw_dist`

`src/combat/weapon_runner.gd:176-195`：无目标时 `pos = ppos + Vector2(0, 40)`，`throw_dist` 从未被读取。受影响的数据：`tambourine`（铃鼓自心脉冲，我用 `range: 1` 规避索敌）、`abel_blood`（献祭红环）、`censer`（香炉）。

建议：`zone` 支持 `center: "self"` 或读 `throw_dist` 做落点偏移；否则铃鼓的圈永远偏玩家 40px。

## 7. combat / engine-core：`homing` 硬编码 `pierce: 0`，dual 键名要双读

- `src/combat/weapon_runner.gd:147` 对 homing 写死 `"pierce": 0`，导致 `heaven_keys.pierce: 2`、`key_of_david.pierce: 4` 在数据里但不生效。要么读 `params.pierce`，要么我把数据键删掉（说一声）。
- `src/core/game_state.gd:210-212` 读 `f["weapon_a"]` / `f["weapon_b"]`，契约第 4 节要求 `"weapons": ["a","b"]`。我在 6 条合鸣里**两种都写了**（值一致），当前代码能跑；建议 `GameData` 装载时统一成 `weapons[]`，我下轮再删旧键。

---

## 附：我这边没有阻塞的点

- 20 把武器 id 与 20 位见证人的 `weapon` 字段已对齐（`sling` `staff` `torch` `horn` `censer` `harp` + `olive_branch` `tambourine` `jawbone` `sickle` + 其余 10 把）。
- 无头冒烟与 `--sim` 已跑通：`goliaths_knell` / `zion_psalm` 双成全、`seven_stars_sword` 双武合鸣在实机路径上成立（日志见 `docs/V2-数据-武器宝物.md` 第 6 节）。
