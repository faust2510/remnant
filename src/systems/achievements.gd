class_name RunAchievements
extends RefCounted
## 成就钩子（第 2 波 · 局内系统）。
## 每局结束（胜利或失败）按 data/achievements.json 的 cond 判定，调用
## Meta.grant_achievement(id) 真正写入存档（含银两与圣物解锁由 Meta 负责）。
## 支持 10 种 cond.type：stage_clear / stage_clear_seal / kills_in_run / kills_total /
## no_damage / elite_kills / fusion_count / level_reach / survive_time / weapon_only。
## cond 里可选的 stage/flag 作为附加条件；flag 来自机关 flags 与 run.ach_flags。

var run: Node
var newly: Array = []

func setup(r: Node) -> void:
	run = r

## victory：是否通关；commit=false 时只判定不写档（--sim 干跑用，便于回归看会给什么）。
func evaluate(victory: bool, commit: bool) -> Array:
	var got: Array = []
	var flags: Dictionary = {}
	if run.mechanics != null:
		for k in run.mechanics.flags.keys():
			flags[String(k)] = run.mechanics.flags[k]
	for k in run.ach_flags.keys():
		flags[String(k)] = run.ach_flags[k]
	for a in GameData.achievements:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var aid: String = String(a.get("id", ""))
		if aid == "":
			continue
		if Meta.has_achievement(aid):
			continue
		var cond: Dictionary = a.get("cond", {})
		if not _check(cond, victory, flags):
			continue
		if commit and not Meta.grant_achievement(aid):
			continue
		got.append({ "id": aid, "name": String(a.get("name", aid)), "reward": a.get("reward", {}) })
	newly = got
	return got

func _check(cond: Dictionary, victory: bool, flags: Dictionary) -> bool:
	var t: String = String(cond.get("type", ""))
	var v: Variant = cond.get("value", 0)
	var stage: String = String(cond.get("stage", ""))
	var flag: String = String(cond.get("flag", ""))
	if stage != "" and stage != run.stage_id:
		return false
	if flag != "" and not bool(flags.get(flag, false)):
		return false
	match t:
		"stage_clear":
			return victory and (String(v) == "" or String(v) == run.stage_id)
		"stage_clear_seal":
			return victory and int(run.seal) >= int(v)
		"kills_in_run":
			return int(run.state.kills) >= int(v)
		"kills_total":
			return int(Meta.lifetime_kills) + int(run.state.kills) >= int(v)
		"no_damage":
			return victory and float(run.damage_taken_total) <= 0.01
		"elite_kills":
			return int(run.elite_kills_total) >= int(v)
		"fusion_count":
			return _fusion_count() >= int(v)
		"level_reach":
			return int(run.state.level) >= int(v)
		"survive_time":
			return float(run.elapsed) >= float(v)
		"weapon_only":
			return _weapon_only(String(v))
	return false

func _fusion_count() -> int:
	var n: int = 0
	for w in run.state.weapons:
		if String(w.get("kind", "base")) == "fusion":
			n += 1
	return n

## "melee_orbit"：只允许近战（arc_melee）与环绕（orbit）两类武器。
func _weapon_only(kind: String) -> bool:
	if run.state.weapons.is_empty():
		return false
	if kind == "melee_orbit":
		for w in run.state.weapons:
			var b: String = run.state.entry_behavior(w)
			if b != "arc_melee" and b != "orbit":
				return false
		return true
	return false

## 结算页文案
func lines(limit: int = 6) -> Array:
	var out: Array = []
	for a in newly:
		out.append("成就 · %s" % String(a["name"]))
		if out.size() >= limit:
			break
	return out
