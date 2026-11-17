class_name CombatFx
extends RefCounted
## 《余民》战斗特效层 —— 纯渲染、确定性、零 sim 副作用。
##
## 分档（UserSettings.fx_level；命令行 --fx=0/1/2 可强制覆盖，仅用于截图对比）：
##   0 = 全关：本层一点不画，只保留可玩性所需的最小提示（伤害数字 / 危险区预警 /
##              武器挥击反馈这些不归本层管，仍由 world_renderer 照常绘制）
##   1 = 中：只留屏幕震动（≤4 逻辑像素）+ 命中粒子（数量减半）
##   2 = 高：全开 —— 死亡碎裂块 / 尘土 / 拾取上浮光点 / 升级金柱 / BOSS 入场暗角脉冲 /
##              精英击杀白闪
##
## 铁律：
## - 只读 run 的字段，绝不写任何 sim 数据；绝不碰 run.rng / enemies.rng / weapons.rng。
##   所有抖动、散射方向、碎片大小走整数哈希 _hash2，同一输入永远同一结果，连跑两次一致。
## - 不加载任何纹理：全部 draw_* 几何，--headless 下天然安全。
## - 只在 WorldRenderer 可见时被 update/draw 调用（--sim 隐藏世界层 → 本层完全不跑）。

const LV_OFF := 0
const LV_MID := 1
const LV_HIGH := 2

# ---- 屏幕震动：幅度按逻辑像素给，落到世界坐标要除相机 zoom ----
const SHAKE_MAX_PX := 4.0        # 硬上限 4 逻辑像素
const SHAKE_LIFE := 0.26         # 0.26s 衰减（落在 0.2..0.3 的要求区间）
const WORLD_PER_PX_FALLBACK := 0.70  # 取不到相机时的兜底（按 zoom=1.35 标定）；正常按 1/zoom 动态换算

# ---- 粒子预算（同屏硬上限，防 600 敌人时爆量）----
const DEBRIS_MAX := 120
const DEBRIS_LIFE := 0.46
const DUST_MAX := 140
const DUST_LIFE := 0.30
const PICKUP_MAX := 64
const PICKUP_LIFE := 0.55
const PILLAR_LIFE := 0.62
const FLASH_LIFE := 0.10
const VIG_LIFE := 0.95
const RING_LIFE := 0.20
const GEM_NEAR_SQ := 2304.0      # 拾取判定只盯玩家 48px 内的宝石（48^2）

var _forced: int = -1            # --fx=N；-1 = 跟随 UserSettings

# ---- 现场探针（--fx-probe=秒，默认关）：只在开发/验收时打印触发计数，证明特效真的在跑 ----
var _probe_every: float = 0.0
var _probe_next: float = 0.0
var _n_kick: int = 0
var _n_dust: int = 0
var _n_debris: int = 0
var _n_pickup: int = 0
var _n_pillar: int = 0
var _n_vig: int = 0
var _n_flash: int = 0

# ---- 震动 ----
var _shake_t: float = 0.0
var _shake_amp: float = 0.0      # 世界坐标幅度（已乘 _wpp）
var _wpp: float = 1.0            # 世界单位/逻辑像素，每帧按相机 zoom 更新
var _shake_step: int = 0
var _shake_off: Vector2 = Vector2.ZERO

# ---- 粒子 ----
var _debris: Array = []
var _dust: Array = []
var _pickup: Array = []
var _rings: Array = []

# ---- 瞬时特效 ----
var _pillar_t: float = 0.0
var _pillar_pos: Vector2 = Vector2.ZERO
var _flash_t: float = 0.0
var _vig_t: float = 0.0
var _t: float = 0.0              # 本层自己的计时（只在可见时推进，不参与 sim）

# ---- 事件游标（只读 run / state）----
var _seen: bool = false
var _hp_prev: float = 0.0
var _level_prev: int = 1
var _boss_prev: bool = false
var _xp_prev: float = 0.0
var _gem_n_prev: int = 0
var _gem_prev: Array = []

# ================================================================ 生命周期

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fx="):
			var v: int = int(a.substr(5))
			if v >= LV_OFF and v <= LV_HIGH:
				_forced = v
		elif a.begins_with("--fx-probe="):
			_probe_every = maxf(float(a.substr(11)), 0.0)

