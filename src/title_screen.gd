extends Control
## 标题 / 见证人选择。20 位见证人卡片，2 列 × 3 行的滚动窗口。
## 已解锁可选，未解锁显示条件与灰态；选人后把 character_id 交给营地/单局。

const CARD_W := 276.0
const CARD_H := 58.0
const X0 := 36.0
const Y0 := 120.0
const GAP_X := 16.0
const GAP_Y := 8.0
const VIS_COLS := 2
const VIS_ROWS := 3
const VIS_COUNT := 6

var ids: Array = []
var sel: int = 0
var window_start: int = 0
var hover: int = -1
var t: float = 0.0
var sfx: Sfx
var notice: String = ""
var notice_t: float = 0.0
var shot_title: bool = false
var shot_path: String = "/tmp/title.png"
var shot_frames: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	sfx = Sfx.new()
	add_child(sfx)
	for c in GameData.characters:
		ids.append(String(c.get("id", "")))
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a == "--shot-title":
			shot_title = true
		elif a.begins_with("--shot-path="):
			shot_path = a.substr(12)
	if shot_title:
		return
	if args.has("--title-selftest"):
		var unlocked: int = 0
		for c in GameData.characters:
			if UIText.character_unlocked(c):
				unlocked += 1
		print("[title] witnesses=%d unlocked=%d first=%s last=%s" % [ids.size(), unlocked, ids[0] if not ids.is_empty() else "-", ids[ids.size() - 1] if not ids.is_empty() else "-"])
		for i in range(ids.size()):
			sel = i
			_ensure_visible()
			if i % 6 == 5:
				print("[title] scroll sel=%d window_start=%d" % [sel, window_start])
		print("[title] SELFTEST_DONE")
		get_tree().quit()
		return
	for a in args:
		if a == "--camp-selftest":
			_go(0, false)
			return
		if a == "--shot-camp":
			for b in args:
				if b.begins_with("--char="):
					_go(maxi(ids.find(b.substr(7)), 0), false)
					return
			_go(0, false)
			return
	for a in args:
		if a == "--sim" or a == "--sim-god" or a == "--shot" or a == "--shot-modal" or a.begins_with("--char=") or a.begins_with("--sim-speed=") or a.begins_with("--shot-"):
			_go(0 if not a.begins_with("--char=") else maxi(ids.find(a.substr(7)), 0), true)
			return
	if RunCfg.skip_title:
		_go(maxi(ids.find(RunCfg.character_id), 0), true)
		return
	if GameData.characters.is_empty():
		RunCfg.character_id = "david"
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	_ensure_visible()

func _char(i: int) -> Dictionary:
	if i < 0 or i >= GameData.characters.size():
		return {}
	return GameData.characters[i]

func _selectable(i: int) -> bool:
	if i < 0 or i >= ids.size():
		return false
	return UIText.character_unlocked(_char(i))

func _go(i: int, direct: bool = false) -> void:
	RunCfg.character_id = String(ids[i]) if i >= 0 and i < ids.size() else "david"
	var target: String = "res://scenes/main.tscn" if direct else "res://scenes/camp.tscn"
	get_tree().change_scene_to_file.call_deferred(target)

func _try_select(i: int) -> void:
	if not _selectable(i):
		var c: Dictionary = _char(i)
		notice = "「%s」未解锁：%s" % [String(c.get("name", "?")), UIText.character_unlock_text(c)]
		notice_t = 2.6
		sfx.play("hit", -12.0, 0.8)
		return
	sfx.play("dash", -8.0)
	_go(i)

func _open_codex() -> void:
	CodexScreen.back_scene = "res://scenes/title.tscn"
	sfx.play("pickup", -10.0)
	get_tree().change_scene_to_file.call_deferred("res://scenes/codex.tscn")

