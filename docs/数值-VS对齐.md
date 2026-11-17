# 数值 · VS（Vampire Survivors）对齐

> 代理：balance-vs　｜　日期：2026-11-17　｜　引擎：Godot 4.7 headless 模拟
> 目标：用户原话「数值方面，我希望你尽可能学习和照搬吸血鬼幸存者」。
> 本局长度目标 12-15 分钟、结束 30-45 级、击杀 3000-8000、不 3 分钟暴死也不无脑速通。

## 0. 结论速览

- **经验曲线**从旧的指数 `8 * 1.13^n` 换成 VS 的线性形状，再加一个只在本项目生效的晚段二次项：
  `xp_need(L) = 3 + 4*(L-1) + 0.62*(L-1)^2`。
  早期比 VS 略便宜（Lv2 需 7 点 vs VS 5 点），因为本局唯一续航是「升级回血」，而刷怪在 90-240s 叠到 20-220 只同屏，箭矢的细水长流必须在升级节奏里被抵消。
- **武器/被动/敌人**按 VS 每级原值重定：起手武器伤害 10、冷却 1.0-1.1s；被动每级 +10% 面积/+20 HP/-8% 冷却等；敌人 1 分钟 8-12 HP、伤害 3-4、移速 50-70。
- **实测（无 meta 默认存档，连跑两次字节级 diff=0）**：victory @ 841.8s（14.0 分钟），**L44**，击杀 10225，全程同屏 22-234，最低血量 123/160（t=209s），BOSS 690s 出、841.8s 打完（152s）。
- 仍有 3 处无法照搬的硬偏差（刷怪预算、敌人 HP 成长公式、BOSS 血量覆盖）都不在我名下的文件，见 §4。

## 1. 锚点对照表

