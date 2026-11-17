class_name BossAI
extends RefCounted
## BOSS 三阶段技能控制器（数据契约第 9 节）。
##
## 只读写 EnemySim / ProjectileSim 的 SoA 与请求队列，不碰场景树，
## 因此可以在 --headless 里独立跑；随机数全部走外部传入的 rng，同 seed 可复现。
##
## 契约：setup(enemies, idx, def, shots, rng) / tick(delta, ppos)
## 八种技能：ring_burst / aimed_shot / summon / charge /
##          zone_denial / heal_self / spawn_totem / nova
##
## 阶段：def.phases 按 at_hp 从高到低（1.0 / 0.66 / 0.33），
##      当前血量占比 <= at_hp 且比上一阶段更深时切阶段；
##      阶段可带 speed_mult（移速乘区）与 dr（受伤减免 0~1）。

const SKILL_IDS := ["ring_burst", "aimed_shot", "summon", "charge", "zone_denial", "heal_self", "spawn_totem", "nova"]

## 冲撞单段持续时间；多段冲撞之间的间隔
const CHARGE_DUR := 0.42
const CHARGE_GAP := 0.26
## 冲撞结束后的硬直，给玩家输出窗口
const CHARGE_STUN := 0.42

var enemies: EnemySim = null
var idx: int = -1
var def: Dictionary = {}
var shots: ProjectileSim = null
var rng: RandomNumberGenerator = null

var phases: Array = []
var phase: int = 0
var speed_mult: float = 1.0
var dr: float = 0.0
## 当前阶段每条技能的冷却剩余，下标与 phases[phase].skills 对齐
var cd: Array = []
## 延时齐射队列：{t, off, n, spread, speed, dmg}
var burst: Array = []

var charge_t: float = 0.0
var charge_gap: float = 0.0
var charge_speed: float = 0.0
var charge_dir: Vector2 = Vector2.ZERO
var charge_left: int = 0
var charge_bonus: float = 0.0
var stun_t: float = 0.0
var alive_t: float = 0.0

## REMNANT_BOSS_TRACE=1 时每 5 秒打印一次实际血量（无头标定用，正常游戏静默）
var trace: bool = false
var _trace_acc: float = 0.0
var _trace_hp0: float = 0.0

func setup(e: EnemySim, i: int, d: Dictionary, s: ProjectileSim, r: RandomNumberGenerator) -> void:
	enemies = e
	idx = i
	def = d
	shots = s
	rng = r if r != null else RandomNumberGenerator.new()
	phases = def.get("phases", [])
	burst = []
	charge_t = 0.0
	charge_gap = 0.0
	charge_left = 0
	charge_bonus = 0.0
	stun_t = 0.0
	alive_t = 0.0
	phase = -1
	_enter_phase(0, true)
	trace = OS.has_environment("REMNANT_BOSS_TRACE")
	_trace_acc = 0.0
	_trace_hp0 = float(enemies.max_hp[idx]) if idx >= 0 and idx < enemies.count else 0.0

# ---------------------------------------------------------------- 阶段

func _phase_def() -> Dictionary:
	if phase >= 0 and phase < phases.size():
		return phases[phase]
	return {}

func hp_ratio() -> float:
	if enemies == null or idx < 0 or idx >= enemies.count:
		return 0.0
	return clampf(float(enemies.hp[idx]) / maxf(float(enemies.max_hp[idx]), 0.0001), 0.0, 1.0)

func _enter_phase(p: int, first: bool = false) -> void:
	phase = clampi(p, 0, maxi(phases.size() - 1, 0))
	var pd: Dictionary = _phase_def()
	speed_mult = float(pd.get("speed_mult", 1.0))
	dr = clampf(float(pd.get("dr", 0.0)), 0.0, 0.9)
	var list: Array = pd.get("skills", [])
	cd = []
	for s in list:
		var c: float = maxf(float(s.get("cd", 3.0)), 0.25)
		# 开场稍作蓄力，换阶段时给 0.3 秒热身，避免瞬移式秒人
		cd.append(c * (0.5 if first else 0.3))

