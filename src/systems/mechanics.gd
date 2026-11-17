class_name RunMechanics
extends RefCounted
## 24 张地图机关（第 2 波 · 局内系统）。
## 按 stages.json 的 mechanic_id 分发，全部走同一套骨架：
##   spots    常驻/临时地形（可破坏物、灯台、井口、麦田、水池…）
##   hazards  延迟伤害圈（雷击、陨星、火雹…）
##   pickups  机关掉落（石子、火舌、水桶…）
## tick() 每帧推进；on_kill()/on_level_up()/on_boss_spawn() 由 run 转发。
## 与武器/敌人的耦合只走 EnemySim / run 的公开方法，不改别人的文件。

const VISION_TORCH := 190.0
const VISION_DARK := 110.0

var run: Node
var id: String = ""
var rng := RandomNumberGenerator.new()
var spots: Array = []
var hazards: Array = []
var pickups: Array = []
var flags: Dictionary = {}
var counters: Dictionary = {}
var _t: float = 0.0
var _acc: float = 0.0
var _ramp: Dictionary = {}

func setup(r: Node) -> void:
	run = r
	id = String(run.stage.get("mechanic_id", ""))
	rng.seed = int(run.rng.randi())
	_run()

func _run() -> void:
	match id:
		"dry_creek": _setup_dry_creek()
		"lightning_zones": pass
		"drought_fire": pass
		"altar_charge": _setup_altar_charge()
		"wall_ring": _setup_wall_ring()
		"temptation_choice": pass
		"glass_sea": _setup_glass_sea()
		"meteor_horde": pass
		"flood_tide": _setup_flood()
		"babel_confusion": pass
		"plague_cycle": pass
		"sea_walls": _setup_sea_walls()
		"bitter_water": _setup_bitter_water()
		"darkness_lamp": _setup_darkness()
		"burnable_field": _setup_burnable()
		"cave_choke": _setup_cave()
		"belly_shade": pass
		"furnace_rings": pass
		"storm_push": pass
		"pentecost_rush": pass
		"prison_quake": pass
		"seven_lamps": _setup_lamps()
		"abyss_vents": _setup_vents()
		"eden_fall": pass

# ================================================================ 主循环

func tick(delta: float) -> void:
	if run.over:
		return
	_t += delta
	match id:
		"eden_fall": _t_eden(delta)
		"flood_tide": _t_flood(delta)
		"babel_confusion": _t_babel(delta)
		"altar_charge": _t_altar(delta)
		"plague_cycle": _t_plague(delta)
		"sea_walls": _t_sea_walls(delta)
		"lightning_zones": _t_lightning(delta)
		"bitter_water": _t_bitter(delta)
		"wall_ring": _t_wall_ring(delta)
		"darkness_lamp": _t_darkness(delta)
		"burnable_field": _t_burnable(delta)
		"cave_choke": _t_cave(delta)
		"dry_creek": _t_dry_creek(delta)
		"drought_fire": _t_drought(delta)
		"belly_shade": _t_belly(delta)
		"furnace_rings": _t_furnace(delta)
		"temptation_choice": _t_temptation(delta)
		"storm_push": _t_storm(delta)
		"pentecost_rush": _t_pentecost(delta)
		"prison_quake": _t_prison(delta)
		"seven_lamps": _t_lamps(delta)
		"abyss_vents": _t_vents(delta)
		"meteor_horde": _t_meteor(delta)
		"glass_sea": _t_glass(delta)
	_tick_hazards(delta)
	_tick_pickups(delta)
	_tick_spots(delta)
	_apply_terrain()

func on_kill(pos: Vector2) -> void:
	counters["kills"] = int(counters.get("kills", 0)) + 1
	if id == "altar_charge" and pos.distance_to(Vector2.ZERO) <= 64.0:
		counters["altar_kills"] = int(counters.get("altar_kills", 0)) + 1
		if int(counters["altar_kills"]) % 40 == 0:
			_scatter_sheep()
	if id == "babel_confusion" and float(_ramp.get("confuse", 0.0)) > 0.0:
		flags["friendly_fire_kill"] = true
	if id == "sea_walls" and absf(pos.x) > 100.0:
		flags["water_wall_kill"] = true

func on_level_up() -> void:
	pass

func on_boss_spawn() -> void:
	if id == "dry_creek" and int(counters.get("stones", 0)) >= 5:
		for i in range(run.enemies.count):
			if not run.enemies.is_boss(i):
				continue
			var dmg: float = float(run.enemies.max_hp[i]) * 0.20
			run.enemies.apply_status(i, "tremor", 3.0)
			run.enemies.damage(i, dmg)
			run.active_fx.append({ "kind": "nova", "x": run.enemies.px[i], "y": run.enemies.py[i], "r": 120.0, "life": 0.6, "color": Color("#7FE0C0") })
			run.toast_text = "五颗光滑石子 · BOSS 虚弱"
			run.toast_t = 2.4
			flags["dry_creek_stones"] = true
			break
	if id == "temptation_choice" and int(counters.get("bread_eaten", 0)) > 0:
		var bonus: float = 0.15 * float(counters["bread_eaten"])
		for i in range(run.enemies.count):
			if run.enemies.is_boss(i):
				run.enemies.max_hp[i] = float(run.enemies.max_hp[i]) * (1.0 + bonus)
				run.enemies.hp[i] = float(run.enemies.hp[i]) * (1.0 + bonus)
				break

## 敌人双倍经验区（烈火窑内圈）
func xp_mult_at(pos: Vector2) -> float:
	if id == "furnace_rings" and pos.distance_to(Vector2.ZERO) < 180.0:
		return 2.0
	return 1.0

## 变乱口音：敌人弹幕偏转 35° 且敌我同伤
func enemy_bullet_mod() -> Dictionary:
	if id == "babel_confusion" and float(_ramp.get("confuse", 0.0)) > 0.0:
		return { "active": true, "angle": 0.6109, "friendly": true }
	return { "active": false, "angle": 0.0, "friendly": false }

## 精英必掉金箱（倾倒的大城）
func elite_chest_tier() -> String:
	if id == "meteor_horde":
		return "gold"
	return ""

# ================================================================ 24 个机关

