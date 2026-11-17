class_name WeaponRunner
extends RefCounted
## 武器执行器：把「行为原子 + 数据参数」跑成实际攻击。
## 五类原子：line_projectile / arc_melee / orbit / zone / homing。
## 祝圣武器与成全武器只是同一套原子的参数组合 + modifier，不新增代码路径。

var state: GameState
var enemies: EnemySim
var shots: ProjectileSim

var timers: PackedFloat32Array = PackedFloat32Array()
var orbit_angle: float = 0.0
var zones: Array = []          # {x, y, r, dmg, dps, status, life, tick_t, tick}
var fx: Array = []             # {kind, x, y, r, ang, arc, life, color} 供渲染层消费
var manual_aim: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var heal_pending: float = 0.0   # 治疗类区域（金香坛）累积的治疗量，由 run 每帧取走
var pending: Array = []         # 延时复奏（锡安诗篇 echo_blade）

func setup(s: GameState, e: EnemySim, p: ProjectileSim) -> void:
	state = s
	enemies = e
	shots = p
	timers.resize(state.weapons.size())
	for i in range(timers.size()):
		timers[i] = 0.0

func _sync() -> void:
	if timers.size() != state.weapons.size():
		timers.resize(state.weapons.size())

func drain_fx() -> Array:
	var out: Array = fx
	fx = []
	return out

# ---------------------------------------------------------------- 每帧

func tick(delta: float, ppos: Vector2, aim_dir: Vector2) -> void:
	_sync()
	manual_aim = aim_dir.length_squared() > 0.001
	orbit_angle += delta * 2.3

	for i in range(state.weapons.size()):
		var entry: Dictionary = state.weapons[i]
		var beh: String = state.entry_behavior(entry)
		var params: Dictionary = state.resolved_params(entry)
		if beh == "orbit":
			_tick_orbit(entry, params, ppos, delta)
			continue
		timers[i] -= delta
		if timers[i] <= 0.0:
			var cd: float = float(params.get("cooldown", 1.0)) * float(state.stats.get("cooldown_mult", 1.0))
			if bool(entry.get("ascended", false)):
				cd *= 0.82
			timers[i] = maxf(cd, 0.08)
			_fire(entry, beh, params, ppos, aim_dir)

	_tick_zones(delta)
	_tick_pending(delta)

func _pick_target(ppos: Vector2, rng: float) -> int:
	var n: int = enemies.query(ppos.x, ppos.y, rng)
	var best: int = -1
	var best_d: float = 1e18
	for k in range(n):
		var j: int = enemies.query_buf[k]
		var dx: float = enemies.px[j] - ppos.x
		var dy: float = enemies.py[j] - ppos.y
		var d2: float = dx * dx + dy * dy
		if d2 < best_d:
			best_d = d2
			best = j
	return best

func _damage_of(params: Dictionary) -> float:
	return float(params.get("damage", 1.0)) * float(state.stats.get("damage_mult", 1.0))

func _roll_crit() -> float:
	var c: float = float(state.stats.get("crit_chance", 0.05))
	if rng.randf() < c:
		var mult: float = float(state.stats.get("crit_mult", 1.6))
		if manual_aim:
			mult *= float(state.perf("aim_crit_mult", 1.0))
		return mult
	return 1.0

