class_name RunCovenants
extends RefCounted
## 约（Covenants）系统（第 2 波 · 局内系统）。
## 持有圣物 R05《乌陵与土明》时开启：0:00 抽第 1 张、6:00 抽第 2 张（每局最多 2 张）。
## 抽卡复用现有 Chooser（mode = "covenant"）。effects 通过 run.stat_patch 注入 stats，
## 特殊口径（槽位/门槛/治疗波）写在 state 的 meta 上，供 run/武器层按 id 读取。

const DRAW_TIMES := [0.0, 360.0]
const MAX_CARDS := 2
const RARITY_COLOR := { 1: "#9FD3C0", 2: "#E0B85A", 3: "#C79BE8" }
const RARITY_NAME := { 1: "常见", 2: "稀有", 3: "传说" }
## 这几条约的近似数值已被真实机制取代（见 _apply_special），不再叠加
const SKIP_APPROX := {
	"cov_seven_spirits": ["damage_mult"],
	"cov_david_throne": ["damage_mult", "area_mult"],
	"cov_alpha_omega": ["extra_projectile"]
}

var run: Node
var cards: Array = []          # 已生效的 covenant id
var drawn: int = 0
var enabled: bool = false
var rng := RandomNumberGenerator.new()

func setup(r: Node) -> void:
	run = r
	rng.seed = int(r.rng.randi())
	enabled = run.state.has_relic("R05") or has_relic_effect("covenant_system")

## 按 relics.json 的 effect 字段判断（R05 的 effect 是 covenant_system）。
func has_relic_effect(effect_name: String) -> bool:
	for id in run.state.relics:
		var d: Dictionary = GameData.relic_def(String(id))
		if String(d.get("effect", "")) == effect_name:
			return true
	return false

func tick(delta: float) -> void:
	if not enabled or run.over or drawn >= MAX_CARDS:
		return
	if run.modal:
		return
	if run.elapsed + 0.0001 >= float(DRAW_TIMES[drawn]):
		_open_draw()

func _open_draw() -> void:
	var pool: Array = []
	for c in GameData.covenants:
		var cid: String = String(c.get("id", ""))
		if cid != "" and not cards.has(cid):
			pool.append(cid)
	if pool.size() < 3:
		return
	var picked: Array = []
	while picked.size() < 3 and not pool.is_empty():
		var i: int = rng.randi_range(0, pool.size() - 1)
		picked.append(pool[i])
		pool.remove_at(i)
	var opts: Array = []
	for cid in picked:
		var d: Dictionary = GameData.covenant_def(String(cid))
		var rarity: int = int(d.get("rarity", 1))
		opts.append({
			"kind": "covenant",
			"id": String(cid),
			"name": String(d.get("name", cid)),
			"tag": "约 · %s（%s）" % [RARITY_NAME.get(rarity, "常见"), String(d.get("scripture", ""))],
			"desc": String(d.get("text", "")),
			"color": Color(String(RARITY_COLOR.get(rarity, "#E0B85A")))
		})
	run.modal = true
	run.chooser_mode = "covenant"
	run.current_options = opts
	run.chooser.open("约 · 乌陵与土明", opts, 0)
	run.sfx.play("level", -3.0, 1.08, 0.25)
	drawn += 1
	if run.sim_mode:
		print("[sim] covenant_draw n=%d pool=%s t=%.0f" % [drawn, str(picked), run.elapsed])

## 由 run._on_picked 在 mode == "covenant" 时调用。
func pick(index: int) -> void:
	if index < 0 or index >= run.current_options.size():
		return
	var o: Dictionary = run.current_options[index]
	var cid: String = String(o.get("id", ""))
	var d: Dictionary = GameData.covenant_def(cid)
	if d.is_empty():
		return
	cards.append(cid)
	if run.sim_mode:
		print("[sim] covenant_pick %s t=%.0f" % [cid, run.elapsed])
	# 已实装真机制的约，不再叠加数据里的「近似折算」数值，避免双算
	var skip: Array = SKIP_APPROX.get(cid, [])
	for e in d.get("effects", []):
		if skip.has(String(e.get("key", ""))):
			continue
		_apply_effect(cid, String(e.get("key", "")), e.get("value", 0))
	_apply_special(cid)
	run.stat_patch.apply()
	run._sync_max_hp()
	run.toast_text = "约 · " + String(d.get("name", cid))
	run.toast_t = 2.2
	run.active_fx.append({ "kind": "nova", "x": run.player.x, "y": run.player.y, "r": 170.0, "life": 0.6, "color": Color(String(RARITY_COLOR.get(int(d.get("rarity", 1)), "#E0B85A"))) })

