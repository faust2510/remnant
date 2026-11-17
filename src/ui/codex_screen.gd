class_name CodexScreen
extends Control
## 图鉴：圣物 12 / 成就 40 / 见证人 20。左列表右详情，全部数据来自 data/*.json 与 Meta。
## 入口：营地或标题页按 V，营地顶部「图鉴」页签；Esc / V 返回来源页面。

static var back_scene: String = "res://scenes/camp.tscn"

const TAB_NAMES := ["圣物", "成就", "见证人"]
const LIST_X := 28.0
const LIST_Y := 80.0
const LIST_W := 300.0
const LIST_H := 236.0
const LIST_ROW := 22.0
const LIST_ROWS := 10
const DET_X := 336.0
const DET_W := 276.0

var tab: int = 0
var sel: int = 0
var scroll: int = 0
var hover: int = -1
var t: float = 0.0
var sfx: Sfx
var selftest: bool = false
var shot_codex: bool = false
var shot_path: String = "/tmp/codex.png"
var shot_frames: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	sfx = Sfx.new()
	add_child(sfx)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a == "--codex-selftest":
			selftest = true
		elif a == "--shot-codex":
			shot_codex = true
		elif a.begins_with("--shot-path="):
			shot_path = a.substr(12)
		elif a.begins_with("--codex-tab="):
			tab = clampi(int(a.substr(12)), 0, 2)
	if selftest:
		_selftest()
		return

func _selftest() -> void:
	var relics: int = 0
	for r in GameData.relics:
		if Meta.has_relic(String(r.get("id", ""))):
			relics += 1
	print("[codex] relics=%d unlocked=%d" % [GameData.relics.size(), relics])
	var done: int = 0
	for a in GameData.achievements:
		if Meta.has_achievement(String(a.get("id", ""))):
			done += 1
	print("[codex] achievements=%d done=%d" % [GameData.achievements.size(), done])
	var witnesses: int = 0
	for c in GameData.characters:
		if UIText.character_unlocked(c):
			witnesses += 1
	print("[codex] witnesses=%d unlocked=%d" % [GameData.characters.size(), witnesses])
	for i in range(3):
		tab = i
		sel = 0
		scroll = 0
		var es: Array = _entries()
		if es.is_empty():
			print("[codex] tab=%d entries=0" % i)
		else:
			print("[codex] tab=%d entries=%d first=%s" % [i, es.size(), String(es[0].get("name", "?"))])
	print("[codex] back=%s" % back_scene)
	print("[codex] SELFTEST_DONE")
	get_tree().quit()

func _entries() -> Array:
	match tab:
		0:
			return GameData.relics
		1:
			return GameData.achievements
		2:
			return GameData.characters
	return []

func _entry_unlocked(e: Dictionary) -> bool:
	match tab:
		0:
			return Meta.has_relic(String(e.get("id", "")))
		1:
			return Meta.has_achievement(String(e.get("id", "")))
		2:
			return UIText.character_unlocked(e)
	return false

func _total() -> int:
	return _entries().size()

func _collected() -> int:
	var n: int = 0
	for e in _entries():
		if _entry_unlocked(e):
			n += 1
	return n

func _tab_rect(i: int) -> Rect2:
	return Rect2(28.0 + float(i) * 100.0, 52.0, 92.0, 22.0)

func _row_rect(i: int) -> Rect2:
	return Rect2(LIST_X, LIST_Y + 4.0 + float(i) * LIST_ROW, LIST_W, LIST_ROW - 2.0)

func _clamp_sel() -> void:
	var n: int = _total()
	if n <= 0:
		sel = 0
		scroll = 0
		return
	sel = clampi(sel, 0, n - 1)
	scroll = clampi(scroll, 0, maxi(0, n - LIST_ROWS))
	if sel < scroll:
		scroll = sel
	elif sel >= scroll + LIST_ROWS:
		scroll = sel - LIST_ROWS + 1

func _back() -> void:
	var target: String = back_scene if back_scene != "" else "res://scenes/camp.tscn"
	sfx.play("dash", -8.0)
	get_tree().change_scene_to_file.call_deferred(target)

func _switch_tab(dir: int) -> void:
	tab = (tab + dir + TAB_NAMES.size()) % TAB_NAMES.size()
	sel = 0
	scroll = 0
	sfx.play("pickup", -12.0)

