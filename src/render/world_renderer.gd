class_name WorldRenderer
extends Node2D
## 世界渲染层：从模拟数据直接批量绘制，不建场景节点。
## 敌人 / 投射物 / 宝石 / 区域 / 特效全部在这里用 draw_* 一次性画完。

var run: Node = null

const GEM_COLORS := [Color("#7FE0C0"), Color("#F0D890"), Color("#F07A9A")]

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	if run == null or run.state == null:
		return
	_draw_ground()
	_draw_altars()
	_draw_gems()
	_draw_zones()
	_draw_mechanics()
	_draw_enemies()
	_draw_shots()
	_draw_fx()
	_draw_hazard_fx()
	_draw_player()

func _draw_ground() -> void:
	var p: Vector2 = run.player_pos()
	var half: Vector2 = Vector2(460, 300)
	var r: Rect2 = Rect2(p - half, half * 2.0)
	var g: Dictionary = run.stage.get("ground", {})
	var c_base: Color = Color(String(g.get("base", "#2A2419")))
	var c_speck: Color = Color(String(g.get("speckle", "#3A3122")))
	var c_line: Color = c_base.lightened(0.05)
	draw_rect(r, c_base, true)
	# 32px 网格暗纹 + 确定性沙砾
	var x0: int = int(floor(r.position.x / 32.0))
	var y0: int = int(floor(r.position.y / 32.0))
	var x1: int = int(ceil(r.end.x / 32.0))
	var y1: int = int(ceil(r.end.y / 32.0))
	for gx in range(x0, x1):
		for gy in range(y0, y1):
			var h: int = (gx * 73856093) ^ (gy * 19349663)
			if (h & 7) == 0:
				var sx: float = float(gx) * 32.0 + float(h & 31)
				var sy: float = float(gy) * 32.0 + float((h >> 5) & 31)
				draw_rect(Rect2(sx, sy, 2, 2), c_speck, true)
		if (gx & 1) == 0:
			draw_line(Vector2(float(gx) * 32.0, r.position.y), Vector2(float(gx) * 32.0, r.end.y), c_line, 1.0)
	if bool(g.get("rocks", false)):
		# 旷野的石灰岩碎块：确定性散布，不占随机数也不随帧闪烁
		for gx2 in range(x0, x1):
			for gy2 in range(y0, y1):
				var h2: int = (gx2 * 83492791) ^ (gy2 * 2654435761)
				if (h2 & 15) != 3:
					continue
				var rx: float = float(gx2) * 32.0 + float(h2 & 23)
				var ry: float = float(gy2) * 32.0 + float((h2 >> 6) & 23)
				draw_rect(Rect2(rx, ry, 4 + (h2 & 3), 3), c_speck, true)
				draw_line(Vector2(rx, ry + 3), Vector2(rx + 4 + (h2 & 3), ry + 3), c_base.darkened(0.25), 1.0)

func _draw_altars() -> void:
	for a in run.altars:
		var x: float = float(a["x"])
		var y: float = float(a["y"])
		if bool(a.get("used", false)):
			draw_rect(Rect2(x - 9, y - 6, 18, 12), Color("#4A4030"), true)
			continue
		var pulse: float = 0.5 + 0.5 * sin(run.elapsed * 3.0)
		draw_circle(Vector2(x, y), 22.0 + pulse * 4.0, Color(0.88, 0.72, 0.35, 0.12 + pulse * 0.08))
		draw_rect(Rect2(x - 10, y - 7, 20, 14), Color("#6B5A3C"), true)
		draw_rect(Rect2(x - 10, y - 7, 20, 3), Color("#C9A66B"), true)
		draw_circle(Vector2(x, y - 10), 3.0, Color(1.0, 0.55, 0.2, 0.85 + pulse * 0.15))

func _draw_gems() -> void:
	for g in run.gems:
		var c: Color = GEM_COLORS[0]
		if int(g["val"]) >= 4:
			c = GEM_COLORS[1]
		elif int(g["val"]) >= 2:
			c = GEM_COLORS[0]
		draw_rect(Rect2(float(g["x"]) - 1, float(g["y"]) - 1, 3, 3), c, true)

func _draw_zones() -> void:
	for z in run.weapons.zones:
		var c: Color = z["color"]
		var a: float = clampf(float(z["life"]) / 2.6, 0.0, 1.0)
		draw_circle(Vector2(float(z["x"]), float(z["y"])), float(z["r"]), Color(c.r, c.g, c.b, 0.09 * a))
		draw_circle(Vector2(z["x"], z["y"]), float(z["r"]), Color(c.r, c.g, c.b, 0.26 * a), false, 1.0)
		draw_circle(Vector2(z["x"], z["y"]), float(z["r"]) * 0.62, Color(c.r, c.g, c.b, 0.14 * a), false, 1.0)