func _card_rect(i: int) -> Rect2:
	var local: int = i - window_start
	var cx: int = local % VIS_COLS
	var cy: int = local / VIS_COLS
	return Rect2(X0 + float(cx) * (CARD_W + GAP_X), Y0 + float(cy) * (CARD_H + GAP_Y), CARD_W, CARD_H)

func _window_max() -> int:
	return maxi(0, ids.size() - VIS_COUNT)

func _ensure_visible() -> void:
	if ids.is_empty():
		return
	sel = clampi(sel, 0, ids.size() - 1)
	var ws: int = window_start
	if sel < ws:
		ws = sel
	elif sel >= ws + VIS_COUNT:
		ws = sel - VIS_COUNT + 1
	ws = clampi(ws, 0, _window_max())
	if ws % 2 != 0:
		ws = maxi(0, ws - 1)
	window_start = ws

func _process(d: float) -> void:
	t += d
	notice_t = maxf(0.0, notice_t - d)
	var m: Vector2 = get_local_mouse_position()
	hover = -1
	for i in range(window_start, mini(window_start + VIS_COUNT, ids.size())):
		if _card_rect(i).has_point(m):
			hover = i
	queue_redraw()
	if shot_title:
		shot_frames += 1
		if shot_frames == 6:
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png(shot_path)
			print("[shot] title saved ", shot_path, " ", img.get_width(), "x", img.get_height())
			get_tree().quit()

