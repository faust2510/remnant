class_name GameState
extends RefCounted
## 玩家构筑状态：见证人、武器槽、被动槽、衍生属性、等级经验。
## 纯 RefCounted，不依赖场景树 —— 无头模拟可以直接复用。

signal stats_changed
signal slots_changed

const BASE_WEAPON_SLOTS := 4
## 被动/宝物槽：v2 起固定 4 格（圣典：3 -> 4）。宝物 = kind 为 "treasure" 的被动，
## 与果子共用这 4 格，但另有 4 件的上限，防止全是宝物把祝圣必需的果子挤光。
const BASE_PASSIVE_SLOTS := 4
const BASE_TREASURE_SLOTS := 4
const XP_BASE := 8.0
const XP_GROWTH := 1.13

## 成全（Ascend）永久倍率：成全瞬间一次性算好，整包写进武器字典 entry["ascend_params"]，
## 之后每次开火/轨道结算都直接吃这份参数；recompute() 只重建 stats，不碰 weapons，所以不会被冲掉。
const ASCEND_COUNT_BONUS := 2      # 弹数 +2
const ASCEND_RADIUS_MULT := 1.35   # 范围半径 ×1.35
const ASCEND_DAMAGE_MULT := 1.25   # 单发伤害 ×1.25
const ASCEND_COOLDOWN_MULT := 0.85 # 冷却/节奏 ×0.85（环绕与领域类的 tick 同吃）
const ASCEND_RANGE_MULT := 1.12    # 射程/触达距离 ×1.12
const ASCEND_ARC_MULT := 1.1       # 近战扇角 ×1.1（上限 360°）

var character: Dictionary = {}
var weapons: Array = []          # [{id, kind:"base"|"fusion", level, ascended:bool}]
var passives: Array = []         # [{id, level}]
var consumed_weapons: Dictionary = {}   # 被祝圣吃掉的基础武器 id
var stats: Dictionary = {}
var meta_bonus: Dictionary = {}
var stage_cd: float = 1.0         # 营地永久强化，由 Meta.bonus() 提供

var armor: Array = []              # 全副军装：精英战利品，不占被动槽、不进升级池、不参与祝圣配方
## 圣物：局外用 Meta.unlock_relic 解锁，局内整局生效。这里只是 Meta.relics 的只读镜像。
var relics: Array = []
## 觉醒缓存：-1 未查过 / 0 未觉醒 / 1 已觉醒（3 印通关后由 Meta.awakened_ids 点亮）
var _awakened: int = -1

var level: int = 1
var xp: float = 0.0
var xp_need: float = XP_BASE
var kills: int = 0
var coals: int = 0
var ascended_count: int = 0

## relic_ids 留空时自动从 Meta.relics 拉取（局外解锁的圣物整局生效）。
func setup(character_id: String, bonus: Dictionary = {}, relic_ids: Array = []) -> void:
	meta_bonus = bonus
	character = GameData.characters_by_id.get(character_id, {})
	_awakened = -1
	relics = []
	var ids: Array = relic_ids if not relic_ids.is_empty() else _meta_relics()
	for rid in ids:
		add_relic(String(rid))
	weapons = []
	passives = []
	armor = []
	consumed_weapons = {}
	level = 1
	xp = 0.0
	xp_need = XP_BASE
	kills = 0
	coals = 0
	ascended_count = 0
	if not character.is_empty():
		add_weapon(String(character["weapon"]))
	recompute()

## 角色 perk 与「觉醒 perk」的合并读取。
## 数值键相加（乘性键 _mult 相乘），非数值键由觉醒覆盖；觉醒未点亮时只有角色 perk。
func perf(key: String, default_value: Variant = 0.0) -> Variant:
	var perk: Dictionary = character.get("perk", {})
	var has_base: bool = perk.has(key)
	var v: Variant = perk.get(key, default_value)
	var aw: Dictionary = _awakening_perk()
	if aw.is_empty() or not aw.has(key):
		return v
	var av: Variant = aw[key]
	var v_num: bool = typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
	var a_num: bool = typeof(av) == TYPE_INT or typeof(av) == TYPE_FLOAT
	if not (v_num and a_num):
		return av
	var mult: bool = key.ends_with("_mult")
	var base_num: float = float(v)
	if not has_base:
		base_num = 1.0 if mult else float(default_value)
	if mult:
		return base_num * float(av)
	return base_num + float(av)

