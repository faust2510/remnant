class_name WeaponRunner
extends RefCounted
## 武器执行器：把「行为原子 + 数据参数」跑成实际攻击。
## 五类原子：line_projectile / arc_melee / orbit / zone / homing。
## 祝圣武器与成全武器只是同一套原子的参数组合 + modifier，不新增代码路径。

## 六种祝圣 modifier 的附加区域参数表：附加区域全部从这里取值，
## 并统一由 _spawn_mod_zone() -> _spawn_zone() 生成，代码里不再各自 append zones。
## r = 半径（再乘面积倍率） / life = 存活秒 / tick = 结算间隔 /
## dmg_pct = 占本次命中伤害的比例 / status + dps = 区域施加的状态 /
## slow = 区域内敌人速度倍率（1.0 = 不减速） / heal = 每秒治疗 / color = 颜色。
## shockwave_on_hit 的溅射仍由弹幕内部结算（ProjectileSim 冻结，外面拿不到逐敌回调），
## 但半径与伤害比例同样取自这张表，六条走的是同一份数值口径。
## holy_smoke 不另生成区域：它的 heal 挂在 zone 武器自己的领域上（_fire 的 zone 分支读取）。
const MOD_ZONES := {
	"tidal_push": { "r": 46.0, "life": 2.0, "tick": 0.5, "dmg_pct": 0.18, "status": "wet", "dps": 4.0, "slow": 0.6, "color": "#3F86C8" },
	"trail_fire": { "r": 22.0, "life": 1.5, "tick": 0.4, "dmg_pct": 0.35, "status": "burn", "dps": 4.0, "slow": 1.0, "color": "#E0731A" },
	"wall_push": { "r": 26.0, "life": 0.18, "tick": 0.18, "dmg_pct": 0.35, "status": "", "dps": 0.0, "slow": 1.0, "color": "#E0B85A" },
	"echo_blade": { "r": 42.0, "life": 1.2, "tick": 0.6, "dmg_pct": 0.0, "status": "blind", "dps": 0.0, "slow": 1.0, "color": "#B9A6E8" },
	"holy_smoke": { "heal": 1.5 },
	"shockwave_on_hit": { "r": 34.0, "dmg_pct": 0.45 }
}
const MAX_ZONES := 120           # 区域总数上限（火径会疯狂生成，必须有帽）
const MAX_BLASTS_PER_SWING := 4  # 城墙倾覆：一次挥击最多几次二次震爆
const ECHO_DELAY := 0.22         # 锡安诗篇：主弹之后多久复奏一轮
const ECHO_RING_DELAY := 0.5     # 音刃消散点近似延迟（见 _fire 的 homing 分支注释）

var state: GameState
var enemies: EnemySim
var shots: ProjectileSim

var timers: PackedFloat32Array = PackedFloat32Array()
var orbit_angle: float = 0.0
var zones: Array = []          # {x, y, r, dmg, dps, status, life, tick_t, tick, heal, slow, crit, color}
var fx: Array = []             # {kind, x, y, r, ang, arc, life, color} 供渲染层消费
var manual_aim: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var heal_pending: float = 0.0   # 治疗类区域的累积治疗量（没接 on_heal 时由 run 每帧取走）
var pending: Array = []         # 延时效果：{t, entry, params, ppos, dir} 复奏 / {t, ring, at, dmg, crit} 音环