func _apply_effect(cid: String, key: String, val: Variant) -> void:
	var v: float = float(val)
	match key:
		"damage_mult":
			run.stat_patch.add(cid, "damage_mult", "mul", 1.0 + v)
		"cooldown_mult":
			run.stat_patch.add(cid, "cooldown_mult", "mul", maxf(0.2, 1.0 + v))
		"area_mult":
			run.stat_patch.add(cid, "area_mult", "mul", 1.0 + v)
		"projectile_speed":
			run.stat_patch.add(cid, "proj_speed_mult", "mul", 1.0 + v)
		"move_speed":
			run.stat_patch.add(cid, "speed", "mul", 1.0 + v)
		"max_hp":
			run.stat_patch.add(cid, "max_hp", "mul", 1.0 + v)
		"xp_gain":
			run.stat_patch.add(cid, "xp_gain", "mul", 1.0 + v)
		"silver_gain":
			run.stat_patch.add(cid, "silver_mult", "mul", 1.0 + v)
		"knockback_mult":
			run.stat_patch.add(cid, "knockback_mult", "mul", 1.0 + v)
		"crit_chance":
			run.stat_patch.add(cid, "crit_chance", "add", v)
		"crit_damage":
			run.stat_patch.add(cid, "crit_mult", "add", v)
		"armor":
			run.stat_patch.add(cid, "armor", "add", v)
		"lifesteal":
			run.stat_patch.add(cid, "lifesteal", "add", v)
		"status_on_hit":
			var names: Array = run.state.get_meta("status_on_hit", [])
			if not names.has(String(val)):
				names.append(String(val))
			run.state.set_meta("status_on_hit", names)
		"extra_projectile":
			run.state.set_meta("extra_projectile", int(run.state.get_meta("extra_projectile", 0)) + int(v))

## 数据里写明「需引擎特判」的几条，先落最关键的语义。
func _apply_special(cid: String) -> void:
	match cid:
		"cov_sinai":
			run.state.set_meta("treasure_slots_delta", -1)
			run.state.set_meta("covenant_sinai", true)
		"cov_living_water":
			run.state.set_meta("covenant_heal_wave", true)
		"cov_sun_stand":
			run.state.set_meta("covenant_sun_stand", true)
		"cov_better_promise":
			run.state.set_meta("fusion_threshold_mult", 0.6)
			run.state.set_meta("covenant_better_promise", true)
		"cov_alpha_omega":
			# 真机制：line_projectile / homing 弹幕寿命耗尽时折返再穿透（weapon_runner + projectile_sim）。
			# 冷却 +20% 的代价由数据里的 cooldown_mult = 0.2 提供，这里不再重复叠加。
			run.state.set_meta("covenant_alpha_omega", true)
		"cov_david_throne":
			# 动态加成：按当前空格数在 game_state.recompute() 里实时计算
			run.state.set_meta("covenant_david_throne", true)
			run.state.recompute()
		"cov_seven_spirits":
			# 真机制：每带 1 种状态承受伤害 ×1.2（死亡时由 enemy_sim 结算）
			run.enemies.status_dmg_bonus = 0.2
		"cov_new_heart":
			run.state.set_meta("covenant_reflect", true)
		"cov_broken_jar":
			run.state.set_meta("covenant_broken_jar", true)

## UI/渲染用：已持有的约（含名称/稀有度/颜色/原文）。
func draw_data() -> Array:
	var out: Array = []
	for cid in cards:
		var d: Dictionary = GameData.covenant_def(String(cid))
		var rarity: int = int(d.get("rarity", 1))
		out.append({
			"id": String(cid),
			"name": String(d.get("name", cid)),
			"rarity": rarity,
			"color": String(RARITY_COLOR.get(rarity, "#E0B85A")),
			"text": String(d.get("text", ""))
		})
	return out

func title() -> String:
	return "约 " + str(cards.size()) + "/" + str(MAX_CARDS)
