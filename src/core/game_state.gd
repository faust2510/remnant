class_name GameState
extends RefCounted
## 玩家构筑状态：见证人、武器槽、被动槽、衍生属性、等级经验。
## 纯 RefCounted，不依赖场景树 —— 无头模拟可以直接复用。

signal stats_changed
signal slots_changed

const BASE_WEAPON_SLOTS := 4
const BASE_PASSIVE_SLOTS := 4
const XP_BASE := 8.0
const XP_GROWTH := 1.13

var character: Dictionary = {}
var weapons: Array = []          # [{id, kind:"base"|"fusion", level, ascended:bool}]
var passives: Array = []         # [{id, level}]
var consumed_weapons: Dictionary = {}   # 被祝圣吃掉的基础武器 id
var stats: Dictionary = {}
var meta_bonus: Dictionary = {}
var stage_cd: float = 1.0         # 营地永久强化，由 Meta.bonus() 提供

var level: int = 1
var xp: float = 0.0
var xp_need: float = XP_BASE
var kills: int = 0
var coals: int = 0
var ascended_count: int = 0

func setup(character_id: String, bonus: Dictionary = {}) -> void:
	meta_bonus = bonus
	character = GameData.characters_by_id.get(character_id, {})
	weapons = []
	passives = []
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

func perf(key: String, default_value: Variant = 0.0) -> Variant:
	var perk: Dictionary = character.get("perk", {})
	return perk.get(key, default_value)

func max_weapon_slots() -> int:
	return int(perf("weapon_slots", BASE_WEAPON_SLOTS))

func max_passive_slots() -> int:
	return BASE_PASSIVE_SLOTS

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
	passives.append({ "id": id, "level": 1 })
	recompute()
	slots_changed.emit()
	return true

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

func apply_fusion(fusion: Dictionary, slot: int, slot_b: int = -1) -> void:
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
	weapons.append({ "id": fusion["id"], "kind": "fusion", "level": start_level, "ascended": false })
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
		if all_kills < int(evo.get("kills", 500)):
			continue
		w["ascended"] = true
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
		"proj_speed_mult": 1.0
	}
	for p in passives:
		var def: Dictionary = GameData.passives.get(p["id"], {})
		if def.is_empty():
			continue
		var amount: float = float(def["per_level"]) * float(p["level"])
		match String(def["stat"]):
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
			_: pass

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
	s["damage_reduction"] = clampf(s["damage_reduction"], 0.0, 0.75)

	# 基甸：每空 1 个武器槽，全伤害提升
	var dps: float = float(perf("damage_per_empty_slot", 0.0))
	if dps > 0.0:
		var empty: int = max_weapon_slots() - weapons.size()
		s["damage_mult"] += dps * float(maxi(empty, 0))

	stats = s
	stats_changed.emit()

func total_damage_reduction() -> float:
	var armor: float = float(stats.get("armor", 0.0))
	var armor_red: float = armor / (armor + 50.0)
	return clampf(armor_red + float(stats.get("damage_reduction", 0.0)), 0.0, 0.85)

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