# ---- ch01 伊甸：分别善恶树 / 禁果 / 荆棘荒原
func _t_eden(delta: float) -> void:
	if not _ramp.has("tree") and run.elapsed >= 300.0:
		_ramp["tree"] = true
		var a: float = rng.randf() * TAU
		spots.append({ "kind": "tree", "x": run.player.x + cos(a) * 170.0, "y": run.player.y + sin(a) * 170.0, "r": 26.0, "life": 1e9 })
		_toast("分别善恶树 · 吃果或持守", 2.4)
	if not bool(flags.get("eden_decided", false)) and run.elapsed >= 360.0:
		flags["eden_decided"] = true
		flags["no_fruit"] = true
		flags["no_forbidden_fruit"] = true
		_patch("eden_keep", "cooldown_mult", "mul", 0.9)
		_toast("树枯萎 · 冷却 -10%", 2.0)
	for s in spots:
		if String(s["kind"]) == "tree" and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < 32.0:
			_eat_fruit()
			s["kind"] = "tree_withered"
			flags["eden_decided"] = true
			flags.erase("no_fruit")

func _eat_fruit() -> void:
	if bool(flags.get("eden_eaten", false)):
		return
	flags["eden_eaten"] = true
	_patch("eden_fruit_dmg", "damage_mult", "mul", 1.4)
	_patch("eden_fruit_xp", "xp_gain", "mul", 0.85)
	for i in range(12):
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(120.0, 520.0)
		spots.append({ "kind": "thorn", "x": run.player.x + cos(a) * d, "y": run.player.y + sin(a) * d, "r": 30.0, "life": 1e9 })
	_toast("吃了禁果 · 伤害 +40% / 经验 -15%", 2.6)

# ---- ch02 洪水：涨潮 / 方舟木台高地
func _setup_flood() -> void:
	for i in range(3):
		var a: float = TAU * float(i) / 3.0 + 0.4
		spots.append({ "kind": "platform", "x": cos(a) * 260.0, "y": sin(a) * 260.0, "r": 70.0, "life": 1e9 })

func _t_flood(delta: float) -> void:
	if not _ramp.has("tide_next"):
		_ramp["tide_next"] = 90.0
	if run.elapsed >= float(_ramp["tide_next"]):
		_ramp["tide_next"] = float(_ramp["tide_next"]) + 90.0
		_ramp["tide_t"] = 30.0
		_toast("雨水涨潮 · 寻找方舟木台", 2.2)
	_ramp["tide_t"] = maxf(float(_ramp.get("tide_t", 0.0)) - delta, 0.0)
	_ramp["tide"] = 1.0 if float(_ramp["tide_t"]) > 0.0 else 0.0
	# 涨潮期间不在方舟木台上站满 60s → ach_26
	if float(_ramp["tide_t"]) > 0.0:
		var safe: bool = false
		for s in spots:
			if String(s["kind"]) == "platform" and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < float(s["r"]):
				safe = true
		if not safe:
			_ramp["deep_t"] = float(_ramp.get("deep_t", 0.0)) + delta
			if float(_ramp["deep_t"]) >= 60.0:
				flags["deep_water_stand_60s"] = true

# ---- ch03 巴别：变乱口音
func _t_babel(delta: float) -> void:
	if not _ramp.has("babel_next"):
		_ramp["babel_next"] = 120.0
	if run.elapsed >= float(_ramp["babel_next"]):
		_ramp["babel_next"] = float(_ramp["babel_next"]) + 120.0
		_ramp["confuse"] = 20.0
		_toast("口音变乱 · 敌军弹幕反噬", 2.2)
	_ramp["confuse"] = maxf(float(_ramp.get("confuse", 0.0)) - delta, 0.0)

# ---- ch04 亚伯拉罕古坛：圈内每 40 杀召替罪金羊
func _setup_altar_charge() -> void:
	spots.append({ "kind": "ancient_altar", "x": 0.0, "y": 0.0, "r": 64.0, "life": 1e9 })

func _t_altar(delta: float) -> void:
	pass

func _scatter_sheep() -> void:
	var c: int = 0
	for i in range(run.enemies.count):
		if not run.enemies.is_boss(i):
			c += 1
	run.enemies.damage_in_circle(0.0, 0.0, 150.0, 220.0, "tremor", 0.0, 300.0)
	_nova(0.0, 0.0, 170.0, "#E0B85A", 0.6)
	_toast("替罪金羊冲撞 · 220 震慑", 1.8)
	flags["altar_sheep"] = true

# ---- ch05 十灾轮换
func _t_plague(delta: float) -> void:
	if not _ramp.has("plague_next"):
		_ramp["plague_next"] = 120.0
		_ramp["plague_i"] = 0
	if run.elapsed >= float(_ramp["plague_next"]):
		_ramp["plague_next"] = float(_ramp["plague_next"]) + 120.0
		var i: int = int(_ramp["plague_i"])
		_ramp["plague_i"] = (i + 1) % 4
		match i:
			0:
				for k in range(4):
					var a: float = rng.randf() * TAU
					spots.append({ "kind": "blood", "x": run.player.x + cos(a) * rng.randf_range(80.0, 320.0), "y": run.player.y + sin(a) * rng.randf_range(80.0, 320.0), "r": 44.0, "life": 30.0 })
				_toast("第一灾 · 水变血", 1.8)
			1:
				for k in range(8):
					_spawn_ring("plague_locust", 1, 180.0, 300.0)
				_toast("第二灾 · 蛙群/蝗虫", 1.8)
			2:
				for k in range(8):
					var p: Vector2 = _rand_around(80.0, 360.0)
					_hazard(p.x, p.y, 28.0, 1.2, 40.0)
				_toast("第三灾 · 火雹", 1.8)
			3:
				run.vision_radius = 140.0
				_ramp["dark_t"] = 12.0
				_toast("第九灾 · 三日之暗", 1.8)
	_ramp["dark_t"] = maxf(float(_ramp.get("dark_t", 0.0)) - delta, 0.0)
	if float(_ramp.get("dark_t", 0.0)) <= 0.0 and float(run.vision_radius) == 140.0 and id == "plague_cycle":
		run.vision_radius = 0.0

# ---- ch06 红海：水墙合拢
func _setup_sea_walls() -> void:
	spots.append({ "kind": "wall", "x": -210.0, "y": 0.0, "r": 0.0, "h": 900.0, "life": 1e9, "side": -1 })
	spots.append({ "kind": "wall", "x": 210.0, "y": 0.0, "r": 0.0, "h": 900.0, "life": 1e9, "side": 1 })