func _process(d: float) -> void:
	t += d
	var m: Vector2 = get_local_mouse_position()
	hover = -1
	for i in range(LIST_ROWS):
		if _row_rect(i).has_point(m):
			var idx: int = scroll + i
			if idx >= 0 and idx < _total():
				hover = idx
	queue_redraw()
	if shot_codex:
		shot_frames += 1
		if shot_frames >= 6:
			var img: Image = get_viewport().get_texture().get_image()
			if img != null:
				img.save_png(shot_path)
			print("[shot] codex saved ", shot_path)
			get_tree().quit()

func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		var m: Vector2 = e.position
		if e.button_index == MOUSE_BUTTON_LEFT:
			for i in range(TAB_NAMES.size()):
				if _tab_rect(i).has_point(m):
					tab = i
					sel = 0
					scroll = 0
					sfx.play("pickup", -12.0)
					return
			for i in range(LIST_ROWS):
				if _row_rect(i).has_point(m):
					var idx: int = scroll + i
					if idx >= 0 and idx < _total():
						sel = idx
						sfx.play("pickup", -14.0)
					return
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll = maxi(0, scroll - 3)
			_clamp_sel()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll = mini(maxi(0, _total() - LIST_ROWS), scroll + 3)
			_clamp_sel()
		return
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = e.keycode
	match k:
		KEY_UP, KEY_W:
			sel = maxi(0, sel - 1)
		KEY_DOWN, KEY_S:
			sel = mini(_total() - 1, sel + 1)
		KEY_PAGEUP:
			sel = maxi(0, sel - LIST_ROWS)
		KEY_PAGEDOWN:
			sel = mini(_total() - 1, sel + LIST_ROWS)
		KEY_HOME:
			sel = 0
		KEY_END:
			sel = maxi(0, _total() - 1)
		KEY_LEFT, KEY_A:
			_switch_tab(-1)
		KEY_RIGHT, KEY_D:
			_switch_tab(1)
		KEY_TAB:
			_switch_tab(-1 if e.shift_pressed else 1)
		KEY_1:
			tab = 0
			sel = 0
		KEY_2:
			tab = 1
			sel = 0
		KEY_3:
			tab = 2
			sel = 0
		KEY_ESCAPE, KEY_V:
			_back()
			return
	_clamp_sel()
	sfx.play("pickup", -16.0, 1.3)

func _draw() -> void:
	var f: Font = GameFont.get_font()
	draw_rect(Rect2(0, 0, 640, 360), Color(0.055, 0.06, 0.08), true)
	for i in range(6):
		draw_rect(Rect2(0, float(i) * 60.0, 640, 30.0), Color(1, 1, 1, 0.012), true)
	draw_string(f, Vector2(28, 34), "图  鉴", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.94, 0.90, 0.78))
	draw_string(f, Vector2(140, 34), "圣物 · 成就 · 见证人", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.56, 0.52))
	draw_string(f, Vector2(400, 32), "已收集  %d / %d" % [_collected(), _total()], HORIZONTAL_ALIGNMENT_RIGHT, 212, 12, Color(0.95, 0.80, 0.35))
	draw_line(Vector2(28, 44), Vector2(612, 44), Color(0.28, 0.28, 0.26), 1.0)
	for i in range(TAB_NAMES.size()):
		var r: Rect2 = _tab_rect(i)
		var on: bool = i == tab
		draw_rect(r, Color(0.14, 0.15, 0.18) if on else Color(0.09, 0.10, 0.12), true)
		draw_rect(r, Color(0.95, 0.80, 0.38) if on else Color(0.24, 0.25, 0.27), false, 1.0)
		draw_string(f, Vector2(r.position.x, r.position.y + 15), TAB_NAMES[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, Color(0.96, 0.92, 0.80) if on else Color(0.62, 0.63, 0.62))
	var es: Array = _entries()
	_draw_list(f, es)
	_draw_detail(f, es)
	draw_string(f, Vector2(28, 340), "↑↓ 浏览 · PgUp/PgDn 翻页 · Tab 切页 · Esc / V 返回", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.44, 0.46, 0.44))

