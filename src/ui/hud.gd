class_name HUD
extends Control
## 局内 HUD（V3）：内容仍全部由 _draw 程序化绘制，改用 UITheme 的「暗蓝石刻 + 烛金镶边 + 羊皮纸」美术。
## 基准分辨率 640×360，坐标一律写死常量（project.godot 用 viewport 拉伸，接口层不会改坐标）。
##
## 与 run.gd 的接口全部走 get()/has_method() 兜底（run.gd 由局内系统并行改造）：
##   paused / pause_index / muted / picked_shillings / toggle_pause() / pause_confirm()
## 字段缺失时按「未暂停 / 未静音 / 0 舍客勒」处理，绝不 push_error。
## 无头模拟（--sim）下 run.gd 会设 hud.visible = false → _draw 不执行 → 不加载任何图集、不依赖纹理。

var run: Node = null

# ================================================================ 交互状态
var _t: float = 0.0                  # 呼吸/脉动动画时钟（纯 UI，不参与模拟）
var _hover_menu: int = -1            # 暂停菜单悬停按钮 0..3，-1 = 未悬停
var _hover_pause_btn: bool = false   # 右上角 [||] 悬停
var _hover_fx: bool = false          # 暂停面板「特效」行悬停

# id → 图集下标（按 data/*.json 数组顺序；首次绘制时建表，GameData 未就绪则下次重试）
static var _weapon_idx: Dictionary = {}
static var _passive_idx: Dictionary = {}

# ================================================================ 布局常量（640×360）
const VIEW := Vector2(640.0, 360.0)

# ---- 顶部：经验金属槽 / 等级 / 章节·七印·沙漏石牌 / 击杀银两火炭 / [||]
const XP_BAR := Rect2(4.0, 1.0, 632.0, 6.0)
const LV_POS := Vector2(10.0, 30.0)
const LV_SUB_POS := Vector2(10.0, 43.0)
# V5：顶部石牌加宽到 220×34，章节名 10px、计时 15px，字号升了也不挤。
const HEAD_PLATE := Rect2(206.0, 7.0, 220.0, 35.0)
const SEAL_CENTER := Vector2(226.0, 24.5)
const SEAL_RADIUS := 10.5
const HEAD_DIV_X := 244.0
const HEAD_TEXT_RECT := Rect2(250.0, 7.0, 172.0, 35.0)
const HEAD_NAME_Y := 21.0
const HEAD_TIME_Y := 37.0
const HOURGLASS_H := 12.0
# V5：右上战况改成「小标签 + 大数字」三格（每格 56px），不再靠自动缩字号硬塞一行。
const STAT_RECT := Rect2(428.0, 10.0, 174.0, 24.0)
const STAT_Y := 28.0
const STAT_SLOT := 56.0
const PAUSE_BTN := Rect2(606.0, 8.0, 26.0, 18.0)

# ---- BOSS 血条
const BOSS_BAR := Rect2(168.0, 47.0, 304.0, 10.0)
const BOSS_NAME_X := 168.0
const BOSS_NAME_Y := 69.0
const BOSS_SUB_RECT := Rect2(352.0, 60.0, 120.0, 12.0)
const BOSS_PHASE_Y := 80.0

# ---- 约卡（左上，BOSS 血条左侧）
const COV_ORIGIN := Vector2(8.0, 47.0)
const COV_STEP := 19.0
const COV_SIZE := 17.0
const COV_MAX := 8

# ---- 左下：见证人头像 / 生命槽 / 圣物 / 军装
const AVATAR_RECT := Rect2(8.0, 290.0, 34.0, 34.0)
const AVATAR_NAME_Y := 339.0
const HP_BAR := Rect2(46.0, 290.0, 150.0, 13.0)
const HP_TEXT_Y := 300.0
const RELIC_LABEL_POS := Vector2(44.0, 317.0)
const RELIC_ORIGIN := Vector2(64.0, 305.0)
const ARMOR_LABEL_POS := Vector2(44.0, 331.0)
const ARMOR_ORIGIN := Vector2(64.0, 320.0)
const CHIP_STEP := 14.0
const CHIP_BOX := 12.0
const CHIP_MAX := 11

# ---- 右下：武器 / 宝物 32×32 图标格
const SLOT := 32.0
const SLOT_GAP := 4.0
const SLOT_RIGHT := 632.0
const WEAPON_ROW_Y := 288.0
const PASSIVE_ROW_Y := 324.0
const SLOT_MAX := 6

# ---- 中段：toast / 机制提示 / 祭坛提示 / 守望者时刻
const TOAST_Y := 250.0
const MECH_RECT := Rect2(160.0, 264.0, 320.0, 19.0)
const MECH_Y := 278.0
const ALTAR_HINT_RECT := Rect2(496.0, 262.0, 136.0, 18.0)
const PERFECT_Y := 118.0

# ---- 暂停遮罩
# V5 暂停面板：496×340，两级列宽拉开；正文 10px + 14px 行距（行距 4px），
# 底部留一条独立「特效」选择行，与 2×2 按钮分开，避免挤在一起。
const PAUSE_PANEL := Rect2(72.0, 10.0, 496.0, 340.0)
const PAUSE_TITLE_Y := 46.0
const PAUSE_DIV_Y := 54.0
const PAUSE_LX := 92.0
const PAUSE_LW := 204.0
const PAUSE_MID_X := 304.0
const PAUSE_RX := 316.0
const PAUSE_RW := 236.0
const PAUSE_W_HEAD_Y := 72.0
const PAUSE_W_ROW_Y := 88.0
const PAUSE_W_ROWS := 6
const PAUSE_P_HEAD_Y := 176.0
const PAUSE_P_ROW_Y := 190.0
const PAUSE_P_ROWS := 4
const PAUSE_ARMOR_Y := 250.0
const PAUSE_S_HEAD_Y := 72.0
const PAUSE_S_ROW_Y := 88.0
const PAUSE_PICK_Y := 204.0
const PAUSE_TIME_Y := 220.0
const PAUSE_BTN_W := 196.0
const PAUSE_BTN_H := 30.0
const PAUSE_BTN_X0 := 112.0
const PAUSE_BTN_Y0 := 264.0
const PAUSE_BTN_GX := 12.0
const PAUSE_BTN_GY := 10.0
const PAUSE_HINT_Y := 344.0
const ROW_STEP := 14.0
# 「特效：高/中/关」整行点击区（不进键盘选择项：run.gd 的 PAUSE_ITEMS 只有 4 项，不能改）
const FX_ROW := Rect2(320.0, 236.0, 196.0, 20.0)     # 与右列按钮同宽同左沿（320..516）

# ---- 结算页
const RESULT_PANEL := Rect2(84.0, 22.0, 472.0, 316.0)

# ---- 配色（UITheme 常量取不到的补充色）
const C_XP := Color(0.50, 0.84, 0.69)
const C_HP := Color(0.72, 0.26, 0.21)
const C_HP_LOW := Color(0.90, 0.36, 0.26)
const C_DIM := Color(0.02, 0.03, 0.05, 0.76)
const C_PANEL_TEXT := Color(0.72, 0.70, 0.64)

# ================================================================ 生命周期
func _ready() -> void:
	# 暂停菜单的「特效」档位要读写 UserSettings（只读 API，不改该文件）；
	# 它是 static 缓存 + 幂等，重复调用安全，先在这里保证磁盘设置被载入。
	UserSettings.load_settings()
	# 全屏接收鼠标：暂停按钮与暂停菜单需要点击；chooser 层号更高，模态时先拿到事件
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 全屏锚点已经给出 640×360 的绘制区域；不要再写 size（非等锚点下会触发
	# "size overridden after _ready" 警告，且绘制坐标全部走常量，不依赖节点尺寸）。
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

# ================================================================ 鼠标交互
func _gui_input(event: InputEvent) -> void:
	if run == null:
		return
	if event is InputEventMouseMotion:
		var p: Vector2 = (event as InputEventMouseMotion).position
		_hover_pause_btn = PAUSE_BTN.has_point(p)
		_hover_menu = _pause_btn_at(p) if _overlay_open() else -1
		_hover_fx = _overlay_open() and FX_ROW.has_point(p)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(mb.position)

