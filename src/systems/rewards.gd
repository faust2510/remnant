class_name RunRewards
extends RefCounted
## 奖励与掉落（第 2 波 · 局内系统）。
## 覆盖：经验宝石分级与合并（防卡顿）、三档宝箱（精英/定向/城墙掉落）、
## 战场奇物（陶罐掉落）、祷告祭圈、约柜护送、局内银两。
## gems 与 run.gems 是同一个 Array 引用，渲染层无需改动。

const PROP_TARGET := 8
const PROP_RESPAWN := 20.0
const MERGE_CAP := 120          # 场上未拾取宝石超过 120 颗开始合体（圣典 220 的保守值）
const MERGE_BATCH := 20
const CHEST_R := 26.0
const PICKUP_R := 24.0
const CIRCLE_TIMES := [300.0, 570.0]
const CIRCLE_STAND := 10.0
const ARK_AT := 420.0
const ARK_SPEED := 32.0
const ARK_LIFE := 25.0

var run: Node
var gems: Array = []
var chests: Array = []
var props: Array = []
var pickups: Array = []
var circles: Array = []
var silver_run: int = 0
var meta_silver_bonus: int = 0
var ark: Dictionary = {}
var flags: Dictionary = {}
var rng := RandomNumberGenerator.new()

var _prop_t: float = 0.0
var _merge_t: float = 0.0
var _circle_done: int = 0
var _ark_done: bool = false
var _buffs: Dictionary = {}     # patch id -> 剩余秒
var _delayed: Array = []        # {t, fn 用 kind 描述}

func setup(r: Node) -> void:
	run = r
	gems = run.gems
	rng.seed = int(run.rng.randi())
	for i in range(PROP_TARGET):
		_spawn_prop()

func tick(delta: float) -> void:
	if run.over:
		return
	_tick_buffs(delta)
	_tick_chests(delta)
	_tick_pickups(delta)
	_tick_props(delta)
	_tick_circles(delta)
	_tick_ark(delta)
	_tick_delayed(delta)
	_merge_t += delta
	if _merge_t >= 0.5:
		_merge_t = 0.0
		_merge_gems()

# ---------------------------------------------------------------- 经验宝石

## 按圣典 11.1 的四档给宝石定性（渲染层可用，不影响数值）。
static func gem_tier(val: int) -> Dictionary:
	if val >= 100:
		return { "name": "星辰王冠石", "color": "#BFD4FF" }
	if val >= 25:
		return { "name": "绯红圣晶", "color": "#F07A9A" }
	if val >= 4:
		return { "name": "金黄宝石", "color": "#F0D890" }
	return { "name": "青绿微晶", "color": "#7FE0C0" }

func add_gem(x: float, y: float, val: int) -> void:
	if val <= 0:
		return
	var t: Dictionary = gem_tier(val)
	gems.append({ "x": x, "y": y, "val": val, "tier": String(t["name"]), "color": String(t["color"]) })

## 场上宝石过多时，把「离玩家最远」的 20 颗低价值宝石合成 1 颗星辰石。
## 目的：防止 gems 数组与渲染循环在后期爆炸（契约要求）。
func _merge_gems() -> void:
	if gems.size() <= MERGE_CAP:
		return
	var candidates: Array = []
	for i in range(gems.size()):
		var g: Dictionary = gems[i]
		var d: float = Vector2(float(g["x"]), float(g["y"])).distance_to(run.player)
		candidates.append({ "i": i, "d": d, "val": int(g["val"]) })
	candidates.sort_custom(func(a, b): return float(a["d"]) > float(b["d"]))
	var take: Array = []
	for c in candidates:
		if take.size() >= MERGE_BATCH:
			break
		if int(c["val"]) < 100:
			take.append(int(c["i"]))
	if take.size() < MERGE_BATCH:
		take.clear()
		for c in candidates:
			if take.size() >= MERGE_BATCH:
				break
			take.append(int(c["i"]))
	if take.size() < 2:
		return
	var sum: int = 0
	var sx: float = 0.0
	var sy: float = 0.0
	for i in take:
		var g: Dictionary = gems[i]
		sum += int(g["val"])
		sx += float(g["x"])
		sy += float(g["y"])
	take.sort()
	for k in range(take.size() - 1, -1, -1):
		gems.remove_at(int(take[k]))
	var t: Dictionary = gem_tier(maxi(sum, 100))
	gems.append({ "x": sx / float(take.size()), "y": sy / float(take.size()), "val": mini(sum, 9999), "tier": "星辰王冠石", "color": String(t["color"]), "merged": true })

