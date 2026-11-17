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
## 区域减速：剩余秒数与速度倍率（活水 tidal_push 等持续刷新，1.0 = 不减速）
var slow_t: PackedFloat32Array
var slow_mul: PackedFloat32Array

# 行为计时与本帧输出
var timer: PackedFloat32Array
var state: PackedInt32Array
var touch_cd: PackedFloat32Array
## 俯冲锁定方向（dive 行为专用：起手时锁定角度，冲刺阶段不再追人）
var dive_a: PackedFloat32Array
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 本局累计模拟时间（秒）。任何计时都读它，禁止 Time.get_ticks_msec()——否则同种子不同机器出不同结果。
var sim_time: float = 0.0
## 本帧最强接触伤害是否来自精英 / BOSS（run 侧据此放宽单次上限）。
var contact_elite: bool = false
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

# ---- BOSS 控制器（每关最多一只；SoA 被 _swap_remove 搬动时索引会迁移）
var boss_ai: BossAI = null
var boss_idx: int = -1

# ---- 精英词条：按类型预解码成位掩码，避免每帧比中文字符串
const AFFIX_ARMOR := 1      ## 护甲：受击 -30%
const AFFIX_SUMMON := 2     ## 召唤：每 6 秒召 2 只护卫
const AFFIX_QUAKE := 4      ## 震地：每 4.5 秒一圈冲击波
const AFFIX_AURA := 8       ## 光环：周围小怪加速 25% / 加伤 25%
const AFFIX_SPLIT := 16     ## 分裂：死亡时分裂 4 只溺水暗影
const AFFIX_TELEPORT := 32  ## 瞬移：贴近 90px 时贴脸突刺
const AFFIX_RING := 64      ## 重踏：每 4 秒 6 颗环形巨石
const AFFIX_PILLAR := 128   ## 火柱：每 5 秒在玩家脚下落火柱
var affix_flags: PackedInt32Array

# ---- 图腾：totem_t > 0 表示这是召唤柱（不动、不打人、到期静默消失）
var totem_t: PackedFloat32Array
var totem_count: int = 0

# ---- 场地危害（BOSS 技能 / 精英火柱）：{x,y,r,dmg,life,tick,tick_t,kind,color}
var hazards: Array = []

# ---- 光环笼罩剩余时间（被精英加成的普通怪）
var haste_t: PackedFloat32Array
var affix_t: PackedFloat32Array

# ---- 灼烧叠层上限，由武器层按被动 burn_stack_max 覆写
var burn_cap: int = 5

# ---- BOSS 累计承伤（遥测用，REMNANT_BOSS_TRACE 打印）
var boss_dmg_taken: float = 0.0

# ---- 精英词条主动技能总开关。REMNANT_NO_AFFIX=1 时关闭（光环/瞬移/召唤/震地/环形/火柱/分裂），
#      供平衡排查时把「精英机制太狠」和「章节预算太狠」分开归因。
var affix_enabled: bool = true

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
	timer.resize(CAPACITY); state.resize(CAPACITY); touch_cd.resize(CAPACITY); dive_a.resize(CAPACITY)
	totem_t.resize(CAPACITY); affix_t.resize(CAPACITY); haste_t.resize(CAPACITY)
	slow_t.resize(CAPACITY); slow_mul.resize(CAPACITY)
	affix_flags.resize(types.size())
	for k in range(types.size()):
		affix_flags[k] = _decode_affix(String(types[k].get("elite_affix", "")))
	hazards = []
	boss_ai = null
	boss_idx = -1
	totem_count = 0
	burn_cap = 5
	boss_dmg_taken = 0.0
	# 确定性：时钟与重击标记随本局重置，同一 seed + 同一命令逐位一致
	sim_time = 0.0
	contact_elite = false
	affix_enabled = OS.get_environment("REMNANT_NO_AFFIX") != "1"
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
	hazards = []
	boss_ai = null
	boss_idx = -1
	totem_count = 0
	burn_cap = 5
	sim_time = 0.0
	contact_elite = false

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
	timer[i] = rng.randf() * 1.5
	state[i] = 0
	touch_cd[i] = 0.0
	dive_a[i] = 0.0
	totem_t[i] = 0.0
	haste_t[i] = 0.0
	slow_t[i] = 0.0
	slow_mul[i] = 1.0
	affix_t[i] = rng.randf() * 1.5
	# BOSS 自带三阶段技能控制器：挂在模拟层内，run 侧无需接线
	if String(t.get("behavior", "")) == "boss":
		boss_ai = BossAI.new()
		boss_ai.setup(self, i, t, null, rng)
		boss_idx = i
	return i