## 「结算 / 暂停」这层遮罩是否吃掉鼠标
func _overlay_open() -> bool:
	if bool(run.get("over")):
		return false
	return _is_paused()

func _handle_click(p: Vector2) -> void:
	# 右上角 [||]：切换暂停 / 继续（暂停中也生效）
	if PAUSE_BTN.has_point(p) and not bool(run.get("over")):
		if run.has_method("toggle_pause"):
			run.call("toggle_pause")
		return
	if _overlay_open():
		# 特效行：整行可点，循环 关 → 中 → 高 → 关
		if FX_ROW.has_point(p):
			UserSettings.cycle_fx_level()
			queue_redraw()
			return
		var i: int = _pause_btn_at(p)
		if i >= 0:
			run.set("pause_index", i)
			if run.has_method("pause_confirm"):
				run.call("pause_confirm")

func _pause_btn_rect(i: int) -> Rect2:
	var col: int = i % 2
	var row: int = i / 2
	return Rect2(PAUSE_BTN_X0 + float(col) * (PAUSE_BTN_W + PAUSE_BTN_GX),
		PAUSE_BTN_Y0 + float(row) * (PAUSE_BTN_H + PAUSE_BTN_GY), PAUSE_BTN_W, PAUSE_BTN_H)

func _pause_btn_at(p: Vector2) -> int:
	for i in range(4):
		if _pause_btn_rect(i).has_point(p):
			return i
	return -1

func _pause_btn_label(i: int) -> String:
	match i:
		0:
			return "继续试炼"
		1:
			return "重开本局"
		2:
			return "返回营地"
		_:
			return "音效：关" if _muted() else "音效：开"

# ================================================================ run 字段兜底
func _is_paused() -> bool:
	return bool(run.get("paused")) if run != null else false

func _muted() -> bool:
	return bool(run.get("muted")) if run != null else false

func _run_int(key: String, def: int) -> int:
	if run == null:
		return def
	var v = run.get(key)
	if v is int:
		return int(v)
	if v is float:
		return int(v)
	return def

func _picked_shillings() -> int:
	var v = run.get("picked_shillings") if run != null else null
	if v is int:
		return int(v)
	if v is float:
		return int(v)
	return _pickup_silver()

func _stage_coin() -> float:
	var v = run.get("stage_coin") if run != null else null
	if v is float or v is int:
		return float(v)
	return 1.0

# ================================================================ 文本工具
## 普通文字（panel / 石牌等实底上用）
func _txt(pos: Vector2, s: String, size: int, col: Color, align: int = 0, width: float = -1.0) -> void:
	if s == "":
		return
	UITheme.text(self, pos, s, size, col, align, width)

## 带 1px 暗影的文字（压在玩法画面上的文字，保证可读）
func _txt_sh(pos: Vector2, s: String, size: int, col: Color, align: int = 0, width: float = -1.0) -> void:
	if s == "":
		return
	UITheme.text(self, pos + Vector2(1.0, 1.0), s, size, Color(0.0, 0.0, 0.0, 0.70 * col.a), align, width)
	UITheme.text(self, pos, s, size, col, align, width)

## 按像素宽度截断并加省略号（640×360 排版铁律：宁可省略，不许溢出/截半字）
func _fit(s: String, width: float, size: int) -> String:
	if s == "" or width <= 1.0:
		return s
	var f: Font = UITheme.font()
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return s
	var out: String = s
	while out.length() > 1:
		out = out.substr(0, out.length() - 1)
		if f.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			return out + "…"
	return "…"

# ================================================================ 主绘制
func _draw() -> void:
	if run == null or run.state == null:
		return
	_ensure_index()
	var st = run.state
	_draw_feedback()
	_draw_top(st)
	_draw_boss()
	_draw_covenants()
	_draw_bottom_left(st)
	_draw_slots(st)
	_draw_mid()
	if bool(run.get("over")):
		_draw_result(st)
	elif _is_paused():
		_draw_pause(st)

# ---------------------------------------------------------------- 屏幕反馈（保留）
func _draw_feedback() -> void:
	var hurt: float = clampf(float(run.get("hurt_flash")), 0.0, 1.0) if UserSettings.fx_at_least(1) else 0.0
	if hurt > 0.001:
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.72, 0.11, 0.09, hurt * 0.30), true)
	var max_hp: float = maxf(float(run.get("player_max_hp")), 1.0)
	var hp: float = clampf(float(run.get("player_hp")) / max_hp, 0.0, 1.0)
	if hp > 0.0 and hp < 0.35 and not bool(run.get("over")):
		var puls: float = 0.55 + 0.45 * sin(_t * 4.2)
		var a: float = (0.35 - hp) / 0.35 * 0.28 * puls
		var band: float = 44.0
		draw_rect(Rect2(0.0, 0.0, VIEW.x, band), Color(0.32, 0.02, 0.02, a), true)
		draw_rect(Rect2(0.0, VIEW.y - band, VIEW.x, band), Color(0.32, 0.02, 0.02, a), true)
		draw_rect(Rect2(0.0, 0.0, band, VIEW.y), Color(0.32, 0.02, 0.02, a), true)
		draw_rect(Rect2(VIEW.x - band, 0.0, band, VIEW.y), Color(0.32, 0.02, 0.02, a), true)
	var lvl: float = clampf(float(run.get("level_flash")), 0.0, 1.0) if UserSettings.fx_at_least(1) else 0.0
	if lvl > 0.001:
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.95, 0.82, 0.42, lvl * 0.16), true)

# ---------------------------------------------------------------- A. 顶部
func _draw_top(st) -> void:
	var f: Font = UITheme.font()
	# 经验双层金属槽
	UITheme.metal_bar(self, XP_BAR, st.xp_progress(), C_XP, clampf(float(run.get("level_flash")), 0.0, 1.0))
	# 等级（V5：12→13，经验百分比 7→9，字与条不再互相顶）
	_txt(LV_POS, "Lv %d" % st.level, 13, UITheme.GOLD_BRIGHT)
	_txt(LV_SUB_POS, "经验 %d%%" % int(round(st.xp_progress() * 100.0)), 9, UITheme.PARCH_DIM)
	# 章节 / 七印 / 沙漏计时 石牌
	UITheme.panel(self, HEAD_PLATE, 0.97)
	var seal: int = _run_int("seal", 1)
	draw_circle(SEAL_CENTER, SEAL_RADIUS + 0.8, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.80))
	draw_circle(SEAL_CENTER, SEAL_RADIUS - 0.8, UITheme.INK_DEEP)
	_txt(Vector2(SEAL_CENTER.x - 12.0, SEAL_CENTER.y - 3.0), "印", 7, UITheme.PARCH_DIM, 1, 24.0)
	_txt(Vector2(SEAL_CENTER.x - 12.0, SEAL_CENTER.y + 9.0), str(seal), 10, UITheme.GOLD_BRIGHT, 1, 24.0)
	draw_line(Vector2(HEAD_DIV_X, HEAD_PLATE.position.y + 5.0), Vector2(HEAD_DIV_X, HEAD_PLATE.end.y - 5.0),
		Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.45), 1.0)
	# 章节名
	var sname: String = String(run.stage.get("name", ""))
	var chp: int = int(run.stage.get("chapter", 0))
	var head: String = ""
	if chp > 0:
		head = "第 %d 章《%s》" % [chp, sname]
	else:
		head = sname
	if head == "":
		head = "以拉谷"
	_txt(Vector2(HEAD_TEXT_RECT.position.x, HEAD_NAME_Y), _fit(head, HEAD_TEXT_RECT.size.x, 10), 10,
		UITheme.PARCH, HORIZONTAL_ALIGNMENT_CENTER, HEAD_TEXT_RECT.size.x)
	# 沙漏 + MM:SS（V5：14→15，石牌加高到 35 才装得下）
	var tstr: String = _fmt_time(float(run.get("elapsed")))
	var tw: float = f.get_string_size(tstr, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var gw: float = tw + HOURGLASS_H + 5.0
	var gx: float = HEAD_TEXT_RECT.position.x + (HEAD_TEXT_RECT.size.x - gw) * 0.5
	_draw_hourglass(Vector2(gx, HEAD_TIME_Y - HOURGLASS_H + 2.0), HOURGLASS_H)
	_txt(Vector2(gx + HOURGLASS_H + 5.0, HEAD_TIME_Y), tstr, 15, UITheme.GOLD_BRIGHT)
	# 右上战况：三格「小标签 + 大数字」。标签 9px 暗羊皮、数字 11px 烛金，各自右对齐到格沿，
	# 不再像旧实现那样把 19 字塞进一行、再自动缩到 6px（实机里标签和数字糊成一片）。
	draw_rect(STAT_RECT, Color(UITheme.INK_DEEP.r, UITheme.INK_DEEP.g, UITheme.INK_DEEP.b, 0.62), true)
	draw_rect(Rect2(STAT_RECT.position.x, STAT_RECT.position.y, STAT_RECT.size.x, 1.0),
		Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.22), true)
	draw_rect(Rect2(STAT_RECT.position.x, STAT_RECT.end.y - 1.0, STAT_RECT.size.x, 1.0),
		Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.30), true)
	var stat_rows: Array = [["击杀", str(st.kills)], ["银两", str(_picked_shillings())], ["火炭", str(st.coals)]]
	for i in range(3):
		var sx: float = STAT_RECT.position.x + 5.0 + float(i) * STAT_SLOT
		if i > 0:
			draw_rect(Rect2(sx - 8.0, STAT_RECT.position.y + 5.0, 1.0, 14.0),
				Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.20), true)
		_txt(Vector2(sx, STAT_Y), String(stat_rows[i][0]), 9, Color(0.66, 0.64, 0.54))
		var num: String = String(stat_rows[i][1])
		var vw: float = f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_txt_sh(Vector2(sx + 43.0 - vw, STAT_Y), num, 11, UITheme.GOLD_BRIGHT)
	_draw_pause_button()

