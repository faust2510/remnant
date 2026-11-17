extends Control
## 营地：左侧 6 张强化 / 会幕卡片（图标框 + 名称 + 价格 + 等级星标），
## 右上七印金点（←→ 调整、可直接点击）+ 当前加成摘要，右下试炼地图卡，
## 底部固定「出发」按钮。↑↓ 选卡，Enter 购买 / 出发，Tab 切页，V 图鉴，Esc 返回。

const CARD_X := 24.0
const CARD_W := 308.0
const CARD_H := 34.0
const CARD_STEP := 37.0
const CARD_Y0 := 76.0
const DEPART_Y := 302.0
const DEPART_H := 38.0
const PANEL_X := 340.0
const PANEL_W := 276.0
const SEAL_Y := 76.0
const SEAL_H := 102.0
const STAGE_Y := 184.0
const STAGE_H := 111.0
const PAGE_NAMES := ["强化", "会幕", "图鉴"]
const STAGE_ROW := 6
const ENTER_ROW := 7
const SEAL_MAX := 7
const EMBER_COUNT := 18

var sel: int = 0
var page: int = 0
var hover: int = -1
var tab_hover: int = -1
var seal_hover: int = 0
var stage_arrow_hover: int = -1
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

func _silver_mult() -> float:
	var cur: int = Meta.effective_tier()
	var tr: Dictionary = Meta.tier_row(cur)
	return float(tr.get("silver_mult", Meta.seal_mult(cur)))

func _difficulty_stars(s: Dictionary) -> int:
	var budget: Dictionary = s.get("budget", {})
	var score: float = float(budget.get("base", 0)) + float(budget.get("per_minute", 0)) * 5.0
	var ratio: float = clampf((score - 450.0) / 290.0, 0.0, 1.0)
	return clampi(1 + int(round(ratio * 4.0)), 1, 5)

func _upgrade_card(i: int) -> Dictionary:
	if page != 0 or i < 0 or i >= Meta.UPGRADES.size():
		return {}
	var u: Dictionary = Meta.UPGRADES[i]
	var id: String = String(u.get("id", ""))
	var lv: int = Meta.level_of(id)
	var mx: int = int(u.get("max", 5))
	var cost: int = 0
	var state: String = "ok"
	if lv >= mx:
		state = "max"
	else:
		cost = Meta.upgrade_cost(id)
	return {
		"id": id, "name": String(u.get("name", "")), "desc": String(u.get("desc", "")),
		"level": lv, "max": mx, "cost": cost, "state": state, "glyph": id
	}

func _building_card(i: int) -> Dictionary:
	if page != 1:
		return {}
	var b: Dictionary = _building_at(i)
	if b.is_empty():
		return {}
	var st: Dictionary = _building_status(b)
	var ups: Array = _all_upgrades(b)
	var state: String = "ok"
	if bool(st["pending"]):
		state = "pending"
	elif not bool(st["unlock_ok"]):
		state = "locked"
	elif bool(st["maxed"]):
		state = "max"
	var glyph: String = String(b.get("id", ""))
	if not ups.is_empty():
		glyph = String(ups[0].get("id", glyph))
	return {
		"id": String(b.get("id", "")), "name": String(b.get("name", "")),
		"desc": String(b.get("desc", "")), "level": int(st["level"]),
		"max": maxi(ups.size(), 1), "cost": int(st["cost"]), "state": state, "glyph": glyph,
		"unlocks": String(b.get("unlocks", ""))
	}

func _card_view(i: int) -> Dictionary:
	return _upgrade_card(i) if page == 0 else _building_card(i)

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

func _set_tier(n: int) -> void:
	var hi: int = Meta.max_tier_allowed()
	if n > hi:
		sfx.play("hit", -14.0, 0.8)
		_notify("第 %d 阶以上需圣物「七印书卷」（通关第 7 印解锁）" % (hi + 1))
		return
	if n == Meta.effective_tier():
		return
	Meta.set_tier(n)
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
	if i == STAGE_ROW or i == ENTER_ROW:
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

func _card_rect(i: int) -> Rect2:
	return Rect2(CARD_X, CARD_Y0 + float(i) * CARD_STEP, CARD_W, CARD_H)

func _depart_rect() -> Rect2:
	return Rect2(CARD_X, DEPART_Y, CARD_W, DEPART_H)

func _stage_card_rect() -> Rect2:
	return Rect2(PANEL_X, STAGE_Y, PANEL_W, STAGE_H)

