class_name Chooser
extends Control
## 领受 / 祭坛三选一：石刻卷轴卡片（V3 契约 §1 图集顺序 + §6 美术口径）。
## 每张卡 = 石刻金框 + 羊皮纸内页 + 左侧 32×32 图标框 + 右上状态角标 + 底部金色斜体出处。
## 悬停/选中：外框呼吸金光 + 整卡右移 4px（只在 draw 里偏移，Control 位置不动；命中区取并集）。
## 键盘 1/2/3 选择，R 重新求问，鼠标点击也可。

signal picked(index: int)
signal reroll_requested

var title: String = ""
var options: Array = []      # [{kind, id/fusion_id, name, tag, desc, color, level?}]
var active: bool = false
var hover: int = -1
var rerolls: int = 0         # 剩余重掷次数（只用于领受面板）
var _t: float = 0.0

# ---------------------------------------------------------------- 卡片几何常量（640×360 基准）
const SCREEN_W := 640.0
const SCREEN_H := 360.0
const CARD_W := 300.0
const CARD_H := 72.0
const CARD_GAP := 10.0
const CARD_X := 168.0          # 卡左沿：居中 170 再让出 2px，悬停右移 4px 后仍不越界
const CARD_CENTER_Y := 206.0   # 三张卡整体的纵向中心 → 三张卡占 88..324
const HOVER_SHIFT := 4.0       # 悬停/选中整卡右移量（只影响绘制与命中）
const FRAME_PAD := 6.0         # 石刻外框 → 羊皮纸内页的内缩
const SHEET_H := 44.0          # 羊皮纸内页高度（6..50）
const FOOT_TOP := 50.0         # 底部出处条相对卡顶（50..68），18px 才装得下 10px 中文
const FOOT_H := 18.0
const ICON_SIZE := 32.0
const ICON_LEFT := 10.0
const ICON_TOP := 10.0
const TEXT_LEFT := 50.0        # 文字列相对卡左沿
const SHEAR := 0.16            # 斜体剪切量（GameFont 无 italic 字重，用剪切矩阵伪造；过大会让中文糊）
const BAR_TOP := 28.0          # 楣饰卷轴上沿
const BAR_H := 30.0

# ---------------------------------------------------------------- 数据下标缓存（只读 data/*.json 顺序）
var _weapon_icon_index: Dictionary = {}   # weapon id -> 图集下标（= weapons.json 顺序）
var _passive_icon_index: Dictionary = {}  # passive id -> 图集下标（= passives.json 顺序）
var _passive_to_weapon: Dictionary = {}   # passive id -> 对应祝圣武器 id（读 fusions.json）
var _index_ready: bool = false
var _gd: Variant = null                   # /root/GameData 动态句柄（--check-only 下 autoload 标识符不可见）

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func open(p_title: String, opts: Array, p_rerolls: int = 0) -> void:
	title = p_title
	options = opts
	rerolls = p_rerolls
	active = true
	hover = -1
	visible = true
	set_process(true)
	queue_redraw()

func set_options(opts: Array) -> void:
	options = opts
	hover = -1
	queue_redraw()

func close() -> void:
	active = false
	visible = false
	options = []

func _process(delta: float) -> void:
	if active:
		_t += delta
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover = -1
		queue_redraw()

# ---------------------------------------------------------------- 几何

## 卡片基准矩形（不含悬停偏移）
func _card_rect(i: int) -> Rect2:
	var n: int = options.size()
	var total: float = float(n) * CARD_H + float(maxi(n - 1, 0)) * CARD_GAP
	var y0: float = CARD_CENTER_Y - total * 0.5
	return Rect2(CARD_X, y0 + float(i) * (CARD_H + CARD_GAP), CARD_W, CARD_H)

## 卡片实际绘制矩形：悬停的那张整体右移 4px（不改 Control 位置）
func _card_draw_rect(i: int) -> Rect2:
	var r: Rect2 = _card_rect(i)
	if i == hover:
		r.position.x += HOVER_SHIFT
	return r