func _fire(entry: Dictionary, beh: String, params: Dictionary, ppos: Vector2, aim_dir: Vector2) -> void:
	var mod: String = String(state.entry_modifier(entry))
	if bool(entry.get("ascended", false)):
		params = _ascend_params(params)
	var status_name: String = state.entry_status(entry)
	var status_code: int = shots.status_code(status_name)
	var dot_mult: float = float(state.stats.get("dot_mult", 1.0))
	var area: float = float(state.stats.get("area_mult", 1.0))
	var kb_mult: float = float(state.stats.get("knockback_mult", 1.0))
	var color_idx: int = ProjectileSim.COL_STONE
	match status_name:
		"tremor": color_idx = ProjectileSim.COL_SOUND
		"burn": color_idx = ProjectileSim.COL_FIRE
		"wet": color_idx = ProjectileSim.COL_WATER
		"blind": color_idx = ProjectileSim.COL_SOUND
		_: color_idx = ProjectileSim.COL_STONE

	match beh:
		"line_projectile":
			var tgt: int = _pick_target(ppos, float(params.get("range", 200.0)))
			var base_dir: Vector2 = aim_dir if manual_aim else Vector2.RIGHT
			if not manual_aim:
				if tgt >= 0:
					base_dir = Vector2(enemies.px[tgt] - ppos.x, enemies.py[tgt] - ppos.y).normalized()
				else:
					base_dir = Vector2.from_angle(rng.randf() * TAU)
			var cnt: int = int(params.get("count", 1))
			var spread: float = deg_to_rad(float(params.get("spread_deg", 6.0)))
			var speed: float = float(params.get("speed", 300.0)) * float(state.stats.get("proj_speed_mult", 1.0))
			var base_ang: float = base_dir.angle()
			for k in range(cnt):
				var off: float = 0.0
				if cnt > 1:
					off = (float(k) - float(cnt - 1) * 0.5) * spread
				var d: Vector2 = Vector2.from_angle(base_ang + off)
				shots.spawn(ppos.x, ppos.y, d.x, d.y, speed, _damage_of(params) * _roll_crit(), true, {
					"life": 0.9,
					"pierce": int(params.get("pierce", 0)),
					"radius": float(params.get("size", 3.0)),
					"size": float(params.get("size", 3.0)),
					"status": status_code,
					"dps": 4.0 * dot_mult,
					"kb": 0.0,
					"color": color_idx,
					"splash_r": 34.0 * area if mod == "shockwave_on_hit" else 0.0,
					"splash_dmg": _damage_of(params) * 0.45 if mod == "shockwave_on_hit" else 0.0
				})

		"homing":
			var cnt2: int = int(params.get("count", 1))
			var tgt2: int = _pick_target(ppos, float(params.get("range", 220.0)))
			var dir2: Vector2 = aim_dir if manual_aim else Vector2.RIGHT
			if not manual_aim and tgt2 >= 0:
				dir2 = Vector2(enemies.px[tgt2] - ppos.x, enemies.py[tgt2] - ppos.y).normalized()
			for k in range(cnt2):
				var a2: float = dir2.angle() + rng.randf_range(-0.6, 0.6)
				var d2: Vector2 = Vector2.from_angle(a2)
				shots.spawn(ppos.x, ppos.y, d2.x, d2.y, float(params.get("speed", 200.0)) * float(state.stats.get("proj_speed_mult", 1.0)), _damage_of(params) * _roll_crit(), true, {
					"life": float(params.get("life", 2.0)),
					"pierce": 0,
					"radius": float(params.get("size", 3.0)),
					"size": float(params.get("size", 3.0)),
					"status": status_code,
					"dps": 4.0 * dot_mult,
					"homing": float(params.get("turn_rate", 4.0)),
					"color": color_idx
				})
			if mod == "echo_blade":
				pending.append({ "t": 0.22, "entry": entry, "params": params.duplicate(), "ppos": ppos, "dir": dir2 })

		"arc_melee":
			var tgt3: int = _pick_target(ppos, float(params.get("range", 60.0)) * area)
			var facing: Vector2 = aim_dir if manual_aim else Vector2.DOWN
			if not manual_aim and tgt3 >= 0:
				facing = Vector2(enemies.px[tgt3] - ppos.x, enemies.py[tgt3] - ppos.y).normalized()
			var half: float = deg_to_rad(float(params.get("arc_deg", 110.0))) * 0.5
			var reach: float = float(params.get("range", 50.0)) * area
			var kb: float = float(params.get("knockback", 0.0)) * kb_mult
			if mod == "tidal_push":
				kb *= 1.6
			elif mod == "wall_push":
				kb *= 1.9
			var swings: int = int(params.get("count", 1))
			for s in range(swings):
				var sw_ang: float = facing.angle() + (float(s) * TAU / float(maxi(swings, 1)))
				_arc_hit(ppos, sw_ang, reach, half, _damage_of(params), status_name, 4.0 * dot_mult, kb)
				fx.append({ "kind": "arc", "x": ppos.x, "y": ppos.y, "r": reach, "ang": sw_ang, "arc": half * 2.0, "life": 0.18, "color": state.entry_color(entry) })

		"zone":
			var tgt4: int = _pick_target(ppos, float(params.get("range", 200.0)))
			var pos: Vector2 = ppos + Vector2(0, 40)
			if tgt4 >= 0:
				pos = Vector2(enemies.px[tgt4], enemies.py[tgt4])
			var cnt3: int = int(params.get("count", 1))
			for k in range(cnt3):
				zones.append({
					"x": pos.x + rng.randf_range(-16.0, 16.0) * float(k),
					"y": pos.y + rng.randf_range(-16.0, 16.0) * float(k),
					"r": float(params.get("radius", 34.0)) * area,
					"dmg": _damage_of(params),
					"dps": 4.0 * dot_mult,
					"status": status_name,
					"life": float(params.get("duration", 2.5)),
					"tick_t": 0.0,
					"tick": float(params.get("tick", 0.4)),
					"heal": 0.7 if mod == "holy_smoke" else 0.0,
					"color": state.entry_color(entry)
				})