func _seal_rect() -> Rect2:
	return Rect2(PANEL_X, SEAL_Y, PANEL_W, SEAL_H)

func _tab_rect(i: int) -> Rect2:
	return Rect2(24.0 + float(i) * 94.0, 50.0, 88.0, 22.0)

func _seal_dot_pos(n: int) -> Vector2:
	return Vector2(PANEL_X + 34.0 + float(n - 1) * 32.0, SEAL_Y + 34.0)

## 左右箭头：手绘 V 形（宋体里的 ‹ › 会渲染成「( )」，实机像乱码）
func _chevron(ar: Rect2, side: int, col: Color) -> void:
	var cx: float = ar.position.x + ar.size.x * 0.5
	var cy: float = ar.position.y + ar.size.y * 0.5
	var w: float = ar.size.x * 0.22
	var h: float = ar.size.y * 0.24
	var sgn: float = 1.0 if side == 0 else -1.0   # side 0 = 左箭头，顶点必须朝左
	draw_line(Vector2(cx + sgn * w * 0.5, cy - h), Vector2(cx - sgn * w * 0.5, cy), col, 2.0)
	draw_line(Vector2(cx - sgn * w * 0.5, cy), Vector2(cx + sgn * w * 0.5, cy + h), col, 2.0)

func _seal_arrow_rect(side: int) -> Rect2:
	return Rect2(PANEL_X + (2.0 if side == 0 else PANEL_W - 30.0), SEAL_Y + 26.0, 18.0, 20.0)

func _stage_arrow_rect(side: int) -> Rect2:
	var r: Rect2 = _stage_card_rect()
	return Rect2(r.position.x + r.size.x - (56.0 if side == 0 else 30.0), r.position.y + 6.0, 22.0, 20.0)

func _pointer_row(m: Vector2) -> int:
	for i in range(6):
		if _card_rect(i).has_point(m):
			return i
	if _stage_card_rect().has_point(m):
		return STAGE_ROW
	if _depart_rect().has_point(m):
		return ENTER_ROW
	return -1

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
		var row: int = _pointer_row(m)
		if row >= 0:
			hover = row
			sel = row
	elif e is InputEventMouseButton and e.pressed:
		var m2: Vector2 = e.position
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _seal_rect().has_point(m2):
				_adjust_tier(-1)
				return
			if _stage_card_rect().has_point(m2):
				_cycle_stage(-1)
				return
		if e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _seal_rect().has_point(m2):
				_adjust_tier(1)
				return
			if _stage_card_rect().has_point(m2):
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
		for n in range(1, 8):
			if _seal_dot_pos(n).distance_to(m2) <= 11.0:
				_set_tier(n)
				return
		for side in range(2):
			if _seal_arrow_rect(side).has_point(m2):
				_adjust_tier(-1 if side == 0 else 1)
				return
			if _stage_arrow_rect(side).has_point(m2):
				_cycle_stage(-1 if side == 0 else 1)
				return
		if _stage_card_rect().has_point(m2):
			sel = STAGE_ROW
			return
		if _depart_rect().has_point(m2):
			sel = ENTER_ROW
			_enter()
			return
		for i in range(6):
			if _card_rect(i).has_point(m2):
				sel = i
				_activate(i)
				return

func _process(d: float) -> void:
	t += d
	flash = maxf(0.0, flash - d * 2.5)
	notice_t = maxf(0.0, notice_t - d)
	var m: Vector2 = get_local_mouse_position()
	hover = _pointer_row(m)
	tab_hover = -1
	for i in range(3):
		if _tab_rect(i).has_point(m):
			tab_hover = i
	seal_hover = 0
	var sd: float = 999.0
	for n in range(1, 8):
		var d2: float = _seal_dot_pos(n).distance_to(m)
		if d2 < sd and d2 <= 12.0:
			sd = d2
			seal_hover = n
	stage_arrow_hover = -1
	for side in range(2):
		if _stage_arrow_rect(side).has_point(m):
			stage_arrow_hover = side
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
	_draw_background()
	if flash > 0.0:
		draw_rect(Rect2(0, 0, 640, 360), Color(1.0, 0.85, 0.4, 0.10 * flash), true)
	_draw_header(font)
	_draw_tabs(font)
	_draw_cards(font)
	_draw_seals(font)
	_draw_stage_card(font)
	_draw_depart(font)
	_draw_career(font)
	if notice_t > 0.0:
		UITheme.text(self, Vector2(24, 352), notice, 10, Color(0.95, 0.82, 0.55, clampf(notice_t, 0.0, 1.0)), 1, 592.0)

