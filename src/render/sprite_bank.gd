class_name SpriteBank
extends RefCounted
## 纹理银行：统一加载 assets/sprites 与 assets/icons，缺失时返回 null（调用方必须有程序化回退）。
## 无头模拟不加载任何纹理：所有绘制入口都不从这里取数据。

const CELL := 32
const FRAMES := 4

const WITNESS_ROWS := ["david", "moses", "gideon", "joshua"]
const ENEMY_ROWS := ["soldier", "archer", "raven", "beast", "scorpion", "six_finger_giant", "goliath", "the_tempter"]

const SPRITES_DIR := "res://assets/sprites/"
const ICONS_DIR := "res://assets/icons/"

static var _cache: Dictionary = {}
static var _checked: Dictionary = {}

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
static func weapon_icons() -> Texture2D: return _tex(ICONS_DIR + "weapons.png")
static func passive_icons() -> Texture2D: return _tex(ICONS_DIR + "passives.png")

## 见证人图集行号；未知返回 -1
static func witness_row(id: String) -> int:
	return WITNESS_ROWS.find(id)

## 敌人图集行号；未收录返回 -1（调用方回退到程序化绘制）
static func enemy_row(id: String) -> int:
	return ENEMY_ROWS.find(id)

static func frame_rect(row: int, frame: int) -> Rect2:
	var f: int = clampi(frame, 0, FRAMES - 1)
	return Rect2(Vector2(f * CELL, row * CELL), Vector2(CELL, CELL))

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
	return Rect2(Vector2((i % 5) * CELL, (i / 5) * CELL), Vector2(CELL, CELL))

static func passive_icon_rect(index: int) -> Rect2:
	var i: int = clampi(index, 0, 19)
	return Rect2(Vector2((i % 5) * CELL, (i / 5) * CELL), Vector2(CELL, CELL))

## 一次抽 4 帧里当前该画哪一帧（呼吸/跑动），time 可用 run.elapsed
static func frame_index(time: float, speed_ratio: float = 1.0) -> int:
	var fps: float = 6.0 + clampf(speed_ratio, 0.0, 3.0) * 3.0
	return int(floor(time * fps)) % FRAMES
