extends Control
## 营地：两页签（强化 / 会幕）+ 常驻试炼行与出发行。
## 试炼覆盖 stages.json 全部 24 章（按 Meta.wins 与 unlock_wins 解锁），
## ←→ 在 24 章间移动，Enter 出发；Tab 切页；V 打开图鉴；右栏固定灾变阶面板。

const ROW_X := 28.0
const ROW_W := 344.0
const ROW_H := 25.0
const ROW_STEP := 27.0
const ROW_Y0 := 80.0
const STAGE_Y := 244.0
const STAGE_H := 30.0
const ENTER_Y := 278.0
const ENTER_H := 26.0
const PANEL_X := 384.0
const PANEL_W := 228.0
const TIER_Y := 54.0
const TIER_H := 100.0
const DETAIL_Y := 160.0
const DETAIL_H := 140.0
const PAGE_NAMES := ["强化", "会幕", "图鉴"]
const STAGE_ROW := 6
const ENTER_ROW := 7

var sel: int = 0
var page: int = 0
var hover: int = -1
var tab_hover: int = -1
var stage_cursor: int = 0
var t: float = 0.0
var sfx: Sfx
var flash: float = 0.0
var notice: String = ""
var notice_t: float = 0.0
var shot_camp: bool = false
var shot_path: String = "/tmp/camp.png"
var shot_frames: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	sfx = Sfx.new()
	add_child(sfx)
	stage_cursor = _stage_index()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a == "--shot-camp":
			shot_camp = true
		elif a.begins_with("--shot-path="):
			shot_path = a.substr(12)
		elif a.begins_with("--camp-page="):
			page = clampi(int(a.substr(12)), 0, 1)
		elif a.begins_with("--camp-stage="):
			stage_cursor = clampi(int(a.substr(13)), 0, maxi(GameData.stages.size() - 1, 0))
	for a in args:
		if a == "--camp-selftest":
			_selftest()
			return
	if shot_camp:
		return
	for a in args:
		if a == "--sim" or a == "--sim-god" or a == "--shot" or a == "--shot-modal" or a.begins_with("--char=") or a.begins_with("--sim-speed=") or a.begins_with("--shot-"):
			_enter()
			return

# ---------------------------------------------------------------- 数据与状态

func _rows() -> int:
	return 8

func _page_rows() -> int:
	return 6

func _upgrade_at(i: int) -> Dictionary:
	if i < 0 or i >= Meta.UPGRADES.size():
		return {}
	if page != 0:
		return {}
	return Meta.UPGRADES[i]

func _buildings() -> Array:
	return GameData.store_buildings()

func _building_at(i: int) -> Dictionary:
	var bs: Array = _buildings()
	if i < 0 or i >= bs.size() or page != 1:
		return {}
	return bs[i]

func _stage_index() -> int:
	for i in range(GameData.stages.size()):
		if String(GameData.stages[i].get("id", "")) == Meta.stage_id:
			return i
	return 0

func _stage_def_at(i: int) -> Dictionary:
	if i < 0 or i >= GameData.stages.size():
		return {}
	return GameData.stages[i]

func _stage_unlocked(i: int) -> bool:
	var s: Dictionary = _stage_def_at(i)
	if s.is_empty():
		return false
	return Meta.wins >= int(s.get("unlock_wins", 0))

func _count_unlocked() -> int:
	var n: int = 0
	for i in range(GameData.stages.size()):
		if _stage_unlocked(i):
			n += 1
	return n

func _first_int(s: String) -> int:
	var num: String = ""
	for i in range(s.length()):
		var ch: String = s[i]
		if ch >= "0" and ch <= "9":
			num += ch
		elif num != "":
			break
	return int(num) if num != "" else 0

func _live_upgrades(b: Dictionary) -> Array:
	var out: Array = []
	for uid in b.get("upgrades", []):
		for u in GameData.store_upgrades():
			if String(u.get("id", "")) == String(uid) and bool(u.get("live", false)):
				out.append(u)
	return out

func _all_upgrades(b: Dictionary) -> Array:
	var out: Array = []
	for uid in b.get("upgrades", []):
		for u in GameData.store_upgrades():
			if String(u.get("id", "")) == String(uid):
				out.append(u)
	return out

func _building_unlock_ok(b: Dictionary) -> bool:
	var txt: String = String(b.get("unlocks", ""))
	if txt == "" or txt.contains("初始"):
		return true
	var n: int = maxi(_first_int(txt), 1)
	if txt.contains("印"):
		return maxi(Meta.seals, Meta.effective_tier()) >= n
	if txt.contains("局"):
		return Meta.runs >= n
	return true

