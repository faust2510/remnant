extends Control
## 标题 / 见证人选择（V3 美术轮）：石刻大字 + 暗金粒子；左栏为选中见证人的立绘预览，
## 右栏为生命 / 速度 / 起始武器强度三条对比条（UITheme.metal_bar）；底部是 20 人分页选人条。
## 已解锁可选，未解锁显示条件与灰态；选人后把 character_id 交给营地/单局。

const VIS_COUNT := 6
const SLOT_X0 := 29.0
const SLOT_W := 92.0
const SLOT_H := 42.0
const SLOT_STEP := 98.0
const SLOT_Y := 294.0
const LEFT_X := 24.0
const LEFT_W := 228.0
const RIGHT_X := 264.0
const RIGHT_W := 348.0
const PANEL_Y := 118.0
const PANEL_H := 170.0
const PORTRAIT_X := 34.0
const PORTRAIT_Y := 128.0
const PORTRAIT_SIZE := 96.0
const PARTICLE_COUNT := 46

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

var hp_vals: Array = []
var spd_vals: Array = []
var wpn_vals: Array = []
var hp_lo: float = 0.0
var hp_hi: float = 1.0
var hp_avg: float = 0.0
var spd_lo: float = 0.0
var spd_hi: float = 1.0
var spd_avg: float = 0.0
var wpn_hi: float = 1.0
var wpn_avg: float = 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	sfx = Sfx.new()
	add_child(sfx)
	for c in GameData.characters:
		ids.append(String(c.get("id", "")))
	_compute_stats()
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

# ---------------------------------------------------------------- 数据

func _char(i: int) -> Dictionary:
	if i < 0 or i >= GameData.characters.size():
		return {}
	return GameData.characters[i]

func _selectable(i: int) -> bool:
	if i < 0 or i >= ids.size():
		return false
	return UIText.character_unlocked(_char(i))

func _compute_stats() -> void:
	hp_vals.clear()
	spd_vals.clear()
	wpn_vals.clear()
	for i in range(ids.size()):
		var c: Dictionary = _char(i)
		hp_vals.append(float(c.get("hp", 0)))
		spd_vals.append(float(c.get("speed", 0)))
		wpn_vals.append(float(_weapon_info(String(c.get("weapon", ""))).get("score", 0.0)))
	var hr: Dictionary = _range(hp_vals)
	var sr: Dictionary = _range(spd_vals)
	var wr: Dictionary = _range(wpn_vals)
	hp_lo = float(hr["lo"])
	hp_hi = float(hr["hi"])
	hp_avg = float(hr["avg"])
	spd_lo = float(sr["lo"])
	spd_hi = float(sr["hi"])
	spd_avg = float(sr["avg"])
	wpn_hi = maxf(float(wr["hi"]), 0.001)
	wpn_avg = float(wr["avg"])

func _range(vals: Array) -> Dictionary:
	if vals.is_empty():
		return {"lo": 0.0, "hi": 1.0, "avg": 0.0}
	var lo: float = float(vals[0])
	var hi: float = lo
	var sum: float = 0.0
	for v in vals:
		var f: float = float(v)
		lo = minf(lo, f)
		hi = maxf(hi, f)
		sum += f
	return {"lo": lo, "hi": hi, "avg": sum / float(vals.size())}

func _weapon_info(wid: String) -> Dictionary:
	var w: Dictionary = GameData.weapons.get(wid, {})
	if w.is_empty():
		return {"name": wid, "kind": "—", "score": 0.0}
	var p: Dictionary = w.get("params", {})
	var dmg: float = float(p.get("damage", 1.0))
	var cnt: float = float(p.get("count", 1.0))
	var behavior: String = String(w.get("behavior", ""))
	var score: float = 0.0
	if behavior == "orbit":
		score = dmg * cnt * 0.6
	else:
		score = dmg * cnt / maxf(float(p.get("cooldown", 1.0)), 0.2)
	return {"name": String(w.get("name", wid)), "kind": _kind_cn(behavior), "score": score}

func _kind_cn(behavior: String) -> String:
	match behavior:
		"line_projectile":
			return "远程"
		"arc_melee":
			return "近战"
		"orbit":
			return "环绕"
		"zone":
			return "领域"
		"homing":
			return "追踪"
	return "—"