func _swap_remove(i: int) -> void:
	var last: int = count - 1
	if totem_t[i] != 0.0:
		totem_count = maxi(totem_count - 1, 0)
	if i != last:
		px[i] = px[last]; py[i] = py[last]; vx[i] = vx[last]; vy[i] = vy[last]
		hp[i] = hp[last]; max_hp[i] = max_hp[last]; spd[i] = spd[last]; dmg[i] = dmg[last]
		rad[i] = rad[last]; typ[i] = typ[last]; flash[i] = flash[last]; armor_shred[i] = armor_shred[last]
		burn_stack[i] = burn_stack[last]; burn_t[i] = burn_t[last]; burn_dps[i] = burn_dps[last]
		tremor_t[i] = tremor_t[last]; blind_t[i] = blind_t[last]; wet_t[i] = wet_t[last]; fear_t[i] = fear_t[last]
		timer[i] = timer[last]; state[i] = state[last]; touch_cd[i] = touch_cd[last]; dive_a[i] = dive_a[last]
		totem_t[i] = totem_t[last]; haste_t[i] = haste_t[last]; affix_t[i] = affix_t[last]
		slow_t[i] = slow_t[last]; slow_mul[i] = slow_mul[last]
	# BOSS 索引迁移：被删的正好是 BOSS 就释放控制器，否则把控制器的 idx 跟到新槽位
	if boss_idx >= 0:
		if i == boss_idx:
			boss_idx = -1
			boss_ai = null
		elif i < boss_idx and last == boss_idx:
			boss_idx = i
			if boss_ai != null:
				boss_ai.idx = i
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
	# 精英「分裂」词条：死亡时原地分裂出 4 只溺水暗影
	if affix_enabled and affix_flags[typ[i]] & AFFIX_SPLIT != 0:
		var sti: int = type_ids.find("drowned_shade")
		if sti >= 0:
			for k in range(4):
				var a: float = TAU * float(k) / 4.0 + rng.randf() * 0.35
				_emit_summon(px[i] + cos(a) * 24.0, py[i] + sin(a) * 24.0, sti)

## 约 · 宝座前七灵：敌人每带 1 种异常状态，承受伤害独立 ×(1+bonus)（0 = 关闭）
var status_dmg_bonus: float = 0.0

func status_count(i: int) -> int:
	var n: int = 0
	if burn_t[i] > 0.0: n += 1
	if tremor_t[i] > 0.0: n += 1
	if blind_t[i] > 0.0: n += 1
	if wet_t[i] > 0.0: n += 1
	if fear_t[i] > 0.0: n += 1
	return n

## 造成伤害。返回是否击杀。
func damage(i: int, amount: float) -> bool:
	if i < 0 or i >= count:
		return false
	if status_dmg_bonus > 0.0:
		var sc: int = status_count(i)
		if sc > 0:
			amount *= pow(1.0 + status_dmg_bonus, float(sc))
	if i == boss_idx:
		boss_dmg_taken += amount
	if i == boss_idx and boss_ai != null:
		amount *= 1.0 - clampf(boss_ai.dr + boss_ai.shield_dr(), 0.0, 0.85)
	elif affix_flags[typ[i]] & AFFIX_ARMOR != 0:
		amount *= 0.7
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
			burn_stack[i] = mini(burn_stack[i] + 1, maxi(burn_cap, 1))
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