func _building_status(b: Dictionary) -> Dictionary:
	var bid: String = String(b.get("id", ""))
	var st := {
		"ok": true,
		"reason": "",
		"pending": false,
		"maxed": false,
		"cost": 0,
		"level": Meta.building_level(bid),
		"unlock_ok": _building_unlock_ok(b)
	}
	if _live_upgrades(b).is_empty():
		st["pending"] = true
		st["ok"] = false
		st["reason"] = "待实装"
		return st
	if not bool(st["unlock_ok"]):
		st["ok"] = false
		st["reason"] = "未开放 · " + String(b.get("unlocks", ""))
		return st
	if Meta.building_next(bid) == "":
		st["maxed"] = true
		st["ok"] = false
		st["reason"] = "已满"
		return st
	st["cost"] = Meta.building_cost(bid)
	return st

func _stage_reward_text(sid: String) -> String:
	var a: Dictionary = UIText.stage_achievement(sid)
	if a.is_empty():
		return "首通奖励未配置"
	var prefix: String = "已领取 · " if Meta.has_achievement(String(a.get("id", ""))) else "首通 · "
	return prefix + UIText.achievement_reward_text(a)

func _notify(text: String) -> void:
	notice = text
	notice_t = 2.8

func _witness_name() -> String:
	var cid: String = RunCfg.character_id if RunCfg.character_id != "" else "david"
	var c: Dictionary = GameData.characters_by_id.get(cid, {})
	return String(c.get("name", cid))

# ---------------------------------------------------------------- 操作

func _enter() -> void:
	var i: int = stage_cursor
	if not _stage_unlocked(i):
		var s: Dictionary = _stage_def_at(i)
		_notify("「%s」尚未解锁：需得胜 %d 次（当前 %d）" % [String(s.get("name", "?")), int(s.get("unlock_wins", 0)), Meta.wins])
		sfx.play("hit", -12.0, 0.8)
		return
	var sdef: Dictionary = _stage_def_at(i)
	var sid: String = String(sdef.get("id", Meta.stage_id))
	Meta.stage_id = sid
	Meta.save_save()
	RunCfg.stage_id = sid
	var cid: String = RunCfg.character_id if RunCfg.character_id != "" else "david"
	var c: Dictionary = GameData.characters_by_id.get(cid, {})
	if c.is_empty() or not UIText.character_unlocked(c):
		cid = "david"
	RunCfg.character_id = cid
	sfx.play("dash", -6.0)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")

func _cycle_stage(dir: int) -> void:
	var n: int = GameData.stages.size()
	if n <= 0:
		return
	stage_cursor = (stage_cursor + dir + n) % n
	var s: Dictionary = _stage_def_at(stage_cursor)
	if _stage_unlocked(stage_cursor):
		Meta.stage_id = String(s.get("id", Meta.stage_id))
		Meta.save_save()
		sfx.play("pickup", -10.0, 1.05)
		_notify("试炼 · 第 %d 章 %s" % [int(s.get("chapter", 0)), String(s.get("name", ""))])
	else:
		sfx.play("hit", -14.0, 0.7)
		_notify("「%s」未解锁：需得胜 %d 次（当前 %d）" % [String(s.get("name", "?")), int(s.get("unlock_wins", 0)), Meta.wins])

func _adjust_tier(dir: int) -> void:
	var hi: int = Meta.max_tier_allowed()
	var cur: int = Meta.effective_tier()
	var nxt: int = clampi(cur + dir, 1, hi)
	if nxt == cur:
		sfx.play("hit", -14.0, 0.8)
		if dir > 0 and hi < 21:
			_notify("第 %d 阶以上需圣物「七印书卷」（通关第 7 印解锁）" % (hi + 1))
		elif dir > 0:
			_notify("已是当前最高灾变阶")
		return
	Meta.set_tier(nxt)
	Meta.save_save()
	sfx.play("pickup", -10.0, 1.1)
	_notify("灾变阶 · %s" % Meta.tier_name())

func _buy_upgrade() -> void:
	var u: Dictionary = _upgrade_at(sel)
	if u.is_empty():
		return
	var id: String = String(u.get("id", ""))
	var lv: int = Meta.level_of(id)
	var mx: int = int(u.get("max", 5))
	if lv >= mx:
		sfx.play("hit", -12.0)
		_notify("「%s」已满级" % String(u.get("name", "")))
		return
	var cost: int = Meta.upgrade_cost(id)
	if Meta.buy(id):
		sfx.play("level", -4.0)
		flash = 1.0
		_notify("%s 升级 Lv%d（-%d 舍客勒）" % [String(u.get("name", "")), Meta.level_of(id), cost])
	else:
		sfx.play("hit", -14.0, 0.7)
		_notify("舍客勒不足：还需 %d" % maxi(cost - Meta.shillings, 0))

