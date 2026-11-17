class_name ProjectileSim
extends RefCounted
## 投射物模拟：玩家弹幕与敌人弹幕共用一套 SoA 数组，靠 friendly 区分。

const CAPACITY := 1400

var count: int = 0
var px: PackedFloat32Array
var py: PackedFloat32Array
var vx: PackedFloat32Array
var vy: PackedFloat32Array
var dmg: PackedFloat32Array
var life: PackedFloat32Array
var pierce: PackedInt32Array
var rad: PackedFloat32Array
var size: PackedFloat32Array
var friendly: PackedByteArray
var homing: PackedFloat32Array
var status: PackedInt32Array   # 0 无 / 1 burn / 2 tremor / 3 blind / 4 wet / 5 fear
var dps: PackedFloat32Array
var kb: PackedFloat32Array
var color: PackedInt32Array    # 0 圣石 1 音 2 火 3 水 4 敌弹
var splash_r: PackedFloat32Array
var splash_dmg: PackedFloat32Array

const STATUS_NAMES := ["", "burn", "tremor", "blind", "wet", "fear"]
const COL_STONE := 0
const COL_SOUND := 1
const COL_FIRE := 2
const COL_WATER := 3
const COL_ENEMY := 4

func setup() -> void:
	px.resize(CAPACITY); py.resize(CAPACITY); vx.resize(CAPACITY); vy.resize(CAPACITY)
	dmg.resize(CAPACITY); life.resize(CAPACITY); pierce.resize(CAPACITY); rad.resize(CAPACITY)
	size.resize(CAPACITY); friendly.resize(CAPACITY); homing.resize(CAPACITY)
	status.resize(CAPACITY); dps.resize(CAPACITY); kb.resize(CAPACITY); color.resize(CAPACITY)
	splash_r.resize(CAPACITY); splash_dmg.resize(CAPACITY)
	count = 0

func clear() -> void:
	count = 0

func status_code(name: String) -> int:
	return STATUS_NAMES.find(name)

func spawn(x: float, y: float, dir_x: float, dir_y: float, speed: float, dmg_out: float, is_friendly: bool, opts: Dictionary) -> void:
	if count >= CAPACITY:
		return
	var i: int = count
	count += 1
	var l: float = sqrt(dir_x * dir_x + dir_y * dir_y)
	if l < 0.0001: l = 1.0
	px[i] = x; py[i] = y
	vx[i] = dir_x / l * speed
	vy[i] = dir_y / l * speed
	dmg[i] = dmg_out
	life[i] = float(opts.get("life", 1.6))
	pierce[i] = int(opts.get("pierce", 0))
	rad[i] = float(opts.get("radius", 3.0))
	size[i] = float(opts.get("size", 3.0))
	friendly[i] = 1 if is_friendly else 0
	homing[i] = float(opts.get("homing", 0.0))
	status[i] = int(opts.get("status", 0))
	dps[i] = float(opts.get("dps", 0.0))
	kb[i] = float(opts.get("kb", 0.0))
	color[i] = int(opts.get("color", 0))
	splash_r[i] = float(opts.get("splash_r", 0.0))
	splash_dmg[i] = float(opts.get("splash_dmg", 0.0))

func _swap_remove(i: int) -> void:
	var last: int = count - 1
	if i != last:
		px[i] = px[last]; py[i] = py[last]; vx[i] = vx[last]; vy[i] = vy[last]
		dmg[i] = dmg[last]; life[i] = life[last]; pierce[i] = pierce[last]; rad[i] = rad[last]
		size[i] = size[last]; friendly[i] = friendly[last]; homing[i] = homing[last]
		status[i] = status[last]; dps[i] = dps[last]; kb[i] = kb[last]; color[i] = color[last]
		splash_r[i] = splash_r[last]; splash_dmg[i] = splash_dmg[last]
	count -= 1

## 推进并结算对敌人的命中。hit_callback 用于特效/音效（可选）。
func update(delta: float, enemies: EnemySim, on_hit: Callable = Callable()) -> void:
	var i: int = count - 1
	while i >= 0:
		if life[i] <= 0.0:
			_swap_remove(i)
			i -= 1
			continue
		life[i] -= delta
		px[i] += vx[i] * delta
		py[i] += vy[i] * delta

		if friendly[i] == 1 and homing[i] > 0.0:
			var n: int = enemies.query(px[i], py[i], 180.0)
			var best: int = -1
			var best_d: float = 1e9
			for k in range(n):
				var j: int = enemies.query_buf[k]
				var ddx: float = enemies.px[j] - px[i]
				var ddy: float = enemies.py[j] - py[i]
				var d2: float = ddx * ddx + ddy * ddy
				if d2 < best_d:
					best_d = d2
					best = j
			if best >= 0:
				var tx: float = enemies.px[best] - px[i]
				var ty: float = enemies.py[best] - py[i]
				var tl: float = sqrt(tx * tx + ty * ty)
				if tl > 0.001:
					var sp: float = sqrt(vx[i] * vx[i] + vy[i] * vy[i])
					var cur_ang: float = atan2(vy[i], vx[i])
					var want_ang: float = atan2(ty, tx)
					var na: float = lerp_angle(cur_ang, want_ang, clampf(homing[i] * delta, 0.0, 1.0))
					vx[i] = cos(na) * sp
					vy[i] = sin(na) * sp

		if friendly[i] == 1 and life[i] > 0.0:
			var hits: int = enemies.query(px[i], py[i], rad[i] + 8.0)
			if hits > 0:
				var consumed := false
				for k in range(hits):
					var e: int = enemies.query_buf[k]
					if e < 0 or e >= enemies.count:
						continue
					var dd: float = enemies.rad[e] + rad[i]
					var dx2: float = enemies.px[e] - px[i]
					var dy2: float = enemies.py[e] - py[i]
					if dx2 * dx2 + dy2 * dy2 > dd * dd:
						continue
					if status[i] > 0:
						enemies.apply_status(e, STATUS_NAMES[status[i]], dps[i])
					if kb[i] > 0.0:
						enemies.knockback(e, dx2, dy2, kb[i])
					enemies.damage(e, dmg[i])
					if splash_r[i] > 0.0:
						enemies.damage_in_circle(px[i], py[i], splash_r[i], splash_dmg[i], "", 0.0, 0.0)
					if on_hit.is_valid():
						on_hit.call(px[i], py[i])
					if pierce[i] <= 0:
						consumed = true
						break
					pierce[i] -= 1
				if consumed:
					_swap_remove(i)
					i -= 1
					continue
		i -= 1

## 敌人弹幕是否命中玩家。返回命中的总伤害。
func player_hit_damage(px0: float, py0: float, player_r: float) -> float:
	var total := 0.0
	var i: int = count - 1
	while i >= 0:
		if friendly[i] == 0:
			var dx: float = px[i] - px0
			var dy: float = py[i] - py0
			var dd: float = player_r + size[i]
			if dx * dx + dy * dy <= dd * dd:
				total += dmg[i]
				_swap_remove(i)
		i -= 1
	return total