func _t_sea_walls(delta: float) -> void:
	if not _ramp.has("wall_next"):
		_ramp["wall_next"] = 90.0
	if run.elapsed >= float(_ramp["wall_next"]):
		_ramp["wall_next"] = float(_ramp["wall_next"]) + 90.0
		_ramp["closing"] = 18.0
		_toast("红海合拢 · 退向中央", 2.0)
	_ramp["closing"] = maxf(float(_ramp.get("closing", 0.0)) - delta, 0.0)
	var target: float = 140.0 if float(_ramp["closing"]) > 0.0 else 210.0
	for s in spots:
		if String(s["kind"]) == "wall":
			s["x"] = move_toward(float(s["x"]), target * float(s["side"]), 6.0 * delta)
	var wx: float = absf(float(_ramp.get("wall_x", target)))
	_ramp["wall_x"] = target
	# 擦墙：每秒 18【活水】并推向中心
	# 夹紧线要留 6px 余量：贴着 clamping 值正好等于伤害阈值时，浮点误差会让「被墙夹住」变成永久掉血
	if absf(run.player.x) > target - 20.0:
		run.player = Vector2(clampf(run.player.x, -target + 20.0, target - 20.0), run.player.y)
		run.hurt_player_dot(10.0 * delta)
		_ramp["wall_hit"] = true
	# 水墙同样冲刷敌人，擦墙致死记【红海压碎】
	for i in range(run.enemies.count):
		if absf(float(run.enemies.px[i])) > target - 16.0 and not run.enemies.is_boss(i):
			run.enemies.damage(i, 18.0 * delta)
			_ramp["wall_enemy_hit"] = true

# ---- ch07 西乃：十诫雷击圈 + 山界
func _t_lightning(delta: float) -> void:
	if not _ramp.has("light_next"):
		_ramp["light_next"] = 12.0
	if run.elapsed >= float(_ramp["light_next"]):
		_ramp["light_next"] = float(_ramp["light_next"]) + 12.0
		for k in range(3):
			var p: Vector2 = _rand_around(60.0, 320.0)
			# 敌我同伤是设计口径，但对玩家侧收 40%（34）：85 点落在 140 血上两发即死，
			# 手操还能躲，自动驾驶必吃，先保证任何章节能跑完一局。
			_hazard(p.x, p.y, 48.0, 1.5, 85.0, true, "lightning", 34.0)
		_toast("雷击圈 · 1.5 秒后落下", 1.2)
	if run.player.y < -300.0:
		run.player = Vector2(run.player.x, -300.0)
		_toast("山界不可逾越", 1.0)

# ---- ch08 玛拉苦水 / 铜蛇
func _setup_bitter_water() -> void:
	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		spots.append({ "kind": "bitter", "x": cos(a) * 300.0, "y": sin(a) * 300.0, "r": 52.0, "life": 1e9 })

func _t_bitter(delta: float) -> void:
	for s in spots:
		if String(s["kind"]) == "bitter" and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < float(s["r"]):
			run.hurt_player_dot(2.0 * delta)
	if not _ramp.has("snake_next"):
		_ramp["snake_next"] = 60.0
	if run.elapsed >= float(_ramp["snake_next"]):
		_ramp["snake_next"] = float(_ramp["snake_next"]) + 60.0
		var p: Vector2 = _rand_around(100.0, 300.0)
		spots.append({ "kind": "snake", "x": p.x, "y": p.y, "r": 14.0, "life": 20.0 })
	for s in spots:
		if String(s["kind"]) == "snake" and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < 48.0:
			s["kind"] = "snake_used"
			_patch("bitter_heal", "heal_per_sec", "add", 3.0)
			_ramp["snake_buff"] = 8.0
			_toast("仰望铜蛇 · 8 秒回血", 1.8)
	_ramp["snake_buff"] = maxf(float(_ramp.get("snake_buff", 0.0)) - delta, 0.0)
	if float(_ramp.get("snake_buff", 0.0)) <= 0.0:
		run.stat_patch.remove("bitter_heal")

# ---- ch09 耶利哥城墙
func _setup_wall_ring() -> void:
	spots.append({ "kind": "city_wall", "x": 0.0, "y": 0.0, "r": 160.0, "life": 1e9 })
	_ramp["lap"] = 0.0
	_ramp["last_ang"] = 0.0

func _t_wall_ring(delta: float) -> void:
	if bool(flags.get("wall_down", false)):
		return
	var d: float = run.player.length()
	if d < 176.0:
		var n: Vector2 = run.player.normalized() if d > 0.01 else Vector2.RIGHT
		run.player = n * 176.0
	if d > 140.0 and d < 300.0:
		var ang: float = run.player.angle()
		var prev: float = float(_ramp.get("last_ang", ang))
		var da: float = absf(wrapf(ang - prev, -PI, PI))
		if da < 0.5:
			_ramp["lap"] = float(_ramp["lap"]) + da
		_ramp["last_ang"] = ang
	if float(_ramp["lap"]) >= TAU * 7.0:
		_collapse_wall()

func _collapse_wall() -> void:
	flags["wall_down"] = true
	flags["jericho_inner_wall"] = true
	_ramp["lap"] = 0.0
	for s in spots:
		if String(s["kind"]) == "city_wall":
			s["life"] = 0.0
	for i in range(3):
		run.rewards.spawn_chest("silver", run.player.x + float(i - 1) * 40.0, run.player.y + 30.0)
	for i in range(24):
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(30.0, 220.0)
		run.rewards.add_gem(run.player.x + cos(a) * r, run.player.y + sin(a) * r, 8)
	_nova(0.0, 0.0, 220.0, "#E0B85A", 0.8)
	run.shake = maxf(run.shake, 8.0)
	_toast("城墙震塌 · 三只银箱", 3.0)

# ---- ch10 基甸：黑夜 / 火把瓦罐
func _setup_darkness() -> void:
	run.vision_radius = VISION_DARK
	_ramp["lamp_next"] = 30.0

func _t_darkness(delta: float) -> void:
	if run.elapsed >= float(_ramp.get("lamp_next", 30.0)):
		_ramp["lamp_next"] = float(_ramp["lamp_next"]) + 30.0
		for k in range(6):
			var a: float = rng.randf() * TAU
			spots.append({ "kind": "torch", "x": run.player.x + cos(a) * rng.randf_range(120.0, 400.0), "y": run.player.y + sin(a) * rng.randf_range(120.0, 400.0), "r": 12.0, "life": 60.0 })
	for s in spots:
		if String(s["kind"]) == "torch" and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < 22.0:
			s["kind"] = "torch_lit"
			run.light_t = 6.0
			var feared: int = 0
			for i in range(run.enemies.count):
				if Vector2(run.enemies.px[i], run.enemies.py[i]).distance_to(run.player) < 180.0:
					run.enemies.apply_status(i, "fear", 3.0)
					feared += 1
			if feared >= 8:
				flags["trample_kill"] = true
			_nova(run.player.x, run.player.y, 180.0, "#F0D890", 0.5)
	run.light_t = maxf(run.light_t - delta, 0.0)

