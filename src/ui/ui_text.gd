class_name UIText
extends RefCounted
## UI 文本工具：见证人 perk、解锁条件、成就条件的中文格式化。
## 所有内容都从 data/*.json 与 Meta 读取，页面里不写死数据。

const STAGE_CLEAR := "stage_clear"

static func first_ach_id(text: String) -> String:
	var idx: int = text.find("ach_")
	if idx < 0:
		return ""
	var out: String = ""
	var i: int = idx
	while i < text.length():
		var ch: String = text[i]
		var ok: bool = (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_"
		if not ok:
			break
		out += ch
		i += 1
	return out

static func stage_achievement(stage_id: String) -> Dictionary:
	for a in GameData.achievements:
		var cond: Dictionary = a.get("cond", {})
		if String(cond.get("type", "")) == STAGE_CLEAR and String(cond.get("value", "")) == stage_id:
			return a
	return {}

static func stage_name(stage_id: String) -> String:
	var sdef: Dictionary = GameData.stages_by_id.get(stage_id, {})
	if sdef.is_empty():
		return stage_id
	return "第 %d 章《%s》" % [int(sdef.get("chapter", 0)), String(sdef.get("name", stage_id))]

## 见证人解锁：优先用 Meta 的正式接口，没有就从 data 推导（成就 / 章节首通）。
static func character_unlocked(c: Dictionary) -> bool:
	var cid: String = String(c.get("id", ""))
	if cid == "":
		return false
	if Meta.has_method("is_character_unlocked"):
		return bool(Meta.is_character_unlocked(cid))
	var unlock: Dictionary = c.get("unlock", {})
	var note: String = String(unlock.get("note", ""))
	var stage_id: String = String(unlock.get("stage", ""))
	if note.contains("默认") or (stage_id == "" and note == ""):
		return true
	var ach: String = first_ach_id(note)
	if ach != "":
		return Meta.has_achievement(ach)
	if stage_id != "":
		var a: Dictionary = stage_achievement(stage_id)
		if not a.is_empty():
			return Meta.has_achievement(String(a.get("id", "")))
		var sdef: Dictionary = GameData.stages_by_id.get(stage_id, {})
		return Meta.wins >= int(sdef.get("unlock_wins", 0))
	return false

static func character_unlock_text(c: Dictionary) -> String:
	if character_unlocked(c):
		return "已解锁"
	var unlock: Dictionary = c.get("unlock", {})
	var note: String = String(unlock.get("note", ""))
	var stage_id: String = String(unlock.get("stage", ""))
	var silver: int = int(unlock.get("silver", 0))
	if note != "":
		return note
	if stage_id != "":
		var extra: String = (" · 需 %d 银两" % silver) if silver > 0 else ""
		return "通关" + stage_name(stage_id) + extra
	return "尚未解锁"

static func _pct(v: float) -> String:
	return "%d%%" % int(round(v * 100.0))

static func stat_text(key: String, value: float) -> String:
	match key:
		"crit_chance":
			return "暴击 +" + _pct(value)
		"aim_crit_mult":
			return "锁头暴击 ×%.1f" % value
		"max_hp_bonus":
			return "最大生命 +%d" % int(value)
		"damage_taken_mult":
			return "受到伤害 %+.0f%%" % ((value - 1.0) * 100.0)
		"level_heal_bonus":
			return "升级回血 +" + _pct(value)
		"pickup_bonus":
			return "拾取范围 +" + _pct(value)
		"damage_pct":
			return "伤害 +" + _pct(value)
		"burn_stack_max":
			return "灼烧层数 +%d" % int(value)
		"damage_per_empty_slot":
			return "空槽增伤 +" + _pct(value)
		"duration_mult":
			return "持续 ×%.2f" % value
		"hit_push":
			return "击退 +%d" % int(value)
		"knockback_mult":
			return "击退 +" + _pct(value)
		"melee_only_bonus":
			return "近战增伤 +" + _pct(value)
		"projectile_speed":
			return "弹速 +" + _pct(value)
		"silver_bonus":
			return "舍客勒 +" + _pct(value)
		"weapon_slots":
			return "武器槽 +%d" % int(value)
		"move_shockwave":
			return "移动冲击波" if value > 0.0 else "无"
		_:
			return "%s %s" % [key, str(value)]

static func perk_items(perk: Dictionary) -> Array:
	var out: Array = []
	for k in perk.keys():
		var v: Variant = perk[k]
		if v is bool:
			if bool(v):
				out.append(stat_text(String(k), 1.0))
			continue
		if v is float or v is int:
			if absf(float(v)) < 0.0001 and String(k) != "move_shockwave":
				continue
			out.append(stat_text(String(k), float(v)))
	return out

static func perk_text(perk: Dictionary, limit: int = 2) -> String:
	var items: Array = perk_items(perk)
	if items.is_empty():
		return ""
	var parts: PackedStringArray = []
	for i in range(mini(items.size(), limit)):
		parts.append(String(items[i]))
	return " · ".join(parts)

static func achievement_cond_text(a: Dictionary) -> String:
	var cond: Dictionary = a.get("cond", {})
	var t: String = String(cond.get("type", ""))
	var value: Variant = cond.get("value", 0)
	var stage_id: String = String(cond.get("stage", ""))
	match t:
		"stage_clear":
			return "通关 " + stage_name(String(value))
		"stage_clear_seal":
			return "以 %d 印难度通关任意章节" % int(value)
		"kills_in_run":
			var where: String = ("（" + stage_name(stage_id) + "）") if stage_id != "" else ""
			return "单局击杀 %d 只%s" % [int(value), where]
		"survive_time":
			var where2: String = ("（" + stage_name(stage_id) + "）") if stage_id != "" else ""
			return "单局存活 %d 秒%s" % [int(value), where2]
		"fusion_count":
			return "单局合成 %d 次祝圣武器" % int(value)
		"weapon_only":
			return "限定武器类型通关" + (("（" + stage_name(stage_id) + "）") if stage_id != "" else "")
		_:
			return String(a.get("desc", ""))

static func achievement_reward_text(a: Dictionary) -> String:
	var reward: Dictionary = a.get("reward", {})
	var parts: PackedStringArray = []
	var silver: int = int(reward.get("silver", 0))
	if silver > 0:
		parts.append("舍客勒 +%d" % silver)
	var relic: String = String(reward.get("relic", ""))
	if relic != "":
		var rdef: Dictionary = GameData.relic_def(relic)
		parts.append("圣物「%s」" % String(rdef.get("name", relic)))
	if parts.is_empty():
		return "无额外奖励"
	return " · ".join(parts)

static func clip(text: String, max_chars: int) -> String:
	if max_chars <= 0 or text.length() <= max_chars:
		return text
	return text.substr(0, max_chars - 1) + "…"