## 命中矩形 = 基准卡 ∪ 偏移卡：点击区跟着 4px 偏移走，又不会在左边缘来回抖动
func _card_hit_rect(i: int) -> Rect2:
	return _card_rect(i).merge(_card_draw_rect(i))

# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	if not active:
		return
	_ensure_index()
	var f: Font = UITheme.font()
	draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0.03, 0.04, 0.07, 0.78), true)
	_draw_lintel(f)
	for i in range(options.size()):
		_draw_card(f, i, options[i])
	_draw_hint(f)

## 标题区：卷轴楣饰（领 受 / 祝 圣）+ 卷轴两端金杆 + 副标题
func _draw_lintel(f: Font) -> void:
	var label: String = _rite_label()
	var sub: String = _rite_sub()
	var tw: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x
	var bar_w: float = clampf(tw + 92.0, 168.0, 460.0)
	var bar: Rect2 = Rect2((SCREEN_W - bar_w) * 0.5, BAR_TOP, bar_w, BAR_H)
	# 投影 + 羊皮纸卷身
	draw_rect(Rect2(bar.position + Vector2(2.0, 3.0), bar.size), Color(0, 0, 0, 0.38), true)
	UITheme.scroll(self, bar, 1.0)
	# 两端卷轴金杆 + 轴心铆钉
	for x in [bar.position.x - 1.0, bar.end.x - 3.0]:
		draw_rect(Rect2(x, bar.position.y - 4.0, 4.0, bar.size.y + 8.0), UITheme.GOLD.darkened(0.2), true)
		draw_rect(Rect2(x, bar.position.y - 4.0, 1.0, bar.size.y + 8.0), UITheme.GOLD_PALE, true)
		draw_circle(Vector2(x + 2.0, bar.position.y - 4.0), 2.0, UITheme.GOLD_BRIGHT)
		draw_circle(Vector2(x + 2.0, bar.end.y + 4.0), 2.0, UITheme.GOLD_BRIGHT)
	# 楣饰横线：左右各一段，收在卷轴两侧
	var mid_y: float = bar.position.y + bar.size.y * 0.5
	var la: float = 0.45
	var lc: Color = Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, la)
	var dc: Color = Color(UITheme.GOLD_BRIGHT.r, UITheme.GOLD_BRIGHT.g, UITheme.GOLD_BRIGHT.b, 0.9)
	var lx0: float = 22.0
	var lx1: float = bar.position.x - 14.0
	if lx1 > lx0 + 8.0:
		draw_line(Vector2(lx0, mid_y), Vector2(lx1, mid_y), lc, 1.0)
		draw_circle(Vector2(lx0 + 3.0, mid_y), 1.6, dc)
	var rx0: float = bar.end.x + 14.0
	var rx1: float = SCREEN_W - 22.0
	if rx1 > rx0 + 8.0:
		draw_line(Vector2(rx0, mid_y), Vector2(rx1, mid_y), lc, 1.0)
		draw_circle(Vector2(rx1 - 3.0, mid_y), 1.6, dc)
	# 主标题：石刻深墨字
	draw_string(f, Vector2(bar.position.x, mid_y + 5.0), label, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 15, UITheme.INK_DEEP)
	# 副标题（卷轴下的说明，如「Lv 3」/「乌陵与土明」）
	if sub != "":
		UITheme.text(self, Vector2(0, bar.end.y + 13.0), sub, 9, UITheme.PARCH_DIM, 1, SCREEN_W)