func _arc_hit(ppos: Vector2, ang: float, reach: float, half: float, dmg_out: float, status_name: String, dps: float, kb: float) -> void:
	var n: int = enemies.query(ppos.x, ppos.y, reach)
	var idx: int = n - 1
	while idx >= 0:
		var i: int = enemies.query_buf[idx]
		if i >= 0 and i < enemies.count:
			var dx: float = enemies.px[i] - ppos.x
			var dy: float = enemies.py[i] - ppos.y
			var da: float = absf(angle_difference(ang, atan2(dy, dx)))
			if da <= half:
				if status_name != "":
					enemies.apply_status(i, status_name, dps)
				if kb > 0.0:
					enemies.knockback(i, dx, dy, kb)
				enemies.damage(i, dmg_out)
		idx -= 1

func _tick_orbit(entry: Dictionary, params: Dictionary, ppos: Vector2, delta: float) -> void:
	# 环绕武器按 tick 节流结算，不必每帧查询
	var i: int = state.weapons.find(entry)
	if i < 0:
		return
	_sync()
	if i >= timers.size():
		return
	timers[i] -= delta
	if timers[i] > 0.0:
		return
	timers[i] = float(params.get("tick", 0.35)) * (0.85 if bool(entry.get("ascended", false)) else 1.0)
	var mod: String = String(state.entry_modifier(entry))
	var cnt: int = int(params.get("count", 2))
	var radius: float = float(params.get("radius", 42.0)) * float(state.stats.get("area_mult", 1.0))
	var size: float = float(params.get("size", 7.0))
	var status_name: String = state.entry_status(entry)
	var dmg_out: float = _damage_of(params) * _roll_crit()
	if bool(entry.get("ascended", false)):
		cnt += 1
		radius *= 1.12
		dmg_out *= 1.25
	var dot_mult: float = float(state.stats.get("dot_mult", 1.0))
	var kb_mult: float = float(state.stats.get("knockback_mult", 1.0))
	for k in range(cnt):
		var a: float = orbit_angle + TAU * float(k) / float(maxi(cnt, 1))
		var ox: float = ppos.x + cos(a) * radius
		var oy: float = ppos.y + sin(a) * radius
		enemies.damage_in_circle(ox, oy, size * 0.5 + 6.0, dmg_out, status_name, 4.0 * dot_mult, 40.0 * kb_mult)
		# 燃烧的荆棘：沿途留下短命的火径
		if mod == "trail_fire" and zones.size() < 90:
			zones.append({ "x": ox, "y": oy, "r": 22.0 * float(state.stats.get("area_mult", 1.0)), "dmg": dmg_out * 0.35, "dps": 4.0 * dot_mult, "status": "burn", "life": 1.1, "tick_t": 0.2, "tick": 0.4, "heal": 0.0, "color": Color("#E0731A") })

func orbit_points(entry: Dictionary, ppos: Vector2) -> Array:
	var params: Dictionary = state.resolved_params(entry)
	var cnt: int = int(params.get("count", 2))
	var radius: float = float(params.get("radius", 42.0)) * float(state.stats.get("area_mult", 1.0))
	var pts: Array = []
	for k in range(cnt):
		var a: float = orbit_angle + TAU * float(k) / float(maxi(cnt, 1))
		pts.append({ "x": ppos.x + cos(a) * radius, "y": ppos.y + sin(a) * radius, "size": float(params.get("size", 7.0)) })
	return pts

