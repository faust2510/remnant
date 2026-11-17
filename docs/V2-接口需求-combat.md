# V2 · combat 侧接口需求（给别的代理）

> 来源：战斗与 BOSS 代理（combat）。本波我只改 `src/sim/enemy_sim.gd`、
> `src/sim/projectile_sim.gd`、`src/sim/boss_ai.gd`、`src/combat/weapon_runner.gd`、
> `data/enemies.json`、`data/bosses.json`。下面这些**不在我的写作用域**，需要对应负责人接线。

---

## 1. 渲染（owner: 局内系统 / world_renderer）

### 1.1 危害场（BOSS 的 zone_denial / nova / 火柱）目前完全看不见

数据在 `run.enemies.hazards`，每个元素：

```gdscript
{ "x": float, "y": float, "r": float, "dmg": float,
  "life": float, "tick": float, "tick_t": float,
  "kind": "zone" | "nova" | "pillar" | "heal", "color": Color }
```

建议画法（两段式，让玩家有反应时间）：

- `tick_t > 0`：预警阶段 → 画 `color` 的描边圆 + 逐渐收缩的内圈（`tick_t` 是剩余预警秒数）。
- `tick_t <= 0`：生效阶段 → 半透明填充圆（alpha 0.18~0.25）。
- `kind == "heal"`：绿色系，不伤害玩家。
- 直接复用 `world_renderer._draw_zones()` 的思路即可，`hazards` 上限 48 个，开销可以忽略。

### 1.2 图腾柱需要和普通怪区分

`enemies.totem_t[i] > 0` 的敌人是 `spawn_totem` 召出来的柱子（站桩、不造成接触伤害、到期自灭）。
它借用了 `brick_golem` 的贴图数据，建议画成方形/加裂缝，否则玩家会以为是普通怪。

### 1.3 BOSS 血条

`run.enemies.boss_idx`（-1 表示场上无 BOSS）与 `run.enemies.hp[boss_idx] / max_hp[boss_idx]`。
阶段信息在 `run.enemies.boss_ai.phase`（0/1/2），可以画三段血条。

---

## 2. 引擎（owner: engine-core / src/core/game_state.gd）

### 2.1 被动 `stat2` 双效果（data-weapons 第 1 条，仍未落地）

`_apply_passive_def(p, s)` 目前只读 `def.stat` / `def.per_level`。需要补：

```gdscript
if p.has("stat2"):
    _apply_stat(s, String(p["stat2"]), float(p.get("per_level2", p.get("per_level", 0.0))))
```

对应 5 个被动（`data/passives.json`）：patience（armor + 抗击退）、gospel_shoes（move_speed + 闪避 cd）、
shield_of_faith（armor + 远程格挡）、ephod（crit_damage + 银两）、olive_oil（projectile_speed + Lv3 穿透 +1）。

### 2.2 `extra_projectile` 建议进 stats

武器层现在读的是 `stats.get("extra_projectile", 0) + state.get_meta("extra_projectile")`，
契约卡（covenants）走 meta 已经能生效。若希望被动/角色也能给，请在 `recompute()` 里加
`"extra_projectile": 0`，并在 `_apply_passive_def` 加分支（武器层无需再改）。

### 2.3 `burn_stack_max` 默认值

`recompute()` 现在默认 `"burn_stack_max": 1.0`，而引擎基准灼烧上限是 5 层。
武器层做了兜底：`enemies.burn_cap = max(5, round(burn_stack_max))`，所以**默认不会退化**；
但如果你把默认值改成 5.0，语义会更干净（角色 `burn_stack_max: 10` 直接生效）。

### 2.4 `stages.json` 的 `status_duration`

ch10 有 `mods.status_duration: 1.25`，目前没有任何消费方。建议并进 `apply_status` 的时长
（`EnemySim.apply_status` 的 3.0/2.0/4.0 秒可以接一个 `status_duration_scale` 字段）。

---

## 3. 局内系统（owner: run.gd）

### 3.1 不要重复 tick BOSS

`EnemySim.spawn()` 已经在 `behavior == "boss"` 时创建 `BossAI`，`EnemySim.update()` 每帧调 `boss_ai.tick()`。
如果 run.gd 新增的 `_tick_boss_ai()` 再调一次，**技能频率会翻倍**、冲撞会叠加。
需要 shots 直连时不要新建控制器，改这一行即可：