## 单张卡：石刻外框 → 羊皮纸内页 → 图标 → 名/简介 → 状态角标 → 出处条
func _draw_card(f: Font, i: int, o: Dictionary) -> void:
	var r: Rect2 = _card_draw_rect(i)
	var hi: bool = (i == hover)
	var accent: Color = UITheme.GOLD
	var c_raw: Variant = o.get("color", null)
	if c_raw is Color:
		accent = c_raw
	elif typeof(c_raw) == TYPE_STRING and not String(c_raw).is_empty():
		accent = Color.from_string(String(c_raw), UITheme.GOLD)   # 非法色值回退金，不 push_error
	# 悬停呼吸金光：向外扩三层描边（纯绘制，不改变卡片尺寸）
	var glow: float = 0.0
	if hi:
		glow = 0.5 + 0.5 * sin(_t * 5.0)
		for k in range(3, 0, -1):
			var a: float = (0.05 + 0.13 * glow) / float(k)
			draw_rect(r.grow(float(k) * 2.0), Color(UITheme.GOLD_BRIGHT.r, UITheme.GOLD_BRIGHT.g, UITheme.GOLD_BRIGHT.b, a), false, 1.0)
	# 石刻底板（金边 + 四角铆钉）
	UITheme.panel(self, r, 1.0, true)
	# 羊皮纸内页
	var sheet: Rect2 = Rect2(r.position + Vector2(FRAME_PAD, FRAME_PAD), Vector2(r.size.x - FRAME_PAD * 2.0, SHEET_H))
	UITheme.scroll(self, sheet, 1.0)
	# 底部出处条：石刻深槽 + 顶沿金线
	var foot: Rect2 = Rect2(sheet.position.x, r.position.y + FOOT_TOP, sheet.size.x, FOOT_H)
	draw_rect(foot, Color(UITheme.INK_DEEP.r, UITheme.INK_DEEP.g, UITheme.INK_DEEP.b, 0.94), true)
	draw_rect(Rect2(foot.position, Vector2(foot.size.x, 1.0)), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.55), true)
	# 左侧图标框（武器/被动取图集，祭坛与成就类画金色十字纹章）
	_draw_card_icon(Vector2(r.position.x + ICON_LEFT, r.position.y + ICON_TOP), o, glow)
	# 图标与文字之间的类别色竖线
	draw_rect(Rect2(r.position.x + 45.0, r.position.y + 12.0, 2.0, 34.0), Color(accent.r, accent.g, accent.b, 0.85), true)
	# 状态角标（Lv.N → Lv.N+1 / ★ 祝圣 / MAX）
	var st: Dictionary = _status_of(o)
	var chip: Rect2 = _status_chip_rect(f, r, st)
	var name_w: float = r.size.x - TEXT_LEFT - 12.0
	if chip.size.x > 0.0:
		name_w = chip.position.x - (r.position.x + TEXT_LEFT) - 8.0
	# 名字
	draw_string(f, Vector2(r.position.x + TEXT_LEFT, r.position.y + 24.0), String(o.get("name", "")),
		HORIZONTAL_ALIGNMENT_LEFT, maxf(24.0, name_w), 11, UITheme.INK)
	# 简介：最多两行，按宽度自动折行
	var desc: String = String(o.get("desc", ""))
	if desc != "":
		# 实测（modal_v3 逐行像素剖面）：draw_multiline_string 的 pos 是**首行基线**，不是左上角。
		# 名字基线 +24（字高 11 → 占 16..24），简介首行基线必须 ≥ +32 才不会压名字下沿；+34 留 2px 呼吸。
		# 宽度同时让开右上角状态角标（否则两行字会钻到「新得 Lv.N」下面）。
		draw_multiline_string(f, Vector2(r.position.x + TEXT_LEFT, r.position.y + 34.0), desc,
			HORIZONTAL_ALIGNMENT_LEFT, maxf(120.0, name_w), 8, 2,
			Color(UITheme.INK.r, UITheme.INK.g, UITheme.INK.b, 0.75))
	# 状态角标
	if chip.size.x > 0.0:
		_draw_status_chip(chip, st)
	# 底部：金色斜体出处 + 祝圣配对提示
	var line: String = _scripture_line(o)
	if line != "":
		# 单行金色斜体：超宽先降字号，再不行按宽度裁切（不换行、不缩放纹理）
		var fsz: int = 10
		var need: float = f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsz).x + SHEAR * float(fsz) + 4.0
		var room: float = foot.size.x - 14.0
		if need > room:
			fsz = 9
			need = f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsz).x + SHEAR * float(fsz) + 4.0
		if need > room:
			fsz = 8
			need = f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsz).x + SHEAR * float(fsz) + 4.0
		# pos 是 draw_string 的基线：+13 让 10px 字形落在条带 3..13，上下各留 3/5px
		_italic_text(Vector2(foot.position.x + 4.0, foot.position.y + 13.0), line, fsz, UITheme.GOLD_BRIGHT, minf(room, maxf(need, 40.0)))
	# 左侧行号（对应键盘 1/2/3）
	draw_string(f, Vector2(r.position.x - 22.0, r.position.y + r.size.y * 0.5 + 4.0), str(i + 1),
		HORIZONTAL_ALIGNMENT_CENTER, 14.0, 11, Color(UITheme.GOLD_PALE.r, UITheme.GOLD_PALE.g, UITheme.GOLD_PALE.b, 0.7))