# ---- ch11 可燃麦田 / 石柱
func _setup_burnable() -> void:
	for i in range(8):
		var a: float = TAU * float(i) / 8.0
		spots.append({ "kind": "wheat", "x": cos(a) * 240.0, "y": sin(a) * 240.0, "r": 80.0, "life": 1e9, "burn": 0.0 })
	for i in range(8):
		var b: float = TAU * float(i) / 8.0 + 0.3
		spots.append({ "kind": "pillar", "x": cos(b) * 360.0, "y": sin(b) * 360.0, "r": 14.0, "life": 1e9 })

func _t_burnable(delta: float) -> void:
	for s in spots:
		if String(s["kind"]) != "wheat":
			continue
		var wx: float = float(s["x"])
		var wy: float = float(s["y"])
		var burning: bool = float(s.get("burn", 0.0)) > 0.0
		if not burning:
			for i in range(run.enemies.count):
				if float(run.enemies.burn_t[i]) > 0.0 and Vector2(run.enemies.px[i], run.enemies.py[i]).distance_to(Vector2(wx, wy)) < float(s["r"]):
					s["burn"] = 6.0
					break
		if float(s.get("burn", 0.0)) > 0.0:
			s["burn"] = float(s["burn"]) - delta
			run.enemies.damage_in_circle(wx, wy, float(s["r"]), 14.0 * delta, "", 0.0, 0.0)
			flags["burnable_fire"] = true
			# 连环烧荒：点燃邻近麦田
			for o in spots:
				if String(o["kind"]) == "wheat" and float(o.get("burn", 0.0)) <= 0.0 and Vector2(float(o["x"]), float(o["y"])).distance_to(Vector2(wx, wy)) < 150.0:
					o["burn"] = 6.0
	# 石柱单独一轮判定（不能写在麦田循环里：上面的 continue 会让它永远走不到）
	for s in spots:
		if String(s["kind"]) == "pillar" and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < 24.0:
			s["kind"] = "pillar_down"
			run.enemies.damage_in_circle(float(s["x"]), float(s["y"]), 70.0, 300.0, "tremor", 0.0, 0.0)
			_nova(float(s["x"]), float(s["y"]), 80.0, "#C9A66B", 0.5)

# ---- ch12 亚杜兰洞：窄口 / 篝火
func _setup_cave() -> void:
	for sy in [-1.0, 1.0]:
		spots.append({ "kind": "rockwall", "x": 0.0, "y": 52.0 * sy, "r": 0.0, "gap": 34.0, "life": 1e9 })
	_ramp["fire_next"] = 90.0

func _t_cave(delta: float) -> void:
	var half: float = 10.0
	for s in spots:
		if String(s["kind"]) != "rockwall":
			continue
		var wy: float = float(s["y"])
		if absf(run.player.x) > float(s["gap"]) and absf(run.player.y - wy) < half:
			run.player = Vector2(clampf(run.player.x, -float(s["gap"]), float(s["gap"])), run.player.y)
	if run.elapsed >= float(_ramp.get("fire_next", 90.0)):
		_ramp["fire_next"] = float(_ramp["fire_next"]) + 90.0
		var p: Vector2 = _rand_around(80.0, 240.0)
		spots.append({ "kind": "campfire", "x": p.x, "y": p.y, "r": 16.0, "life": 40.0 })
	for s in spots:
		if String(s["kind"]) == "campfire" and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < 30.0:
			s["kind"] = "campfire_used"
			run.heal_player(float(run.player_max_hp) * 0.25)
			_toast("大卫勇士的篝火 · 回 25%", 1.6)

# ---- ch13 以拉谷：干涸溪床 / 光滑石子
func _setup_dry_creek() -> void:
	spots.append({ "kind": "creek", "x": 0.0, "y": 0.0, "r": 0.0, "half_h": 46.0, "life": 1e9 })
	_ramp["stone_next"] = 45.0
	_ramp["stones"] = 0

func _t_dry_creek(delta: float) -> void:
	if int(_ramp.get("stones", 0)) < 5 and run.elapsed >= float(_ramp.get("stone_next", 45.0)):
		_ramp["stone_next"] = float(_ramp["stone_next"]) + 45.0
		var a: float = rng.randf() * TAU
		spots.append({ "kind": "stone", "x": run.player.x + cos(a) * rng.randf_range(60.0, 260.0), "y": run.player.y + sin(a) * rng.randf_range(60.0, 260.0), "r": 10.0, "life": 120.0 })
	for s in spots:
		if String(s["kind"]) == "stone" and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < 22.0:
			s["kind"] = "stone_taken"
			_ramp["stones"] = int(_ramp.get("stones", 0)) + 1
			counters["stones"] = int(_ramp["stones"])
			_toast("光滑石子 %d/5" % int(_ramp["stones"]), 1.4)
			run.sfx.play("pickup", -6.0, 1.05, 0.08)

# ---- ch14 迦密山：旱灾 / 倒水坛
func _t_drought(delta: float) -> void:
	if run.elapsed < 210.0:
		_patch("drought_dry", "heal_per_sec", "mul", 0.5)
		_patch("drought_dry_ls", "lifesteal", "mul", 0.5)
	if not _ramp.has("drought_next"):
		_ramp["drought_next"] = 210.0
	if run.elapsed >= float(_ramp["drought_next"]) and float(_ramp["drought_next"]) <= 420.0:
		_ramp["drought_next"] = float(_ramp["drought_next"]) + 210.0
		var p: Vector2 = _rand_around(60.0, 200.0)
		spots.append({ "kind": "water_altar", "x": p.x, "y": p.y, "r": 56.0, "life": 45.0, "stand": 0.0 })
		_toast("倒水坛 · 站圈注水", 2.0)
	for s in spots:
		if String(s["kind"]) != "water_altar":
			continue
		if Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) <= float(s["r"]):
			s["stand"] = float(s["stand"]) + delta
		if float(s["stand"]) >= 4.0 or (run.sim_mode and float(s["stand"]) >= 3.0):
			s["kind"] = "water_done"
			run.stat_patch.remove("drought_dry")
			run.stat_patch.remove("drought_dry_ls")
			_patch("drought_reverse", "heal_per_sec", "mul", 1.5)
			run.enemies.damage_in_circle(run.player.x, run.player.y, 900.0, 400.0, "burn", 8.0, 0.0)
			_nova(run.player.x, run.player.y, 420.0, "#FF8A3C", 0.9)
			flags["carmel_fire"] = true
			flags["max_burn_kill"] = true
			_toast("迦密天火 · 回血反转 +50%", 3.0)