## 区域减速（活水等）：中心 (cx,cy) 半径 r 内敌人限速到 mult，持续 dur 秒。
## 只写状态数组、不消耗 rng，因此不改变既有种子的随机流。
func slow_area(cx: float, cy: float, r: float, mult: float, dur: float) -> void:
	if mult >= 1.0 or mult <= 0.0 or dur <= 0.0:
		return
	var ids: PackedInt32Array = indices_in_circle(cx, cy, r)
	for i in ids:
		if i < 0 or i >= count:
			continue
		slow_mul[i] = mult if slow_t[i] <= 0.0 else minf(slow_mul[i], mult)
		slow_t[i] = maxf(slow_t[i], dur)

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
	sim_time += delta
	var contact := 0.0
	contact_elite = false
	var hz_dmg: float = _tick_hazards(delta, ppos)
	if hz_dmg > 0.0:
		# 场地危害只由 BOSS / 精英技能落下，按重击来源处理
		contact = maxf(contact, hz_dmg)
		contact_elite = true
	var i: int = 0
	while i < count:
		var t: Dictionary = types[typ[i]]
		var beh: String = String(t.get("behavior", "chase"))

		# ---- 状态衰减
		if flash[i] > 0.0:
			flash[i] = maxf(flash[i] - delta, 0.0)
		if burn_t[i] > 0.0:
			burn_t[i] -= delta
			hp[i] -= burn_dps[i] * float(burn_stack[i]) * delta * dot_mult
			if hp[i] <= 0.0:
				_kill_index(i)
				continue
		if tremor_t[i] > 0.0: tremor_t[i] -= delta
		if blind_t[i] > 0.0: blind_t[i] -= delta
		if wet_t[i] > 0.0: wet_t[i] -= delta
		if fear_t[i] > 0.0: fear_t[i] -= delta
		if haste_t[i] > 0.0: haste_t[i] -= delta
		if slow_t[i] > 0.0: slow_t[i] -= delta

		# ---- 图腾：站桩、不造成接触伤害，寿命结束静默消失
		if totem_t[i] > 0.0:
			totem_t[i] -= delta
			if totem_t[i] <= 0.0:
				_swap_remove(i)
				continue
			vx[i] = 0.0
			vy[i] = 0.0
			i += 1
			continue

		var dx: float = ppos.x - px[i]
		var dy: float = ppos.y - py[i]
		var dist: float = sqrt(dx * dx + dy * dy)
		if dist < 0.001: dist = 0.001

		# ---- 精英词条（12 种精英按 elite_affix 文本解码，见 _decode_affix）
		var fl: int = affix_flags[typ[i]]
		if fl != 0:
			_tick_affix(i, fl, delta, ppos, dx, dy, dist)

		var slow: float = 0.7 if tremor_t[i] > 0.0 else 1.0
		if slow_t[i] > 0.0: slow = minf(slow, slow_mul[i])
		var haste: float = 1.25 if haste_t[i] > 0.0 else 1.0
		var speed: float = spd[i] * slow * haste

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
						_emit_fan(i, t, dx / dist, dy / dist, dist)
				else:
					vx[i] = 0.0
					vy[i] = 0.0
			"dive":
				# 盘旋 → 起手 → 锁定方向冲刺 → 拉开，冲刺之外不贴身，避免「比玩家快的敌人」变成永久接触伤害
				var hover: float = float(t.get("hover_dist", 88.0))
				var tang: float = sin(sim_time * 0.9 + float(i)) * 0.5
				timer[i] -= delta
				if state[i] == 0:
					var ring: float = 1.0 if dist > hover else -1.0
					vx[i] = (dx / dist * ring - dy / dist * tang) * speed * 0.75
					vy[i] = (dy / dist * ring + dx / dist * tang) * speed * 0.75
					if dist < hover + 34.0 and timer[i] <= 0.0:
						state[i] = 1
						timer[i] = 0.45
				elif state[i] == 1:
					vx[i] = 0.0
					vy[i] = 0.0
					dive_a[i] = atan2(dy, dx)
					if timer[i] <= 0.0:
						state[i] = 2
						timer[i] = 0.34
				elif state[i] == 2:
					vx[i] = cos(dive_a[i]) * speed * 3.2
					vy[i] = sin(dive_a[i]) * speed * 3.2
					if timer[i] <= 0.0:
						state[i] = 3
						timer[i] = 0.85
				else:
					vx[i] = -dx / dist * speed * 0.9
					vy[i] = -dy / dist * speed * 0.9
					if timer[i] <= 0.0:
						state[i] = 0
						timer[i] = rng.randf_range(0.4, 1.2)
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
				if boss_ai != null and i == boss_idx:
					# 三阶段技能控制器接管移动与出招（data/bosses.json 的 phases）
					boss_ai.tick(delta, ppos)
				else:
					# 兜底：没有控制器时仍按旧的环弹行为跑，保证不空转
					timer[i] -= delta
					vx[i] = dx / dist * speed
					vy[i] = dy / dist * speed
					if timer[i] <= 0.0:
						timer[i] = 2.4
						var ring: int = 10
						for k in range(ring):
							var a: float = TAU * float(k) / float(ring) + rng.randf() * 0.2
							_emit_shot(px[i], py[i], cos(a), sin(a), 130.0, 9.0)
			_:
				vx[i] = dx / dist * speed
				vy[i] = dy / dist * speed

		if beh != "boss":
			if fear_t[i] > 0.0:
				vx[i] = -vx[i]
				vy[i] = -vy[i]
			if beh == "ranged" and blind_t[i] > 0.0:
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
			var hit_dmg: float = dmg[i] * haste
			if hit_dmg > contact:
				contact = hit_dmg
				# 契约 3.1：只有精英 / BOSS 的接触才允许放宽到 18.0
				contact_elite = is_elite(i) or is_boss(i)
			touch_cd[i] = 0.8
		i += 1

	return contact