func _hp_ratio(v: float) -> float:
	return _low_high(v, hp_lo, hp_hi)

func _spd_ratio(v: float) -> float:
	return _low_high(v, spd_lo, spd_hi)

func _wpn_ratio(v: float) -> float:
	return clampf(sqrt(maxf(v, 0.0) / wpn_hi), 0.0, 1.0)

func _low_high(v: float, lo: float, hi: float) -> float:
	if hi - lo < 0.0001:
		return 0.55
	return 0.18 + 0.82 * clampf((v - lo) / (hi - lo), 0.0, 1.0)

func _delta_text(v: float, avg: float, decimals: int) -> String:
	var d: float = v - avg
	if decimals <= 0:
		var n: int = int(round(d))
		if n == 0:
			return "±0"
		return ("+%d" % n) if n > 0 else ("%d" % n)
	if absf(d) < 0.05:
		return "±0"
	return ("+%.1f" % d) if d > 0.0 else ("%.1f" % d)

# ---------------------------------------------------------------- 操作

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

# ---------------------------------------------------------------- 布局

func _slot_rect(k: int) -> Rect2:
	return Rect2(SLOT_X0 + float(k) * SLOT_STEP, SLOT_Y, SLOT_W, SLOT_H)

func _slot_at(m: Vector2) -> int:
	for k in range(VIS_COUNT):
		var i: int = window_start + k
		if i >= ids.size():
			break
		if _slot_rect(k).has_point(m):
			return i
	return -1

# ---------------------------------------------------------------- 输入

func _process(d: float) -> void:
	t += d
	notice_t = maxf(0.0, notice_t - d)
	hover = _slot_at(get_local_mouse_position())
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
			var hit: int = _slot_at(e.position)
			if hit >= 0:
				if hit == sel:
					_try_select(hit)
				else:
					sel = hit
					_ensure_visible()
					sfx.play("pickup", -14.0, 1.1)
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

# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	_draw_background()
	_draw_header()
	if not ids.is_empty():
		_draw_left_panel(clampi(sel, 0, ids.size() - 1))
		_draw_right_panel(clampi(sel, 0, ids.size() - 1))
	_draw_strip()
	if notice_t > 0.0:
		UITheme.text(self, Vector2(24, 347), notice, 10, Color(0.95, 0.74, 0.52, clampf(notice_t, 0.0, 1.0)), 1, 592.0)
	UITheme.text(self, Vector2(0, 357), "← → ↑ ↓ 选择 · Enter 整备出发 · 点击预览 / 再点出发 · V 图鉴 · Esc 退出", 10, Color(0.50, 0.49, 0.44), 1, 640.0)

func _draw_background() -> void:
	draw_rect(Rect2(0, 0, 640, 360), UITheme.INK_DEEP, true)
	for row in range(4):
		var y: float = float(row) * 90.0
		var lift: float = 0.008 if row % 2 == 0 else 0.0
		draw_rect(Rect2(0, y, 640, 90), Color(0.055 + lift, 0.070 + lift, 0.105 + lift, 1.0), true)
		draw_rect(Rect2(0, y, 640, 1), Color(0, 0, 0, 0.35), true)
		for k in range(3):
			var jx: float = fposmod(_hash01(row * 31 + k) * 640.0 + float(k) * 212.0, 640.0)
			draw_rect(Rect2(jx, y, 1, 90), Color(0, 0, 0, 0.22), true)
	for i in range(7):
		var a: float = 0.018 * float(7 - i)
		draw_rect(Rect2(0, 0, 640, 118.0 - float(i) * 14.0), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, a), true)
	for i in range(90):
		var px: float = _hash01(i * 3 + 1) * 640.0
		var py: float = _hash01(i * 7 + 2) * 360.0
		draw_rect(Rect2(px, py, 1, 1), Color(0.78, 0.72, 0.56, 0.04 + 0.05 * _hash01(i * 11 + 5)), true)
	_draw_particles()
	for i in range(7):
		draw_rect(Rect2(float(i) * 3.0, float(i) * 2.0, 640.0 - float(i) * 6.0, 360.0 - float(i) * 4.0), Color(0, 0, 0, 0.03), false, 2.0)