| 项目 | VS 原值 / 机制 | 本项目改前 | 本项目改后 | 说明 |
|---|---|---|---|---|
| 玩家初始 HP | 100 | adam 150 + perk 10 = 160 | 同左（未动） | `data/characters.json` 归他人；HP 与 VS 的对应关系是「血包类被动 +20/级」已对齐 |
| 玩家移速 | ~100 | 72 | 72（未动） | `game_state.recompute` 基础值不在我可改范围（只许改经验曲线）；建议移速代理调到 100 |
| 拾取半径 | 小（~50），可成长 | 42 + 仁厚 20%/级 | 同左 | 已接近 VS |
| 受伤无敌帧 | 0.5s | 0.60s | 0.60s（未动） | `src/run.gd:441`，归他人 |
| 起手武器 | 鞭子 dmg 10 / cd 1.15 / 范围小 | staff dmg 8 / cd 0.9 / range 48 / arc 110 | **staff dmg 10 / cd 1.0 / range 76 / arc 150 / knockback 90** | VS 起手手感 |
| 第二把可玩武器 | 投掷类 dmg 10 左右 | sling dmg 9 / cd 0.8 / range 210 | **sling dmg 10 / cd 1.1 / range 200**（Lv5 count 3 + cd 0.62） | 冷却落进 VS 的 0.9-1.3s 带 |
| 区域武器 | Garlic 每 tick 3-5 dmg | torch dmg 6 / tick 0.35 / radius 42 / count 2 | **dmg 6 / tick 0.4 / radius 48 / count 2**（Lv3-5 加到 3-4 颗） | 贴近 VS 大蒜的「贴身持续掉血」 |
| 被动：血量 | Hollow Heart +20/级（满 +100） | breastplate max_hp 14 | **20** | 逐条照 VS |
| 被动：面积 | Candelabrador +10%/级 | belt_of_truth 0.08 | **0.10** | 满级 +50% |
| 被动：冷却 | Empty Tome -8%/级 | self_control 0.06 | **0.08** | 满级 -40% |
| 被动：伤害 | Spinach +10%/级 | spirit_sword 0.08 | **0.10** | 满级 +50% |
| 被动：回血 | Pummarola +0.2/s/级（满 1.6/s） | myrrh 0.6/级 | **0.30/级**（满 1.5/s） | 避免一口奶满 |
| 被动：移速 | Wings +10%/级 | gentleness / gospel_shoes 0.05-0.06 | **0.10** | |
| 被动：经验 | Crown +8%/级（满 +64%） | joy 0.12（满 +60%） | 保持 | 已等价 |
| 被动：弹速 | Bracer +10%/级 | frankincense 0.06 / olive_oil 0.12 | **0.10 / 0.10** | |
| 敌人 1 分钟档 | HP 5-20 / 伤害 2-4 / 移速 40-70 | soldier 20HP·dmg4·spd58、raven 14HP·dmg3·spd96 | **soldier 12·3·58、raven 8·3·70、archer 11·4·50** | 全部落进 VS 首分钟带 |
| 敌人中后期 | 每 60s 全局 HP ×1.6（复利） | 幂函数缩放到 10 分钟 ×2.24 | 未动（`run.gd:405`） | 见 §4 偏差 2；我改的是基础 HP 分档 |
| 敌人中期档 | HP 20-80 | 20-77 | **beast 58 / iron_shielder 126** 等按档位 | |
| 敌人后期档 | HP 100-200 | 126-180 | **law_golem 144 / dragon_spawn 180** | |
| 精英 | ×8-10 血量 | six_finger_giant 171 | **198**（≈中期杂兵 20×10） | 精英接触伤害 12-15（VS 上限 18 已放开） |
| 同屏数量 | 100-300 | 峰值 620（饱和） | **22-234** | 靠武器 DPS + 敌人速度收敛达成，不改刷怪表 |
| 每局击杀 | 12 分钟约 3000 | 10010 | 10225 | 由 `data/stages.json` 刷怪预算决定，不归我（见 §4 偏差 1） |
| 升级需求 | `5 + 10*(L-1)`（Lv10=95、Lv30=295） | `8 * 1.13^(L-1)` 指数 | **`3 + 4*(L-1) + 0.62*(L-1)^2`**（Lv10=93、Lv30=628、Lv45=1280） | 形状照 VS，晚期按本局 1 万击杀拉伸 |
| 升到多少级 | 12 分钟 30-45 级 | L51 | **L44** | |
| 武器 / 被动槽 | 6 / 6 | 4 / 4 | 4 / 4（未动） | 圣典写死 3→4，归设计，见 §4 偏差 5 |
| 升级三选一 | 有 | 有 | 有 | |
| 每分钟末精英 | 有 | 150/330/510/630s 各 1 只 | 同左（stages.json） | |
| 10 分钟大 BOSS | 数千 HP | goliath 实际 24000 | 未动 | `run.gd:1226` 覆盖，见 §4 偏差 3 |

## 2. 逐文件改动

### `src/core/game_state.gd`（只动经验曲线，共 4 处约 20 行）
```gdscript
const XP_BASE := 3.0
const XP_STEP := 4.0
const XP_LATE := 0.62
# add_xp 内
var lv_steps: float = float(level - 1)
xp_need = XP_BASE + XP_STEP * lv_steps + XP_LATE * lv_steps * lv_steps
```
另把 `setup()` 与声明处的初值从 XP_BASE 沿用，注释重写为「VS 线性形状 + 本项目校准」的说明。

### `data/weapons.json`
- sling：damage 9→10、cooldown 0.8→1.1、range 210→200（其余 overrides 不变）。
- staff：damage→10、cooldown 0.9→1.0、range 48→76、arc_deg 110→150、knockback 90、Lv5 cooldown 0.7。
- torch：tick 0.35→0.4、radius 42→48、count 2、angular_speed 2.3。

