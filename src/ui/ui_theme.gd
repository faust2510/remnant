class_name UITheme
extends RefCounted
## 统一美术语言：「暗蓝石刻 + 烛金镶边 + 羊皮纸卷轴」。
## 所有函数都是纯绘制工具，接收 CanvasItem（Control/Node2D 都行），不持有状态。

const INK := Color("#0E1726")
const INK_DEEP := Color("#080D16")
const INK_SOFT := Color("#16233A")
const STONE := Color("#2A3A52")
const MYSTONE := Color("#4A5B78")
const GOLD := Color("#C9A66B")
const GOLD_BRIGHT := Color("#E0B85A")
const GOLD_PALE := Color("#F2E3B8")
const PARCH := Color("#E8D9B5")
const PARCH_DIM := Color("#B9A887")
const BLOOD := Color("#B4472F")
const OLIVE := Color("#6E8B5A")

static func font() -> Font:
	return GameFont.get_font()

## 双层镶边石刻面板：外金框 + 内暗蓝底 + 内阴影 + 四角铆钉
static func panel(ci: CanvasItem, rect: Rect2, alpha: float = 1.0, rivets: bool = true) -> void:
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return
	var r := rect.abs()
	ci.draw_rect(r, Color(INK_DEEP.r, INK_DEEP.g, INK_DEEP.b, 0.92 * alpha), true)
	ci.draw_rect(r.grow(-1.0), Color(INK.r, INK.g, INK.b, alpha), true)
	ci.draw_rect(r.grow(-2.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.55 * alpha), false, 1.0)
	ci.draw_rect(r.grow(-4.0), Color(INK_SOFT.r, INK_SOFT.g, INK_SOFT.b, alpha), true)
	# 顶部高光与底部内阴影
	ci.draw_rect(Rect2(r.position + Vector2(4, 4), Vector2(r.size.x - 8, 1)), Color(GOLD_PALE.r, GOLD_PALE.g, GOLD_PALE.b, 0.10 * alpha), true)
	ci.draw_rect(Rect2(r.position + Vector2(4, r.size.y - 5), Vector2(r.size.x - 8, 2)), Color(0, 0, 0, 0.28 * alpha), true)
	ci.draw_rect(r, Color(GOLD.r, GOLD.g, GOLD.b, alpha), false, 1.0)
	if rivets:
		for p in [r.position + Vector2(3, 3), Vector2(r.end.x - 3, r.position.y + 3),
				Vector2(r.position.x + 3, r.end.y - 3), r.end - Vector2(3, 3)]:
			rivet(ci, p, 1.6, alpha)

static func rivet(ci: CanvasItem, pos: Vector2, radius: float, alpha: float = 1.0) -> void:
	ci.draw_circle(pos, radius, Color(GOLD_BRIGHT.r, GOLD_BRIGHT.g, GOLD_BRIGHT.b, alpha))
	ci.draw_circle(pos - Vector2(0.4, 0.4), radius * 0.45, Color(GOLD_PALE.r, GOLD_PALE.g, GOLD_PALE.b, 0.9 * alpha))

## 羊皮纸卷轴：上下卷轴杆 + 纸面 + 细横纹
static func scroll(ci: CanvasItem, rect: Rect2, alpha: float = 1.0) -> void:
	var r := rect.abs()
	ci.draw_rect(r, Color(PARCH.r, PARCH.g, PARCH.b, 0.96 * alpha), true)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(PARCH_DIM.r, PARCH_DIM.g, PARCH_DIM.b, alpha), true)
	ci.draw_rect(Rect2(Vector2(r.position.x, r.end.y - 2), Vector2(r.size.x, 2)), Color(PARCH_DIM.r, PARCH_DIM.g, PARCH_DIM.b, alpha), true)
	ci.draw_rect(Rect2(r.position, Vector2(2, r.size.y)), Color(PARCH_DIM.r, PARCH_DIM.g, PARCH_DIM.b, 0.7 * alpha), true)
	ci.draw_rect(Rect2(Vector2(r.end.x - 2, r.position.y), Vector2(2, r.size.y)), Color(PARCH_DIM.r, PARCH_DIM.g, PARCH_DIM.b, 0.7 * alpha), true)
	# 纸纹横线：原先 6px 一条、alpha 0.06，与 8-9px 中文正文的字形横向笔画穿插，
	# 5x 放大读作「文字重影」（modal_v6 实测）。降到 8px 间距 + alpha 0.035，只留纸质感。
	var y: float = r.position.y + 5.0
	while y < r.end.y - 4.0:
		ci.draw_rect(Rect2(Vector2(r.position.x + 4, y), Vector2(r.size.x - 8, 1)), Color(INK.r, INK.g, INK.b, 0.035 * alpha), true)
		y += 8.0

