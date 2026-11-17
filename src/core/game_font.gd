class_name GameFont
extends RefCounted
## 取一个能显示中文的字体。优先用系统 CJK 字体，找不到就退回引擎内置字体。

const CANDIDATES := [
	"/System/Library/Fonts/STHeiti Medium.ttc",
	"/System/Library/Fonts/STHeiti Light.ttc",
	"/System/Library/Fonts/Supplemental/Songti.ttc",
	"/System/Library/Fonts/Hiragino Sans GB.ttc",
	"/System/Library/Fonts/PingFang.ttc",
	"/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
	"C:/Windows/Fonts/msyh.ttc"
]

static var _cached: Font = null

static func get_font() -> Font:
	if _cached != null:
		return _cached
	for p in CANDIDATES:
		if FileAccess.file_exists(p):
			var f := FontFile.new()
			var err: int = f.load_dynamic_font(p)
			if err == OK:
				f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
				f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
				_cached = f
				return _cached
	_cached = ThemeDB.fallback_font
	return _cached
