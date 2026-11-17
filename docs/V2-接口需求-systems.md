# V2 接口需求 · 局内系统（systems → combat / UI）

> 来源：`src/systems/*.gd`、`src/run.gd`。这里只列「其他代理负责的文件」需要配合的点，
> 局内系统侧不会去改 `src/combat/*`、`src/sim/*`、`src/ui/*`、`src/render/*`。

## 1. weapon_runner：弹幕附加状态（五旬节 / 火舌）

现状：`RunMechanics` 在拾取火舌时只给玩家身边 160px 敌人挂【灼烧 4s + 致盲 2s】。
需要：`WeaponRunner._fire()` 生成友方弹幕时读取一个状态附加钩子，例如：

```gdscript
# GameState 上已有 set_meta/get_meta（Object 自带），局内系统会写：
state.set_meta("bullet_status_extra", "burn")
state.set_meta("bullet_status_dur", 2.0)
# weapon_runner 里 opts 增加：
"status": String(state.get_meta("bullet_status_extra", "")),
"dps": float(state.get_meta("bullet_status_dur", 2.0))
```

再配上「致盲」：ProjectileSim 的 status 只支持一个状态，建议友方弹幕用 `splash_r=0` 的情况下由 combat 侧在命中回调里补 `blind`。
接口文成后，我会把 mechanics 里的临时范围上状态删掉。

## 2. weapon_runner：音波轰城墙（耶利哥 ach_31 的第二种解法）

现状：只做了「绕跑 7 圈」。需要 `WeaponRunner._fire()` 在 `behavior == "line_projectile"` 且
`state.has_meta("jericho_wall")`（或 run 传一个回调 `run.on_sound_hit(x, y)`）时，对城墙半径 160 附近计数。
约定：`run.mechanics.counters["sound_hits"]`，满 50 次调用 `run.mechanics.collapse_wall()`。
若不想加回调，也可以由 `weapons.drain_fx()` 输出一个 `{kind:"sound_hit", x, y}`，run 在 `_drain_fx` 转发给 mechanics。

## 3. 约·初终（cov_alpha_omega）：折返弹幕

现状：只写 `state.set_meta("covenant_alpha_omega", true)` 并给直线/追踪冷却 +20%（由 covenant effects 注入 `cooldown_mult`）。
需要：`ProjectileSim.update` 在友方弹幕到达 `life` 末端时，如果 `state.get_meta("covenant_alpha_omega")` 为真，
让弹幕反向再飞一次（穿透 +1、伤害 ×0.8），最多 1 次。局内系统不改弹幕循环。

## 4. 约·大卫之座 / 七灵 / 更美之约（meta 已写，待消费）

- `covenant_david_throne`：`GameState.recompute()` 里按 `4 - weapons.size()` 叠 `area_mult` 与 `damage_mult`（每缺 1 把 +25% 范围 / +35% 伤害）。
- `covenant_seven_spirits`：受伤计算或 `_take_damage` 里按目标身上的异常种类数 `+20%/种`（需要 enemy_sim 暴露 `status_count(i)`）。
- `cov_better_promise`：`GameState.available_fusions()` 的成全门槛 ×0.6（meta 已写 `fusion_threshold_mult`）。

## 5. UI：结算页与图鉴

- 结算页读 `run.achievements.lines()`、`run.codex_unlocked`（R01：显示「已解锁图鉴」）、`run.fast_forward_available`（R04：显示可加速，先只做标记）。
- 约卡展示：`run.covenants.draw_data()` → `{id,name,rarity,color,text}`；标题 `run.covenants.title()`。
- 机关提示：`run.mechanics.hint()` 一行中文，放 HUD 底部。

## 6. 渲染：新 draw_data

见 `docs/V2-跑局接口.md` §3/§4：`mechanics.draw_data()`、`rewards.draw_data()` 的 kind 分发；
世界层还要消费 `run.vision_radius / run.light_t`（黑幕与火把照亮）。