## 底部提示：重掷次数 + 键盘说明
func _draw_hint(f: Font) -> void:
	var dim: Color = Color(UITheme.PARCH_DIM.r, UITheme.PARCH_DIM.g, UITheme.PARCH_DIM.b, 0.62)
	var key_hint: String = "按 1 / 2 / 3 或点击卡片选择"
	if rerolls > 0:
		UITheme.text(self, Vector2(0, 338.0), "R 重新求问（剩余 %d 次）" % rerolls, 9, UITheme.GOLD_PALE, 1, SCREEN_W)
		UITheme.text(self, Vector2(0, 352.0), key_hint, 8, dim, 1, SCREEN_W)
	else:
		UITheme.text(self, Vector2(0, 344.0), key_hint, 9, dim, 1, SCREEN_W)

# ---------------------------------------------------------------- 图标

## 32×32 图标框：武器用 weapons.png + weapons.json 下标，被动用 passives.png + passives.json 下标，
## 祭坛/圣约/图集缺失一律画金色十字纹章（不 push_error、不崩溃）。
func _draw_card_icon(at: Vector2, o: Dictionary, glow: float) -> void:
	var box: Rect2 = Rect2(at, Vector2(ICON_SIZE, ICON_SIZE))
	var kind: String = String(o.get("kind", ""))
	var id: String = String(o.get("id", ""))
	var tex: Texture2D = null
	var src: Rect2 = Rect2()
	if kind == "new_weapon" or kind == "up_weapon":
		var wi: int = int(_weapon_icon_index.get(id, -1))
		if wi >= 0:
			tex = SpriteBank.weapon_icons()
			if tex != null:
				src = SpriteBank.weapon_icon_rect(wi)
	elif kind == "new_passive" or kind == "up_passive":
		var pi: int = int(_passive_icon_index.get(id, -1))
		if pi >= 0:
			tex = SpriteBank.passive_icons()
			if tex != null:
				src = SpriteBank.passive_icon_rect(pi)
	if tex == null or src.size.x <= 0.0:
		UITheme.icon_frame(self, box, null, Rect2(), glow)
		_draw_cross_emblem(box, glow)
		return
	UITheme.icon_frame(self, box, tex, src, glow)

## 金色十字纹章：无图标的条目（祝圣 / 圣约 / 成就）统一标识
func _draw_cross_emblem(box: Rect2, glow: float) -> void:
	var c: Vector2 = box.get_center()
	var a: float = 0.86 + 0.14 * glow
	draw_circle(c, 13.0, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.10 + 0.07 * glow))
	draw_rect(Rect2(c.x - 1.5, c.y - 9.0, 3.0, 18.0), Color(UITheme.GOLD_PALE.r, UITheme.GOLD_PALE.g, UITheme.GOLD_PALE.b, a), true)
	draw_rect(Rect2(c.x - 7.0, c.y - 4.5, 14.0, 3.0), Color(UITheme.GOLD_PALE.r, UITheme.GOLD_PALE.g, UITheme.GOLD_PALE.b, a), true)
	UITheme.star(self, Vector2(c.x, c.y - 12.0), 2.0, Color(UITheme.GOLD_BRIGHT.r, UITheme.GOLD_BRIGHT.g, UITheme.GOLD_BRIGHT.b, a))