func max_weapon_slots() -> int:
	return int(perf("weapon_slots", BASE_WEAPON_SLOTS))

func max_passive_slots() -> int:
	return BASE_PASSIVE_SLOTS + int(perf("passive_slots", 0.0))

## 这 4 格里最多能放几件宝物（圣典 v2：宝物槽 4）
func max_treasure_slots() -> int:
	return BASE_TREASURE_SLOTS + int(perf("treasure_slots", 0.0))

func treasure_count() -> int:
	var n: int = 0
	for p in passives:
		var def: Dictionary = GameData.passives.get(p["id"], {})
		if String(def.get("kind", "")) == "treasure":
			n += 1
	return n

func passive_def(entry: Dictionary) -> Dictionary:
	return GameData.passives.get(entry.get("id", ""), {})

func is_treasure(entry: Dictionary) -> bool:
	return String(passive_def(entry).get("kind", "")) == "treasure"

# ---------------------------------------------------------------- 圣物

func has_relic(id: String) -> bool:
	return relics.has(id)

## 局内加入圣物（只在本局 stats 里生效，不解锁存档；解锁走 Meta.unlock_relic）。
func add_relic(id: String) -> bool:
	if id.is_empty() or relics.has(id):
		return false
	if not GameData.relics_by_id.has(id):
		return false
	relics.append(id)
	return true

func relic_defs() -> Array:
	var out: Array = []
	for id in relics:
		var d: Dictionary = GameData.relics_by_id.get(id, {})
		if not d.is_empty():
			out.append(d)
	return out

# ---------------------------------------------------------------- 觉醒

func is_awakened() -> bool:
	if _awakened < 0:
		_awakened = 1 if _meta_is_awakened() else 0
	return _awakened == 1

## 觉醒 perk；未觉醒或该见证人没有 awakening 时返回空字典。
func _awakening_perk() -> Dictionary:
	if not is_awakened():
		return {}
	var aw: Variant = character.get("awakening", {})
	if typeof(aw) != TYPE_DICTIONARY:
		return {}
	var perk: Variant = aw.get("perk", {})
	if typeof(perk) != TYPE_DICTIONARY:
		return {}
	return perk

func _meta_node() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Meta")
	return null

func _meta_relics() -> Array:
	var meta: Node = _meta_node()
	if meta == null:
		return []
	var arr: Variant = meta.get("relics")
	if typeof(arr) != TYPE_ARRAY:
		return []
	return arr

func _meta_is_awakened() -> bool:
	var meta: Node = _meta_node()
	if meta == null or not meta.has_method("is_awakened"):
		return false
	return bool(meta.call("is_awakened", String(character.get("id", ""))))

func base_hp() -> float:
	return float(character.get("hp", 100))

func base_speed() -> float:
	return float(character.get("speed", 72))

# ---------------------------------------------------------------- 武器槽

func weapon_def(entry: Dictionary) -> Dictionary:
	if String(entry.get("kind", "base")) == "fusion":
		return GameData.fusion_by_id.get(entry["id"], {})
	return GameData.weapons.get(entry["id"], {})

func weapon_max_level(entry: Dictionary) -> int:
	var def: Dictionary = weapon_def(entry)
	if String(entry.get("kind", "base")) == "base":
		return int(def.get("max_level", 5))
	return 5

func has_weapon(id: String) -> bool:
	for w in weapons:
		if String(w["id"]) == id:
			return true
	return false

func add_weapon(id: String) -> bool:
	if weapons.size() >= max_weapon_slots():
		return false
	if has_weapon(id):
		return false
	weapons.append({ "id": id, "kind": "base", "level": 1, "ascended": false })
	slots_changed.emit()
	return true