# ---- ch15 鱼腹 / 烈日荒原
func _t_belly(delta: float) -> void:
	if run.elapsed < 360.0:
		var limit: float = maxf(260.0, 500.0 - run.elapsed * 0.66)
		if run.player.length() > limit:
			run.player = run.player.normalized() * limit
		if not _ramp.has("acid_next"):
			_ramp["acid_next"] = 8.0
		if run.elapsed >= float(_ramp["acid_next"]):
			_ramp["acid_next"] = float(_ramp["acid_next"]) + 8.0
			var p: Vector2 = _rand_around(60.0, 280.0)
			_hazard(p.x, p.y, 26.0, 0.8, 12.0)
	else:
		# 360s 后进入烈日荒原：先补 3 处蓖麻树荫，否则每秒掉血无处可躲
		if not _ramp.has("shade_spawned"):
			_ramp["shade_spawned"] = true
			for k in range(3):
				var a: float = TAU * float(k) / 3.0 + 0.5
				spots.append({ "kind": "shade", "x": cos(a) * 240.0, "y": sin(a) * 240.0, "r": 90.0, "life": 1e9 })
			_toast("烈日荒原 · 站进蓖麻树荫", 2.4)
		var sheltered: bool = false
		for s in spots:
			if String(s["kind"]) == "shade" and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < float(s["r"]):
				sheltered = true
		if sheltered:
			_patch("belly_shade", "cooldown_mult", "mul", 0.8)
		else:
			_patch("belly_shade", "cooldown_mult", "mul", 1.0)
			run.hurt_player_dot(1.0 * delta)

# ---- ch16 烈火窑 / 狮坑
func _t_furnace(delta: float) -> void:
	if run.player.length() < 180.0:
		run.hurt_player_dot(0.5 * delta)
		_ramp["inner_t"] = float(_ramp.get("inner_t", 0.0)) + delta
		if float(_ramp["inner_t"]) >= 120.0:
			flags["furnace_inner_zone"] = true
	if not _ramp.has("lion_next"):
		_ramp["lion_next"] = 45.0
	if run.elapsed >= float(_ramp["lion_next"]):
		_ramp["lion_next"] = float(_ramp["lion_next"]) + 45.0
		for k in range(3):
			_spawn_ring("beast", 1, 220.0, 340.0)

# ---- ch17 试探：昼夜 / 石饼
func _t_temptation(delta: float) -> void:
	var phase: float = fmod(run.elapsed, 120.0)
	var day: bool = phase < 60.0
	_ramp["day"] = 1.0 if day else 0.0
	if day:
		_patch("tempt_day", "damage_mult", "mul", 1.25)
		run.hurt_player_dot(1.5 * delta)
	else:
		_patch("tempt_day", "damage_mult", "mul", 1.0)
		_patch("tempt_night", "speed", "mul", 0.9)
	if not _ramp.has("bread_next"):
		_ramp["bread_next"] = 90.0
	if run.elapsed >= float(_ramp["bread_next"]):
		_ramp["bread_next"] = float(_ramp["bread_next"]) + 90.0
		var p: Vector2 = _rand_around(60.0, 220.0)
		spots.append({ "kind": "bread", "x": p.x, "y": p.y, "r": 16.0, "life": 40.0, "arm": 0.0 })
	for s in spots:
		if String(s["kind"]) != "bread":
			continue
		var d: float = Vector2(float(s["x"]), float(s["y"])).distance_to(run.player)
		if d > 32.0:
			continue
		s["arm"] = float(s.get("arm", 0.0)) + delta
		var eat: bool = false
		if run.sim_mode:
			eat = false
		elif Input.is_action_just_pressed("interact"):
			eat = true
		if eat:
			s["kind"] = "bread_eaten"
			run.heal_player(1e9)
			counters["bread_eaten"] = int(counters.get("bread_eaten", 0)) + 1
			_toast("吃了试探石饼 · BOSS 血量 +15%", 2.4)
		elif float(s["arm"]) >= 1.5:
			s["kind"] = "bread_broken"
			flags["smash_all_bread"] = true
			run.enemies.damage_in_circle(run.player.x, run.player.y, 220.0, 120.0, "tremor", 0.0, 200.0)
			_patch("tempt_hyper", "damage_mult", "mul", 1.3)
			_patch("tempt_hyper_spd", "speed", "mul", 1.2)
			_ramp["hyper_t"] = 15.0
			_nova(run.player.x, run.player.y, 220.0, "#F3E3A8", 0.6)
			_toast("打碎石饼 · 15 秒亢奋", 2.0)
	_ramp["hyper_t"] = maxf(float(_ramp.get("hyper_t", 0.0)) - delta, 0.0)
	if float(_ramp.get("hyper_t", 0.0)) <= 0.0:
		run.stat_patch.remove("tempt_hyper")
		run.stat_patch.remove("tempt_hyper_spd")

# ---- ch18 加利利风暴
func _t_storm(delta: float) -> void:
	if not _ramp.has("storm_next"):
		_ramp["storm_next"] = 45.0
		_ramp["wind_dir"] = 1.0
	if run.elapsed >= float(_ramp["storm_next"]):
		_ramp["storm_next"] = float(_ramp["storm_next"]) + 45.0
		_ramp["wind_t"] = 12.0
		_ramp["wind_dir"] = -float(_ramp["wind_dir"])
		_toast("狂风巨浪 · 全场横向推移", 1.8)
	var calm: bool = float(_ramp.get("calm_t", 0.0)) > 0.0
	_ramp["calm_t"] = maxf(float(_ramp.get("calm_t", 0.0)) - delta, 0.0)
	_ramp["wind_t"] = maxf(float(_ramp.get("wind_t", 0.0)) - delta, 0.0)
	if float(_ramp["wind_t"]) > 0.0 and not calm:
		var push: float = 28.0 * float(_ramp["wind_dir"]) * delta
		run.player = Vector2(run.player.x + push, run.player.y)
		for i in range(run.enemies.count):
			run.enemies.px[i] = float(run.enemies.px[i]) + push
	if not _ramp.has("lantern_done"):
		var a: float = rng.randf() * TAU
		spots.append({ "kind": "lantern", "x": run.player.x + cos(a) * 200.0, "y": run.player.y + sin(a) * 200.0, "r": 14.0, "life": 1e9 })
		_ramp["lantern_done"] = true
	for s in spots:
		if String(s["kind"]) == "lantern" and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < 26.0:
			_ramp["calm_t"] = 20.0
			_patch("storm_aura", "heal_per_sec", "add", 1.0)
			for i in range(run.enemies.count):
				if Vector2(run.enemies.px[i], run.enemies.py[i]).distance_to(run.player) < 90.0:
					run.enemies.apply_status(i, "wet", 3.0)
			_toast("点亮船尾灯笼 · 风浪平息", 1.8)