func _tick_zones(delta: float) -> void:
	var i: int = zones.size() - 1
	while i >= 0:
		var z: Dictionary = zones[i]
		z["life"] = float(z["life"]) - delta
		if float(z["life"]) <= 0.0:
			zones.remove_at(i)
			i -= 1
			continue
		z["tick_t"] = float(z["tick_t"]) - delta
		var heal: float = float(z.get("heal", 0.0))
		if heal > 0.0:
			heal_pending += heal * delta
		if float(z["tick_t"]) <= 0.0:
			z["tick_t"] = float(z["tick"])
			enemies.damage_in_circle(float(z["x"]), float(z["y"]), float(z["r"]), float(z["dmg"]), String(z["status"]), float(z["dps"]), 0.0)
		i -= 1

## 成全后的永久改造：伤害、弹数、范围、节奏全部提升（不再只是一次性礼花）。
func _ascend_params(params: Dictionary) -> Dictionary:
	var p: Dictionary = params.duplicate()
	p["damage"] = float(p.get("damage", 1.0)) * 1.25
	if p.has("count"):
		p["count"] = int(p["count"]) + 1
	if p.has("radius"):
		p["radius"] = float(p["radius"]) * 1.12
	if p.has("range"):
		p["range"] = float(p["range"]) * 1.12
	if p.has("arc_deg"):
		p["arc_deg"] = float(p["arc_deg"]) * 1.1
	return p

## 延时复奏（锡安诗篇 echo_blade）：主弹之后 0.22 秒再来一轮弱化齐射。
func _tick_pending(delta: float) -> void:
	var i: int = pending.size() - 1
	while i >= 0:
		var pd: Dictionary = pending[i]
		pd["t"] = float(pd["t"]) - delta
		if float(pd["t"]) <= 0.0:
			_spawn_echo(pd["entry"], pd["params"], pd["ppos"], pd["dir"])
			pending.remove_at(i)
		i -= 1

func _spawn_echo(entry: Dictionary, params: Dictionary, ppos: Vector2, dir: Vector2) -> void:
	var cnt: int = int(params.get("count", 1))
	var dmg: float = _damage_of(params) * 0.55 * _roll_crit()
	var color_idx: int = shots.status_code(state.entry_status(entry))
	for k in range(cnt):
		var a: float = dir.angle() + (float(k) - float(cnt - 1) * 0.5) * 0.35
		var d: Vector2 = Vector2.from_angle(a)
		shots.spawn(ppos.x, ppos.y, d.x, d.y, float(params.get("speed", 220.0)) * float(state.stats.get("proj_speed_mult", 1.0)), dmg, true, {
			"life": float(params.get("life", 2.0)),
			"pierce": 0,
			"radius": float(params.get("size", 3.0)),
			"size": float(params.get("size", 3.0)),
			"status": color_idx,
			"dps": 4.0 * float(state.stats.get("dot_mult", 1.0)),
			"homing": float(params.get("turn_rate", 4.0)),
			"color": ProjectileSim.COL_SOUND
		})

## 成全（nova）：全屏一次性爆发。
func trigger_nova(brew: String, ppos: Vector2) -> void:
	var dmg_scale: float = float(state.stats.get("damage_mult", 1.0))
	match brew:
		"stone_rain":
			fx.append({ "kind": "nova", "x": ppos.x, "y": ppos.y, "r": 420.0, "ang": 0.0, "arc": TAU, "life": 0.6, "color": Color("#E0B85A") })
			enemies.damage_in_circle(ppos.x, ppos.y, 420.0, 120.0 * dmg_scale, "tremor", 10.0, 220.0)
		"walls_fall":
			fx.append({ "kind": "nova", "x": ppos.x, "y": ppos.y, "r": 400.0, "ang": 0.0, "arc": TAU, "life": 0.6, "color": Color("#E0B85A") })
			enemies.damage_in_circle(ppos.x, ppos.y, 400.0, 150.0 * dmg_scale, "tremor", 10.0, 300.0)
		"eternal_flame":
			fx.append({ "kind": "nova", "x": ppos.x, "y": ppos.y, "r": 380.0, "ang": 0.0, "arc": TAU, "life": 0.9, "color": Color("#E0731A") })
			enemies.damage_in_circle(ppos.x, ppos.y, 380.0, 90.0 * dmg_scale, "burn", 14.0, 0.0)
		_:
			fx.append({ "kind": "nova", "x": ppos.x, "y": ppos.y, "r": 360.0, "ang": 0.0, "arc": TAU, "life": 0.6, "color": Color("#F0D890") })
			enemies.damage_in_circle(ppos.x, ppos.y, 360.0, 110.0 * dmg_scale, "", 0.0, 120.0)
