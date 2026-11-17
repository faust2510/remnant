extends Node
## 全局数据表（autoload: GameData）。所有玩法内容来自 res://data/*.json，代码里不写死内容。
## v2 新增五张表：bosses / relics / covenants / achievements / store。
## 兼容铁律：这些文件暂时不存在时**静默跳过**（只在 debug 构建里打印一次），不 push_error、不刷屏。

const DATA_DIR := "res://data/"

var weapons: Dictionary = {}
var passives: Dictionary = {}
var fusions: Array = []
var fusion_by_weapon: Dictionary = {}
var fusion_by_id: Dictionary = {}
var dual_fusions: Array = []
var enemies: Dictionary = {}
var characters: Array = []
var characters_by_id: Dictionary = {}
var stages: Array = []
var stages_by_id: Dictionary = {}

# ---------------------------------------------------------------- v2 新增表
var bosses: Array = []
var bosses_by_id: Dictionary = {}
var relics: Array = []
var relics_by_id: Dictionary = {}
var covenants: Array = []
var covenants_by_id: Dictionary = {}
var achievements: Array = []
var achievements_by_id: Dictionary = {}
## data/store.json 原样保留：{"buildings":[], "upgrades":[], "tiers":[], "tier_curve":{}}
var store: Dictionary = {}

## 缺文件只在 debug 下提示一次（key = 文件名）
var _missing_logged: Dictionary = {}

func _ready() -> void:
	reload()

func reload() -> void:
	weapons = _index(_load("weapons.json").get("weapons", []), "id")
	passives = _index(_load("passives.json").get("passives", []), "id")
	enemies = _index(_load("enemies.json").get("enemies", []), "id")
	characters = _array_of(_load("characters.json"), "characters")
	characters_by_id = _index(characters, "id")
	stages = _array_of(_load("stages.json"), "stages")
	stages_by_id = _index(stages, "id")

	fusions = _array_of(_load("fusions.json"), "fusions")
	fusion_by_weapon.clear()
	fusion_by_id.clear()
	dual_fusions.clear()
	for f in fusions:
		fusion_by_id[f["id"]] = f
		if String(f.get("type", "")) == "dual_weapon":
			dual_fusions.append(f)
		else:
			fusion_by_weapon[f["weapon"]] = f

	# ---- v2：可选表。文件不在就跳过，老工程照常跑 ----
	bosses = _array_of(_load_optional("bosses.json"), "bosses")
	bosses_by_id = _index(bosses, "id")
	relics = _array_of(_load_optional("relics.json"), "relics")
	relics_by_id = _index(relics, "id")
	covenants = _array_of(_load_optional("covenants.json"), "covenants")
	covenants_by_id = _index(covenants, "id")
	achievements = _array_of(_load_optional("achievements.json"), "achievements")
	achievements_by_id = _index(achievements, "id")
	store = _load_optional("store.json")

	if weapons.is_empty():
		push_error("[GameData] weapons.json 为空，检查 res://data/")

# ---------------------------------------------------------------- 便捷查询（给 systems / ui 用）

func boss_def(id: String) -> Dictionary:
	return bosses_by_id.get(id, {})

func relic_def(id: String) -> Dictionary:
	return relics_by_id.get(id, {})

func covenant_def(id: String) -> Dictionary:
	return covenants_by_id.get(id, {})

func achievement_def(id: String) -> Dictionary:
	return achievements_by_id.get(id, {})

## 会幕 6 建筑定义（store.json 缺失时返回空数组，调用方要能接受）
func store_buildings() -> Array:
	return _store_array("buildings")

func store_upgrades() -> Array:
	return _store_array("upgrades")

## 21 阶灾变表（第 1..21 阶，按 tier 升序；store.json 缺失时返回空数组）
func store_tiers() -> Array:
	return _store_array("tiers")

func store_row(tier: int) -> Dictionary:
	for row in store_tiers():
		if int(row.get("tier", 0)) == tier:
			return row
	return {}

func _store_array(key: String) -> Array:
	var v: Variant = store.get(key, [])
	if typeof(v) != TYPE_ARRAY:
		return []
	return v

# ---------------------------------------------------------------- 装载

func _load(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("[GameData] 缺少数据文件: " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[GameData] 无法打开: " + path)
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[GameData] JSON 解析失败: " + path)
		return {}
	return parsed

## v2 可选表：缺文件/坏 JSON 都不报错，debug 构建里每个文件只提示一次。
func _load_optional(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		_note_missing(file_name, "不存在")
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_note_missing(file_name, "无法打开")
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_note_missing(file_name, "JSON 解析失败")
		return {}
	return parsed

func _note_missing(file_name: String, why: String) -> void:
	if not OS.is_debug_build():
		return
	if _missing_logged.has(file_name):
		return
	_missing_logged[file_name] = true
	print("[GameData] 可选数据跳过: ", file_name, "（", why, "），使用安全默认值")

func _array_of(doc: Dictionary, key: String) -> Array:
	var v: Variant = doc.get(key, [])
	if typeof(v) != TYPE_ARRAY:
		return []
	return v

func _index(arr: Array, key: String) -> Dictionary:
	var out := {}
	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if not item.has(key):
			continue
		out[item[key]] = item
	return out