func _draw_particles() -> void:
	var gold := UITheme.GOLD_PALE
	for i in range(PARTICLE_COUNT):
		var sx: float = _hash01(i * 3 + 1)
		var sy: float = _hash01(i * 5 + 7)
		var spd: float = 5.0 + _hash01(i * 7 + 3) * 14.0
		var sway: float = 6.0 + _hash01(i * 11 + 4) * 12.0
		var x: float = sx * 640.0 + sin(t * 0.30 + float(i) * 1.71) * sway
		var y: float = fposmod(sy * 380.0 - t * spd, 380.0) - 10.0
		var tw: float = 0.35 + 0.35 * sin(t * 0.9 + float(i) * 2.3)
		var r: float = 0.8 + _hash01(i * 13 + 6) * 1.4
		draw_circle(Vector2(x, y), r, Color(gold.r, gold.g, gold.b, 0.10 + 0.18 * tw))
		if r > 1.5:
			draw_circle(Vector2(x, y), r * 2.4, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.05))
		elif _hash01(i * 17 + 9) > 0.86:
			draw_line(Vector2(x, y), Vector2(x, y - 3.0), Color(gold.r, gold.g, gold.b, 0.10), 1.0)

func _draw_header() -> void:
	draw_circle(Vector2(320, 36), 152.0, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.045))
	draw_circle(Vector2(320, 36), 96.0, Color(UITheme.GOLD_BRIGHT.r, UITheme.GOLD_BRIGHT.g, UITheme.GOLD_BRIGHT.b, 0.05))
	UITheme.etched_title(self, Vector2(0, 58), "余  民", 40)
	draw_string(GameFont.get_font(), Vector2(0, 57), "余  民", HORIZONTAL_ALIGNMENT_CENTER, 640, 40, Color(1.0, 0.94, 0.76, 0.22))
	UITheme.text(self, Vector2(0, 77), "T H E   R E M N A N T", 11, UITheme.PARCH_DIM, 1, 640.0)
	UITheme.text(self, Vector2(0, 93), "「我们既有这许多的见证人，如同云彩围着我们」  来 12:1", 10, Color(0.62, 0.58, 0.48), 1, 640.0)
	UITheme.divider(self, 24.0, 616.0, 101.0, 0.9)
	var unlocked: int = 0
	for i in range(ids.size()):
		if _selectable(i):
			unlocked += 1
	var pages: int = maxi(1, ceili(float(maxi(ids.size(), 1)) / float(VIS_COUNT)))
	UITheme.text(self, Vector2(24, 113), "见证人 · 已解锁 %d / %d" % [unlocked, ids.size()], 10, Color(0.62, 0.59, 0.48), 0, -1.0)
	UITheme.text(self, Vector2(500, 113), "第 %d / %d 页" % [window_start / VIS_COUNT + 1, pages], 10, Color(0.62, 0.59, 0.48), 2, 116.0)