func _update_phase() -> void:
	if phases.size() <= 1:
		return
	var r: float = hp_ratio()
	var want: int = 0
	for k in range(phases.size()):
		if r <= float(phases[k].get("at_hp", 1.0)) + 0.0001:
			want = k
	if want > phase:
		_enter_phase(want)
		# 换阶段的宣告：一圈慢速环弹 + 一圈碎石，给玩家一个明确的"阶段变了"信号
		_ring_burst({ "count": 12, "damage": 6.0, "speed": 95.0 })

# ---------------------------------------------------------------- 每帧

func tick(delta: float, ppos: Vector2) -> void:
	if enemies == null:
		return
	# 单驱动保护：EnemySim 在 spawn 时已经注册了它自己的实例并每帧 tick。
	# run 侧若另建实例（src/run.gd 的 _ensure_boss_ai）再 tick 一次，会让技能频率翻倍、
	# 且槽位搬移后 idx 失配，所以这里只允许「注册在敌人身上的那一个」出手。
	if enemies.boss_ai == null:
		enemies.boss_ai = self
		enemies.boss_idx = idx
	elif enemies.boss_ai != self:
		return
	if idx < 0 or idx >= enemies.count:
		return
	if float(enemies.hp[idx]) <= 0.0:
		return
	alive_t += delta
	_update_phase()
	var dx: float = ppos.x - enemies.px[idx]
	var dy: float = ppos.y - enemies.py[idx]
	var dist: float = maxf(sqrt(dx * dx + dy * dy), 0.001)
	var dir := Vector2(dx / dist, dy / dist)
	_tick_move(delta, dir, dist)
	_tick_skills(delta, ppos, dir)
	_tick_burst(delta)
	_tick_trace(delta)

func _tick_move(delta: float, dir: Vector2, dist: float) -> void:
	if charge_t > 0.0:
		charge_t -= delta
		enemies.vx[idx] = charge_dir.x * charge_speed
		enemies.vy[idx] = charge_dir.y * charge_speed
		if charge_t <= 0.0:
			charge_t = 0.0
			if charge_left > 1:
				charge_left -= 1
				charge_gap = CHARGE_GAP
			else:
				charge_left = 0
				_restore_charge_damage()
				stun_t = CHARGE_STUN
		return
	if charge_gap > 0.0:
		charge_gap -= delta
		enemies.vx[idx] = 0.0
		enemies.vy[idx] = 0.0
		if charge_gap <= 0.0:
			charge_gap = 0.0
			_start_charge(dir)
		return
	if stun_t > 0.0:
		stun_t -= delta
		enemies.vx[idx] = 0.0
		enemies.vy[idx] = 0.0
		return
	# 站位：BOSS 倾向保持中距离放技能（阶段越深越压前），把"贴脸站桩挨打"变成
	# "追进内圈换输出窗口"的博弈；冲撞与硬直阶段会打破这个站位。
	var spd: float = float(enemies.spd[idx]) * speed_mult
	var pref: float = clampf(118.0 - 12.0 * float(maxi(phase, 0)), 92.0, 125.0)
	if dist > pref + 22.0:
		# 追击速度给下限：数据里 BOSS 的 speed 只有 40-60，玩家跑位会把距离拉到 200px 外，
		# 那样长枪短炮全打空，关底变成"跑满 90 秒"。下限让 BOSS 至少跟得上玩家的绕圈。
		var chase: float = maxf(spd * 1.35, 110.0)
		enemies.vx[idx] = dir.x * chase
		enemies.vy[idx] = dir.y * chase
	elif dist < pref - 26.0:
		# 太近就后撤（负向速度），避免被近战武器白吃
		enemies.vx[idx] = -dir.x * spd * 0.9
		enemies.vy[idx] = -dir.y * spd * 0.9
	else:
		# 中距离侧移绕圈，玩家必须主动追
		enemies.vx[idx] = -dir.y * spd * 0.55
		enemies.vy[idx] = dir.x * spd * 0.55

