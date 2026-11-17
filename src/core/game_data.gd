extends Node
## 全局数据表（autoload: GameData）。所有玩法内容来自 res://data/*.json，代码里不写死内容。

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

func _ready() -> void:
	reload()

func reload() -> void:
	weapons = _index(_load("weapons.json").get("weapons", []), "id")
	passives = _index(_load("passives.json").get("passives", []), "id")
	enemies = _index(_load("enemies.json").get("enemies", []), "id")
	characters = _load("characters.json").get("characters", [])
	characters_by_id = _index(characters, "id")
	stages = _load("stages.json").get("stages", [])
	stages_by_id = _index(stages, "id")

	fusions = _load("fusions.json").get("fusions", [])
	fusion_by_weapon.clear()
	fusion_by_id.clear()
	dual_fusions.clear()
	for f in fusions:
		fusion_by_id[f["id"]] = f
		if String(f.get("type", "")) == "dual_weapon":
			dual_fusions.append(f)
		else:
			fusion_by_weapon[f["weapon"]] = f

	if weapons.is_empty():
		push_error("[GameData] weapons.json 为空，检查 res://data/")

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

func _index(arr: Array, key: String) -> Dictionary:
	var out := {}
	for item in arr:
		out[item[key]] = item
	return out