func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if hover >= 0:
				sel = hover
				_try_select(hover)
				return
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			sel = maxi(0, sel - 2)
			_ensure_visible()
			return
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			sel = mini(ids.size() - 1, sel + 2)
			_ensure_visible()
			return
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	match e.keycode:
		KEY_LEFT, KEY_A:
			sel = maxi(0, sel - 1)
		KEY_RIGHT, KEY_D:
			sel = mini(ids.size() - 1, sel + 1)
		KEY_UP, KEY_W:
			sel = maxi(0, sel - 2)
		KEY_DOWN, KEY_S:
			sel = mini(ids.size() - 1, sel + 2)
		KEY_PAGEUP:
			sel = maxi(0, sel - VIS_COUNT)
		KEY_PAGEDOWN:
			sel = mini(ids.size() - 1, sel + VIS_COUNT)
		KEY_HOME:
			sel = 0
		KEY_END:
			sel = maxi(0, ids.size() - 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_try_select(sel)
		KEY_V:
			_open_codex()
			return
		KEY_ESCAPE:
			get_tree().quit()
	_ensure_visible()
	sfx.play("pickup", -16.0, 1.3)

func _draw() -> void:
	var f: Font = GameFont.get_font()
	draw_rect(Rect2(0, 0, 640, 360), Color("#15120D"), true)
	for gx in range(0, 40):
		var x: float = float(gx) * 16.0
		draw_line(Vector2(x, 0), Vector2(x, 360), Color(0.10, 0.09, 0.07, 1.0), 1.0)
	var glow: float = 0.05 + 0.02 * sin(t * 1.1)
	draw_rect(Rect2(0, 0, 640, 96), Color(0.85, 0.68, 0.32, glow), true)
	draw_string(f, Vector2(0, 52), "余  民", HORIZONTAL_ALIGNMENT_CENTER, 640, 34, Color("#E8D6A8"))
	draw_string(f, Vector2(0, 70), "T H E   R E M N A N T", HORIZONTAL_ALIGNMENT_CENTER, 640, 9, Color(0.72, 0.63, 0.45))
	draw_string(f, Vector2(0, 92), "我们既有这许多的见证人，如同云彩围着我们   来 12:1", HORIZONTAL_ALIGNMENT_CENTER, 640, 9, Color(0.62, 0.58, 0.50))
	draw_line(Vector2(150, 98), Vector2(490, 98), Color(0.45, 0.38, 0.24), 1.0)
	var unlocked: int = 0
	for i in range(ids.size()):
		if _selectable(i):
			unlocked += 1
	var pages: int = maxi(1, ceili(float(ids.size()) / float(VIS_COUNT)))
	draw_string(f, Vector2(36, 112), "见证人 · 已解锁 %d / %d" % [unlocked, ids.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.60, 0.56, 0.44))
	draw_string(f, Vector2(504, 112), "第 %d / %d 页" % [window_start / VIS_COUNT + 1, pages], HORIZONTAL_ALIGNMENT_RIGHT, 100, 8, Color(0.60, 0.56, 0.44))
	var last: int = mini(window_start + VIS_COUNT, ids.size())
	for i in range(window_start, last):
		_draw_card(f, i)
	if notice_t > 0.0:
		draw_string(f, Vector2(0, 322), notice, HORIZONTAL_ALIGNMENT_CENTER, 640, 9, Color(0.95, 0.72, 0.55, clampf(notice_t, 0.0, 1.0)))
	draw_string(f, Vector2(0, 344), "← ↑ → ↓ 选择      Enter 整备出发（营地）      V 图鉴      Esc 退出", HORIZONTAL_ALIGNMENT_CENTER, 640, 9, Color(0.55, 0.52, 0.46))

func _draw_card(f: Font, i: int) -> void:
	var c: Dictionary = _char(i)
	if c.is_empty():
		return
	var r: Rect2 = _card_rect(i)
	var ok: bool = _selectable(i)
	var on: bool = (i == sel) or (i == hover)
	var bg: Color = Color(0.10, 0.09, 0.07) if ok else Color(0.075, 0.075, 0.075)
	if on:
		bg = Color(0.15, 0.13, 0.09) if ok else Color(0.11, 0.10, 0.09)
	draw_rect(r, bg, true)
	var border: Color = Color("#C9A66B") if on and ok else (Color(0.40, 0.34, 0.24) if ok else Color(0.22, 0.21, 0.19))
	draw_rect(r, border, false, 2.0 if on else 1.0)
	if on:
		draw_circle(r.position + Vector2(12, 12), 3.0, Color("#E0B85A") if ok else Color(0.45, 0.38, 0.30))
	var name_c: Color = Color("#E8DCC0") if ok else Color(0.52, 0.51, 0.48)
	draw_string(f, r.position + Vector2(22, 20), String(c.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, name_c)
	draw_string(f, r.position + Vector2(22, 32), String(c.get("scripture", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.60, 0.55, 0.42))
	var wname: String = String(GameData.weapons.get(String(c.get("weapon", "")), {}).get("name", String(c.get("weapon", "?"))))
	draw_string(f, r.position + Vector2(CARD_W - 130, 20), "起始 · " + wname, HORIZONTAL_ALIGNMENT_RIGHT, 118, 8, Color(0.70, 0.74, 0.63) if ok else Color(0.44, 0.45, 0.42))
	var line3: String
	var line3_c: Color
	if ok:
		line3 = UIText.perk_text(c.get("perk", {}), 1)
		if line3 == "":
			line3 = String(c.get("desc", "")).split("\n")[0] if String(c.get("desc", "")) != "" else ""
		line3_c = Color(0.76, 0.74, 0.66)
	else:
		line3 = "未解锁 · " + UIText.clip(UIText.character_unlock_text(c), 30)
		line3_c = Color(0.72, 0.48, 0.40)
	draw_string(f, r.position + Vector2(22, 46), UIText.clip(line3, 34), HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 34, 8, line3_c)
	if not ok:
		draw_string(f, r.position + Vector2(CARD_W - 30, 46), "锁", HORIZONTAL_ALIGNMENT_RIGHT, 18, 8, Color(0.60, 0.40, 0.34))
	if Meta.is_awakened(String(c.get("id", ""))):
		draw_string(f, r.position + Vector2(CARD_W - 24, 34), "★", HORIZONTAL_ALIGNMENT_RIGHT, 14, 9, Color(0.92, 0.78, 0.40))