func _draw_left_panel(i: int) -> void:
	var c: Dictionary = _char(i)
	if c.is_empty():
		return
	var f: Font = GameFont.get_font()
	UITheme.panel(self, Rect2(LEFT_X, PANEL_Y, LEFT_W, PANEL_H), 1.0, true)
	var pr := Rect2(PORTRAIT_X, PORTRAIT_Y, PORTRAIT_SIZE, PORTRAIT_SIZE)
	draw_rect(pr.grow(5.0), Color(0.03, 0.04, 0.06, 1.0), true)
	draw_rect(pr.grow(4.0), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.85), false, 1.0)
	draw_rect(pr, Color(0.02, 0.03, 0.05, 1.0), true)
	_draw_portrait(pr, String(c.get("id", "")))
	var tx: float = PORTRAIT_X + PORTRAIT_SIZE + 10.0
	var tw: float = LEFT_X + LEFT_W - tx - 12.0
	var ok: bool = _selectable(i)
	var w: Dictionary = _weapon_info(String(c.get("weapon", "")))
	UITheme.text(self, Vector2(tx, 147), UIText.clip(String(c.get("name", "?")), 6), 15, UITheme.PARCH if ok else Color(0.56, 0.54, 0.50), 0, tw)
	UITheme.text(self, Vector2(tx, 163), String(c.get("scripture", "")), 10, Color(0.63, 0.58, 0.44), 0, tw)
	UITheme.text(self, Vector2(tx, 178), "起始 · " + UIText.clip(String(w["name"]), 6), 10, Color(0.74, 0.76, 0.64) if ok else Color(0.48, 0.49, 0.46), 0, tw)
	UITheme.text(self, Vector2(tx, 192), "强度 %.1f · %s" % [float(w["score"]), String(w["kind"])], 10, Color(0.70, 0.66, 0.52) if ok else Color(0.46, 0.46, 0.43), 0, tw)
	draw_multiline_string(f, Vector2(LEFT_X + 10.0, 240.0), String(c.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, LEFT_W - 20.0, 10, 3, Color(0.77, 0.74, 0.65) if ok else Color(0.55, 0.54, 0.51))
	if ok:
		UITheme.text(self, Vector2(LEFT_X + 10.0, 280.0), "已解锁 · Enter 出发", 10, Color(0.60, 0.84, 0.58), 0, LEFT_W - 20.0)
	else:
		var cond: String = UIText.character_unlock_text(c)
		UITheme.text(self, Vector2(LEFT_X + 10.0, 280.0), "未解锁 · " + UIText.clip(cond, 19), 10, Color(0.86, 0.55, 0.44), 0, LEFT_W - 20.0)

func _draw_right_panel(i: int) -> void:
	var c: Dictionary = _char(i)
	if c.is_empty():
		return
	var f: Font = GameFont.get_font()
	draw_line(Vector2(258, 130), Vector2(258, 276), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.22), 1.0)
	UITheme.panel(self, Rect2(RIGHT_X, PANEL_Y, RIGHT_W, PANEL_H), 1.0, true)
	UITheme.text(self, Vector2(RIGHT_X + 14.0, 138), "天 资 对 照", 12, UITheme.GOLD_PALE, 0, -1.0)
	UITheme.text(self, Vector2(RIGHT_X + 160.0, 138), "金色竖线 = 20 人均值", 10, Color(0.52, 0.50, 0.42), 2, RIGHT_W - 174.0)
	var hp: float = float(c.get("hp", 0))
	var spd: float = float(c.get("speed", 0))
	var w: Dictionary = _weapon_info(String(c.get("weapon", "")))
	var wpn: float = float(w["score"])
	_stat_row(150, "生命", _hp_ratio(hp), _low_high(hp_avg, hp_lo, hp_hi), "%d  %s" % [int(hp), _delta_text(hp, hp_avg, 0)], UITheme.BLOOD)
	_stat_row(176, "速度", _spd_ratio(spd), _low_high(spd_avg, spd_lo, spd_hi), "%d  %s" % [int(spd), _delta_text(spd, spd_avg, 0)], UITheme.OLIVE)
	_stat_row(202, "武器", _wpn_ratio(wpn), _wpn_ratio(wpn_avg), "%.1f  %s" % [wpn, _delta_text(wpn, wpn_avg, 1)], UITheme.GOLD)
	UITheme.divider(self, RIGHT_X + 14.0, RIGHT_X + RIGHT_W - 14.0, 218.0, 0.6)
	UITheme.text(self, Vector2(RIGHT_X + 14.0, 234), "起始武器 · %s · %s" % [String(w["name"]), String(w["kind"])], 10, Color(0.74, 0.76, 0.64), 0, RIGHT_W - 28.0)
	var perk: String = UIText.perk_text(c.get("perk", {}), 2)
	if perk != "":
		draw_multiline_string(f, Vector2(RIGHT_X + 14.0, 250.0), perk, HORIZONTAL_ALIGNMENT_LEFT, RIGHT_W - 28.0, 10, 2, Color(0.77, 0.75, 0.65))
	var cid: String = String(c.get("id", ""))
	if Meta.is_awakened(cid):
		var aw: Dictionary = c.get("awakening", {})
		UITheme.text(self, Vector2(RIGHT_X + 14.0, 280), "★ 已觉醒 · " + UIText.clip(String(aw.get("name", "")), 10), 10, UITheme.GOLD_BRIGHT, 0, RIGHT_W - 28.0)
	else:
		UITheme.text(self, Vector2(RIGHT_X + 14.0, 280), "未觉醒 · 以三印通关点亮", 10, Color(0.50, 0.50, 0.46), 0, RIGHT_W - 28.0)