# ---------------------------------------------------------------- 宝箱

func spawn_chest(tier: String, x: float, y: float) -> void:
	chests.append({ "tier": tier, "x": x, "y": y, "t": 0.0, "opened": false })

## 精英死亡：150/330 掉铜，510/630 掉银（圣典 11.2）。
func on_elite_killed(x: float, y: float) -> void:
	var tier: String = "silver" if run.elapsed >= 480.0 else "bronze"
	spawn_chest(tier, x, y)

func _tick_chests(delta: float) -> void:
	var i: int = chests.size() - 1
	while i >= 0:
		var c: Dictionary = chests[i]
		c["t"] = float(c["t"]) + delta
		if Vector2(float(c["x"]), float(c["y"])).distance_to(run.player) < CHEST_R:
			_open_chest(c)
			chests.remove_at(i)
		i -= 1

func _open_chest(c: Dictionary) -> void:
	var tier: String = String(c["tier"])
	var lv: int = 1
	var silver: int = 25
	var heal: float = 0.15
	if tier == "silver":
		lv = 3
		silver = 60
		heal = 0.30
	elif tier == "gold":
		lv = 5
		silver = 150
		heal = 0.30
		run._grant_armor()
	# 圣物 R12：宝箱银两翻倍
	if _has_relic_effect("chest_double"):
		silver *= 2
	run.pending_levels += lv
	_heal(float(run.player_max_hp) * heal)
	silver_run += silver
	if run.sim_mode:
		print("[sim] chest %s silver=%d lv=%d t=%.0f" % [tier, silver, lv, run.elapsed])
	run.active_fx.append({ "kind": "nova", "x": float(c["x"]), "y": float(c["y"]), "r": 90.0, "life": 0.5, "color": Color("#E0B85A") })
	run.toast_text = "%s宝箱 · +%d 银" % [ { "bronze": "铜", "silver": "银", "gold": "金" }.get(tier, "铜"), silver ]
	run.toast_t = 1.6
	run.sfx.play("pickup", -3.0, 0.9, 0.2)

# ---------------------------------------------------------------- 战场奇物（陶罐）

func _spawn_prop() -> void:
	var a: float = rng.randf() * TAU
	var d: float = rng.randf_range(140.0, 620.0)
	props.append({ "x": run.player.x + cos(a) * d, "y": run.player.y + sin(a) * d, "broken": false, "hp": 10.0 })

func _tick_props(delta: float) -> void:
	var alive: int = 0
	for p in props:
		if not bool(p["broken"]):
			alive += 1
			if Vector2(float(p["x"]), float(p["y"])).distance_to(run.player) < 22.0:
				_break_prop(p)
	_prop_t += delta
	if alive < PROP_TARGET and _prop_t >= PROP_RESPAWN:
		_prop_t = 0.0
		for k in range(PROP_TARGET - alive):
			_spawn_prop()

func _break_prop(p: Dictionary) -> void:
	p["broken"] = true
	run.active_fx.append({ "kind": "spark", "x": float(p["x"]), "y": float(p["y"]), "r": 5.0, "life": 0.3 })
	flags["pot_broken"] = true
	# 破瓶露光之约：破罐 → 全屏致盲+战兢 3s，随后 6s 冷却 -35%
	if bool(run.state.get_meta("covenant_broken_jar", false)):
		_status_all("blind", 3.0)
		_status_all("fear", 3.0)
		_buff("prop_broken_jar", "cooldown_mult", "mul", 0.65, 6.0)
	_spawn_drop(String(_roll_prop_drop()), float(p["x"]), float(p["y"]))