func add_passive(id: String) -> bool:
	if passives.size() >= max_passive_slots():
		return false
	for p in passives:
		if String(p["id"]) == id:
			return false
	# v2：宝物（kind = "treasure"）与果子共用 4 个被动槽，但同类宝物最多 4 件
	var def: Dictionary = GameData.passives.get(id, {})
	if String(def.get("kind", "")) == "treasure" and treasure_count() >= max_treasure_slots():
		return false
	passives.append({ "id": id, "level": 1 })
	recompute()
	slots_changed.emit()
	return true

## 全副军装只作为精英掉落，自动穿戴：不占被动槽，避免把祝圣必需的圣灵果子挤出 4 个槽位。
func add_armor(id: String) -> bool:
	for a in armor:
		if String(a["id"]) == id:
			return false
	armor.append({ "id": id, "level": 1 })
	recompute()
	slots_changed.emit()
	return true

func has_armor(id: String) -> bool:
	for a in armor:
		if String(a["id"]) == id:
			return true
	return false

func upgrade_weapon_at(index: int) -> bool:
	if index < 0 or index >= weapons.size():
		return false
	var w: Dictionary = weapons[index]
	if int(w["level"]) >= weapon_max_level(w):
		return false
	w["level"] = int(w["level"]) + 1
	slots_changed.emit()
	recompute()
	return true

func upgrade_passive_at(index: int) -> bool:
	if index < 0 or index >= passives.size():
		return false
	var p: Dictionary = passives[index]
	var def: Dictionary = GameData.passives.get(p["id"], {})
	if int(p["level"]) >= int(def.get("max_level", 5)):
		return false
	p["level"] = int(p["level"]) + 1
	recompute()
	slots_changed.emit()
	return true

func has_passive(id: String) -> bool:
	for p in passives:
		if String(p["id"]) == id:
			return true
	return false

## 解析某件武器在当前等级下的实际参数（基线 × 每级增幅，再套 overrides）。
func resolved_params(entry: Dictionary) -> Dictionary:
	var def: Dictionary = weapon_def(entry)
	if def.is_empty():
		return {}
	var base: Dictionary = def.get("params", {})
	var scaling: Dictionary = def.get("scaling", {})
	var lv: int = int(entry["level"])
	var out: Dictionary = {}
	for k in base.keys():
		var v: Variant = base[k]
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			var s: float = float(scaling.get(k, 0.0))
			out[k] = float(v) * (1.0 + s * float(lv - 1))
		else:
			out[k] = v
	var ov_all: Dictionary = def.get("overrides", {})
	var ov: Dictionary = ov_all.get(str(lv), {})
	for k in ov.keys():
		out[k] = ov[k]
	return out

## 成全的永久参数：evolves_to.overrides 先落成绝对值，再乘成全倍率，整包写进 entry["ascend_params"]。
## 写进武器字典而不是 stats —— recompute() 重建 stats 时不会把它重置，武器在，强化就在。
## 幂等：已有 ascend_params 就直接返回。
func bake_ascend(entry: Dictionary) -> void:
	if entry.get("ascend_params", null) is Dictionary:
		return
	var p: Dictionary = resolved_params(entry)
	var def: Dictionary = weapon_def(entry)
	var ov: Dictionary = {}
	if def.get("evolves_to", null) is Dictionary:
		var ev: Dictionary = def["evolves_to"]
		if ev.get("overrides", null) is Dictionary:
			ov = ev["overrides"]
	if ov.is_empty() and p.is_empty():
		return
	for k in ov.keys():
		p[String(k)] = ov[k]
	if p.has("damage"):
		p["damage"] = float(p["damage"]) * ASCEND_DAMAGE_MULT
	if p.has("count"):
		p["count"] = int(p["count"]) + ASCEND_COUNT_BONUS
	if p.has("radius"):
		p["radius"] = float(p["radius"]) * ASCEND_RADIUS_MULT
	if p.has("range"):
		p["range"] = float(p["range"]) * ASCEND_RANGE_MULT
	if p.has("arc_deg"):
		p["arc_deg"] = minf(float(p["arc_deg"]) * ASCEND_ARC_MULT, 360.0)
	if p.has("cooldown"):
		p["cooldown"] = float(p["cooldown"]) * ASCEND_COOLDOWN_MULT
	if p.has("tick"):
		# 环绕 / 领域类没有 cooldown，用 tick 当节奏键，吃同一条冷却倍率
		p["tick"] = float(p["tick"]) * ASCEND_COOLDOWN_MULT
	entry["ascend_params"] = p

