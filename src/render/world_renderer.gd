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
	_draw_enemies()
	_draw_shots()
	_draw_fx()
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
		if bool(t.get("elite", false)):
			draw_rect(Rect2(x - r - 2, y - r - 2, (r + 2) * 2.0, (r + 2) * 2.0), Color(0.85, 0.3, 0.25, 0.55), false, 1.0)
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