func _draw_background() -> void:
	draw_rect(Rect2(0, 0, 640, 360), UITheme.INK_DEEP, true)
	for row in range(4):
		var y: float = float(row) * 90.0
		var lift: float = 0.006 if row % 2 == 0 else 0.0
		draw_rect(Rect2(0, y, 640, 90), Color(0.052 + lift, 0.062 + lift, 0.090 + lift, 1.0), true)
		draw_rect(Rect2(0, y, 640, 1), Color(0, 0, 0, 0.35), true)
		for k in range(3):
			var jx: float = fposmod(_hash01(row * 23 + k) * 640.0 + float(k) * 226.0, 640.0)
			draw_rect(Rect2(jx, y, 1, 90), Color(0, 0, 0, 0.20), true)
	draw_circle(Vector2(168, 322), 150.0, Color(0.95, 0.62, 0.24, 0.035))
	draw_circle(Vector2(320, 30), 190.0, Color(0.90, 0.70, 0.34, 0.030))
	_draw_embers()
	for i in range(7):
		draw_rect(Rect2(float(i) * 3.0, float(i) * 2.0, 640.0 - float(i) * 6.0, 360.0 - float(i) * 4.0), Color(0, 0, 0, 0.03), false, 2.0)

func _draw_embers() -> void:
	for i in range(EMBER_COUNT):
		var sx: float = _hash01(i * 3 + 2)
		var spd: float = 7.0 + _hash01(i * 5 + 1) * 15.0
		var y: float = fposmod(360.0 - t * spd - _hash01(i * 7 + 4) * 360.0, 396.0)
		var x: float = sx * 640.0 + sin(t * 0.45 + float(i) * 1.9) * (5.0 + _hash01(i * 11) * 9.0)
		var a: float = (0.08 + 0.18 * _hash01(i * 13 + 5)) * clampf(y / 396.0, 0.22, 1.0)
		draw_circle(Vector2(x, y), 0.9 + _hash01(i * 17) * 1.2, Color(0.95, 0.72, 0.38, a))

func _draw_header(font: Font) -> void:
	UITheme.text(self, Vector2(25, 35), "营  地", 22, Color(0, 0, 0, 0.55), 0, -1.0)
	UITheme.text(self, Vector2(24, 34), "营  地", 22, UITheme.PARCH, 0, -1.0)
	var st: Dictionary = _stage_def_at(stage_cursor)
	UITheme.text(self, Vector2(106, 30), "旷野整备 · %s · 第 %d 章 %s" % [_witness_name(), int(st.get("chapter", 0)), UIText.clip(String(st.get("name", "—")), 8)], 10, Color(0.56, 0.57, 0.53), 0, 330.0)
	draw_circle(Vector2(466, 29), 6.0, Color(0.86, 0.70, 0.32))
	draw_circle(Vector2(464.5, 27.5), 2.4, Color(0.98, 0.92, 0.72, 0.85))
	UITheme.text(self, Vector2(478, 34), "舍客勒  %d" % Meta.shillings, 14, Color(0.95, 0.80, 0.35), 2, 138.0)
	UITheme.divider(self, 24.0, 616.0, 46.0, 0.9)

func _draw_tabs(font: Font) -> void:
	for i in range(3):
		var r: Rect2 = _tab_rect(i)
		var on: bool = i == page
		var hv: bool = i == tab_hover
		var base := Color(0.085, 0.090, 0.105)
		if on:
			base = Color(0.15, 0.16, 0.19)
		elif hv:
			base = Color(0.11, 0.12, 0.14)
		draw_rect(r, base, true)
		draw_rect(r, UITheme.GOLD_BRIGHT if on else (UITheme.GOLD if hv else Color(0.24, 0.25, 0.27)), false, 1.0)
		UITheme.text(self, Vector2(r.position.x, r.position.y + 15.0), PAGE_NAMES[i], 11, Color(0.96, 0.92, 0.80) if on else Color(0.60, 0.61, 0.60), 1, r.size.x)
	UITheme.text(self, Vector2(300, 66), "↑↓ 选择 · Enter 购买 · Tab 切页 · V 图鉴 · Esc 返回", 10, Color(0.46, 0.48, 0.46), 2, 316.0)