func _stat_row(y: float, label: String, ratio: float, avg_ratio: float, value: String, col: Color) -> void:
	UITheme.text(self, Vector2(RIGHT_X + 14.0, y + 9.0), label, 10, Color(0.74, 0.71, 0.61), 0, 46.0)
	var bar := Rect2(RIGHT_X + 62.0, y, 192.0, 9.0)
	UITheme.metal_bar(self, bar, ratio, col, 0.7)
	var mx: float = bar.position.x + bar.size.x * clampf(avg_ratio, 0.0, 1.0)
	draw_line(Vector2(mx, bar.position.y - 2.0), Vector2(mx, bar.position.y + bar.size.y + 2.0), Color(0.95, 0.92, 0.80, 0.8), 1.0)
	UITheme.text(self, Vector2(RIGHT_X + RIGHT_W - 90.0, y + 9.0), value, 10, Color(0.88, 0.86, 0.76), 2, 76.0)

func _draw_portrait(r: Rect2, cid: String) -> void:
	var tex: Texture2D = SpriteBank.witnesses()
	var row: int = SpriteBank.witness_row(cid)
	if tex != null and row >= 0:
		draw_texture_rect_region(tex, r, SpriteBank.frame_rect(row, 0))
	else:
		_draw_fallback_portrait(r, cid)
	draw_rect(r, Color(0, 0, 0, 0.16), false, 1.0)

func _draw_fallback_portrait(r: Rect2, cid: String) -> void:
	var seed: int = _id_seed(cid)
	var w: float = r.size.x
	var h: float = r.size.y
	draw_rect(r, Color(0.045, 0.055, 0.08, 1.0), true)
	for i in range(6):
		var k: float = float(i) / 6.0
		draw_rect(Rect2(r.position.x, r.position.y + h * k, w, h / 6.0 + 1.0), Color(0.055 + 0.014 * (1.0 - k), 0.065 + 0.014 * (1.0 - k), 0.095 + 0.016 * (1.0 - k), 1.0), true)
	draw_circle(r.position + Vector2(w * 0.5, h * 0.40), w * 0.36, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.06))
	draw_rect(Rect2(r.position.x + 8.0, r.position.y + h - 13.0, w - 16.0, 2.0), Color(0.34, 0.29, 0.19, 0.85), true)
	var cx: float = r.position.x + w * 0.5
	var head_y: float = r.position.y + h * 0.31
	var head_r: float = w * 0.098
	var hem: float = r.position.y + h - 13.0
	var mantle := PackedVector2Array([
		Vector2(cx - w * 0.09, head_y + head_r + 1.0),
		Vector2(cx + w * 0.09, head_y + head_r + 1.0),
		Vector2(cx + w * 0.27, hem),
		Vector2(cx - w * 0.27, hem)
	])
	draw_colored_polygon(mantle, Color(0.30, 0.26, 0.20, 1.0))
	var robe := PackedVector2Array([
		Vector2(cx - w * 0.06, head_y + head_r + 5.0),
		Vector2(cx + w * 0.06, head_y + head_r + 5.0),
		Vector2(cx + w * 0.17, hem - 2.0),
		Vector2(cx - w * 0.17, hem - 2.0)
	])
	draw_colored_polygon(robe, Color(0.40, 0.35, 0.26, 1.0))
	draw_line(Vector2(cx - w * 0.27, hem), Vector2(cx - w * 0.09, head_y + head_r + 1.0), Color(0.52, 0.45, 0.31, 0.9), 1.0)
	draw_circle(Vector2(cx, head_y), head_r, Color(0.54, 0.44, 0.33, 1.0))
	draw_circle(Vector2(cx, head_y - head_r * 0.35), head_r * 0.9, Color(0.34, 0.27, 0.21, 1.0))
	draw_line(Vector2(cx, head_y + head_r * 0.55), Vector2(cx, hem - 4.0), Color(0.24, 0.20, 0.15, 0.8), 1.0)
	var variant: int = seed % 3
	if variant == 0:
		var sx: float = cx + w * 0.24
		draw_line(Vector2(sx, head_y - h * 0.06), Vector2(sx, hem), Color(0.58, 0.47, 0.28, 1.0), 2.0)
		draw_arc(Vector2(sx - 4.0, head_y - h * 0.08), 6.0, -PI * 0.55, PI * 0.55, 10, Color(0.58, 0.47, 0.28, 1.0), 2.0, true)
	elif variant == 1:
		draw_rect(Rect2(cx - w * 0.16, head_y + h * 0.30, w * 0.32, h * 0.07), Color(0.72, 0.66, 0.50, 1.0), true)
		draw_rect(Rect2(cx - w * 0.16, head_y + h * 0.30, w * 0.32, 2), Color(0.50, 0.42, 0.28, 1.0), true)
	else:
		draw_arc(Vector2(cx, head_y + h * 0.42), w * 0.16, -PI * 0.95, PI * 0.15, 12, Color(0.66, 0.55, 0.32, 1.0), 2.0, true)
		draw_line(Vector2(cx + w * 0.12, head_y + h * 0.36), Vector2(cx + w * 0.20, head_y + h * 0.20), Color(0.66, 0.55, 0.32, 1.0), 2.0)