## 对外钩子（V3 契约）：所有对敌人造成伤害的位置都回调 (x, y, amount, crit)，
## run 侧在 _ready 里接成 dmg_events.append({x, y, amt, crit}) 就有浮动伤害数字。
var on_damage: Callable = Callable()
## 对外钩子：区域治疗回调 (amount)。run 接上 heal_player() 后香炉治疗立即生效；
## 不接则退回 heal_pending 累积（run.gd 现有逻辑，一行不改也能跑）。
var on_heal: Callable = Callable()
## 最近一次 _roll_crit() 是否暴击：同步结算路径（近战/环绕/领域）用它标 on_damage 的 crit。
var last_crit: bool = false
## 暴击弹幕的伤害值表：弹幕命中回调只有坐标，靠伤害值反查 crit（条目随等级缓慢增长，很小）。
var _crit_dmgs: Dictionary = {}

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
		# 成全后的永久参数（entry["ascend_params"]）统一从 fire_params 取：
		# 已经烘进字典，这里不需要也不允许再乘一次倍率。
		var params: Dictionary = state.fire_params(entry)
		if beh == "orbit":
			_tick_orbit(entry, params, ppos, delta)
			continue
		timers[i] -= delta
		if timers[i] <= 0.0:
			var cd: float = float(params.get("cooldown", 1.0)) * float(state.stats.get("cooldown_mult", 1.0))
			timers[i] = maxf(cd, 0.08)
			_fire(entry, beh, params, ppos, aim_dir)

	_tick_zones(delta)
	_tick_pending(delta)
	# 契约 v2：灼烧最大层数由武器层下发（默认为 1.0 表示未配置，保留引擎基准 5 层）
	if enemies != null:
		enemies.burn_cap = maxi(5, int(round(float(state.stats.get("burn_stack_max", 1.0)))))

func _pick_target(ppos: Vector2, rng_dist: float) -> int:
	var n: int = enemies.query(ppos.x, ppos.y, rng_dist)
	var best: int = -1
	var best_d: float = 1e18
	var boss: int = -1
	var boss_d: float = 1e18
	for k in range(n):
		var j: int = enemies.query_buf[k]
		var dx: float = enemies.px[j] - ppos.x
		var dy: float = enemies.py[j] - ppos.y
		var d2: float = dx * dx + dy * dy
		# 契约 v2：BOSS 是关底考卷，只要落在本次武器的射程内就优先锁定。
		# 否则站位拉开后武器永远只打最近的杂兵，BOSS 一发不吃（2026-11 实测 90s 0 伤害）。
		if enemies.is_boss(j):
			if d2 < boss_d:
				boss_d = d2
				boss = j
			continue
		if d2 < best_d:
			best_d = d2
			best = j
	return boss if boss >= 0 else best

func _damage_of(params: Dictionary) -> float:
	return float(params.get("damage", 1.0)) * float(state.stats.get("damage_mult", 1.0))

## 契约 v2 新增：效果持续倍率（领域 / 弹幕存活）。
func _dur_mult() -> float:
	return maxf(float(state.stats.get("duration", 1.0)), 0.1)

## 契约 v2 新增：额外投射物（契约 / 角色 / 圣物都走 state meta）。
## 约 · 阿尔法与俄梅戛：line_projectile 与 homing 弹幕寿命耗尽时折返玩家方向再穿透一次
func _alpha_omega() -> bool:
	return bool(state.get_meta("covenant_alpha_omega", false))

func _extra_projectiles() -> int:
	var n: int = int(state.stats.get("extra_projectile", 0))
	if state.has_meta("extra_projectile"):
		n += int(state.get_meta("extra_projectile"))
	return maxi(n, 0)

## 契约 v2 新增：仅近战加成（只作用于 arc_melee）。
func _melee_bonus() -> float:
	return 1.0 + maxf(float(state.stats.get("melee_only_bonus", 0.0)), 0.0)

func _roll_crit() -> float:
	last_crit = false
	var c: float = float(state.stats.get("crit_chance", 0.05))
	if rng.randf() < c:
		last_crit = true
		var mult: float = float(state.stats.get("crit_mult", 1.6))
		if manual_aim:
			mult *= float(state.perf("aim_crit_mult", 1.0))
		return mult
	return 1.0

## 算一发弹幕的伤害并顺手记下暴击标记：
## 弹幕命中只有坐标回调，on_projectile_hit 靠伤害值反查 crit（见 _crit_dmgs）。
func _shot_dmg(params: Dictionary, mult: float = 1.0) -> float:
	var dmg: float = _damage_of(params) * mult * _roll_crit()
	if last_crit:
		_crit_dmgs[dmg] = true
	return dmg