func _draw_cards(font: Font) -> void:
	for i in range(6):
		_draw_card(i, font)

func _draw_card(i: int, font: Font) -> void:
	var v: Dictionary = _card_view(i)
	var r: Rect2 = _card_rect(i)
	if v.is_empty():
		draw_rect(r, Color(0.05, 0.055, 0.075, 0.6), true)
		draw_rect(r, Color(0.22, 0.22, 0.20, 0.35), false, 1.0)
		return
	var state: String = String(v["state"])
	var lit: bool = state != "pending" and state != "locked"
	var on: bool = sel == i
	var hv: bool = hover == i and not on
	var bg := Color(0.072, 0.082, 0.108, 0.96)
	if hv:
		bg = bg.lightened(0.06)
	if on:
		bg = bg.lerp(UITheme.INK_SOFT, 0.55)
	draw_rect(r, bg, true)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1.0), Color(1, 1, 1, 0.035), true)
	var border := Color(0.22, 0.24, 0.27, 0.9)
	if on:
		border = UITheme.GOLD_BRIGHT
	elif hv:
		border = UITheme.GOLD
	draw_rect(r, border, false, 2.0 if on else 1.0)
	if on:
		draw_rect(Rect2(r.position.x, r.position.y + 2.0, 3.0, r.size.y - 4.0), UITheme.GOLD_BRIGHT, true)
	var ir := Rect2(r.position.x + 6.0, r.position.y + 1.0, 32.0, 32.0)
	UITheme.icon_frame(self, ir, null, Rect2(), 0.9 if on else 0.0)
	_draw_glyph(String(v["glyph"]), ir.position.x + 16.0, ir.position.y + 16.0, Color(0.94, 0.84, 0.58) if lit else Color(0.60, 0.57, 0.50))
	UITheme.text(self, Vector2(r.position.x + 44.0, r.position.y + 14.0), UIText.clip(String(v["name"]), 6), 11, UITheme.PARCH if lit else Color(0.66, 0.64, 0.58), 0, 152.0)
	var note: String = ""
	var note_c := Color(0.95, 0.80, 0.35)
	var cost: int = int(v["cost"])
	match state:
		"max":
			note = "已满级"
			note_c = Color(0.56, 0.58, 0.54)
		"pending":
			note = "待实装"
			note_c = Color(0.68, 0.58, 0.44)
		"locked":
			note = "未开放"
			note_c = Color(0.78, 0.50, 0.42)
		_:
			note = "%d" % cost
			if Meta.shillings < cost:
				note_c = Color(0.70, 0.40, 0.36)
	UITheme.text(self, Vector2(r.position.x + r.size.x - 70.0, r.position.y + 14.0), note, 10, note_c, 2, 58.0)
	if state == "ok":
		var coin := Color(0.78, 0.66, 0.36) if Meta.shillings >= cost else Color(0.52, 0.34, 0.30)
		draw_circle(Vector2(r.position.x + r.size.x - 76.0, r.position.y + 10.0), 3.0, coin)
		draw_circle(Vector2(r.position.x + r.size.x - 77.2, r.position.y + 8.8), 1.1, Color(0.96, 0.90, 0.72, 0.8))
	var desc_text: String = String(v["desc"])
	if state == "locked":
		desc_text = String(v.get("unlocks", "")) + " · " + desc_text
	UITheme.text(self, Vector2(r.position.x + 44.0, r.position.y + 28.0), UIText.clip(desc_text, 15), 10, Color(0.58, 0.60, 0.56) if lit else Color(0.46, 0.47, 0.46), 0, 158.0)
	_draw_level_stars(r.position.x + r.size.x - 12.0, r.position.y + 27.0, int(v["level"]), int(v["max"]), lit)

func _draw_level_stars(right_x: float, y: float, level: int, max_level: int, lit: bool) -> void:
	var n: int = clampi(max_level, 1, 8)
	for k in range(n):
		var cx: float = right_x - float(n - 1 - k) * 9.0 - 2.0
		var col := UITheme.GOLD_BRIGHT if k < level else Color(0.30, 0.31, 0.30, 0.9)
		if not lit and k < level:
			col = Color(0.62, 0.55, 0.38)
		UITheme.star(self, Vector2(cx, y), 3.4, col)