func _draw_enemies() -> void:
	var e: EnemySim = run.enemies
	var types: Array = e.types
	var pp: Vector2 = run.player_pos()
	for i in range(e.count):
		var t: Dictionary = types[e.typ[i]]
		var base: Color = Color(String(t.get("color", "#8A7F6D")))
		var col: Color = base
		if e.flash[i] > 0.0:
			col = Color(1, 1, 1)
		elif e.burn_t[i] > 0.0:
			col = Color(minf(base.r + 0.35, 1.0), base.g * 0.8, base.b * 0.6)
		var r: float = e.rad[i]
		var x: float = e.px[i]
		var y: float = e.py[i]
		var dark: Color = col.darkened(0.35)
		var light: Color = col.lightened(0.24)
		# 落地投影（一次矩形，不用 transform，省 draw call）
		draw_rect(Rect2(x - r * 0.8, y + r * 0.75, r * 1.6, r * 0.32), Color(0, 0, 0, 0.25), true)
		if e.is_boss(i):
			# BOSS：阶段光环（血量 >66% 暗红、33%-66% 橙、<33% 金红）+ 两圈阶段刻度
			var bfrac: float = clampf(e.hp[i] / maxf(e.max_hp[i], 1.0), 0.0, 1.0)
			var bpulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.004)
			var aura: Color = Color(0.86, 0.32, 0.24, 0.08 + 0.06 * bpulse)
			if bfrac <= 0.33:
				aura = Color(0.96, 0.62, 0.22, 0.12 + 0.10 * bpulse)
			elif bfrac <= 0.66:
				aura = Color(0.92, 0.48, 0.22, 0.10 + 0.08 * bpulse)
			draw_circle(Vector2(x, y), r * (1.5 + 0.10 * bpulse), aura)
			for k in range(2):
				draw_arc(Vector2(x, y), r * (1.25 + 0.22 * float(k)), 0.0, TAU, 24, Color(0.90, 0.72, 0.46, 0.10), 1.0)
			draw_rect(Rect2(x - r, y - r * 0.9, r * 2.0, r * 1.9), col, true)
			draw_rect(Rect2(x - r * 0.7, y - r * 1.7, r * 1.4, r * 0.8), light, true)
			draw_rect(Rect2(x - r, y + r * 0.4, r * 2.0, r * 0.6), dark, true)
			draw_rect(Rect2(x - 1, y - r * 1.7, 2, r * 0.8), Color("#B33A2A"), true)
			continue
		var beh: String = String(t.get("behavior", "chase"))
		match beh:
			"ranged":
				draw_rect(Rect2(x - r * 0.8, y - r * 0.7, r * 1.6, r * 1.5), col, true)
				draw_rect(Rect2(x - r * 0.55, y - r * 1.25, r * 1.1, r * 0.55), light, true)
				draw_arc(Vector2(x, y), r * 1.25, -0.9, 0.9, 8, light, 1.0)
			"dive":
				if r >= 1.0 and is_finite(x) and is_finite(y):
					# 用两个三角形代替四边形：Godot 的 draw_colored_polygon 在退化四边形上会 triangulation failed
					var top := Vector2(x, y - r)
					var right := Vector2(x + r, y)
					var bot := Vector2(x, y + r * 0.8)
					var left := Vector2(x - r, y)
					var tri_a := PackedVector2Array([top, right, bot])
					var tri_b := PackedVector2Array([top, bot, left])
					draw_primitive(tri_a, PackedColorArray([col, col, col]), PackedVector2Array())
					draw_primitive(tri_b, PackedColorArray([col, col, col]), PackedVector2Array())
				draw_line(Vector2(x - r * 1.6, y - r * 0.3), Vector2(x - r * 0.2, y), Color(col.r, col.g, col.b, 0.55), 1.0)
				draw_line(Vector2(x + r * 1.6, y - r * 0.3), Vector2(x + r * 0.2, y), Color(col.r, col.g, col.b, 0.55), 1.0)
			"charger":
				draw_rect(Rect2(x - r, y - r * 0.7, r * 2.0, r * 1.4), col, true)
				draw_rect(Rect2(x - r * 0.5, y - r * 1.3, r, r * 0.6), light, true)
				draw_line(Vector2(x - r, y - r * 1.1), Vector2(x - r * 1.5, y - r * 1.8), light, 1.0)
				draw_line(Vector2(x + r, y - r * 1.1), Vector2(x + r * 1.5, y - r * 1.8), light, 1.0)
			_:
				draw_rect(Rect2(x - r * 0.85, y - r * 0.85, r * 1.7, r * 1.7), col, true)
				draw_rect(Rect2(x - r * 0.85, y + r * 0.3, r * 1.7, r * 0.55), dark, true)
				draw_rect(Rect2(x - r * 0.58, y - r * 1.35, r * 1.16, r * 0.6), light, true)
				var dir: Vector2 = (pp - Vector2(x, y)).normalized()
				draw_line(Vector2(x, y) + dir * r, Vector2(x, y) + dir * r * 2.4, light, 1.0)
		# 新怪物的属性外观分型：飞行 / 披甲 / 召唤 / 自爆（数据有字段才画）
		if bool(t.get("flying", false)):
			draw_line(Vector2(x - r, y - r * 0.2), Vector2(x - r * 2.1, y - r * 0.7), Color(col.r, col.g, col.b, 0.55), 1.0)
			draw_line(Vector2(x + r, y - r * 0.2), Vector2(x + r * 2.1, y - r * 0.7), Color(col.r, col.g, col.b, 0.55), 1.0)
		if bool(t.get("armored", false)):
			draw_arc(Vector2(x, y), r * 1.15, -2.6, -0.5, 8, Color(0.72, 0.74, 0.80, 0.65), 1.5)
		if bool(t.get("summoner", false)):
			for k in range(3):
				var ang: float = run.elapsed * 1.6 + TAU * float(k) / 3.0
				draw_circle(Vector2(x + cos(ang) * r * 1.5, y + sin(ang) * r * 0.8), 1.4, Color(0.72, 0.55, 0.90, 0.85))
		if bool(t.get("exploder", false)):
			var ep: float = 0.5 + 0.5 * sin(run.elapsed * 8.0)
			draw_circle(Vector2(x, y), r * (1.15 + 0.2 * ep), Color(0.95, 0.55, 0.20, 0.16 + 0.14 * ep), false, 1.0)
		if bool(t.get("elite", false)):
			var ac: Color = _affix_color(t)
			draw_rect(Rect2(x - r - 2, y - r - 2, (r + 2) * 2.0, (r + 2) * 2.0), Color(ac.r, ac.g, ac.b, 0.62), false, 1.0)
			# 精英菱形标记
			var dm: float = r + 6.0
			draw_primitive(PackedVector2Array([Vector2(x, y - dm - 3.0), Vector2(x + 3.0, y - dm), Vector2(x, y - dm + 3.0), Vector2(x - 3.0, y - dm)]), PackedColorArray([ac, ac, ac, ac]), PackedVector2Array())
		if e.blind_t[i] > 0.0:
			draw_circle(Vector2(x, y - r * 1.6), 1.5, Color(0.9, 0.9, 1.0, 0.8))

