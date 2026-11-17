class_name ProjectileVisuals
extends RefCounted
## V4 弹道视觉映射（渲染层专用；--sim / --headless 下不碰纹理、无副作用）。
##
## 数据形状：weapon id → { row, tint, scale, trail, gap, size }
##   row   projectiles.png 的行名（stone/arrow/flame/blade/note/water/shock/spark）
##   tint  弹体叠色（1:1 乘在贴图上，不改形状）
##   scale 整数放大（1 = 16px 格 1:1；2 = 32px，给 BOSS/巨物级弹体）
##   trail 残影段数（契约要求同屏 4 段）
##   gap   每段残影按速度回溯的秒数（越大拖尾越长）
##   size  该武器弹体的典型 size（同 (color,status) 多把武器时按它挑最像的）
##
## 运行期解析顺序（world_renderer 调用）：
##   1. 敌方弹幕（friendly=0）→ ENEMY_PROFILE（红调 spark）
##   2. 已装备武器的 (color,status) 命中 → 取 size 最接近的那把
##   3. 未命中（融合武器 / 未装备 / 敌方技能弹）→ 按 color+status 给主题行
## 图集缺失、行缺失、贴图尺寸与 atlas.json 对不上时 row_index() 返回 -1，
## 由调用方回退程序化绘制：本文件绝不 push_error、不加载纹理。

const SHEET := "projectiles"
const DEFAULT_TRAIL := 4
const DEFAULT_GAP := 0.014

## 行 → [发光描边色, 命中火花色]
const ROW_FX := {
	"stone": ["#F0D890", "#FFE9AE"],
	"arrow": ["#D9CBB0", "#FFF3D2"],
	"flame": ["#E0731A", "#FFB347"],
	"blade": ["#DCE9F5", "#FFFFFF"],
	"note": ["#F2C46B", "#FFE9A8"],
	"water": ["#6FA8C4", "#CFEFFF"],
	"shock": ["#C9A6E8", "#E8DAFF"],
	"spark": ["#F2C14E", "#FFF0B8"],
}

## 20 把武器的完整映射（顺序与 data/weapons.json 一致；st = 数据里的 status 名）
const PROFILES := {
	"sling": { "row": "stone", "tint": "#FFF3D6", "scale": 1, "trail": 4, "gap": 0.013, "size": 3.0, "st": "tremor" },
	"staff": { "row": "water", "tint": "#BBD9E8", "scale": 1, "trail": 4, "gap": 0.014, "size": 4.0, "st": "wet" },
	"torch": { "row": "flame", "tint": "#FFD9A8", "scale": 1, "trail": 4, "gap": 0.012, "size": 7.0, "st": "burn" },
	"horn": { "row": "note", "tint": "#FFEDC4", "scale": 1, "trail": 4, "gap": 0.014, "size": 4.0, "st": "tremor" },
	"censer": { "row": "flame", "tint": "#D9A8F0", "scale": 1, "trail": 4, "gap": 0.017, "size": 4.0, "st": "burn" },
	"harp": { "row": "note", "tint": "#CFE0F5", "scale": 1, "trail": 4, "gap": 0.018, "size": 4.0, "st": "blind" },
	"olive_branch": { "row": "water", "tint": "#C6E0A8", "scale": 1, "trail": 4, "gap": 0.014, "size": 8.0, "st": "wet" },
	"jawbone": { "row": "arrow", "tint": "#F0E4C8", "scale": 1, "trail": 4, "gap": 0.012, "size": 6.0, "st": "tremor" },
	"tambourine": { "row": "note", "tint": "#F2C0D0", "scale": 1, "trail": 4, "gap": 0.014, "size": 4.0, "st": "tremor" },
	"sickle": { "row": "blade", "tint": "#E8D9A8", "scale": 1, "trail": 4, "gap": 0.012, "size": 4.0, "st": "fear" },
	"spirit_blade": { "row": "blade", "tint": "#EAF3FF", "scale": 1, "trail": 4, "gap": 0.011, "size": 4.0, "st": "blind" },
	"menorah": { "row": "spark", "tint": "#FFD98A", "scale": 1, "trail": 4, "gap": 0.014, "size": 8.0, "st": "blind" },
	"bronze_serpent": { "row": "flame", "tint": "#C48A46", "scale": 1, "trail": 4, "gap": 0.014, "size": 4.0, "st": "burn" },
	"chariot": { "row": "flame", "tint": "#FF9A5C", "scale": 2, "trail": 4, "gap": 0.012, "size": 9.0, "st": "burn" },
	"hammer": { "row": "shock", "tint": "#C8BCA8", "scale": 1, "trail": 4, "gap": 0.014, "size": 4.0, "st": "tremor" },
	"scepter": { "row": "spark", "tint": "#FFE08A", "scale": 1, "trail": 4, "gap": 0.016, "size": 4.0, "st": "fear" },
	"abel_blood": { "row": "flame", "tint": "#D95A5A", "scale": 1, "trail": 4, "gap": 0.016, "size": 4.0, "st": "burn" },
	"voice": { "row": "shock", "tint": "#A8D0E8", "scale": 1, "trail": 4, "gap": 0.016, "size": 8.0, "st": "wet" },
	"fishing_net": { "row": "water", "tint": "#9FBBD0", "scale": 1, "trail": 4, "gap": 0.014, "size": 4.0, "st": "wet" },
	"heaven_keys": { "row": "spark", "tint": "#FFF0B8", "scale": 1, "trail": 4, "gap": 0.015, "size": 5.0, "st": "blind" },
}