## 实际开火参数：成全武器返回永久烘好的那份（副本，防外部改写），否则按当前等级解析。
## weapon_runner 每帧只认这一个入口，所以成全强化不会因为重复乘而叠爆。
func fire_params(entry: Dictionary) -> Dictionary:
	if bool(entry.get("ascended", false)):
		if not (entry.get("ascend_params", null) is Dictionary):
			bake_ascend(entry)
		var baked: Variant = entry.get("ascend_params", null)
		if baked is Dictionary:
			return (baked as Dictionary).duplicate()
	return resolved_params(entry)

func entry_status(entry: Dictionary) -> String:
	return String(weapon_def(entry).get("status", ""))

func entry_behavior(entry: Dictionary) -> String:
	return String(weapon_def(entry).get("behavior", ""))

func entry_modifier(entry: Dictionary) -> String:
	return String(weapon_def(entry).get("modifier", ""))

func entry_color(entry: Dictionary) -> Color:
	return Color(String(weapon_def(entry).get("color", "#C9A66B")))

# ---------------------------------------------------------------- 祝圣

## 返回该槽位此刻可执行的祝圣配方（已满足武器满级 + 被动持有 + 火炭）。
func available_fusions(ignore_coal: bool = false) -> Array:
	var out: Array = []
	if coals <= 0 and not ignore_coal:
		return out
	for i in range(weapons.size()):
		var w: Dictionary = weapons[i]
		if String(w.get("kind", "base")) != "base":
			continue
		if int(w["level"]) < 5:
			continue
		var f: Dictionary = GameData.fusion_by_weapon.get(w["id"], {})
		if f.is_empty():
			continue
		if has_passive(String(f["passive"])):
			out.append({ "fusion": f, "slot": i })
	# 双武合鸣：两件都 Lv5
	for f in GameData.dual_fusions:
		var ia := -1
		var ib := -1
		for i in range(weapons.size()):
			var w: Dictionary = weapons[i]
			if String(w.get("kind", "base")) != "base":
				continue
			if int(w["level"]) < 5:
				continue
			if String(w["id"]) == String(f["weapon_a"]):
				ia = i
			if String(w["id"]) == String(f["weapon_b"]):
				ib = i
		if ia >= 0 and ib >= 0 and ia != ib:
			out.append({ "fusion": f, "slot": ia, "slot_b": ib })
	return out

func apply_fusion(fusion: Dictionary, slot: int, slot_b: int = -1, kills_now: int = 0) -> void:
	if coals <= 0:
		return
	coals -= 1
	var consumed: Array = []
	if String(fusion.get("type", "")) == "dual_weapon":
		var idxs: Array = [slot, slot_b]
		idxs.sort()
		idxs.reverse()
		for i in idxs:
			consumed.append(String(weapons[i]["id"]))
			weapons.remove_at(i)
	else:
		consumed.append(String(weapons[slot]["id"]))
		weapons.remove_at(slot)
	for cid in consumed:
		consumed_weapons[cid] = true
	var start_level := 1
	if float(perf("fusion_start_level", 0.0)) > 0.0:
		start_level = int(perf("fusion_start_level", 1.0))
	weapons.append({ "id": fusion["id"], "kind": "fusion", "level": start_level, "ascended": false, "born_kills": kills_now })
	recompute()
	slots_changed.emit()

## 成全：满级 + 击杀达标时把成全过程挂到武器上。
func try_ascend(all_kills: int) -> Array:
	var newly: Array = []
	for w in weapons:
		if String(w.get("kind", "base")) != "fusion":
			continue
		if bool(w.get("ascended", false)):
			continue
		var def: Dictionary = weapon_def(w)
		var evo: Dictionary = def.get("evolves_to", {})
		if evo.is_empty():
			continue
		if int(w["level"]) < int(evo.get("level", 5)):
			continue
		# 成全长按「武器成圣之后」累计的击杀算，而不是整局总击杀（否则中后期一到 5 级就立刻触发）
		var thresh_mult: float = float(get_meta("fusion_threshold_mult", 1.0))
		var need_kills: int = int(float(evo.get("kills", 500)) * thresh_mult)
		if all_kills - int(w.get("born_kills", 0)) < need_kills:
			continue
		w["ascended"] = true
		# 成全强化在点亮的这一刻就永久写进武器字典（之后开火只读这份，重复成全也不会再乘）
		bake_ascend(w)
		ascended_count += 1
		newly.append({ "entry": w, "evolve": evo })
	if not newly.is_empty():
		slots_changed.emit()
	return newly