func _draw_glyph(gid: String, cx: float, cy: float, col: Color) -> void:
	match gid:
		"might":
			draw_line(Vector2(cx, cy - 11.0), Vector2(cx, cy + 3.0), col, 3.0)
			draw_rect(Rect2(cx - 5.0, cy + 3.0, 10.0, 2.0), col, true)
			draw_line(Vector2(cx, cy + 5.0), Vector2(cx, cy + 10.0), col, 2.0)
			draw_circle(Vector2(cx, cy + 11.0), 1.8, col)
		"vitality", "mercy":
			draw_circle(Vector2(cx - 4.0, cy - 3.0), 4.2, col)
			draw_circle(Vector2(cx + 4.0, cy - 3.0), 4.2, col)
			var heart := PackedVector2Array([Vector2(cx - 8.0, cy - 1.0), Vector2(cx + 8.0, cy - 1.0), Vector2(cx, cy + 9.0)])
			draw_colored_polygon(heart, col)
			if gid == "mercy":
				for k in range(3):
					var ax: float = cx - 7.0 + float(k) * 7.0
					draw_line(Vector2(ax, cy - 11.0), Vector2(ax + 1.5, cy - 8.0), Color(col.r, col.g, col.b, 0.75), 1.0)
		"swift":
			draw_line(Vector2(cx - 9.0, cy + 8.0), Vector2(cx + 7.0, cy - 8.0), col, 2.4)
			var head := PackedVector2Array([Vector2(cx + 10.0, cy - 11.0), Vector2(cx + 2.0, cy - 9.0), Vector2(cx + 8.0, cy - 3.0)])
			draw_colored_polygon(head, col)
			draw_line(Vector2(cx - 10.0, cy + 2.0), Vector2(cx - 4.0, cy + 2.0), Color(col.r, col.g, col.b, 0.5), 1.0)
			draw_line(Vector2(cx - 10.0, cy + 6.0), Vector2(cx - 6.0, cy + 6.0), Color(col.r, col.g, col.b, 0.4), 1.0)
		"grace":
			draw_arc(Vector2(cx, cy), 8.0, 0.0, TAU, 22, col, 2.0, true)
			draw_line(Vector2(cx, cy - 4.0), Vector2(cx, cy + 4.0), col, 1.6)
			draw_line(Vector2(cx - 4.0, cy), Vector2(cx + 4.0, cy), col, 1.2)
		"wisdom":
			draw_rect(Rect2(cx - 8.0, cy - 8.0, 16.0, 16.0), col, false, 2.0)
			for k in range(3):
				draw_line(Vector2(cx - 5.0, cy - 4.0 + float(k) * 4.0), Vector2(cx + 5.0, cy - 4.0 + float(k) * 4.0), col, 1.0)
		"faith":
			var shield := PackedVector2Array([Vector2(cx, cy - 10.0), Vector2(cx + 8.0, cy - 6.0), Vector2(cx + 6.0, cy + 5.0), Vector2(cx, cy + 10.0), Vector2(cx - 6.0, cy + 5.0), Vector2(cx - 8.0, cy - 6.0)])
			draw_colored_polygon(shield, col)
			draw_line(Vector2(cx, cy - 6.0), Vector2(cx, cy + 7.0), Color(0.12, 0.12, 0.14, 0.6), 1.2)
		"prayer":
			draw_arc(Vector2(cx, cy - 6.0), 3.0, 0.0, TAU, 10, Color(col.r, col.g, col.b, 0.5), 1.0, true)
			draw_arc(Vector2(cx, cy - 1.0), 4.0, 0.0, TAU, 12, Color(col.r, col.g, col.b, 0.7), 1.0, true)
			var bowl := PackedVector2Array([Vector2(cx - 8.0, cy + 3.0), Vector2(cx + 8.0, cy + 3.0), Vector2(cx + 4.0, cy + 9.0), Vector2(cx - 4.0, cy + 9.0)])
			draw_colored_polygon(bowl, col)
		"sanctuary":
			draw_arc(Vector2(cx, cy - 3.0), 8.0, PI * 1.05, PI * 1.95, 12, Color(col.r, col.g, col.b, 0.9), 1.6, true)
			draw_rect(Rect2(cx - 9.0, cy - 1.0, 18.0, 8.0), col, true)
			draw_line(Vector2(cx - 6.0, cy - 5.0), Vector2(cx - 6.0, cy - 1.0), col, 1.6)
			draw_line(Vector2(cx + 6.0, cy - 5.0), Vector2(cx + 6.0, cy - 1.0), col, 1.6)
		_:
			var dia := PackedVector2Array([Vector2(cx, cy - 9.0), Vector2(cx + 9.0, cy), Vector2(cx, cy + 9.0), Vector2(cx - 9.0, cy)])
			draw_colored_polygon(dia, col)