## 沙漏图标（纯几何，不依赖图集）
func _draw_hourglass(p: Vector2, h: float) -> void:
	var w: float = h * 0.62
	var col: Color = UITheme.GOLD_BRIGHT
	var sand: Color = Color(col.r, col.g, col.b, 0.85)
	draw_line(p, p + Vector2(w, 0.0), col, 1.0)
	draw_line(p + Vector2(0.0, h), p + Vector2(w, h), col, 1.0)
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(1.5, 1.0), p + Vector2(w - 1.5, 1.0), p + Vector2(w * 0.5, h * 0.5)]), sand)
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(w * 0.5, h * 0.5), p + Vector2(w - 1.5, h - 1.0), p + Vector2(1.5, h - 1.0)]), sand)

## 右上 [||] 暂停按钮
func _draw_pause_button() -> void:
	var r: Rect2 = PAUSE_BTN
	var hot: bool = _hover_pause_btn or _is_paused()
	var gcol: Color = UITheme.GOLD
	draw_rect(r, UITheme.INK_DEEP, true)
	draw_rect(r.grow(-1.0), UITheme.INK_SOFT, true)
	draw_rect(r, Color(gcol.r, gcol.g, gcol.b, 0.95 if hot else 0.55), false, 1.0)
	var col: Color = UITheme.GOLD_BRIGHT if hot else UITheme.PARCH_DIM
	if _is_paused():
		draw_colored_polygon(PackedVector2Array([
			r.position + Vector2(9.0, 5.0), r.position + Vector2(9.0, 13.0), r.position + Vector2(17.0, 9.0)]), col)
	else:
		draw_rect(Rect2(r.position + Vector2(9.0, 5.0), Vector2(3.0, 9.0)), col, true)
		draw_rect(Rect2(r.position + Vector2(15.0, 5.0), Vector2(3.0, 9.0)), col, true)

# ---------------------------------------------------------------- E. BOSS 血条
func _draw_boss() -> void:
	if run == null:
		return
	var bi: int = int(run.get("boss_index"))
	var e = run.get("enemies")
	if bi < 0 or e == null:
		return
	if bi >= int(e.count):
		return
	var frac: float = clampf(float(e.hp[bi]) / maxf(float(e.max_hp[bi]), 1.0), 0.0, 1.0)
	UITheme.metal_bar(self, BOSS_BAR, frac, UITheme.BLOOD, 0.0)
	for notch in [0.66, 0.33]:
		var nx: float = BOSS_BAR.position.x + BOSS_BAR.size.x * float(notch)
		draw_line(Vector2(nx, BOSS_BAR.position.y), Vector2(nx, BOSS_BAR.end.y),
			Color(0.95, 0.82, 0.55, 0.50), 1.0)
	var bid: String = String(e.type_ids[e.typ[bi]])
	var bdef: Dictionary = _boss_def(bid)
	var bname: String = String(bdef.get("name", "首领"))
	_txt_sh(Vector2(BOSS_NAME_X, BOSS_NAME_Y), _fit(bname, 190.0, 10), 10, UITheme.PARCH)
	var bchp: int = int(bdef.get("chapter", 0))
	var bpct: int = int(round(frac * 100.0))
	var bsub: String = ("第 %d 章 · %d%%" % [bchp, bpct]) if bchp > 0 else ("剩余 %d%%" % bpct)
	_txt_sh(Vector2(BOSS_SUB_RECT.position.x, BOSS_NAME_Y), bsub, 9, Color(0.80, 0.68, 0.55),
		HORIZONTAL_ALIGNMENT_RIGHT, BOSS_SUB_RECT.size.x)
	var phase_txt: String = _boss_phase_text(bdef, frac)
	if phase_txt != "":
		_txt_sh(Vector2(BOSS_NAME_X, BOSS_PHASE_Y), _fit(phase_txt, 300.0, 9), 9, Color(0.86, 0.60, 0.52))

# ---------------------------------------------------------------- E. 约卡
func _draw_covenants() -> void:
	var cards: Array = _covenant_data()
	# V3：未立约时不再画 2 个空「约」槽（旧占位在实机里像两个无意义方框，纯噪声）
	if cards.is_empty():
		return
	var n: int = mini(cards.size(), COV_MAX)
	for i in range(n):
		var card: Dictionary = cards[i]
		var r := Rect2(COV_ORIGIN.x + float(i) * COV_STEP, COV_ORIGIN.y, COV_SIZE, COV_SIZE)
		var rc: Color = Color(String(card.get("color", "#9FD3C0")))
		draw_rect(r, Color(0.10, 0.10, 0.14, 0.88), true)
		draw_rect(r.grow(-1.0), Color(rc.r, rc.g, rc.b, 0.22), true)
		draw_rect(r, rc, false, 1.0)
		var nm: String = String(card.get("name", card.get("id", "?")))
		_txt(Vector2(r.position.x, r.position.y + 13.0), nm.substr(0, 1), 10, Color(0.95, 0.91, 0.77),
			HORIZONTAL_ALIGNMENT_CENTER, COV_SIZE)
	if cards.size() > COV_MAX:
		_txt(Vector2(COV_ORIGIN.x + float(COV_MAX) * COV_STEP - 4.0, COV_ORIGIN.y + 13.0),
			"+%d" % (cards.size() - COV_MAX), 9, Color(0.66, 0.66, 0.60))

# ---------------------------------------------------------------- B. 左下
func _draw_bottom_left(st) -> void:
	_draw_witness()
	var frac: float = clampf(float(run.get("player_hp")) / maxf(float(run.get("player_max_hp")), 1.0), 0.0, 1.0)
	var low: bool = frac < 0.35
	var col: Color = C_HP_LOW if low else C_HP
	var glow: float = 0.0
	if low:
		glow = 0.40 + 0.40 * sin(_t * 5.5)
	UITheme.metal_bar(self, HP_BAR, frac, col, glow)
	_txt_sh(Vector2(HP_BAR.position.x, HP_TEXT_Y),
		"%d / %d" % [int(float(run.get("player_hp"))), int(float(run.get("player_max_hp")))],
		10, Color(1.0, 1.0, 1.0, 0.96), HORIZONTAL_ALIGNMENT_CENTER, HP_BAR.size.x)
	_draw_relic_row(st)
	_draw_armor_row(st)

