extends Node
## 局外存档：舍客勒、营地永久强化、圣物、成就、会幕 6 建筑、灾变阶（1–21）、见证人觉醒。
## 存档位置 user://save.json（本机 = .godot_home/Library/Application Support/Godot/app_userdata/...）。
## 兼容铁律：v2 新增键全部带安全默认值，老存档（只有 v1 的十个键）照常读入，读不到就用默认。

const SAVE_PATH := "user://save.json"
## 七印/七号/七碗：每阶增量（run.gd 与营地面板共用，改这里即可）
const SEAL_HP := 0.09
const SEAL_DMG := 0.06
const SEAL_RATE := 0.04
const SAVE_VERSION := 2

## ---- 21 阶灾变（七印 1–7 / 七号 8–14 / 七碗 15–21）----
const TIER_MAX := 21
const TIER_SEAL_END := 7
## 银两倍率：1 阶 = 1.00（与旧 1 印完全一致）
const SEAL_MULT_STEP := 0.3
## 21 阶 = 3.20（设计圣典：终局银两倍率约为七印顶端的 3.2 倍）
const SEAL_MULT_TOP := 3.2
## 突破七印上限所需的圣物（R11《七印封印》）。id 兼容两种写法。
const TIER_GATE_RELICS: Array = ["seven_seals_scroll", "R11"]

## 营地强化表。每级 line 是给 recompute() 的增量，key 与 GameState.stats 对齐。
## 第 2 波的 UI/系统若要加「信心 faith / 祈祷 prayer / 恩膏重随 sanctuary」，
## 数值在 data/store.json 的 upgrades 里（live=false），加进来时记得同步 bonus()。
const UPGRADES: Array = [
	{ "id": "might", "name": "刚强", "desc": "全伤害 +4% / 级", "base": 50, "step": 35, "max": 5 },
	{ "id": "vitality", "name": "壮胆", "desc": "生命上限 +12 / 级", "base": 45, "step": 30, "max": 5 },
	{ "id": "swift", "name": "快跑", "desc": "移动速度 +3% / 级", "base": 40, "step": 30, "max": 5 },
	{ "id": "grace", "name": "恩典", "desc": "拾取范围 +10% / 级", "base": 35, "step": 25, "max": 5 },
	{ "id": "wisdom", "name": "智慧", "desc": "经验获取 +5% / 级", "base": 55, "step": 40, "max": 5 },
	{ "id": "mercy", "name": "怜恤", "desc": "领受回血 +3% / 级", "base": 60, "step": 45, "max": 5 }
]

## 21 阶名称兜底（store.json 缺失时用；正常情况读 data/store.json 的 tiers）
const TIER_NAMES: Array = [
	"一印 · 白马", "二印 · 红马", "三印 · 黑马", "四印 · 灰马",
	"五印 · 祭坛下的呼声", "六印 · 天震", "七印 · 寂静",
	"八号 · 火雹带血", "九号 · 火烧大山入海", "十号 · 苦水茵陈",
	"十一号 · 日月三分暗", "十二号 · 无底坑蝗灾", "十三号 · 伯拉大河马军", "十四号 · 天上大声音",
	"十五碗 · 恶毒生疮", "十六碗 · 海变死血", "十七碗 · 江河变血", "十八碗 · 日头烤人",
	"十九碗 · 兽座黑暗", "二十碗 · 伯拉河干涸", "二十一 · 成了"
]

## 存档字段（老存档里没有的都走默认值）
var shillings: int = 0
var levels: Dictionary = {}
var seals: int = 1
var selected_seal: int = 1
var stage_id: String = "elah_valley"
var runs: int = 0
var wins: int = 0
var best_kills: int = 0
var best_time: float = 0.0
var lifetime_kills: int = 0
# ---- v2 ----
## 当前灾变阶 1–21。≤7 时与 selected_seal 等价（营地面板仍可只写 selected_seal）。
var tier: int = 1
## 已解锁圣物 id（Meta 权威；GameState.relics 是局内只读镜像）
var relics: Array = []
## 已完成成就 id
var achievements: Array = []
## 会幕 6 建筑等级 {建筑 id: 0..5}，由所属强化等级派生
var buildings: Dictionary = {}
## 已觉醒见证人 id（3 印通关点亮）
var awakened_ids: Array = []

