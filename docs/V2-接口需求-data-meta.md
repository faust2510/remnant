# V2 接口需求 · data-meta（人物局外区）

> 提出人：data-meta。涉及我名下：`data/characters.json`、`data/achievements.json`、`data/relics.json`、`data/covenants.json`。
> 下面每一条都是「数据已经写好，需要别人实现」的部分；我**没有**改任何人的文件。

## A. 给引擎代理（`src/core/game_state.gd`、`src/core/meta.gd`、`src/systems/**`）

### A1. `awakening.hook` 需要分派（20 个 id）

`game_state.gd::perf()` 目前只合并 `awakening.perk`，不读 `awakening.hook`。数据里 20 个 hook 已就位，请按 `hook.id` 分派（参数在 `hook.params`，缺省时按圣典数值）：

| hook.id | 归属 | 期望行为 |
|---|---|---|
| `aimed_crit_debuff` | 大卫 | 锁头暴击命中精英/BOSS → 眩晕 0.6s + 破甲 15% |
| `dove_heal_drop` | 挪亚 | 方舟水幕期间每 3s 向敌群投回血 10 的橄榄果 |
| `sanctify_stack_bonus` | 亚伯拉罕 | 每次祝圣永久 +12% 伤害 / +20% 拾取（本局） |
| `elite_hit_buff` | 雅各 | 受精英/BOSS 伤后 5s：暴击 +35%、抗击退 100% |
| `status_move_speed_stack` | 米利暗 | 每次震慑/活水 +3% 移速，上限 +30%，持续 4s |
| `hit_wave_damage_band` | 摩西 | 受击水波附带 45 活水伤害 + 5s 治愈水带（3 HP/s） |
| `shockwave_seventh_nova` | 约书亚 | 第 7 次移动震荡波 → 220px + 冻结 1.8s |
| `pot_shatter_flash` | 基甸 | 破陶罐 → 全屏战兢 + 35% 掉火炭 |
| `undying_rage_once` | 参孙 | 单局 1 次：HP→1 触发 5s 不死狂暴，结束全屏震爆 + 回 50% |
| `levelup_meteors` | 底波拉 | 升级降 8 颗流星（觉醒后 14 颗，锁定最高血量目标） |
| `gem_pick_drop` | 路得 | 每拾取 100 颗宝石掉 1 个回血道具 |
| `near_burn_buff` | 以利亚 | 火源 64px 内移速 +25% / 1 HP/s |
| `revive_once` | 以利沙 | 单局 1 次满血复活 + 清屏 + 10s 无限火力 |
| `wall_tower_shard` | 尼希米 | 石墙塔每秒碎石；摧毁爆 15 颗宝石 |
| `fear_damage_bonus` | 以斯帖 | 每只战兢敌人 +1% 全伤，上限 60% |
| `prayer_zone_immunity` | 但以理 | 祭圈/自身 zone 内免疫弹幕 + 25% 接触减伤 |
| `start_level_and_xp` | 施洗约翰 | 开局 Lv.3 + 前 5 分钟经验 +35% |
| `perfect_dodge_stack` | 彼得 | 每完美闪避 +8 最大 HP / +1 护甲，上限 10 次 |
| `armor_set_cooldown` | 保罗 | 集齐 3 件军装 → 冷却 -20% + 每 15s 免伤盾 |
| `extra_covenant` | 拔摩岛约翰 | 开局多选 1 张约（上限 3） |

### A2. `perk` 键表缺口（数据目前用代理值，建议加真键）

| 角色 | 圣典规则 | 现在的代理 | 建议新增键 |
|---|---|---|---|
| 以利沙 | 投射物数量 +1 | `level_heal_bonus` 0.5（只覆盖回血 ×1.5） | `projectile_count`（整数） |
| 施洗约翰 | 直线武器穿透 +4 | `crit_chance` 0.1 | `pierce_bonus`（整数） |
| 尼希米 | 护甲 +6 | `damage_taken_mult` 0.89 | `armor`（数值，可与宝物 armor 同链路） |
| 雅各 | 56px 内敌人受伤 +40% | `melee_only_bonus` 0.4 | `near_damage_bonus` + `near_radius` |
| 以斯帖 | HP<45% 时暴击 +30% | `crit_chance` 0.3（无条件，偏强） | `low_hp_crit`（阈值+值） |
| 亚伯拉罕 | 首次祝圣免火炭 + Lv.3 起 | `level_heal_bonus` 0.1 | 祭坛系统直接读 `has_character("abraham")` |
| 路得 | 经验/银两 25% 暴击翻倍 | `silver_bonus` 0.25 | 拾取系统读角色 id |
| 彼得 | 完美闪避抛聚怪渔网 | `pickup_bonus` 0.2 | 事件系统读角色 id |

> 加键后我会把代理值改回真键（属于我名下 `characters.json`，不需要你改数据）。

### A3. 成就判定