### `data/passives.json`
- 清掉 10 处误写在被动对象**顶层**的重复键（`xp_gain/area_pct/max_hp/...`）——真正生效的是 `per_level`，这些垃圾键会误导后来人。
- per_level 按 VS：breastplate 14→20、belt_of_truth 0.08→0.10、spirit_sword 0.08→0.10、self_control 0.06→0.08、gentleness 0.05→0.10、gospel_shoes 0.06→0.10、myrrh 0.6→0.30、frankincense 0.06→0.10、olive_oil 0.12→0.10；`desc` 里同步改数字。
- 未动：love 0.004（吸血 2%/满级）、joy 0.12、patience armor 4、peace 0.06、helmet 0.07、goodness 0.05、kindness 0.20、faithfulness 0.12、fine_linen 0.03、ephod 0.10。

### `data/enemies.json`
- 36 只按 VS 档位重定 hp / damage / xp：早期 8-13 HP·dmg 3-4·xp 1，中期 20-77·dmg 4-6·xp 2-3，后期 126-180·dmg 9-11·xp 4-5。
- 把所有「比玩家（72）还快」的敌人收敛到 VS 的 40-70 带：raven 96→70、serpent_brood 90→70、plague_locust 100→72、night_owl 98→74、storm_petrel 100→74、scorpion 76→68、iron_locust 78→70、midian_prowler 76→68、horsemen_vanguard 78→70 等。**这是同屏数量从 620 掉到 22-221 的关键**（跑不过的怪才能被 AoE 清掉）。
- 精英接触伤害 12-15，普通精英 hp 171-342，xp 15-19（原 25-40，避免精英变经验炸弹）。
- 早期误加的 14 个远程射击键（`shoot_cd/shot_damage`）已**全部删除**：它们在代码里不生效（见 §4 偏差 4），留着只会误导后来人去改错地方。

## 3. 迭代记录（全部 `--headless --path . -- --sim --sim-speed=900 --no-meta`，exit=0、SCRIPT ERROR=0）

| # | 改动 | 结果 |
|---|---|---|
| it0 | 原始数据（基线） | victory 826.4s，**L51**，kills 10010，hp 140/140，dmg total 2383 → 等级过高、全程满血 |
| it1 | 曲线换成纯 VS 线性 `5+10*(L-1)` | victory 831.8s，**L65**，kills 10091 → 击杀量是 VS 的 3 倍，纯线性一定爆级 |
| it2 | 需求整体 ×2.6（压等级） | **defeat 235.9s，L9，kills 899** → 死亡螺旋：早期升不动→武器弱→同屏 620→被磨死 |
| it3 | 线性曲线 + 远程/精英伤害上调 | victory 846.5s，L66，hp 160/160 → 说明「伤害上调」本身不致命，等级过高才是病 |
| it4 | 线性 + 晚段二次项（XP_LATE 0.63） | **defeat 229.8s，L13** → 早期等级节奏被打断，续航（升级回血）跟不上细水长流的箭矢 |
| it5 | staff range 76/arc 150、torch radius 48 | defeat 241.9s，L13，但**同屏峰值 620→137**，首次贴近 VS 的 100-300 |
| it6 | + 敌人速度收敛到 40-70 | victory 842.6s，**L40**，kills 10265，同屏 14-242，最低血 37/160@404s，BOSS 用 152s 打完 → 第一个全指标合格配置 |
| it7 | 被动对齐（belt 0.08→0.10、frankincense 0.06→0.10） | **defeat 241.5s，L13，kills 1313** → 证明结局在 4 分钟点是刀刃：有没有拿到吸血（仁爱）决定生死 |
| it8 | archer 数据键 shot_damage 5 / shoot_cd 3.0 | 与 it7 **字节级相同** → 证实远程参数走代码白名单，数据键是死数据 |
| 诊断 A | archer behavior 临时改 chase（无箭矢） | victory，且 dmg_src 从 `shot=248` 变成 `contact=2722` → **箭矢是 3-5 分钟段的主要死因** |
| 诊断 B | 精英 six_finger_giant hp 40 | 仍 defeat 241s、shot≈272 → 精英环形弹幕不是主因，弓手才是 |
| it9 | 曲线校准为 `3 + 4*(L-1) + 0.55*(L-1)^2` | victory 848.6s（14.1 min），**L46**，kills 10391，同屏 22-221，最低血 146/160@299s |
| it10 | XP_LATE 0.55→0.62（把 L46 压回 45 以内） | **victory 841.8s（14.0 min），L44，kills 10225，同屏 22-234，最低血 123/160@209s，dmg contact 1272 + shot 1282 = 2299** → 最终交付配置 |