## 远程敌人通用齐射：count / spread_deg / shot_speed / shot_damage 全部可以只靠数据表达。
## 数据没写这些键时，退化成原来的单发直射，老敌人行为不变。
func _emit_fan(i: int, t: Dictionary, dxn: float, dyn: float, dist: float) -> void:
	var n: int = maxi(int(t.get("count", 1)), 1)
	var spread: float = deg_to_rad(float(t.get("spread_deg", 12.0)))
	var spd: float = float(t.get("shot_speed", 150))
	var dmg_out: float = float(t.get("shot_damage", 6))
	var keep: float = float(t.get("keep_dist", 110))
	if dist > keep * 2.2:
		return
	for k in range(n):
		var off: float = 0.0
		if n > 1:
			off = (float(k) - float(n - 1) * 0.5) * spread
		var ca: float = cos(off)
		var sa: float = sin(off)
		_emit_shot(px[i], py[i], dxn * ca - dyn * sa, dxn * sa + dyn * ca, spd, dmg_out)

# ---------------------------------------------------------------- 击杀 / 危害 / 精英

func _kill_index(i: int) -> void:
	# 故意不前进 i：swap_remove 把最后一个敌人搬进当前槽位，下一轮立刻处理它
	_record_death(i)
	_swap_remove(i)

## BOSS / 精英技能落下的场地危害。delay 是预警时间；dmg 为 0 时只当特效标记。
func add_hazard(x: float, y: float, radius: float, dmg_out: float, life: float, tick: float, kind: String, color: Color, delay: float = 0.0) -> void:
	if hazards.size() >= 48:
		return
	hazards.append({
		"x": x, "y": y, "r": radius, "dmg": dmg_out,
		"life": life, "tick": maxf(tick, 0.2), "tick_t": maxf(delay, 0.0),
		"kind": kind, "color": color
	})

func _tick_hazards(delta: float, ppos: Vector2) -> float:
	if hazards.is_empty():
		return 0.0
	var out := 0.0
	var i: int = hazards.size() - 1
	while i >= 0:
		var h: Dictionary = hazards[i]
		h["life"] = float(h["life"]) - delta
		if float(h["life"]) <= 0.0:
			hazards.remove_at(i)
			i -= 1
			continue
		h["tick_t"] = float(h["tick_t"]) - delta
		var rr: float = float(h["r"]) + 7.0
		var hx: float = ppos.x - float(h["x"])
		var hy: float = ppos.y - float(h["y"])
		if hx * hx + hy * hy <= rr * rr and float(h["tick_t"]) <= 0.0:
			h["tick_t"] = float(h.get("tick", 1.0))
			out = maxf(out, float(h["dmg"]))
		i -= 1
	return out