func _buy_building() -> void:
	var b: Dictionary = _building_at(sel)
	if b.is_empty():
		return
	var bid: String = String(b.get("id", ""))
	var st: Dictionary = _building_status(b)
	if bool(st["pending"]):
		sfx.play("hit", -12.0)
		_notify("「%s」的强化尚未实装，暂不可购买" % String(b.get("name", "")))
		return
	if not bool(st["ok"]):
		sfx.play("hit", -12.0)
		_notify(String(st["reason"]))
		return
	var nid: String = Meta.building_next(bid)
	var cost: int = Meta.building_cost(bid)
	if Meta.buy_building(bid):
		sfx.play("level", -4.0)
		flash = 1.0
		var uname: String = nid
		for u in GameData.store_upgrades():
			if String(u.get("id", "")) == nid:
				uname = String(u.get("name", nid))
		_notify("%s 升级 · %s（-%d）" % [String(b.get("name", "")), uname, cost])
	else:
		sfx.play("hit", -14.0, 0.7)
		_notify("舍客勒不足：还需 %d" % maxi(cost - Meta.shillings, 0))

func _activate(i: int) -> void:
	if i == STAGE_ROW:
		# 试炼行 Enter 直接出发；锁定章节由 _enter 提示并拦下
		_enter()
		return
	if i == ENTER_ROW:
		_enter()
		return
	if page == 1:
		_buy_building()
	else:
		_buy_upgrade()

func _switch_page(dir: int) -> void:
	page = (page + dir + 2) % 2
	sfx.play("pickup", -12.0, 1.15)

func _open_codex() -> void:
	CodexScreen.back_scene = "res://scenes/camp.tscn"
	sfx.play("pickup", -10.0)
	get_tree().change_scene_to_file.call_deferred("res://scenes/codex.tscn")

# ---------------------------------------------------------------- 布局

func _row_rect(i: int) -> Rect2:
	return Rect2(ROW_X, ROW_Y0 + float(i) * ROW_STEP, ROW_W, ROW_H)

func _stage_rect() -> Rect2:
	return Rect2(ROW_X, STAGE_Y, ROW_W, STAGE_H)

func _enter_rect() -> Rect2:
	return Rect2(ROW_X, ENTER_Y, ROW_W, ENTER_H)

func _tab_rect(i: int) -> Rect2:
	return Rect2(28.0 + float(i) * 92.0, 52.0, 88.0, 22.0)

func _stage_arrow_rect(which: int) -> Rect2:
	var r: Rect2 = _stage_rect()
	return Rect2(r.position.x + r.size.x - (60.0 if which == 0 else 32.0), r.position.y + 4.0, 24.0, 22.0)

# ---------------------------------------------------------------- 输入

func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = e.keycode
	match k:
		KEY_UP, KEY_W:
			sel = (sel - 1 + _rows()) % _rows()
		KEY_DOWN, KEY_S:
			sel = (sel + 1) % _rows()
		KEY_LEFT, KEY_A:
			if sel == STAGE_ROW:
				_cycle_stage(-1)
			else:
				_adjust_tier(-1)
		KEY_RIGHT, KEY_D:
			if sel == STAGE_ROW:
				_cycle_stage(1)
			else:
				_adjust_tier(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate(sel)
		KEY_TAB:
			_switch_page(-1 if e.shift_pressed else 1)
		KEY_1:
			page = 0
		KEY_2:
			page = 1
		KEY_3, KEY_V:
			_open_codex()
		KEY_ESCAPE:
			get_tree().change_scene_to_file.call_deferred("res://scenes/title.tscn")

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var m: Vector2 = e.position
		hover = -1
		tab_hover = -1
		for i in range(3):
			if _tab_rect(i).has_point(m):
				tab_hover = i
		for i in range(_rows()):
			var rr: Rect2 = _stage_rect() if i == STAGE_ROW else (_enter_rect() if i == ENTER_ROW else _row_rect(i))
			if rr.has_point(m):
				hover = i
				sel = i
	elif e is InputEventMouseButton and e.pressed:
		var m2: Vector2 = e.position
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and _stage_rect().has_point(m2):
			_cycle_stage(-1)
			return
		if e.button_index == MOUSE_BUTTON_WHEEL_DOWN and _stage_rect().has_point(m2):
			_cycle_stage(1)
			return
		if e.button_index != MOUSE_BUTTON_LEFT:
			return
		for i in range(3):
			if _tab_rect(i).has_point(m2):
				if i == 2:
					_open_codex()
				else:
					page = i
					sfx.play("pickup", -12.0)
				return
		if _stage_rect().has_point(m2):
			if _stage_arrow_rect(0).has_point(m2):
				_cycle_stage(-1)
			elif _stage_arrow_rect(1).has_point(m2):
				_cycle_stage(1)
			else:
				sel = STAGE_ROW
			return
		for i in range(_rows()):
			var rr: Rect2 = _enter_rect() if i == ENTER_ROW else (_row_rect(i) if i != STAGE_ROW else _stage_rect())
			if rr.has_point(m2):
				sel = i
				_activate(i)
				return

func _process(d: float) -> void:
	t += d
	flash = maxf(0.0, flash - d * 2.5)
	notice_t = maxf(0.0, notice_t - d)
	queue_redraw()
	if shot_camp:
		shot_frames += 1
		if shot_frames >= 6:
			var img: Image = get_viewport().get_texture().get_image()
			if img != null:
				img.save_png(shot_path)
			print("[shot] camp saved ", shot_path)
			get_tree().quit()

# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var font: Font = GameFont.get_font()
	draw_rect(Rect2(0, 0, 640, 360), Color(0.055, 0.06, 0.08), true)
	for i in range(6):
		draw_rect(Rect2(0, float(i) * 60.0, 640, 30.0), Color(1, 1, 1, 0.012), true)
	if flash > 0.0:
		draw_rect(Rect2(0, 0, 640, 360), Color(1.0, 0.85, 0.4, 0.10 * flash), true)
	_draw_header(font)
	_draw_tabs(font)
	_draw_rows(font)
	_draw_stage(font)
	_draw_enter(font)
	_draw_tier_panel(font)
	_draw_detail(font)
	_draw_career(font)
	if notice_t > 0.0:
		draw_string(font, Vector2(28, 336), notice, HORIZONTAL_ALIGNMENT_LEFT, 560, 10, Color(0.95, 0.82, 0.55, clampf(notice_t, 0.0, 1.0)))
	draw_string(font, Vector2(28, 350), "↑↓ 选择 · Enter 购买 / 出发 · ←→ 灾变阶或试炼 · Tab 切页 · V 图鉴 · Esc 返回", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.44, 0.46, 0.44))