## 见证人小头像框（SpriteBank.witnesses 对应行第 0 帧）
func _draw_witness() -> void:
	var cid: String = String(run.get("character_id"))
	var cdef: Dictionary = _characters_db().get(cid, {})
	var nm: String = String(cdef.get("name", cid))
	var r: Rect2 = AVATAR_RECT
	var tex: Texture2D = SpriteBank.witnesses()
	var wrow: int = SpriteBank.witness_row(cid)
	draw_rect(r, Color(0.05, 0.06, 0.09, 0.96), true)
	# 头像一律 1:1 整数像素：48px 格直接塞进 32px 框会变成 0.667x 非整数缩放（糊边、眼神散）
	# 所以按格取「头部 32x32 裁剪」；prompt: V4 图集 48px / 脚底 y=44。
	var has_body: bool = false
	if tex != null and wrow >= 0:
		var cell: int = SpriteBank.cell_of("witnesses")
		var rows_ok: int = int(tex.get_height() / maxi(cell, 1))
		if cell > 0 and wrow < rows_ok:
			var src: Rect2 = SpriteBank.frame_rect(wrow, 0)
			if cell == 32:
				draw_texture_rect_region(tex, r, src)
			else:
				var crop: float = 32.0
				var ox: float = floorf((float(cell) - crop) * 0.5)
				draw_texture_rect_region(tex, r, Rect2(src.position.x + ox, src.position.y + 6.0, crop, crop))
			has_body = true
	if not has_body:
		# 纹理缺失：程序化回退（头 + 肩），绝不 push_error
		draw_circle(r.position + Vector2(16.0, 12.0), 6.0, Color(0.74, 0.68, 0.54, 0.92))
		draw_rect(Rect2(r.position + Vector2(6.0, 20.0), Vector2(20.0, 10.0)), Color(0.52, 0.47, 0.38, 0.92), true)
	draw_rect(r.grow(-0.5), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.85), false, 1.0)
	UITheme.rivet(self, r.position + Vector2(2.0, 2.0), 1.0, 0.9)
	UITheme.rivet(self, Vector2(r.end.x - 2.0, r.position.y + 2.0), 1.0, 0.9)
	UITheme.rivet(self, Vector2(r.position.x + 2.0, r.end.y - 2.0), 1.0, 0.9)
	UITheme.rivet(self, r.end - Vector2(2.0, 2.0), 1.0, 0.9)
	_txt_sh(Vector2(AVATAR_RECT.position.x - 4.0, AVATAR_NAME_Y), _fit(nm, 42.0, 10), 10, UITheme.PARCH,
		HORIZONTAL_ALIGNMENT_CENTER, AVATAR_RECT.size.x + 8.0)

## 圣物图标行
func _draw_relic_row(st) -> void:
	var ids: Array = _relic_ids(st)
	if ids.is_empty():
		return
	_txt(RELIC_LABEL_POS, "圣物", 9, Color(0.58, 0.60, 0.54))
	var n: int = mini(ids.size(), CHIP_MAX)
	for i in range(n):
		var r := Rect2(RELIC_ORIGIN.x + float(i) * CHIP_STEP, RELIC_ORIGIN.y, CHIP_BOX, CHIP_BOX)
		draw_rect(r, Color(0.10, 0.11, 0.14, 0.92), true)
		draw_rect(r, Color(0.72, 0.66, 0.44, 0.92), false, 1.0)
		var nm: String = _relic_name(String(ids[i]))
		_txt(Vector2(r.position.x, r.position.y + 9.5), nm.substr(0, 1), 9, Color(0.95, 0.89, 0.71),
			HORIZONTAL_ALIGNMENT_CENTER, CHIP_BOX)

## 军装图标行（不占宝物的槽）
func _draw_armor_row(st) -> void:
	if st.armor.is_empty():
		return
	_txt(ARMOR_LABEL_POS, "军装", 9, Color(0.66, 0.58, 0.42))
	var n: int = mini(st.armor.size(), CHIP_MAX)
	for i in range(n):
		var r := Rect2(ARMOR_ORIGIN.x + float(i) * CHIP_STEP, ARMOR_ORIGIN.y, CHIP_BOX, CHIP_BOX)
		draw_rect(r, Color(0.16, 0.14, 0.10, 0.92), true)
		draw_rect(r, Color(0.82, 0.70, 0.44, 0.92), false, 1.0)
		var e: Dictionary = st.armor[i]
		var nm: String = String(_passive_def(String(e.get("id", ""))).get("name", String(e.get("id", "?"))))
		_txt(Vector2(r.position.x, r.position.y + 9.5), nm.substr(0, 1), 9, Color(0.97, 0.91, 0.75),
			HORIZONTAL_ALIGNMENT_CENTER, CHIP_BOX)

# ---------------------------------------------------------------- B. 右下槽位
func _draw_slots(st) -> void:
	# ---- 武器
	var wn: int = st.weapons.size()
	var wmax: int = clampi(maxi(st.max_weapon_slots(), wn), 0, SLOT_MAX)
	var wtotal: float = float(wmax) * SLOT + float(maxi(wmax - 1, 0)) * SLOT_GAP
	var wx: float = SLOT_RIGHT - wtotal
	if wx >= 470.0 and wmax > 0:
		_txt(Vector2(wx - 36.0, WEAPON_ROW_Y + 19.0), "武器", 9, Color(0.66, 0.63, 0.55),
			HORIZONTAL_ALIGNMENT_RIGHT, 30.0)
	var tex_w: Texture2D = SpriteBank.weapon_icons()
	var timers: PackedFloat32Array = _weapon_timers()
	for i in range(wmax):
		var cell := Rect2(wx + float(i) * (SLOT + SLOT_GAP), WEAPON_ROW_Y, SLOT, SLOT)
		if i >= wn:
			_empty_cell(cell)
			continue
		var w: Dictionary = st.weapons[i]
		var idx: int = _weapon_icon_index(st, w)
		var src: Rect2 = SpriteBank.weapon_icon_rect(idx) if idx >= 0 else Rect2()
		UITheme.icon_frame(self, cell, tex_w if idx >= 0 else null, src, 0.0)
		if tex_w == null or idx < 0:
			_fallback_icon(cell, st.entry_color(w), String(st.weapon_def(w).get("name", "?")))
		if i < timers.size():
			var iv: float = _weapon_interval(st, w)
			if iv > 0.01:
				_draw_cooldown(cell, float(timers[i]) / iv)
		_draw_cell_badge(cell, w)
	# ---- 宝物 / 果子
	var pn: int = st.passives.size()
	var pmax: int = clampi(maxi(st.max_passive_slots(), pn), 0, SLOT_MAX)
	var ptotal: float = float(pmax) * SLOT + float(maxi(pmax - 1, 0)) * SLOT_GAP
	var px: float = SLOT_RIGHT - ptotal
	if px >= 470.0 and pmax > 0:
		_txt(Vector2(px - 36.0, PASSIVE_ROW_Y + 19.0), "宝物", 9, Color(0.66, 0.63, 0.55),
			HORIZONTAL_ALIGNMENT_RIGHT, 30.0)
	var tex_p: Texture2D = SpriteBank.passive_icons()
	for i in range(pmax):
		var cell2 := Rect2(px + float(i) * (SLOT + SLOT_GAP), PASSIVE_ROW_Y, SLOT, SLOT)
		if i >= pn:
			_empty_cell(cell2)
			continue
		var pe: Dictionary = st.passives[i]
		var pid: String = String(pe.get("id", ""))
		var pidx: int = int(_passive_idx.get(pid, -1))
		var src2: Rect2 = SpriteBank.passive_icon_rect(pidx) if pidx >= 0 else Rect2()
		UITheme.icon_frame(self, cell2, tex_p if pidx >= 0 else null, src2, 0.0)
		var pdef: Dictionary = st.passive_def(pe)
		if tex_p == null or pidx < 0:
			_fallback_icon(cell2, Color(0.62, 0.70, 0.55), String(pdef.get("name", pid)))
		_draw_cell_badge(cell2, pe)