## 召唤一根可打碎的图腾柱：不动、不造成接触伤害，life 秒后静默消失。
## 外形借 enemies.json 里的 brick_golem（缺此 id 时退回血量最高的普通怪），不改数据结构。
func spawn_totem(x: float, y: float, hp_override: float, life: float) -> int:
	var ti: int = type_ids.find("brick_golem")
	if ti < 0:
		var best: float = -1.0
		for k in range(types.size()):
			var d: Dictionary = types[k]
			if bool(d.get("elite", false)) or String(d.get("behavior", "")) == "boss":
				continue
			if float(d.get("hp", 0)) > best:
				best = float(d.get("hp", 0))
				ti = k
	if ti < 0:
		return -1
	var i: int = spawn(ti, x, y)
	if i < 0:
		return -1
	hp[i] = hp_override
	max_hp[i] = hp_override
	rad[i] = 10.0
	spd[i] = 0.0
	dmg[i] = 0.0
	totem_t[i] = maxf(life, 1.0)
	totem_count += 1
	return i

## 把 data/enemies.json 的中文 elite_affix 解码成位掩码；没有词条的普通怪为 0。
func _decode_affix(text: String) -> int:
	if text == "":
		return 0
	var f: int = 0
	if text.contains("护甲"): f |= AFFIX_ARMOR
	if text.contains("召唤"): f |= AFFIX_SUMMON
	if text.contains("震地"): f |= AFFIX_QUAKE
	if text.contains("加速"): f |= AFFIX_AURA
	if text.contains("分裂"): f |= AFFIX_SPLIT
	if text.contains("瞬移"): f |= AFFIX_TELEPORT
	if text.contains("环形"): f |= AFFIX_RING
	if text.contains("火柱"): f |= AFFIX_PILLAR
	return f

## 精英词条每帧推进：光环常驻、瞬移看距离、其余按自身计时器触发。
func _tick_affix(i: int, fl: int, delta: float, ppos: Vector2, dx: float, dy: float, dist: float) -> void:
	if not affix_enabled:
		return
	if fl & AFFIX_AURA != 0:
		_apply_aura(i)
	if fl & AFFIX_TELEPORT != 0:
		if state[i] == 1:
			affix_t[i] = maxf(affix_t[i] - delta, 0.0)
			if affix_t[i] <= 0.0:
				state[i] = 0
		elif dist < 90.0:
			# 瞬移突刺：贴到玩家身侧 34px，随后 2.5 秒冷却
			var a: float = rng.randf() * TAU
			px[i] = ppos.x + cos(a) * 34.0
			py[i] = ppos.y + sin(a) * 34.0
			vx[i] = 0.0
			vy[i] = 0.0
			state[i] = 1
			affix_t[i] = 2.5
	if fl & (AFFIX_SUMMON | AFFIX_QUAKE | AFFIX_RING | AFFIX_PILLAR) != 0:
		affix_t[i] = maxf(affix_t[i] - delta, 0.0)
		if affix_t[i] > 0.0:
			return
		if fl & AFFIX_SUMMON != 0:
			affix_t[i] = 6.0
			var ti: int = type_ids.find("brick_golem")
			if ti >= 0:
				for k in range(2):
					var a2: float = rng.randf() * TAU
					_emit_summon(px[i] + cos(a2) * 34.0, py[i] + sin(a2) * 34.0, ti)
		elif fl & AFFIX_QUAKE != 0:
			affix_t[i] = 4.5
			for k in range(8):
				var a3: float = rng.randf() * TAU + TAU * float(k) / 8.0
				_emit_shot(px[i], py[i], cos(a3), sin(a3), 62.0, 5.0)
		elif fl & AFFIX_RING != 0:
			affix_t[i] = 4.0
			for k in range(6):
				var a4: float = TAU * float(k) / 6.0
				_emit_shot(px[i], py[i], cos(a4), sin(a4), 80.0, 6.0)
		elif fl & AFFIX_PILLAR != 0:
			affix_t[i] = 5.0
			add_hazard(ppos.x, ppos.y, 44.0, 7.0, 1.4, 0.5, "pillar", Color("#E0731A"), 0.65)

## 光环：给 170px 内的普通怪挂 0.4 秒加速/加伤（每帧续挂，离开即失效）。
func _apply_aura(i: int) -> void:
	var n: int = query(px[i], py[i], 170.0)
	for k in range(n):
		var j: int = query_buf[k]
		if j != i and affix_flags[typ[j]] == 0:
			haste_t[j] = 0.4

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
			if absf(kb) > 0.01:
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