func _draw_header(font: Font) -> void:
	draw_string(font, Vector2(28, 34), "营  地", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.94, 0.90, 0.78))
	var st: Dictionary = _stage_def_at(stage_cursor)
	draw_string(font, Vector2(120, 34), "旷野整备 · 第 %d 章 %s" % [int(st.get("chapter", 0)), String(st.get("name", "—"))], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.56, 0.52))
	draw_string(font, Vector2(400, 32), "舍客勒  %d" % Meta.shillings, HORIZONTAL_ALIGNMENT_RIGHT, 212, 14, Color(0.95, 0.80, 0.35))
	draw_line(Vector2(28, 44), Vector2(612, 44), Color(0.28, 0.28, 0.26), 1.0)

func _draw_tabs(font: Font) -> void:
	for i in range(3):
		var r: Rect2 = _tab_rect(i)
		var on: bool = (i == page) or (i == 2 and false)
		var hv: bool = i == tab_hover
		draw_rect(r, Color(0.15, 0.16, 0.19) if on else (Color(0.11, 0.12, 0.14) if hv else Color(0.085, 0.09, 0.105)), true)
		draw_rect(r, Color(0.95, 0.80, 0.38) if on else Color(0.24, 0.25, 0.27), false, 1.0)
		draw_string(font, Vector2(r.position.x, r.position.y + 15), PAGE_NAMES[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, Color(0.96, 0.92, 0.80) if on else Color(0.60, 0.61, 0.60))
	draw_string(font, Vector2(336, 67), "Tab 切页 · V 图鉴", HORIZONTAL_ALIGNMENT_RIGHT, 276, 9, Color(0.46, 0.48, 0.46))

func _draw_rows(font: Font) -> void:
	if page == 1:
		_draw_building_rows(font)
	else:
		_draw_upgrade_rows(font)

func _draw_upgrade_rows(font: Font) -> void:
	for i in range(Meta.UPGRADES.size()):
		var u: Dictionary = Meta.UPGRADES[i]
		var id: String = String(u.get("id", ""))
		var lv: int = Meta.level_of(id)
		var mx: int = int(u.get("max", 5))
		var r: Rect2 = _row_rect(i)
		var on: bool = i == sel
		draw_rect(r, Color(0.12, 0.13, 0.16) if on else Color(0.085, 0.09, 0.11), true)
		if on:
			draw_rect(Rect2(r.position.x, r.position.y, 3, r.size.y), Color(0.95, 0.80, 0.38), true)
		var name_c: Color = Color(0.96, 0.92, 0.80) if lv < mx else Color(0.62, 0.62, 0.58)
		draw_string(font, Vector2(r.position.x + 11, r.position.y + 15), String(u.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, name_c)
		draw_string(font, Vector2(r.position.x + 11, r.position.y + 24), String(u.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.52, 0.54, 0.56))
		for k in range(mx):
			var cx: float = r.position.x + 204.0 + float(k) * 10.0
			var cy: float = r.position.y + 12.5
			if k < lv:
				draw_circle(Vector2(cx, cy), 3.2, Color(0.95, 0.80, 0.38))
			else:
				draw_arc(Vector2(cx, cy), 3.0, 0.0, TAU, 10, Color(0.34, 0.35, 0.36), 1.0, true)
		var cost_txt: String
		var cost_c: Color
		if lv >= mx:
			cost_txt = "已满"
			cost_c = Color(0.55, 0.58, 0.52)
		else:
			var cost: int = Meta.upgrade_cost(id)
			cost_txt = "%d" % cost
			cost_c = Color(0.95, 0.80, 0.35) if Meta.shillings >= cost else Color(0.62, 0.34, 0.32)
		draw_string(font, Vector2(r.position.x + r.size.x - 92, r.position.y + 17), cost_txt, HORIZONTAL_ALIGNMENT_RIGHT, 82, 13, cost_c)

func _draw_building_rows(font: Font) -> void:
	var bs: Array = _buildings()
	if bs.is_empty():
		draw_string(font, Vector2(ROW_X + 8, ROW_Y0 + 24), "会幕数据缺失（data/store.json 未加载）", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.62, 0.5, 0.4))
		return
	for i in range(mini(6, bs.size())):
		var b: Dictionary = bs[i]
		var s: Dictionary = _building_status(b)
		var r: Rect2 = _row_rect(i)
		var on: bool = i == sel
		draw_rect(r, Color(0.12, 0.13, 0.16) if on else Color(0.085, 0.09, 0.11), true)
		if on:
			draw_rect(Rect2(r.position.x, r.position.y, 3, r.size.y), Color(0.95, 0.80, 0.38), true)
		var ok: bool = bool(s["ok"])
		draw_string(font, Vector2(r.position.x + 11, r.position.y + 15), String(b.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.96, 0.92, 0.80) if ok else Color(0.70, 0.68, 0.62))
		draw_string(font, Vector2(r.position.x + 11, r.position.y + 24), UIText.clip(String(b.get("desc", "")), 40), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.52, 0.54, 0.56))
		var right: String
		var rc: Color
		if bool(s["pending"]):
			right = "待实装"
			rc = Color(0.66, 0.56, 0.42)
		elif not bool(s["unlock_ok"]):
			right = "未开放"
			rc = Color(0.72, 0.48, 0.40)
		elif bool(s["maxed"]):
			right = "满级 Lv%d" % int(s["level"])
			rc = Color(0.55, 0.58, 0.52)
		else:
			right = "Lv %d · %d" % [int(s["level"]), int(s["cost"])]
			rc = Color(0.95, 0.80, 0.35) if Meta.shillings >= int(s["cost"]) else Color(0.62, 0.34, 0.32)
		draw_string(font, Vector2(r.position.x + r.size.x - 118, r.position.y + 17), right, HORIZONTAL_ALIGNMENT_RIGHT, 108, 11, rc)
		draw_string(font, Vector2(r.position.x + r.size.x - 118, r.position.y + 24), UIText.clip(String(b.get("unlocks", "")), 12), HORIZONTAL_ALIGNMENT_RIGHT, 108, 7, Color(0.42, 0.44, 0.42))