func _draw_shots() -> void:
	var s: ProjectileSim = run.shots
	for i in range(s.count):
		var c: Color = Color("#C9A66B")
		match s.color[i]:
			ProjectileSim.COL_SOUND: c = Color("#E0B85A")
			ProjectileSim.COL_FIRE: c = Color("#E0731A")
			ProjectileSim.COL_WATER: c = Color("#6FA8C4")
			ProjectileSim.COL_ENEMY: c = Color("#D46A5A")
			_: c = Color("#C9A66B")
		var sz: float = maxf(s.size[i], 1.6)
		draw_rect(Rect2(s.px[i] - sz * 0.5, s.py[i] - sz * 0.5, sz, sz), c, true)

func _draw_fx() -> void:
	for f in run.active_fx:
		var life: float = float(f["life"])
		var a: float = clampf(life / 0.4, 0.0, 1.0)
		var c: Color = f.get("color", Color("#E0B85A"))
		match String(f["kind"]):
			"arc":
				draw_arc(Vector2(float(f["x"]), float(f["y"])), float(f["r"]) * 0.9, float(f["ang"]) - float(f["arc"]) * 0.5, float(f["ang"]) + float(f["arc"]) * 0.5, 10, Color(c.r, c.g, c.b, 0.75 * a), 2.0)
			"nova":
				var rr: float = float(f["r"]) * (1.0 - a * 0.85)
				draw_circle(Vector2(float(f["x"]), float(f["y"])), rr, Color(c.r, c.g, c.b, 0.35 * a), false, 3.0)
			"spark":
				draw_circle(Vector2(float(f["x"]), float(f["y"])), float(f.get("r", 3.0)), Color(1, 1, 1, 0.6 * a))
			"pop":
				var pr: float = float(f.get("r", 5.0)) * (1.6 - a)
				draw_circle(Vector2(float(f["x"]), float(f["y"])), pr, Color(c.r, c.g, c.b, 0.55 * a), false, 1.5)