# ---------------------------------------------------------------- 属性

func recompute() -> void:
	var s: Dictionary = {
		"max_hp": base_hp(),
		"speed": base_speed(),
		"crit_chance": 0.05,
		"crit_mult": 1.6,
		"armor": 0.0,
		"damage_reduction": 0.0,
		"cooldown_mult": 1.0,
		"area_mult": 1.0,
		"xp_gain": 1.0,
		"pickup_radius": 42.0,
		"lifesteal": 0.0,
		"dot_mult": 1.0,
		"damage_mult": 1.0,
		"knockback_mult": 1.0,
		"proj_speed_mult": 1.0,
		# ---- v2 契约第 5 节新增 stat：旧键全保留，函数末尾把新键镜像回旧键 ----
		"area_pct": 0.0,          # 范围 +%（area_mult = 1 + area_pct）
		"projectile_speed": 1.0,  # 弹速倍率（proj_speed_mult 镜像）
		"duration": 1.0,          # 效果持续倍率（灼烧 / 领域 / 回旋）
		"knockback": 0.0,         # 击退 +%（knockback_mult = 1 + knockback）
		"crit_damage": 0.0,       # 暴伤加成（crit_mult = 基础 1.6 + crit_damage）
		"heal_per_sec": 0.0,      # 每秒回血 HP/s
		"silver_gain": 0.0,       # 银两 +%
		"enemy_speed_slow": 0.0,  # 敌人减速（0..0.8）
		# ---- v2 契约第 6 节新增 perk 落点（角色 / 觉醒 / 圣物 / 契约都能改）----
		"max_hp_bonus": 0.0,
		"damage_taken_mult": 1.0, # 受到伤害倍率（<1 = 减伤）
		"pickup_bonus": 0.0,      # 拾取范围 +%（独立于恩典强化的乘区）
		"level_heal_bonus": 0.0,  # 升级回血 +%
		"melee_only_bonus": 0.0,  # 仅近战加成（weapon_runner 按行为类型消费）
		"burn_stack_max": 1.0,    # 灼烧最大层数
		"silver_bonus": 0.0,      # 结算银两 +%
		"silver_mult": 1.0,
		"extra_projectile": 0.0   # 投射物 +N（取整消费，weapon_runner._extra_projectiles）
	}
	for p in passives:
		_apply_passive_def(p, s)
	for a in armor:
		_apply_passive_def(a, s)
	_apply_relic_effects(s)

	# 营地永久强化
	s["damage_mult"] += float(meta_bonus.get("damage_mult", 0.0))
	s["max_hp"] += float(meta_bonus.get("max_hp", 0.0))
	s["speed"] *= 1.0 + float(meta_bonus.get("speed_pct", 0.0))
	s["pickup_radius"] *= 1.0 + float(meta_bonus.get("pickup_pct", 0.0))
	s["xp_gain"] += float(meta_bonus.get("xp_gain", 0.0))
	s["level_heal"] = 0.15 + float(meta_bonus.get("level_heal", 0.0))

	# 地图修饰：以拉谷的干涸河床让武器冷却 -10%
	if stage_cd != 1.0:
		s["cooldown_mult"] = float(s["cooldown_mult"]) * stage_cd

	s["crit_chance"] += float(perf("crit_chance", 0.0))
	s["knockback_mult"] *= float(perf("knockback_mult", 1.0))

	# ---- v2 契约第 6 节 perk ----
	s["max_hp_bonus"] = float(s["max_hp_bonus"]) + float(perf("max_hp_bonus", 0.0))
	s["damage_taken_mult"] = float(s["damage_taken_mult"]) * float(perf("damage_taken_mult", 1.0))
	s["projectile_speed"] = float(s["projectile_speed"]) * float(perf("projectile_speed", 1.0))
	s["duration"] = float(s["duration"]) * float(perf("duration_mult", 1.0))
	s["pickup_bonus"] = float(s["pickup_bonus"]) + float(perf("pickup_bonus", 0.0))
	s["level_heal_bonus"] = float(s["level_heal_bonus"]) + float(perf("level_heal_bonus", 0.0))
	s["melee_only_bonus"] = float(s["melee_only_bonus"]) + float(perf("melee_only_bonus", 0.0))
	s["burn_stack_max"] = float(s["burn_stack_max"]) + float(perf("burn_stack_max", 0.0))
	s["silver_bonus"] = float(s["silver_bonus"]) + float(perf("silver_bonus", 0.0))
	s["max_hp"] += float(s["max_hp_bonus"])
	s["level_heal"] = float(s["level_heal"]) + float(s["level_heal_bonus"])
	s["pickup_radius"] *= 1.0 + float(s["pickup_bonus"])

	# ---- 镜像：weapon_runner / run.gd 只认旧键，新键必须同步回旧键 ----
	s["area_mult"] = float(s["area_mult"]) * (1.0 + float(s["area_pct"]))
	s["proj_speed_mult"] = float(s["proj_speed_mult"]) * float(s["projectile_speed"])
	s["knockback_mult"] = float(s["knockback_mult"]) * (1.0 + float(s["knockback"]))
	s["crit_mult"] = float(s["crit_mult"]) + float(s["crit_damage"])
	s["silver_mult"] = (1.0 + float(s["silver_gain"])) * (1.0 + float(s["silver_bonus"]))
	s["enemy_speed_slow"] = clampf(float(s["enemy_speed_slow"]), 0.0, 0.8)
	s["damage_taken_mult"] = clampf(float(s["damage_taken_mult"]), 0.05, 4.0)
	s["damage_reduction"] = clampf(s["damage_reduction"], 0.0, 0.75)

	# 约 · 大卫宝座：每少装备 1 把武器（4 槽基准），范围 +25%、最终伤害 +35%
	if bool(get_meta("covenant_david_throne", false)):
		var missing: int = maxi(max_weapon_slots() - weapons.size(), 0)
		if missing > 0:
			s["damage_mult"] = float(s["damage_mult"]) * (1.0 + 0.35 * float(missing))
			s["area_mult"] = float(s["area_mult"]) * (1.0 + 0.25 * float(missing))

	# 约 · 更美之约：每点亮 1 件成全，伤害与范围永久 +12%（成全门槛另在 try_ascend 里降 40%）
	if bool(get_meta("covenant_better_promise", false)):
		var asc: int = int(ascended_count)
		if asc > 0:
			s["damage_mult"] = float(s["damage_mult"]) * (1.0 + 0.12 * float(asc))
			s["area_mult"] = float(s["area_mult"]) * (1.0 + 0.08 * float(asc))

	# 基甸：每空 1 个武器槽，全伤害提升
	var dps: float = float(perf("damage_per_empty_slot", 0.0))
	if dps > 0.0:
		var empty: int = max_weapon_slots() - weapons.size()
		s["damage_mult"] += dps * float(maxi(empty, 0))

	# 只换 stats，不碰 weapons / passives / armor / relics：
	# 成全写进 entry["ascend_params"] 的永久参数因此不会被 recompute 重置。
	stats = s
	stats_changed.emit()