func _draw_stage(font: Font) -> void:
	var r: Rect2 = _stage_rect()
	var on: bool = sel == STAGE_ROW
	var s: Dictionary = _stage_def_at(stage_cursor)
	var unlocked: bool = _stage_unlocked(stage_cursor)
	draw_rect(r, Color(0.13, 0.14, 0.18) if on else Color(0.09, 0.10, 0.13), true)
	if on:
		draw_rect(Rect2(r.position.x, r.position.y, 3, r.size.y), Color(0.72, 0.78, 0.95), true)
	var line1: String = "第 %d 章 · %s · %s" % [int(s.get("chapter", 0)), String(s.get("name", "—")), String(s.get("scripture", ""))]
	draw_string(font, Vector2(r.position.x + 12, r.position.y + 14), line1, HORIZONTAL_ALIGNMENT_LEFT, 250, 12, Color(0.86, 0.90, 0.98) if unlocked else Color(0.86, 0.66, 0.58))
	var line2: String
	var line2_c: Color
	if unlocked:
		line2 = _stage_reward_text(String(s.get("id", "")))
		line2_c = Color(0.74, 0.66, 0.44)
	else:
		line2 = "未解锁 · 需得胜 %d 次（当前 %d）" % [int(s.get("unlock_wins", 0)), Meta.wins]
		line2_c = Color(0.80, 0.48, 0.40)
	draw_string(font, Vector2(r.position.x + 12, r.position.y + 26), UIText.clip(line2, 44), HORIZONTAL_ALIGNMENT_LEFT, 270, 8, line2_c)
	draw_string(font, Vector2(r.position.x + r.size.x - 96, r.position.y + 15), "%d / %d" % [stage_cursor + 1, GameData.stages.size()], HORIZONTAL_ALIGNMENT_RIGHT, 34, 8, Color(0.56, 0.60, 0.66))
	for w in range(2):
		var ar: Rect2 = _stage_arrow_rect(w)
		draw_rect(ar, Color(0.10, 0.11, 0.14), true)
		draw_rect(ar, Color(0.30, 0.33, 0.38), false, 1.0)
		draw_string(font, Vector2(ar.position.x, ar.position.y + 16), "‹" if w == 0 else "›", HORIZONTAL_ALIGNMENT_CENTER, ar.size.x, 14, Color(0.72, 0.78, 0.92))