## 当前档位：命令行强制优先，否则实时跟随 UserSettings（暂停菜单切档立刻生效）
func level() -> int:
	if _forced >= 0:
		return _forced
	return clampi(int(UserSettings.fx_level), LV_OFF, LV_HIGH)

## 本帧世界层要平移的画布偏移（屏幕震动）。只作用于绘制，不触碰 cam / sim。
func world_offset() -> Vector2:
	return _shake_off

## 每帧推进：事件检测（只读）+ 粒子寿命。调用方保证「世界层可见」。
func update(dt: float, run: Node) -> void:
	if run == null:
		return
	var st = run.get("state")
	if st == null:
		return
	var lvl: int = level()
	# 震动幅度按「逻辑像素」给：世界位移 = 像素 / zoom，这样相机 1.0/1.35 改档后屏幕抖动幅度不变
	var cam_n = run.get("cam")
	if cam_n is Camera2D:
		_wpp = 1.0 / maxf(0.1, (cam_n as Camera2D).zoom.x)
	else:
		_wpp = WORLD_PER_PX_FALLBACK
	_t += dt
	var p: Vector2 = run.player_pos()
	var hpv = run.get("player_hp")
	var hp: float = float(hpv) if hpv != null else 0.0
	if not _seen:
		_seen = true
		_hp_prev = hp
		_level_prev = int(st.level)
		_boss_prev = bool(run.get("boss_spawned"))
		_xp_prev = float(st.xp)
		_gem_n_prev = _gem_count(run)
	else:
		# ---- 玩家受击：血量掉（回血/升级治疗不算）----
		if hp < _hp_prev - 0.01:
			_kick(3.8)
		_hp_prev = hp
		# ---- 升级：金色光柱 + 轻微震动 ----
		var lv_now: int = int(st.level)
		if lv_now > _level_prev:
			_kick(2.2)
			if lvl >= LV_HIGH:
				_pillar_t = PILLAR_LIFE
				_pillar_pos = p
				_n_pillar += 1
		# ---- BOSS 出场：暗角脉冲 + 震动 ----
		var bp: bool = bool(run.get("boss_spawned"))
		if bp and not _boss_prev:
			_kick(3.6)
			if lvl >= LV_HIGH:
				_vig_t = VIG_LIFE
				_n_vig += 1
		_boss_prev = bp
	# 拾取光点要在 _level_prev / _xp_prev 更新前判定（捡宝石会同时改 xp 与 gems）
	if lvl >= LV_HIGH:
		_update_pickups(run, st)
	else:
		_gem_prev.clear()
		_gem_n_prev = _gem_count(run)
		_xp_prev = float(st.xp)
	_level_prev = int(st.level)
	# ---- 震动衰减：写成角度抖动，幅度按 k² 收口 ----
	if _shake_t > 0.0 and lvl >= LV_MID:
		_shake_t = maxf(_shake_t - dt, 0.0)
		var k: float = _shake_t / SHAKE_LIFE
		var amp: float = _shake_amp * k * k
		_shake_step += 1
		var h: int = _hash2(_shake_step, 7919)
		var ang: float = float(h & 1023) / 1024.0 * TAU
		_shake_off = Vector2(cos(ang), sin(ang)) * amp
	else:
		_shake_t = 0.0
		_shake_amp = 0.0
		_shake_off = Vector2.ZERO
	# ---- 粒子寿命 ----
	if _probe_every > 0.0 and _t >= _probe_next:
		_probe_next = _t + _probe_every
		print("[fx] lvl=%d el=%.1f t=%.1f kick=%d dust=%d debris=%d pickup=%d pillar=%d vig=%d flash=%d live(dust=%d debris=%d pickup=%d) timer(pillar=%.2f vig=%.2f flash=%.2f shake=%.2f)" % [
			lvl, float(run.get("elapsed")), _t, _n_kick, _n_dust, _n_debris, _n_pickup, _n_pillar, _n_vig, _n_flash,
			_dust.size(), _debris.size(), _pickup.size(),
			_pillar_t, _vig_t, _flash_t, _shake_t
		])
	_tick_debris(dt, lvl)
	_tick_dust(dt, lvl)
	_tick_pickup(dt, lvl)
	_tick_rings(dt, lvl)
	_pillar_t = maxf(_pillar_t - dt, 0.0)
	_flash_t = maxf(_flash_t - dt, 0.0)
	_vig_t = maxf(_vig_t - dt, 0.0)