# ---- ch19 五旬节火舌
func _t_pentecost(delta: float) -> void:
	if not _ramp.has("fire_next"):
		_ramp["fire_next"] = 75.0
	if run.elapsed >= float(_ramp["fire_next"]):
		_ramp["fire_next"] = float(_ramp["fire_next"]) + 75.0
		for k in range(3):
			var p: Vector2 = _rand_around(60.0, 260.0)
			pickups.append({ "kind": "tongue", "x": p.x, "y": p.y, "r": 14.0, "life": 30.0 })
		_toast("圣灵如火舌 · 拾取得能力", 1.8)

# ---- ch20 腓立比地震
func _t_prison(delta: float) -> void:
	if not _ramp.has("quake_next"):
		_ramp["quake_next"] = 120.0
	if run.elapsed >= float(_ramp["quake_next"]):
		_ramp["quake_next"] = float(_ramp["quake_next"]) + 120.0
		for i in range(run.enemies.count):
			run.enemies.apply_status(i, "tremor", 3.0)
		for k in range(2):
			var p: Vector2 = _rand_around(80.0, 260.0)
			spots.append({ "kind": "door", "x": p.x, "y": p.y, "r": 18.0, "life": 40.0 })
		_nova(run.player.x, run.player.y, 500.0, "#C8D0D8", 0.8)
		_toast("午夜赞美诗 · 大地震动", 2.2)
	for s in spots:
		if String(s["kind"]) == "door" and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < 26.0:
			s["kind"] = "door_open"
			run._grant_armor()
			run.rewards.spawn_chest("silver", float(s["x"]), float(s["y"]))

# ---- ch21 七灯台
func _setup_lamps() -> void:
	for i in range(7):
		var a: float = TAU * float(i) / 7.0
		spots.append({ "kind": "lamp", "x": cos(a) * 220.0, "y": sin(a) * 220.0, "r": 40.0, "life": 1e9, "lit": 0.0, "idx": i })

func _t_lamps(delta: float) -> void:
	if not _ramp.has("lamp_next"):
		_ramp["lamp_next"] = 40.0
	if run.elapsed >= float(_ramp["lamp_next"]):
		_ramp["lamp_next"] = float(_ramp["lamp_next"]) + 40.0
		var lamps: Array = []
		for s in spots:
			if String(s["kind"]) == "lamp":
				lamps.append(s)
		for k in range(2):
			if not lamps.is_empty():
				var s2: Dictionary = lamps[rng.randi_range(0, lamps.size() - 1)]
				s2["lit"] = 1.0
				s2["life"] = 1e9
				counters["lamp_lit_%d" % int(s2.get("idx", 0))] = true
				var lit_n: int = 0
				for kk in counters:
					if String(kk).begins_with("lamp_lit_"):
						lit_n += 1
				if lit_n >= 7:
					flags["lamps_7"] = true
	for s in spots:
		if String(s["kind"]) != "lamp":
			continue
		s["lit"] = maxf(float(s.get("lit", 0.0)) - delta, 0.0)
		if float(s["lit"]) > 0.0 and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < float(s["r"]):
			var idx: int = int(counters.get("lamp_idx", 0)) % 3
			match idx:
				0:
					_patch("lamp_bless", "damage_mult", "mul", 1.15)
				1:
					run.mech_shield = true
				2:
					for i in range(run.enemies.count):
						if Vector2(run.enemies.px[i], run.enemies.py[i]).distance_to(run.player) < 130.0:
							run.enemies.apply_status(i, "tremor", 1.0)
			counters["lamp_idx"] = int(counters.get("lamp_idx", 0)) + 1

# ---- ch22 无底坑井口
func _setup_vents() -> void:
	for i in range(3):
		var a: float = TAU * float(i) / 3.0 + 0.2
		spots.append({ "kind": "vent", "x": cos(a) * 300.0, "y": sin(a) * 300.0, "r": 34.0, "life": 1e9, "seal": 0.0, "sealed": false })

func _t_vents(delta: float) -> void:
	var live: int = 0
	for s in spots:
		if String(s["kind"]) != "vent" or bool(s["sealed"]):
			continue
		live += 1
		if Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < 44.0:
			s["seal"] = float(s["seal"]) + delta
			if float(s["seal"]) >= 4.0:
				s["sealed"] = true
				run.rewards.spawn_chest("silver", float(s["x"]), float(s["y"]))
				_toast("井口封印 · 银箱", 1.8)
	if not _ramp.has("vent_next"):
		_ramp["vent_next"] = 5.0
	if run.elapsed >= float(_ramp["vent_next"]):
		_ramp["vent_next"] = float(_ramp["vent_next"]) + 5.0
		for s in spots:
			if String(s["kind"]) == "vent" and not bool(s["sealed"]):
				_spawn_ring("smoke_specter", 1, 20.0, 40.0)
				_spawn_ring("iron_locust", 1, 20.0, 40.0)

# ---- ch23 陨星火雨 / 精英方阵
func _t_meteor(delta: float) -> void:
	if not _ramp.has("meteor_next"):
		_ramp["meteor_next"] = 60.0
	if run.elapsed >= float(_ramp["meteor_next"]):
		_ramp["meteor_next"] = float(_ramp["meteor_next"]) + 60.0
		for k in range(8):
			var p: Vector2 = _rand_around(40.0, 380.0)
			_hazard(p.x, p.y, 60.0, 1.0, 120.0)
		for k in range(4):
			var a: float = TAU * float(k) / 4.0
			var ti: int = run.enemies.type_index_of("six_finger_giant")
			if ti >= 0:
				run.enemies.spawn(ti, run.player.x + cos(a) * 280.0, run.player.y + sin(a) * 280.0)
		run.shake = maxf(run.shake, 6.0)
		_toast("倾倒的大城 · 陨星与方阵", 2.4)

# ---- ch24 玻璃海
func _setup_glass_sea() -> void:
	_ramp["glass"] = 0.0
	_ramp["sanct_next"] = 90.0
	_ramp["melt_cd"] = 0.0