- 数据里 `cond` 有 3 个字段：`type`（契约 9 种）、`value`、`stage`（章节过滤）、`flag`（真实判定标记）。
- 期望语义：`stage` 匹配当前局 → `type` 达标 → **且** `flag` 对应事件已发生 → 发奖。未实现 `flag` 时只按 `type` 判定（会偏宽松，但不会误发高价值项）。
- 需要的计数器/事件：`perfect_dodge`（闪避成功次数）、`friendly_fire_kill`、`lightning_kill`、`water_wall_kill`、`max_burn_kill`、`trample_kill`、`furnace_inner_zone` 停留秒数、`lamps_lit`、`armor_treasures`、`smash_bread`。
- 发奖接口：`Meta.unlock_relic / unlock_character / unlock_weapon / add_silver`。`characters.json` 的 `unlock.stage`+`unlock.silver` 已是「章节前置 + 银两购买」口径，成就达成时只需放开前置（或直接 `unlock_character`）。
- `ach_33` 的 `weapon_only` 取值是 **`melee_orbit`**：判定本局只装备 `arc_melee` 与 `orbit` 两类 behavior 的武器。

### A4. 圣物 effect 语义（12 种已在数据里，需要 systems 按 id 落地）

- `R03 all_treasures` 需按 `relic.id == "R03"` 补「配色切换 + 开局无花果饼」；不要把它实现成「宝物全开」。
- `R07 silver_magnet` 需按 id 落地「狂热模式：移速 +20%、弹速 +20%、银两 +40%」。
- `R08 endless` = Boss Rush、`R10 endless` = 无尽波次，两者共用 effect，必须按 id 分支。
- `R12 chest_double` 需按 id 落地「镜像反转：地图上下翻转、敌 HP ×2、银两 ×2、+1 张约」。
- 其余 7 件（`codex` `dps_meter` `fast_forward` `covenant_system` `jukebox` `banish` `seal_shop`）语义与 effect 一致。
- **数据里没有写 `stats`**，所以不会与 `_apply_relic_effects` 双算；数值加成请只在一个地方实现。

### A5. 约 `effects` 只是数值近似

16 张约的 `text` 是圣典原规则，`effects` 是能直接结算的近似（`cov_*` 规则多为事件触发，15 个键表达不了完整语义）。建议：先按 `effects` 生效（保证手感），再按 `covenant.id` 补规则特判。特别注意 `cov_sinai`（宝物槽 -1）、`cov_david_throne`（按空槽动态加成）、`cov_alpha_omega`（`cooldown_mult` 取正 = 变慢，是代价）。

### A6. 会幕 9 属性与 21 阶

- 会幕表见 `docs/V2-数据-人物局外.md` 第 5 节（6 建筑 / 9 属性 / 逐级价格 / 满级合计 6275）。`sanctuary` 是 `max_level=3` 的例外，读表时别硬编码 5。存储建议放 `data/store.json`（不在我名下，我没动）。
- 21 阶系数表见同一文档第 6 节：`hp=1+0.09×(n-1)`、`dmg=1+0.06×(n-1)`、`rate=1+0.04×(n-1)`、`silver=1+0.30×(n-1)`（8 阶起再 `+0.25×(n-7)`）。现有 `meta.gd::seal_mult()` 是 `clamp(1,7)`，需要扩到 21，并用 `Meta.has_relic("R11")` 决定是否放开 8–21。

## B. 给武器代理

- 我引用的 17 个初始武器 id 全部已在 `data/weapons.json` 中命中：`sling` `olive_branch` `censer` `staff` `tambourine` `horn` `torch` `jawbone` `harp` `sickle` `chariot` `hammer` `scepter` `voice` `fishing_net` `spirit_blade` `menorah`。
- 成就 `note` 里引用的 W07/W08/W11/W12/W15/W18/W19 已对应到 `olive_branch`/`jawbone`/`spirit_blade`/`menorah`/`hammer`/`voice`/`fishing_net`，无需新增。
- 唯一请求：**不要改这 17 个 id**（我这边按 id 引用）。

## C. 给场景/UI 代理

- 见证人卡片：`characters[].desc` 是两行被动说明（含换行），`awakening.desc` 是一行觉醒说明，`unlock.note` 是解锁提示。
- 圣物卡片：`desc` 是功能说明，`note` 是「与圣典原规则的差距」，UI 不必显示 `note`。
- 成就卡片：`desc` 是人类可读条件；`note` 里写明了圣典解锁的见证人/武器，成就列表想显示「解锁 XX」可直接读 `note`（不建议解析）。
- 约卡片：`rarity` 1/2/3 可用于卡面配色，`text` 是一句话规则。

## D. 给数值/模拟代理

- 40 项成就银两合计 **10690**；会幕 9 属性全满 **6275**。若成就全清，玩家能一次性买满会幕还余 4415，属于圣典设定的「长线积累」，不要私自下调成就银两。
- 21 阶倍率到 21 阶是敌 HP ×2.80 / 敌伤 ×2.20 / 刷怪 ×1.80，银两 ×6.30；做平衡时按此口径，不要按「每阶 +9% 已经很大」再额外加码。
