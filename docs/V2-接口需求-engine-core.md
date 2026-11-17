# V2 接口需求 · engine-core（引擎底座 → 其他模块）

> 我只改了 `src/core/game_data.gd`、`src/core/game_state.gd`、`src/core/meta.gd`、`data/store.json`。
> 下面每一条都是**别人文件里需要接线的一行改动**，引擎侧已经准备好 API，不需要再改核心。
> 详细 API 表见 [V2-引擎底座.md](V2-引擎底座.md)。

## 0. 已经向后兼容、不需要改的地方

- `GameState.setup(character_id, bonus)` 旧两参调用**照常工作**（第三参可选）。
- 旧的 stats 键（`area_mult` / `proj_speed_mult` / `knockback_mult` / `crit_mult` / `max_hp` …）全部保留，并把新键同步镜像回去，所以 `weapon_runner.gd` 现有读取**不会失效**。
- `data/relics.json`、`data/covenants.json` 不存在时静默跳过，不报错。
- 老 `save.json` 没有 v2 键时走默认值，正常读档。

## 1. src/run.gd（拥有者：运行流程）

### 1.1 开局把圣物带进本局

```gdscript
# 之前
state.setup(character_id, GameData_char_bonus)
# 之后（可选第三参：不传就自动读 Meta.relics）
state.setup(character_id, Meta.bonus(), Meta.relics)
```

### 1.2 结算必须传真实阶

```gdscript
var gain: int = Meta.register_run(victory, state.kills, elapsed, Meta.effective_tier())
```
> `register_run / reward_for` 的 `seal <= 0` 才会回退到 `effective_tier()`；`--seal=N` 命令行跑局要显式传 N，否则银两倍率与实际难度不一致。

### 1.3 新 stat 的消费点

| 键 | 建议位置 | 语义 |
| --- | --- | --- |
| `stats["heal_per_sec"]` | `_process(delta)` | `hp = min(hp + heal_per_sec * delta, max_hp)` |
| `stats["damage_taken_mult"]` / `incoming_damage_mult()` | 玩家受伤处 | 直接把普适减伤一起乘掉：`dmg *= state.incoming_damage_mult()` |
| `state.silver_mult()` | 拾取银两 | 银两掉落量 `*= state.silver_mult()` |
| `stats["level_heal"]` | 升级回血 | 已经包含 `level_heal_bonus`，不用再改 |
| `stats["melee_only_bonus"]` | 交给 weapon_runner | 仅近战行为吃这个加成 |
| `stats["burn_stack_max"]` | 交给 combat | 灼烧最大层数 |
| `stats["duration"]` | 交给 weapon_runner | 领域/回旋/灼烧的持续时间乘区 |
| `stats["enemy_speed_slow"]` | 交给 sim | 0..0.8，敌人移速 `*= (1 - slow)` |

### 1.4 升级池要能出宝物（kind = "treasure"）

- 被动槽现在是 4 格，宝物与果子共用；`GameState.add_passive()` 内部按 `kind` 判上限（4 件宝物）。
- run.gd 的升级候选生成如果按 `GameData.passives` 过滤，**不需要改**；但 UI 图标建议区分 `kind`（fruit / armor / treasure）。
- 宝物**不进祝圣配方**：`available_fusions()` 只查 `has_passive()`，宝物若与配方被动同 id 才会误触发——数据侧保证 id 不冲突即可。

### 1.5 觉醒点亮（3 印通关）

```gdscript
if victory and Meta.effective_tier() >= 3:
    Meta.set_awakened(character_id)   # 之后 GameState.setup 会自动叠觉醒 perk
```
> `set_awakened` 会立刻写盘；重复调用无副作用。觉醒 perk 只在该见证人 `character["awakening"]["perk"]` 存在时生效。

### 1.6 HUD 显示（可选）

`state.is_awakened()`、`state.relic_defs()`、`Meta.tier_name()` 可直接拿文案。

## 2. src/camp_screen.gd（拥有者：营地 UI）