```gdscript
if enemies.boss_ai != null:
    enemies.boss_ai.shots = shots   # 不传就继续走 shot_queue，两条路都通
```

**现状（2026-11-17 复核）**：run.gd 已经加了 `_ensure_boss_ai()`（L1299 用 `load("res://src/sim/boss_ai.gd").new()`）
和 `_tick_boss_ai(delta)`（L410 每帧调）。战斗层为避免双驱动，已在 `BossAI.tick()` 开头加了单驱动保护
（只有 `enemies.boss_ai` 指向的那个实例会生效，run 侧另建的实例直接 return），所以**现在重复调用是无害的**，
但每帧多一次脚本调用 + 槽位搬移后 run 侧实例的 `idx` 会失配，建议还是把 `_tick_boss_ai` 删掉或改成上面那行接线。

### 3.2 false_idol 的"全屏脉冲禁武器"

需要 run 侧支持：`state.disabled_weapon_until[i]`（或 run 维护一个 `PackedFloat32Array`），
在 `weapons.tick()` 之前把被禁武器的 `timers[i]` 按住。战斗层可以配合：敌人死亡/命中事件里不带这个状态。
本波未做，因为禁武器必须落在 run 的武器循环上。

### 3.3 冲刺无敌 `iframe`

`stats.iframe` 契约键在武器/被动里出现，但无敌判定在 `run._take_damage()`，需要 run 消费。

---

## 4. 数据侧（owner: data-enemies / data-stages）

### 4.1 精英词条参数目前写死在 `enemy_sim.gd`

12 个精英用 `elite_affix` 中文串驱动 8 个机制（震地/召唤/光环/护甲/瞬移/环形/火柱/分裂），
但**频率、伤害、半径都是代码默认值**（震地 4.5s 8 发 5 伤、环形 4.0s 6 发 6 伤、火柱 5.0s 44px 7 伤…），
因为 `enemies.json` 没有对应字段。若要让策划改数，建议加可选字段（战斗层会按 "取不到就用默认" 读取）：

```json
{ "id": "nephilim_shade", "elite": true, "elite_affix": "…",
  "affix": { "cd": 4.5, "count": 8, "damage": 5, "radius": 52, "speed": 62 } }
```

本轮我**没有**改 enemies.json 的结构，只在敌人数据里新增了三个可选行为参数（已生效、缺省值与原行为等价）：
`ranged` 的 `count` / `spread_deg`，`dive` 的 `dive_freq` / `dive_wobble`，`charger` 的 `charge_speed` / `charge_time` / `charge_cd`。
蝗虫群、蛙群要"扇形齐射"只需在 enemies.json 里给 `count`+`spread_deg`。

### 4.2 ch06 / ch24 的开局暴毙

`--seed=7 --no-meta --seal=1` 下 ch06 在 t=31.3 就死（Lv8，111 杀），ch24 在 t=388.7 死（Lv47），
而 ch01/ch02 能活到 750 并击杀 BOSS。A/B 关掉全部精英主动机制后结果逐字节相同 → 与战斗层无关，
是 `budget.base`（ch06 215 / ch24 280）与 t=0 的 mix（ch06 直接上 blood_wraith+plague_locust）太狠。
需要 data-stages 校准开局 0-60 秒的压力曲线。

### 4.3 ch24 的 BOSS 打不死

`beast_of_sea` raw 40000 × 生成时 hp_scale 2.34 = 93739，自动构筑 DPS ≈ 800 → 需要 ~117s，
但 `boss_at=660`、`duration=750` 只留 90s。二选一：拉长窗口或把终章 BOSS 下调到 ~30000。
按 lead 要求本轮保持 40000 未动。

---

## 5. UI（owner: ui_text / HUD）

- 新增 stat 文案：`duration`（效果持续）、`melee_only_bonus`（近战加成）、`burn_stack_max`（灼烧层数）。
  `src/ui/ui_text.gd` 里已有 `burn_stack_max` / `melee_only_bonus` 分支，`duration` 若没有请补一条。
