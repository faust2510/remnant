extends Control
## 营地：花舍客勒买永久强化、选七印与试炼之地，然后出发。
## 行 0..5 = 六项强化，行 6 = 试炼（←→ 切换已解锁地图），行 7 = 出发。

const ROW_X := 28.0
const ROW_W := 344.0
const ROW_H := 27.0
const ROW_STEP := 31.0
const ROW_Y0 := 64.0
const PANEL_X := 384.0
const PANEL_W := 228.0

var sel: int = 0
var hover: int = -1
var t: float = 0.0
var sfx: Sfx
var flash: float = 0.0
var shot_camp: bool = false
var shot_path: String = "/tmp/camp.png"
var shot_frames: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	sfx = Sfx.new()
	add_child(sfx)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a == "--shot-camp":
			shot_camp = true
		elif a.begins_with("--shot-path="):
			shot_path = a.substr(12)
	for a in args:
		if a == "--camp-selftest":
			_selftest()
			return
	if shot_camp:
		return
	# 命令行直接开跑时跳过营地
	for a in args:
		if a == "--sim" or a == "--sim-god" or a == "--shot" or a == "--shot-modal" or a.begins_with("--char=") or a.begins_with("--sim-speed=") or a.begins_with("--shot-"):
			_enter()
			return

func _selftest() -> void:
	print("[camp] start shillings=%d" % Meta.shillings)
	for u in Meta.UPGRADES:
		var id: String = String(u["id"])
		var cost: int = Meta.upgrade_cost(id)
		var ok: bool = Meta.buy(id)
		print("[camp] buy %s cost=%d ok=%s lv=%d left=%d" % [id, cost, str(ok), Meta.level_of(id), Meta.shillings])
	print("[camp] bonus=%s" % str(Meta.bonus()))
	print("[camp] seals=%d selected=%d" % [Meta.seals, Meta.selected_seal])
	# 键盘导航自检：连按 7 次下键应绕回 0，中途经过「进入以拉谷」行
	var start_sel: int = sel
	for i in range(_rows()):
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.keycode = KEY_DOWN
		_input(ev)
	print("[camp] nav start=%d after7=%d rows=%d" % [start_sel, sel, _rows()])
	print("[camp] SELFTEST_DONE")
	get_tree().quit()

func _rows() -> int:
	return Meta.UPGRADES.size() + 2

func _stage_row() -> int:
	return Meta.UPGRADES.size()

func _cur_stage_index() -> int:
	for i in range(GameData.stages.size()):
		if String(GameData.stages[i].get("id", "")) == Meta.stage_id:
			return i
	return 0

func _stage_def() -> Dictionary:
	var i: int = _cur_stage_index()
	if i < 0 or i >= GameData.stages.size():
		return {}
	return GameData.stages[i]

func _stage_unlocked(i: int) -> bool:
	if i < 0 or i >= GameData.stages.size():
		return false
	var need: int = int(GameData.stages[i].get("unlock_wins", 0))
	return Meta.wins >= need

## 在已解锁的试炼之间切换（dir = +1 / -1）
func _cycle_stage(dir: int) -> void:
	var n: int = GameData.stages.size()
	if n <= 1:
		return
	var i: int = _cur_stage_index()
	for step in range(1, n + 1):
		var j: int = (i + dir * step + n * 4) % n
		if _stage_unlocked(j):
			Meta.stage_id = String(GameData.stages[j].get("id", Meta.stage_id))
			Meta.save_save()
			sfx.play("pickup", -10.0, 1.05)
			return
	sfx.play("hit", -14.0, 0.7)

func _row_rect(i: int) -> Rect2:
	return Rect2(ROW_X, ROW_Y0 + float(i) * ROW_STEP, ROW_W, ROW_H)

func _enter() -> void:
	RunCfg.stage_id = Meta.stage_id
	RunCfg.character_id = RunCfg.character_id if RunCfg.character_id != "" else "david"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")

func _activate(i: int) -> void:
	if i < Meta.UPGRADES.size():
		var u: Dictionary = Meta.UPGRADES[i]
		var id: String = String(u["id"])
		if Meta.level_of(id) >= int(u["max"]):
			sfx.play("hit", -12.0)
			return
		if Meta.buy(id):
			sfx.play("level", -4.0)
			flash = 1.0
		else:
			sfx.play("hit", -14.0, 0.7)
	elif i == _stage_row():
		_cycle_stage(1)
	else:
		sfx.play("dash", -6.0)
		_enter()