func _fire(entry: Dictionary, beh: String, params: Dictionary, ppos: Vector2, aim_dir: Vector2) -> void:
	var mod: String = String(state.entry_modifier(entry))
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
			var cnt: int = int(params.get("count", 1)) + _extra_projectiles()
			var spread: float = deg_to_rad(float(params.get("spread_deg", 6.0)))
			var speed: float = float(params.get("speed", 300.0)) * float(state.stats.get("proj_speed_mult", 1.0))
			var base_ang: float = base_dir.angle()
			# 音波溅射（shockwave_on_hit）仍走弹幕自带的 splash 字段，数值取 MOD_ZONES
			var sw: Dictionary = _mod_cfg(mod)
			for k in range(cnt):
				var off: float = 0.0
				if cnt > 1:
					off = (float(k) - float(cnt - 1) * 0.5) * spread
				var d: Vector2 = Vector2.from_angle(base_ang + off)
				shots.spawn(ppos.x, ppos.y, d.x, d.y, speed, _shot_dmg(params), true, {
					"life": 0.9 * _dur_mult(),
					"pierce": int(params.get("pierce", 0)),
					"radius": float(params.get("size", 3.0)),
					"size": float(params.get("size", 3.0)),
					"status": status_code,
					"dps": 4.0 * dot_mult,
					"kb": 0.0,
					"color": color_idx,
					"splash_r": float(sw.get("r", 0.0)) * area,
					"splash_dmg": _damage_of(params) * float(sw.get("dmg_pct", 0.0)),
					"return": _alpha_omega()
				})

		"homing":
			var cnt2: int = int(params.get("count", 1)) + _extra_projectiles()
			var tgt2: int = _pick_target(ppos, float(params.get("range", 220.0)))
			var dir2: Vector2 = aim_dir if manual_aim else Vector2.RIGHT
			if not manual_aim and tgt2 >= 0:
				dir2 = Vector2(enemies.px[tgt2] - ppos.x, enemies.py[tgt2] - ppos.y).normalized()
			for k in range(cnt2):
				var a2: float = dir2.angle() + rng.randf_range(-0.6, 0.6)
				var d2: Vector2 = Vector2.from_angle(a2)
				shots.spawn(ppos.x, ppos.y, d2.x, d2.y, float(params.get("speed", 200.0)) * float(state.stats.get("proj_speed_mult", 1.0)), _shot_dmg(params), true, {
					"life": float(params.get("life", 2.0)) * _dur_mult(),
					"pierce": int(params.get("pierce", 0)),
					"radius": float(params.get("size", 3.0)),
					"size": float(params.get("size", 3.0)),
					"status": status_code,
					"dps": 4.0 * dot_mult,
					"homing": float(params.get("turn_rate", 4.0)),
					"color": color_idx,
					"return": _alpha_omega()
				})
			if mod == "echo_blade":
				# 1) 复奏一轮弱化齐射
				pending.append({ "t": ECHO_DELAY, "entry": entry, "params": params.duplicate(), "ppos": ppos, "dir": dir2 })
				# 2) 消散处留 1.2 秒致盲音环。
				#    ProjectileSim 冻结、没有「弹幕消散」回调，这里用「锁定目标此刻的位置 + 0.5 秒延迟」
				#    近似消散点：命中型音刃基本都在目标附近消失（无目标时沿射向取 70px 落点）。
				var ring_at: Vector2 = ppos + dir2 * 70.0
				if tgt2 >= 0:
					ring_at = Vector2(enemies.px[tgt2], enemies.py[tgt2])
				pending.append({ "t": ECHO_RING_DELAY, "ring": "echo_blade", "at": ring_at, "dmg": _damage_of(params), "crit": false })

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
			var dmg_arc: float = _damage_of(params) * _melee_bonus()
			var swings: int = int(params.get("count", 1))
			for s in range(swings):
				var sw_ang: float = facing.angle() + (float(s) * TAU / float(maxi(swings, 1)))
				# 近战扇击沿用既有算法，不吃暴击（crit 恒 false），不在这里顺手改数值
				var hits: int = _arc_hit(ppos, sw_ang, reach, half, dmg_arc, status_name, 4.0 * dot_mult, kb, mod, false)
				# 活水：命中后在前方留 2 秒减速带（区域统一走 MOD_ZONES / _spawn_mod_zone）
				if mod == "tidal_push" and hits > 0:
					var wdir: Vector2 = Vector2.from_angle(sw_ang)
					var off2: float = minf(reach * 0.6, 72.0)
					_spawn_mod_zone("tidal_push", ppos.x + wdir.x * off2, ppos.y + wdir.y * off2, dmg_arc, false)
				fx.append({ "kind": "arc", "x": ppos.x, "y": ppos.y, "r": reach, "ang": sw_ang, "arc": half * 2.0, "life": 0.18, "color": state.entry_color(entry) })

		"zone":
			# center:"self" 表示以玩家为圆心（铃鼓类）；range<=8 视为自心领域（旧数据兼容）。
			# throw_dist 表示「朝目标方向只扔这么远」，缺省仍然落在目标脚下。
			var zrange: float = float(params.get("range", 200.0))
			var tgt4: int = _pick_target(ppos, zrange)
			var throw_dist: float = float(params.get("throw_dist", 0.0))
			var pos: Vector2 = ppos + Vector2(0, 40)
			if String(params.get("center", "")) == "self" or zrange <= 8.0:
				pos = ppos
			elif tgt4 >= 0:
				var to_t: Vector2 = Vector2(enemies.px[tgt4] - ppos.x, enemies.py[tgt4] - ppos.y)
				if throw_dist > 0.0:
					to_t = to_t.limit_length(throw_dist)
				pos = ppos + to_t
			elif throw_dist > 0.0:
				var fdir: Vector2 = aim_dir.normalized() if manual_aim else Vector2(0, 1)
				pos = ppos + fdir * throw_dist
			# 香炉（holy_smoke）：领域内每秒回 1.5 HP，数值同样来自 MOD_ZONES
			var heal_ps: float = float(_mod_cfg("holy_smoke").get("heal", 0.0)) if mod == "holy_smoke" else 0.0
			var cnt3: int = int(params.get("count", 1)) + _extra_projectiles()
			for k in range(cnt3):
				_spawn_zone({
					"x": pos.x + rng.randf_range(-16.0, 16.0) * float(k),
					"y": pos.y + rng.randf_range(-16.0, 16.0) * float(k),
					"r": float(params.get("radius", 34.0)) * area,
					"dmg": _damage_of(params),
					"dps": 4.0 * dot_mult,
					"status": status_name,
					"life": float(params.get("duration", 2.5)) * _dur_mult(),
					"tick_t": 0.0,
					"tick": float(params.get("tick", 0.4)),
					"heal": heal_ps,
					"slow": 1.0,
					"crit": false,
					"color": state.entry_color(entry)
				})