## 金属槽条（经验条/生命条）：深槽 + 内阴影 + 金色填充 + 顶部高光
static func metal_bar(ci: CanvasItem, rect: Rect2, ratio: float, fill: Color, glow: float = 0.0) -> void:
	var r := rect.abs()
	ci.draw_rect(r, Color(INK_DEEP.r, INK_DEEP.g, INK_DEEP.b, 0.95), true)
	ci.draw_rect(r.grow(-1.0), Color(INK_SOFT.r, INK_SOFT.g, INK_SOFT.b, 1.0), true)
	var w: float = maxf(0.0, (r.size.x - 2.0) * clampf(ratio, 0.0, 1.0))
	if w > 0.0:
		var body := Rect2(r.position + Vector2(1, 1), Vector2(w, r.size.y - 2.0))
		ci.draw_rect(body, fill, true)
		ci.draw_rect(Rect2(body.position, Vector2(w, 1)), Color(fill.r + 0.25, fill.g + 0.25, fill.b + 0.25, 0.9), true)
		if glow > 0.01:
			ci.draw_rect(body.grow(1.5), Color(fill.r, fill.g, fill.b, 0.20 * clampf(glow, 0.0, 1.0)), false, 1.0)
	ci.draw_rect(r, Color(GOLD.r, GOLD.g, GOLD.b, 0.75), false, 1.0)

static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color,
		align: int = 0, width: float = -1.0) -> void:
	if s.is_empty():
		return
	ci.draw_string(font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT if align == 0 else (HORIZONTAL_ALIGNMENT_CENTER if align == 1 else HORIZONTAL_ALIGNMENT_RIGHT), width, size, col)

## 32x32 图标框：凹槽 + 图标 + 选中时的呼吸金光
static func icon_frame(ci: CanvasItem, rect: Rect2, tex: Texture2D, src: Rect2, glow: float = 0.0) -> void:
	var r := rect.abs()
	ci.draw_rect(r, Color(INK_DEEP.r, INK_DEEP.g, INK_DEEP.b, 0.95), true)
	if glow > 0.02:
		ci.draw_rect(r.grow(1.0), Color(GOLD_BRIGHT.r, GOLD_BRIGHT.g, GOLD_BRIGHT.b, 0.35 * clampf(glow, 0.0, 1.0)), false, 1.0)
	if tex != null and src.size.x > 0.0:
		ci.draw_texture_rect_region(tex, r, src)
	ci.draw_rect(r, Color(GOLD.r, GOLD.g, GOLD.b, 0.6), false, 1.0)

## 蚀刻标题字：深色描边 + 金色主体
static func etched_title(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color = GOLD_BRIGHT) -> void:
	var f := font()
	for off in [Vector2(2, 2), Vector2(1, 1)]:
		ci.draw_string(f, pos + off * 1.0, s, HORIZONTAL_ALIGNMENT_CENTER, 640.0, size, Color(0, 0, 0, 0.55))
	ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_CENTER, 640.0, size, col)

static func divider(ci: CanvasItem, x0: float, x1: float, y: float, alpha: float = 0.7) -> void:
	ci.draw_line(Vector2(x0, y), Vector2(x1, y), Color(GOLD.r, GOLD.g, GOLD.b, 0.35 * alpha), 1.0)
	ci.draw_circle(Vector2((x0 + x1) * 0.5, y), 1.4, Color(GOLD_BRIGHT.r, GOLD_BRIGHT.g, GOLD_BRIGHT.b, alpha))

## 按钮：石刻底 + 金框；选中时金边呼吸 + 底色提亮
static func button(ci: CanvasItem, rect: Rect2, label: String, active: bool, pulse: float = 0.0) -> void:
	var r := rect.abs()
	var base := Color(INK_SOFT.r, INK_SOFT.g, INK_SOFT.b, 1.0)
	if active:
		base = base.lerp(Color(GOLD_BRIGHT.r, GOLD_BRIGHT.g, GOLD_BRIGHT.b, 1.0), 0.16 + 0.06 * pulse)
	ci.draw_rect(r, Color(INK_DEEP.r, INK_DEEP.g, INK_DEEP.b, 1.0), true)
	ci.draw_rect(r.grow(-1.0), base, true)
	ci.draw_rect(r, Color(GOLD.r, GOLD.g, GOLD.b, 0.9 if active else 0.5), false, 1.0)
	if active:
		ci.draw_rect(r.grow(1.0), Color(GOLD_BRIGHT.r, GOLD_BRIGHT.g, GOLD_BRIGHT.b, 0.25 + 0.15 * pulse), false, 1.0)
	text(ci, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 5.0), label, 13,
		GOLD_BRIGHT if active else PARCH_DIM, 1, r.size.x)

static func star(ci: CanvasItem, center: Vector2, radius: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var ang: float = -PI * 0.5 + i * PI / 5.0
		var rad: float = radius if i % 2 == 0 else radius * 0.45
		pts.append(center + Vector2(cos(ang), sin(ang)) * rad)
	ci.draw_colored_polygon(pts, col)