func _draw_seals(font: Font) -> void:
	var r: Rect2 = _seal_rect()
	UITheme.panel(self, r, 1.0, true)
	var cur: int = Meta.effective_tier()
	var hi: int = Meta.max_tier_allowed()
	UITheme.text(self, Vector2(r.position.x + 14.0, r.position.y + 18.0), "七 印", 12, UITheme.GOLD_PALE, 0, -1.0)
	UITheme.text(self, Vector2(r.position.x + 80.0, r.position.y + 18.0), "灾变阶 · " + UIText.clip(Meta.tier_name(), 9), 10, Color(0.82, 0.74, 0.54), 2, r.size.x - 94.0)
	for side in range(2):
		var ar: Rect2 = _seal_arrow_rect(side)
		var hv: bool = _seal_arrow_rect(side).has_point(get_local_mouse_position())
		draw_rect(ar, Color(0.10, 0.11, 0.14, 0.9) if not hv else Color(0.16, 0.17, 0.21), true)
		draw_rect(ar, Color(0.30, 0.33, 0.38), false, 1.0)
		_chevron(ar, side, Color(0.72, 0.78, 0.92))
	for n in range(1, SEAL_MAX + 1):
		var p: Vector2 = _seal_dot_pos(n)
		var avail: bool = n <= hi
		var act: bool = n == cur
		var hov: bool = n == seal_hover
		var col := Color(0.86, 0.72, 0.40)
		if not avail:
			col = Color(0.34, 0.28, 0.26)
		elif not act:
			col = col.lerp(Color(0.98, 0.90, 0.66), 0.25 if hov else 0.0)
		draw_circle(p, 7.2 if act else (6.2 if hov else 5.4), col)
		draw_circle(p, 2.4, Color(0.12, 0.10, 0.08, 0.9))
		if act:
			draw_arc(p, 9.6, 0.0, TAU, 24, Color(0.98, 0.88, 0.60, 0.9), 1.4, true)
		UITheme.text(self, Vector2(p.x - 10.0, p.y + 20.0), "%d" % n, 10, Color(0.86, 0.78, 0.58) if avail else Color(0.40, 0.36, 0.34), 1, 20.0)
	var b: Dictionary = Meta.bonus()
	var tr: Dictionary = Meta.tier_row(cur)
	UITheme.text(self, Vector2(r.position.x + 14.0, r.position.y + 70.0), "伤害 +%d%% · 生命 +%d · 移速 +%d%%" % [int(round(float(b.get("damage_mult", 0.0)) * 100.0)), int(b.get("max_hp", 0)), int(round(float(b.get("speed_pct", 0.0)) * 100.0))], 10, Color(0.80, 0.82, 0.72), 0, r.size.x - 28.0)
	UITheme.text(self, Vector2(r.position.x + 14.0, r.position.y + 82.0), "拾取 +%d%% · 经验 +%d%% · 回血 +%d%%" % [int(round(float(b.get("pickup_pct", 0.0)) * 100.0)), int(round(float(b.get("xp_gain", 0.0)) * 100.0)), int(round(float(b.get("level_heal", 0.0)) * 100.0))], 10, Color(0.74, 0.78, 0.66), 0, r.size.x - 28.0)
	UITheme.text(self, Vector2(r.position.x + 14.0, r.position.y + 94.0), "敌 HP +%d%% · 舍客勒 ×%.2f" % [int(round((Meta.tier_enemy_hp(cur) - 1.0) * 100.0)), float(tr.get("silver_mult", Meta.seal_mult(cur)))], 10, Color(0.78, 0.62, 0.58), 0, r.size.x - 28.0)