func _tick_skills(delta: float, ppos: Vector2, dir: Vector2) -> void:
	var list: Array = _phase_def().get("skills", [])
	var n: int = mini(cd.size(), list.size())
	for k in range(n):
		cd[k] = float(cd[k]) - delta
		if float(cd[k]) > 0.0:
			continue
		var s: Dictionary = list[k]
		cd[k] = maxf(float(s.get("cd", 3.0)), 0.25)
		_cast(String(s.get("id", "")), s.get("params", {}), ppos, dir)

func _cast(id: String, p: Dictionary, ppos: Vector2, dir: Vector2) -> void:
	match id:
		"ring_burst":
			_ring_burst(p)
		"aimed_shot":
			_aimed_shot(p, dir)
		"summon":
			_summon(p)
		"charge":
			_charge(p, dir)
		"zone_denial":
			_zone_denial(p, ppos)
		"heal_self":
			_heal_self(p)
		"spawn_totem":
			_spawn_totem(p)
		"nova":
			_nova(p)
		_:
			_ring_burst({})

# ---------------------------------------------------------------- 八种技能

## 环弹：以自身为圆心均匀铺开，起始角随机（同 seed 可复现）
func _ring_burst(p: Dictionary) -> void:
	var cnt: int = maxi(int(p.get("count", 8)), 1)
	var dmg: float = float(p.get("damage", 6.0))
	var spd: float = float(p.get("speed", 130.0))
	var a0: float = rng.randf() * TAU
	for k in range(cnt):
		var a: float = a0 + TAU * float(k) / float(cnt)
		_shoot(cos(a), sin(a), spd, dmg)

## 瞄准点射：连发 count 颗，每颗间隔 0.09 秒并带一点扇角，读起来就是"三连点射"
func _aimed_shot(p: Dictionary, dir: Vector2) -> void:
	var cnt: int = maxi(int(p.get("count", 3)), 1)
	var spd: float = float(p.get("speed", 170.0))
	var dmg: float = float(p.get("damage", 8.0))
	var spread: float = deg_to_rad(float(p.get("spread_deg", 7.0)))
	for k in range(cnt):
		burst.append({
			"t": 0.09 * float(k),
			"off": (float(k) - float(cnt - 1) * 0.5) * spread,
			"n": 1,
			"spread": 0.0,
			"speed": spd,
			"dmg": dmg,
			"dir": dir
		})

## 召唤：params.enemy 是 enemies.json 的 id，n 只数
func _summon(p: Dictionary) -> void:
	var eid: String = String(p.get("enemy", ""))
	var ti: int = enemies.type_index_of(eid)
	if ti < 0:
		return
	var n: int = maxi(int(p.get("n", 2)), 1)
	for k in range(n):
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(42.0, 92.0)
		enemies._emit_summon(enemies.px[idx] + cos(a) * d, enemies.py[idx] + sin(a) * d, ti)

## 冲撞：可多段；冲撞期间接触伤害临时提高，结束回落到原值
func _charge(p: Dictionary, dir: Vector2) -> void:
	if charge_t > 0.0 or charge_gap > 0.0:
		return
	charge_left = maxi(int(p.get("count", 1)), 1)
	charge_speed = float(p.get("speed", 240.0))
	charge_bonus = float(p.get("damage", 10.0))
	enemies.dmg[idx] = float(enemies.dmg[idx]) + charge_bonus
	_start_charge(dir)

func _start_charge(dir: Vector2) -> void:
	charge_dir = dir if dir.length_squared() > 0.0001 else Vector2.RIGHT
	charge_t = CHARGE_DUR

func _restore_charge_damage() -> void:
	if charge_bonus <= 0.0:
		return
	enemies.dmg[idx] = maxf(float(enemies.dmg[idx]) - charge_bonus, 0.0)
	charge_bonus = 0.0