## 空格子：暗底 + 极淡金边 + 中心点
func _empty_cell(cell: Rect2) -> void:
	draw_rect(cell, Color(0.05, 0.06, 0.09, 0.55), true)
	draw_rect(cell, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.22), false, 1.0)
	draw_circle(cell.get_center(), 1.6, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.28))

## 纹理缺失时的图标回退：色块 + 名称首字
func _fallback_icon(cell: Rect2, col: Color, label: String) -> void:
	var inner: Rect2 = cell.grow(-3.0)
	draw_rect(inner, Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 0.90), true)
	draw_rect(inner, col, false, 1.0)
	_txt_sh(Vector2(inner.position.x, inner.position.y + inner.size.y * 0.72), label.substr(0, 1), 10,
		UITheme.PARCH, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x)

## 冷却扇形遮罩：timers[i] 剩余量 / 估算 interval，顺时针从 12 点收拢
func _draw_cooldown(cell: Rect2, ratio: float) -> void:
	var r: float = clampf(ratio, 0.0, 1.0)
	if r <= 0.02:
		return
	var inner: Rect2 = cell.grow(-1.0)
	var c: Vector2 = inner.get_center()
	var rad: float = minf(inner.size.x, inner.size.y) * 0.5
	var steps: int = maxi(6, int(ceil(24.0 * r)))
	var shade: Color = Color(0.02, 0.03, 0.06, 0.72)
	for k in range(steps):
		var a0: float = -PI * 0.5 + TAU * r * float(k) / float(steps)
		var a1: float = -PI * 0.5 + TAU * r * float(k + 1) / float(steps)
		draw_colored_polygon(PackedVector2Array([
			c, c + Vector2(cos(a0), sin(a0)) * rad, c + Vector2(cos(a1), sin(a1)) * rad]), shade)
	# 扫描边缘：1px 烛金弧 + 收尾半径线，让「还剩多少 / 什么时候好」一眼可读
	var edge: Color = Color(UITheme.GOLD_BRIGHT.r, UITheme.GOLD_BRIGHT.g, UITheme.GOLD_BRIGHT.b, 0.62)
	var a_end: float = -PI * 0.5 + TAU * r
	draw_arc(c, maxf(rad - 0.5, 1.0), -PI * 0.5, a_end, maxi(10, int(ceil(36.0 * r))), edge, 1.0, true)
	draw_line(c, c + Vector2(cos(a_end), sin(a_end)) * rad, Color(edge.r, edge.g, edge.b, 0.45), 1.0)
	draw_circle(c, 1.6, Color(0.0, 0.0, 0.0, 0.55))

## 右下角等级 / 成全星标
func _draw_cell_badge(cell: Rect2, entry: Dictionary) -> void:
	var asc: bool = bool(entry.get("ascended", false))
	var badge: String = "★" if asc else str(int(entry.get("level", 1)))
	var bw: float = 12.0
	draw_rect(Rect2(cell.position + Vector2(cell.size.x - bw, cell.size.y - bw), Vector2(bw, bw)),
		Color(0.03, 0.04, 0.06, 0.86), true)
	_txt_sh(Vector2(cell.position.x + cell.size.x - bw, cell.position.y + cell.size.y - 2.0), badge, 9,
		UITheme.GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER, bw)

# ---------------------------------------------------------------- 图标下标 / 冷却估值
## 按 data 数组顺序建 id→下标表（weapons.json / passives.json 的数组顺序 = 图集格子顺序）
func _ensure_index() -> void:
	if _weapon_idx.is_empty():
		var i: int = 0
		for k in _weapon_ids():
			_weapon_idx[String(k)] = i
			i += 1
	if _passive_idx.is_empty():
		var j: int = 0
		for k2 in _passive_ids():
			_passive_idx[String(k2)] = j
			j += 1

## 武器图标下标：融合武器回落到 grow_from 的基础武器图（weapon / weapon_a）
func _weapon_icon_index(st, entry: Dictionary) -> int:
	var id: String = String(entry.get("id", ""))
	if String(entry.get("kind", "base")) != "fusion":
		return int(_weapon_idx.get(id, -1))
	var def: Dictionary = st.weapon_def(entry)
	var base_id: String = String(def.get("weapon", def.get("weapon_a", "")))
	if base_id == "":
		return -1
	return int(_weapon_idx.get(base_id, -1))

## 冷却估值：镜像 WeaponRunner.tick / _tick_orbit 的计时口径
func _weapon_interval(st, entry: Dictionary) -> float:
	var params: Dictionary = st.resolved_params(entry)
	var beh: String = String(entry.get("behavior", ""))
	if beh == "":
		beh = st.entry_behavior(entry)
	var asc: bool = bool(entry.get("ascended", false))
	var iv: float = 1.0
	if beh == "orbit":
		iv = float(params.get("tick", 0.35)) * (0.85 if asc else 1.0)
	else:
		iv = float(params.get("cooldown", 1.0)) * float(st.stats.get("cooldown_mult", 1.0))
		if asc:
			iv *= 0.82
	return maxf(iv, 0.08)

func _weapon_timers() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if run == null:
		return out
	var wr = run.get("weapons")
	if wr == null:
		return out
	var tv = wr.get("timers")
	if typeof(tv) == TYPE_PACKED_FLOAT32_ARRAY:
		return tv
	return out

# ---------------------------------------------------------------- E. 中段提示
func _draw_mid() -> void:
	var toast_t: float = float(run.get("toast_t"))
	if toast_t > 0.0:
		var ta: float = clampf(toast_t / 0.8, 0.0, 1.0)
		_txt_sh(Vector2(0.0, TOAST_Y), _fit(String(run.get("toast_text")), 560.0, 11), 11,
			Color(0.96, 0.88, 0.63, ta), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	var perfect: float = float(run.get("perfect_flash"))
	if perfect > 0.0:
		_txt_sh(Vector2(0.0, PERFECT_Y), "守望者时刻", 13,
			Color(0.85, 0.90, 1.0, clampf(perfect, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	_draw_mechanics_line()

## 机制提示条 + [E] 祭坛提示（保留旧功能，只换美术）
func _draw_mechanics_line() -> void:
	if bool(run.get("over")):
		return
	var txt: String = _mechanics_text()
	if txt == "":
		return
	var gold: Color = Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.30)
	draw_rect(MECH_RECT, Color(0.04, 0.05, 0.07, 0.68), true)
	draw_rect(Rect2(MECH_RECT.position, Vector2(MECH_RECT.size.x, 1.0)), gold, true)
	draw_rect(Rect2(Vector2(MECH_RECT.position.x, MECH_RECT.end.y - 1.0), Vector2(MECH_RECT.size.x, 1.0)), gold, true)
	_txt_sh(Vector2(MECH_RECT.position.x, MECH_Y), _fit(txt, MECH_RECT.size.x - 8.0, 10), 10,
		Color(0.94, 0.80, 0.54, 0.96), HORIZONTAL_ALIGNMENT_CENTER, MECH_RECT.size.x)
	var st = run.state
	if st != null and st.coals > 0:
		draw_rect(ALTAR_HINT_RECT, Color(0.04, 0.05, 0.07, 0.62), true)
		draw_rect(ALTAR_HINT_RECT, Color(0.94, 0.62, 0.28, 0.32), false, 1.0)
		_txt_sh(Vector2(ALTAR_HINT_RECT.position.x, ALTAR_HINT_RECT.position.y + 13.0), "[E] 祭坛", 9,
			Color(0.96, 0.66, 0.30), HORIZONTAL_ALIGNMENT_CENTER, ALTAR_HINT_RECT.size.x)

# ---------------------------------------------------------------- C. 暂停遮罩
func _draw_pause(st) -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), C_DIM, true)
	UITheme.vignette(self, 0.60, 104.0)
	UITheme.panel(self, PAUSE_PANEL, 1.0)
	UITheme.etched_title(self, Vector2(0.0, PAUSE_TITLE_Y), "试炼暂停", 18)
	UITheme.divider(self, PAUSE_LX, PAUSE_PANEL.end.x - 20.0, PAUSE_DIV_Y, 0.85)
	draw_rect(Rect2(PAUSE_MID_X, PAUSE_DIV_Y + 10.0, 1.0, 184.0),
		Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.22), true)
	_draw_pause_lists(st)
	_draw_pause_stats(st)
	_draw_fx_row()
	var sel: int = clampi(_run_int("pause_index", 0), 0, 3)
	var pulse: float = 0.5 + 0.5 * sin(_t * 3.2)
	for i in range(4):
		var r: Rect2 = _pause_btn_rect(i)
		var hov: bool = i == _hover_menu
		UITheme.button(self, r, _pause_btn_label(i), (i == sel) or hov, pulse)
		if hov and i != sel:
			draw_rect(r.grow(1.0), Color(UITheme.GOLD_PALE.r, UITheme.GOLD_PALE.g, UITheme.GOLD_PALE.b, 0.50), false, 1.0)
	_txt(Vector2(0.0, PAUSE_HINT_Y), "↑↓ 选择 · Enter 确认 · Esc 继续 · 特效行可直接点击", 9,
		Color(0.64, 0.62, 0.55), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)