func _draw_player() -> void:
	var p: Vector2 = run.player_pos()
	# 信心跨步的残影
	if run.dash_iframe > 0.0:
		draw_circle(p, 9.0, Color(0.75, 0.85, 1.0, 0.25))
	# 大卫：羊皮短袍 + 投石索，脚下有影子，面朝瞄准/移动方向
	draw_ellipse_shadow(p.x, p.y + 6, 7.0, 2.6)
	var face: Vector2 = run.aim_dir if run.aim_dir.length() > 0.1 else Vector2(0, 1)
	draw_rect(Rect2(p.x - 5, p.y - 5, 10, 12), Color("#E8DCC0"), true)
	draw_rect(Rect2(p.x - 5, p.y + 2, 10, 3), Color("#B99460"), true)
	draw_rect(Rect2(p.x - 4, p.y - 9, 8, 5), Color("#D8B98A"), true)
	draw_rect(Rect2(p.x - 4, p.y - 9, 8, 2), Color("#6B4A2A"), true)
	draw_circle(Vector2(p.x - 1.5, p.y - 6.5), 0.9, Color("#2E2418"))
	draw_circle(Vector2(p.x + 1.5, p.y - 6.5), 0.9, Color("#2E2418"))
	# 投石索：朝面向方向甩出的一小段弧
	draw_arc(p + face * 3.0, 7.0, face.angle() - 1.1, face.angle() - 0.2, 6, Color("#C9A66B"), 1.4)
	draw_circle(p + face * 9.5, 1.4, Color("#F0D890"))
	# 环绕武器
	for entry in run.state.weapons:
		if run.state.entry_behavior(entry) != "orbit":
			continue
		for pt in run.weapons.orbit_points(entry, p):
			var c: Color = run.state.entry_color(entry)
			draw_circle(Vector2(float(pt["x"]), float(pt["y"])), float(pt["size"]) * 0.55, Color(c.r, c.g, c.b, 0.9))
			draw_circle(Vector2(float(pt["x"]), float(pt["y"])), float(pt["size"]) * 0.9, Color(c.r, c.g, c.b, 0.2))


