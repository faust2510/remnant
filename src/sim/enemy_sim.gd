class_name EnemySim
extends RefCounted
## 敌人模拟层：SoA 数组 + 空间哈希，完全脱离场景树。
## 渲染由 EntityRenderer 读取本结构批量绘制；逻辑可被 tools/sim_run.gd 无头复用。

const CAPACITY := 2400
const MAX_QUERY := 512

var types: Array = []          # 类型定义（GameData.enemies 的有序数组）
var type_ids: Array = []       # 与 types 对应的 id 字符串

var count: int = 0
var px: PackedFloat32Array
var py: PackedFloat32Array
var vx: PackedFloat32Array
var vy: PackedFloat32Array
var hp: PackedFloat32Array
var max_hp: PackedFloat32Array
var spd: PackedFloat32Array
var dmg: PackedFloat32Array
var rad: PackedFloat32Array
var typ: PackedInt32Array
var flash: PackedFloat32Array
var armor_shred: PackedFloat32Array

# 状态：0 burn 叠层 / 1 burn 计时 / 2 震慑 / 3 致盲 / 4 活水 / 5 战兢
var burn_stack: PackedInt32Array
var burn_t: PackedFloat32Array
var burn_dps: PackedFloat32Array
var tremor_t: PackedFloat32Array
var blind_t: PackedFloat32Array
var wet_t: PackedFloat32Array
var fear_t: PackedFloat32Array

# 行为计时与本帧输出
var timer: PackedFloat32Array
var state: PackedInt32Array
var touch_cd: PackedFloat32Array
var hp_scale: float = 1.0
var speed_scale: float = 1.0

var grid: SpatialGrid
var query_buf: PackedInt32Array

# 敌人投射物请求队列：每 5 个 float 一枚 [x, y, vx, vy, dmg]
var shot_queue: PackedFloat32Array
var shot_count: int = 0
# 召唤请求：每 3 个 float [x, y, type_index]
var summon_queue: PackedFloat32Array
var summon_count: int = 0

var killed: PackedInt32Array
var killed_count: int = 0
## 死亡事件队列：{x, y, xp, typ, elite, boss}，由外层每帧消费后清空。
var deaths: Array = []
var stat_hp: PackedFloat32Array
var stat_dmg: PackedFloat32Array
var stat_xp: PackedInt32Array

func setup(type_defs: Array) -> void:
	types = type_defs
	type_ids = []
	for t in types:
		type_ids.append(String(t["id"]))
	px.resize(CAPACITY); py.resize(CAPACITY); vx.resize(CAPACITY); vy.resize(CAPACITY)
	hp.resize(CAPACITY); max_hp.resize(CAPACITY); spd.resize(CAPACITY); dmg.resize(CAPACITY)
	rad.resize(CAPACITY); typ.resize(CAPACITY); flash.resize(CAPACITY); armor_shred.resize(CAPACITY)
	burn_stack.resize(CAPACITY); burn_t.resize(CAPACITY); burn_dps.resize(CAPACITY)
	tremor_t.resize(CAPACITY); blind_t.resize(CAPACITY); wet_t.resize(CAPACITY); fear_t.resize(CAPACITY)
	timer.resize(CAPACITY); state.resize(CAPACITY); touch_cd.resize(CAPACITY)
	grid = SpatialGrid.new()
	grid.setup(CAPACITY, 32.0)
	query_buf.resize(MAX_QUERY)
	shot_queue.resize(512 * 5)
	summon_queue.resize(256 * 3)
	killed.resize(512)
	deaths = []
	count = 0

func clear() -> void:
	count = 0
	shot_count = 0
	summon_count = 0
	killed_count = 0
	deaths.clear()
	hp_scale = 1.0
	speed_scale = 1.0

func type_index_of(id: String) -> int:
	return type_ids.find(id)

func spawn(ti: int, x: float, y: float, phase: int = 0) -> int:
	if count >= CAPACITY:
		return -1
	var t: Dictionary = types[ti]
	var i: int = count
	count += 1
	px[i] = x; py[i] = y; vx[i] = 0.0; vy[i] = 0.0
	var base_hp: float = float(t.get("hp", 10)) * hp_scale
	hp[i] = base_hp; max_hp[i] = base_hp
	spd[i] = float(t.get("speed", 40)) * speed_scale
	dmg[i] = float(t.get("damage", 5))
	rad[i] = float(t.get("radius", 6))
	typ[i] = ti
	flash[i] = 0.0
	armor_shred[i] = 0.0
	burn_stack[i] = 0; burn_t[i] = 0.0; burn_dps[i] = 0.0
	tremor_t[i] = 0.0; blind_t[i] = 0.0; wet_t[i] = 0.0; fear_t[i] = 0.0
	timer[i] = randf() * 1.5
	state[i] = 0
	touch_cd[i] = 0.0
	return i