## 九大奇物权重（圣典 11.3）。火炭单独 6% 走 state.coals。
func _roll_prop_drop() -> String:
	var r: float = rng.randf()
	if r < 0.30:
		return "fig_cake"
	r -= 0.30
	if r < 0.20:
		return "manna"
	r -= 0.20
	if r < 0.10:
		return "elisha_salt"
	r -= 0.10
	if r < 0.12:
		return "gideon_jar"
	r -= 0.12
	if r < 0.08:
		return "silver_trumpet"
	r -= 0.08
	if r < 0.06:
		return "widows_oil"
	r -= 0.06
	if r < 0.06:
		return "david_pouch"
	r -= 0.06
	if r < 0.05:
		return "scapegoat_horn"
	r -= 0.05
	if r < 0.03:
		return "coal"
	return "pouch_of_silver"

func _spawn_drop(kind: String, x: float, y: float) -> void:
	pickups.append({ "kind": kind, "x": x, "y": y, "life": 30.0 })

func _tick_pickups(delta: float) -> void:
	var i: int = pickups.size() - 1
	while i >= 0:
		var p: Dictionary = pickups[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			pickups.remove_at(i)
		elif Vector2(float(p["x"]), float(p["y"])).distance_to(run.player) < PICKUP_R:
			_apply_pickup(String(p["kind"]))
			pickups.remove_at(i)
		i -= 1

func _apply_pickup(kind: String) -> void:
	match kind:
		"fig_cake":
			_heal(25.0)
		"manna":
			_heal(12.0)
			_buff("prop_manna", "xp_gain", "mul", 1.5, 12.0)
		"elisha_salt":
			run.shots.clear()
			run.toast_text = "盐 · 弹幕尽散"
			run.toast_t = 1.2
		"gideon_jar":
			_status_all("blind", 4.0)
			_status_all("fear", 4.0)
		"silver_trumpet":
			run.magnet_t = 4.0
		"widows_oil":
			_buff("prop_oil", "cooldown_mult", "mul", 0.35, 8.0)
		"david_pouch":
			_buff("prop_pouch_crit", "crit_chance", "add", 1.0, 10.0)
			_buff("prop_pouch_spd", "proj_speed_mult", "mul", 1.4, 10.0)
		"scapegoat_horn":
			_delayed.append({ "t": 6.0, "kind": "scapegoat", "x": float(run.player.x), "y": float(run.player.y) })
		"pouch_of_silver":
			meta_silver_bonus += 50
		"coal":
			run.state.coals += 1
			run.toast_text = "火炭 +1"
			run.toast_t = 1.0
	run.sfx.play("pickup", -8.0, randf_range(0.95, 1.15), 0.05)

func _status_all(status: String, dur: float) -> void:
	for i in range(run.enemies.count):
		run.enemies.apply_status(i, status, 0.0)

func _heal(amount: float) -> void:
	if amount <= 0.0:
		return
	run.heal_player(amount)
	# 活水江河之约：满血也触发治疗，并把治疗量转成冲击波
	if bool(run.state.get_meta("covenant_heal_wave", false)) and amount >= 1.0:
		run.enemies.damage_in_circle(run.player.x, run.player.y, 140.0, amount * 8.0, "wet", 0.0, 0.0)
		run.active_fx.append({ "kind": "nova", "x": run.player.x, "y": run.player.y, "r": 140.0, "life": 0.4, "color": Color("#8FC8E0") })

# ---------------------------------------------------------------- 祷告祭圈 / 约柜护送

func _tick_circles(delta: float) -> void:
	while _circle_done < CIRCLE_TIMES.size() and run.elapsed >= float(CIRCLE_TIMES[_circle_done]):
		_circle_done += 1
		var a: float = rng.randf() * TAU
		circles.append({ "x": run.player.x + cos(a) * 110.0, "y": run.player.y + sin(a) * 110.0, "r": 52.0, "stand": 0.0, "done": false, "life": 90.0 })
	for c in circles:
		if bool(c["done"]):
			continue
		c["life"] = float(c["life"]) - delta
		if float(c["life"]) <= 0.0:
			c["done"] = true
			continue
		if Vector2(float(c["x"]), float(c["y"])).distance_to(run.player) <= float(c["r"]):
			c["stand"] = float(c["stand"]) + delta
			if float(c["stand"]) >= CIRCLE_STAND or (run.sim_mode and float(c["stand"]) >= CIRCLE_STAND * 0.6):
				c["done"] = true
				run.state.coals += 1
				spawn_chest("bronze", float(c["x"]), float(c["y"]))
				run.toast_text = "祷告已满 · 火炭与铜箱"
				run.toast_t = 2.0

func _tick_ark(delta: float) -> void:
	if not _ark_done:
		if run.elapsed >= ARK_AT:
			_ark_done = true
			var dir: Vector2 = Vector2(1, 0).rotated(rng.randf() * TAU)
			ark = { "x": run.player.x + dir.x * 120.0, "y": run.player.y + dir.y * 120.0, "dir": dir, "life": ARK_LIFE, "done": false }
			run.toast_text = "约柜同行 · 护送 25 秒"
			run.toast_t = 2.2
		return
	if ark.is_empty() or bool(ark.get("done", true)):
		return
	ark["x"] = float(ark["x"]) + Vector2(ark["dir"]).x * ARK_SPEED * delta
	ark["y"] = float(ark["y"]) + Vector2(ark["dir"]).y * ARK_SPEED * delta
	ark["life"] = float(ark["life"]) - delta
	if Vector2(float(ark["x"]), float(ark["y"])).distance_to(run.player) < 72.0:
		_heal(2.0 * delta)
	if float(ark["life"]) <= 0.0:
		ark["done"] = true
		spawn_chest("gold", float(ark["x"]), float(ark["y"]))

func _tick_delayed(delta: float) -> void:
	var i: int = _delayed.size() - 1
	while i >= 0:
		var d: Dictionary = _delayed[i]
		d["t"] = float(d["t"]) - delta
		if float(d["t"]) <= 0.0:
			if String(d["kind"]) == "scapegoat":
				run.enemies.damage_in_circle(float(d["x"]), float(d["y"]), 220.0, 180.0, "fear", 0.0, 60.0)
				run.active_fx.append({ "kind": "nova", "x": float(d["x"]), "y": float(d["y"]), "r": 220.0, "life": 0.5, "color": Color("#D8B98A") })
			_delayed.remove_at(i)
		i -= 1

# ---------------------------------------------------------------- buff / 圣物工具

func _buff(id: String, key: String, op: String, val: float, dur: float) -> void:
	_buffs[id] = { "key": key, "op": op, "val": val, "t": dur }
	run.stat_patch.add(id, key, op, val)

func _tick_buffs(delta: float) -> void:
	for id in _buffs.keys():
		var b: Dictionary = _buffs[id]
		b["t"] = float(b["t"]) - delta
		if float(b["t"]) <= 0.0:
			run.stat_patch.remove(String(id))
			_buffs.erase(id)

func _has_relic_effect(name: String) -> bool:
	for id in run.state.relics:
		var d: Dictionary = GameData.relic_def(String(id))
		if String(d.get("effect", "")) == name:
			return true
	return false

# ---------------------------------------------------------------- 给 UI / 渲染

func draw_data() -> Array:
	var out: Array = []
	for c in circles:
		if bool(c["done"]):
			continue
		out.append({ "kind": "circle", "x": float(c["x"]), "y": float(c["y"]), "r": float(c["r"]), "color": "#9FD3C0", "alpha": 0.18, "progress": clampf(float(c["stand"]) / CIRCLE_STAND, 0.0, 1.0) })
	for c in chests:
		out.append({ "kind": "chest", "x": float(c["x"]), "y": float(c["y"]), "r": 10.0, "tier": String(c["tier"]), "color": { "bronze": "#C08A5A", "silver": "#C8D0D8", "gold": "#E0B85A" }.get(String(c["tier"]), "#C08A5A") })
	for p in props:
		if not bool(p["broken"]):
			out.append({ "kind": "pot", "x": float(p["x"]), "y": float(p["y"]), "r": 8.0, "color": "#5A4A3A" })
	for p in pickups:
		out.append({ "kind": "pickup", "x": float(p["x"]), "y": float(p["y"]), "r": 7.0, "label": String(p["kind"]), "color": "#7FE0C0" })
	if not ark.is_empty() and not bool(ark.get("done", true)):
		out.append({ "kind": "ark", "x": float(ark["x"]), "y": float(ark["y"]), "r": 16.0, "color": "#E0B85A" })
	return out