## 近战扇击：逐敌结算并逐敌发 on_damage。
## 返回本击命中数（活水减速区按「命中后」才生成，靠它判断）。
## mod 用于城墙倾覆的二次震爆；爆裂本身只生成区域，不会再进本函数 —— 天然不递归。
func _arc_hit(ppos: Vector2, ang: float, reach: float, half: float, dmg_out: float, status_name: String, dps: float, kb: float, mod: String, crit: bool) -> int:
	var n: int = enemies.query(ppos.x, ppos.y, reach)
	var hits: int = 0
	var blasts: int = 0
	var idx: int = n - 1
	while idx >= 0:
		var i: int = enemies.query_buf[idx]
		if i >= 0 and i < enemies.count:
			var dx: float = enemies.px[i] - ppos.x
			var dy: float = enemies.py[i] - ppos.y
			var da: float = absf(angle_difference(ang, atan2(dy, dx)))
			if da <= half:
				var ex: float = enemies.px[i]
				var ey: float = enemies.py[i]
				if status_name != "":
					enemies.apply_status(i, status_name, dps)
				if absf(kb) > 0.01:
					enemies.knockback(i, dx, dy, kb)
				enemies.damage(i, dmg_out)
				hits += 1
				_emit_damage(ex, ey, dmg_out, crit)
				# 城墙倾覆：被击退目标的落点再来一次小震爆（每次挥击限量，不递归）
				if mod == "wall_push" and blasts < MAX_BLASTS_PER_SWING:
					blasts += 1
					_wall_blast(i, dx, dy, kb, dmg_out, crit)
		idx -= 1
	return hits