func _swap_remove(i: int) -> void:
	var last: int = count - 1
	if i != last:
		px[i] = px[last]; py[i] = py[last]; vx[i] = vx[last]; vy[i] = vy[last]
		hp[i] = hp[last]; max_hp[i] = max_hp[last]; spd[i] = spd[last]; dmg[i] = dmg[last]
		rad[i] = rad[last]; typ[i] = typ[last]; flash[i] = flash[last]; armor_shred[i] = armor_shred[last]
		burn_stack[i] = burn_stack[last]; burn_t[i] = burn_t[last]; burn_dps[i] = burn_dps[last]
		tremor_t[i] = tremor_t[last]; blind_t[i] = blind_t[last]; wet_t[i] = wet_t[last]; fear_t[i] = fear_t[last]
		timer[i] = timer[last]; state[i] = state[last]; touch_cd[i] = touch_cd[last]
	count -= 1

func is_elite(i: int) -> bool:
	return bool(types[typ[i]].get("elite", false))

func is_boss(i: int) -> bool:
	return String(types[typ[i]].get("behavior", "")) == "boss"

func _record_death(i: int) -> void:
	var t: Dictionary = types[typ[i]]
	deaths.append({
		"x": px[i], "y": py[i],
		"xp": int(t.get("xp", 1)),
		"typ": String(t.get("id", "")),
		"elite": bool(t.get("elite", false)),
		"coal": int(t.get("coal_drop", 0)),
		"boss": String(t.get("behavior", "")) == "boss"
	})

## 造成伤害。返回是否击杀。
func damage(i: int, amount: float) -> bool:
	if i < 0 or i >= count:
		return false
	hp[i] -= amount
	flash[i] = 0.12
	if hp[i] <= 0.0:
		_record_death(i)
		_swap_remove(i)
		return true
	return false

func kill_now(i: int) -> void:
	if i < 0 or i >= count:
		return
	_record_death(i)
	_swap_remove(i)

func apply_status(i: int, status: String, dps: float) -> void:
	if i < 0 or i >= count:
		return
	match status:
		"burn":
			burn_stack[i] = mini(burn_stack[i] + 1, 5)
			burn_t[i] = maxf(burn_t[i], 3.0)
			burn_dps[i] = maxf(burn_dps[i], dps)
		"tremor":
			tremor_t[i] = maxf(tremor_t[i], 3.0)
		"blind":
			blind_t[i] = maxf(blind_t[i], 2.0)
		"wet":
			wet_t[i] = maxf(wet_t[i], 4.0)
		"fear":
			fear_t[i] = maxf(fear_t[i], 2.0)
		_: pass

func knockback(i: int, dir_x: float, dir_y: float, force: float) -> void:
	if i < 0 or i >= count:
		return
	var l: float = sqrt(dir_x * dir_x + dir_y * dir_y)
	if l < 0.0001:
		return
	var f: float = force / l
	vx[i] += dir_x * f
	vy[i] += dir_y * f

func rebuild_grid() -> void:
	grid.rebuild(px, py, count)

func query(x: float, y: float, radius: float) -> int:
	return grid.query_radius(x, y, radius, query_buf, MAX_QUERY)

