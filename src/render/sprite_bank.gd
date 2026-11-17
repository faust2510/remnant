class_name SpriteBank
extends RefCounted
## 纹理银行：统一加载 assets/sprites 与 assets/icons，缺失时返回 null（调用方必须有程序化回退）。
## 图集几何（格宽 / 帧数 / 行序）由 assets/sprites/atlas.json 决定，运行期唯一事实源；
## 清单缺失时退回内置默认（V3 的 32px / 4 帧），保证老资源不崩。
## 无头模拟不加载任何纹理：所有绘制入口都不从这里取数据。

const SPRITES_DIR := "res://assets/sprites/"
const ICONS_DIR := "res://assets/icons/"
const ATLAS_PATH := SPRITES_DIR + "atlas.json"

## 内置兜底（atlas.json 读不到时使用；与 V3 完全一致）
const DEFAULT_SHEETS := {
	"witnesses": { "cell": 32, "frames": 4, "feet_y": 29, "idle_frames": 4,
		"rows": ["david", "moses", "gideon", "joshua"] },
	"enemies": { "cell": 32, "frames": 4, "feet_y": 28,
		"rows": ["soldier", "archer", "raven", "beast", "scorpion", "six_finger_giant", "goliath", "the_tempter"] },
	"props": { "cell": 16, "frames": 8, "feet_y": 16, "rows": ["props"] },
}

static var _cache: Dictionary = {}
static var _checked: Dictionary = {}
static var _sheets: Dictionary = {}
static var _sheets_loaded: bool = false

# ---------------------------------------------------------------- 清单

static func _load_sheets() -> void:
	if _sheets_loaded:
		return
	_sheets_loaded = true
	for k in DEFAULT_SHEETS.keys():
		_sheets[k] = (DEFAULT_SHEETS[k] as Dictionary).duplicate(true)
	if not FileAccess.file_exists(ATLAS_PATH):
		return
	var f: FileAccess = FileAccess.open(ATLAS_PATH, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return
	for k in (data as Dictionary).keys():
		var v: Variant = data[k]
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var one: Dictionary = v as Dictionary
		if not one.has("cell") or not one.has("rows"):
			continue
		var merged: Dictionary = (_sheets.get(k, {}) as Dictionary).duplicate(true)
		for kk in one.keys():
			merged[kk] = one[kk]
		_sheets[k] = merged

static func sheet(name: String) -> Dictionary:
	_load_sheets()
	return _sheets.get(name, {}) as Dictionary

static func cell_of(name: String) -> int:
	return int(sheet(name).get("cell", 32))

## 兼容旧调用：见证人图集的格宽
static func cell() -> int:
	return cell_of("witnesses")

static func frames_of(name: String) -> int:
	return maxi(1, int(sheet(name).get("frames", 4)))

static func feet_of(name: String) -> int:
	return int(sheet(name).get("feet_y", 29))

static func rows_of(name: String) -> Array:
	return sheet(name).get("rows", []) as Array

# ---------------------------------------------------------------- 纹理

static func _tex(path: String) -> Texture2D:
	if _checked.has(path):
		return _cache.get(path, null) as Texture2D
	_checked[path] = true
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			tex = res as Texture2D
	_cache[path] = tex
	return tex

static func witnesses() -> Texture2D: return _tex(SPRITES_DIR + "witnesses.png")
static func enemies() -> Texture2D: return _tex(SPRITES_DIR + "enemies.png")
static func props() -> Texture2D: return _tex(SPRITES_DIR + "props.png")
static func projectiles() -> Texture2D: return _tex(SPRITES_DIR + "projectiles.png")
static func weapon_icons() -> Texture2D: return _tex(ICONS_DIR + "weapons.png")
static func passive_icons() -> Texture2D: return _tex(ICONS_DIR + "passives.png")

## 见证人图集行号；未知返回 -1
static func witness_row(id: String) -> int:
	return rows_of("witnesses").find(id)

## 敌人图集行号；未收录返回 -1（调用方回退到程序化绘制）
static func enemy_row(id: String) -> int:
	var rows: Array = rows_of("enemies")
	var direct: int = rows.find(id)
	if direct >= 0:
		return direct
	# 兼容：data 里可能用类型前缀命名（soldier_a 等），按前缀再匹配一次
	for i in range(rows.size()):
		if id.begins_with(String(rows[i])):
			return i
	return -1

## 投影物图集行号；未知返回 -1
static func projectile_row(id: String) -> int:
	return rows_of("projectiles").find(id)

# ---------------------------------------------------------------- 区域

## 通用格子区域。sheet 取 witnesses / enemies / props / projectiles
static func frame_rect(row: int, frame: int, sheet_name: String = "witnesses") -> Rect2:
	var c: int = cell_of(sheet_name)
	var frames: int = frames_of(sheet_name)
	var f: int = clampi(frame, 0, frames - 1)
	return Rect2(Vector2(f * c, row * c), Vector2(c, c))

## props.png 的 16x16 格子：gem0..gem3 / coin / coal
static func prop_rect(kind: String, tier: int = 0) -> Rect2:
	var col := 0
	match kind:
		"gem": col = clampi(tier, 0, 3)
		"coin": col = 4
		"coal": col = 5
		_: return Rect2()
	return Rect2(Vector2(col * 16.0, 0.0), Vector2(16, 16))

static func weapon_icon_rect(index: int) -> Rect2:
	var i: int = clampi(index, 0, 19)
	var c: int = 32
	return Rect2(Vector2((i % 5) * c, (i / 5) * c), Vector2(c, c))

static func passive_icon_rect(index: int) -> Rect2:
	var i: int = clampi(index, 0, 19)
	var c: int = 32
	return Rect2(Vector2((i % 5) * c, (i / 5) * c), Vector2(c, c))

## 一次抽 4 帧里当前该画哪一帧（呼吸/跑动），time 可用 run.elapsed
static func frame_index(time: float, speed_ratio: float = 1.0) -> int:
	var fps: float = 6.0 + clampf(speed_ratio, 0.0, 3.0) * 3.0
	return int(floor(time * fps)) % frames_of("witnesses")

## 站定/行走分帧：前 idle_frames 帧是呼吸，其余是走步。moving=false 时只在站立帧里循环。
static func witness_frame(time: float, moving: bool) -> int:
	var idle: int = maxi(1, int(sheet("witnesses").get("idle_frames", 4)))
	var total: int = frames_of("witnesses")
	if not moving or idle >= total:
		return int(floor(time * 6.0)) % idle
	var walk: int = total - idle
	return idle + (int(floor(time * 9.0)) % walk)

## 敌人帧：按速度提频，全部帧参与循环
static func enemy_frame(time: float, speed_ratio: float = 1.0) -> int:
	var fps: float = 7.0 + clampf(speed_ratio, 0.0, 2.5) * 3.0
	return int(floor(time * fps)) % frames_of("enemies")
