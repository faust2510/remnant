extends Control
## 标题 / 见证人选择。4 张卡（2×2），键盘或鼠标选人后进入以拉谷。

const CARD_W := 276.0
const CARD_H := 88.0
const X0 := 36.0
const Y0 := 118.0
const GAP_X := 16.0
const GAP_Y := 14.0

var ids: Array = []
var sel: int = 0
var hover: int = -1
var t: float = 0.0
var shot_title: bool = false
var shot_path: String = "/tmp/title.png"
var shot_frames: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
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

func _go(i: int, direct: bool = false) -> void:
	RunCfg.character_id = String(ids[i]) if i >= 0 and i < ids.size() else "david"
	var target: String = "res://scenes/main.tscn" if direct else "res://scenes/camp.tscn"
	get_tree().change_scene_to_file.call_deferred(target)

func _card_rect(i: int) -> Rect2:
	var cx: int = i % 2
	var cy: int = i / 2
	return Rect2(X0 + float(cx) * (CARD_W + GAP_X), Y0 + float(cy) * (CARD_H + GAP_Y), CARD_W, CARD_H)

func _process(d: float) -> void:
	t += d
	var m: Vector2 = get_local_mouse_position()
	hover = -1
	for i in range(ids.size()):
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
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if hover >= 0:
			_go(hover)
			return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_LEFT, KEY_A:
				sel = maxi(sel - 1, 0)
			KEY_RIGHT, KEY_D:
				sel = mini(sel + 1, ids.size() - 1)
			KEY_UP, KEY_W:
				sel = maxi(sel - 2, 0)
			KEY_DOWN, KEY_S:
				sel = mini(sel + 2, ids.size() - 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_go(sel)
			KEY_ESCAPE:
				get_tree().quit()

func _draw() -> void:
	var f: Font = GameFont.get_font()
	# 背景
	draw_rect(Rect2(0, 0, 640, 360), Color("#15120D"), true)
	for gx in range(0, 40):
		var x: float = float(gx) * 16.0
		draw_line(Vector2(x, 0), Vector2(x, 360), Color(0.10, 0.09, 0.07, 1.0), 1.0)
	# 顶部光
	var glow: float = 0.05 + 0.02 * sin(t * 1.1)
	draw_rect(Rect2(0, 0, 640, 96), Color(0.85, 0.68, 0.32, glow), true)

	draw_string(f, Vector2(0, 52), "余  民", HORIZONTAL_ALIGNMENT_CENTER, 640, 34, Color("#E8D6A8"))
	draw_string(f, Vector2(0, 70), "T H E   R E M N A N T", HORIZONTAL_ALIGNMENT_CENTER, 640, 9, Color(0.72, 0.63, 0.45))
	draw_string(f, Vector2(0, 92), "我们既有这许多的见证人，如同云彩围着我们   来 12:1", HORIZONTAL_ALIGNMENT_CENTER, 640, 9, Color(0.62, 0.58, 0.50))
	draw_line(Vector2(150, 100), Vector2(490, 100), Color(0.45, 0.38, 0.24), 1.0)

	for i in range(ids.size()):
		var c: Dictionary = GameData.characters[i]
		var r: Rect2 = _card_rect(i)
		var on: bool = (i == sel) or (i == hover)
		draw_rect(r, Color(0.10, 0.09, 0.07) if not on else Color(0.15, 0.13, 0.09), true)
		draw_rect(r, Color("#C9A66B") if on else Color(0.28, 0.25, 0.18), false, 2.0 if on else 1.0)
		if on:
			draw_circle(r.position + Vector2(14, 14), 3.0, Color("#E0B85A"))
		draw_string(f, r.position + Vector2(26, 24), String(c.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#E8DCC0"))
		draw_string(f, r.position + Vector2(26, 38), String(c.get("scripture", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.60, 0.55, 0.42))
		var wn: String = String(GameData.weapons.get(String(c.get("weapon", "")), {}).get("name", c.get("weapon", "?")))
		draw_string(f, r.position + Vector2(CARD_W - 96, 24), "起始 · " + wn, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#B8C4A8"))
		var lines: PackedStringArray = String(c.get("desc", "")).split("\n")
		for li in range(mini(lines.size(), 2)):
			var col_txt := Color(0.78, 0.74, 0.66) if li == 0 else Color(0.65, 0.62, 0.55)
			draw_string(f, r.position + Vector2(26, 58 + float(li) * 12.0), lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col_txt)

	var hint: String = "← ↑ → ↓ 选择      Enter 整备出发（营地）      Esc 退出"
	draw_string(f, Vector2(0, 344), hint, HORIZONTAL_ALIGNMENT_CENTER, 640, 9, Color(0.55, 0.52, 0.46))
