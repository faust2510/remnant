class_name HUD
extends Control
## 全部 UI 都在这一层用 draw_* 画出来，避免一堆 theme 资源。
## V2：约卡图标 / 机制状态行 / 圣物小图标 / BOSS 名与阶段刻度 / 结算成就与银两明细。
## run.gd 由局内代理并行改，所有新字段都用 run.get("x") 兜底，缺失就跳过。

var run: Node = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_d: float) -> void:
	queue_redraw()

func _font() -> Font:
	return GameFont.get_font()

func _fmt_time(t: float) -> String:
	var tt: int = int(maxf(t, 0.0))
	return "%02d:%02d" % [tt / 60, tt % 60]

func _draw() -> void:
	if run == null or run.state == null:
		return
	var f: Font = _font()
	var st: GameState = run.state

	# ---- 屏幕反馈层：受伤红闪 / 低血暗角 / 升级金闪
	var vw: float = 640.0
	var vh: float = 360.0
	var hurt: float = clampf(float(run.hurt_flash), 0.0, 1.0)
	if hurt > 0.01:
		draw_rect(Rect2(0, 0, vw, vh), Color(0.72, 0.10, 0.12, 0.22 * hurt), true)
	var hp_now: float = clampf(run.player_hp / maxf(run.player_max_hp, 1.0), 0.0, 1.0)
	if hp_now < 0.35 and not run.over:
		var pulse: float = 0.07 + 0.05 * sin(float(Time.get_ticks_msec()) * 0.0055)
		var band: float = 44.0
		var vc := Color(0.45, 0.05, 0.07, pulse)
		draw_rect(Rect2(0, 0, vw, band), vc, true)
		draw_rect(Rect2(0, vh - band, vw, band), vc, true)
		draw_rect(Rect2(0, band, band, vh - band * 2.0), vc, true)
		draw_rect(Rect2(vw - band, band, band, vh - band * 2.0), vc, true)
	var lf: float = clampf(float(run.level_flash), 0.0, 1.0)
	if lf > 0.01:
		draw_rect(Rect2(0, 0, vw, vh), Color(1.0, 0.86, 0.45, 0.12 * lf), true)

	# ---- 顶部：经验条 + 时间
	var xp_w: float = 640.0 * st.xp_progress()
	draw_rect(Rect2(0, 0, 640, 5), Color(0.08, 0.09, 0.12, 0.9), true)
	draw_rect(Rect2(0, 0, xp_w, 5), Color("#7FE0C0"), true)
	draw_string(f, Vector2(6, 18), "Lv %d" % st.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#E8DCC0"))
	draw_string(f, Vector2(560, 18), _fmt_time(run.elapsed), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#E8DCC0"))
	draw_string(f, Vector2(6, 32), "击杀 %d" % st.kills, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.75, 0.72, 0.65))
	if st.coals > 0:
		draw_string(f, Vector2(6, 46), "火炭 %d · [E] 祭坛" % st.coals, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#E0731A"))

	# ---- 约卡（run.covenants，缺字段则整行不画）
	_draw_covenants(f)

	# ---- 左下：HP 条
	var hp_frac: float = clampf(run.player_hp / maxf(run.player_max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(6, 338, 132, 8), Color(0.08, 0.09, 0.12, 0.9), true)
	draw_rect(Rect2(6, 338, 132.0 * hp_frac, 8), Color("#B0424A") if hp_frac < 0.35 else Color("#C96A5A"), true)
	draw_string(f, Vector2(9, 346), "%d / %d" % [int(run.player_hp), int(run.player_max_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 1, 1, 0.85))

	# ---- 左下：圣物小图标（最多 12 个，不占果子槽）
	_draw_relic_icons(f, st)

	# ---- 右下：武器槽与被动槽
	var wx: float = 640.0 - 8.0
	for i in range(st.weapons.size() - 1, -1, -1):
		var w: Dictionary = st.weapons[i]
		var def: Dictionary = st.weapon_def(w)
		var c: Color = Color(String(def.get("color", "#C9A66B")))
		wx -= 26.0
		draw_rect(Rect2(wx, 292, 24, 24), Color(0.08, 0.09, 0.12, 0.85), true)
		draw_rect(Rect2(wx + 1, 293, 22, 22), c, false, 1.0)
		var nm: String = String(def.get("name", "?"))
		draw_string(f, Vector2(wx + 3, 306), nm.substr(0, 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#E8DCC0"))
		var lv_txt: String = "★" if bool(w.get("ascended", false)) else str(int(w["level"]))
		draw_string(f, Vector2(wx + 15, 314), lv_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("#E0B85A"))
	var px: float = 640.0 - 8.0
	for i in range(st.passives.size() - 1, -1, -1):
		var ps: Dictionary = st.passives[i]
		var pdef: Dictionary = GameData.passives.get(ps["id"], {})
		px -= 18.0
		draw_rect(Rect2(px, 322, 16, 12), Color(0.12, 0.12, 0.16, 0.85), true)
		draw_string(f, Vector2(px + 1, 330), String(pdef.get("name", "?")).substr(0, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("#B8C4A8"))
	# 全副军装：精英战利品，单独一行小金字，不占果子槽
	var ax: float = 640.0 - 8.0
	for i in range(st.armor.size() - 1, -1, -1):
		var adef: Dictionary = GameData.passives.get(String(st.armor[i]["id"]), {})
		ax -= 15.0
		draw_rect(Rect2(ax, 338, 13, 10), Color(0.18, 0.16, 0.10, 0.85), true)
		draw_string(f, Vector2(ax + 1, 345), String(adef.get("name", "?")).substr(0, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("#D8C48A"))
	# 战利品浮字（得军装 / 得火炭）
	if run.toast_t > 0.0:
		var ta: float = clampf(run.toast_t / 0.8, 0.0, 1.0)
		draw_string(f, Vector2(0, 268), run.toast_text, HORIZONTAL_ALIGNMENT_CENTER, 640, 10, Color(0.95, 0.87, 0.62, ta))

	# ---- 机制状态行（run.mechanics，多形态兼容，缺就跳过）
	_draw_mechanics_line(f)

	# ---- BOSS 血条
	if run.boss_index >= 0 and run.boss_index < run.enemies.count:
		var e: EnemySim = run.enemies
		var frac: float = clampf(e.hp[run.boss_index] / maxf(e.max_hp[run.boss_index], 1.0), 0.0, 1.0)
		draw_rect(Rect2(160, 12, 320, 8), Color(0.08, 0.09, 0.12, 0.9), true)
		draw_rect(Rect2(160, 12, 320.0 * frac, 8), Color("#8E2F2F"), true)
		for notch in [0.66, 0.33]:
			draw_line(Vector2(160.0 + 320.0 * notch, 12), Vector2(160.0 + 320.0 * notch, 20), Color(0.95, 0.82, 0.55, 0.55), 1.0)
		var bid: String = String(e.type_ids[e.typ[run.boss_index]])
		var bdef: Dictionary = GameData.enemies.get(bid, {})
		if bdef.is_empty():
			bdef = GameData.boss_def(bid)
		var bname: String = String(bdef.get("name", "首领"))
		draw_string(f, Vector2(160, 34), bname, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#E8DCC0"))
		var bsub: String = "首领 · 第 %d 章 · %d%%" % [int(bdef.get("chapter", 0)), int(frac * 100.0)]
		draw_string(f, Vector2(400, 34), bsub, HORIZONTAL_ALIGNMENT_RIGHT, 78, 7, Color(0.78, 0.66, 0.55))
		var phase_txt: String = _boss_phase_text(bdef, frac)
		if phase_txt != "":
			draw_string(f, Vector2(160, 44), phase_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.82, 0.56, 0.50))

	# ---- 结算
	if run.over:
		_draw_result(f, st)

	# ---- 提示：完美闪避
	if run.perfect_flash > 0.0:
		draw_string(f, Vector2(258, 120), "守望者时刻", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1.0, clampf(run.perfect_flash, 0.0, 1.0)))

# ---------------------------------------------------------------- 约卡

func _covenant_data() -> Array:
	# 系统侧 RunCovenants.draw_data() → [{id,name,rarity,color,text}]；缺失时兼容数组/字典形态
	var c = run.get("covenants")
	if c != null and c.has_method("draw_data"):
		var d = c.draw_data()
		if d is Array:
			return d
	var out: Array = []
	var v = c
	if v is Array:
		for it in v:
			if it is Dictionary:
				out.append(it)
			else:
				out.append({ "id": String(it), "name": String(it), "rarity": 1, "color": "#9FD3C0" })
	elif v is Dictionary:
		var keys: Array = v.keys()
		keys.sort()
		for k in keys:
			out.append({ "id": String(k), "name": String(k), "rarity": 1, "color": "#9FD3C0" })
	return out

func _draw_covenants(f: Font) -> void:
	var cards: Array = _covenant_data()
	if cards.is_empty():
		# 约系统存在但还没抽到：留 2 个暗色占位槽（R05 未持有时系统会 disabled，占位也淡）
		if run.get("covenants") != null:
			for i in range(2):
				var px: float = 6.0 + float(i) * 18.0
				draw_rect(Rect2(px, 56, 16, 16), Color(0.09, 0.09, 0.11, 0.55), true)
				draw_rect(Rect2(px, 56, 16, 16), Color(0.38, 0.38, 0.40, 0.55), false, 1.0)
				draw_string(f, Vector2(px, 68), "约", HORIZONTAL_ALIGNMENT_CENTER, 16, 7, Color(0.45, 0.45, 0.44))
		return
	var n: int = mini(cards.size(), 8)
	for i in range(n):
		var card: Dictionary = cards[i]
		var x: float = 6.0 + float(i) * 18.0
		var y: float = 56.0
		draw_rect(Rect2(x, y, 16, 16), Color(0.10, 0.10, 0.14, 0.85), true)
		var rc: Color = Color(String(card.get("color", "#9FD3C0")))
		draw_rect(Rect2(x, y, 16, 16), rc, false, 1.0)
		var nm: String = String(card.get("name", card.get("id", "?")))
		draw_string(f, Vector2(x, y + 12), nm.substr(0, 1), HORIZONTAL_ALIGNMENT_CENTER, 16, 9, Color(0.92, 0.88, 0.74))
	if cards.size() > 8:
		draw_string(f, Vector2(6.0 + 8.0 * 18.0, 68), "+%d" % (cards.size() - 8), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.62, 0.62, 0.58))

# ---------------------------------------------------------------- 圣物图标

func _relic_ids(st: GameState) -> Array:
	var out: Array = []
	if st.has_method("relic_defs"):
		var defs = st.relic_defs()
		if defs is Array:
			for d in defs:
				if d is Dictionary:
					out.append(String(d.get("id", "")))
				else:
					out.append(String(d))
		if not out.is_empty():
			return out
	var v = run.get("relics")
	if v is Array:
		for it in v:
			if it is Dictionary:
				out.append(String(it.get("id", "")))
			else:
				out.append(String(it))
	if out.is_empty():
		var m = run.get("relic_ids")
		if m is Array:
			for it in m:
				out.append(String(it))
	return out

func _draw_relic_icons(f: Font, st: GameState) -> void:
	var ids: Array = _relic_ids(st)
	if ids.is_empty():
		return
	var n: int = mini(ids.size(), 12)
	draw_string(f, Vector2(6, 322), "圣物", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.52, 0.54, 0.50))
	for i in range(n):
		var id: String = String(ids[i])
		var def: Dictionary = GameData.relic_def(id)
		var x: float = 24.0 + float(i) * 11.0
		draw_rect(Rect2(x, 314, 10, 10), Color(0.10, 0.11, 0.14, 0.85), true)
		draw_rect(Rect2(x, 314, 10, 10), Color(0.72, 0.66, 0.44, 0.9), false, 1.0)
		draw_string(f, Vector2(x, 322), String(def.get("name", id)).substr(0, 1), HORIZONTAL_ALIGNMENT_CENTER, 10, 6, Color(0.94, 0.88, 0.70))

# ---------------------------------------------------------------- 机制状态

func _mechanics_text() -> String:
	var direct = run.get("mechanics_text")
	if direct is String and String(direct) != "":
		return String(direct)
	var m = run.get("mechanics")
	# 系统侧 RunMechanics.hint() 已给出本图机关的一行提示
	if m != null and m.has_method("hint"):
		var h: String = String(m.hint())
		var extra: String = _hazard_short(m)
		if h != "" and extra != "":
			return h + "  ｜  " + extra
		if h != "":
			return h
		if extra != "":
			return extra
	var v = m
	if v == null:
		return ""
	var parts: Array = []
	if v is String:
		return String(v)
	if v is Array:
		for it in v:
			if parts.size() >= 3:
				break
			if it is Dictionary:
				parts.append(_mech_item_text(it))
			elif it is String:
				parts.append(String(it))
	elif v is Dictionary:
		for k in v.keys():
			if parts.size() >= 3:
				break
			var it = v[k]
			var label: String = _mech_label(String(k))
			if it is Dictionary:
				var d: Dictionary = it
				var t: String = _mech_item_text(d)
				parts.append(label if t == "" else "%s %s" % [label, t])
			elif it is String:
				parts.append("%s %s" % [label, String(it)])
			elif it is bool:
				if bool(it):
					parts.append(label)
			elif it is float or it is int:
				parts.append("%s %s" % [label, _num_short(float(it))])
	return "   ·   ".join(parts)

func _mech_label(key: String) -> String:
	match key:
		"lightning", "lightning_zones":
			return "雷击"
		"meteor", "meteor_warning", "meteor_horde":
			return "陨星"
		"wall", "wall_ring":
			return "城墙"
		"glass", "glass_sea":
			return "玻璃海"
		"cooling", "cooldown_band", "dry_creek":
			return "冷却带"
		"flood", "flood_tide":
			return "洪水"
		"plague", "plague_cycle":
			return "瘟疫"
		"darkness", "darkness_lamp":
			return "黑暗"
		"pentecost", "pentecost_rush":
			return "五旬风"
		"belly", "belly_shade":
			return "鱼腹荫"
		"furnace", "furnace_rings":
			return "火窑"
		"temptation", "temptation_choice":
			return "试探"
		"storm", "storm_push":
			return "风暴"
		"quake", "prison_quake":
			return "地震"
		"abyss", "abyss_vents":
			return "深渊"
		"altar", "altar_charge":
			return "祭坛"
		"babel", "babel_confusion":
			return "变乱"
		"sea", "sea_walls":
			return "分海"
		"bitter", "bitter_water":
			return "苦水"
		"burnable", "burnable_field":
			return "枯草"
		"cave", "cave_choke":
			return "洞穴"
		"drought", "drought_fire":
			return "旱火"
		"lamps", "seven_lamps":
			return "七灯"
	return key

func _mech_item_text(d: Dictionary) -> String:
	var nm: String = String(d.get("name", d.get("text", d.get("id", ""))))
	if nm == "":
		return ""
	var rem: float = -1.0
	for k in ["left", "remaining", "t", "timer", "warn", "delay"]:
		if d.has(k) and (d[k] is float or d[k] is int):
			rem = float(d[k])
			break
	if rem >= 0.0:
		return "%s %s" % [nm, _num_short(rem)]
	var cnt = d.get("count", d.get("n", -1))
	if cnt is float or cnt is int:
		return "%s ×%d" % [nm, int(cnt)]
	return nm

func _num_short(v: float) -> String:
	if absf(v) >= 10.0:
		return "%.0f" % v
	return "%.1f" % v

func _draw_mechanics_line(f: Font) -> void:
	if run.over:
		return
	var txt: String = _mechanics_text()
	if txt == "":
		return
	draw_rect(Rect2(150, 340, 320, 13), Color(0.05, 0.05, 0.07, 0.62), true)
	draw_string(f, Vector2(150, 351), txt, HORIZONTAL_ALIGNMENT_CENTER, 320, 8, Color(0.93, 0.78, 0.52, 0.92))

func _boss_phase_text(bdef: Dictionary, frac: float) -> String:
	var phases = bdef.get("phases", [])
	if not (phases is Array) or phases.is_empty():
		return ""
	var left: float = -1.0
	for p in phases:
		if p is Dictionary and p.has("at_hp"):
			left = float(p.get("at_hp", 0.0))
			if frac > left:
				var idx: int = phases.find(p)
				return "第 %d 阶段前 · 技能 %s" % [idx + 1, _phase_skills(p)]
			break
	return "最终阶段"

func _phase_skills(p: Dictionary) -> String:
	var skills = p.get("skills", [])
	var names: Array = []
	if skills is Array:
		for s in skills:
			if s is Dictionary:
				names.append(String(s.get("id", "?")))
	return "/".join(names) if not names.is_empty() else "—"

# ---------------------------------------------------------------- 结算

func _draw_result(f: Font, st: GameState) -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color(0.03, 0.04, 0.07, 0.86), true)
	var head: String = "约柜得胜" if run.won else ("倒在" + String(run.stage.get("name", "战场")))
	draw_string(f, Vector2(0, 106), head, HORIZONTAL_ALIGNMENT_CENTER, 640, 20, Color("#E0B85A") if run.won else Color("#B0424A"))
	draw_string(f, Vector2(0, 136), "存活 %s   击杀 %d   等级 %d" % [_fmt_time(run.elapsed), st.kills, st.level], HORIZONTAL_ALIGNMENT_CENTER, 640, 11, Color("#E8DCC0"))
	var fb: int = 0
	for w in st.weapons:
		if String(w.get("kind", "")) == "fusion":
			fb += 1
	var relic_ids: Array = _relic_ids(st)
	draw_string(f, Vector2(0, 154), "祝圣武器 %d   七印 %d   圣物 %d" % [fb, int(run.get("seal")), relic_ids.size()], HORIZONTAL_ALIGNMENT_CENTER, 640, 9, Color(0.72, 0.70, 0.64))
	_draw_silver_breakdown(f, st)
	var coin: float = 1.0
	var raw_coin = run.get("stage_coin")
	if raw_coin is float or raw_coin is int:
		coin = float(raw_coin)
	var pick: int = int(round(float(_pickup_silver()) * coin))
	var meta_bonus: int = _meta_silver_bonus()
	# run.reward 已含局内拾取×关卡倍率 与 局外银两，这里只做拆分展示，不重复累加
	draw_string(f, Vector2(0, 204), "舍客勒合计  +%d   （局内拾取 %d · 局外 %d）" % [int(run.reward), pick, meta_bonus], HORIZONTAL_ALIGNMENT_CENTER, 640, 12, Color("#E0B85A"))
	_draw_result_achievements(f)
	draw_string(f, Vector2(0, 306), "Esc 再来一局   ·   R 返回营地", HORIZONTAL_ALIGNMENT_CENTER, 640, 10, Color(0.62, 0.60, 0.55))

func _draw_silver_breakdown(f: Font, st: GameState) -> void:
	var sec_part: int = int(run.elapsed) / 8
	var kill_part: int = st.kills / 3
	var win_part: int = 120 if run.won else 0
	var base: int = sec_part + kill_part + win_part
	var seal: int = int(run.get("seal"))
	var tier_mult: float = Meta.seal_mult(seal)
	var coin: float = 1.0
	var raw = run.get("stage_coin")
	if raw is float or raw is int:
		coin = float(raw)
	var base_reward: int = int(round(Meta.reward_for(run.won, st.kills, run.elapsed, seal) * coin))
	var pick_raw: int = _pickup_silver()
	var pick: int = int(round(float(pick_raw) * coin))
	var meta_bonus: int = _meta_silver_bonus()
	draw_string(f, Vector2(0, 182), "银两明细   存活 +%d   击杀 +%d   得胜 +%d   =  %d（×%.2f）" % [sec_part, kill_part, win_part, base, tier_mult * coin], HORIZONTAL_ALIGNMENT_CENTER, 640, 8, Color(0.66, 0.68, 0.62))
	draw_string(f, Vector2(0, 194), "灾变阶 %s ×%.2f   关卡 ×%.2f   结算 +%d   局内拾取 +%d   局外 +%d" % [Meta.tier_name(seal), tier_mult, coin, base_reward, pick, meta_bonus], HORIZONTAL_ALIGNMENT_CENTER, 640, 8, Color(0.62, 0.66, 0.58))

func _result_achievement_entries() -> Array:
	var out: Array = []
	var ar = run.get("achievements")
	if ar != null and ar.has_method("lines"):
		var v = ar.get("newly")
		if v is Array:
			for it in v:
				if it is Dictionary:
					out.append(it)
				else:
					out.append({ "id": String(it), "name": String(it) })
		return out
	for key in ["new_achievements", "achievements_unlocked", "run_achievements"]:
		var v2 = run.get(key)
		if v2 is Array and not v2.is_empty():
			for it in v2:
				if it is Dictionary:
					out.append(it)
				else:
					out.append({ "id": String(it), "name": String(it) })
			break
	return out

func _draw_result_achievements(f: Font) -> void:
	var entries: Array = _result_achievement_entries()
	var relics: Array = []
	for key in ["new_relics", "relics_unlocked"]:
		var v = run.get(key)
		if v is Array and not v.is_empty():
			for it in v:
				if it is Dictionary:
					relics.append(String(it.get("id", "")))
				else:
					relics.append(String(it))
			break
	var y: float = 220.0
	draw_string(f, Vector2(0, y), "成就达成", HORIZONTAL_ALIGNMENT_CENTER, 640, 8, Color(0.58, 0.62, 0.56))
	if entries.is_empty():
		draw_string(f, Vector2(0, y + 12), "本局无新增成就", HORIZONTAL_ALIGNMENT_CENTER, 640, 8, Color(0.48, 0.50, 0.46))
	else:
		for i in range(mini(entries.size(), 3)):
			var e: Dictionary = entries[i]
			var aid: String = String(e.get("id", ""))
			var adef: Dictionary = GameData.achievement_def(aid)
			var nm: String = String(e.get("name", adef.get("name", aid)))
			var rw_def: Dictionary = e.get("reward", adef.get("reward", {}))
			var rw: String = ""
			if not rw_def.is_empty():
				rw = "  " + _reward_dict_text(rw_def)
			draw_string(f, Vector2(0, y + 12 + float(i) * 10.0), "✓ %s%s" % [nm, rw], HORIZONTAL_ALIGNMENT_CENTER, 640, 8, Color(0.85, 0.78, 0.52))
	if not relics.is_empty():
		var names: Array = []
		for rid in relics:
			var rd: Dictionary = GameData.relic_def(String(rid))
			names.append(String(rd.get("name", rid)))
		draw_string(f, Vector2(0, 262), "圣物解锁  " + " · ".join(names), HORIZONTAL_ALIGNMENT_CENTER, 640, 8, Color(0.88, 0.80, 0.50))

func _pickup_silver() -> int:
	var rr = run.get("rewards")
	if rr != null:
		var v = rr.get("silver_run")
		if v is float or v is int:
			return int(v)
	return 0

func _meta_silver_bonus() -> int:
	var rr = run.get("rewards")
	if rr != null:
		var v = rr.get("meta_silver_bonus")
		if v is float or v is int:
			return int(v)
	return 0

func _hazard_short(m) -> String:
	var hs = m.get("hazards")
	if not (hs is Array) or hs.is_empty():
		var flags0 = m.get("flags")
		if flags0 is Dictionary and bool(flags0.get("wall_down", false)):
			return "城墙已塌"
		return ""
	var l: int = 0
	var other: int = 0
	for h in hs:
		if h is Dictionary and String(h.get("tag", "")) == "lightning":
			l += 1
		else:
			other += 1
	var parts: Array = []
	if l > 0:
		parts.append("雷击 %d 处" % l)
	if other > 0:
		parts.append("危险区 %d 处" % other)
	var flags = m.get("flags")
	if flags is Dictionary and bool(flags.get("wall_down", false)):
		parts.append("城墙已塌")
	return " · ".join(parts)

func _reward_dict_text(rw: Dictionary) -> String:
	var parts: Array = []
	var silver: int = int(rw.get("silver", 0))
	if silver > 0:
		parts.append("+%d 舍客勒" % silver)
	var rid: String = String(rw.get("relic", ""))
	if rid != "":
		parts.append("圣物「%s」" % String(GameData.relic_def(rid).get("name", rid)))
	return " · ".join(parts)
