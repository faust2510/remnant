class_name RunStatPatch
extends RefCounted
## 局内属性补丁（第 2 波 · 局内系统）。
## 目的：约、圣物、机关地形、奇物 buff 都要改 state.stats，但每次 state.recompute()
## 都会从基础值重算 stats 并 emit stats_changed。若各系统直接 +=，recompute 后就会丢，
## recompute 前又会互相叠加。这里统一做「目标值 + 增量」记账：
##   - add(id, key, "mul", x) / add(id, key, "add", x)，同 id 同 key 覆盖
##   - apply() 每帧把 (目标值 - 已应用值) 折算成增量写进 stats
##   - stats_changed 触发时清空已应用记录，下一帧重新叠（不会重复叠加）
## 约定：一局只有一个实例（run.stat_patch），所有系统共用，禁止直接写 stats。

var state: GameState
var _contribs: Dictionary = {}   # stat_key -> Array[{id, op, val}]
var _prev: Dictionary = {}       # stat_key -> {"mul": float, "add": float}

func setup(st: GameState) -> void:
	state = st
	if state != null:
		var cb := Callable(self, "_on_recomputed")
		if not state.stats_changed.is_connected(cb):
			state.stats_changed.connect(cb)

func _on_recomputed() -> void:
	_prev.clear()

## op: "mul"（乘算，val 是倍率，如 1.2）或 "add"（加算，val 是数值，如 0.1）。
func add(id: String, key: String, op: String, val: float) -> void:
	if key == "" or val == 0.0:
		return
	if not _contribs.has(key):
		_contribs[key] = []
	var arr: Array = _contribs[key]
	for i in range(arr.size()):
		if String(arr[i]["id"]) == id:
			arr[i] = { "id": id, "op": op, "val": val }
			return
	arr.append({ "id": id, "op": op, "val": val })

func remove(id: String) -> void:
	for key in _contribs.keys():
		var arr: Array = _contribs[key]
		for i in range(arr.size() - 1, -1, -1):
			if String(arr[i]["id"]) == id:
				arr.remove_at(i)
		if arr.is_empty():
			_contribs.erase(key)

func has(id: String) -> bool:
	for key in _contribs.keys():
		for c in _contribs[key]:
			if String(c["id"]) == id:
				return true
	return false

func total(key: String) -> Dictionary:
	var dm: float = 1.0
	var da: float = 0.0
	for c in _contribs.get(key, []):
		if String(c["op"]) == "mul":
			dm *= float(c["val"])
		else:
			da += float(c["val"])
	return { "mul": dm, "add": da }

## 把当前目标值折算成增量写进 stats。每帧调用一次即可（无变化时是空转）。
func apply() -> void:
	if state == null:
		return
	for key in _contribs.keys():
		if not state.stats.has(key):
			continue
		var t: Dictionary = total(key)
		var dm: float = float(t["mul"])
		var da: float = float(t["add"])
		var p: Dictionary = _prev.get(key, { "mul": 1.0, "add": 0.0 })
		var pm: float = float(p.get("mul", 1.0))
		var pa: float = float(p.get("add", 0.0))
		if absf(dm - pm) < 0.00001 and absf(da - pa) < 0.00001:
			continue
		var cur: float = float(state.stats[key])
		# 反推 recompute 的基础值：先减掉已加的，再除回已乘的
		var base_val: float = (cur - pa) / (pm if absf(pm) > 0.000001 else 1.0)
		state.stats[key] = base_val * dm + da
		_prev[key] = { "mul": dm, "add": da }