func _draw_enter(font: Font) -> void:
	var r: Rect2 = _enter_rect()
	var on: bool = sel == ENTER_ROW
	var unlocked: bool = _stage_unlocked(stage_cursor)
	if unlocked:
		draw_rect(r, Color(0.15, 0.21, 0.16) if on else Color(0.09, 0.12, 0.10), true)
		if on:
			draw_rect(r, Color(0.55, 0.78, 0.52), false, 1.0)
	else:
		draw_rect(r, Color(0.16, 0.12, 0.12) if on else Color(0.10, 0.09, 0.09), true)
		if on:
			draw_rect(r, Color(0.62, 0.44, 0.40), false, 1.0)
	var txt: String
	var col: Color
	if unlocked:
		txt = "出发 →  第 %d 章 %s   ·   %s" % [int(_stage_def_at(stage_cursor).get("chapter", 0)), String(_stage_def_at(stage_cursor).get("name", "")), _witness_name()]
		col = Color(0.86, 0.96, 0.82)
	else:
		txt = "未解锁 · 需得胜 %d 次" % int(_stage_def_at(stage_cursor).get("unlock_wins", 0))
		col = Color(0.86, 0.66, 0.58)
	draw_string(font, Vector2(r.position.x, r.position.y + 17), txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, col)

func _draw_tier_panel(font: Font) -> void:
	var x: float = PANEL_X
	var y: float = TIER_Y
	draw_rect(Rect2(x, y, PANEL_W, TIER_H), Color(0.085, 0.09, 0.11), true)
	draw_rect(Rect2(x, y, PANEL_W, TIER_H), Color(0.26, 0.27, 0.28), false, 1.0)
	var hi: int = Meta.max_tier_allowed()
	var cur: int = Meta.effective_tier()
	draw_string(font, Vector2(x + 12, y + 19), "灾 变 阶", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.90, 0.86, 0.74))
	draw_string(font, Vector2(x + 130, y + 19), "最高 %d 阶" % hi, HORIZONTAL_ALIGNMENT_RIGHT, 86, 8, Color(0.50, 0.52, 0.50))
	draw_string(font, Vector2(x + 12, y + 36), Meta.tier_name(cur), HORIZONTAL_ALIGNMENT_LEFT, 200, 10, Color(0.92, 0.82, 0.60))
	for i in range(21):
		var n: int = i + 1
		var cx: float = x + 14.0 + float(i) * 9.4
		var avail: bool = n <= hi
		var active: bool = n == cur
		var c: Color = Color(0.95, 0.80, 0.38) if active else (Color(0.62, 0.64, 0.58) if avail else Color(0.30, 0.24, 0.24))
		draw_line(Vector2(cx, y + 48), Vector2(cx, y + 60), c, 2.0 if active else 1.0)
		if active:
			draw_circle(Vector2(cx, y + 44), 2.4, c)
	var tr: Dictionary = Meta.tier_row(cur)
	draw_string(font, Vector2(x + 12, y + 74), "敌 HP +%d%%   伤害 +%d%%   刷怪 +%d%%" % [int((Meta.tier_enemy_hp(cur) - 1.0) * 100.0), int((Meta.tier_enemy_dmg(cur) - 1.0) * 100.0), int((Meta.tier_spawn_rate(cur) - 1.0) * 100.0)], HORIZONTAL_ALIGNMENT_LEFT, 210, 8, Color(0.78, 0.60, 0.58))
	draw_string(font, Vector2(x + 12, y + 86), "舍客勒 ×%.2f   ·   七印 %d" % [float(tr.get("silver_mult", Meta.seal_mult(cur))), Meta.seals], HORIZONTAL_ALIGNMENT_LEFT, 210, 8, Color(0.72, 0.86, 0.66))
	draw_string(font, Vector2(x + 12, y + 98), "← → 调整 · 通关解锁下一印", HORIZONTAL_ALIGNMENT_LEFT, 210, 8, Color(0.46, 0.47, 0.45))

func _draw_detail(font: Font) -> void:
	var x: float = PANEL_X
	var y: float = DETAIL_Y
	draw_rect(Rect2(x, y, PANEL_W, DETAIL_H), Color(0.075, 0.08, 0.10), true)
	draw_rect(Rect2(x, y, PANEL_W, DETAIL_H), Color(0.24, 0.25, 0.26), false, 1.0)
	var tx: float = x + 12.0
	var tw: float = PANEL_W - 24.0
	if sel == ENTER_ROW:
		draw_string(font, Vector2(tx, y + 18), "出 发", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.86, 0.94, 0.82))
		var c: Dictionary = GameData.characters_by_id.get(RunCfg.character_id, {})
		draw_string(font, Vector2(tx, y + 36), String(c.get("name", "大卫")), HORIZONTAL_ALIGNMENT_LEFT, tw, 14, Color(0.94, 0.90, 0.78))
		draw_multiline_string(font, Vector2(tx, y + 52), UIText.perk_text(c.get("perk", {}), 2), HORIZONTAL_ALIGNMENT_LEFT, tw, 8, 2, Color(0.68, 0.72, 0.64))
		var s: Dictionary = _stage_def_at(stage_cursor)
		draw_string(font, Vector2(tx, y + 82), "试炼 · 第 %d 章 %s" % [int(s.get("chapter", 0)), String(s.get("name", ""))], HORIZONTAL_ALIGNMENT_LEFT, tw, 9, Color(0.72, 0.76, 0.82))
		draw_string(font, Vector2(tx, y + 96), "灾变阶 · %s" % Meta.tier_name(), HORIZONTAL_ALIGNMENT_LEFT, tw, 9, Color(0.78, 0.68, 0.50))
		draw_string(font, Vector2(tx, y + 116), "Enter 出发 · 先在此整备", HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.50, 0.52, 0.50))
		return
	if sel == STAGE_ROW:
		_draw_stage_detail(font, tx, y, tw)
		return
	if page == 1:
		_draw_building_detail(font, tx, y, tw)
	else:
		_draw_upgrade_detail(font, tx, y, tw)