## 被动 / 宝物 / 军装共用的属性累加（都是 {id, level}；kind 只决定它算不算宝物，不影响计算）
func _apply_passive_def(p: Dictionary, s: Dictionary) -> void:
	var def: Dictionary = GameData.passives.get(p["id"], {})
	if def.is_empty():
		return
	var amount: float = float(def["per_level"]) * float(p["level"])
	_apply_stat(s, String(def["stat"]), amount)
	# 双效果被动 / 宝物（圣典里 fruit/treasure 有 5 件是两个属性）：第二属性用 stat2 + per_level2
	if def.has("stat2") and String(def["stat2"]) != "":
		var amount2: float = float(def.get("per_level2", def["per_level"])) * float(p["level"])
		_apply_stat(s, String(def["stat2"]), amount2)


## 把一条 stat 叠进属性字典（被 _apply_passive_def 的 stat / stat2 共用）
func _apply_stat(s: Dictionary, stat_id: String, amount: float) -> void:
	match stat_id:
		"lifesteal": s["lifesteal"] += amount
		"xp_gain": s["xp_gain"] += amount
		"damage_reduction": s["damage_reduction"] += amount
		"armor": s["armor"] += amount
		"pickup_radius": s["pickup_radius"] *= (1.0 + amount)
		"crit_chance": s["crit_chance"] += amount
		"dot_damage": s["dot_mult"] += amount
		"move_speed": s["speed"] *= (1.0 + amount)
		"cooldown": s["cooldown_mult"] *= (1.0 - minf(amount, 0.6))
		"damage_pct": s["damage_mult"] += amount
		"max_hp": s["max_hp"] += amount
		# ---- v2 契约第 5 节新增 stat ----
		"area_pct": s["area_pct"] += amount
		"projectile_speed": s["projectile_speed"] *= (1.0 + amount)
		"duration": s["duration"] *= (1.0 + amount)
		"knockback": s["knockback"] += amount
		"crit_damage": s["crit_damage"] += amount
		"heal_per_sec": s["heal_per_sec"] += amount
		"silver_gain": s["silver_gain"] += amount
		"enemy_speed_slow": s["enemy_speed_slow"] += amount
		# ---- v2 契约第 6 节新增 perk（写成被动 stat 时也认）----
		"max_hp_bonus": s["max_hp_bonus"] += amount
		"damage_taken_mult": s["damage_taken_mult"] *= (1.0 - minf(amount, 0.9))
		"pickup_bonus": s["pickup_bonus"] += amount
		"level_heal_bonus": s["level_heal_bonus"] += amount
		"melee_only_bonus": s["melee_only_bonus"] += amount
		"burn_stack_max": s["burn_stack_max"] += amount
		"silver_bonus": s["silver_bonus"] += amount
		"extra_projectile": s["extra_projectile"] += amount
		_: pass