## 触发震动：px 是逻辑像素；同一时刻只保留更强的那一次（小的不覆盖大的）
func _kick(px: float) -> void:
	if level() < LV_MID:
		return
	var amp: float = minf(px, SHAKE_MAX_PX) * _wpp
	var cur: float = _shake_amp * clampf(_shake_t / SHAKE_LIFE, 0.0, 1.0)
	if _shake_t <= 0.0 or amp >= cur:
		_shake_amp = amp
		_shake_t = SHAKE_LIFE
		_n_kick += 1

## 整数哈希：与 world_renderer._hash2 同族，纯确定性（不消费 rng）
func _hash2(x: int, y: int) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663)
	h = h * 83492791
	h = h ^ (h >> 17)
	return h & 0x7FFFFFFFFFFF

# ================================================================ 事件入口（由 world_renderer 调用）

## 命中：尘土溅射（火星本体仍由 world_renderer 的 _hit_fx 画，那边负责减半）
func on_hit(x: float, y: float, crit: bool) -> void:
	var lv: int = level()
	if lv < LV_MID:
		return
	var n: int = 2 if crit else 1
	if lv >= LV_HIGH:
		n += 1
	_spawn_dust(Vector2(x, y + 5.0), n, Color("#B9A888"))
	if lv >= LV_HIGH and crit:
		_spawn_dust(Vector2(x, y + 3.0), 1, Color("#F0C878"))

## 敌人死亡：精英/BOSS 震动 + 碎裂块 + 尘土 + 白闪（高）。typ 颜色由调用方查好传入。
func on_enemy_death(x: float, y: float, col: Color, elite: bool, boss: bool) -> void:
	var lv: int = level()
	if lv < LV_MID:
		return
	if boss:
		_kick(4.0)
	elif elite:
		_kick(2.6)
	if lv < LV_HIGH:
		return
	_spawn_debris(x, y, col, elite, boss)
	_spawn_dust(Vector2(x, y + 2.0), 6 if boss else (3 if elite else 2), Color("#8E7F68"))
	if boss:
		_flash_t = FLASH_LIFE
		_n_flash += 1
		_add_ring(x, y, 48.0, Color(1.0, 0.94, 0.74))
	elif elite:
		_flash_t = FLASH_LIFE
		_n_flash += 1
		_add_ring(x, y, 26.0, Color(1.0, 1.0, 0.96))

# ================================================================ 粒子生成

## 死亡碎裂块：沿圆周甩出 + 上抛，重力 240，0.46s 淡出。颜色取自敌人本体再压暗。
func _spawn_debris(x: float, y: float, col: Color, elite: bool, boss: bool) -> void:
	var n: int = 12 if boss else (7 if elite else 4)
	var h: int = _hash2(int(round(x * 2.0)), int(round(y * 2.0)))
	for k in range(n):
		if _debris.size() >= DEBRIS_MAX:
			return
		var hk: int = (h >> ((k % 7) * 4)) & 255
		var ang: float = TAU * float(k) / float(n) + float(hk) * 0.0245
		var spd: float = (34.0 + float(hk & 31) * 2.4) * (1.35 if boss else 1.0)
		var sz: float = 1.6 + float((hk >> 5) & 3) * 0.9 + (1.6 if boss else 0.0)
		var c: Color = col.darkened(0.12 + 0.22 * float((hk >> 3) & 1))
		_n_debris += 1
		_debris.append({
			"x": x + cos(ang) * 2.0,
			"y": y - 2.0 + sin(ang) * 2.0,
			"vx": cos(ang) * spd,
			"vy": sin(ang) * spd - 52.0,
			"life": DEBRIS_LIFE,
			"sz": sz,
			"c": c,
		})