## 城墙倾覆的二次震爆：先自己把目标推到落点，再在落点生成低伤小范围区域。
## 为什么要自己写 px/py：EnemySim 每帧把 vx/vy 整个重写成追击方向（knockback 只加 vx，下一帧就被覆盖），
## 击退实际位移≈0；run.gd 也直接写 enemies.spd，直接推坐标是本项目既有做法。
func _wall_blast(i: int, dx: float, dy: float, force: float, dmg_out: float, crit: bool) -> void:
	if enemies == null or i < 0 or i >= enemies.count:
		return
	var d: Vector2 = Vector2(dx, dy)
	if d.length_squared() < 0.0001:
		d = Vector2.DOWN
	d = d.normalized()
	var push: float = clampf(absf(force) * 0.06, 8.0, 40.0)
	var lx: float = enemies.px[i] + d.x * push
	var ly: float = enemies.py[i] + d.y * push
	enemies.px[i] = lx
	enemies.py[i] = ly
	_spawn_mod_zone("wall_push", lx, ly, dmg_out, crit)

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
	# 成全的节奏（tick ×0.85）已在成全瞬间永久写进参数，这里不再重复乘
	timers[i] = maxf(float(params.get("tick", 0.35)), 0.05)
	var mod: String = String(state.entry_modifier(entry))
	var cnt: int = int(params.get("count", 2)) + _extra_projectiles()
	var radius: float = float(params.get("radius", 42.0)) * float(state.stats.get("area_mult", 1.0))
	var size: float = float(params.get("size", 7.0))
	var status_name: String = state.entry_status(entry)
	var dmg_out: float = _damage_of(params) * _roll_crit()
	var crit: bool = last_crit
	var dot_mult: float = float(state.stats.get("dot_mult", 1.0))
	var kb_mult: float = float(state.stats.get("knockback_mult", 1.0))
	for k in range(cnt):
		var a: float = orbit_angle + TAU * float(k) / float(maxi(cnt, 1))
		var ox: float = ppos.x + cos(a) * radius
		var oy: float = ppos.y + sin(a) * radius
		_damage_area(ox, oy, size * 0.5 + 6.0, dmg_out, status_name, 4.0 * dot_mult, 40.0 * kb_mult, crit)
		# 燃烧的荆棘（trail_fire）：每个 tick 在轨道位置留 1.5 秒圣火余烬区域
		if mod == "trail_fire":
			_spawn_mod_zone("trail_fire", ox, oy, dmg_out, crit)

func orbit_points(entry: Dictionary, ppos: Vector2) -> Array:
	var params: Dictionary = state.fire_params(entry)
	var cnt: int = int(params.get("count", 2))
	var radius: float = float(params.get("radius", 42.0)) * float(state.stats.get("area_mult", 1.0))
	var pts: Array = []
	for k in range(cnt):
		var a: float = orbit_angle + TAU * float(k) / float(maxi(cnt, 1))
		pts.append({ "x": ppos.x + cos(a) * radius, "y": ppos.y + sin(a) * radius, "size": float(params.get("size", 7.0)) })
	return pts

# ---------------------------------------------------------------- 区域

## 统一区域生成入口：领域武器 + 六种祝圣 modifier 的附加区域全部走这里。
func _spawn_zone(spec: Dictionary) -> Dictionary:
	if zones.size() >= MAX_ZONES:
		return {}
	var z: Dictionary = {
		"x": float(spec.get("x", 0.0)),
		"y": float(spec.get("y", 0.0)),
		"r": maxf(float(spec.get("r", 20.0)), 2.0),
		"dmg": float(spec.get("dmg", 0.0)),
		"dps": float(spec.get("dps", 0.0)),
		"status": String(spec.get("status", "")),
		"life": maxf(float(spec.get("life", 1.0)), 0.02),
		"tick_t": float(spec.get("tick_t", 0.0)),
		"tick": maxf(float(spec.get("tick", 0.4)), 0.05),
		"heal": float(spec.get("heal", 0.0)),
		"slow": clampf(float(spec.get("slow", 1.0)), 0.05, 1.0),
		"crit": bool(spec.get("crit", false)),
		"color": spec.get("color", Color("#C9A66B"))
	}
	zones.append(z)
	return z

func _mod_cfg(mod: String) -> Dictionary:
	var c: Variant = MOD_ZONES.get(mod, null)
	return c if c is Dictionary else {}