# ---------------------------------------------------------------- 状态角标

## 右上角状态：普通升级 Lv.N → Lv.N+1；祝圣 ★ 祝圣（金）；满级 MAX
func _status_of(o: Dictionary) -> Dictionary:
	var kind: String = String(o.get("kind", ""))
	if kind == "fusion":
		return { "text": "祝圣", "color": UITheme.GOLD_BRIGHT, "star": true }
	if kind == "covenant":
		return { "text": "圣约", "color": UITheme.GOLD_PALE, "star": false }
	if kind == "up_weapon" or kind == "up_passive":
		var lv: int = _current_level(o)
		var mx: int = _max_level_of(o)
		if lv >= 0 and mx > 0 and lv >= mx:
			return { "text": "MAX", "color": Color("#A9C08A"), "star": false }
		if lv < 0:
			return { "text": "提升", "color": UITheme.GOLD_PALE, "star": false }
		return { "text": "Lv.%d → Lv.%d" % [lv, lv + 1], "color": UITheme.GOLD_PALE, "star": false }
	if kind == "new_weapon" or kind == "new_passive":
		return { "text": "新得 Lv.1", "color": UITheme.PARCH, "star": false }
	return {}

func _status_chip_rect(f: Font, r: Rect2, st: Dictionary) -> Rect2:
	var txt: String = String(st.get("text", ""))
	if txt == "":
		return Rect2()
	var size: int = 8
	var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var star_w: float = 7.0 if bool(st.get("star", false)) else 0.0
	var chip_w: float = tw + star_w + 10.0
	return Rect2(r.end.x - 8.0 - chip_w, r.position.y + 8.0, chip_w, 13.0)

func _draw_status_chip(chip: Rect2, st: Dictionary) -> void:
	draw_rect(Rect2(chip.position + Vector2(1.0, 1.0), chip.size), Color(0, 0, 0, 0.28), true)
	draw_rect(chip, Color(UITheme.INK_DEEP.r, UITheme.INK_DEEP.g, UITheme.INK_DEEP.b, 0.94), true)
	draw_rect(chip, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.55), false, 1.0)
	var col: Color = st.get("color", UITheme.GOLD_PALE)
	var tx: float = chip.position.x + 5.0
	if bool(st.get("star", false)):
		UITheme.star(self, Vector2(tx + 2.5, chip.position.y + chip.size.y * 0.5), 3.2, col)
		tx += 7.0
	draw_string(UITheme.font(), Vector2(tx, chip.position.y + chip.size.y - 3.5), String(st.get("text", "")),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, col)

# ---------------------------------------------------------------- 出处与配对提示（读 data/*.json）

func _scripture_line(o: Dictionary) -> String:
	var parts := PackedStringArray()
	var s: String = _scripture_of(o)
	if s != "":
		parts.append(s)
	var h: String = _pair_hint(o)
	if h != "":
		parts.append(h)
	return "  ·  ".join(parts)

func _scripture_of(o: Dictionary) -> String:
	var kind: String = String(o.get("kind", ""))
	var id: String = String(o.get("id", ""))
	match kind:
		"new_weapon", "up_weapon":
			return _def_field(_table("weapons"), id, "scripture")
		"new_passive", "up_passive":
			return _def_field(_table("passives"), id, "scripture")
		"covenant":
			return _def_field(_table("covenants_by_id"), id, "scripture")
		"fusion":
			var s: String = _def_field(_table("fusion_by_id"), String(o.get("fusion_id", "")), "scripture")
			if s == "":
				s = String(o.get("tag", ""))   # run 把 scripture 放在 tag
			return s
	return String(o.get("scripture", ""))