func _draw_list(f: Font, es: Array) -> void:
	draw_rect(Rect2(LIST_X, LIST_Y, LIST_W, LIST_H), Color(0.075, 0.08, 0.10), true)
	draw_rect(Rect2(LIST_X, LIST_Y, LIST_W, LIST_H), Color(0.24, 0.25, 0.26), false, 1.0)
	if es.is_empty():
		draw_string(f, Vector2(LIST_X + 12, LIST_Y + 24), "数据缺失（data/*.json 未加载）", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.5, 0.45))
		return
	var shown: int = mini(LIST_ROWS, es.size() - scroll)
	for i in range(maxi(shown, 0)):
		var idx: int = scroll + i
		var e: Dictionary = es[idx]
		var r: Rect2 = _row_rect(i)
		var on: bool = idx == sel
		var hv: bool = idx == hover
		if on:
			draw_rect(r, Color(0.16, 0.15, 0.10), true)
			draw_rect(Rect2(r.position.x, r.position.y, 3, r.size.y), Color(0.95, 0.80, 0.38), true)
		elif hv:
			draw_rect(r, Color(0.11, 0.11, 0.13), true)
		var unlocked: bool = _entry_unlocked(e)
		var mark: String = "✓" if unlocked else "锁"
		var mark_c: Color = Color(0.55, 0.85, 0.60) if unlocked else Color(0.48, 0.44, 0.40)
		draw_string(f, Vector2(r.position.x + 10, r.position.y + 14), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, mark_c)
		var nm: String = UIText.clip(String(e.get("name", e.get("id", "?"))), 16)
		draw_string(f, Vector2(r.position.x + 30, r.position.y + 15), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.92, 0.89, 0.78) if unlocked else Color(0.56, 0.56, 0.54))
		var right: String = ""
		match tab:
			0:
				right = String(e.get("effect", ""))
			1:
				var rw: Dictionary = e.get("reward", {})
				right = ("+%d" % int(rw.get("silver", 0))) if int(rw.get("silver", 0)) > 0 else ""
			2:
				right = "生命 %d" % int(e.get("hp", 0))
		if right != "":
			draw_string(f, Vector2(r.position.x + r.size.x - 76, r.position.y + 14), right, HORIZONTAL_ALIGNMENT_RIGHT, 68, 8, Color(0.50, 0.56, 0.50))
	if es.size() > LIST_ROWS:
		var track_h: float = LIST_H - 12.0
		draw_rect(Rect2(LIST_X + LIST_W - 4, LIST_Y + 6, 2, track_h), Color(0.18, 0.19, 0.20), true)
		var frac: float = float(scroll) / float(maxi(es.size() - LIST_ROWS, 1))
		var bar_h: float = track_h * float(LIST_ROWS) / float(es.size())
		draw_rect(Rect2(LIST_X + LIST_W - 4, LIST_Y + 6 + frac * (track_h - bar_h), 2, bar_h), Color(0.75, 0.65, 0.40), true)

func _draw_detail(f: Font, es: Array) -> void:
	draw_rect(Rect2(DET_X, LIST_Y, DET_W, LIST_H), Color(0.085, 0.09, 0.11), true)
	draw_rect(Rect2(DET_X, LIST_Y, DET_W, LIST_H), Color(0.24, 0.25, 0.26), false, 1.0)
	if es.is_empty() or sel < 0 or sel >= es.size():
		return
	var e: Dictionary = es[sel]
	var x: float = DET_X + 12.0
	var w: float = DET_W - 24.0
	match tab:
		0:
			_draw_relic_detail(f, e, x, w)
		1:
			_draw_ach_detail(f, e, x, w)
		2:
			_draw_witness_detail(f, e, x, w)