## 按 MOD_ZONES 生成一件祝圣 modifier 的区域：x/y 由调用点给，dmg = 本次命中的伤害基数。
## scale 用来额外缩放半径（默认 1.0）。未配置的 modifier 返回空字典，不生成任何东西。
func _spawn_mod_zone(mod: String, x: float, y: float, dmg: float, crit: bool, scale: float = 1.0) -> Dictionary:
	var cfg: Dictionary = _mod_cfg(mod)
	if cfg.is_empty() or state == null:
		return {}
	var area: float = float(state.stats.get("area_mult", 1.0)) * scale
	return _spawn_zone({
		"x": x,
		"y": y,
		"r": float(cfg.get("r", 20.0)) * area,
		"dmg": dmg * float(cfg.get("dmg_pct", 0.0)),
		"dps": float(cfg.get("dps", 0.0)) * float(state.stats.get("dot_mult", 1.0)),
		"status": String(cfg.get("status", "")),
		"life": float(cfg.get("life", 1.0)) * _dur_mult(),
		"tick": float(cfg.get("tick", 0.4)),
		"tick_t": 0.0,
		"heal": float(cfg.get("heal", 0.0)),
		"slow": float(cfg.get("slow", 1.0)),
		"crit": crit,
		"color": Color(String(cfg.get("color", "#C9A66B")))
	})

func _tick_zones(delta: float) -> void:
	var i: int = zones.size() - 1
	while i >= 0:
		var z: Dictionary = zones[i]
		z["life"] = float(z["life"]) - delta
		if float(z["life"]) <= 0.0:
			zones.remove_at(i)
			i -= 1
			continue
		var heal: float = float(z.get("heal", 0.0))
		if heal > 0.0:
			# 香炉治疗：run 接了 on_heal = heal_player 就立刻回血（up to 1.5 HP/s），
			# 没接则退回旧口径 heal_pending 累积，run.gd 一行不改也不会丢治疗。
			if on_heal.is_valid():
				on_heal.call(heal * delta)
			else:
				heal_pending += heal * delta
		# 活水减速区：区域内敌人速度 ×slow（默认 1.0 不处理）
		var slow: float = float(z.get("slow", 1.0))
		if slow < 0.999:
			_slow_area(float(z["x"]), float(z["y"]), float(z["r"]), slow)
		z["tick_t"] = float(z["tick_t"]) - delta
		if float(z["tick_t"]) <= 0.0:
			z["tick_t"] = float(z["tick"])
			_damage_area(float(z["x"]), float(z["y"]), float(z["r"]), float(z["dmg"]), String(z.get("status", "")), float(z.get("dps", 0.0)), 0.0, bool(z.get("crit", false)))
		i -= 1

## 区域减速。EnemySim 目前只有 tremor 一条减速通道（0.7×），没有逐单位减速字段；
## 若 run-systems 侧补上 slow_area(cx, cy, r, mult, dur)（in-range 取最慢、离开即过期），
## 这里检测到就直接调用，球速会精确变成 ×0.6，不用再改本文件。
func _slow_area(cx: float, cy: float, r: float, mult: float) -> void:
	if enemies == null:
		return
	if enemies.has_method("slow_area"):
		enemies.call("slow_area", cx, cy, r, mult, 0.25)
		return
	var ids: PackedInt32Array = enemies.indices_in_circle(cx, cy, r)
	var k: int = ids.size() - 1
	while k >= 0:
		var i: int = ids[k]
		if i >= 0 and i < enemies.count:
			enemies.apply_status(i, "tremor", 0.0)
		k -= 1

# ---------------------------------------------------------------- 伤害结算

func _emit_damage(x: float, y: float, amount: float, crit: bool) -> void:
	if on_damage.is_valid():
		on_damage.call(x, y, amount, crit)

## 统一范围伤害：按 indices_in_circle 拷出来的索引逐敌结算，这样每个被命中的敌人都能单独发 on_damage。
## （enemies.damage_in_circle 内部是同一套 grid 查询，但它不暴露逐敌回调，所以这里自己走一遍。）
func _damage_area(cx: float, cy: float, r: float, amount: float, status_name: String, dps: float, kb: float, crit: bool) -> int:
	if enemies == null or r <= 0.0:
		return 0
	var ids: PackedInt32Array = enemies.indices_in_circle(cx, cy, r)
	var hits: int = 0
	var k: int = ids.size() - 1
	while k >= 0:
		var i: int = ids[k]
		if i >= 0 and i < enemies.count:
			var ex: float = enemies.px[i]
			var ey: float = enemies.py[i]
			if status_name != "":
				enemies.apply_status(i, status_name, dps)
			if absf(kb) > 0.01:
				enemies.knockback(i, ex - cx, ey - cy, kb)
			if amount > 0.0:
				enemies.damage(i, amount)
				hits += 1
				_emit_damage(ex, ey, amount, crit)
		k -= 1
	return hits