func _t_glass(delta: float) -> void:
	if run.elapsed < 360.0:
		return
	_ramp["glass"] = 1.0
	_ramp["melt_cd"] = maxf(float(_ramp.get("melt_cd", 0.0)) - delta, 0.0)
	if float(_ramp["melt_cd"]) <= 0.0:
		for i in range(run.enemies.count):
			if float(run.enemies.burn_t[i]) > 0.0 or float(run.enemies.wet_t[i]) > 0.0:
				run.enemies.damage_in_circle(run.enemies.px[i], run.enemies.py[i], 90.0, 160.0, "burn", 4.0, 0.0)
				_nova(float(run.enemies.px[i]), float(run.enemies.py[i]), 90.0, "#8FC8E0", 0.4)
				_ramp["melt_cd"] = 0.6
				break
	if run.elapsed >= float(_ramp["sanct_next"]):
		_ramp["sanct_next"] = float(_ramp["sanct_next"]) + 90.0
		var p: Vector2 = _rand_around(60.0, 240.0)
		spots.append({ "kind": "sanctuary", "x": p.x, "y": p.y, "r": 26.0, "life": 30.0 })
	for s in spots:
		if String(s["kind"]) == "sanctuary" and Vector2(float(s["x"]), float(s["y"])).distance_to(run.player) < 30.0:
			s["kind"] = "sanctuary_used"
			run.heal_player(1e9)
			_toast("圣所光柱 · 全额回血", 1.8)

# ================================================================ 地形与判定

func _apply_terrain() -> void:
	var spd: float = 1.0
	var cdm: float = 1.0
	var p: Vector2 = run.player
	match id:
		"dry_creek":
			if absf(p.y) <= 46.0:
				cdm *= 0.9
		"flood_tide":
			var on_high: bool = false
			for s in spots:
				if String(s["kind"]) == "platform" and p.distance_to(Vector2(float(s["x"]), float(s["y"]))) <= float(s["r"]):
					on_high = true
			if on_high:
				cdm *= 1.0 / 1.15
			elif float(_ramp.get("tide", 0.0)) > 0.0:
				spd *= 0.75
		"eden_fall":
			for s in spots:
				if String(s["kind"]) == "thorn" and p.distance_to(Vector2(float(s["x"]), float(s["y"]))) <= float(s["r"]):
					spd *= 0.7
					break
		"sea_walls":
			if float(_ramp.get("wall_hit", 0.0)) > 0.0:
				pass
		"belly_shade":
			if run.elapsed >= 360.0:
				for s in spots:
					if String(s["kind"]) == "shade" and p.distance_to(Vector2(float(s["x"]), float(s["y"]))) <= float(s["r"]):
						cdm *= 0.8
	run.stat_patch.add("mech_terrain", "speed", "mul", spd)
	run.stat_patch.add("mech_terrain", "cooldown_mult", "mul", cdm)

func _tick_spots(delta: float) -> void:
	var i: int = spots.size() - 1
	while i >= 0:
		var s: Dictionary = spots[i]
		if String(s["kind"]) in ["creek", "platform", "bitter", "ancient_altar", "city_wall", "rockwall"]:
			i -= 1
			continue
		if float(s.get("life", 1e9)) < 1e8:
			s["life"] = float(s["life"]) - delta
		if float(s.get("life", 1e9)) <= 0.0:
			spots.remove_at(i)
		i -= 1

func _tick_hazards(delta: float) -> void:
	var i: int = hazards.size() - 1
	while i >= 0:
		var h: Dictionary = hazards[i]
		h["t"] = float(h["t"]) - delta
		if float(h["t"]) <= 0.0:
			var n: int = run.enemies.damage_in_circle(float(h["x"]), float(h["y"]), float(h["r"]), float(h["dmg"]), String(h.get("status", "")), 0.0, 0.0)
			if n > 0 and String(h.get("tag", "")) == "lightning":
				flags["lightning_kill"] = true
			if bool(h.get("player", true)) and Vector2(float(h["x"]), float(h["y"])).distance_to(run.player) <= float(h["r"]) and run.dash_iframe <= 0.0:
				run.hurt_player(float(h.get("pdmg", h["dmg"])))
			_nova(float(h["x"]), float(h["y"]), float(h["r"]), "#F0D890", 0.35)
			hazards.remove_at(i)
		i -= 1