func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = e.keycode
	if k == KEY_UP or k == KEY_W:
		sel = (sel - 1 + _rows()) % _rows()
	elif k == KEY_DOWN or k == KEY_S:
		sel = (sel + 1) % _rows()
	elif k == KEY_LEFT or k == KEY_A:
		if sel == _stage_row():
			_cycle_stage(-1)
		else:
			Meta.selected_seal = maxi(1, Meta.selected_seal - 1)
			Meta.save_save()
			sfx.play("pickup", -10.0)
	elif k == KEY_RIGHT or k == KEY_D:
		if sel == _stage_row():
			_cycle_stage(1)
		else:
			Meta.selected_seal = mini(Meta.seals, Meta.selected_seal + 1)
			Meta.save_save()
			sfx.play("pickup", -10.0)
	elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
		_activate(sel)
	elif k == KEY_ESCAPE:
		get_tree().change_scene_to_file.call_deferred("res://scenes/title.tscn")

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var m: Vector2 = e.position
		hover = -1
		for i in range(_rows()):
			if _row_rect(i).has_point(m):
				hover = i
				sel = i
		if _seal_rect(0).has_point(m) or _seal_rect(1).has_point(m):
			hover = 100
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var m2: Vector2 = e.position
		if _seal_rect(0).has_point(m2):
			Meta.selected_seal = maxi(1, Meta.selected_seal - 1)
			Meta.save_save()
			sfx.play("pickup", -10.0)
		elif _seal_rect(1).has_point(m2):
			Meta.selected_seal = mini(Meta.seals, Meta.selected_seal + 1)
			Meta.save_save()
			sfx.play("pickup", -10.0)
		else:
			for i in range(_rows()):
				if _row_rect(i).has_point(m2):
					sel = i
					_activate(i)

func _seal_rect(which: int) -> Rect2:
	return Rect2(PANEL_X + 22.0 + float(which) * 150.0, 86.0, 26.0, 26.0)

func _process(d: float) -> void:
	t += d
	flash = maxf(0.0, flash - d * 2.5)
	queue_redraw()
	if shot_camp:
		shot_frames += 1
		if shot_frames >= 6:
			var img: Image = get_viewport().get_texture().get_image()
			if img != null:
				img.save_png(shot_path)
			get_tree().quit()