func draw_ellipse_shadow(x: float, y: float, rx: float, ry: float) -> void:
	draw_set_transform(Vector2(x, y), 0.0, Vector2(1.0, ry / maxf(rx, 0.001)))
	draw_circle(Vector2.ZERO, rx, Color(0, 0, 0, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ================================================================ V2 机制可视化
# 数据由局内系统写入（字段名见 docs/V2-接口需求-ui.md），渲染层只读、不推断玩法状态。
# 统一约定：每个危险区是 Dictionary，kind 取 lightning / meteor / wall / glass / band，
# 位置 x,y（缺省用玩家位置），半径 r（缺省 30），倒计时 left/t（秒），预警窗 warn（秒）。

func _zf(d: Dictionary, key: String, def: float) -> float:
	var v = d.get(key, null)
	if v is float or v is int:
		return float(v)
	return def

func _z_left(z: Dictionary) -> float:
	for k in ["left", "t", "remaining", "timer", "delay"]:
		if z.has(k):
			return _zf(z, k, -1.0)
	return -1.0

func _zpos(z: Dictionary) -> Vector2:
	var p: Vector2 = run.player_pos()
	return Vector2(_zf(z, "x", p.x), _zf(z, "y", p.y))

func _hazard_list() -> Array:
	var out: Array = []
	for key in ["hazards", "mechanics_zones", "hazard_zones"]:
		var v = run.get(key)
		if v is Array and not v.is_empty():
			for it in v:
				if it is Dictionary:
					out.append(it)
			return out
	var mech = run.get("mechanics")
	if mech != null:
		for key in ["zones", "hazards"]:
			var v2 = mech.get(key)
			if v2 is Array:
				for it in v2:
					if it is Dictionary:
						out.append(it)
	return out

func _affix_color(t: Dictionary) -> Color:
	var s: String = String(t.get("elite_affix", "")) + String(t.get("name", "")) + String(t.get("id", ""))
	if s.contains("火") or s.contains("焰") or s.contains("灼"):
		return Color(0.95, 0.48, 0.24)
	if s.contains("毒") or s.contains("瘟"):
		return Color(0.55, 0.88, 0.38)
	if s.contains("雷") or s.contains("电"):
		return Color(0.92, 0.86, 0.35)
	if s.contains("冰") or s.contains("霜") or s.contains("寒"):
		return Color(0.55, 0.82, 0.98)
	if s.contains("甲") or s.contains("护") or s.contains("铁"):
		return Color(0.72, 0.76, 0.84)
	if s.contains("召唤") or s.contains("魂") or s.contains("灵"):
		return Color(0.76, 0.58, 0.95)
	if s.contains("疾") or s.contains("迅") or s.contains("风"):
		return Color(0.55, 0.92, 0.78)
	if s.contains("圣") or s.contains("光"):
		return Color(0.96, 0.90, 0.60)
	return Color(0.85, 0.30, 0.25)

func _draw_mechanics() -> void:
	var mech = run.get("mechanics")
	# 优先消费系统侧 RunMechanics.draw_data()：kind = band/circle/wall/prop/hazard/pickup/overlay/vision
	if mech != null and mech.has_method("draw_data"):
		var entries = mech.draw_data()
		if entries is Array:
			for e in entries:
				if e is Dictionary:
					_draw_mech_entry(e, mech)
			return
	for z in _hazard_list():
		var kind: String = String(z.get("kind", z.get("type", "")))
		match kind:
			"lightning", "thunder":
				_draw_lightning(z)
			"meteor", "meteor_fire":
				_draw_meteor(z)
			"wall", "wall_ring":
				_draw_wall(z)
			"glass", "glass_sea":
				_draw_glass(z)
			"band", "cooldown_band", "cooling":
				_draw_band(z)
			_:
				_draw_warning(z)
	# 也接受顶层单值字段，方便系统侧不经数组直接挂一个
	var wall = run.get("wall_ring")
	if wall is Dictionary:
		_draw_wall(wall)
	var glass = run.get("glass_sea")
	if glass is Dictionary:
		_draw_glass(glass)
	var mw = run.get("meteor_warning")
	if mw is Dictionary:
		_draw_meteor(mw)
	elif mw is Array:
		for it in mw:
			if it is Dictionary:
				_draw_meteor(it)

func _draw_mech_entry(e: Dictionary, mech) -> void:
	var kind: String = String(e.get("kind", ""))
	var mid: String = String(mech.get("id")) if mech != null else ""
	var p: Vector2 = Vector2(_zf(e, "x", 0.0), _zf(e, "y", 0.0))
	match kind:
		"band":
			_draw_band(e)
		"overlay":
			var oc := Color(String(e.get("color", "#8FC8E0")))
			var oa: float = clampf(_zf(e, "alpha", 0.10), 0.0, 0.6)
			draw_rect(Rect2(-20, -20, 700, 400), Color(oc.r, oc.g, oc.b, oa), true)
		"wall":
			_draw_sea_wall(p, e)
		"hazard":
			var prog: float = clampf(_zf(e, "progress", 0.0), 0.0, 1.0)
			var r: float = maxf(_zf(e, "r", 30.0), 8.0)
			var fake := { "x": p.x, "y": p.y, "r": r, "warn": 1.5, "left": (1.0 - prog) * 1.5 }
			if mid == "meteor_horde" or mid == "meteor":
				_draw_meteor(fake)
			elif mid in ["lightning_zones", "furnace_rings", "drought_fire", "abyss_vents", "plague_cycle"]:
				_draw_lightning(fake)
			else:
				_draw_warning(fake)
		"pickup":
			_draw_pickup_mark(p, e)
		"prop":
			_draw_prop(p, e)
		"circle":
			_draw_mech_circle(p, e, mech)
		"vision":
			pass
		_:
			_draw_warning({ "x": p.x, "y": p.y, "r": _zf(e, "r", 30.0) })

func _draw_mech_circle(p: Vector2, e: Dictionary, mech) -> void:
	var col := Color(String(e.get("color", "#C8D0D8")))
	var a: float = clampf(_zf(e, "alpha", 0.18), 0.0, 0.8)
	var r: float = maxf(_zf(e, "r", 20.0), 4.0)
	if String(e.get("color", "")).to_upper() == "#8A8378" and r >= 80.0:
		var coll: float = 0.0
		if mech != null:
			var flags = mech.get("flags")
			if flags is Dictionary and bool(flags.get("wall_down", false)):
				coll = 1.0
		_draw_wall({ "x": p.x, "y": p.y, "r": r, "collapse": coll })
		return
	draw_circle(p, r, Color(col.r, col.g, col.b, a), true)
	draw_circle(p, r, Color(col.r, col.g, col.b, minf(0.55, a * 2.6)), false, 1.2)
	var label: String = String(e.get("label", ""))
	if label != "":
		var f: Font = ThemeDB.fallback_font
		draw_string(f, p + Vector2(-r, -r - 3.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(col.r, col.g, col.b, 0.75))

func _draw_sea_wall(p: Vector2, e: Dictionary) -> void:
	var h: float = maxf(_zf(e, "h", 96.0), 8.0)
	var w: float = 12.0
	var col := Color(String(e.get("color", "#4F86B8")))
	draw_rect(Rect2(p.x - w * 0.5, p.y - h * 0.5, w, h), Color(col.r, col.g, col.b, 0.30), true)
	draw_rect(Rect2(p.x - w * 0.5, p.y - h * 0.5, w, h), Color(col.r, col.g, col.b, 0.80), false, 1.5)
	for i in range(int(h / 12.0)):
		var yy: float = p.y - h * 0.5 + 6.0 + float(i) * 12.0
		var wob: float = sin(run.elapsed * 3.0 + yy * 0.05) * 3.0
		draw_line(Vector2(p.x - w * 0.5, yy), Vector2(p.x + w * 0.5 + wob, yy), Color(0.80, 0.94, 1.0, 0.45), 1.0)

func _draw_pickup_mark(p: Vector2, e: Dictionary) -> void:
	var col := Color(String(e.get("color", "#F3E3A8")))
	var r: float = maxf(_zf(e, "r", 8.0), 3.0)
	var pulse: float = 0.5 + 0.5 * sin(run.elapsed * 4.0 + p.x * 0.1)
	draw_circle(p, r + 2.0 + pulse * 3.0, Color(col.r, col.g, col.b, 0.10), true)
	draw_circle(p, r * 0.55, Color(col.r, col.g, col.b, 0.85), true)
	var d: float = r * 1.2
	draw_polyline(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)]), Color(col.r, col.g, col.b, 0.55), 1.0)