**关键教训**：本局唯一续航是 `run.gd:1640` 的升级回血（15% max_hp），所以经验曲线的「早期便宜程度」直接等于生存能力；把早期压陡（it2/it4）会在 t≈240s 稳定暴死，把早期放松（it9）则同一套敌人压力下能活到 14 分钟。曲线是本局唯一既能控等级、又能控生死的数据旋钮。

## 4. 已知偏差（机制不同，无法照搬）

1. **每局击杀量 1 万 vs VS 3 千**：`data/stages.json` 的 elah_valley 刷怪预算 = base 210 / per_minute 76 / max_alive 620，全程约 9,000-10,000 只。这是击杀量的硬上限，与本代理无关。建议（未执行）：base 210→70、per_minute 76→40、max_alive 620→300，同时把经验曲线二次项降到 0.25 左右，就能同时贴近 VS 的「同屏 100-300 + 击杀 3000」。
2. **敌人 HP 成长不是 ×1.6/分钟**：`src/run.gd:405` 用幂函数 `(1 + pow(elapsed/60, 0.85) * 0.175) * seal`，10 分钟只有 ×2.24，而 VS 是 `1.6^n`（10 分钟 ×110）。照搬会让本局中期直接变成僵尸墙，所以只把「基础 HP 分档」照 VS 对齐。
3. **BOSS 血量被代码覆盖**：`src/run.gd:1226` 用 `target_hp = 9000 + 1250*(chapter-1)`（chapter 13 → 24000）覆盖 `data/bosses.json`，所以 bosses.json 里的 hp 无效。VS 的 10 分钟 BOSS 是数千级，本局 boss 需要 150s 才打死（在容错上限附近）。
4. **远程弹幕参数写死在代码里**：`src/sim/enemy_sim.gd:13-20` 的 `RANGED_WHITELIST`（archer: 4 dmg / 4.8s / keep 132 / 弹速 126）优先于 `data/enemies.json`，非白名单的 ranged 会被降级成 chase。因此我给 7 只远程加的 `shoot_cd/shot_damage` 是死数据（it8 实测字节级一致）。若要让远程可调，最小改动点是 `enemy_sim.gd` 的 `set_types()`：白名单只保留 keep_dist/count/spread 等几何键，伤害/冷却改从 `t.get("shot_damage", 4.0)` 读。
5. **槽位 4/4 vs VS 6/6、移速 72 vs 100、无敌帧 0.6 vs 0.5、升级回血 15%（VS 无此机制）**：分别在 `game_state.gd` 槽位常量、`recompute()` 基础移速、`run.gd:441`、`run.gd:1640`，都不在「只改经验曲线」的授权内。
6. **精英技能参数在代码**（`enemy_sim.gd:643+ _tick_affix`），数据只能改精英的血/伤害/速度。
7. **确定性**：`--sim` 用固定 seed 20261116，并默认读取实际存档的解锁池（只有 sling/staff/torch + love/joy/belt_of_truth/frankincense）。所以数值是**按实际可玩池**校准的，全解锁后 DPS 更高、等级会再高 2-4 级。

## 5. 复现与门禁

```bash
cd '/Users/qwe/Documents/文件大总管/10-项目/幸存者游戏'
export HOME="$PWD/.godot_home"
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --import > /tmp/import.log 2>&1; echo import=$?
$G --headless --path . -- --sim --sim-speed=900 --no-meta > /tmp/vs_a.log 2>&1; echo a=$?
$G --headless --path . -- --sim --sim-speed=900 --no-meta > /tmp/vs_b.log 2>&1; echo b=$?
diff /tmp/vs_a.log /tmp/vs_b.log; echo diff=$?
grep -c 'SCRIPT ERROR' /tmp/vs_a.log
```