func _draw_upgrade_detail(font: Font, tx: float, y: float, tw: float) -> void:
	var u: Dictionary = _upgrade_at(sel)
	if u.is_empty():
		return
	var id: String = String(u.get("id", ""))
	var lv: int = Meta.level_of(id)
	var mx: int = int(u.get("max", 5))
	draw_string(font, Vector2(tx, y + 18), String(u.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, 14, Color(0.96, 0.90, 0.74))
	draw_string(font, Vector2(tx, y + 32), String(u.get("scripture", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.58, 0.54, 0.44))
	draw_multiline_string(font, Vector2(tx, y + 46), String(u.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, 9, 2, Color(0.78, 0.75, 0.66))
	draw_string(font, Vector2(tx, y + 76), "等级 Lv %d / %d" % [lv, mx], HORIZONTAL_ALIGNMENT_LEFT, tw, 9, Color(0.70, 0.72, 0.66))
	if lv >= mx:
		draw_string(font, Vector2(tx, y + 92), "已满级", HORIZONTAL_ALIGNMENT_LEFT, tw, 10, Color(0.56, 0.60, 0.54))
	else:
		draw_string(font, Vector2(tx, y + 92), "下一级  %d 舍客勒" % Meta.upgrade_cost(id), HORIZONTAL_ALIGNMENT_LEFT, tw, 10, Color(0.95, 0.80, 0.35))
	draw_string(font, Vector2(tx, y + 112), "当前 " + _bonus_text(id), HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.66, 0.74, 0.64))

func _bonus_text(id: String) -> String:
	var b: Dictionary = Meta.bonus()
	match id:
		"might":
			return "全伤害 +%d%%" % int(round(float(b.get("damage_mult", 0.0)) * 100.0))
		"vitality":
			return "最大生命 +%d" % int(b.get("max_hp", 0))
		"swift":
			return "移速 +%d%%" % int(round(float(b.get("speed_pct", 0.0)) * 100.0))
		"grace":
			return "拾取 +%d%%" % int(round(float(b.get("pickup_pct", 0.0)) * 100.0))
		"wisdom":
			return "经验 +%d%%" % int(round(float(b.get("xp_gain", 0.0)) * 100.0))
		"mercy":
			return "升级回血 +%d%%" % int(round(float(b.get("level_heal", 0.0)) * 100.0))
	return ""

func _draw_building_detail(font: Font, tx: float, y: float, tw: float) -> void:
	var b: Dictionary = _building_at(sel)
	if b.is_empty():
		return
	var s: Dictionary = _building_status(b)
	draw_string(font, Vector2(tx, y + 18), String(b.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, 14, Color(0.96, 0.90, 0.74))
	draw_string(font, Vector2(tx, y + 31), String(b.get("scripture", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.58, 0.54, 0.44))
	draw_multiline_string(font, Vector2(tx, y + 44), String(b.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, 8, 2, Color(0.74, 0.72, 0.64))
	draw_string(font, Vector2(tx, y + 64), "开放 · " + String(b.get("unlocks", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, 7, Color(0.60, 0.58, 0.50))
	var ups: Array = _all_upgrades(b)
	for i in range(mini(ups.size(), 2)):
		var u: Dictionary = ups[i]
		var uid: String = String(u.get("id", ""))
		var live: bool = bool(u.get("live", false))
		var lv: int = Meta.level_of(uid)
		var mx: int = int(u.get("max_level", 5))
		var tail: String
		if not live:
			tail = "待实装"
		elif lv >= mx:
			tail = "已满"
		else:
			tail = "%d 舍客勒" % Meta.upgrade_cost(uid)
		var line: String = "%s  Lv %d/%d  %s" % [String(u.get("name", uid)), lv, mx, tail]
		draw_string(font, Vector2(tx, y + 80 + float(i) * 12.0), line, HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.70, 0.72, 0.66) if live else Color(0.50, 0.48, 0.44))
	if bool(s["pending"]):
		draw_string(font, Vector2(tx, y + 108), "强化数值尚未实装", HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.72, 0.54, 0.40))
	elif bool(s["maxed"]):
		draw_string(font, Vector2(tx, y + 108), "本建筑已全部满级", HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.56, 0.60, 0.54))
	elif bool(s["unlock_ok"]):
		draw_string(font, Vector2(tx, y + 108), "Enter 购买 · 下一级 %d 舍客勒" % int(s["cost"]), HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.92, 0.78, 0.38))
	else:
		draw_string(font, Vector2(tx, y + 108), "未开放 · " + String(b.get("unlocks", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.72, 0.48, 0.40))

func _draw_stage_detail(font: Font, tx: float, y: float, tw: float) -> void:
	var s: Dictionary = _stage_def_at(stage_cursor)
	if s.is_empty():
		return
	var sid: String = String(s.get("id", ""))
	var unlocked: bool = _stage_unlocked(stage_cursor)
	draw_string(font, Vector2(tx, y + 16), "试炼 · %d / %d · 已解锁 %d 章" % [stage_cursor + 1, GameData.stages.size(), _count_unlocked()], HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.60, 0.64, 0.70))
	draw_string(font, Vector2(tx, y + 33), String(s.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, 14, Color(0.90, 0.93, 0.98) if unlocked else Color(0.86, 0.66, 0.58))
	draw_string(font, Vector2(tx, y + 46), "第 %d 章 · %s" % [int(s.get("chapter", 0)), String(s.get("scripture", ""))], HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.58, 0.54, 0.44))
	draw_multiline_string(font, Vector2(tx, y + 60), String(s.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, 8, 3, Color(0.74, 0.72, 0.64))
	draw_multiline_string(font, Vector2(tx, y + 92), _stage_reward_text(sid), HORIZONTAL_ALIGNMENT_LEFT, tw, 8, 2, Color(0.78, 0.68, 0.42))
	if unlocked:
		draw_string(font, Vector2(tx, y + 112), "已解锁 · Enter 出发", HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.55, 0.82, 0.58))
	else:
		draw_string(font, Vector2(tx, y + 112), "需得胜 %d 次（当前 %d）" % [int(s.get("unlock_wins", 0)), Meta.wins], HORIZONTAL_ALIGNMENT_LEFT, tw, 8, Color(0.80, 0.50, 0.42))

func _draw_career(font: Font) -> void:
	draw_string(font, Vector2(PANEL_X + 2, 314), "出发 %d 次 · 得胜 %d 次 · 最佳击杀 %d" % [Meta.runs, Meta.wins, Meta.best_kills], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.56, 0.58, 0.55))
	draw_string(font, Vector2(PANEL_X + 2, 328), "最长存活 %s · 累计击杀 %d" % [_mmss(Meta.best_time), Meta.lifetime_kills], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.56, 0.58, 0.55))

func _mmss(s: float) -> String:
	var n: int = int(s)
	return "%d:%02d" % [n / 60, n % 60]

# ---------------------------------------------------------------- 自检

func _selftest() -> void:
	print("[camp] start shillings=%d wins=%d runs=%d seals=%d" % [Meta.shillings, Meta.wins, Meta.runs, Meta.seals])
	for u in Meta.UPGRADES:
		var id: String = String(u["id"])
		var cost: int = Meta.upgrade_cost(id)
		var ok: bool = Meta.buy(id)
		print("[camp] buy %s cost=%d ok=%s lv=%d left=%d" % [id, cost, str(ok), Meta.level_of(id), Meta.shillings])
	print("[camp] bonus=%s" % str(Meta.bonus()))
	print("[camp] tier cur=%d max=%d name=%s" % [Meta.effective_tier(), Meta.max_tier_allowed(), Meta.tier_name()])
	for b in _buildings():
		var s: Dictionary = _building_status(b)
		print("[camp] building %s lv=%d next=%s cost=%d ok=%s reason=%s pending=%s" % [String(b.get("id", "")), int(s["level"]), Meta.building_next(String(b.get("id", ""))), int(s["cost"]), str(s["ok"]), String(s["reason"]), str(s["pending"])])
	for b in _buildings():
		if bool(_building_status(b)["ok"]):
			var bid: String = String(b.get("id", ""))
			var okb: bool = Meta.buy_building(bid)
			print("[camp] buy_building %s ok=%s lv=%d left=%d" % [bid, str(okb), Meta.building_level(bid), Meta.shillings])
			break
	print("[camp] rows=%d stages=%d unlocked=%d" % [_rows(), GameData.stages.size(), _count_unlocked()])
	var start_sel: int = sel
	for i in range(_rows()):
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.keycode = KEY_DOWN
		_input(ev)
	print("[camp] nav start=%d after=%d rows=%d" % [start_sel, sel, _rows()])
	page = 1
	print("[camp] page1 rows=%d first=%s" % [_buildings().size(), String(_buildings()[0].get("name", "-")) if not _buildings().is_empty() else "-"])
	page = 0
	var before: int = stage_cursor
	for i in range(GameData.stages.size()):
		_cycle_stage(1)
	print("[camp] stage_cycle_back=%s cursor=%d" % [str(stage_cursor == before), stage_cursor])
	print("[camp] SELFTEST_DONE")
	get_tree().quit()