func _draw_prop(p: Vector2, e: Dictionary) -> void:
	var col := Color(String(e.get("color", "#C8B48A")))
	var r: float = maxf(_zf(e, "r", 10.0), 3.0)
	var label: String = String(e.get("label", ""))
	draw_ellipse_shadow(p.x, p.y + r * 0.55, r * 0.7, r * 0.24)
	match label:
		"torch", "campfire":
			draw_rect(Rect2(p.x - 1.5, p.y - r * 0.2, 3.0, r * 0.8), Color(0.35, 0.28, 0.20), true)
			var flick: float = 0.6 + 0.4 * sin(run.elapsed * 9.0 + p.x)
			draw_circle(p + Vector2(0, -r * 0.55), r * 0.45 * flick, Color(0.98, 0.62, 0.22, 0.80))
			draw_circle(p + Vector2(0, -r * 0.55), r * 1.0 * flick, Color(0.98, 0.62, 0.22, 0.16))
		"pillar":
			draw_rect(Rect2(p.x - r * 0.35, p.y - r * 1.6, r * 0.7, r * 1.9), Color(col.r, col.g, col.b, 0.50), true)
			draw_rect(Rect2(p.x - r * 0.55, p.y - r * 1.8, r * 1.1, r * 0.35), Color(col.r, col.g, col.b, 0.70), true)
		"snake":
			var pts := PackedVector2Array()
			for i in range(7):
				pts.append(p + Vector2((float(i) - 3.0) * r * 0.35, sin(run.elapsed * 4.0 + float(i) * 0.9) * r * 0.3))
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.85), 2.0)
			draw_circle(pts[pts.size() - 1], r * 0.16, Color(0.95, 0.85, 0.35, 0.90))
		"door":
			draw_rect(Rect2(p.x - r * 0.6, p.y - r * 1.2, r * 1.2, r * 1.4), Color(col.r, col.g, col.b, 0.30), true)
			draw_rect(Rect2(p.x - r * 0.6, p.y - r * 1.2, r * 1.2, r * 1.4), Color(col.r, col.g, col.b, 0.80), false, 1.5)
			draw_circle(p + Vector2(0, -r * 0.45), r * 0.25, Color(0.98, 0.90, 0.60, 0.30))
		"lantern":
			draw_rect(Rect2(p.x - r * 0.2, p.y - r * 1.3, r * 0.4, r * 0.6), Color(0.35, 0.30, 0.24), true)
			draw_circle(p, r * 0.55, Color(0.98, 0.86, 0.48, 0.28))
			draw_circle(p, r * 0.30, Color(0.98, 0.90, 0.62, 0.85))
		"stone", "bread":
			draw_circle(p, r * 0.6, Color(col.r, col.g, col.b, 0.50))
			draw_circle(p, r * 0.6, Color(col.r, col.g, col.b, 0.85), false, 1.0)
		_:
			draw_rect(Rect2(p.x - r * 0.4, p.y - r * 0.4, r * 0.8, r * 0.8), Color(col.r, col.g, col.b, 0.55), true)
			draw_rect(Rect2(p.x - r * 0.4, p.y - r * 0.4, r * 0.8, r * 0.8), Color(col.r, col.g, col.b, 0.85), false, 1.0)