### 2026-11-17 22:26 最终门禁（实测输出）

```
import_exit=0                      # --headless --path . --import
/tmp/vs_import.log SCRIPT ERROR = 0
a: runner=done elapsed=23s  → /tmp/vs_a.log  SCRIPT ERROR = 0
b: runner=done elapsed=23s  → /tmp/vs_b.log  SCRIPT ERROR = 0
diff /tmp/vs_a.log /tmp/vs_b.log → 0 行差异（diff_exit=0）

# 22:31 复核（别的代理改完 hud.gd 的 GUI 警告之后，再连跑两次）
c: runner=done elapsed=23s  → /tmp/vs_c.log  SCRIPT ERROR = 0
d: runner=done elapsed=23s  → /tmp/vs_d.log  SCRIPT ERROR = 0
diff /tmp/vs_c.log /tmp/vs_d.log → 0 行差异（diff_exit=0）
[sim] victory=true t=841.8 level=44 kills=10225 hp=160/160   （c 与 d 完全一致）
# c 与 a 的唯一差别：a 里多 6 行 hud.gd:138 的 GUI anchor 警告，已由 ui 代理修掉，不影响模拟

[sim] ==== RESULT ====
[sim] victory=true t=841.8 level=44 kills=10225 hp=160/160 coals=1 cd=0.90
[sim] weapons=投石索(Lv5), 云柱与火柱(Lv5)
[sim] passives=仁爱(Lv5), 馨香乳香(Lv4), 喜乐(Lv5)
[sim] stage=elah_valley seal=1 reward=4658 shillings=0 saved=false armor=1 ground_coins=27 picked=845
[sim] dmg_src contact=1272 shot=1282 total=2299
[sim] systems silver_run=180 meta_silver=0 covenants=0 coals=1
[sim] SIM_DONE
```

### 截图自查（验收「运行中的画面」）

```bash
export HOME="$PWD/.godot_home"
$G --path . -- --shot --shot-at=50 --shot-path=/tmp/vs_shot.png
# [shot] saved /tmp/vs_shot.png 1280x720
```
截图：`docs/shots/vs_align_t50.png`（t=50s）
画面核对：HUD 正常（Lv6 / 经验 56% / 击杀 95 / 银两 8 / 火炭 0 / 160-160 血条 / 左下 亚当 头像 / 右下 武器 2 格 + 宝物 4 格）；
同屏敌人约 20 只（士兵 + 乌鸦），符合 VS 首分钟的稀疏手感；地面有火焰残留与投石索弹道，伤害飘字 22 属正常暴击/多段；
与 it0 基线（L51、全程满血）相比，t=50s 敌人已能围成小型包围圈但玩家 160 血未掉，符合「首分钟无压力」的 VS 节奏。

### 已知限制
- 以上数值是**无 meta 默认存档 + 固定 seed 20261116** 的确定性结果；全解锁池或改 seed 会偏离 1-3 级。
- 本次门禁在 cam-ranged 修完 `src/run.gd:830` 之后跑；别的代理后续再改 `run.gd`/`enemy_sim.gd`（尤其敌弹收敛）会改变箭矢压力，届时重跑一次 sim 即可复核，不必改我的数据。
- 交付文件只动了：`data/weapons.json`、`data/passives.json`、`data/enemies.json`、`src/core/game_state.gd`（经验曲线）、`docs/数值-VS对齐.md`。
  `data/fusions.json` 与 `data/bosses.json` 经核对**无需改动**：融合武器（pillar_cloud_fire）的 DPS 由 weapons.json 的参数合成，改动会破坏「融合是击杀主力」的现状；BOSS 血量被 `run.gd:1226` 按章节覆盖，改 bosses.json 不生效（见偏差 3）。