func _draw_strip() -> void:
	for k in range(VIS_COUNT):
		var r: Rect2 = _slot_rect(k)
		var i: int = window_start + k
		if i >= ids.size():
			draw_rect(r, Color(0.045, 0.055, 0.08, 0.6), true)
			draw_rect(r, Color(0.25, 0.24, 0.20, 0.35), false, 1.0)
			continue
		_draw_slot(r, i)

func _draw_slot(r: Rect2, i: int) -> void:
	var c: Dictionary = _char(i)
	var ok: bool = _selectable(i)
	var on: bool = i == sel
	var hv: bool = i == hover
	var bg := Color(0.075, 0.085, 0.11, 0.95)
	if hv:
		bg = bg.lightened(0.07)
	if on:
		bg = bg.lerp(UITheme.INK_SOFT, 0.55)
	draw_rect(r, bg, true)
	var border := Color(0.28, 0.28, 0.26)
	if on:
		border = UITheme.GOLD_BRIGHT
	elif hv:
		border = UITheme.GOLD
	draw_rect(r, border, false, 2.0 if on else 1.0)
	if on:
		draw_rect(Rect2(r.position.x, r.position.y - 3.0, r.size.x, 2.0), UITheme.GOLD_BRIGHT, true)
	var name_c := UITheme.PARCH if ok else Color(0.53, 0.52, 0.49)
	UITheme.text(self, Vector2(r.position.x, r.position.y + 17.0), UIText.clip(String(c.get("name", "?")), 6), 11, name_c, 1, r.size.x)
	var w: Dictionary = _weapon_info(String(c.get("weapon", "")))
	UITheme.text(self, Vector2(r.position.x, r.position.y + 32.0), UIText.clip(String(w["name"]), 8), 10, Color(0.63, 0.64, 0.55) if ok else Color(0.43, 0.43, 0.41), 1, r.size.x)
	if not ok:
		UITheme.text(self, Vector2(r.position.x + r.size.x - 20.0, r.position.y + 13.0), "锁", 10, Color(0.72, 0.46, 0.38), 0, -1.0)
	if Meta.is_awakened(String(c.get("id", ""))):
		UITheme.star(self, Vector2(r.position.x + r.size.x - 10.0, r.position.y + 9.0), 4.2, UITheme.GOLD_BRIGHT)

func _hash01(n: int) -> float:
	var v: float = sin(float(n) * 12.9898 + 78.233) * 43758.5453
	return v - floor(v)

func _id_seed(id: String) -> int:
	var s: int = 7
	for i in range(id.length()):
		s = (s * 131 + id.unicode_at(i)) % 1000003
	return s
