class_name HUD
extends Control
## 全部 UI 都在这一层用 draw_* 画出来，避免一堆 theme 资源。

var run: Node = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_d: float) -> void:
	queue_redraw()

func _font() -> Font:
	return GameFont.get_font()

func _fmt_time(t: float) -> String:
	var tt: int = int(maxf(t, 0.0))
	return "%02d:%02d" % [tt / 60, tt % 60]

func _draw() -> void:
	if run == null or run.state == null:
		return
	var f: Font = _font()
	var st: GameState = run.state

	# ---- 屏幕反馈层：受伤红闪 / 低血暗角 / 升级金闪
	var vw: float = 640.0
	var vh: float = 360.0
	var hurt: float = clampf(float(run.hurt_flash), 0.0, 1.0)
	if hurt > 0.01:
		draw_rect(Rect2(0, 0, vw, vh), Color(0.72, 0.10, 0.12, 0.22 * hurt), true)
	var hp_now: float = clampf(run.player_hp / maxf(run.player_max_hp, 1.0), 0.0, 1.0)
	if hp_now < 0.35 and not run.over:
		var pulse: float = 0.07 + 0.05 * sin(float(Time.get_ticks_msec()) * 0.0055)
		var band: float = 44.0
		var vc := Color(0.45, 0.05, 0.07, pulse)
		draw_rect(Rect2(0, 0, vw, band), vc, true)
		draw_rect(Rect2(0, vh - band, vw, band), vc, true)
		draw_rect(Rect2(0, band, band, vh - band * 2.0), vc, true)
		draw_rect(Rect2(vw - band, band, band, vh - band * 2.0), vc, true)
	var lf: float = clampf(float(run.level_flash), 0.0, 1.0)
	if lf > 0.01:
		draw_rect(Rect2(0, 0, vw, vh), Color(1.0, 0.86, 0.45, 0.12 * lf), true)

	# ---- 顶部：经验条 + 时间
	var xp_w: float = 640.0 * st.xp_progress()
	draw_rect(Rect2(0, 0, 640, 5), Color(0.08, 0.09, 0.12, 0.9), true)
	draw_rect(Rect2(0, 0, xp_w, 5), Color("#7FE0C0"), true)
	draw_string(f, Vector2(6, 18), "Lv %d" % st.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#E8DCC0"))
	draw_string(f, Vector2(560, 18), _fmt_time(run.elapsed), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#E8DCC0"))
	draw_string(f, Vector2(6, 32), "击杀 %d" % st.kills, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.75, 0.72, 0.65))
	if st.coals > 0:
		draw_string(f, Vector2(80, 32), "火炭 %d   [E] 祭坛" % st.coals, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#E0731A"))

	# ---- 左下：HP 条
	var hp_frac: float = clampf(run.player_hp / maxf(run.player_max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(6, 338, 132, 8), Color(0.08, 0.09, 0.12, 0.9), true)
	draw_rect(Rect2(6, 338, 132.0 * hp_frac, 8), Color("#B0424A") if hp_frac < 0.35 else Color("#C96A5A"), true)
	draw_string(f, Vector2(9, 346), "%d / %d" % [int(run.player_hp), int(run.player_max_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 1, 1, 0.85))

	# ---- 右下：武器槽与被动槽
	var wx: float = 640.0 - 8.0
	for i in range(st.weapons.size() - 1, -1, -1):
		var w: Dictionary = st.weapons[i]
		var def: Dictionary = st.weapon_def(w)
		var c: Color = Color(String(def.get("color", "#C9A66B")))
		wx -= 26.0
		draw_rect(Rect2(wx, 292, 24, 24), Color(0.08, 0.09, 0.12, 0.85), true)
		draw_rect(Rect2(wx + 1, 293, 22, 22), c, false, 1.0)
		var nm: String = String(def.get("name", "?"))
		draw_string(f, Vector2(wx + 3, 306), nm.substr(0, 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#E8DCC0"))
		var lv_txt: String = "★" if bool(w.get("ascended", false)) else str(int(w["level"]))
		draw_string(f, Vector2(wx + 15, 314), lv_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("#E0B85A"))
	var px: float = 640.0 - 8.0
	for i in range(st.passives.size() - 1, -1, -1):
		var ps: Dictionary = st.passives[i]
		var pdef: Dictionary = GameData.passives.get(ps["id"], {})
		px -= 18.0
		draw_rect(Rect2(px, 322, 16, 12), Color(0.12, 0.12, 0.16, 0.85), true)
		draw_string(f, Vector2(px + 1, 330), String(pdef.get("name", "?")).substr(0, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("#B8C4A8"))

	# ---- BOSS 血条
	if run.boss_index >= 0 and run.boss_index < run.enemies.count:
		var e: EnemySim = run.enemies
		var frac: float = clampf(e.hp[run.boss_index] / maxf(e.max_hp[run.boss_index], 1.0), 0.0, 1.0)
		draw_rect(Rect2(160, 12, 320, 8), Color(0.08, 0.09, 0.12, 0.9), true)
		draw_rect(Rect2(160, 12, 320.0 * frac, 8), Color("#8E2F2F"), true)
		draw_string(f, Vector2(160, 34), "歌利亚", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#E8DCC0"))

	# ---- 结算
	if run.over:
		draw_rect(Rect2(0, 0, 640, 360), Color(0.03, 0.04, 0.07, 0.86), true)
		var head: String = "约柜得胜" if run.won else "倒在以拉谷"
		draw_string(f, Vector2(0, 130), head, HORIZONTAL_ALIGNMENT_CENTER, 640, 20, Color("#E0B85A") if run.won else Color("#B0424A"))
		draw_string(f, Vector2(0, 168), "存活 %s   击杀 %d   等级 %d" % [_fmt_time(run.elapsed), st.kills, st.level], HORIZONTAL_ALIGNMENT_CENTER, 640, 11, Color("#E8DCC0"))
		var fb: int = 0
		for w in st.weapons:
			if String(w.get("kind", "")) == "fusion":
				fb += 1
		draw_string(f, Vector2(0, 190), "祝圣武器 %d   七印 %d" % [fb, run.seal], HORIZONTAL_ALIGNMENT_CENTER, 640, 9, Color(0.72, 0.70, 0.64))
		draw_string(f, Vector2(0, 212), "获得舍客勒  +%d" % run.reward, HORIZONTAL_ALIGNMENT_CENTER, 640, 13, Color("#E0B85A"))
		draw_string(f, Vector2(0, 240), "Esc 再来一局   ·   R 返回营地", HORIZONTAL_ALIGNMENT_CENTER, 640, 10, Color(0.62, 0.60, 0.55))

	# ---- 提示：完美闪避
	if run.perfect_flash > 0.0:
		draw_string(f, Vector2(258, 120), "守望者时刻", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1.0, clampf(run.perfect_flash, 0.0, 1.0)))