## 弹幕命中回调（给 ProjectileSim.update 的第三个参数用）：
## run 侧改成 shots.update(delta, enemies, weapons.on_projectile_hit, player) 之后，
## line_projectile / homing 的每次命中都会以浮动伤害数字的形式回报给 on_damage。
## 命中点就是弹幕自己的坐标，所以反查同坐标的友方弹幕取伤害值（crit 靠 _crit_dmgs 反查）。
func on_projectile_hit(hx: float, hy: float) -> void:
	if not on_damage.is_valid() or shots == null:
		return
	var best: int = -1
	var best_d2: float = 6.0
	for i in range(shots.count):
		if int(shots.friendly[i]) == 0:
			continue
		var dx: float = shots.px[i] - hx
		var dy: float = shots.py[i] - hy
		var d2: float = dx * dx + dy * dy
		if d2 <= best_d2:
			best_d2 = d2
			best = i
	if best < 0:
		return
	var dmg: float = float(shots.dmg[best])
	on_damage.call(hx, hy, dmg, _crit_dmgs.has(dmg))

# ---------------------------------------------------------------- 延时效果

## 延时效果：复奏（echo_blade 的弱化齐射）与音环（echo_blade 的致盲区域）。
func _tick_pending(delta: float) -> void:
	var i: int = pending.size() - 1
	while i >= 0:
		var pd: Dictionary = pending[i]
		pd["t"] = float(pd["t"]) - delta
		if float(pd["t"]) <= 0.0:
			if pd.has("ring"):
				var at: Vector2 = pd.get("at", Vector2.ZERO)
				_spawn_mod_zone(String(pd["ring"]), at.x, at.y, float(pd.get("dmg", 0.0)), bool(pd.get("crit", false)))
			else:
				_spawn_echo(pd["entry"], pd["params"], pd["ppos"], pd["dir"])
			pending.remove_at(i)
		i -= 1

func _spawn_echo(entry: Dictionary, params: Dictionary, ppos: Vector2, dir: Vector2) -> void:
	var cnt: int = int(params.get("count", 1))
	var dmg: float = _shot_dmg(params, 0.55)
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

## 成全（nova）：全屏一次性爆发。走 _damage_area，所以成全伤害也会发浮动数字。
func trigger_nova(brew: String, ppos: Vector2) -> void:
	var dmg_scale: float = float(state.stats.get("damage_mult", 1.0))
	match brew:
		"stone_rain":
			fx.append({ "kind": "nova", "x": ppos.x, "y": ppos.y, "r": 420.0, "ang": 0.0, "arc": TAU, "life": 0.6, "color": Color("#E0B85A") })
			_damage_area(ppos.x, ppos.y, 420.0, 120.0 * dmg_scale, "tremor", 10.0, 220.0, false)
		"walls_fall":
			fx.append({ "kind": "nova", "x": ppos.x, "y": ppos.y, "r": 400.0, "ang": 0.0, "arc": TAU, "life": 0.6, "color": Color("#E0B85A") })
			_damage_area(ppos.x, ppos.y, 400.0, 150.0 * dmg_scale, "tremor", 10.0, 300.0, false)
		"eternal_flame":
			fx.append({ "kind": "nova", "x": ppos.x, "y": ppos.y, "r": 380.0, "ang": 0.0, "arc": TAU, "life": 0.9, "color": Color("#E0731A") })
			_damage_area(ppos.x, ppos.y, 380.0, 90.0 * dmg_scale, "burn", 14.0, 0.0, false)
		_:
			fx.append({ "kind": "nova", "x": ppos.x, "y": ppos.y, "r": 360.0, "ang": 0.0, "arc": TAU, "life": 0.6, "color": Color("#F0D890") })
			_damage_area(ppos.x, ppos.y, 360.0, 110.0 * dmg_scale, "", 0.0, 120.0, false)