func _ready() -> void:
	load_save()

# ---------------------------------------------------------------- 存档

func load_save() -> void:
	levels = {}
	for u in UPGRADES:
		levels[String(u["id"])] = 0
	# v2 字段先给默认值：老存档没有这些键时也必须是干净的初值
	relics = []
	achievements = []
	awakened_ids = []
	buildings = {}
	tier = 1
	if not FileAccess.file_exists(SAVE_PATH):
		_sync_buildings()
		tier = selected_seal
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		_sync_buildings()
		return
	var txt: String = f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		_sync_buildings()
		return
	shillings = int(data.get("shillings", 0))
	runs = int(data.get("runs", 0))
	wins = int(data.get("wins", 0))
	best_kills = int(data.get("best_kills", 0))
	best_time = float(data.get("best_time", 0.0))
	lifetime_kills = int(data.get("lifetime_kills", 0))
	seals = clampi(int(data.get("seals", 1)), 1, TIER_MAX)
	selected_seal = clampi(int(data.get("selected_seal", 1)), 1, seals)
	stage_id = String(data.get("stage_id", "elah_valley"))
	var lv: Dictionary = data.get("levels", {})
	if typeof(lv) != TYPE_DICTIONARY:
		lv = {}
	for u in UPGRADES:
		var id: String = String(u["id"])
		levels[id] = clampi(int(lv.get(id, 0)), 0, int(u["max"]))

	# ---- v2 键：缺省安全默认；有则严格收窄 ----
	relics = _str_array(data.get("relics", []))
	achievements = _str_array(data.get("achievements", []))
	awakened_ids = _str_array(data.get("awakened_ids", []))
	var bd: Variant = data.get("buildings", {})
	if typeof(bd) == TYPE_DICTIONARY:
		for k in bd.keys():
			buildings[String(k)] = clampi(int(bd[k]), 0, 5)
	# 老存档没有 buildings 键：按已买强化等级推一次
	_sync_buildings()
	# 老存档没有 tier 键：等值迁移成 selected_seal（1–7 语义不变）
	tier = clampi(int(data.get("tier", selected_seal)), 1, TIER_MAX)