## 尘土 / 火星：慢速外扩 + 轻微上浮，0.30s 淡出
func _spawn_dust(p: Vector2, n: int, col: Color) -> void:
	if n <= 0:
		return
	var h: int = _hash2(int(round(p.x * 4.0)), int(round(p.y * 4.0)))
	for k in range(n):
		if _dust.size() >= DUST_MAX:
			return
		var hk: int = (h >> ((k % 5) * 6)) & 63
		var ang: float = TAU * float(hk) / 64.0
		var spd: float = 16.0 + float(hk & 7) * 4.0
		_n_dust += 1
		_dust.append({
			"x": p.x, "y": p.y,
			"vx": cos(ang) * spd, "vy": sin(ang) * spd * 0.5 - 14.0,
			"life": DUST_LIFE,
			"r": 1.1 + float((hk >> 3) & 3) * 0.5,
			"c": col,
		})

## 拾取宝石：3 颗上浮光点（颜色按宝石四档取）
func _spawn_pickup(p: Vector2, val: int) -> void:
	var col := Color("#8FE8CC")
	if val >= 100:
		col = Color("#F49AB4")
	elif val >= 25:
		col = Color("#F6D98A")
	elif val >= 4:
		col = Color("#E9DFA8")
	var h: int = _hash2(int(round(p.x * 3.0)), int(round(p.y * 3.0)))
	for k in range(3):
		if _pickup.size() >= PICKUP_MAX:
			return
		var hk: int = (h >> (k * 5)) & 63
		var ox: float = float((hk & 15) - 8) * 1.1
		_n_pickup += 1
		_pickup.append({
			"x": p.x + ox,
			"y": p.y - 2.0,
			"vx": ox * 0.9,
			"vy": -18.0 - float((hk >> 4) & 7) * 2.2,
			"life": PICKUP_LIFE,
			"r": 1.0 + float(hk & 1) * 0.6,
			"c": col,
		})

## 精英 / BOSS 死亡白环（最多 6 个）
func _add_ring(x: float, y: float, rmax: float, c: Color) -> void:
	if _rings.size() >= 6:
		_rings.remove_at(0)
	_rings.append({ "x": x, "y": y, "r": rmax, "life": RING_LIFE, "c": c })

# ================================================================ 粒子推进

func _tick_debris(dt: float, lvl: int) -> void:
	var i: int = _debris.size() - 1
	while i >= 0:
		if lvl < LV_HIGH:
			_debris.remove_at(i)
			i -= 1
			continue
		var d: Dictionary = _debris[i]
		var life: float = float(d["life"]) - dt
		if life <= 0.0:
			_debris.remove_at(i)
			i -= 1
			continue
		d["life"] = life
		d["x"] = float(d["x"]) + float(d["vx"]) * dt
		d["y"] = float(d["y"]) + float(d["vy"]) * dt
		d["vx"] = float(d["vx"]) * 0.985
		d["vy"] = float(d["vy"]) + 240.0 * dt
		i -= 1

func _tick_dust(dt: float, lvl: int) -> void:
	var i: int = _dust.size() - 1
	while i >= 0:
		if lvl < LV_MID:
			_dust.remove_at(i)
			i -= 1
			continue
		var d2: Dictionary = _dust[i]
		var life: float = float(d2["life"]) - dt
		if life <= 0.0:
			_dust.remove_at(i)
			i -= 1
			continue
		d2["life"] = life
		d2["x"] = float(d2["x"]) + float(d2["vx"]) * dt
		d2["y"] = float(d2["y"]) + float(d2["vy"]) * dt
		d2["vx"] = float(d2["vx"]) * 0.90
		d2["vy"] = float(d2["vy"]) * 0.90 - 10.0 * dt
		i -= 1

func _tick_pickup(dt: float, lvl: int) -> void:
	var i: int = _pickup.size() - 1
	while i >= 0:
		if lvl < LV_HIGH:
			_pickup.remove_at(i)
			i -= 1
			continue
		var p: Dictionary = _pickup[i]
		var life: float = float(p["life"]) - dt
		if life <= 0.0:
			_pickup.remove_at(i)
			i -= 1
			continue
		p["life"] = life
		p["x"] = float(p["x"]) + float(p["vx"]) * dt
		p["y"] = float(p["y"]) + float(p["vy"]) * dt
		p["vy"] = float(p["vy"]) + 26.0 * dt
		i -= 1