## 祝圣配对提示：武器 →「可与[宝物]祝圣」；宝物 →「可配[武器]祝圣」；祝圣 → 配方；合鸣 → 两把武器
func _pair_hint(o: Dictionary) -> String:
	var kind: String = String(o.get("kind", ""))
	var id: String = String(o.get("id", ""))
	if kind == "new_weapon" or kind == "up_weapon":
		var f: Dictionary = _def(_table("fusion_by_weapon"), id)
		if not f.is_empty():
			var pn: String = _def_name(_table("passives"), String(f.get("passive", "")))
			if pn != "":
				return "可与[%s]祝圣" % pn
	elif kind == "new_passive" or kind == "up_passive":
		var wn: String = _def_name(_table("weapons"), String(_passive_to_weapon.get(id, "")))
		if wn != "":
			return "可配[%s]祝圣" % wn
	elif kind == "fusion":
		var fd: Dictionary = _def(_table("fusion_by_id"), String(o.get("fusion_id", "")))
		if not fd.is_empty():
			if String(fd.get("type", "")) == "dual_weapon":
				var names := PackedStringArray()
				for wid in fd.get("weapons", []):
					names.append(_def_name(_table("weapons"), String(wid)))
				if names.size() >= 2:
					return "合鸣 [%s] + [%s]" % [names[0], names[1]]
			else:
				var wn2: String = _def_name(_table("weapons"), String(fd.get("weapon", "")))
				var pn2: String = _def_name(_table("passives"), String(fd.get("passive", "")))
				if wn2 != "" and pn2 != "":
					return "需 [%s] + [%s]" % [wn2, pn2]
	return ""

# ---------------------------------------------------------------- 等级解析

## 当前等级：优先 level 字段，其次从 tag（「强化 Lv2 → Lv3」）里取第一个 Lv 数字；取不到返回 -1
func _current_level(o: Dictionary) -> int:
	if o.has("level"):
		return int(o.get("level", -1))
	return _first_lv_number(String(o.get("tag", "")))

func _first_lv_number(s: String) -> int:
	var at: int = s.find("Lv")
	if at < 0:
		return -1
	var i: int = at + 2
	while i < s.length() and (s.unicode_at(i) == 32 or s.unicode_at(i) == 12288):
		i += 1
	var num: int = 0
	var digits: int = 0
	while i < s.length():
		var c: int = s.unicode_at(i)
		if c < 48 or c > 57:
			break
		num = num * 10 + (c - 48)
		i += 1
		digits += 1
	return num if digits > 0 else -1

func _max_level_of(o: Dictionary) -> int:
	var id: String = String(o.get("id", ""))
	var kind: String = String(o.get("kind", ""))
	if kind == "up_weapon" or kind == "new_weapon":
		return int(_def(_table("weapons"), id).get("max_level", 5))
	if kind == "up_passive" or kind == "new_passive":
		return int(_def(_table("passives"), id).get("max_level", 5))
	return 0

# ---------------------------------------------------------------- 数据访问（运行期从 /root/GameData 取值）

## autoload 标识符在 --check-only 下不可见（对照 run.gd 的 RunCfg 同样报错），
## 因此统一走 /root/GameData 动态句柄；autoload 缺失时各访问器返回空值，绘制自动降级。
func _data() -> Variant:
	if _gd == null:
		_gd = get_node_or_null("/root/GameData")
	return _gd

func _table(name: String) -> Variant:
	var gd: Variant = _data()
	if gd == null:
		return null
	return gd.get(name)

func _def_table(name: String) -> Dictionary:
	var t: Variant = _table(name)
	if typeof(t) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = t
	return d

func _array_table(name: String) -> Array:
	var t: Variant = _table(name)
	if typeof(t) != TYPE_ARRAY:
		return []
	var a: Array = t
	return a

## 取表里的一条定义（Dictionary），取不到返回空字典
func _def(table: Variant, key: String) -> Dictionary:
	if typeof(table) != TYPE_DICTIONARY or key.is_empty():
		return {}
	var t: Dictionary = table
	var v: Variant = t.get(key, null)
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	return d