func save_save() -> void:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"shillings": shillings,
		"levels": levels,
		"seals": seals,
		"selected_seal": selected_seal,
		"stage_id": stage_id,
		"runs": runs,
		"wins": wins,
		"best_kills": best_kills,
		"best_time": best_time,
		"lifetime_kills": lifetime_kills,
		"tier": tier,
		"relics": relics,
		"achievements": achievements,
		"buildings": buildings,
		"awakened_ids": awakened_ids
	}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("save failed: " + str(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()

func _str_array(v: Variant) -> Array:
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for x in v:
		var s: String = String(x)
		if not s.is_empty() and not out.has(s):
			out.append(s)
	return out

# ---------------------------------------------------------------- 强化

func level_of(id: String) -> int:
	return int(levels.get(id, 0))

func upgrade_def(id: String) -> Dictionary:
	for u in UPGRADES:
		if String(u["id"]) == id:
			return u
	return {}

func upgrade_cost(id: String) -> int:
	var d: Dictionary = upgrade_def(id)
	if d.is_empty():
		return 0
	var lv: int = level_of(id)
	if lv >= int(d["max"]):
		return 0
	return int(d["base"]) + int(d["step"]) * lv

func can_buy(id: String) -> bool:
	var d: Dictionary = upgrade_def(id)
	if d.is_empty() or level_of(id) >= int(d["max"]):
		return false
	return shillings >= upgrade_cost(id)

func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	shillings -= upgrade_cost(id)
	levels[id] = level_of(id) + 1
	_sync_buildings()
	save_save()
	return true

## 汇总成 GameState 能直接吃的加成。
func bonus() -> Dictionary:
	return {
		"damage_mult": 0.04 * float(level_of("might")),
		"max_hp": 12.0 * float(level_of("vitality")),
		"speed_pct": 0.03 * float(level_of("swift")),
		"pickup_pct": 0.10 * float(level_of("grace")),
		"xp_gain": 0.05 * float(level_of("wisdom")),
		"level_heal": 0.03 * float(level_of("mercy"))
	}

# ---------------------------------------------------------------- 会幕 6 建筑

## 建筑定义来自 data/store.json；缺失时返回空数组（调用方要能接受）。
func building_defs() -> Array:
	var arr: Variant = GameData.store_buildings()
	if typeof(arr) != TYPE_ARRAY:
		return []
	return arr

func building_def(id: String) -> Dictionary:
	for b in building_defs():
		if typeof(b) == TYPE_DICTIONARY and String(b.get("id", "")) == id:
			return b
	return {}

## 建筑等级 = 其所属强化里最高的那一级（圣典里建筑就是强化的分组）。
## 每次买入 / 读档都会重算，所以老存档也能立刻显示正确的建筑等级。
func _sync_buildings() -> void:
	for b in building_defs():
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var bid: String = String(b.get("id", ""))
		if bid.is_empty():
			continue
		var lv: int = 0
		var ups: Variant = b.get("upgrades", [])
		if typeof(ups) == TYPE_ARRAY:
			for uid in ups:
				lv = maxi(lv, level_of(String(uid)))
		buildings[bid] = maxi(int(buildings.get(bid, 0)), lv)

func building_level(id: String) -> int:
	var best: int = int(buildings.get(id, 0))
	var ups: Variant = building_def(id).get("upgrades", [])
	if typeof(ups) == TYPE_ARRAY:
		for uid in ups:
			best = maxi(best, level_of(String(uid)))
	return best

## 该建筑下一笔可买的强化 id（买得起买不起都返回；全满级返回空串）
func building_next(id: String) -> String:
	var ups: Variant = building_def(id).get("upgrades", [])
	if typeof(ups) != TYPE_ARRAY:
		return ""
	var best_id: String = ""
	var best_cost: int = 1 << 30
	for uid in ups:
		var u: Dictionary = upgrade_def(String(uid))
		if u.is_empty():
			continue
		if level_of(String(uid)) >= int(u["max"]):
			continue
		var c: int = upgrade_cost(String(uid))
		if c > 0 and c < best_cost:
			best_cost = c
			best_id = String(uid)
	return best_id

func building_cost(id: String) -> int:
	var nid: String = building_next(id)
	if nid.is_empty():
		return 0
	return upgrade_cost(nid)

## 买该建筑下一级。upgrade_id 非空时精确买某一项。
func buy_building(id: String, upgrade_id: String = "") -> bool:
	var nid: String = upgrade_id
	if nid.is_empty():
		nid = building_next(id)
	if nid.is_empty():
		return false
	var ok: bool = buy(nid)
	if ok:
		_sync_buildings()
		save_save()
	return ok

# ---------------------------------------------------------------- 圣物 / 成就 / 觉醒

func unlock_relic(id: String) -> bool:
	if id.is_empty() or relics.has(id):
		return false
	relics.append(id)
	save_save()
	return true

func has_relic(id: String) -> bool:
	return relics.has(id)

func grant_achievement(id: String) -> bool:
	if id.is_empty() or achievements.has(id):
		return false
	achievements.append(id)
	save_save()
	return true

func has_achievement(id: String) -> bool:
	return achievements.has(id)

func is_awakened(cid: String) -> bool:
	if cid.is_empty():
		return false
	return awakened_ids.has(cid)

func set_awakened(cid: String, value: bool = true) -> void:
	if cid.is_empty():
		return
	var has_it: bool = awakened_ids.has(cid)
	if value == has_it:
		return
	if value:
		awakened_ids.append(cid)
	else:
		awakened_ids.erase(cid)
	save_save()

# ---------------------------------------------------------------- 21 阶灾变

## 当前生效的阶：>7 时以 tier 为准；1–7 仍以 selected_seal 为准
## （营地面板直接写 selected_seal，不能让它读到过期的 tier）。
func effective_tier() -> int:
	if tier > TIER_SEAL_END:
		return clampi(tier, 1, TIER_MAX)
	return clampi(selected_seal, 1, TIER_MAX)

func set_tier(t: int) -> void:
	tier = clampi(t, 1, TIER_MAX)
	if tier <= TIER_SEAL_END:
		selected_seal = clampi(tier, 1, maxi(seals, 1))
	save_save()

## 能选到第几阶：默认七印；持有 R11《七印封印》后开放到 21。
func max_tier_allowed() -> int:
	for r in TIER_GATE_RELICS:
		if has_relic(String(r)):
			return TIER_MAX
	return TIER_SEAL_END

func tier_row(t: int = -1) -> Dictionary:
	var n: int = effective_tier() if t <= 0 else clampi(t, 1, TIER_MAX)
	var row: Dictionary = GameData.store_row(n)
	if not row.is_empty():
		return row
	return {}

func tier_name(t: int = -1) -> String:
	var row: Dictionary = tier_row(t)
	if not row.is_empty():
		return String(row.get("name", ""))
	var n: int = effective_tier() if t <= 0 else clampi(t, 1, TIER_MAX)
	if n >= 1 and n <= TIER_NAMES.size():
		return String(TIER_NAMES[n - 1])
	return "第 %d 阶" % n

## 该阶的敌人生命 / 敌人伤害 / 刷怪量倍率（1–21 阶同斜率线性叠加）。
func tier_enemy_hp(t: int = -1) -> float:
	var n: int = effective_tier() if t <= 0 else clampi(t, 1, TIER_MAX)
	return 1.0 + SEAL_HP * float(n - 1)

func tier_enemy_dmg(t: int = -1) -> float:
	var n: int = effective_tier() if t <= 0 else clampi(t, 1, TIER_MAX)
	return 1.0 + SEAL_DMG * float(n - 1)

func tier_spawn_rate(t: int = -1) -> float:
	var n: int = effective_tier() if t <= 0 else clampi(t, 1, TIER_MAX)
	return 1.0 + SEAL_RATE * float(n - 1)

# ---------------------------------------------------------------- 结算

## 结算银两公式。seal <= 0 才回落到 save 里的当前灾变阶（effective_tier）。
## 契约 F：命令行 --seal=N 跑局时调用方（run.gd）必须显式传本局印，不能读存档阶，
##       否则结算系数与这一局的实际难度对不上。
func reward_for(victory: bool, kills: int, seconds: float, seal: int = -1) -> int:
	var base: int = int(seconds / 8.0) + int(kills / 3.0) + (120 if victory else 0)
	return int(float(base) * seal_mult(seal))

## 银两倍率（按阶）。1–7 与旧版逐位相同（1 阶 1.00 … 7 阶 2.80）；
## 8–21 在 2.80 → 3.20 之间用 smoothstep 平滑递增，21 阶正好 3.20。
func seal_mult(seal: int = -1) -> float:
	var n: int = effective_tier() if seal <= 0 else clampi(seal, 1, TIER_MAX)
	var seal_top: float = 1.0 + SEAL_MULT_STEP * float(TIER_SEAL_END - 1)
	if n <= TIER_SEAL_END:
		return 1.0 + SEAL_MULT_STEP * float(n - 1)
	var p: float = float(n - TIER_SEAL_END) / float(TIER_MAX - TIER_SEAL_END)
	var ease: float = p * p * (3.0 - 2.0 * p)
	return seal_top + (SEAL_MULT_TOP - seal_top) * ease

## 结算并写档。seal 语义与 reward_for 完全一致：<= 0 才读存档阶，
## --seal=N 跑局时必须由调用方显式传本局印（契约 F），觉醒判定也只看这个 seal。
func register_run(victory: bool, kills: int, seconds: float, seal: int = -1) -> int:
	var gain: int = reward_for(victory, kills, seconds, seal)
	shillings += gain
	runs += 1
	if victory:
		wins += 1
		var s: int = effective_tier() if seal <= 0 else clampi(seal, 1, TIER_MAX)
		seals = clampi(maxi(seals, s + 1), 1, max_tier_allowed())
	best_kills = maxi(best_kills, kills)
	best_time = maxf(best_time, seconds)
	lifetime_kills += kills
	save_save()
	return gain