func _tick_pickups(delta: float) -> void:
	var i: int = pickups.size() - 1
	while i >= 0:
		var p: Dictionary = pickups[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			pickups.remove_at(i)
		elif Vector2(float(p["x"]), float(p["y"])).distance_to(run.player) < float(p.get("r", 14.0)):
			match String(p["kind"]):
				"tongue":
					_patch("pente_cd", "cooldown_mult", "mul", 0.6)
					_ramp["pente_t"] = 10.0
					# 弹幕附加【圣火+致盲】需要 weapon_runner 读取 state meta；
					# 战斗侧还没消费前，先给身边 160px 的敌人挂上同样的状态作为可见反馈。
					for ei in range(run.enemies.count):
						if Vector2(run.enemies.px[ei], run.enemies.py[ei]).distance_to(run.player) < 160.0:
							run.enemies.apply_status(ei, "burn", 4.0)
							run.enemies.apply_status(ei, "blind", 2.0)
					_toast("火舌 · 10 秒冷却 -40%", 1.8)
			pickups.remove_at(i)
		i -= 1
	_ramp["pente_t"] = maxf(float(_ramp.get("pente_t", 0.0)) - delta, 0.0)
	if float(_ramp.get("pente_t", 0.0)) <= 0.0:
		run.stat_patch.remove("pente_cd")

# ================================================================ 工具

func _patch(pid: String, key: String, op: String, val: float) -> void:
	run.stat_patch.add(pid, key, op, val)

func _spawn_ring(enemy_id: String, n: int, rmin: float, rmax: float) -> void:
	var ti: int = run.enemies.type_index_of(enemy_id)
	if ti < 0:
		return
	for k in range(n):
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(rmin, rmax)
		run.enemies.spawn(ti, run.player.x + cos(a) * d, run.player.y + sin(a) * d)

func _hazard(x: float, y: float, r: float, delay: float, dmg: float, hit_player: bool = true, tag: String = "", pdmg: float = -1.0) -> void:
	hazards.append({ "x": x, "y": y, "r": r, "t": delay, "dmg": dmg, "player": hit_player, "tag": tag, "pdmg": dmg if pdmg < 0.0 else pdmg })

func _nova(x: float, y: float, r: float, color: String, life: float = 0.45) -> void:
	run.active_fx.append({ "kind": "nova", "x": x, "y": y, "r": r, "life": life, "color": Color(color) })

func _toast(text: String, t: float = 1.6) -> void:
	run.toast_text = text
	run.toast_t = t

func _rand_around(rmin: float, rmax: float) -> Vector2:
	var a: float = rng.randf() * TAU
	var d: float = rng.randf_range(rmin, rmax)
	return run.player + Vector2(cos(a) * d, sin(a) * d)

func _on_spot(kind: String, pos: Vector2, r: float) -> bool:
	for s in spots:
		if String(s["kind"]) == kind and pos.distance_to(Vector2(float(s["x"]), float(s["y"]))) <= r:
			return true
	return false

# ================================================================ 给 UI / 渲染

## 地形标签：以前直接把 kind（英文 id）糊到画面上（"tree"、"wheat"），改成中文短名，无对应名字就不画
const SPOT_NAMES := {
	"platform": "高台", "bitter": "苦水", "ancient_altar": "古坛", "lamp": "灯台", "vent": "地气",
	"wheat": "麦田", "shade": "荫下", "campfire": "营火", "tree": "分别善恶树", "tree_withered": "枯树",
	"blood": "血田", "sanctuary": "至圣所", "water_altar": "洗濯盆", "pillar": "石柱", "torch": "火把",
	"snake": "铜蛇", "door": "门", "bread": "陈设饼", "stone": "石头", "lantern": "灯", "creek": "溪床",
}

func _spot_label(k: String) -> String:
	return String(SPOT_NAMES.get(k, ""))

func draw_data() -> Array:
	var out: Array = []
	for s in spots:
		var k: String = String(s["kind"])
		if k in ["creek"]:
			out.append({ "kind": "band", "x": 0.0, "y": 0.0, "h": float(s.get("half_h", 46.0)) * 2.0, "w": 1400.0, "color": "#7FE0C0", "alpha": 0.10 })
		elif k in ["platform", "bitter", "ancient_altar", "lamp", "vent", "wheat", "shade", "campfire", "tree", "tree_withered", "blood", "sanctuary", "water_altar", "creek"]:
			out.append({ "kind": "circle", "x": float(s["x"]), "y": float(s["y"]), "r": float(s.get("r", 30.0)), "color": _spot_color(k), "alpha": 0.18 if k != "lamp" else (0.32 if float(s.get("lit", 0.0)) > 0.0 else 0.08), "label": _spot_label(k) })
		elif k in ["city_wall", "rockwall"]:
			out.append({ "kind": "circle", "x": float(s["x"]), "y": float(s["y"]), "r": float(s.get("r", 160.0)), "color": "#8A8378", "alpha": 0.30 })
		elif k in ["pillar", "torch", "snake", "door", "bread", "stone", "lantern", "campfire"]:
			out.append({ "kind": "prop", "x": float(s["x"]), "y": float(s["y"]), "r": float(s.get("r", 10.0)), "color": _spot_color(k), "label": _spot_label(k) })
	for h in hazards:
		out.append({ "kind": "hazard", "x": float(h["x"]), "y": float(h["y"]), "r": float(h["r"]), "color": "#F0D890", "progress": clampf(1.0 - float(h["t"]) / 1.5, 0.0, 1.0) })
	for p in pickups:
		out.append({ "kind": "pickup", "x": float(p["x"]), "y": float(p["y"]), "r": float(p.get("r", 14.0)), "color": "#F3E3A8", "label": "" })
	if id == "sea_walls":
		for s in spots:
			if String(s["kind"]) == "wall":
				out.append({ "kind": "wall", "x": float(s["x"]), "y": float(s["y"]), "h": float(s.get("h", 900.0)), "color": "#4F86B8", "alpha": 0.35 })
	if float(run.vision_radius) > 0.0:
		out.append({ "kind": "vision", "r": float(run.vision_radius) if run.light_t <= 0.0 else 190.0 })
	if id == "glass_sea" and run.elapsed >= 360.0:
		out.append({ "kind": "overlay", "color": "#8FC8E0", "alpha": 0.10 })
	return out

func _spot_color(k: String) -> String:
	match k:
		"platform": return "#C9A66B"
		"bitter", "blood": return "#8A3A3A"
		"ancient_altar": return "#E0B85A"
		"lamp": return "#F0D890"
		"vent": return "#4A3A5A"
		"wheat": return "#C9B45A"
		"shade": return "#6B8A5A"
		"water_altar": return "#8FC8E0"
		"sanctuary": return "#F3E3A8"
		"tree", "tree_withered": return "#7A5A3A"
		_: return "#C8D0D8"

## 给 HUD 的一行机关提示
func hint() -> String:
	match id:
		# 「CD -10%」里的 % 必须写成 %%：这行后面用 % 运算符填石数，裸 % 会被当成格式符
		"dry_creek": return "干涸溪床 · 站上降温  CD -10%% ｜ 石 %d/5" % int(counters.get("stones", 0))
		"lightning_zones": return "十诫雷击 · 圈落前离开"
		"drought_fire": return "旱灾 · 回血减半；天火祭坛注水反转"
		"altar_charge": return "亚伯拉罕古坛 · 圈内每 40 杀召金羊"
		"wall_ring": return "耶利哥城墙 · 绕跑 %d/7 圈" % int(float(_ramp.get("lap", 0.0)) / TAU)
		"temptation_choice": return "试探 · 昼伤 +25% ｜ 石饼：吃回复满血/打碎亢奋"
		"glass_sea": return "玻璃海 · 活水+圣火连锁爆炸"
		"meteor_horde": return "倾倒的大城 · 陨星火雨与精英方阵"
		"seven_lamps": return "七灯台 · 站亮灯得祝福"
		"abyss_vents": return "无底坑 · 站井口 4 秒封印"
		"flood_tide": return "涨潮 · 上方舟木台"
		"babel_confusion": return "变乱口音 · 敌军弹幕反噬"
		"sea_walls": return "红海合拢 · 退向中央"
		"bitter_water": return "玛拉苦水 · 避开苦水池"
		"darkness_lamp": return "黑夜 · 打破火把瓦罐照亮"
		"burnable_field": return "麦田 · 圣火引发烧荒"
		"cave_choke": return "亚杜兰洞 · 窄口与篝火"
		"belly_shade": return "鱼腹 → 烈日荒原 · 找蓖麻树荫"
		"furnace_rings": return "烈火窑内圈 · 双倍经验"
		"storm_push": return "狂风巨浪 · 点亮船尾灯笼"
		"pentecost_rush": return "火舌 · 拾取得冷却 -40%"
		"prison_quake": return "午夜地震 · 铁牢门掉军装"
		"eden_fall": return "分别善恶树 · 吃果或持守"
		"plague_cycle": return "十灾轮换"
	return ""