func _def_field(table: Variant, key: String, field: String) -> String:
	var d: Dictionary = _def(table, key)
	return String(d.get(field, ""))

func _def_name(table: Variant, key: String) -> String:
	return _def_field(table, key, "name")

# ---------------------------------------------------------------- 图标下标（只在首次 _draw 时建一次）

func _ensure_index() -> void:
	if _index_ready:
		return
	var wt: Dictionary = _def_table("weapons")
	var pt: Dictionary = _def_table("passives")
	if wt.is_empty() and pt.is_empty():
		return   # 数据尚未就绪：下一帧再建，避免缓存空下标
	_index_ready = true
	var wi: int = 0
	for id in wt.keys():
		_weapon_icon_index[String(id)] = wi
		wi += 1
	var pi: int = 0
	for id in pt.keys():
		_passive_icon_index[String(id)] = pi
		pi += 1
	for fv in _array_table("fusions"):
		if typeof(fv) != TYPE_DICTIONARY:
			continue
		var wp: String = String(fv.get("weapon", ""))
		var ps: String = String(fv.get("passive", ""))
		if wp != "" and ps != "" and not _passive_to_weapon.has(ps):
			_passive_to_weapon[ps] = wp

# ---------------------------------------------------------------- 文字

## 金色斜体小字：GameFont 没有 italic 字重，用剪切矩阵（x -= SHEAR*y）伪造，
## 不缩放纹理、不改变字号，画完立刻复位变换。
func _italic_text(pos: Vector2, s: String, size: int, col: Color, width: float = -1.0) -> void:
	if s.is_empty():
		return
	draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(-SHEAR, 1.0), pos))
	draw_string(UITheme.font(), Vector2.ZERO, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, col)
	draw_set_transform_matrix(Transform2D.IDENTITY)

# ---------------------------------------------------------------- 楣饰文字

## 楣饰主标题：按面板性质取「领 受 / 祝 圣 / 圣 约」
func _rite_label() -> String:
	var has_fusion: bool = false
	var has_covenant: bool = false
	for o in options:
		var k: String = String(o.get("kind", ""))
		if k == "fusion":
			has_fusion = true
		elif k == "covenant":
			has_covenant = true
	if has_fusion:
		return "祝 圣"
	if has_covenant:
		return "圣 约"
	return "领 受"

## 楣饰副标题：title 里「·」后面的部分（如 "Lv 3" / "乌陵与土明"）
func _rite_sub() -> String:
	var parts: PackedStringArray = title.split("·", false)
	if parts.size() < 2:
		return ""
	var sub: String = String(parts[1]).strip_edges()
	var label: String = _rite_label().replace(" ", "")
	# 去掉与楣饰主标题重复的开头（如「祝圣与合鸣」→「合鸣」）
	if sub.begins_with(label):
		sub = sub.substr(label.length()).strip_edges()
		if sub.begins_with("与") or sub.begins_with("、") or sub.begins_with("·"):
			sub = sub.substr(1).strip_edges()
	return sub

# ---------------------------------------------------------------- 输入

func _gui_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		var p: Vector2 = (event as InputEventMouseMotion).position
		var h: int = -1
		for i in range(options.size()):
			if _card_hit_rect(i).has_point(p):
				h = i
				break
		if h != hover:
			hover = h
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			for i in range(options.size()):
				if _card_hit_rect(i).has_point(mb.position):
					_choose(i)
					return

func _unhandled_key_input(event: InputEvent) -> void:
	if not active:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var k: int = key.keycode
	if k >= KEY_1 and k <= KEY_9:
		var idx: int = k - KEY_1
		if idx < options.size():
			_choose(idx)
	elif k == KEY_R:
		# 只有领受面板有重掷；次数由 run 侧判定，这里只转发
		reroll_requested.emit()

func _choose(i: int) -> void:
	if not active:
		return
	active = false
	visible = false
	picked.emit(i)
