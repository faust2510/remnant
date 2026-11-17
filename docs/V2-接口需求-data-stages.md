# V2 接口需求：关卡 / 敌人 / BOSS（data-stages → engine-core, systems, combat, ui）

> 数据侧已按契约落地：24 章 / 36 敌（24 普通 + 12 精英）/ 24 BOSS 三阶段。下面 7 条是需要别人配合的地方，按「谁改、改哪、为什么」列。
> 现状校验：python3 /tmp/check_v2_data.py → ALL CHECKS PASSED；Godot 4.7.1 headless 装载 → === STAGES LOAD CHECK done: fail=0 ===（stages=24 enemies=36 bosses=24，stage.boss 全部命中 bosses.json）。

## 1. systems：关底 BOSS 现在还生成不出来（最高优先级）

src/run.gd:736-742 仍是旧写法：

    if not boss_spawned and elapsed >= float(stage.get("boss_at", 690)):
        boss_spawned = true
        var bti: int = enemies.type_index_of(String(stage.get("boss", "goliath")))
        if bti >= 0:
            _spawn_at_ring(bti, 150.0, 175.0)

而 goliath / the_tempter 已按契约 §9 迁到 data/bosses.json（enemies.json 里不再有 BOSS），GameData.enemies 只装 enemies.json，所以 bti 恒为 -1：**24 章全部没有关底 BOSS，而且没有任何报错**（静默跳过，最容易漏）。

src/core/game_data.gd:59-60 已装载 bosses 表，boss_def(id)（:74-75）可直接用。两种接法选一：

- **A（推荐，不动敌人表）**：bd = GameData.boss_def(String(stage.get("boss","")))，用 bd 的 hp/speed/damage/radius/xp/color 生成 BOSS 实体，行为按 behavior:"boss"（src/sim/enemy_sim.gd:131 的判据）。BOSS 不在 mix 类型表里，需要 EnemySim 支持"临时类型 / 覆盖数值"的 spawn。
- **B（一行都不用改 run.gd）**：GameData.reload() 里把 bosses 合并进 enemies 表。bosses.json 每条已带 behavior:"boss" 与 tier:"boss"，结构与旧 goliath 兼容。代价是类型表变成 60 条、语义变混。

## 2. combat / systems：三阶段数据还没有人消费

data/bosses.json 每位 BOSS 的结构：

    "phases": [{"at_hp": 1.0, "skills": [...]}, {"at_hp": 0.66, "skills": [...]}, {"at_hp": 0.33, "skills": [...]}]

语义：at_hp = 剩余 HP 比例首次降到该值以下时切入该阶段（1.0 为开场）；skills[].cd 单位秒；skills[].params 直接并入技能参数。24 位共 148 个技能槽（2/2/2，终章 3/4/3）。

src/sim/boss_ai.gd（combat 名下）需要的落地顺序建议：

1. ring_burst / aimed_shot / charge / nova / summon —— 直接走 projectile_sim 与 EnemySim 现有能力；
2. zone_denial（预警圈）/ spawn_totem（柱、图腾）/ heal_self —— 需要新实体或计时器，契约里是 8 种技能里的 3 种，不能只做前 5 种就宣布完成；
3. 阶段切换时给一次镜头震动 + 换色即可（可选，但三个阶段的差异玩家要看得出来）。

## 3. combat：behavior 枚举里多了 chaser

src/sim/enemy_sim.gd:202 的默认值是 "chase"，match 里没有 "chaser" 分支，所以它落到 _ 默认追击（行为等价）。契约 §7 的枚举写的是 chaser，36 条敌人全部写 chaser。建议把 match 显式加一条 "chaser"（或把默认分支注释成 chaser）——现在等价，等你们以后加新分支时它会静默错位。

## 4. systems：elites 的 n 与 count 是双写

stages.json 每条精英同时写 "n"（契约 §8）与 "count"（src/run.gd:729 现在读的旧键），两值恒等（24 章共 96 条）。建议 run.gd 改读 n，count 保留一个版本后由我从数据里删——**迁移期两边都别删**，否则会有一边读到默认值 1。

## 5. systems：mods 20+ 个键只有 3 个生效

已接线：enemy_speed / shillings / cooldown（src/run.gd:146-149）。budget 已接线（src/run.gd:674-678）。ground 的 base/speckle/rocks 已接线（src/render/world_renderer.gd:29-48，zone 未用）。

未接线但有语义的键：heal_per_sec、area、enemy_projectile_speed、elite_xp、status_duration、knockback、crit_damage、dot_damage、fear_damage、melee_damage、pierce_bonus、heal_mult、fire_resist、xp_gain、dodge_cooldown、sanctified_damage、armor_bonus、pickup_radius、max_alive_bonus、all_stats、fusion_kills_bonus。

逐键语义见 docs/V2-数据-关卡敌人.md 第 7 节。建议二选一：按表接线；或在 run.gd 里对 stage.mods 的未实现键打一次 push_warning，避免"数据写了、玩家完全感觉不到"。**同一章的 mechanic_id 也是数据，行为同样要 sim 实现**（24 个 mechanic 目前全部没有代码分支）。

## 6. ui / systems：unlock_wins = 章号-1 会让老存档丢进度

unlock_wins 按章节顺序取 0..23（第 1 章 0，第 24 章 23）。src/camp_screen.gd:86 用它和 Meta.wins 比较。老存档如果 wins 只有 3，第 4..24 章会一起锁住；更要紧的是 elah_valley 从"第 2 章就是下一关"变成了"第 13 章、需要 12 胜"。

两种修法，请定一个：

- 存档迁移：按已经通关的最高章回填 wins = max(wins, chapter - 1)；
- 数据侧放宽：我把 unlock_wins 改成 min(chapter-1, 5) 之类的早期宽松曲线（一条 sed 就改完，等你们说）。

定之前请在选关/营地画面上做一次「新档 + 老档」目视验证，这是玩家第一眼会看到的东西。

## 7. ui：BOSS 名牌 / 血条取名字的地方

HUD 现在靠 GameData.enemies 的类型表取 name/color；BOSS 迁出后（见第 1 条）需要改从 GameData.boss_def(id) 取。24 个 BOSS 的中文名、颜色、HP、移速、伤害都在 docs/V2-数据-关卡敌人.md 第 5 节，可直接对表验收。