func _draw_warning(z: Dictionary) -> void:
	var p: Vector2 = _zpos(z)
	var r: float = maxf(_zf(z, "r", 30.0), 6.0)
	var left: float = _z_left(z)
	var warn: float = _zf(z, "warn", -1.0)
	var frac: float = 1.0
	if warn > 0.05 and left >= 0.0:
		frac = clampf(1.0 - left / warn, 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(run.elapsed * 7.0)
	draw_circle(p, r, Color(0.82, 0.22, 0.18, 0.10 + 0.10 * pulse), true)
	draw_circle(p, r, Color(0.94, 0.36, 0.28, 0.55), false, 1.5)
	if warn > 0.05:
		draw_arc(p, r - 1.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 28, Color(0.98, 0.66, 0.40, 0.85), 2.0)
	draw_circle(p, 2.0 + pulse * 1.6, Color(0.98, 0.58, 0.42, 0.75))

func _draw_lightning(z: Dictionary) -> void:
	var p: Vector2 = _zpos(z)
	var r: float = maxf(_zf(z, "r", 48.0), 10.0)
	var left: float = _z_left(z)
	var warn: float = maxf(_zf(z, "warn", 1.5), 0.1)
	var frac: float = clampf(1.0 - maxf(left, 0.0) / warn, 0.0, 1.0)
	draw_circle(p, r, Color(0.86, 0.82, 0.30, 0.07 + 0.10 * frac), true)
	draw_circle(p, r, Color(0.96, 0.90, 0.45, 0.65), false, 1.5)
	draw_arc(p, r - 2.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 30, Color(1.0, 0.95, 0.55, 0.9), 2.0)
	for k in range(3):
		var a: float = run.elapsed * 2.4 + TAU * float(k) / 3.0
		draw_line(p, p + Vector2(cos(a), sin(a)) * (r * 0.55), Color(0.95, 0.90, 0.50, 0.30), 1.0)
	if _z_is_struck(z, left):
		var pts := PackedVector2Array()
		for k in range(7):
			var yy: float = p.y - 110.0 + float(k) * 16.0
			var xx: float = p.x + sin(float(k) * 2.7 + p.x * 0.05) * 8.0
			pts.append(Vector2(xx, yy))
		draw_polyline(pts, Color(1.0, 0.98, 0.82, 0.95), 2.2)
		draw_circle(p, r * 0.75, Color(1.0, 0.96, 0.70, 0.35), true)
		draw_circle(p, r, Color(1.0, 0.98, 0.85, 0.9), false, 2.0)

func _draw_meteor(z: Dictionary) -> void:
	var p: Vector2 = _zpos(z)
	var r: float = maxf(_zf(z, "r", 40.0), 10.0)
	var left: float = _z_left(z)
	var warn: float = maxf(_zf(z, "warn", 1.5), 0.1)
	var frac: float = clampf(1.0 - maxf(left, 0.0) / warn, 0.0, 1.0)
	var hit: bool = left <= 0.0 or bool(z.get("impact", false))
	var hot: Color = Color(0.98, 0.52, 0.18) if not hit else Color(1.0, 0.86, 0.45)
	draw_circle(p, r, Color(hot.r, hot.g, hot.b, 0.10 + 0.12 * frac), true)
	draw_circle(p, r, Color(hot.r, hot.g, hot.b, 0.70), false, 1.5)
	# 旋转瞄准环
	var spin: float = run.elapsed * 2.0
	for k in range(4):
		var a: float = spin + TAU * float(k) / 4.0
		draw_line(p + Vector2(cos(a), sin(a)) * (r * 0.55), p + Vector2(cos(a), sin(a)) * r, Color(hot.r, hot.g, hot.b, 0.55), 1.2)
	draw_line(p + Vector2(-4, 0), p + Vector2(4, 0), Color(1.0, 0.8, 0.5, 0.7), 1.0)
	draw_line(p + Vector2(0, -4), p + Vector2(0, 4), Color(1.0, 0.8, 0.5, 0.7), 1.0)
	# 划落的陨星轨迹（预警时从右上角朝落点）
	var from: Vector2 = p + Vector2(r * 2.2, -r * 3.2)
	draw_line(from, p, Color(hot.r, hot.g, hot.b, 0.20 + 0.25 * frac), 2.0)
	draw_circle(from, 3.0 + 2.0 * frac, Color(hot.r, hot.g, hot.b, 0.65))
	if hit:
		draw_circle(p, r * 1.15, Color(1.0, 0.55, 0.20, 0.30), true)
		for k in range(6):
			var a2: float = TAU * float(k) / 6.0 + 0.3
			draw_line(p, p + Vector2(cos(a2), sin(a2)) * (r * 1.3), Color(1.0, 0.62, 0.25, 0.45), 1.5)

func _draw_wall(z: Dictionary) -> void:
	var p: Vector2 = _zpos(z)
	var r: float = maxf(_zf(z, "r", 160.0), 12.0)
	var coll: float = clampf(_zf(z, "collapse", 0.0), 0.0, 1.0)
	var stone: Color = Color(0.66, 0.60, 0.48, 0.55 + 0.3 * coll)
	if z.has("w") or z.has("h"):
		var w: float = _zf(z, "w", 64.0)
		var h: float = _zf(z, "h", 22.0)
		var rr: Rect2 = Rect2(p.x - w * 0.5, p.y - h * 0.5, w, h)
		draw_rect(rr, Color(0.45, 0.40, 0.30, 0.35), true)
		draw_rect(rr, stone, false, 3.0)
		for i in range(int(w / 8.0)):
			draw_line(Vector2(rr.position.x + 4.0 + float(i) * 8.0, rr.position.y), Vector2(rr.position.x + 4.0 + float(i) * 8.0, rr.position.y - 3.0), stone, 1.0)
		return
	# 圆形内城墙：三圈石带 + 垛口
	for k in range(3):
		draw_circle(p, r + float(k) * 1.6, Color(stone.r, stone.g, stone.b, stone.a * (1.0 - float(k) * 0.25)), false, 1.6)
	var teeth: int = 48
	for i in range(teeth):
		if i % 2 != 0:
			continue
		var a: float = TAU * float(i) / float(teeth)
		var d: Vector2 = Vector2(cos(a), sin(a))
		draw_line(p + d * (r - 2.0), p + d * (r - 6.0), stone, 1.5)
	if coll > 0.01:
		# 震塌：缺口与尘裂
		var gaps: int = int(round(coll * 5.0))
		for g in range(gaps):
			var ang: float = TAU * float(g) / maxf(float(gaps), 1.0) + 0.4
			var d2: Vector2 = Vector2(cos(ang), sin(ang))
			draw_line(p + d2 * (r - 10.0), p + d2 * (r + 14.0), Color(0.95, 0.82, 0.55, 0.55), 2.0)
			draw_circle(p + d2 * (r + 10.0), 4.0 + 6.0 * coll, Color(0.80, 0.70, 0.52, 0.20), true)

func _draw_glass(z: Dictionary) -> void:
	var active: bool = bool(z.get("active", true))
	if not active:
		return
	var p: Vector2 = _zpos(z)
	var r: float = maxf(_zf(z, "r", 520.0), 40.0)
	var prog: float = clampf(_zf(z, "progress", 1.0), 0.0, 1.0)
	var base := Color(0.52, 0.80, 0.88, 0.10 + 0.06 * prog)
	draw_circle(p, r, base, true)
	draw_circle(p, r, Color(0.72, 0.92, 0.96, 0.35), false, 1.5)
	# 掺火：玻璃裂纹里透出的暖光
	for i in range(14):
		var a: float = TAU * float(i) / 14.0 + 0.15
		var d: Vector2 = Vector2(cos(a), sin(a))
		draw_line(p + d * (r * 0.10), p + d * (r * 0.95), Color(0.70, 0.92, 0.96, 0.10 + 0.08 * prog), 1.0)
	for i in range(6):
		var a2: float = TAU * float(i) / 6.0 + run.elapsed * 0.15
		var d2: Vector2 = Vector2(cos(a2), sin(a2))
		var spark: float = 0.5 + 0.5 * sin(run.elapsed * 3.0 + float(i))
		draw_circle(p + d2 * (r * (0.35 + 0.1 * float(i % 3))), 1.2 + spark * 1.2, Color(1.0, 0.55, 0.22, 0.35 + 0.3 * spark))
	# 圣所光柱：z 里带 pillar 时画一道自上而下的光
	if bool(z.get("pillar", false)):
		var pw: float = maxf(r * 0.12, 10.0)
		draw_rect(Rect2(p.x - pw * 0.5, p.y - 240.0, pw, 240.0), Color(0.95, 0.90, 0.62, 0.10), true)
		draw_rect(Rect2(p.x - pw * 0.5, p.y - 240.0, pw, 240.0), Color(0.95, 0.90, 0.62, 0.18), false, 1.0)

func _draw_band(z: Dictionary) -> void:
	var p: Vector2 = _zpos(z)
	var frac: float = clampf(_zf(z, "frac", 0.0), 0.0, 1.0)
	var base := Color(String(z.get("color", "#DCAE62")))
	var alpha: float = clampf(_zf(z, "alpha", 0.16), 0.02, 0.7)
	var warm := Color(base.r, base.g, base.b, alpha)
	if z.has("w") or z.has("h"):
		var w: float = _zf(z, "w", 80.0)
		var h: float = _zf(z, "h", 16.0)
		var rr: Rect2 = Rect2(p.x - w * 0.5, p.y - h * 0.5, w, h)
		draw_rect(rr, warm, true)
		draw_rect(rr, Color(0.92, 0.78, 0.46, 0.55), false, 1.0)
		if frac > 0.0:
			draw_rect(Rect2(rr.position.x, rr.position.y, rr.size.x * frac, 2.0), Color(0.98, 0.88, 0.55, 0.9), true)
		return
	var r: float = maxf(_zf(z, "r", 150.0), 12.0)
	var width: float = maxf(_zf(z, "width", 7.0), 2.0)
	draw_arc(p, r, 0.0, TAU, 48, warm, width)
	draw_arc(p, r + width * 0.6, 0.0, TAU, 48, Color(0.92, 0.78, 0.46, 0.32), 1.0)
	if frac > 0.0:
		draw_arc(p, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 40, Color(0.98, 0.86, 0.52, 0.85), width + 1.0)

func _z_is_struck(z: Dictionary, left: float) -> bool:
	if bool(z.get("struck", false)) or bool(z.get("strike", false)):
		return true
	return left <= 0.0

func _draw_hazard_fx() -> void:
	# 命中瞬间的加色闪光层（画在敌人与弹幕之上，不遮挡 HUD）
	for z in _hazard_list():
		var kind: String = String(z.get("kind", z.get("type", "")))
		var flash: float = _zf(z, "flash", 0.0)
		var hit: bool = flash > 0.01 or bool(z.get("impact", false)) or bool(z.get("struck", false))
		if not hit:
			continue
		var p: Vector2 = _zpos(z)
		var r: float = maxf(_zf(z, "r", 30.0), 8.0)
		var k: float = clampf(flash, 0.0, 1.0) if flash > 0.01 else 0.8
		match kind:
			"lightning", "thunder":
				draw_circle(p, r * (0.8 + 0.5 * k), Color(1.0, 0.97, 0.72, 0.18 * k), true)
			"meteor", "meteor_fire":
				draw_circle(p, r * (0.9 + 0.6 * k), Color(1.0, 0.52, 0.16, 0.20 * k), true)
			"wall", "wall_ring":
				draw_circle(p, r + 8.0, Color(0.92, 0.82, 0.60, 0.10 * k), false, 3.0)
			_:
				draw_circle(p, r * (0.9 + 0.3 * k), Color(1.0, 0.60, 0.30, 0.12 * k), true)