const ENEMY_PROFILE := { "row": "spark", "tint": "#FF9A7A", "scale": 1, "trail": 4, "gap": 0.016, "size": 3.0 }
const FALLBACK_PROFILE := { "row": "stone", "tint": "#FFF6DE", "scale": 1, "trail": 4, "gap": 0.014, "size": 3.0 }

## 与 data/weapons.json 的 color 派生规则一致（weapon_runner._fire）
const STATUS_TO_COLOR := { "tremor": 1, "burn": 2, "wet": 3, "blind": 1 }

static var _baked: Dictionary = {}
static var _index: Dictionary = {}
static var _index_sig: String = ""
static var _enemy_baked: Dictionary = {}


# ---------------------------------------------------------------- 查询

static func has_weapon(id: String) -> bool:
	return PROFILES.has(id)


## 单把武器的视觉档案（烘焙一次，含 Color 化字段）
static func profile(id: String) -> Dictionary:
	if _baked.has(id):
		return _baked[id] as Dictionary
	_baked[id] = _bake(id, PROFILES.get(id, FALLBACK_PROFILE) as Dictionary)
	return _baked[id] as Dictionary


static func enemy_profile() -> Dictionary:
	if _enemy_baked.is_empty():
		_enemy_baked = _bake("_enemy", ENEMY_PROFILE)
	return _enemy_baked


## 装备变化时重建 (color,status) → 候选档案列表；sig 不变直接复用（每帧都可安全调用）
static func rebuild_index(weapon_ids: Array) -> void:
	var sig: String = ""
	for id in weapon_ids:
		sig += String(id) + "|"
	if sig == _index_sig:
		return
	_index_sig = sig
	_index.clear()
	for id in weapon_ids:
		var wid: String = String(id)
		if not PROFILES.has(wid):
			continue
		var p: Dictionary = profile(wid)
		var key: int = _key(int(p["color"]), int(p["status"]))
		if not _index.has(key):
			_index[key] = []
		(_index[key] as Array).append(p)


## 一发弹幕该用哪条档案。friendly=false 恒为敌方红调。
static func resolve(color_code: int, status_code: int, size: float, friendly: bool) -> Dictionary:
	if not friendly:
		return enemy_profile()
	var list: Variant = _index.get(_key(color_code, status_code), null)
	if list is Array and not (list as Array).is_empty():
		var arr: Array = list
		var best: Dictionary = arr[0] as Dictionary
		var bd: float = absf(float(best["size"]) - size)
		for k in range(1, arr.size()):
			var p: Dictionary = arr[k] as Dictionary
			var d: float = absf(float(p["size"]) - size)
			if d < bd:
				bd = d
				best = p
		return best
	return profile(_theme_id(color_code, status_code))


## 投影物图集行号；纹理缺失 / 行未收录 / 贴图高度对不上清单时返回 -1（调用方回退）
static func row_index(row_name: String, tex: Texture2D) -> int:
	if tex == null:
		return -1
	var idx: int = SpriteBank.projectile_row(row_name)
	if idx < 0:
		return -1
	var cell: int = SpriteBank.cell_of(SHEET)
	if cell <= 0:
		return -1
	if (idx + 1) * cell > tex.get_height():
		return -1
	return idx


## 当前该画哪一帧（闪烁/旋转）；实际列数以贴图宽度收敛，OVERSIZE 的清单不会越界采样
static func frame_for(time: float, phase: int, tex: Texture2D) -> int:
	var cols: int = SpriteBank.frames_of(SHEET)
	var cell: int = SpriteBank.cell_of(SHEET)
	if tex != null and cell > 0:
		cols = clampi(int(tex.get_width() / cell), 1, maxi(cols, 1))
	if cols <= 1:
		return 0
	return int(floor(time * 12.0) + float(phase)) % cols


## 命中火花的取色：crit 更亮，其余按弹道行的 spark 色
static func spark_color(prof: Dictionary, crit: bool) -> Color:
	var c: Color = prof.get("spark", Color("#FFE9AE")) as Color
	return c.lerp(Color(1.0, 1.0, 1.0), 0.45) if crit else c


# ---------------------------------------------------------------- 内部

static func _key(color_code: int, status_code: int) -> int:
	return color_code * 16 + clampi(status_code, 0, 15)


static func _bake(id: String, raw: Dictionary) -> Dictionary:
	var row: String = String(raw.get("row", "stone"))
	var fx: Array = ROW_FX.get(row, ROW_FX["stone"]) as Array
	var tint: Color = Color(String(raw.get("tint", "#FFFFFF")))
	tint.a = 1.0
	return {
		"id": id,
		"row": row,
		"tint": tint,
		"scale": clampi(int(raw.get("scale", 1)), 1, 4),
		"trail": clampi(int(raw.get("trail", DEFAULT_TRAIL)), 0, 4),
		"gap": clampf(float(raw.get("gap", DEFAULT_GAP)), 0.004, 0.06),
		"size": float(raw.get("size", 3.0)),
		"color": int(STATUS_TO_COLOR.get(String(raw.get("st", "")), 0)),
		"status": _status_code(String(raw.get("st", ""))),
		"glow": Color(String(fx[0])),
		"spark": Color(String(fx[1])),
	}


static func _status_code(status_name: String) -> int:
	if status_name == "":
		return 0
	return maxi(ProjectileSim.STATUS_NAMES.find(status_name), 0)


## 未命中装备时的主题兜底：先按状态码，再按颜色码
static func _theme_id(color_code: int, status_code: int) -> String:
	match status_code:
		1: return "chariot"
		2: return "sling"
		3: return "harp"
		4: return "voice"
		5: return "scepter"
	match color_code:
		2: return "chariot"
		3: return "voice"
		4: return "sling"
	return "sling"