func _tick_rings(dt: float, lvl: int) -> void:
	var i: int = _rings.size() - 1
	while i >= 0:
		if lvl < LV_HIGH:
			_rings.remove_at(i)
			i -= 1
			continue
		var r: Dictionary = _rings[i]
		var life: float = float(r["life"]) - dt
		if life <= 0.0:
			_rings.remove_at(i)
			i -= 1
			continue
		r["life"] = life
		i -= 1

# ================================================================ 拾取检测（只读 run.gems / state.xp）

func _gem_count(run: Node) -> int:
	var g = run.get("gems")
	return g.size() if g != null else 0

## 只收玩家 48px 内的宝石：真正会在一两帧内被吃掉的，避免每帧全量扫几百颗
func _gems_near(run: Node, p: Vector2) -> Array:
	var out: Array = []
	var g = run.get("gems")
	if g == null:
		return out
	for i in range(g.size()):
		var e: Dictionary = g[i]
		var dx: float = float(e["x"]) - p.x
		var dy: float = float(e["y"]) - p.y
		if dx * dx + dy * dy <= GEM_NEAR_SQ:
			out.append(Vector3(float(e["x"]), float(e["y"]), float(e["val"])))
	return out

## 上一帧近处宝石 vs 这一帧：最近邻配对（<=16px），配不上的旧宝石视为被吃掉。
## 只在 xp 涨了 / 升级了 / 总数变少时才生成，避免宝石被磁吸引出 48px 圈时误判。
## fx<2 时调用方根本不进来，只刷新游标（见 update）。
func _update_pickups(run: Node, st) -> void:
	var p: Vector2 = run.player_pos()
	var near: Array = _gems_near(run, p)
	var n_now: int = _gem_count(run)
	var xp_now: float = float(st.xp)
	var lv_now: int = int(st.level)
	var gained: bool = xp_now > _xp_prev + 0.001 or lv_now > _level_prev or n_now < _gem_n_prev
	if _gem_prev.size() > 0 and gained:
		var used: Array = []
		used.resize(near.size())
		for i in range(used.size()):
			used[i] = false
		for j in range(_gem_prev.size()):
			var old: Vector3 = _gem_prev[j]
			var best: int = -1
			var best_d: float = 256.0        # 16px 的平方
			for k in range(near.size()):
				if used[k]:
					continue
				var nk: Vector3 = near[k]
				var ddx: float = nk.x - old.x
				var ddy: float = nk.y - old.y
				var dd: float = ddx * ddx + ddy * ddy
				if dd < best_d:
					best_d = dd
					best = k
			if best >= 0:
				used[best] = true
			else:
				_spawn_pickup(Vector2(old.x, old.y), int(old.z))
	_gem_prev = near
	_gem_n_prev = n_now
	_xp_prev = xp_now

# ================================================================ 绘制（世界坐标，全部几何，零纹理）

## 死亡碎裂块：沿速度方向的三角碎片（不用变换矩阵，保证绘制无状态残留）
func draw_debris(ci: CanvasItem, lvl: int) -> void:
	if lvl < LV_HIGH:
		return
	for d in _debris:
		var k: float = float(d["life"]) / DEBRIS_LIFE
		var c: Color = d["c"]
		c.a = 0.35 + 0.65 * k
		var pos := Vector2(float(d["x"]), float(d["y"]))
		var vel := Vector2(float(d["vx"]), float(d["vy"]))
		var dir := vel.normalized() if vel.length_squared() > 0.25 else Vector2.RIGHT
		var perp := Vector2(-dir.y, dir.x)
		var sz: float = float(d["sz"]) * (0.6 + 0.4 * k)
		var pts := PackedVector2Array([
			pos + dir * sz * 1.7,
			pos - dir * sz * 0.7 + perp * sz * 0.75,
			pos - dir * sz * 0.7 - perp * sz * 0.75,
		])
		ci.draw_colored_polygon(pts, c)