## 暂停面板左列：武器 / 宝物 / 军装清单
## V5 排版：名字左对齐 + 等级右对齐（两列各自对齐），名字与等级不再挤成一句。
func _draw_pause_lists(st) -> void:
	_txt(Vector2(PAUSE_LX, PAUSE_W_HEAD_Y), "武器", 10, UITheme.GOLD)
	_txt(Vector2(PAUSE_LX, PAUSE_W_HEAD_Y), "%d / %d" % [st.weapons.size(), st.max_weapon_slots()], 10,
		UITheme.PARCH_DIM, HORIZONTAL_ALIGNMENT_RIGHT, PAUSE_LW)
	if st.weapons.is_empty():
		_txt(Vector2(PAUSE_LX + 2.0, PAUSE_W_ROW_Y), "（尚无武器）", 10, Color(0.56, 0.56, 0.51))
	for i in range(mini(st.weapons.size(), PAUSE_W_ROWS)):
		var w: Dictionary = st.weapons[i]
		var def: Dictionary = st.weapon_def(w)
		var nm: String = String(def.get("name", String(w.get("id", "?"))))
		if bool(w.get("ascended", false)):
			nm += " ★"
		var y: float = PAUSE_W_ROW_Y + float(i) * ROW_STEP
		_txt(Vector2(PAUSE_LX + 2.0, y), _fit("· " + nm, PAUSE_LW - 40.0, 10), 10, UITheme.PARCH)
		_txt(Vector2(PAUSE_LX, y), "Lv%d" % int(w.get("level", 1)), 10, Color(0.80, 0.76, 0.62),
			HORIZONTAL_ALIGNMENT_RIGHT, PAUSE_LW)
	_txt(Vector2(PAUSE_LX, PAUSE_P_HEAD_Y), "宝物 / 果子", 10, UITheme.GOLD)
	_txt(Vector2(PAUSE_LX, PAUSE_P_HEAD_Y), "%d / %d" % [st.passives.size(), st.max_passive_slots()], 10,
		UITheme.PARCH_DIM, HORIZONTAL_ALIGNMENT_RIGHT, PAUSE_LW)
	if st.passives.is_empty():
		_txt(Vector2(PAUSE_LX + 2.0, PAUSE_P_ROW_Y), "（尚未拾取）", 10, Color(0.56, 0.56, 0.51))
	for i in range(mini(st.passives.size(), PAUSE_P_ROWS)):
		var pe: Dictionary = st.passives[i]
		var pdef: Dictionary = st.passive_def(pe)
		var pnm: String = String(pdef.get("name", String(pe.get("id", "?"))))
		var y2: float = PAUSE_P_ROW_Y + float(i) * ROW_STEP
		_txt(Vector2(PAUSE_LX + 2.0, y2), _fit("· " + pnm, PAUSE_LW - 40.0, 10), 10, UITheme.PARCH)
		_txt(Vector2(PAUSE_LX, y2), "Lv%d" % int(pe.get("level", 1)), 10, Color(0.80, 0.76, 0.62),
			HORIZONTAL_ALIGNMENT_RIGHT, PAUSE_LW)
	# 军装（不占宝物槽，单行汇总；辅助级 9px，最长 6 件自动截断）
	var anames: Array = []
	for a in st.armor:
		anames.append(String(_passive_def(String(a.get("id", ""))).get("name", a.get("id", "?"))))
	var aline: String = "军装 %d" % st.armor.size()
	if not anames.is_empty():
		aline += "  " + _join(anames, " · ")
	_txt(Vector2(PAUSE_LX, PAUSE_ARMOR_Y), _fit(aline, PAUSE_LW + 24.0, 9), 9, Color(0.78, 0.70, 0.52))

## 暂停面板右列：实时属性摘要（run.state.stats）——标签左、数值右，两列各自对齐
func _draw_pause_stats(st) -> void:
	var s: Dictionary = st.stats
	var rows: Array = [
		["伤害", "×%.2f" % float(s.get("damage_mult", 1.0))],
		["范围", "×%.2f" % float(s.get("area_mult", 1.0))],
		["冷却", "×%.2f" % float(s.get("cooldown_mult", 1.0))],
		["暴击", "%d%% · ×%.1f" % [int(round(float(s.get("crit_chance", 0.05)) * 100.0)),
			float(s.get("crit_mult", 1.5))]],
		["移速", "%.0f" % float(s.get("speed", 72.0))],
		["生命上限", "%.0f" % float(s.get("max_hp", 100.0))],
		["减伤", "%d%%" % int(round(st.total_damage_reduction() * 100.0))],
		["拾取范围", "%.0f" % float(s.get("pickup_radius", 42.0))],
	]
	_txt(Vector2(PAUSE_RX, PAUSE_S_HEAD_Y), "实时属性", 10, UITheme.GOLD)
	for i in range(rows.size()):
		var y: float = PAUSE_S_ROW_Y + float(i) * ROW_STEP
		var row: Array = rows[i]
		_txt(Vector2(PAUSE_RX, y), String(row[0]), 10, C_PANEL_TEXT)
		_txt(Vector2(PAUSE_RX, y), String(row[1]), 10, UITheme.PARCH, HORIZONTAL_ALIGNMENT_RIGHT, PAUSE_RW)
	_txt(Vector2(PAUSE_RX, PAUSE_PICK_Y), "本局拾取  +%d 舍客勒" % _picked_total(), 10, UITheme.GOLD_BRIGHT)
	_txt(Vector2(PAUSE_RX, PAUSE_TIME_Y), "计时 %s  ·  击杀 %d" % [_fmt_time(float(run.get("elapsed"))), st.kills],
		10, C_PANEL_TEXT)

## 特效档位（UserSettings 只读接口；本行整行可点，鼠标切换，不进键盘 4 项选择）
func _fx_level() -> int:
	return clampi(int(UserSettings.fx_level), 0, 2)