func _draw() -> void:
	var font: Font = GameFont.get_font()
	draw_rect(Rect2(0, 0, 640, 360), Color(0.055, 0.06, 0.08))
	# 地面纹理感：几条横向暗带
	for i in range(6):
		draw_rect(Rect2(0, float(i) * 60.0, 640, 30.0), Color(1, 1, 1, 0.012))
	if flash > 0.0:
		draw_rect(Rect2(0, 0, 640, 360), Color(1.0, 0.85, 0.4, 0.10 * flash))

	draw_string(font, Vector2(28, 34), "营  地", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.94, 0.90, 0.78))
	draw_string(font, Vector2(120, 34), "旷野外 · 出发前整备", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.56, 0.52))
	var coin := "舍客勒  %d" % Meta.shillings
	draw_string(font, Vector2(400, 32), coin, HORIZONTAL_ALIGNMENT_RIGHT, 212, 14, Color(0.95, 0.80, 0.35))
	draw_line(Vector2(28, 44), Vector2(612, 44), Color(0.28, 0.28, 0.26), 1.0)

	# 强化行
	for i in range(Meta.UPGRADES.size()):
		var u: Dictionary = Meta.UPGRADES[i]
		var id: String = String(u["id"])
		var lv: int = Meta.level_of(id)
		var mx: int = int(u["max"])
		var r: Rect2 = _row_rect(i)
		var active: bool = i == sel
		var bg: Color = Color(0.12, 0.13, 0.16) if active else Color(0.085, 0.09, 0.11)
		draw_rect(r, bg)
		if active:
			draw_rect(Rect2(r.position.x, r.position.y, 3, r.size.y), Color(0.95, 0.80, 0.38))
		var name_c: Color = Color(0.96, 0.92, 0.80) if lv < mx else Color(0.62, 0.62, 0.58)
		draw_string(font, Vector2(r.position.x + 12, r.position.y + 13), String(u["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, name_c)
		draw_string(font, Vector2(r.position.x + 12, r.position.y + 25), String(u["desc"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.52, 0.54, 0.56))
		# 等级点
		for k in range(mx):
			var cx: float = r.position.x + 210.0 + float(k) * 12.0
			var cy: float = r.position.y + r.size.y * 0.5
			if k < lv:
				draw_circle(Vector2(cx, cy), 4.0, Color(0.95, 0.80, 0.38))
			else:
				draw_arc(Vector2(cx, cy), 3.6, 0.0, TAU, 12, Color(0.34, 0.35, 0.36), 1.0, true)
		var cost_txt: String
		var cost_c: Color
		if lv >= mx:
			cost_txt = "已满"
			cost_c = Color(0.55, 0.58, 0.52)
		else:
			var cost: int = Meta.upgrade_cost(id)
			cost_txt = "%d" % cost
			cost_c = Color(0.95, 0.80, 0.35) if Meta.shillings >= cost else Color(0.62, 0.34, 0.32)
		draw_string(font, Vector2(r.position.x + r.size.x - 92, r.position.y + 20), cost_txt, HORIZONTAL_ALIGNMENT_RIGHT, 82, 14, cost_c)

	# 试炼行：←→ 在已解锁地图之间切换
	var st: Dictionary = _stage_def()
	var sr: Rect2 = _row_rect(_stage_row())
	var son: bool = sel == _stage_row()
	draw_rect(sr, Color(0.13, 0.14, 0.18) if son else Color(0.09, 0.10, 0.13))
	if son:
		draw_rect(Rect2(sr.position.x, sr.position.y, 3, sr.size.y), Color(0.72, 0.78, 0.95))
	draw_string(font, Vector2(sr.position.x + 12, sr.position.y + 12), "试炼 · %s  %s" % [String(st.get("name", "—")), String(st.get("scripture", ""))], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.86, 0.90, 0.98))
	draw_string(font, Vector2(sr.position.x + 12, sr.position.y + 23), String(st.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, sr.size.x - 96, 8, Color(0.52, 0.55, 0.62))
	var locked_next: bool = false
	for i in range(GameData.stages.size()):
		if not _stage_unlocked(i):
			locked_next = true
			break
	draw_string(font, Vector2(sr.position.x + sr.size.x - 84, sr.position.y + 18), "← →  切换" if not locked_next else "← →  有未解锁", HORIZONTAL_ALIGNMENT_RIGHT, 76, 8, Color(0.60, 0.64, 0.70))

	# 进入行
	var rr: Rect2 = _row_rect(_stage_row() + 1)
	var on: bool = sel == _stage_row() + 1
	draw_rect(rr, Color(0.15, 0.21, 0.16) if on else Color(0.09, 0.12, 0.10))
	if on:
		draw_rect(Rect2(rr.position.x, rr.position.y, rr.size.x, rr.size.y), Color(0.55, 0.78, 0.52), false, 1.0)
	draw_string(font, Vector2(rr.position.x, rr.position.y + 18), "出发 →  %s" % String(st.get("name", "以拉谷")), HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 14, Color(0.86, 0.96, 0.82))

	# 右栏：七印
	draw_rect(Rect2(PANEL_X, ROW_Y0, PANEL_W, 150), Color(0.085, 0.09, 0.11))
	draw_rect(Rect2(PANEL_X, ROW_Y0, PANEL_W, 150), Color(0.26, 0.27, 0.28), false, 1.0)
	draw_string(font, Vector2(PANEL_X + 12, ROW_Y0 + 20), "七 印", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.86, 0.74))
	draw_string(font, Vector2(PANEL_X + 150, ROW_Y0 + 20), "← →  调整", HORIZONTAL_ALIGNMENT_RIGHT, 66, 9, Color(0.5, 0.52, 0.5))
	for i in range(7):
		var n: int = i + 1
		var cx: float = PANEL_X + 20.0 + float(i) * 27.0
		var cy: float = ROW_Y0 + 44.0
		var unlocked: bool = n <= Meta.seals
		var cur: bool = n == Meta.selected_seal
		var col: Color = Color(0.95, 0.80, 0.38) if cur else (Color(0.72, 0.72, 0.66) if unlocked else Color(0.26, 0.27, 0.28))
		draw_circle(Vector2(cx, cy), 10.0 if cur else 8.0, Color(col.r, col.g, col.b, 0.22 if unlocked else 0.10))
		draw_arc(Vector2(cx, cy), 10.0 if cur else 8.0, 0.0, TAU, 20, col, 1.4 if cur else 1.0, true)
		draw_string(font, Vector2(cx - 8, cy + 4), "%d" % n, HORIZONTAL_ALIGNMENT_CENTER, 16, 11, col)
	var mult: float = Meta.seal_mult()
	draw_string(font, Vector2(PANEL_X + 14, ROW_Y0 + 78), "敌人生命 +%d%%   伤害 +%d%%" % [int(Meta.SEAL_HP * 100.0 * float(Meta.selected_seal - 1)), int(Meta.SEAL_DMG * 100.0 * float(Meta.selected_seal - 1))], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.78, 0.60, 0.58))
	draw_string(font, Vector2(PANEL_X + 14, ROW_Y0 + 92), "刷怪量 +%d%%" % int(Meta.SEAL_RATE * 100.0 * float(Meta.selected_seal - 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.78, 0.60, 0.58))
	draw_string(font, Vector2(PANEL_X + 14, ROW_Y0 + 106), "舍客勒收益 ×%.2f" % mult, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.86, 0.66))
	draw_string(font, Vector2(PANEL_X + 14, ROW_Y0 + 128), "通关解锁下一印（七印 = 七层难度）", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.46, 0.47, 0.45))

	# 生涯
	draw_string(font, Vector2(PANEL_X + 2, ROW_Y0 + 176), "生涯", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.78, 0.70))
	var lines: Array = [
		"出发 %d 次 · 得胜 %d 次" % [Meta.runs, Meta.wins],
		"单局最佳击杀 %d" % Meta.best_kills,
		"最长存活 %s" % _mmss(Meta.best_time),
		"累计击杀 %d" % Meta.lifetime_kills
	]
	for i in range(lines.size()):
		draw_string(font, Vector2(PANEL_X + 2, ROW_Y0 + 194 + float(i) * 15.0), String(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.58, 0.60, 0.58))

	# 底部提示
	draw_string(font, Vector2(28, 344), "↑↓ 选择 · Enter 购买 / 出发 · ←→ 七印或试炼 · Esc 返回", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.44, 0.46, 0.44))

func _mmss(s: float) -> String:
	var n: int = int(s)
	return "%d:%02d" % [n / 60, n % 60]