## 地面禁入：在玩家脚下落 count 个持续伤害坑（有 0.5 秒预警窗口）
func _zone_denial(p: Dictionary, ppos: Vector2) -> void:
	var cnt: int = maxi(int(p.get("count", 1)), 1)
	var radius: float = float(p.get("radius", 140.0))
	var dmg: float = float(p.get("damage", 6.0))
	var dur: float = float(p.get("duration", 6.0))
	var tick: float = maxf(float(p.get("tick", 1.0)), 0.25)
	for k in range(cnt):
		var a: float = rng.randf() * TAU
		var d: float = 0.0 if cnt == 1 else rng.randf_range(30.0, 110.0)
		enemies.add_hazard(ppos.x + cos(a) * d, ppos.y + sin(a) * d, radius, dmg, dur, tick, "zone", Color("#7B3FA0"), 0.5)

## 自愈：按最大生命百分比回血
func _heal_self(p: Dictionary) -> void:
	# 回血有上限：最多抬到 85% 最大血，且不能把 CD 变成「打不死」的护盾。
	var pct: float = float(p.get("pct", 0.06))
	var cap: float = float(enemies.max_hp[idx]) * 0.85
	if float(enemies.hp[idx]) >= cap:
		return
	var amount: float = float(enemies.max_hp[idx]) * pct
	enemies.hp[idx] = minf(float(enemies.hp[idx]) + amount, cap)
	enemies.add_hazard(enemies.px[idx], enemies.py[idx], float(enemies.rad[idx]) + 36.0, 0.0, 0.7, 0.7, "heal", Color("#F3E3A8"), 0.0)

## 图腾：召唤 count 根可打碎的柱子，存活期间 BOSS 获得额外减伤（EnemySim.shield_dr）
func _spawn_totem(p: Dictionary) -> void:
	var cnt: int = maxi(int(p.get("count", 2)), 1)
	var hp: float = float(p.get("hp", 140.0))
	var dur: float = float(p.get("duration", 15.0))
	for k in range(cnt):
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(64.0, 118.0)
		enemies.spawn_totem(enemies.px[idx] + cos(a) * d, enemies.py[idx] + sin(a) * d, hp, dur)

## 新星：以自身为圆心的一次性范围爆发（有 0.35 秒预警）
func _nova(p: Dictionary) -> void:
	var radius: float = float(p.get("radius", 130.0))
	var dmg: float = float(p.get("damage", 12.0))
	enemies.add_hazard(enemies.px[idx], enemies.py[idx], radius, dmg, 0.4, 0.4, "nova", Color("#E0B85A"), 0.35)

# ---------------------------------------------------------------- 内部

func _shoot(dx: float, dy: float, speed: float, dmg: float) -> void:
	var x: float = float(enemies.px[idx])
	var y: float = float(enemies.py[idx])
	if shots != null:
		shots.spawn(x, y, dx, dy, speed, dmg, false, {
			"life": 4.0,
			"radius": 2.8,
			"size": 3.4,
			"color": ProjectileSim.COL_ENEMY
		})
	else:
		enemies._emit_shot(x, y, dx, dy, speed, dmg)

func _tick_burst(delta: float) -> void:
	if burst.is_empty():
		return
	var i: int = burst.size() - 1
	while i >= 0:
		var b: Dictionary = burst[i]
		b["t"] = float(b["t"]) - delta
		if float(b["t"]) <= 0.0:
			var dir: Vector2 = b["dir"]
			var a: float = dir.angle() + float(b["off"])
			_shoot(cos(a), sin(a), float(b["speed"]), float(b["dmg"]))
			burst.remove_at(i)
		i -= 1

## 图腾存活时的额外减伤（图腾打掉即消失，逼玩家先清场）
func shield_dr() -> float:
	if enemies == null:
		return 0.0
	return 0.2 if enemies.totem_count > 0 else 0.0

## 技能乘区（留给后续难度/七印扩展；当前恒为 1）
func _tick_trace(delta: float) -> void:
	if not trace:
		return
	_trace_acc += delta
	if _trace_acc < 2.0:
		return
	_trace_acc = 0.0
	print("[boss] t=%.1f hp=%.0f/%.0f pct=%.2f phase=%d dmgtaken=%.0f" % [alive_t, float(enemies.hp[idx]), _trace_hp0, hp_ratio(), phase, enemies.boss_dmg_taken])