## 圣物效果：data/relics.json 里若写了 "stats": {键: 值}，就按 stats 的键叠进 s。
## （圣典第 6 节多数圣物改的是规则而非数值，那类由 systems 读 has_relic 自行生效。）
func _apply_relic_effects(s: Dictionary) -> void:
	for id in relics:
		var d: Dictionary = GameData.relics_by_id.get(id, {})
		if d.is_empty():
			continue
		var bonus: Variant = d.get("stats", {})
		if typeof(bonus) != TYPE_DICTIONARY:
			continue
		for k in bonus.keys():
			var key: String = String(k)
			if not s.has(key):
				continue
			if typeof(s[key]) == TYPE_FLOAT or typeof(s[key]) == TYPE_INT:
				if key.ends_with("_mult") or key == "projectile_speed" or key == "duration":
					s[key] = float(s[key]) * float(bonus[k])
				else:
					s[key] = float(s[key]) + float(bonus[k])

func total_damage_reduction() -> float:
	var armor: float = float(stats.get("armor", 0.0))
	var armor_red: float = armor / (armor + 50.0)
	return clampf(armor_red + float(stats.get("damage_reduction", 0.0)), 0.0, 0.85)

## 实际承伤倍率：普适减伤之后再乘 damage_taken_mult（0.05..4.0）
func incoming_damage_mult() -> float:
	return (1.0 - total_damage_reduction()) * float(stats.get("damage_taken_mult", 1.0))

## 银两倍率（拾取 / 结算都用这一个）
func silver_mult() -> float:
	return float(stats.get("silver_mult", 1.0))

# ---------------------------------------------------------------- 经验

func add_xp(amount: float) -> int:
	xp += amount * float(stats.get("xp_gain", 1.0))
	var gained := 0
	while xp >= xp_need:
		xp -= xp_need
		level += 1
		gained += 1
		xp_need = XP_BASE * pow(XP_GROWTH, float(level - 1))
	return gained

func xp_progress() -> float:
	return clampf(xp / maxf(xp_need, 0.001), 0.0, 1.0)