func _draw_fx_row() -> void:
	var r: Rect2 = FX_ROW
	var lvl: int = _fx_level()
	var hot: bool = _hover_fx
	draw_rect(r, Color(UITheme.INK_DEEP.r, UITheme.INK_DEEP.g, UITheme.INK_DEEP.b, 0.85), true)
	draw_rect(r, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.95 if hot else 0.45), false, 1.0)
	_txt(Vector2(r.position.x + 8.0, r.position.y + 14.0), "特效", 10, C_PANEL_TEXT)
	for i in range(3):
		var seg := Rect2(r.position.x + 36.0 + float(i) * 37.0, r.position.y + 3.0, 34.0, 14.0)
		var on: bool = i == lvl
		var base: Color = Color(UITheme.INK_SOFT.r, UITheme.INK_SOFT.g, UITheme.INK_SOFT.b, 1.0)
		if on:
			base = base.lerp(Color(UITheme.GOLD_BRIGHT.r, UITheme.GOLD_BRIGHT.g, UITheme.GOLD_BRIGHT.b, 1.0), 0.22)
		draw_rect(seg, base, true)
		draw_rect(seg, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.90 if on else 0.26), false, 1.0)
		_txt(Vector2(seg.position.x, seg.position.y + 10.5), String(["关", "中", "高"][i]), 9,
			UITheme.GOLD_BRIGHT if on else Color(0.58, 0.56, 0.48), HORIZONTAL_ALIGNMENT_CENTER, seg.size.x)
	_txt(Vector2(r.position.x + 148.0, r.position.y + 14.0), "点击切换", 9, Color(0.56, 0.54, 0.46))

