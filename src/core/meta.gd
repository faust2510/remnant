extends Node
## 局外存档：舍客勒、营地永久强化、七印进度、生涯统计。
## 存档位置 user://save.json（本机 = .godot_home/Library/Application Support/Godot/app_userdata/...）。

const SAVE_PATH := "user://save.json"
## 七印每层增量（run.gd 与营地面板共用，改这里即可）
const SEAL_HP := 0.09
const SEAL_DMG := 0.06
const SEAL_RATE := 0.04
const SAVE_VERSION := 1

## 营地强化表。每级 line 是给 recompute() 的增量，key 与 GameState.stats 对齐。
const UPGRADES: Array = [
	{ "id": "might", "name": "刚强", "desc": "全伤害 +4% / 级", "base": 50, "step": 35, "max": 5 },
	{ "id": "vitality", "name": "壮胆", "desc": "生命上限 +12 / 级", "base": 45, "step": 30, "max": 5 },
	{ "id": "swift", "name": "快跑", "desc": "移动速度 +3% / 级", "base": 40, "step": 30, "max": 5 },
	{ "id": "grace", "name": "恩典", "desc": "拾取范围 +10% / 级", "base": 35, "step": 25, "max": 5 },
	{ "id": "wisdom", "name": "智慧", "desc": "经验获取 +5% / 级", "base": 55, "step": 40, "max": 5 },
	{ "id": "mercy", "name": "怜恤", "desc": "领受回血 +3% / 级", "base": 60, "step": 45, "max": 5 }
]

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

func _ready() -> void:
	load_save()

# ---------------------------------------------------------------- 存档

func load_save() -> void:
	levels = {}
	for u in UPGRADES:
		levels[String(u["id"])] = 0
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return
	shillings = int(data.get("shillings", 0))
	runs = int(data.get("runs", 0))
	wins = int(data.get("wins", 0))
	best_kills = int(data.get("best_kills", 0))
	best_time = float(data.get("best_time", 0.0))
	lifetime_kills = int(data.get("lifetime_kills", 0))
	seals = clampi(int(data.get("seals", 1)), 1, 7)
	selected_seal = clampi(int(data.get("selected_seal", 1)), 1, seals)
	stage_id = String(data.get("stage_id", "elah_valley"))
	var lv: Dictionary = data.get("levels", {})
	for u in UPGRADES:
		var id: String = String(u["id"])
		levels[id] = clampi(int(lv.get(id, 0)), 0, int(u["max"]))

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
		"lifetime_kills": lifetime_kills
	}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("save failed: " + str(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()

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

# ---------------------------------------------------------------- 结算

## seal <= 0 时用存档里选中的印；命令行 --seal=N 跑局时必须把真实印传进来，否则结算系数与实际难度不符。
func reward_for(victory: bool, kills: int, seconds: float, seal: int = -1) -> int:
	var base: int = int(seconds / 8.0) + int(kills / 3.0) + (120 if victory else 0)
	return int(float(base) * seal_mult(seal))

func seal_mult(seal: int = -1) -> float:
	var s: int = selected_seal if seal <= 0 else seal
	return 1.0 + 0.3 * float(clampi(s, 1, 7) - 1)

func register_run(victory: bool, kills: int, seconds: float, seal: int = -1) -> int:
	var gain: int = reward_for(victory, kills, seconds, seal)
	shillings += gain
	runs += 1
	if victory:
		wins += 1
		var s: int = selected_seal if seal <= 0 else seal
		seals = clampi(maxi(seals, s + 1), 1, 7)
	best_kills = maxi(best_kills, kills)
	best_time = maxf(best_time, seconds)
	lifetime_kills += kills
	save_save()
	return gain