## 尘土 / 火星点：外扩 + 变淡（fx=1 也画，数量在生成时就减半了）
func draw_dust(ci: CanvasItem, lvl: int) -> void:
	if lvl < LV_MID:
		return
	for d in _dust:
		var k: float = float(d["life"]) / DUST_LIFE
		var c: Color = d["c"]
		c.a = 0.62 * k
		ci.draw_circle(Vector2(float(d["x"]), float(d["y"])), float(d["r"]) * (1.55 - 0.55 * k), c)

## 拾取宝石上浮光点：核心点 + 外晕
func draw_pickup(ci: CanvasItem, lvl: int) -> void:
	if lvl < LV_HIGH:
		return
	for p in _pickup:
		var k: float = float(p["life"]) / PICKUP_LIFE
		var c: Color = p["c"]
		var pos := Vector2(float(p["x"]), float(p["y"]))
		var r: float = float(p["r"]) * (0.55 + 0.75 * k)
		ci.draw_circle(pos, r * 2.4, Color(c.r, c.g, c.b, 0.16 * k))
		ci.draw_circle(pos, r, Color(c.r, c.g, c.b, 0.95 * k))

## 精英 / BOSS 死亡白环：向外收口扩张
func draw_rings(ci: CanvasItem, lvl: int) -> void:
	if lvl < LV_HIGH:
		return
	for r in _rings:
		var k: float = float(r["life"]) / RING_LIFE
		var t: float = 1.0 - k
		var rad: float = 5.0 + (float(r["r"]) - 5.0) * (1.0 - k * k)
		var c: Color = r["c"]
		c.a = k * k
		ci.draw_arc(Vector2(float(r["x"]), float(r["y"])), rad, 0.0, TAU, 28, c, 1.6 + 1.8 * k, true)

## 升级金色光柱（画在玩家之前 → 柱子在玩家身下）
func draw_pillar(ci: CanvasItem, lvl: int) -> void:
	if lvl < LV_HIGH or _pillar_t <= 0.0:
		return
	var k: float = _pillar_t / PILLAR_LIFE
	var rise: float = 1.0 - k
	var h: float = 30.0 + 78.0 * rise
	var w: float = 9.0 + 9.0 * k
	var p := _pillar_pos
	ci.draw_rect(Rect2(p.x - w, p.y - h, w * 2.0, h), Color(1.0, 0.84, 0.38, 0.16 * k))
	ci.draw_rect(Rect2(p.x - w * 0.42, p.y - h * 1.08, w * 0.84, h * 1.08), Color(1.0, 0.93, 0.62, 0.30 * k))
	ci.draw_circle(Vector2(p.x, p.y - 1.0), 9.0 + 15.0 * k, Color(1.0, 0.88, 0.48, 0.22 * k))
	ci.draw_arc(Vector2(p.x, p.y), 6.0 + 26.0 * rise, 0.0, TAU, 24, Color(1.0, 0.90, 0.58, 0.55 * k), 1.4, true)

## 全屏层：精英/BOSS 死亡白闪 + BOSS 入场暗角脉冲（画在世界坐标的可视矩形上）
func draw_screen(ci: CanvasItem, lvl: int, view: Rect2) -> void:
	if lvl < LV_HIGH:
		return
	if _flash_t > 0.0:
		var fk: float = _flash_t / FLASH_LIFE
		ci.draw_rect(view, Color(1.0, 1.0, 1.0, 0.30 * fk * fk), true)
	if _vig_t > 0.0:
		var vk: float = _vig_t / VIG_LIFE
		var pulse: float = sin(clampf(1.0 - vk, 0.0, 1.0) * PI)
		if pulse > 0.001:
			# 冷色暗角：纯黑在深色地面上读不出来，掺钢蓝更像「神圣压迫感」
			var step: float = maxf(2.0, view.size.y * 0.016)
			for i in range(16):
				var r2: Rect2 = view.grow(-(float(i) * step))
				if r2.size.x <= 16.0 or r2.size.y <= 16.0:
					break
				var a: float = (0.55 - 0.028 * float(i)) * pulse
				ci.draw_rect(r2, Color(0.05, 0.09, 0.26, a), false, step * 1.2)