func _draw_stage_card(font: Font) -> void:
	var r: Rect2 = _stage_card_rect()
	var s: Dictionary = _stage_def_at(stage_cursor)
	var unlocked: bool = _stage_unlocked(stage_cursor)
	var on: bool = sel == STAGE_ROW
	UITheme.panel(self, r, 1.0, true)
	if on:
		draw_rect(r.grow(-3.0), Color(UITheme.GOLD_BRIGHT.r, UITheme.GOLD_BRIGHT.g, UITheme.GOLD_BRIGHT.b, 0.5), false, 1.0)
	var name_c := Color(0.92, 0.94, 0.98) if unlocked else Color(0.86, 0.64, 0.56)
	UITheme.text(self, Vector2(r.position.x + 14.0, r.position.y + 20.0), "第 %d 章 · %s" % [int(s.get("chapter", 0)), UIText.clip(String(s.get("name", "—")), 10)], 12, name_c, 0, 200.0)
	for side in range(2):
		var ar: Rect2 = _stage_arrow_rect(side)
		var hv: bool = stage_arrow_hover == side
		draw_rect(ar, Color(0.10, 0.11, 0.14, 0.9) if not hv else Color(0.16, 0.17, 0.21), true)
		draw_rect(ar, Color(0.34, 0.37, 0.44), false, 1.0)
		_chevron(ar, side, Color(0.72, 0.78, 0.92))
	UITheme.text(self, Vector2(r.position.x + 14.0, r.position.y + 34.0), "第 %d / %d 章 · 已解锁 %d 章" % [stage_cursor + 1, GameData.stages.size(), _count_unlocked()], 10, Color(0.56, 0.60, 0.66), 0, 250.0)
	var stars: int = _difficulty_stars(s)
	UITheme.text(self, Vector2(r.position.x + 14.0, r.position.y + 54.0), "难度", 10, Color(0.62, 0.60, 0.50), 0, -1.0)
	for k in range(5):
		var cx: float = r.position.x + 60.0 + float(k) * 12.0
		UITheme.star(self, Vector2(cx, r.position.y + 50.0), 4.0, UITheme.GOLD_BRIGHT if k < stars else Color(0.28, 0.29, 0.28))
	UITheme.text(self, Vector2(r.position.x + 130.0, r.position.y + 54.0), "舍客勒 ×%.2f" % _silver_mult(), 10, Color(0.86, 0.78, 0.48), 2, r.size.x - 144.0)
	UITheme.text(self, Vector2(r.position.x + 14.0, r.position.y + 68.0), UIText.clip(String(s.get("scripture", "")), 24), 10, Color(0.58, 0.54, 0.44), 0, 250.0)
	var line: String
	var lc: Color
	if unlocked:
		line = "已解锁 · Enter 出发"
		lc = Color(0.60, 0.84, 0.58)
	else:
		line = "需通关 %d 次（已通关 %d）" % [int(s.get("unlock_wins", 0)), Meta.wins]
		lc = Color(0.86, 0.55, 0.44)
	UITheme.text(self, Vector2(r.position.x + 14.0, r.position.y + 84.0), line, 10, lc, 0, 250.0)
	UITheme.text(self, Vector2(r.position.x + 14.0, r.position.y + 100.0), UIText.clip(String(s.get("desc", "")), 24), 10, Color(0.56, 0.56, 0.50), 0, 250.0)

func _draw_depart(font: Font) -> void:
	var r: Rect2 = _depart_rect()
	var unlocked: bool = _stage_unlocked(stage_cursor)
	var on: bool = sel == ENTER_ROW or hover == ENTER_ROW
	var s: Dictionary = _stage_def_at(stage_cursor)
	var label: String
	if unlocked:
		label = "出 发 · 第 %d 章 %s" % [int(s.get("chapter", 0)), UIText.clip(String(s.get("name", "")), 9)]
	else:
		label = "未解锁 · 需通关 %d 次" % int(s.get("unlock_wins", 0))
	UITheme.button(self, r, label, unlocked, (0.5 + 0.5 * sin(t * 3.0)) if on else 0.0)

func _draw_career(font: Font) -> void:
	UITheme.text(self, Vector2(PANEL_X, 318.0), "出发 %d 次 · 得胜 %d 次 · 累计击杀 %d" % [Meta.runs, Meta.wins, Meta.lifetime_kills], 10, Color(0.56, 0.58, 0.55), 0, PANEL_W)
	UITheme.text(self, Vector2(PANEL_X, 332.0), "最佳存活 %s · 最高击杀 %d" % [_mmss(Meta.best_time), Meta.best_kills], 10, Color(0.56, 0.58, 0.55), 0, PANEL_W)

func _hash01(n: int) -> float:
	var v: float = sin(float(n) * 12.9898 + 78.233) * 43758.5453
	return v - floor(v)

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
