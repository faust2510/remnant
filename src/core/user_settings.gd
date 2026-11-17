extends Node
## 全局用户设置（与存档分开存 user://settings.json）
## 特效档位：0 = 关，1 = 中，2 = 高。渲染侧只读 fx_level()，UI 侧只调 cycle_fx_level()。
class_name UserSettings

const PATH: String = "user://settings.json"
const VERSION: int = 1

const FX_LEVELS: Array[int] = [0, 1, 2]
const FX_NAMES: Array[String] = ["关", "中", "高"]

static var fx_level: int = 2
static var _loaded: bool = false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var f: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var raw: String = f.get_as_text()
	f.close()
	var d: Variant = JSON.parse_string(raw)
	if typeof(d) != TYPE_DICTIONARY:
		return
	var v: int = int((d as Dictionary).get("fx_level", 2))
	fx_level = clampi(v, 0, 2)


static func save_settings() -> void:
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"version": VERSION, "fx_level": fx_level}))
	f.close()


static func set_fx_level(v: int) -> void:
	fx_level = clampi(v, 0, 2)
	save_settings()


static func cycle_fx_level() -> int:
	set_fx_level((fx_level + 1) % 3)
	return fx_level


static func fx_name() -> String:
	return FX_NAMES[clampi(fx_level, 0, 2)]


## 渲染侧的便捷判定：高 = 2，中及以上 = 1。
static func fx_at_least(level: int) -> bool:
	return fx_level >= level