## 每帧推进。返回本帧敌人对玩家造成的接触伤害。
func update(delta: float, ppos: Vector2, dot_mult: float) -> float:
	var contact := 0.0
	for i in range(count):
		var t: Dictionary = types[typ[i]]
		var beh: String = String(t.get("behavior", "chase"))

		# ---- 状态衰减
		if flash[i] > 0.0:
			flash[i] = maxf(flash[i] - delta, 0.0)
		if burn_t[i] > 0.0:
			burn_t[i] -= delta
			hp[i] -= burn_dps[i] * float(burn_stack[i]) * delta * dot_mult
			if hp[i] <= 0.0:
				_record_death(i)
				_swap_remove(i)
				i -= 1
				continue
		if tremor_t[i] > 0.0: tremor_t[i] -= delta
		if blind_t[i] > 0.0: blind_t[i] -= delta
		if wet_t[i] > 0.0: wet_t[i] -= delta
		if fear_t[i] > 0.0: fear_t[i] -= delta

		var dx: float = ppos.x - px[i]
		var dy: float = ppos.y - py[i]
		var dist: float = sqrt(dx * dx + dy * dy)
		if dist < 0.001: dist = 0.001

		var slow: float = 0.7 if tremor_t[i] > 0.0 else 1.0
		var speed: float = spd[i] * slow

		# ---- 行为
		match beh:
			"ranged":
				var keep: float = float(t.get("keep_dist", 110))
				var dir: float = 1.0 if dist > keep else -1.0
				if blind_t[i] <= 0.0:
					vx[i] = dx / dist * speed * dir
					vy[i] = dy / dist * speed * dir
					timer[i] -= delta
					if timer[i] <= 0.0 and dist < keep * 2.2:
						timer[i] = float(t.get("shoot_cd", 2.6))
						_emit_shot(px[i], py[i], dx / dist, dy / dist, float(t.get("shot_speed", 150)), float(t.get("shot_damage", 7)))
				else:
					vx[i] = 0.0
					vy[i] = 0.0
			"dive":
				var wob: float = sin(Time.get_ticks_msec() * 0.004 + float(i)) * 0.35
				vx[i] = (dx / dist - dy / dist * wob) * speed
				vy[i] = (dy / dist + dx / dist * wob) * speed
			"charger":
				timer[i] -= delta
				if state[i] == 0 and timer[i] <= 0.0 and dist < 220.0:
					state[i] = 1
					timer[i] = float(t.get("charge_time", 0.55))
					vx[i] = dx / dist * float(t.get("charge_speed", 200))
					vy[i] = dy / dist * float(t.get("charge_speed", 200))
				elif state[i] == 1:
					if timer[i] <= 0.0:
						state[i] = 0
						timer[i] = float(t.get("charge_cd", 3.0))
				else:
					vx[i] = dx / dist * speed
					vy[i] = dy / dist * speed
			"boss":
				timer[i] -= delta
				vx[i] = dx / dist * speed
				vy[i] = dy / dist * speed
				if timer[i] <= 0.0:
					timer[i] = 2.4
					var ring: int = 10
					for k in range(ring):
						var a: float = TAU * float(k) / float(ring) + randf() * 0.2
						_emit_shot(px[i], py[i], cos(a), sin(a), 130.0, 9.0)
					if randf() < 0.5:
						_emit_summon(px[i] + randf_range(-40.0, 40.0), py[i] + randf_range(-40.0, 40.0), 2)
			_:
				vx[i] = dx / dist * speed
				vy[i] = dy / dist * speed

		if fear_t[i] > 0.0:
			vx[i] = -vx[i]
			vy[i] = -vy[i]

		var idle: bool = (beh == "ranged" and blind_t[i] > 0.0)
		if idle:
			vx[i] *= 0.2
			vy[i] *= 0.2

		px[i] += vx[i] * delta
		py[i] += vy[i] * delta
		vx[i] *= 0.86
		vy[i] *= 0.86

		# ---- 接触伤害：每只敌人独立冷却，避免同帧多体叠成一击
		if touch_cd[i] > 0.0:
			touch_cd[i] -= delta
		var rr: float = rad[i] + 7.0
		if dist < rr and touch_cd[i] <= 0.0:
			# 只吃「最强的那一下」，不做多体叠加，否则被围住就是秒杀
			contact = maxf(contact, dmg[i])
			touch_cd[i] = 0.8

	return contact

# ---- 供武器系统批量使用 ----

func damage_in_circle(cx: float, cy: float, radius: float, amount: float, status: String, dps: float, kb: float) -> int:
	var n: int = query(cx, cy, radius)
	var hits := 0
	# 倒序遍历，避免 swap_remove 打乱
	var idx: int = n - 1
	while idx >= 0:
		var i: int = query_buf[idx]
		if i >= 0 and i < count:
			var ddx: float = px[i] - cx
			var ddy: float = py[i] - cy
			if status != "":
				apply_status(i, status, dps)
			if kb > 0.0:
				knockback(i, ddx, ddy, kb)
			damage(i, amount)
			hits += 1
		idx -= 1
	return hits

func indices_in_circle(cx: float, cy: float, radius: float) -> PackedInt32Array:
	var n: int = query(cx, cy, radius)
	var out := PackedInt32Array()
	out.resize(n)
	for k in range(n):
		out[k] = query_buf[k]
	return out

func _emit_shot(x: float, y: float, dx: float, dy: float, speed: float, dmg_out: float) -> void:
	if shot_count >= 512:
		return
	var o: int = shot_count * 5
	shot_queue[o] = x; shot_queue[o + 1] = y
	shot_queue[o + 2] = dx * speed; shot_queue[o + 3] = dy * speed
	shot_queue[o + 4] = dmg_out
	shot_count += 1

func _emit_summon(x: float, y: float, ti: int) -> void:
	if summon_count >= 256:
		return
	var o: int = summon_count * 3
	summon_queue[o] = x; summon_queue[o + 1] = y; summon_queue[o + 2] = float(ti)
	summon_count += 1