# ---------------------------------------------------------------- D. 结算页
func _draw_result(st) -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.02, 0.03, 0.05, 0.90), true)
	UITheme.vignette(self, 0.68, 108.0)
	UITheme.panel(self, RESULT_PANEL, 1.0)
	var won: bool = bool(run.get("won"))
	var sname: String = String(run.stage.get("name", ""))
	var sshow: String = sname if sname != "" else "战场"
	var head: String = "约柜得胜" if won else ("倒在" + sshow)
	UITheme.etched_title(self, Vector2(0.0, 66.0), head, 20,
		UITheme.GOLD_BRIGHT if won else Color(0.82, 0.32, 0.26))
	UITheme.divider(self, RESULT_PANEL.position.x + 28.0, RESULT_PANEL.end.x - 28.0, 78.0, 0.85)
	# 一级：本局结果（12px）；二级：章节/装备（10px）；三级：明细与成就（9-10px）
	_txt(Vector2(0.0, 102.0), "存活 %s   击杀 %d   等级 %d" % [_fmt_time(float(run.get("elapsed"))), st.kills, st.level],
		12, UITheme.PARCH, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	var chp: int = int(run.stage.get("chapter", 0))
	var stage_line: String = ("第 %d 章《%s》" % [chp, sshow]) if chp > 0 else ("《%s》" % sshow)
	stage_line += "   ·   七印 %d" % _run_int("seal", 1)
	_txt(Vector2(0.0, 120.0), _fit(stage_line, 440.0, 10), 10, C_PANEL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	var fused: int = 0
	for w in st.weapons:
		if String(w.get("kind", "base")) == "fusion":
			fused += 1
	var relic_ids: Array = _relic_ids(st)
	_txt(Vector2(0.0, 138.0), "祝圣武器 %d   圣物 %d   军装 %d" % [fused, relic_ids.size(), st.armor.size()],
		10, C_PANEL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	var lines: Array = _silver_lines(st)
	var line_w: float = RESULT_PANEL.size.x - 48.0
	_txt(Vector2(0.0, 158.0), _fit(String(lines[0]), line_w, 9), 9, Color(0.68, 0.70, 0.63),
		HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	_txt(Vector2(0.0, 172.0), _fit(String(lines[1]), line_w, 9), 9, Color(0.64, 0.68, 0.59),
		HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	var pick_scaled: int = _picked_total()
	_txt(Vector2(0.0, 196.0), "舍客勒合计  +%d   （局内拾取 %d · 局外 %d）" % [int(run.get("reward")), pick_scaled, _meta_silver_bonus()],
		13, UITheme.GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	# 新增：本局拾取
	_txt(Vector2(0.0, 214.0), "本局拾取 舍客勒  +%d" % _picked_total(), 10, UITheme.GOLD_PALE,
		HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	# 成就：整块框进内页，收掉页尾空档；行数 = 成就行 + 圣物行（≤3）
	var entries: Array = _result_achievement_entries()
	var new_relics: Array = _new_relic_ids()
	var has_relics: bool = not new_relics.is_empty()
	var ach_rows: int = entries.size() if not entries.is_empty() else 1
	if has_relics:
		ach_rows = mini(ach_rows, 2)
	var ach_plate := Rect2(108.0, 234.0, VIEW.x - 216.0, 78.0)
	UITheme.panel(self, ach_plate, 0.55, false)
	_txt(Vector2(0.0, 254.0), "成 就 达 成", 10, Color(0.60, 0.64, 0.58), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	if entries.is_empty():
		_txt(Vector2(0.0, 276.0), "本局无新增成就", 10, Color(0.50, 0.52, 0.47), HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	else:
		for i in range(ach_rows):
			var e = entries[i]
			var aid: String = ""
			var ename: String = ""
			var eraw: String = ""
			if e is Dictionary:
				aid = String(e.get("id", ""))
				ename = String(e.get("name", ""))
				var rw = e.get("reward", {})
				if rw is Dictionary and not rw.is_empty():
					eraw = "  " + _reward_dict_text(rw)
			else:
				aid = String(e)
			if ename == "":
				var ad: Dictionary = _achievement_def(aid)
				ename = String(ad.get("name", aid))
				if eraw == "" and ad.get("reward", null) is Dictionary:
					eraw = "  " + _reward_dict_text(ad.get("reward", {}))
			var line: String = "✓ %s%s" % [ename, eraw]
			_txt(Vector2(0.0, 276.0 + float(i) * 16.0), _fit(line, 400.0, 10), 10, Color(0.87, 0.80, 0.54),
				HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	if has_relics:
		var names: Array = []
		for rid in new_relics:
			names.append(_relic_name(String(rid)))
		var rline: String = "圣物解锁  " + _join(names, " · ")
		var ry: float = 276.0 + float(ach_rows) * 16.0
		_txt(Vector2(0.0, ry), _fit(rline, 400.0, 10), 10, Color(0.89, 0.81, 0.52),
			HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)
	_txt(Vector2(0.0, 330.0), "Esc 再来一局   ·   R 返回营地", 11, Color(0.64, 0.62, 0.56),
		HORIZONTAL_ALIGNMENT_CENTER, VIEW.x)

# ---------------------------------------------------------------- 自动加载单例（运行时取，check-only 友好）
# --check-only --script 不会注册 autoload 的全局名（GameData / Meta），直接写全局标识符会编译失败；
# 这里运行时从 /root 取，运行期行为与直接引用全局名完全一致，且不改变任何对外接口。
var _singletons: Dictionary = {}

func _singleton(sname: String) -> Variant:
	if _singletons.has(sname):
		return _singletons[sname]
	if not is_inside_tree():
		return null
	var n: Variant = get_node_or_null("/root/" + sname)
	if n != null:
		_singletons[sname] = n
	return n

func _gd() -> Variant:
	return _singleton("GameData")

func _meta() -> Variant:
	return _singleton("Meta")

func _characters_db() -> Dictionary:
	var gd: Variant = _gd()
	if gd == null:
		return {}
	var db: Variant = gd.characters_by_id
	return db if db is Dictionary else {}

func _weapon_ids() -> Array:
	var gd: Variant = _gd()
	if gd == null:
		return []
	var db: Variant = gd.weapons
	if db is Dictionary:
		var ks: Array = db.keys()
		return ks
	return []

func _passive_ids() -> Array:
	var gd: Variant = _gd()
	if gd == null:
		return []
	var db: Variant = gd.passives
	if db is Dictionary:
		var ks: Array = db.keys()
		return ks
	return []

func _passive_def(id: String) -> Dictionary:
	var gd: Variant = _gd()
	if gd == null:
		return {}
	var db: Variant = gd.passives
	if db is Dictionary:
		var d: Variant = db.get(id, {})
		if d is Dictionary:
			return d
	return {}

func _relic_name(id: String) -> String:
	var gd: Variant = _gd()
	if gd == null:
		return id
	var d: Variant = gd.relic_def(id)
	if d is Dictionary:
		return String(d.get("name", id))
	return id

func _boss_def(id: String) -> Dictionary:
	var gd: Variant = _gd()
	if gd == null:
		return {}
	var db: Variant = gd.enemies
	if db is Dictionary:
		var d: Variant = db.get(id, {})
		if d is Dictionary and not d.is_empty():
			return d
	var b: Variant = gd.boss_def(id)
	return b if b is Dictionary else {}

func _achievement_def(id: String) -> Dictionary:
	var gd: Variant = _gd()
	if gd == null:
		return {}
	var d: Variant = gd.achievement_def(id)
	return d if d is Dictionary else {}

func _seal_mult(seal: int) -> float:
	var m: Variant = _meta()
	if m == null:
		return 1.0
	return float(m.seal_mult(seal))

func _reward_for(victory: bool, kills: int, seconds: float, seal: int) -> int:
	var m: Variant = _meta()
	if m == null:
		return 0
	return int(m.reward_for(victory, kills, seconds, seal))

func _tier_name(seal: int) -> String:
	var m: Variant = _meta()
	if m == null:
		return "第 %d 阶" % seal
	return String(m.tier_name(seal))

# ---------------------------------------------------------------- 数据读取（全部容错）
func _covenant_data() -> Array:
	if run == null:
		return []
	var src = run.get("covenants")
	if src == null:
		return []
	if src is Array:
		return src
	if src is Object and src.has_method("draw_data"):
		var d = src.call("draw_data")
		if d is Array:
			return d
	if src is Dictionary:
		var cards = src.get("cards", [])
		if cards is Array:
			return cards
	return []

func _relic_ids(st) -> Array:
	var out: Array = []
	if st != null and st.has_method("relic_defs"):
		for d in st.relic_defs():
			if d is Dictionary:
				out.append(String(d.get("id", "")))
			else:
				out.append(String(d))
		if not out.is_empty():
			return out
	var src = run.get("relics") if run != null else null
	if src is Array and not src.is_empty():
		return src
	src = run.get("relic_ids") if run != null else null
	if src is Array:
		return src
	return []

## 机制提示（保留旧功能：优先 mechanics.hint() 的中文整句）
func _mechanics_text() -> String:
	if run == null:
		return ""
	var mech = run.get("mechanics")
	if mech == null:
		return ""
	if mech is Object and mech.has_method("hint"):
		return String(mech.call("hint"))
	return ""

func _pickup_silver() -> int:
	if run == null:
		return 0
	var rw = run.get("rewards")
	if rw is Dictionary and rw.has("silver_run"):
		return int(rw.get("silver_run", 0))
	if rw is Object:
		var v = rw.get("silver_run")
		if v is int or v is float:
			return int(v)
	var raw = run.get("silver_run")
	if raw is int or raw is float:
		return int(raw)
	return 0

func _meta_silver_bonus() -> int:
	if run == null:
		return 0
	var rw = run.get("rewards")
	if rw is Dictionary and rw.has("meta_silver_bonus"):
		return int(rw.get("meta_silver_bonus", 0))
	if rw is Object:
		var v = rw.get("meta_silver_bonus")
		if v is int or v is float:
			return int(v)
	return 0

func _result_achievement_entries() -> Array:
	if run == null:
		return []
	var src = run.get("achievements")
	if src is Object and src.has_method("newly"):
		var v = src.call("newly")
		if v is Array:
			return v
	if src is Object:
		var v2 = src.get("newly")
		if v2 is Array:
			return v2
	if src is Dictionary:
		var v3 = src.get("newly", [])
		if v3 is Array:
			return v3
	for key in ["new_achievements", "achievements_unlocked", "run_achievements"]:
		var vv = run.get(key)
		if vv is Array and not vv.is_empty():
			return vv
	return []

func _new_relic_ids() -> Array:
	if run == null:
		return []
	for key in ["new_relics", "relics_unlocked"]:
		var v = run.get(key)
		if v is Array and not v.is_empty():
			return v
	return []

func _boss_phase_text(bdef: Dictionary, frac: float) -> String:
	var skills: Array = _phase_skills(bdef)
	if skills.is_empty():
		return ""
	var idx: int = 2 if frac < 0.34 else (1 if frac < 0.67 else 0)
	idx = mini(idx, skills.size() - 1)
	return "阶段 %d · %s" % [idx + 1, String(skills[idx])]

## 首领技能 id → 中文短名（数据里 skills 是 [{id, cd, params}]，直接 String() 会把整个字典糊到 HUD 上）
const SKILL_LABELS := {
	"ring_burst": "环火爆", "aimed_shot": "瞄准齐射", "summon": "召唤从者", "charge": "冲锋",
	"zone_denial": "封锁地带", "heal_self": "自愈", "spawn_totem": "立起图腾", "nova": "新星爆发",
}

func _skill_label(sk: Variant) -> String:
	var id: String = ""
	if sk is Dictionary:
		id = String((sk as Dictionary).get("id", ""))
	else:
		id = String(sk)
	if SKILL_LABELS.has(id):
		return String(SKILL_LABELS[id])
	return id.replace("_", " ")

func _phase_skills(bdef: Dictionary) -> Array:
	var out: Array = []
	var phases = bdef.get("phases", [])
	if phases is Array:
		for p in phases:
			if p is Dictionary:
				var sk = p.get("skills", p.get("name", ""))
				if sk is Array:
					var names: Array = []
					for one in sk:
						var lab: String = _skill_label(one)
						if lab != "" and not names.has(lab):
							names.append(lab)
					out.append(_join(names, "、"))
				else:
					out.append(_skill_label(sk))
			else:
				out.append(_skill_label(p))
	return out

func _reward_dict_text(d) -> String:
	if not (d is Dictionary):
		return String(d)
	var parts: Array = []
	if int(d.get("silver", 0)) != 0:
		parts.append("舍客勒 +%d" % int(d.get("silver", 0)))
	if int(d.get("relics", 0)) != 0:
		parts.append("圣物 +%d" % int(d.get("relics", 0)))
	if int(d.get("coals", 0)) != 0:
		parts.append("火炭 +%d" % int(d.get("coals", 0)))
	if parts.is_empty():
		for k in d.keys():
			parts.append("%s:%s" % [String(k), str(d[k])])
	return _join(parts, " · ")

## 局内拾取总额（舍客勒）：地面银钱（picked_shillings）+ 约卡等即时银两（rewards.silver_run），
## 都按关卡币值放大。结算页「合计括号」「明细局内拾取」「本局拾取」三处必须同源，否则数字自相矛盾。
func _picked_total() -> int:
	var coin: float = _stage_coin()
	var ground: int = int(round(float(int(run.get("picked_shillings"))) * coin))
	return int(round(float(_pickup_silver()) * coin)) + ground

## 银两明细两行（保留旧结算信息）
func _silver_lines(st) -> Array:
	var sec_part: int = int(float(run.get("elapsed")) / 8.0)
	var kill_part: int = int(float(st.kills) / 3.0)
	var win_part: int = 120 if bool(run.get("won")) else 0
	var base: int = sec_part + kill_part + win_part
	var seal: int = _run_int("seal", 1)
	var tier_mult: float = _seal_mult(seal)
	var coin: float = _stage_coin()
	var base_reward: int = int(round(float(_reward_for(bool(run.get("won")), st.kills, float(run.get("elapsed")), seal)) * coin))
	var pick: int = _picked_total()
	var meta_bonus: int = _meta_silver_bonus()
	var l1: String = "银两明细   存活 +%d   击杀 +%d   得胜 +%d   =  %d（×%.2f）" % [sec_part, kill_part, win_part, base, tier_mult * coin]
	var l2: String = "七印 %s ×%.2f   关卡 ×%.2f   结算 +%d   局内拾取 +%d   局外 +%d" % [_tier_name(seal), tier_mult, coin, base_reward, pick, meta_bonus]
	return [l1, l2]

# ---------------------------------------------------------------- 杂项
func _join(arr: Array, sep: String) -> String:
	var out: String = ""
	for i in range(arr.size()):
		if i > 0:
			out += sep
		out += str(arr[i])
	return out

func _fmt_time(t: float) -> String:
	var total: int = maxi(int(floor(t)), 0)
	return "%02d:%02d" % [int(total / 60), total % 60]