1. **面板高度**：`ROW_Y0 = 64 / ROW_STEP = 31`、高度 360 只放得下 6 行（9 行会到 401）。所以 `faith / prayer / sanctuary` 这次没有进 `Meta.UPGRADES`（数值已在 `data/store.json` 标 `live:false`）。要实装需要先把面板改成两列或滚动。
2. **建筑视图**：`Meta.building_defs()`（6 条，含 `name / scripture / upgrades[]`）、`building_level(id)`、`building_next(id)`、`building_cost(id)`、`buy_building(id)`。等级目前是「该建筑所属强化里最高级」的派生值，不是新的经济系统。
3. **灾变阶选择**：把印数选择器上界从 7 换成 `Meta.max_tier_allowed()`，名字用 `Meta.tier_name(n)`，写回用 `Meta.set_tier(n)`（`n <= 7` 时它同时写 `selected_seal`，旧入口不受影响）。
4. **营地面板第 7 行起**再接三项新强化时，记得同步 `Meta.UPGRADES`（`base/step/max` 与 `data/store.json` 的 `costs` 一致）以及 `Meta.bonus()` 里的键。

## 3. src/combat/weapon_runner.gd（拥有者：战斗）

- 已可直接读到的旧键保持不变（`area_mult`、`proj_speed_mult`、`knockback_mult`、`crit_mult`、`dot_mult` …）。
- 新增需要消费的三个键：

```gdscript
var duration_mult: float = float(stats.get("duration", 1.0))       # 持续时间乘区
var melee_bonus: float = float(stats.get("melee_only_bonus", 0.0)) # 仅 arc_melee 行为吃
var burn_cap: float = float(stats.get("burn_stack_max", 1.0))      # 灼烧最大层数
```

- `enemy_speed_slow` 属于敌人侧（`src/sim`），不要在武器里消费。

## 4. src/sim/**（拥有者：模拟层）

```gdscript
var hp_mult: float = Meta.tier_enemy_hp()      # 1 + 0.09*(tier-1)
var dmg_mult: float = Meta.tier_enemy_dmg()    # 1 + 0.06*(tier-1)
var spawn_mult: float = Meta.tier_spawn_rate() # 1 + 0.04*(tier-1)
var row: Dictionary = Meta.tier_row()          # 含 name / mods / note / max_enemies
```
> `row.mods` 是给各阶特殊规则的数据钩子（`vision:-0.25`、`falling_rock_interval:180.0`、`double_boss:1`、`max_enemies:750` …），目前**没有系统消费**，需要 sim 侧按 `mods` 分支。

## 5. src/ui/**（拥有者：UI）

- 结算页建议显示 `state.silver_mult()` 与 `Meta.tier_name()`。
- 圣物/成就列表：`GameData.relics`、`Meta.relics`、`GameData.achievements`、`Meta.achievements`。`relics.json` 到位前这两个数组是空的，UI 必须能显示空态（不要假设非空）。

## 6. 数据组（拥有者：data/*.json）

1. `data/relics.json` 结构（契约第 6 节）之外，**可选**加 `"stats": {"area_pct": 0.1, "projectile_speed": 1.1}`，引擎会直接叠进 `GameState.stats`；没有 `stats` 的圣物按「规则型」处理，由 systems 读 `has_relic(id)` 自行生效。
2. `passives.json` 新增宝物时把 `kind` 写成 `"treasure"`，`stat` 用第 5 节的新键（`area_pct / projectile_speed / duration / knockback / crit_damage / heal_per_sec / silver_gain / enemy_speed_slow`）。
3. `characters.json` 的 `awakening.perk` 键名用第 6 节的新 perk 名（`max_hp_bonus / damage_taken_mult / projectile_speed / duration_mult / pickup_bonus / level_heal_bonus / melee_only_bonus / burn_stack_max / silver_bonus`），乘性键必须以 `_mult` 结尾，否则会被当加性相加。
4. `data/store.json` 由我维护（6 建筑 / 9 强化 / 21 阶常量表）。改数值请提需求，不要直接照抄到别的 json，避免两处漂移。

## 7. 我明确没动的东西

- `src/run.gd`、`src/ui/**`、`src/camp_screen.gd`、`src/title_screen.gd`、`src/sim/**`、`src/combat/**`、`src/render/**`：只读，未改一行。
- `data/` 下除 `store.json` 以外的文件：只读（数据组正在改 `characters/enemies/fusions/passives/weapons`）。
