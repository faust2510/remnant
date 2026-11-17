# V2 接口需求 · UI / 图鉴 / 营地

> 提出方：UI 负责人。仅描述 UI 只读消费的字段与需要局内系统保证的钩子；UI 不修改 `run.gd`、`src/sim/**`、`src/combat/**`。
> UI 对以下字段全部使用 `run.get("字段")` + 类型判断降级，字段缺失不崩、不阻塞。

## 1. 已对接（当前局内系统已提供，保持兼容即可）

| 字段 / 方法 | 形态 | UI 用途 | 缺失时 |
| --- | --- | --- | --- |
| `run.mechanics` | `RunMechanics` 对象 | 机制提示、危险区摘要 | 跳过机制行 |
| `mechanics.id` | String | 选择危险区画法（meteor/lightning/墙） | 通用红圈 |
| `mechanics.hint()` | String | HUD 机制状态行首段 | 退回自行拼摘要 |
| `mechanics.hazards` | Array[{x,y,r,t,dmg,player,tag}] | 危险区数量/雷击数、落点 | 只显示 hint |
| `mechanics.flags` | Dictionary | `wall_down` 追加「城墙已塌」 | 忽略 |
| `mechanics.draw_data()` | Array[{kind,x,y,r,w,h,color,alpha,label,progress,h}] | 世界渲染机制层 | 退回旧字段 hazards/wall_ring/glass_sea/meteor_warning |
| `run.covenants.draw_data()` | Array[{id,name,rarity,color,text}] | HUD 约卡牌 | 数组/字典兼容，再缺不画 |
| `run.achievements.newly` | Array[{id,name,reward:{silver,relic}}] | 结算成就提示 | 旧字段回退，再缺「本局无新增」 |
| `run.rewards.silver_run` | int | 银两明细「局内拾取」 | 0 |
| `run.rewards.meta_silver_bonus` | int | 银两明细「局外」 | 0 |
| `run.reward` / `run.won` / `run.elapsed` / `run.seal` / `run.stage_coin` | int/bool/float | 结算页复算 | 0/1.0 兜底 |
| `run.state.relic_defs()` / `run.relics` | Array | HUD 圣物图标 | 空则不画 |

## 2. 需要局内系统保证的三处（已确认 `run.gd` 当前实现）

1. **`_finish` 里 `achievements.evaluate(victory, commit)` 必须执行**，并把结果写入 `newly`；UI 结算页只读 `newly`。当前 `src/run.gd:640-641` 已满足。
2. **`reward` 的口径**：当前 `src/run.gd:635-637` 为
   `reward = round(Meta.reward_for(...) * stage_coin) + round(rewards.silver_run * stage_coin + rewards.meta_silver_bonus)`。
   UI 按「`run.reward` 已是总数」展示，只拆分不重复累加；若日后改口径，请同步本文件。
3. **`mechanics.draw_data()` 的 kind 枚举**保持 band/circle/wall/prop/hazard/pickup/overlay/vision；新增 kind 时 UI 会退化为通用红圈，不崩但样式不对，请提前在 `docs/V2-跑局接口.md` 标注。

## 3. 已修复的跨代理问题（留作回归记录）

**1）`src/systems/covenants.gd:21` 运行期 SCRIPT ERROR（当日已修复，现 0 报错）**

```
SCRIPT ERROR: Invalid access to property or key 'run' on a base object of type 'Node2D (run.gd)'.
   at: RunCovenants.setup (res://src/systems/covenants.gd:21)
   GDScript backtrace:
      [0] setup (res://src/systems/covenants.gd:21)
      [1] _ready (res://src/run.gd:251)
```

原因：`run.gd` 调 `covenants.setup(self)`，`self` 就是 `run.gd`（Node2D），没有 `.run` 属性；`setup` 里写的 `r.run.rng` 应改为 `r.rng`（或 `run.rng`）。
影响：每局报 1 条 SCRIPT ERROR，`RunCovenants` 的 rng 未播种，抽卡可能异常（elah_valley `--sim` 日志 `/tmp/ui_sim_elah_valley.log:5-9` 确认）。已同步 systems 代理，改为 `r.rng` 后复跑 elah_valley / judea_wilderness / ch07_sinai 均 0 SCRIPT ERROR。

**2）历史记录（已修复，留作回归参考）**

`covenants.gd:46` 曾出现 `GameData.covenants.keys()`（`GameData.covenants` 是 Array），导致 `run.gd` 编译失败、所有 `--sim` 直接挂起；系统侧已改为遍历条目 `c.get("id")`。**`GameData` 的 v2 表都是 Array，取 id 必须遍历条目，不能 `.keys()`**。

## 4. 对局外 / Meta 的依赖（engine-core 侧，只读调用）

- `Meta.wins / runs / seals / effectively_tier / max_tier_allowed / set_tier / tier_name / tier_enemy_* / silver_mult`
- `Meta.upgrade_def/cost/can_buy/buy/bonus`（强化页）
- `Meta.building_defs/level/next/cost/buy_building`（会幕页）
- `Meta.has_relic / has_achievement / is_awakened`
- `Meta.reward_for(victory, kills, seconds, seal)`

## 5. 可选增强（不阻塞本波）

- `Meta.is_character_unlocked(id)`：若 engine-core 未来实现，UI 的 `UIText.character_unlocked()` 会优先调用它；未实现时用「note 内成就 → 章节首通成就 → wins ≥ unlock_wins」推导。
- `RunCfg` 增加 `from_codex` 字段可让图鉴返回更稳；当前用 `CodexScreen.back_scene` 静态变量已可工作。