func _draw_relic_detail(f: Font, e: Dictionary, x: float, w: float) -> void:
	var unlocked: bool = Meta.has_relic(String(e.get("id", "")))
	draw_string(f, Vector2(x, 104), String(e.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, w, 15, Color(0.96, 0.90, 0.74))
	draw_string(f, Vector2(x, 118), String(e.get("scripture", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 9, Color(0.58, 0.54, 0.44))
	draw_string(f, Vector2(x, 138), "已解锁" if unlocked else "未解锁", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.85, 0.60) if unlocked else Color(0.78, 0.42, 0.38))
	draw_multiline_string(f, Vector2(x, 156), String(e.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 9, 4, Color(0.80, 0.77, 0.68))
	draw_string(f, Vector2(x, 220), "词条 · " + String(e.get("effect", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 8, Color(0.62, 0.72, 0.64))
	var unlock: Dictionary = e.get("unlock", {})
	var stage_id: String = String(unlock.get("stage", ""))
	var wins: int = int(unlock.get("wins", 0))
	var req: String = UIText.stage_name(stage_id)
	if wins > 0:
		req += "（得胜 %d 次）" % wins
	draw_multiline_string(f, Vector2(x, 240), "解锁 · " + req, HORIZONTAL_ALIGNMENT_LEFT, w, 8, 2, Color(0.68, 0.62, 0.52))
	draw_multiline_string(f, Vector2(x, 268), String(e.get("note", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 7, 3, Color(0.50, 0.50, 0.48))

func _draw_ach_detail(f: Font, e: Dictionary, x: float, w: float) -> void:
	var done: bool = Meta.has_achievement(String(e.get("id", "")))
	draw_string(f, Vector2(x, 104), UIText.clip(String(e.get("name", "?")), 22), HORIZONTAL_ALIGNMENT_LEFT, w, 13, Color(0.96, 0.90, 0.74))
	draw_multiline_string(f, Vector2(x, 126), String(e.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 9, 3, Color(0.80, 0.77, 0.68))
	draw_multiline_string(f, Vector2(x, 172), "条件 · " + UIText.achievement_cond_text(e), HORIZONTAL_ALIGNMENT_LEFT, w, 8, 2, Color(0.66, 0.66, 0.60))
	draw_multiline_string(f, Vector2(x, 202), "奖励 · " + UIText.achievement_reward_text(e), HORIZONTAL_ALIGNMENT_LEFT, w, 8, 2, Color(0.72, 0.62, 0.42))
	draw_string(f, Vector2(x, 230), "已达成 ✓" if done else "未达成", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.85, 0.60) if done else Color(0.55, 0.52, 0.46))
	draw_multiline_string(f, Vector2(x, 254), String(e.get("note", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 7, 3, Color(0.50, 0.50, 0.48))

func _draw_witness_detail(f: Font, e: Dictionary, x: float, w: float) -> void:
	var unlocked: bool = UIText.character_unlocked(e)
	var cid: String = String(e.get("id", ""))
	var title: String = String(e.get("name", "?"))
	if Meta.is_awakened(cid):
		title += "  ★"
	draw_string(f, Vector2(x, 104), title, HORIZONTAL_ALIGNMENT_LEFT, w, 15, Color(0.96, 0.90, 0.74) if unlocked else Color(0.58, 0.58, 0.55))
	draw_string(f, Vector2(x, 118), String(e.get("scripture", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 9, Color(0.58, 0.54, 0.44))
	var wn: String = String(GameData.weapons.get(String(e.get("weapon", "")), {}).get("name", String(e.get("weapon", "?"))))
	draw_string(f, Vector2(x, 134), "生命 %d · 速度 %d · 起始 %s" % [int(e.get("hp", 0)), int(e.get("speed", 0)), wn], HORIZONTAL_ALIGNMENT_LEFT, w, 8, Color(0.66, 0.68, 0.62))
	draw_string(f, Vector2(x, 152), "天赋", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.74, 0.68, 0.52))
	var items: Array = UIText.perk_items(e.get("perk", {}))
	for i in range(mini(items.size(), 2)):
		draw_string(f, Vector2(x, 166 + float(i) * 12.0), String(items[i]), HORIZONTAL_ALIGNMENT_LEFT, w, 9, Color(0.82, 0.79, 0.70))
	var awk: Dictionary = e.get("awakening", {})
	if not awk.is_empty():
		draw_string(f, Vector2(x, 196), "觉醒 · " + String(awk.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 9, Color(0.86, 0.74, 0.44))
		draw_multiline_string(f, Vector2(x, 210), String(awk.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 8, 2, Color(0.66, 0.64, 0.58))
	var unlock: Dictionary = e.get("unlock", {})
	var silver: int = int(unlock.get("silver", 0))
	var line: String = "解锁 · " + UIText.character_unlock_text(e)
	if silver > 0:
		line += "  ·  %d 银两" % silver
	draw_multiline_string(f, Vector2(x, 242), line, HORIZONTAL_ALIGNMENT_LEFT, w, 8, 3, Color(0.68, 0.62, 0.52))
	draw_multiline_string(f, Vector2(x, 276), String(e.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 7, 2, Color(0.50, 0.50, 0.48))
