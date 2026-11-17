class_name Chooser
extends Control
## 通用三选一面板：领受（升级）与祭坛（祝圣/合鸣）共用。
## 键盘 1/2/3 选择，鼠标点击也可。

signal picked(index: int)
signal reroll_requested

var title: String = ""
var options: Array = []      # [{name, tag, desc, color, level}]
var active: bool = false
var hover: int = -1
var rerolls: int = 0         # 剩余重掷次数（只用于领受面板）
var _t: float = 0.0

const CARD_W := 300.0
const CARD_H := 62.0
const GAP := 8.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func open(p_title: String, opts: Array, p_rerolls: int = 0) -> void:
	title = p_title
	options = opts
	rerolls = p_rerolls
	active = true
	hover = -1
	visible = true
	set_process(true)
	queue_redraw()

func set_options(opts: Array) -> void:
	options = opts
	hover = -1
	queue_redraw()

func close() -> void:
	active = false
	visible = false
	options = []

func _process(delta: float) -> void:
	if active:
		_t += delta
		queue_redraw()

func _card_rect(i: int) -> Rect2:
	var n: int = options.size()
	var total: float = float(n) * CARD_H + float(maxi(n - 1, 0)) * GAP
	var y0: float = 184.0 - total * 0.5 + 18.0
	return Rect2(320.0 - CARD_W * 0.5, y0 + float(i) * (CARD_H + GAP), CARD_W, CARD_H)

func _draw() -> void:
	if not active:
		return
	var f: Font = GameFont.get_font()
	draw_rect(Rect2(0, 0, 640, 360), Color(0.03, 0.04, 0.07, 0.82), true)
	draw_string(f, Vector2(0, 74), title, HORIZONTAL_ALIGNMENT_CENTER, 640, 15, Color("#E8DCC0"))
	for i in range(options.size()):
		var o: Dictionary = options[i]
		var r: Rect2 = _card_rect(i)
		var c: Color = o.get("color", Color("#C9A66B"))
		var hi: bool = (i == hover)
		draw_rect(r, Color(0.10, 0.11, 0.15, 0.96), true)
		draw_rect(r, c if hi else c.darkened(0.35), false, 2.0 if hi else 1.0)
		draw_rect(Rect2(r.position.x, r.position.y, 3, r.size.y), c, true)
		draw_string(f, Vector2(r.position.x + 10, r.position.y + 18), String(o.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#EDE3CB"))
		var tag: String = String(o.get("tag", ""))
		if tag != "":
			draw_string(f, Vector2(r.position.x + 10, r.position.y + 52), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)
		draw_string(f, Vector2(r.position.x + 84, r.position.y + 34), String(o.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, 206, 8, Color(0.72, 0.70, 0.64))
		draw_string(f, Vector2(r.position.x + r.size.x - 20, r.position.y + 16), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.58, 0.52))
	if rerolls > 0:
		draw_string(f, Vector2(0, 344), "R 重新求问（剩余 %d 次）" % rerolls, HORIZONTAL_ALIGNMENT_CENTER, 640, 9, Color(0.66, 0.62, 0.52))

func _gui_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		hover = -1
		for i in range(options.size()):
			if _card_rect(i).has_point(event.position):
				hover = i
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(options.size()):
			if _card_rect(i).has_point(event.position):
				_choose(i)
				return

func _unhandled_key_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k >= KEY_1 and k <= KEY_9:
			var idx: int = k - KEY_1
			if idx < options.size():
				_choose(idx)
		elif k == KEY_R:
			reroll_requested.emit()

func _choose(i: int) -> void:
	if not active:
		return
	active = false
	visible = false
	picked.emit(i)
