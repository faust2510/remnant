class_name WorldRenderer
extends Node2D
## 世界渲染层：从模拟数据直接批量绘制，不建场景节点。
## 敌人 / 投射物 / 宝石 / 区域 / 特效全部在这里用 draw_* 一次性画完。

var run: Node = null

const GEM_COLORS := [Color("#7FE0C0"), Color("#F0D890"), Color("#F07A9A")]
const VIEW := Vector2(640, 360)
const DMG_LIFE := 0.75     # 与 run.DMG_EVENT_LIFE 一致，淡出比例才对得上
const DMG_MAX := 40
const SPARK_LIFE := 0.25
const SPARK_MAX := 160
const CORPSE_LIFE := 0.20     # 击杀尸体残影：短促缩放淡出，比伤害数字先消失
const CORPSE_MAX := 24
const HIT_FX_LIFE := 0.16     # 命中火花
const HIT_FX_MAX := 96

# ---- 纹理缓存：只在 _draw 里取。--sim 下世界层隐藏、_draw 不跑，模拟完全不碰纹理。
var _tex_proj: Texture2D = null
var _proj_tried: bool = false
var _tex_enemy: Texture2D = null
var _tex_enemy_flip: Texture2D = null
var _tex_wit: Texture2D = null
var _tex_wit_flip: Texture2D = null
var _tex_prop: Texture2D = null
var _flip_tried_enemy: bool = false
var _flip_tried_wit: bool = false
var _row_cache: PackedInt32Array = PackedInt32Array()
## 每种敌人一个微弱色偏：36 种敌人共用 8 个剪影，靠色偏区分「同族不同种」
var _tint_cache: PackedColorArray = PackedColorArray()

# ---- 火把火星（纯视觉，只在可见时推进；无 rng，确定性的整数哈希抖动）
var _sparks: Array = []
var _spark_n: int = 0
var _orbit_prev_angle: float = 0.0
var _orbit_prev_ok: bool = false

# ---- 朝向：0 = 右，1 = 左。速度≈0 时保持上次朝向（契约 v3）。
var _face: PackedByteArray = PackedByteArray()
var _player_face: int = 0

# ---- 受击闪白回退：enemies.flash 长度不足时按 hp 变化判定
var _fb_flash: PackedFloat32Array = PackedFloat32Array()
var _fb_hp: PackedFloat32Array = PackedFloat32Array()

# ---- 浮动伤害数字：直接读 run.dmg_events + run.dmg_life（渲染层只读，run 自己维护过期与删除），同屏硬上限 DMG_MAX

var _dt: float = 1.0 / 60.0

# ---- 击杀尸体：本帧消失的敌人留一具 0.20s 的缩放淡出残影。
# 存活快照用 Vector2i 格键（8px 格）→ Vector3(x, y, typ)，3x3 邻居容差吸收一帧内的移位，
# 纯渲染层推导：不新增模拟字段、不读 run 的 deaths 队列（那个队列在 _tick 里就被清空了）。
var _alive_prev: Dictionary = {}
var _alive_cur: Dictionary = {}
var _corpses: Array = []

# ---- 命中火花：从 run.dmg_events 的新增条目推导（渲染层只读，不删事件）
var _hit_fx: Array = []
var _dmg_seen: int = 0
var _dmg_tail_x: float = -99999.0
var _dmg_tail_amt: float = -99999.0

func _process(delta: float) -> void:
	_dt = clampf(delta, 0.001, 0.05)
	# 世界层隐藏时（--sim / 截图快进）不推进任何视觉粒子：模拟路径零开销
	if visible and run != null:
		_update_sparks(_dt)
		_tick_corpses(_dt)
		_update_hit_fx(_dt)
	queue_redraw()

func _draw() -> void:
	if run == null or run.state == null:
		return
	_draw_ground()
	_draw_altars()
	_draw_gems()
	_draw_ground_coins()
	_draw_zones()
	_draw_mechanics()
	_draw_enemies()
	_draw_corpses()
	_draw_shots()
	_draw_hit_fx()
	_draw_fx()
	_draw_hazard_fx()
	_draw_player()
	_draw_damage_numbers()

func _draw_ground() -> void:
	var p: Vector2 = run.player_pos()
	var half: Vector2 = Vector2(460, 300)
	var r: Rect2 = Rect2(p - half, half * 2.0)
	var g: Dictionary = run.stage.get("ground", {})
	var c_base: Color = Color(String(g.get("base", "#2A2419")))
	var c_speck: Color = Color(String(g.get("speckle", "#3A3122")))
	draw_rect(r, c_base, true)
	# 装饰只画相机可视矩形（外扩 48）：可见区之外交给底色，600 敌人时省下大半地面开销
	var view: Rect2 = _view_rect().grow(48.0)
	var x0: int = int(floor(view.position.x / 32.0))
	var y0: int = int(floor(view.position.y / 32.0))
	var x1: int = int(ceil(view.end.x / 32.0))
	var y1: int = int(ceil(view.end.y / 32.0))
	# 章节配色派生：枯草 / 碎石 / 裂纹 都从 ground 的 base+speckle 混出来，换章不跳色
	var c_grass: Color = c_speck.lerp(Color("#6E5D3A"), 0.55)
	var c_rock: Color = c_speck.lerp(c_base.darkened(0.15), 0.45)
	var c_crack: Color = c_base.darkened(0.38)
	var c_river: Color = c_base.lerp(c_speck, 0.55).darkened(0.22)
	c_river.a = 0.20
	var rocks: bool = bool(g.get("rocks", false))
	# 低频明暗斑（64px 格）：旧版每 64px 一条 1px 竖网格线（c_line），暗底上读作「坐标纸」，
	# 是画面 UI 味的主要来源。改成按格哈希撒 12..43px 宽、3..10px 高的暗斑/亮斑，
	# 只提供大尺度色块层次，不带任何规则直线。
	var mx0: int = int(floor(view.position.x / 64.0))
	var my0: int = int(floor(view.position.y / 64.0))
	var mx1: int = int(ceil(view.end.x / 64.0))
	var my1: int = int(ceil(view.end.y / 64.0))
	for mx in range(mx0, mx1):
		for my in range(my0, my1):
			var hm: int = _hash2(mx + 811, my + 1973)
			var mb: int = hm & 63
			if mb >= 20:
				continue
			var mw: float = 10.0 + float((hm >> 6) & 15)
			var mh: float = 2.0 + float((hm >> 11) & 3)
			var mox: float = float(mx) * 64.0 + float((hm >> 14) & 31)
			var moy: float = float(my) * 64.0 + float((hm >> 20) & 31)
			var mcol: Color
			if (mb & 1) == 0:
				mcol = c_base.darkened(0.12)
				mcol.a = 0.26
			else:
				mcol = c_base.lightened(0.06)
				mcol.a = 0.18
			draw_rect(Rect2(mox, moy, mw, mh), mcol, true)
	for gx in range(x0, x1):
		for gy in range(y0, y1):
			# 一次整数哈希，切成 4 个 6 位字段，分别驱动四层装饰（全程无 rng，--sim 确定性不受影响）
			var h: int = _hash2(gx, gy)
			var b0: int = h & 63
			var b1: int = (h >> 6) & 63
			var b2: int = (h >> 12) & 63
			var b3: int = (h >> 18) & 63
			# 层 0：确定性沙砾（保留旧观感）
			if b0 < 5:
				var sx: float = float(gx) * 32.0 + float((h >> 24) & 31)
				var sy: float = float(gy) * 32.0 + float((h >> 30) & 31)
				draw_rect(Rect2(sx, sy, 2, 2), c_speck, true)
			# 层 1：枯草（两三根斜断线一簇）
			if b1 < 9:
				var gsx: float = float(gx) * 32.0 + float((h >> 36) & 27) + 2.0
				var gsy: float = float(gy) * 32.0 + float((h >> 42) & 27) + 3.0
				draw_line(Vector2(gsx, gsy), Vector2(gsx - 1.5, gsy - 4.0), c_grass, 1.0)
				draw_line(Vector2(gsx + 2.0, gsy), Vector2(gsx + 3.0, gsy - 3.0), c_grass, 1.0)
				if b1 < 3:
					draw_line(Vector2(gsx + 4.0, gsy), Vector2(gsx + 5.5, gsy - 4.5), c_grass, 1.0)
			# 层 2：碎石（旷野章额外给大块石灰岩）
			if b2 < 7:
				var rx: float = float(gx) * 32.0 + float(h & 25) + 3.0
				var ry: float = float(gy) * 32.0 + float((h >> 6) & 25) + 3.0
				var rw: float = 2.0 + float(b2 & 3)
				if rocks and b2 < 3:
					rw += 3.0
				draw_rect(Rect2(rx, ry, rw, 2), c_rock, true)
				draw_line(Vector2(rx, ry + 2.0), Vector2(rx + rw, ry + 2.0), c_base.darkened(0.25), 1.0)
			# 层 3：裂纹（细折线，稀有）
			if b3 == 0:
				var cx: float = float(gx) * 32.0 + 5.0 + float((h >> 12) & 15)
				var cy: float = float(gy) * 32.0 + 6.0 + float((h >> 18) & 15)
				draw_line(Vector2(cx, cy), Vector2(cx + 4.5, cy + 2.0), c_crack, 1.0)
				draw_line(Vector2(cx + 4.5, cy + 2.0), Vector2(cx + 7.0, cy - 1.5), c_crack, 1.0)
	# 层 4：干涸河床（64px 瓦片）。旧版是一条 26..57px 的 2px 水平直线 + 一条 1px 副线，
	# 在暗地上读作「UI 分隔条」。改成三段折线的蜿蜒枯沟：段长/斜率按瓦片哈希取，
	# 沟底再压一条更暗的细线制造深度，沟沿散 3 颗碎石，整体不再是等距横条。
	var tx0: int = int(floor(view.position.x / 64.0))
	var ty0: int = int(floor(view.position.y / 64.0))
	var tx1: int = int(ceil(view.end.x / 64.0))
	var ty1: int = int(ceil(view.end.y / 64.0))
	for tx in range(tx0, tx1):
		for ty in range(ty0, ty1):
			var hr: int = _hash2(tx + 3571, ty + 9151)
			if (hr & 3) != 0:
				continue
			var px0: float = float(tx) * 64.0 + float(hr & 15) + 4.0
			var py0: float = float(ty) * 64.0 + float((hr >> 5) & 31) + 8.0
			var cx: float = px0
			var cy: float = py0
			for seg in range(3):
				var sd: int = (hr >> (seg * 7 + 9)) & 63
				var sl: float = 7.0 + float(sd & 7)
				var rise: float = float((sd >> 3) & 3) - 1.5
				draw_line(Vector2(roundf(cx), roundf(cy)), Vector2(roundf(cx + sl), roundf(cy + rise)), c_river, 1.0)
				cx += sl
				cy += rise
			var gd: int = (hr >> 27) & 63
			var gx0: float = px0 + 3.0 + float(gd & 7)
			draw_line(Vector2(roundf(gx0), roundf(py0 + 1.0)), Vector2(roundf(gx0 + 6.0 + float((gd >> 3) & 7)), roundf(py0 + 2.0)), c_river.darkened(0.35), 1.0)
			for k in range(3):
				var pd: int = (hr >> (k * 6 + 33)) & 63
				var pex: float = px0 + 2.0 + float(pd & 15)
				var pey: float = py0 - 2.0 - float((pd >> 4) & 1)
				draw_rect(Rect2(roundf(pex), roundf(pey), 1.0 + float(pd & 1), 1.0), c_rock, true)

func _draw_altars() -> void:
	for a in run.altars:
		var x: float = float(a["x"])
		var y: float = float(a["y"])
		if bool(a.get("used", false)):
			draw_rect(Rect2(x - 9, y - 6, 18, 12), Color("#4A4030"), true)
			continue
		var pulse: float = 0.5 + 0.5 * sin(run.elapsed * 3.0)
		draw_circle(Vector2(x, y), 22.0 + pulse * 4.0, Color(0.88, 0.72, 0.35, 0.12 + pulse * 0.08))
		draw_rect(Rect2(x - 10, y - 7, 20, 14), Color("#6B5A3C"), true)
		draw_rect(Rect2(x - 10, y - 7, 20, 3), Color("#C9A66B"), true)
		draw_circle(Vector2(x, y - 10), 3.0, Color(1.0, 0.55, 0.2, 0.85 + pulse * 0.15))

func _draw_gems() -> void:
	var view: Rect2 = _view_rect().grow(24.0)
	var tex: Texture2D = _prop_tex()
	var elapsed: float = run.elapsed
	for g in run.gems:
		var gx: float = float(g["x"])
		var gy: float = float(g["y"])
		if gx < view.position.x or gx > view.end.x or gy < view.position.y or gy > view.end.y:
			continue
		var val: int = int(g.get("val", 1))
		# 契约四档：<4 青绿微晶 / <25 金黄 / <100 绯红 / ≥100 星辰王冠
		var tier: int = 0
		if val >= 100:
			tier = 3
		elif val >= 25:
			tier = 2
		elif val >= 4:
			tier = 1
		# sin 悬浮：相位带 x，避免整屏宝石同起同落
		var bob: float = sin(elapsed * 5.0 + gx * 0.03) * 1.6
		if tex != null:
			draw_texture_rect_region(tex, Rect2(gx - 8.0, gy - 8.0 + bob, 16.0, 16.0), SpriteBank.prop_rect("gem", tier))
		else:
			# 图集缺失：回退到旧的三色小方块
			var c: Color = GEM_COLORS[mini(tier, 2)]
			draw_rect(Rect2(gx - 1.5, gy - 1.5 + bob, 3, 3), c, true)
		# 中心高光：菱形切面的反光点
		draw_circle(Vector2(gx - 2.0, gy - 2.5 + bob), 1.0, Color(1, 1, 1, 0.55))

func _draw_zones() -> void:
	for z in run.weapons.zones:
		var c: Color = z["color"]
		var a: float = clampf(float(z["life"]) / 2.6, 0.0, 1.0)
		var zx: float = float(z["x"])
		var zy: float = float(z["y"])
		var zr: float = float(z["r"])
		draw_circle(Vector2(zx, zy), zr, Color(c.r, c.g, c.b, 0.09 * a))
		draw_circle(Vector2(zx, zy), zr, Color(c.r, c.g, c.b, 0.26 * a), false, 1.0)
		draw_circle(Vector2(zx, zy), zr * 0.62, Color(c.r, c.g, c.b, 0.14 * a), false, 1.0)
		# 香炉：中心上升的烟雾圆点（相位驱动，无状态、确定性，不占额外预算）
		for k in range(3):
			var ph: float = fmod(run.elapsed * 0.55 + float(k) * 0.33, 1.0)
			var sy: float = zy - ph * zr * 0.95
			var sx: float = zx + sin(ph * 6.2 + float(k) * 2.1) * 3.4
			draw_circle(Vector2(sx, sy), 1.2 + ph * 2.4, Color(0.90, 0.88, 0.82, (1.0 - ph) * 0.16 * maxf(a, 0.35)))

func _draw_enemies() -> void:
	var e: EnemySim = run.enemies
	if e == null or e.count <= 0:
		# 全清场：把上一帧还活着的一次性结算成尸体，别把陈旧快照留到下一波
		if not _alive_prev.is_empty():
			_alive_cur.clear()
			_harvest_corpses()
		return
	var view: Rect2 = _view_rect().grow(56.0)
	var pp: Vector2 = run.player_pos()
	var elapsed: float = run.elapsed
	var tex: Texture2D = _enemy_tex()
	var flip: Texture2D = _tex_enemy_flip
	_sync_row_cache(e, tex != null)
	# 清单行列与贴图实际尺寸对不上（美术还在写文件）时按贴图收敛，绝不采样到格子外
	var sheet_rows: int = _sheet_rows(tex, "enemies")
	_alive_cur.clear()
	# 契约 v3：受击闪白读 enemies.flash；数组长度不足时回退到 hp 变化判定
	var flash_ok: bool = e.flash.size() >= e.count
	if not flash_ok:
		_sync_flash_fallback(e)
	if _face.size() < e.count:
		_face.resize(e.count)
	for i in range(e.count):
		var x: float = e.px[i]
		var y: float = e.py[i]
		# 视口外（外扩 56）一律不画：600+ 敌人时这是最大的一笔省
		if x < view.position.x or x > view.end.x or y < view.position.y or y > view.end.y:
			continue
		var fi: float = 0.0
		if flash_ok:
			fi = e.flash[i]
		elif i < _fb_flash.size():
			fi = _fb_flash[i]
		var t: Dictionary = e.types[e.typ[i]]
		var base: Color = Color(String(t.get("color", "#8A7F6D")))
		var col: Color = base
		if fi > 0.0:
			col = Color(1, 1, 1)
		elif e.burn_t[i] > 0.0:
			col = Color(minf(base.r + 0.35, 1.0), base.g * 0.8, base.b * 0.6)
		var r: float = e.rad[i]
		var vx: float = e.vx[i]
		var spd: float = sqrt(vx * vx + e.vy[i] * e.vy[i])
		# 朝向：速度≈0 时保持上次朝向（swap_remove 换位后最多错一帧，看不出来）
		if absf(vx) > 4.0:
			_face[i] = 1 if vx < 0.0 else 0
		var row: int = -1
		if tex != null and e.typ[i] < _row_cache.size():
			row = _row_cache[e.typ[i]]
			if row >= sheet_rows:
				row = -1
		# 存活快照：给「这一帧消失的敌人」留尸体残影用
		_alive_cur[Vector2i(int(x) >> 3, int(y) >> 3)] = Vector3(x, y, float(e.typ[i]))
		# 图集只按 1:1 或 2 倍整数放大（禁止模糊缩放）；r>=9 的精英/BOSS 用 2 倍
		var scl: float = 2.0 if r >= 9.0 else 1.0
		var ecell: float = float(SpriteBank.cell_of("enemies"))
		var ehalf: float = ecell * 0.5
		var vr: float = ehalf * scl if row >= 0 else r
		var boss: bool = e.is_boss(i)
		var feet: float = y + r * 0.62 if row >= 0 else y + r * 0.75
		var vcy: float = feet - ehalf * 0.82 * scl if row >= 0 else y
		# 落地投影（先于本体与光环）
		draw_rect(Rect2(x - vr * 0.72, feet - 1.0, vr * 1.44, maxf(2.0, vr * 0.20)), Color(0, 0, 0, 0.25), true)
		if boss:
			# 光环贴住精灵中心（回退几何的 vcy 就等于 y）
			_draw_boss_aura(x, vcy, vr, e, i)
		if row >= 0:
			var btint := Color(1, 1, 1, 1)
			if e.typ[i] >= 0 and e.typ[i] < _tint_cache.size():
				btint = _tint_cache[e.typ[i]]
			_draw_enemy_sprite(x, feet, scl, row, tex, flip, i, spd, elapsed, fi, btint)
		elif boss:
			_draw_enemy_boss_proc(x, y, r, col)
		else:
			_draw_enemy_proc(x, y, r, col, t, pp)
		# 属性外观分型（飞行/披甲/召唤/自爆/精英）+ 致盲
		_draw_enemy_marks(x, vcy, vr, col, t, elapsed, e.blind_t[i] > 0.0)
	_harvest_corpses()

## 每只敌人只发一次 draw_texture_rect_region：图集区域 + 一次性烘焙的镜像图集，不用 draw_set_transform
func _draw_enemy_sprite(x: float, feet: float, scl: float, row: int, tex: Texture2D, flip: Texture2D, i: int, spd: float, elapsed: float, fi: float, base_tint: Color = Color(1, 1, 1, 1)) -> void:
	var body: Texture2D = tex
	if _face[i] == 1 and flip != null:
		body = flip
	# 4 帧循环：速度比越快步频越高；每只按索引错开相位，避免整屏同步
	var frames_ok: int = _sheet_frames(tex, "enemies")
	var frame: int = SpriteBank.enemy_frame(elapsed + float((i * 37) % 97) * 0.01, clampf(spd / 60.0, 0.0, 2.0))
	frame = frame % maxi(frames_ok, 1)
	var ecell2: float = float(SpriteBank.cell_of("enemies"))
	var efeet: float = float(SpriteBank.feet_of("enemies"))
	var src: Rect2 = SpriteBank.frame_rect(row, frame, "enemies")
	# 整数倍缩放 + 整像素落位：nearest 采样下只有整像素才不会糊
	var dst := Rect2(roundf(x - ecell2 * 0.5 * scl), roundf(feet - efeet * scl), ecell2 * scl, ecell2 * scl)
	var tint := base_tint
	if fi > 0.0:
		# 受击白闪：flash 从 0.12 线性衰减，前 3 帧几乎纯白（k 到 2.4 再回落），
		# 比旧版 1.6 上限明显得多，且不会把 32px 图集糊成一团白。
		var k: float = clampf(1.0 + fi * 18.0, 1.0, 2.6)
		tint = Color(k, k, k, 1.0)
	draw_texture_rect_region(body, dst, src, tint)

## 图集行缓存：type_ids 不变就不重复做字符串查找
func _sync_row_cache(e: EnemySim, has_tex: bool) -> void:
	if not has_tex:
		return
	if _row_cache.size() == e.type_ids.size():
		return
	_row_cache.resize(e.type_ids.size())
	_tint_cache.resize(e.type_ids.size())
	for k in range(e.type_ids.size()):
		var sid: String = String(e.type_ids[k])
		_row_cache[k] = SpriteBank.enemy_row(sid)
		# 色偏只做 ±10% 级别的微调：不破坏图集原画，但让 36 个 id 不至于长得一模一样
		var th: int = absi(sid.hash())
		var dr: float = float((th >> 3) % 17 - 8) * 0.010
		var dg: float = float((th >> 9) % 13 - 6) * 0.008
		var db: float = float((th >> 15) % 17 - 8) * 0.012
		_tint_cache[k] = Color(
			clampf(1.0 + dr, 0.88, 1.10),
			clampf(1.0 + dg, 0.90, 1.08),
			clampf(1.0 + db, 0.86, 1.14),
			1.0)

func _draw_boss_aura(x: float, y: float, vr: float, e: EnemySim, i: int) -> void:
	var bfrac: float = clampf(e.hp[i] / maxf(e.max_hp[i], 1.0), 0.0, 1.0)
	var bpulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.004)
	var aura: Color = Color(0.86, 0.32, 0.24, 0.08 + 0.06 * bpulse)
	if bfrac <= 0.33:
		aura = Color(0.96, 0.62, 0.22, 0.12 + 0.10 * bpulse)
	elif bfrac <= 0.66:
		aura = Color(0.92, 0.48, 0.22, 0.10 + 0.08 * bpulse)
	draw_circle(Vector2(x, y), vr * (1.5 + 0.10 * bpulse), aura)
	for k in range(2):
		draw_arc(Vector2(x, y), vr * (1.25 + 0.22 * float(k)), 0.0, TAU, 24, Color(0.90, 0.72, 0.46, 0.10), 1.0)

## 未收录图集的 BOSS：保留旧的悬空方块 + 尖角
func _draw_enemy_boss_proc(x: float, y: float, r: float, col: Color) -> void:
	var light: Color = col.lightened(0.24)
	var dark: Color = col.darkened(0.35)
	draw_rect(Rect2(x - r, y - r * 0.9, r * 2.0, r * 1.9), col, true)
	draw_rect(Rect2(x - r * 0.7, y - r * 1.7, r * 1.4, r * 0.8), light, true)
	draw_rect(Rect2(x - r, y + r * 0.4, r * 2.0, r * 0.6), dark, true)
	draw_rect(Rect2(x - 1, y - r * 1.7, 2, r * 0.8), Color("#B33A2A"), true)

## 未收录进图集的敌人（SpriteBank.enemy_row < 0）继续走旧几何绘制
func _draw_enemy_proc(x: float, y: float, r: float, col: Color, t: Dictionary, pp: Vector2) -> void:
	var dark: Color = col.darkened(0.35)
	var light: Color = col.lightened(0.24)
	var beh: String = String(t.get("behavior", "chase"))
	match beh:
		"ranged":
			draw_rect(Rect2(x - r * 0.8, y - r * 0.7, r * 1.6, r * 1.5), col, true)
			draw_rect(Rect2(x - r * 0.55, y - r * 1.25, r * 1.1, r * 0.55), light, true)
			draw_arc(Vector2(x, y), r * 1.25, -0.9, 0.9, 8, light, 1.0)
		"dive":
			# 两个三角形代替四边形：draw_colored_polygon 在退化四边形上会 triangulation failed
			var top := Vector2(x, y - r)
			var right := Vector2(x + r, y)
			var bot := Vector2(x, y + r * 0.8)
			var left := Vector2(x - r, y)
			draw_primitive(PackedVector2Array([top, right, bot]), PackedColorArray([col, col, col]), PackedVector2Array())
			draw_primitive(PackedVector2Array([top, bot, left]), PackedColorArray([col, col, col]), PackedVector2Array())
			draw_line(Vector2(x - r * 1.6, y - r * 0.3), Vector2(x - r * 0.2, y), Color(col.r, col.g, col.b, 0.55), 1.0)
			draw_line(Vector2(x + r * 1.6, y - r * 0.3), Vector2(x + r * 0.2, y), Color(col.r, col.g, col.b, 0.55), 1.0)
		"charger":
			draw_rect(Rect2(x - r, y - r * 0.7, r * 2.0, r * 1.4), col, true)
			draw_rect(Rect2(x - r * 0.5, y - r * 1.3, r, r * 0.6), light, true)
			draw_line(Vector2(x - r, y - r * 1.1), Vector2(x - r * 1.5, y - r * 1.8), light, 1.0)
			draw_line(Vector2(x + r, y - r * 1.1), Vector2(x + r * 1.5, y - r * 1.8), light, 1.0)
		_:
			draw_rect(Rect2(x - r * 0.85, y - r * 0.85, r * 1.7, r * 1.7), col, true)
			draw_rect(Rect2(x - r * 0.85, y + r * 0.3, r * 1.7, r * 0.55), dark, true)
			draw_rect(Rect2(x - r * 0.58, y - r * 1.35, r * 1.16, r * 0.6), light, true)
			var dir: Vector2 = (pp - Vector2(x, y)).normalized()
			draw_line(Vector2(x, y) + dir * r, Vector2(x, y) + dir * r * 2.4, light, 1.0)

## 属性分型：精灵与几何回退共用（只对真带这些字段的敌人多画几笔）
func _draw_enemy_marks(x: float, vcy: float, vr: float, col: Color, t: Dictionary, elapsed: float, blind: bool) -> void:
	if bool(t.get("flying", false)):
		draw_line(Vector2(x - vr, vcy - vr * 0.2), Vector2(x - vr * 2.1, vcy - vr * 0.7), Color(col.r, col.g, col.b, 0.55), 1.0)
		draw_line(Vector2(x + vr, vcy - vr * 0.2), Vector2(x + vr * 2.1, vcy - vr * 0.7), Color(col.r, col.g, col.b, 0.55), 1.0)
	if bool(t.get("armored", false)):
		draw_arc(Vector2(x, vcy), vr * 1.15, -2.6, -0.5, 8, Color(0.72, 0.74, 0.80, 0.65), 1.5)
	if bool(t.get("summoner", false)):
		for k in range(3):
			var ang: float = elapsed * 1.6 + TAU * float(k) / 3.0
			draw_circle(Vector2(x + cos(ang) * vr * 1.5, vcy + sin(ang) * vr * 0.8), 1.4, Color(0.72, 0.55, 0.90, 0.85))
	if bool(t.get("exploder", false)):
		var ep: float = 0.5 + 0.5 * sin(elapsed * 8.0)
		draw_circle(Vector2(x, vcy), vr * (1.15 + 0.2 * ep), Color(0.95, 0.55, 0.20, 0.16 + 0.14 * ep), false, 1.0)
	if bool(t.get("elite", false)):
		var ac: Color = _affix_color(t)
		draw_rect(Rect2(x - vr - 2.0, vcy - vr - 2.0, (vr + 2.0) * 2.0, (vr + 2.0) * 2.0), Color(ac.r, ac.g, ac.b, 0.62), false, 1.0)
		var dm: float = vr + 6.0
		draw_primitive(PackedVector2Array([Vector2(x, vcy - dm - 3.0), Vector2(x + 3.0, vcy - dm), Vector2(x, vcy - dm + 3.0), Vector2(x - 3.0, vcy - dm)]), PackedColorArray([ac, ac, ac, ac]), PackedVector2Array())
	if blind:
		draw_circle(Vector2(x, vcy - vr * 1.6), 1.5, Color(0.9, 0.9, 1.0, 0.8))

## 弹道：走 ProjectileVisuals 的 weapon→{row,tint,scale,trail} 映射。
## 图集到手 → 贴图 + 发光描边 + 4 段残影；图集/行缺失 → 同色系的程序化剪影（形状按行区分），
## 两条路径都保住「4 段残影 + 发光 + 命中火花」，所以占位期也不会退化成一根方条。
func _draw_shots() -> void:
	var s: ProjectileSim = run.shots
	if s == null or s.count <= 0:
		return
	var tex: Texture2D = _proj_tex()
	if tex != null:
		ProjectileVisuals.rebuild_index(_equipped_weapon_ids())
	var view: Rect2 = _view_rect().grow(28.0)
	var cell: float = float(SpriteBank.cell_of(ProjectileVisuals.SHEET))
	var elapsed: float = run.elapsed
	for i in range(s.count):
		var x: float = s.px[i]
		var y: float = s.py[i]
		# 拖尾与本体都只画可视矩形内
		if x < view.position.x or x > view.end.x or y < view.position.y or y > view.end.y:
			continue
		var vx: float = s.vx[i]
		var vy: float = s.vy[i]
		var sz: float = maxf(s.size[i], 1.6)
		var prof: Dictionary = ProjectileVisuals.resolve(int(s.color[i]), int(s.status[i]), sz, int(s.friendly[i]) != 0)
		var row: int = ProjectileVisuals.row_index(String(prof.get("row", "stone")), tex)
		if row >= 0:
			_draw_shot_sprite(x, y, vx, vy, prof, row, tex, cell, elapsed, i)
		else:
			_draw_shot_proc(x, y, vx, vy, sz, prof, int(s.color[i]))


## 图集路径：两层发光底 → 4 段残影 → 本体。全部整像素落位（nearest 采样下不糊边）
func _draw_shot_sprite(x: float, y: float, vx: float, vy: float, prof: Dictionary, row: int, tex: Texture2D, cell: float, elapsed: float, i: int) -> void:
	var scl: float = float(prof.get("scale", 1))
	var tint: Color = prof.get("tint", Color(1, 1, 1, 1)) as Color
	var glow: Color = prof.get("glow", Color("#F0D890")) as Color
	var frames_ok: int = _sheet_frames(tex, ProjectileVisuals.SHEET)
	var frame: int = ProjectileVisuals.frame_for(elapsed, i, tex) % maxi(frames_ok, 1)
	var src: Rect2 = SpriteBank.frame_rect(row, frame, ProjectileVisuals.SHEET)
	var half: float = cell * 0.5 * scl
	# 发光描边：紧贴 sprite 的两层暖光（半径太大会糊成一圈土黄色晕，16px 图配 0.55/0.34 正好）
	draw_circle(Vector2(roundf(x), roundf(y)), maxf(cell * 0.55, 4.0) * scl, Color(glow.r, glow.g, glow.b, 0.14))
	draw_circle(Vector2(roundf(x), roundf(y)), maxf(cell * 0.34, 2.5) * scl, Color(glow.r, glow.g, glow.b, 0.26))
	# 4 段残影：按速度回溯 gap*k 秒（残影段数由档案给，默认 4）
	var n: int = int(prof.get("trail", 4))
	var gap: float = float(prof.get("gap", 0.014))
	for k in range(1, n + 1):
		var back: float = gap * float(k)
		var tx: float = roundf(x - vx * back - half)
		var ty: float = roundf(y - vy * back - half)
		var a: float = 0.34 * pow(0.60, float(k - 1))
		draw_texture_rect_region(tex, Rect2(tx, ty, half * 2.0, half * 2.0), src, Color(tint.r, tint.g, tint.b, a))
	draw_texture_rect_region(tex, Rect2(roundf(x - half), roundf(y - half), half * 2.0, half * 2.0), src, tint)


## 回退路径：图集未交付时按行给同色系剪影（石块/箭/火/刃/音符/水/冲击/火花），
## 形状跟着 row 走，所以读屏时能分清是「石弹」还是「火球」。
func _draw_shot_proc(x: float, y: float, vx: float, vy: float, sz: float, prof: Dictionary, color_code: int) -> void:
	# 回退路径也吃 weapon 档案的 tint：同是 burn，火把的暖白和战车的橘红要能分开，
	# 这样在 projectiles.png 还没交付时，20 把武器的弹道也不是一坨同色圆点。
	var c: Color = _shot_color(color_code)
	var tint: Color = prof.get("tint", Color(1, 1, 1, 1)) as Color
	c = c.lerp(tint, 0.55)
	var glow: Color = prof.get("glow", c) as Color
	var row: String = String(prof.get("row", "stone"))
	if color_code == ProjectileSim.COL_ENEMY:
		glow = Color("#B4472F")
	# 发光描边
	draw_circle(Vector2(x, y), sz * 1.9, Color(glow.r, glow.g, glow.b, 0.10))
	draw_circle(Vector2(x, y), sz * 1.15, Color(glow.r, glow.g, glow.b, 0.18))
	# 4 段残影：段与段之间用锥形描线连起来，否则等距圆点读起来是「子弹 + 一串珠子」而不是拖尾。
	# 顺序从最远段往回画，近段压在上面，自然形成亮头暗尾。
	var spd2: float = vx * vx + vy * vy
	if spd2 > 900.0:
		var n: int = int(prof.get("trail", 4))
		var gap: float = float(prof.get("gap", 0.014))
		var p0 := Vector2(x, y)
		for k in range(n, 0, -1):
			var pa := Vector2(x - vx * gap * float(k - 1), y - vy * gap * float(k - 1))
			var pb := Vector2(x - vx * gap * float(k), y - vy * gap * float(k))
			var a: float = 0.30 * pow(0.64, float(k - 1))
			var w: float = maxf(0.9, sz * 0.86 * (1.0 - 0.17 * float(k - 1)))
			draw_line(pa, pb, Color(c.r, c.g, c.b, a), w)
		draw_circle(p0 - Vector2(vx, vy).normalized() * sz * 0.5, maxf(0.8, sz * 0.34), Color(c.r, c.g, c.b, 0.30))
	var d := Vector2.RIGHT
	if spd2 > 1.0:
		d = Vector2(vx, vy).normalized()
	match row:
		"arrow":
			draw_line(Vector2(x, y) - d * sz * 1.3, Vector2(x, y) + d * sz * 0.9, c, maxf(1.0, sz * 0.42))
			draw_circle(Vector2(x, y) + d * sz * 0.9, maxf(0.9, sz * 0.30), c.lightened(0.35))
		"blade":
			var nd := Vector2(-d.y, d.x)
			draw_primitive(
				PackedVector2Array([Vector2(x, y) + d * sz * 1.5, Vector2(x, y) + nd * sz * 0.52, Vector2(x, y) - d * sz * 0.9, Vector2(x, y) - nd * sz * 0.52]),
				PackedColorArray([c.lightened(0.34), c, c, c.lightened(0.34)]),
				PackedVector2Array()
			)
		"flame":
			for k in range(3):
				var ph: float = fmod(run.elapsed * 7.0 + float(k) * 0.34 + x * 0.02, 1.0)
				draw_circle(Vector2(x + sin(ph * 6.0) * sz * 0.34, y + sz * 0.5 - ph * sz * 1.5), sz * (0.55 - ph * 0.30), Color(1.0, 0.60 + ph * 0.28, 0.20, 0.55 + 0.35 * ph))
			draw_circle(Vector2(x, y), sz * 0.62, c)
		"note":
			draw_arc(Vector2(x, y), sz * 1.05, -2.4, 0.7, 10, c, maxf(1.0, sz * 0.30))
			draw_arc(Vector2(x, y), sz * 0.58, -2.4, 0.7, 10, c.lightened(0.28), 1.0)
		"water":
			draw_circle(Vector2(x, y), sz * 0.58, c)
			draw_circle(Vector2(x - sz * 0.20, y - sz * 0.20), sz * 0.22, c.lightened(0.45))
		"shock":
			draw_circle(Vector2(x, y), sz * 0.78, c, false, maxf(1.0, sz * 0.30))
			draw_circle(Vector2(x, y), sz * 1.30, Color(c.r, c.g, c.b, 0.42), false, 1.0)
		"spark":
			draw_rect(Rect2(roundf(x - sz * 0.42), roundf(y - sz * 0.42), maxf(1.0, sz * 0.84), maxf(1.0, sz * 0.84)), c, true)
			draw_circle(Vector2(x, y), sz * 0.26, Color(1, 1, 1, 0.85))
		_:  # stone：主力弹（投石/颚骨/敌方重弹）
			draw_circle(Vector2(x, y), sz * 0.62, c)
			draw_circle(Vector2(x - sz * 0.18, y - sz * 0.18), sz * 0.24, c.lightened(0.40))


## 投影物图集（缺失 → null，全走程序化回退）
func _proj_tex() -> Texture2D:
	if not _proj_tried:
		_proj_tried = true
		_tex_proj = SpriteBank.projectiles()
	return _tex_proj


## 当前装备的武器 id（弹幕不携带 weapon id，只能靠 (color,status,size) 反查档案）
func _equipped_weapon_ids() -> Array:
	var out: Array = []
	var st = run.get("state")
	if st == null:
		return out
	var ws = st.get("weapons")
	if ws is Array:
		for w in ws:
			if w is Dictionary:
				out.append(String((w as Dictionary).get("id", "")))
	return out


## 清单行列数 vs 贴图实际尺寸：美术还在写文件时以贴图为准，绝不采样到格子外
func _sheet_rows(tex: Texture2D, sheet: String) -> int:
	if tex == null:
		return 0
	var c: int = SpriteBank.cell_of(sheet)
	if c <= 0:
		return 0
	return int(tex.get_height() / c)


func _sheet_frames(tex: Texture2D, sheet: String) -> int:
	if tex == null:
		return 1
	var c: int = SpriteBank.cell_of(sheet)
	if c <= 0:
		return 1
	return clampi(int(tex.get_width() / c), 1, maxi(SpriteBank.frames_of(sheet), 1))

## 三类基准色：圣石土金 / 音刃淡金 / 敌方红；火水沿用自己的色
func _shot_color(code: int) -> Color:
	match code:
		ProjectileSim.COL_SOUND:
			return Color("#F2E3B8")
		ProjectileSim.COL_FIRE:
			return Color("#E0731A")
		ProjectileSim.COL_WATER:
			return Color("#6FA8C4")
		ProjectileSim.COL_ENEMY:
			return Color("#B4472F")
		_:
			return Color("#C9A66B")

func _draw_fx() -> void:
	for f in run.active_fx:
		var life: float = float(f["life"])
		var a: float = clampf(life / 0.4, 0.0, 1.0)
		var c: Color = f.get("color", Color("#E0B85A"))
		match String(f["kind"]):
			"arc":
				# 牧杖 / 号角：三层渐变半透明扇形 + 边缘高光，0.22s 淡出并向外扩张
				_draw_arc_fx(f, c)
			"nova":
				var rr: float = float(f["r"]) * (1.0 - a * 0.85)
				draw_circle(Vector2(float(f["x"]), float(f["y"])), rr, Color(c.r, c.g, c.b, 0.35 * a), false, 3.0)
			"spark":
				draw_circle(Vector2(float(f["x"]), float(f["y"])), float(f.get("r", 3.0)), Color(1, 1, 1, 0.6 * a))
			"pop":
				var pr: float = float(f.get("r", 5.0)) * (1.6 - a)
				draw_circle(Vector2(float(f["x"]), float(f["y"])), pr, Color(c.r, c.g, c.b, 0.55 * a), false, 1.5)

## 弧形挥击：外/中/内三层渐变扇形（越靠内越亮）+ 外弧与径向边高光
func _draw_arc_fx(f: Dictionary, c: Color) -> void:
	var life: float = maxf(float(f["life"]), 0.0)
	var fade: float = clampf(life / 0.22, 0.0, 1.0)
	if fade <= 0.01:
		return
	var cen := Vector2(float(f["x"]), float(f["y"]))
	var ang: float = float(f["ang"])
	var half: float = maxf(float(f["arc"]), 0.2) * 0.5
	var a0: float = ang - half
	var a1: float = ang + half
	# 向外扩张：越淡越大（最大 18%）
	var grow: float = 1.0 + (1.0 - fade) * 0.18
	var rr: float = maxf(float(f["r"]), 6.0) * grow
	_fill_ring_sector(cen, rr * 0.72, rr, a0, a1, Color(c.r, c.g, c.b, 0.10 * fade))
	_fill_ring_sector(cen, rr * 0.42, rr * 0.72, a0, a1, Color(c.r, c.g, c.b, 0.17 * fade))
	_fill_ring_sector(cen, 1.5, rr * 0.42, a0, a1, Color(minf(c.r + 0.25, 1.0), minf(c.g + 0.22, 1.0), minf(c.b + 0.12, 1.0), 0.26 * fade))
	draw_arc(cen, rr, a0, a1, 14, Color(1.0, 0.96, 0.82, 0.62 * fade), 1.6)
	var hi := Color(c.r, c.g, c.b, 0.45 * fade)
	draw_line(cen + Vector2(cos(a0), sin(a0)) * (rr * 0.2), cen + Vector2(cos(a0), sin(a0)) * rr, hi, 1.0)
	draw_line(cen + Vector2(cos(a1), sin(a1)) * (rr * 0.2), cen + Vector2(cos(a1), sin(a1)) * rr, hi, 1.0)

## 环扇形填充（外弧 + 内弧闭合的多边形，简单多边形，triangulation 安全）
func _fill_ring_sector(cen: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	if col.a <= 0.004 or r1 <= r0:
		return
	var seg: int = 10
	var pts := PackedVector2Array()
	for k in range(seg + 1):
		var a: float = lerpf(a0, a1, float(k) / float(seg))
		pts.append(cen + Vector2(cos(a), sin(a)) * r1)
	for k in range(seg, -1, -1):
		var a2: float = lerpf(a0, a1, float(k) / float(seg))
		pts.append(cen + Vector2(cos(a2), sin(a2)) * r0)
	draw_colored_polygon(pts, col)

func _draw_player() -> void:
	var p: Vector2 = run.player_pos()
	# 信心跨步的残影
	if run.dash_iframe > 0.0:
		draw_circle(p, 9.0, Color(0.75, 0.85, 1.0, 0.25))
	# 朝向：按移动方向水平翻转，速度≈0 保持上次朝向
	var mv = run.get("last_move_dir")
	var mv_v: Vector2 = mv if mv is Vector2 else Vector2.ZERO
	if absf(mv_v.x) > 0.05:
		_player_face = 1 if mv_v.x < 0.0 else 0
	draw_ellipse_shadow(p.x, p.y + 8, 7.0, 2.6)
	var tex: Texture2D = _witness_tex()
	var row: int = -1
	if tex != null:
		row = SpriteBank.witness_row(String(run.character_id))
		if row >= _sheet_rows(tex, "witnesses"):
			row = -1
	if row >= 0:
		# 图集 1:1，脚底对齐 p.y + 8（格内脚底 y≈29）
		var body: Texture2D = tex
		if _player_face == 1 and _tex_wit_flip != null:
			body = _tex_wit_flip
		var moving: bool = run.dash_time > 0.0 or mv_v.length() > 0.05
		var frame: int = SpriteBank.witness_frame(run.elapsed, moving)
		frame = frame % maxi(_sheet_frames(tex, "witnesses"), 1)
		var wcell: float = float(SpriteBank.cell_of("witnesses"))
		var wfeet: float = float(SpriteBank.feet_of("witnesses"))
		# 整数倍缩放（48px 格 1:1）+ 整像素落位：脚底对齐 p.y + 8
		draw_texture_rect_region(body, Rect2(roundf(p.x - wcell * 0.5), roundf(p.y + 8.0 - wfeet), wcell, wcell), SpriteBank.frame_rect(row, frame))
		# 精灵本身没有武器朝向：手动瞄准时点一颗石子作指示
		var aim: Vector2 = run.aim_dir
		if aim.length() > 0.1:
			draw_circle(p + aim * 12.0, 1.6, Color("#F0D890"))
	else:
		_draw_player_proc(p)
	# 环绕武器（火把）：光点 + 火星拖拽
	for entry in run.state.weapons:
		if run.state.entry_behavior(entry) != "orbit":
			continue
		for pt in run.weapons.orbit_points(entry, p):
			var c: Color = run.state.entry_color(entry)
			var px2: float = float(pt["x"])
			var py2: float = float(pt["y"])
			draw_circle(Vector2(px2, py2), float(pt["size"]) * 0.9, Color(c.r, c.g, c.b, 0.2))
			draw_circle(Vector2(px2, py2), float(pt["size"]) * 0.55, Color(c.r, c.g, c.b, 0.9))
	for s in _sparks:
		var sa: float = clampf(float(s["life"]) / SPARK_LIFE, 0.0, 1.0)
		if sa <= 0.01:
			continue
		draw_circle(Vector2(float(s["x"]), float(s["y"])), float(s["r"]) * (0.55 + 0.55 * sa), Color(1.0, 0.58 + 0.2 * sa, 0.20, 0.5 * sa))

## 未收录图集（或图集缺失）的见证人：大卫的旧几何回退
func _draw_player_proc(p: Vector2) -> void:
	var aim: Vector2 = run.aim_dir
	var face: Vector2 = aim if aim.length() > 0.1 else Vector2(0, 1)
	draw_rect(Rect2(p.x - 5, p.y - 5, 10, 12), Color("#E8DCC0"), true)
	draw_rect(Rect2(p.x - 5, p.y + 2, 10, 3), Color("#B99460"), true)
	draw_rect(Rect2(p.x - 4, p.y - 9, 8, 5), Color("#D8B98A"), true)
	draw_rect(Rect2(p.x - 4, p.y - 9, 8, 2), Color("#6B4A2A"), true)
	draw_circle(Vector2(p.x - 1.5, p.y - 6.5), 0.9, Color("#2E2418"))
	draw_circle(Vector2(p.x + 1.5, p.y - 6.5), 0.9, Color("#2E2418"))
	draw_arc(p + face * 3.0, 7.0, face.angle() - 1.1, face.angle() - 0.2, 6, Color("#C9A66B"), 1.4)
	draw_circle(p + face * 9.5, 1.4, Color("#F0D890"))

func draw_ellipse_shadow(x: float, y: float, rx: float, ry: float) -> void:
	draw_set_transform(Vector2(x, y), 0.0, Vector2(1.0, ry / maxf(rx, 0.001)))
	draw_circle(Vector2.ZERO, rx, Color(0, 0, 0, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ================================================================ V2 机制可视化
# 数据由局内系统写入（字段名见 docs/V2-接口需求-ui.md），渲染层只读、不推断玩法状态。
# 统一约定：每个危险区是 Dictionary，kind 取 lightning / meteor / wall / glass / band，
# 位置 x,y（缺省用玩家位置），半径 r（缺省 30），倒计时 left/t（秒），预警窗 warn（秒）。

func _zf(d: Dictionary, key: String, def: float) -> float:
	var v = d.get(key, null)
	if v is float or v is int:
		return float(v)
	return def

func _z_left(z: Dictionary) -> float:
	for k in ["left", "t", "remaining", "timer", "delay"]:
		if z.has(k):
			return _zf(z, k, -1.0)
	return -1.0

func _zpos(z: Dictionary) -> Vector2:
	var p: Vector2 = run.player_pos()
	return Vector2(_zf(z, "x", p.x), _zf(z, "y", p.y))

func _hazard_list() -> Array:
	var out: Array = []
	for key in ["hazards", "mechanics_zones", "hazard_zones"]:
		var v = run.get(key)
		if v is Array and not v.is_empty():
			for it in v:
				if it is Dictionary:
					out.append(it)
			return out
	var mech = run.get("mechanics")
	if mech != null:
		for key in ["zones", "hazards"]:
			var v2 = mech.get(key)
			if v2 is Array:
				for it in v2:
					if it is Dictionary:
						out.append(it)
	return out

func _affix_color(t: Dictionary) -> Color:
	var s: String = String(t.get("elite_affix", "")) + String(t.get("name", "")) + String(t.get("id", ""))
	if s.contains("火") or s.contains("焰") or s.contains("灼"):
		return Color(0.95, 0.48, 0.24)
	if s.contains("毒") or s.contains("瘟"):
		return Color(0.55, 0.88, 0.38)
	if s.contains("雷") or s.contains("电"):
		return Color(0.92, 0.86, 0.35)
	if s.contains("冰") or s.contains("霜") or s.contains("寒"):
		return Color(0.55, 0.82, 0.98)
	if s.contains("甲") or s.contains("护") or s.contains("铁"):
		return Color(0.72, 0.76, 0.84)
	if s.contains("召唤") or s.contains("魂") or s.contains("灵"):
		return Color(0.76, 0.58, 0.95)
	if s.contains("疾") or s.contains("迅") or s.contains("风"):
		return Color(0.55, 0.92, 0.78)
	if s.contains("圣") or s.contains("光"):
		return Color(0.96, 0.90, 0.60)
	return Color(0.85, 0.30, 0.25)

func _draw_mechanics() -> void:
	var mech = run.get("mechanics")
	# 优先消费系统侧 RunMechanics.draw_data()：kind = band/circle/wall/prop/hazard/pickup/overlay/vision
	if mech != null and mech.has_method("draw_data"):
		var entries = mech.draw_data()
		if entries is Array:
			for e in entries:
				if e is Dictionary:
					_draw_mech_entry(e, mech)
			return
	for z in _hazard_list():
		var kind: String = String(z.get("kind", z.get("type", "")))
		match kind:
			"lightning", "thunder":
				_draw_lightning(z)
			"meteor", "meteor_fire":
				_draw_meteor(z)
			"wall", "wall_ring":
				_draw_wall(z)
			"glass", "glass_sea":
				_draw_glass(z)
			"band", "cooldown_band", "cooling":
				_draw_band(z)
			_:
				_draw_warning(z)
	# 也接受顶层单值字段，方便系统侧不经数组直接挂一个
	var wall = run.get("wall_ring")
	if wall is Dictionary:
		_draw_wall(wall)
	var glass = run.get("glass_sea")
	if glass is Dictionary:
		_draw_glass(glass)
	var mw = run.get("meteor_warning")
	if mw is Dictionary:
		_draw_meteor(mw)
	elif mw is Array:
		for it in mw:
			if it is Dictionary:
				_draw_meteor(it)

func _draw_mech_entry(e: Dictionary, mech) -> void:
	var kind: String = String(e.get("kind", ""))
	var mid: String = String(mech.get("id")) if mech != null else ""
	var p: Vector2 = Vector2(_zf(e, "x", 0.0), _zf(e, "y", 0.0))
	match kind:
		"band":
			_draw_band(e)
		"overlay":
			var oc := Color(String(e.get("color", "#8FC8E0")))
			var oa: float = clampf(_zf(e, "alpha", 0.10), 0.0, 0.6)
			draw_rect(Rect2(-20, -20, 700, 400), Color(oc.r, oc.g, oc.b, oa), true)
		"wall":
			_draw_sea_wall(p, e)
		"hazard":
			var prog: float = clampf(_zf(e, "progress", 0.0), 0.0, 1.0)
			var r: float = maxf(_zf(e, "r", 30.0), 8.0)
			var fake := { "x": p.x, "y": p.y, "r": r, "warn": 1.5, "left": (1.0 - prog) * 1.5 }
			if mid == "meteor_horde" or mid == "meteor":
				_draw_meteor(fake)
			elif mid in ["lightning_zones", "furnace_rings", "drought_fire", "abyss_vents", "plague_cycle"]:
				_draw_lightning(fake)
			else:
				_draw_warning(fake)
		"pickup":
			_draw_pickup_mark(p, e)
		"prop":
			_draw_prop(p, e)
		"circle":
			_draw_mech_circle(p, e, mech)
		"vision":
			pass
		_:
			_draw_warning({ "x": p.x, "y": p.y, "r": _zf(e, "r", 30.0) })

func _draw_mech_circle(p: Vector2, e: Dictionary, mech) -> void:
	var col := Color(String(e.get("color", "#C8D0D8")))
	var a: float = clampf(_zf(e, "alpha", 0.18), 0.0, 0.8)
	var r: float = maxf(_zf(e, "r", 20.0), 4.0)
	if String(e.get("color", "")).to_upper() == "#8A8378" and r >= 80.0:
		var coll: float = 0.0
		if mech != null:
			var flags = mech.get("flags")
			if flags is Dictionary and bool(flags.get("wall_down", false)):
				coll = 1.0
		_draw_wall({ "x": p.x, "y": p.y, "r": r, "collapse": coll })
		return
	draw_circle(p, r, Color(col.r, col.g, col.b, a), true)
	draw_circle(p, r, Color(col.r, col.g, col.b, minf(0.55, a * 2.6)), false, 1.2)
	var label: String = String(e.get("label", ""))
	if label != "":
		var f: Font = ThemeDB.fallback_font
		draw_string(f, p + Vector2(-r, -r - 3.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(col.r, col.g, col.b, 0.75))

func _draw_sea_wall(p: Vector2, e: Dictionary) -> void:
	var h: float = maxf(_zf(e, "h", 96.0), 8.0)
	var w: float = 12.0
	var col := Color(String(e.get("color", "#4F86B8")))
	draw_rect(Rect2(p.x - w * 0.5, p.y - h * 0.5, w, h), Color(col.r, col.g, col.b, 0.30), true)
	draw_rect(Rect2(p.x - w * 0.5, p.y - h * 0.5, w, h), Color(col.r, col.g, col.b, 0.80), false, 1.5)
	for i in range(int(h / 12.0)):
		var yy: float = p.y - h * 0.5 + 6.0 + float(i) * 12.0
		var wob: float = sin(run.elapsed * 3.0 + yy * 0.05) * 3.0
		draw_line(Vector2(p.x - w * 0.5, yy), Vector2(p.x + w * 0.5 + wob, yy), Color(0.80, 0.94, 1.0, 0.45), 1.0)

func _draw_pickup_mark(p: Vector2, e: Dictionary) -> void:
	var label: String = String(e.get("label", ""))
	var tex: Texture2D = _prop_tex()
	# 火炭：图集道具 + 跳动的橘红火芯（拾取物里唯一有专属贴图的一类）
	if label == "coal" and tex != null:
		var fl: float = 0.6 + 0.4 * sin(run.elapsed * 7.0 + p.x * 0.07)
		draw_texture_rect_region(tex, Rect2(p.x - 8.0, p.y - 8.0, 16.0, 16.0), SpriteBank.prop_rect("coal", 0))
		draw_circle(p + Vector2(0, -2.0), 1.6 + fl * 1.4, Color(1.0, 0.55, 0.18, 0.55 * fl))
		draw_circle(p + Vector2(0, -3.0), 2.4 + fl * 2.0, Color(1.0, 0.42, 0.12, 0.18 * fl))
		return
	var col := Color(String(e.get("color", "#F3E3A8")))
	var r: float = maxf(_zf(e, "r", 8.0), 3.0)
	var pulse: float = 0.5 + 0.5 * sin(run.elapsed * 4.0 + p.x * 0.1)
	draw_circle(p, r + 2.0 + pulse * 3.0, Color(col.r, col.g, col.b, 0.10), true)
	draw_circle(p, r * 0.55, Color(col.r, col.g, col.b, 0.85), true)
	var d: float = r * 1.2
	draw_polyline(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)]), Color(col.r, col.g, col.b, 0.55), 1.0)

func _draw_prop(p: Vector2, e: Dictionary) -> void:
	var col := Color(String(e.get("color", "#C8B48A")))
	var r: float = maxf(_zf(e, "r", 10.0), 3.0)
	var label: String = String(e.get("label", ""))
	draw_ellipse_shadow(p.x, p.y + r * 0.55, r * 0.7, r * 0.24)
	match label:
		"torch", "campfire":
			draw_rect(Rect2(p.x - 1.5, p.y - r * 0.2, 3.0, r * 0.8), Color(0.35, 0.28, 0.20), true)
			var flick: float = 0.6 + 0.4 * sin(run.elapsed * 9.0 + p.x)
			draw_circle(p + Vector2(0, -r * 0.55), r * 0.45 * flick, Color(0.98, 0.62, 0.22, 0.80))
			draw_circle(p + Vector2(0, -r * 0.55), r * 1.0 * flick, Color(0.98, 0.62, 0.22, 0.16))
		"pillar":
			draw_rect(Rect2(p.x - r * 0.35, p.y - r * 1.6, r * 0.7, r * 1.9), Color(col.r, col.g, col.b, 0.50), true)
			draw_rect(Rect2(p.x - r * 0.55, p.y - r * 1.8, r * 1.1, r * 0.35), Color(col.r, col.g, col.b, 0.70), true)
		"snake":
			var pts := PackedVector2Array()
			for i in range(7):
				pts.append(p + Vector2((float(i) - 3.0) * r * 0.35, sin(run.elapsed * 4.0 + float(i) * 0.9) * r * 0.3))
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.85), 2.0)
			draw_circle(pts[pts.size() - 1], r * 0.16, Color(0.95, 0.85, 0.35, 0.90))
		"door":
			draw_rect(Rect2(p.x - r * 0.6, p.y - r * 1.2, r * 1.2, r * 1.4), Color(col.r, col.g, col.b, 0.30), true)
			draw_rect(Rect2(p.x - r * 0.6, p.y - r * 1.2, r * 1.2, r * 1.4), Color(col.r, col.g, col.b, 0.80), false, 1.5)
			draw_circle(p + Vector2(0, -r * 0.45), r * 0.25, Color(0.98, 0.90, 0.60, 0.30))
		"lantern":
			draw_rect(Rect2(p.x - r * 0.2, p.y - r * 1.3, r * 0.4, r * 0.6), Color(0.35, 0.30, 0.24), true)
			draw_circle(p, r * 0.55, Color(0.98, 0.86, 0.48, 0.28))
			draw_circle(p, r * 0.30, Color(0.98, 0.90, 0.62, 0.85))
		"stone", "bread":
			draw_circle(p, r * 0.6, Color(col.r, col.g, col.b, 0.50))
			draw_circle(p, r * 0.6, Color(col.r, col.g, col.b, 0.85), false, 1.0)
		_:
			draw_rect(Rect2(p.x - r * 0.4, p.y - r * 0.4, r * 0.8, r * 0.8), Color(col.r, col.g, col.b, 0.55), true)
			draw_rect(Rect2(p.x - r * 0.4, p.y - r * 0.4, r * 0.8, r * 0.8), Color(col.r, col.g, col.b, 0.85), false, 1.0)

func _draw_warning(z: Dictionary) -> void:
	var p: Vector2 = _zpos(z)
	var r: float = maxf(_zf(z, "r", 30.0), 6.0)
	var left: float = _z_left(z)
	var warn: float = _zf(z, "warn", -1.0)
	var frac: float = 1.0
	if warn > 0.05 and left >= 0.0:
		frac = clampf(1.0 - left / warn, 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(run.elapsed * 7.0)
	draw_circle(p, r, Color(0.82, 0.22, 0.18, 0.10 + 0.10 * pulse), true)
	draw_circle(p, r, Color(0.94, 0.36, 0.28, 0.55), false, 1.5)
	if warn > 0.05:
		draw_arc(p, r - 1.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 28, Color(0.98, 0.66, 0.40, 0.85), 2.0)
	draw_circle(p, 2.0 + pulse * 1.6, Color(0.98, 0.58, 0.42, 0.75))

func _draw_lightning(z: Dictionary) -> void:
	var p: Vector2 = _zpos(z)
	var r: float = maxf(_zf(z, "r", 48.0), 10.0)
	var left: float = _z_left(z)
	var warn: float = maxf(_zf(z, "warn", 1.5), 0.1)
	var frac: float = clampf(1.0 - maxf(left, 0.0) / warn, 0.0, 1.0)
	draw_circle(p, r, Color(0.86, 0.82, 0.30, 0.07 + 0.10 * frac), true)
	draw_circle(p, r, Color(0.96, 0.90, 0.45, 0.65), false, 1.5)
	draw_arc(p, r - 2.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 30, Color(1.0, 0.95, 0.55, 0.9), 2.0)
	for k in range(3):
		var a: float = run.elapsed * 2.4 + TAU * float(k) / 3.0
		draw_line(p, p + Vector2(cos(a), sin(a)) * (r * 0.55), Color(0.95, 0.90, 0.50, 0.30), 1.0)
	if _z_is_struck(z, left):
		var pts := PackedVector2Array()
		for k in range(7):
			var yy: float = p.y - 110.0 + float(k) * 16.0
			var xx: float = p.x + sin(float(k) * 2.7 + p.x * 0.05) * 8.0
			pts.append(Vector2(xx, yy))
		draw_polyline(pts, Color(1.0, 0.98, 0.82, 0.95), 2.2)
		draw_circle(p, r * 0.75, Color(1.0, 0.96, 0.70, 0.35), true)
		draw_circle(p, r, Color(1.0, 0.98, 0.85, 0.9), false, 2.0)

func _draw_meteor(z: Dictionary) -> void:
	var p: Vector2 = _zpos(z)
	var r: float = maxf(_zf(z, "r", 40.0), 10.0)
	var left: float = _z_left(z)
	var warn: float = maxf(_zf(z, "warn", 1.5), 0.1)
	var frac: float = clampf(1.0 - maxf(left, 0.0) / warn, 0.0, 1.0)
	var hit: bool = left <= 0.0 or bool(z.get("impact", false))
	var hot: Color = Color(0.98, 0.52, 0.18) if not hit else Color(1.0, 0.86, 0.45)
	draw_circle(p, r, Color(hot.r, hot.g, hot.b, 0.10 + 0.12 * frac), true)
	draw_circle(p, r, Color(hot.r, hot.g, hot.b, 0.70), false, 1.5)
	# 旋转瞄准环
	var spin: float = run.elapsed * 2.0
	for k in range(4):
		var a: float = spin + TAU * float(k) / 4.0
		draw_line(p + Vector2(cos(a), sin(a)) * (r * 0.55), p + Vector2(cos(a), sin(a)) * r, Color(hot.r, hot.g, hot.b, 0.55), 1.2)
	draw_line(p + Vector2(-4, 0), p + Vector2(4, 0), Color(1.0, 0.8, 0.5, 0.7), 1.0)
	draw_line(p + Vector2(0, -4), p + Vector2(0, 4), Color(1.0, 0.8, 0.5, 0.7), 1.0)
	# 划落的陨星轨迹（预警时从右上角朝落点）
	var from: Vector2 = p + Vector2(r * 2.2, -r * 3.2)
	draw_line(from, p, Color(hot.r, hot.g, hot.b, 0.20 + 0.25 * frac), 2.0)
	draw_circle(from, 3.0 + 2.0 * frac, Color(hot.r, hot.g, hot.b, 0.65))
	if hit:
		draw_circle(p, r * 1.15, Color(1.0, 0.55, 0.20, 0.30), true)
		for k in range(6):
			var a2: float = TAU * float(k) / 6.0 + 0.3
			draw_line(p, p + Vector2(cos(a2), sin(a2)) * (r * 1.3), Color(1.0, 0.62, 0.25, 0.45), 1.5)

func _draw_wall(z: Dictionary) -> void:
	var p: Vector2 = _zpos(z)
	var r: float = maxf(_zf(z, "r", 160.0), 12.0)
	var coll: float = clampf(_zf(z, "collapse", 0.0), 0.0, 1.0)
	var stone: Color = Color(0.66, 0.60, 0.48, 0.55 + 0.3 * coll)
	if z.has("w") or z.has("h"):
		var w: float = _zf(z, "w", 64.0)
		var h: float = _zf(z, "h", 22.0)
		var rr: Rect2 = Rect2(p.x - w * 0.5, p.y - h * 0.5, w, h)
		draw_rect(rr, Color(0.45, 0.40, 0.30, 0.35), true)
		draw_rect(rr, stone, false, 3.0)
		for i in range(int(w / 8.0)):
			draw_line(Vector2(rr.position.x + 4.0 + float(i) * 8.0, rr.position.y), Vector2(rr.position.x + 4.0 + float(i) * 8.0, rr.position.y - 3.0), stone, 1.0)
		return
	# 圆形内城墙：三圈石带 + 垛口
	for k in range(3):
		draw_circle(p, r + float(k) * 1.6, Color(stone.r, stone.g, stone.b, stone.a * (1.0 - float(k) * 0.25)), false, 1.6)
	var teeth: int = 48
	for i in range(teeth):
		if i % 2 != 0:
			continue
		var a: float = TAU * float(i) / float(teeth)
		var d: Vector2 = Vector2(cos(a), sin(a))
		draw_line(p + d * (r - 2.0), p + d * (r - 6.0), stone, 1.5)
	if coll > 0.01:
		# 震塌：缺口与尘裂
		var gaps: int = int(round(coll * 5.0))
		for g in range(gaps):
			var ang: float = TAU * float(g) / maxf(float(gaps), 1.0) + 0.4
			var d2: Vector2 = Vector2(cos(ang), sin(ang))
			draw_line(p + d2 * (r - 10.0), p + d2 * (r + 14.0), Color(0.95, 0.82, 0.55, 0.55), 2.0)
			draw_circle(p + d2 * (r + 10.0), 4.0 + 6.0 * coll, Color(0.80, 0.70, 0.52, 0.20), true)

func _draw_glass(z: Dictionary) -> void:
	var active: bool = bool(z.get("active", true))
	if not active:
		return
	var p: Vector2 = _zpos(z)
	var r: float = maxf(_zf(z, "r", 520.0), 40.0)
	var prog: float = clampf(_zf(z, "progress", 1.0), 0.0, 1.0)
	var base := Color(0.52, 0.80, 0.88, 0.10 + 0.06 * prog)
	draw_circle(p, r, base, true)
	draw_circle(p, r, Color(0.72, 0.92, 0.96, 0.35), false, 1.5)
	# 掺火：玻璃裂纹里透出的暖光
	for i in range(14):
		var a: float = TAU * float(i) / 14.0 + 0.15
		var d: Vector2 = Vector2(cos(a), sin(a))
		draw_line(p + d * (r * 0.10), p + d * (r * 0.95), Color(0.70, 0.92, 0.96, 0.10 + 0.08 * prog), 1.0)
	for i in range(6):
		var a2: float = TAU * float(i) / 6.0 + run.elapsed * 0.15
		var d2: Vector2 = Vector2(cos(a2), sin(a2))
		var spark: float = 0.5 + 0.5 * sin(run.elapsed * 3.0 + float(i))
		draw_circle(p + d2 * (r * (0.35 + 0.1 * float(i % 3))), 1.2 + spark * 1.2, Color(1.0, 0.55, 0.22, 0.35 + 0.3 * spark))
	# 圣所光柱：z 里带 pillar 时画一道自上而下的光
	if bool(z.get("pillar", false)):
		var pw: float = maxf(r * 0.12, 10.0)
		draw_rect(Rect2(p.x - pw * 0.5, p.y - 240.0, pw, 240.0), Color(0.95, 0.90, 0.62, 0.10), true)
		draw_rect(Rect2(p.x - pw * 0.5, p.y - 240.0, pw, 240.0), Color(0.95, 0.90, 0.62, 0.18), false, 1.0)

func _draw_band(z: Dictionary) -> void:
	var p: Vector2 = _zpos(z)
	var frac: float = clampf(_zf(z, "frac", 0.0), 0.0, 1.0)
	var base := Color(String(z.get("color", "#DCAE62")))
	var alpha: float = clampf(_zf(z, "alpha", 0.16), 0.02, 0.7)
	var warm := Color(base.r, base.g, base.b, alpha)
	if z.has("w") or z.has("h"):
		var w: float = _zf(z, "w", 80.0)
		var h: float = _zf(z, "h", 16.0)
		var rr: Rect2 = Rect2(p.x - w * 0.5, p.y - h * 0.5, w, h)
		draw_rect(rr, warm, true)
		draw_rect(rr, Color(0.92, 0.78, 0.46, 0.55), false, 1.0)
		if frac > 0.0:
			draw_rect(Rect2(rr.position.x, rr.position.y, rr.size.x * frac, 2.0), Color(0.98, 0.88, 0.55, 0.9), true)
		return
	var r: float = maxf(_zf(z, "r", 150.0), 12.0)
	var width: float = maxf(_zf(z, "width", 7.0), 2.0)
	draw_arc(p, r, 0.0, TAU, 48, warm, width)
	draw_arc(p, r + width * 0.6, 0.0, TAU, 48, Color(0.92, 0.78, 0.46, 0.32), 1.0)
	if frac > 0.0:
		draw_arc(p, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 40, Color(0.98, 0.86, 0.52, 0.85), width + 1.0)

func _z_is_struck(z: Dictionary, left: float) -> bool:
	if bool(z.get("struck", false)) or bool(z.get("strike", false)):
		return true
	return left <= 0.0

func _draw_hazard_fx() -> void:
	# 命中瞬间的加色闪光层（画在敌人与弹幕之上，不遮挡 HUD）
	for z in _hazard_list():
		var kind: String = String(z.get("kind", z.get("type", "")))
		var flash: float = _zf(z, "flash", 0.0)
		var hit: bool = flash > 0.01 or bool(z.get("impact", false)) or bool(z.get("struck", false))
		if not hit:
			continue
		var p: Vector2 = _zpos(z)
		var r: float = maxf(_zf(z, "r", 30.0), 8.0)
		var k: float = clampf(flash, 0.0, 1.0) if flash > 0.01 else 0.8
		match kind:
			"lightning", "thunder":
				draw_circle(p, r * (0.8 + 0.5 * k), Color(1.0, 0.97, 0.72, 0.18 * k), true)
			"meteor", "meteor_fire":
				draw_circle(p, r * (0.9 + 0.6 * k), Color(1.0, 0.52, 0.16, 0.20 * k), true)
			"wall", "wall_ring":
				draw_circle(p, r + 8.0, Color(0.92, 0.82, 0.60, 0.10 * k), false, 3.0)
			_:
				draw_circle(p, r * (0.9 + 0.3 * k), Color(1.0, 0.60, 0.30, 0.12 * k), true)


# ============================================================ V3 精灵层 / 粒子 / 数字辅助

## 整数哈希：与旧地面哈希同族，纯确定性（不用 rng/randf，--sim 的确定性完全不受影响）
func _hash2(x: int, y: int) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663)
	h = h * 83492791
	h = h ^ (h >> 17)
	return h & 0x7FFFFFFFFFFF

## 相机可视的世界矩形：Camera2D 以玩家为中心，zoom 取当前值（1.35）
func _view_rect() -> Rect2:
	var c: Vector2 = run.player_pos()
	var z: float = 1.0
	var cam = run.get("cam")
	if cam is Camera2D:
		z = maxf((cam as Camera2D).zoom.x, 0.15)
	var half: Vector2 = VIEW * 0.5 / z
	return Rect2(c - half, half * 2.0)

## 图集取用：缺失一律返回 null，调用方全部有程序化回退（--sim 下 _draw 不跑，不会碰纹理）
func _enemy_tex() -> Texture2D:
	if _tex_enemy == null:
		_tex_enemy = SpriteBank.enemies()
	if _tex_enemy != null and _tex_enemy_flip == null and not _flip_tried_enemy:
		_flip_tried_enemy = true
		_tex_enemy_flip = _make_flip(_tex_enemy, SpriteBank.cell_of("enemies"))
	return _tex_enemy

func _witness_tex() -> Texture2D:
	if _tex_wit == null:
		_tex_wit = SpriteBank.witnesses()
	if _tex_wit != null and _tex_wit_flip == null and not _flip_tried_wit:
		_flip_tried_wit = true
		_tex_wit_flip = _make_flip(_tex_wit, SpriteBank.cell_of("witnesses"))
	return _tex_wit

func _prop_tex() -> Texture2D:
	if _tex_prop == null:
		_tex_prop = SpriteBank.props()
	return _tex_prop

## 水平镜像图集：一次性烘焙，避免每只敌人多一条 draw_set_transform（保住「一敌人一 draw」）。
## 注意要逐 32px 单元镜像、不能整图 flip_x：整图翻转会把 4 帧的列序也反过来（动画倒放）。
func _make_flip(tex: Texture2D, cell_size: int = 32) -> Texture2D:
	if tex == null:
		return null
	var src: Image = tex.get_image()
	if src == null:
		return null
	var img: Image = src.duplicate() as Image
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if src.is_compressed():
		src = src.duplicate() as Image
		src.decompress()
	var cell: int = cell_size
	var cols: int = src.get_width() / cell
	var rows: int = src.get_height() / cell
	for ry in range(rows):
		for cx in range(cols):
			var one: Image = src.get_region(Rect2i(cx * cell, ry * cell, cell, cell))
			if one.is_empty():
				continue
			one.flip_x()
			img.blit_rect(one, Rect2i(0, 0, cell, cell), Vector2i(cx * cell, ry * cell))
	return ImageTexture.create_from_image(img)

## 契约 v3 回退：flash 长度不足时用 hp 变化判定受击，自持一份 0.12s 的闪白衰减
func _sync_flash_fallback(e: EnemySim) -> void:
	var n: int = mini(e.count, e.hp.size())
	if _fb_flash.size() != n or _fb_hp.size() != n:
		_fb_flash.resize(n)
		_fb_hp.resize(n)
		for k in range(n):
			_fb_flash[k] = 0.0
			_fb_hp[k] = e.hp[k]
		return
	for k in range(n):
		if e.hp[k] < _fb_hp[k] - 0.0001:
			_fb_flash[k] = 0.12
		elif _fb_flash[k] > 0.0:
			_fb_flash[k] = maxf(_fb_flash[k] - _dt, 0.0)
		_fb_hp[k] = e.hp[k]

## 火把火星：沿轨道切线每帧甩 2 点，寿命 0.25s；抖动走整数哈希，不用 rng
func _update_sparks(delta: float) -> void:
	var i: int = _sparks.size() - 1
	while i >= 0:
		var s: Dictionary = _sparks[i]
		var life: float = float(s["life"]) - delta
		if life <= 0.0:
			_sparks.remove_at(i)
			i -= 1
			continue
		s["life"] = life
		s["x"] = float(s["x"]) + float(s["vx"]) * delta
		s["y"] = float(s["y"]) + float(s["vy"]) * delta
		s["vx"] = float(s["vx"]) * 0.94
		s["vy"] = float(s["vy"]) * 0.94 - 24.0 * delta
		i -= 1
	var weapons = run.get("weapons")
	var st = run.get("state")
	if weapons == null or st == null:
		return
	var ang: float = float(weapons.orbit_angle)
	var omega: float = 0.0
	if _orbit_prev_ok:
		omega = (ang - _orbit_prev_angle) / maxf(delta, 0.0001)
	_orbit_prev_angle = ang
	_orbit_prev_ok = true
	if absf(omega) < 0.01:
		return
	var pp: Vector2 = run.player_pos()
	for entry in st.weapons:
		if st.entry_behavior(entry) != "orbit":
			continue
		for pt in weapons.orbit_points(entry, pp):
			if _sparks.size() >= SPARK_MAX:
				return
			var rel := Vector2(float(pt["x"]) - pp.x, float(pt["y"]) - pp.y)
			var a: float = rel.angle()
			var tan := Vector2(-sin(a), cos(a)) * (omega * rel.length() * 0.55)
			_spark_n += 1
			var h: int = (_spark_n * 2654435761) & 0x7FFFFFFF
			var jx: float = float((h & 255) - 128) * 0.02
			var jy: float = float(((h >> 8) & 255) - 128) * 0.02
			for k in range(2):
				_sparks.append({ "x": float(pt["x"]), "y": float(pt["y"]), "vx": tan.x + jx + rel.x * 0.6, "vy": tan.y + jy + rel.y * 0.6, "life": SPARK_LIFE, "r": 1.4 + 0.6 * float(k) })

# ---------------------------------------------------------------- 击杀尸体 / 命中火花

## 本帧消失的敌人 → 留一具 0.20s 的尸体残影（缩放 1.0→0.72 + 淡出）。
## 死亡靠「上一帧在、这一帧不在」推导：run 的 deaths 队列在 _tick 内部就清空了，
## 渲染层读不到，也不该夺回它。3x3 格邻居容差吸收一帧内的正常位移。
func _harvest_corpses() -> void:
	if not _alive_prev.is_empty():
		var view: Rect2 = _view_rect().grow(-32.0)
		for k in _alive_prev.keys():
			if _alive_cur.has(k):
				continue
			var cell: Vector2i = k
			var shifted: bool = false
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if _alive_cur.has(cell + Vector2i(dx, dy)):
						shifted = true
						break
				if shifted:
					break
			if shifted:
				continue
			var v: Vector3 = _alive_prev[k]
			# 视口外的「消失」是镜头平移，不是死亡：别浪费尸体配额
			if not view.has_point(Vector2(v.x, v.y)):
				continue
			_add_corpse(v.x, v.y, int(v.z))
	# 双缓冲交换（复用 Dictionary 对象，避免每帧新建）
	var t: Dictionary = _alive_prev
	_alive_prev = _alive_cur
	_alive_cur = t
	_alive_cur.clear()


func _add_corpse(x: float, y: float, typ: int) -> void:
	if _corpses.size() >= CORPSE_MAX:
		_corpses.remove_at(0)
	_corpses.append({ "x": x, "y": y, "typ": typ, "t": CORPSE_LIFE })


func _tick_corpses(delta: float) -> void:
	var i: int = _corpses.size() - 1
	while i >= 0:
		var c: Dictionary = _corpses[i]
		var t: float = float(c["t"]) - delta
		if t <= 0.0:
			_corpses.remove_at(i)
		else:
			c["t"] = t
		i -= 1


func _draw_corpses() -> void:
	if _corpses.is_empty():
		return
	var e: EnemySim = run.enemies
	var tex: Texture2D = _enemy_tex()
	var sheet_rows: int = _sheet_rows(tex, "enemies")
	var cell: float = float(SpriteBank.cell_of("enemies"))
	var efeet: float = float(SpriteBank.feet_of("enemies"))
	for c in _corpses:
		var k: float = clampf(float(c["t"]) / CORPSE_LIFE, 0.0, 1.0)   # 1 → 0
		var typ: int = int(c["typ"])
		var row: int = -1
		if tex != null and typ >= 0 and typ < _row_cache.size():
			row = _row_cache[typ]
			if row >= sheet_rows:
				row = -1
		var x: float = float(c["x"])
		var y: float = float(c["y"])
		var rs: float = 6.0 * (0.72 + 0.28 * k)
		var a: float = 0.85 * k
		if row >= 0:
			var sc: float = 0.72 + 0.28 * k
			draw_texture_rect_region(
				tex,
				Rect2(roundf(x - cell * 0.5 * sc), roundf(y + 3.0 - efeet * sc), cell * sc, cell * sc),
				SpriteBank.frame_rect(row, 0, "enemies"),
				Color(1.0, 1.0, 1.0, a)
			)
		else:
			var base := Color("#8A7F6D")
			if e != null and typ >= 0 and typ < e.types.size():
				base = Color(String((e.types[typ] as Dictionary).get("color", "#8A7F6D")))
			draw_rect(Rect2(roundf(x - rs), roundf(y - rs), maxf(1.0, roundf(rs * 2.0)), maxf(1.0, roundf(rs * 2.0))), Color(base.r, base.g, base.b, a), true)


## 命中火花：从 dmg_events 的新增条目推导（只读事件数组，绝不 pop_front 别人的数据）。
## 事件数组有 200 上限、满了会从头部丢，所以「条数」不能单独当游标：再比一次尾条目的 x/amt。
func _update_hit_fx(delta: float) -> void:
	var i: int = _hit_fx.size() - 1
	while i >= 0:
		var h: Dictionary = _hit_fx[i]
		var life: float = float(h["life"]) - delta
		if life <= 0.0:
			_hit_fx.remove_at(i)
			i -= 1
			continue
		h["life"] = life
		h["x"] = float(h["x"]) + float(h["vx"]) * delta
		h["y"] = float(h["y"]) + float(h["vy"]) * delta
		h["vx"] = float(h["vx"]) * 0.88
		h["vy"] = float(h["vy"]) * 0.88 + 96.0 * delta
		i -= 1
	var arr = run.get("dmg_events")
	if not (arr is Array):
		return
	var evs: Array = arr
	var n: int = evs.size()
	var fresh: int = n - _dmg_seen
	if fresh < 0:
		fresh = 1
	if n > 0:
		var last = evs[n - 1]
		if last is Dictionary:
			var lx: float = float((last as Dictionary).get("x", 0.0))
			var la: float = float((last as Dictionary).get("amt", 0.0))
			if fresh <= 0 and (absf(lx - _dmg_tail_x) > 0.01 or absf(la - _dmg_tail_amt) > 0.01):
				fresh = 1
			_dmg_tail_x = lx
			_dmg_tail_amt = la
	_dmg_seen = n
	if fresh <= 0 or _hit_fx.size() >= HIT_FX_MAX:
		return
	var n0: int = maxi(0, n - mini(fresh, 8))
	for k in range(n0, n):
		var ev = evs[k]
		if not (ev is Dictionary):
			continue
		var d: Dictionary = ev
		_spawn_hit_fx(float(d.get("x", 0.0)), float(d.get("y", 0.0)) - 4.0, bool(d.get("crit", false)))


func _spawn_hit_fx(x: float, y: float, crit: bool) -> void:
	var base: Color = Color("#FFE9A8") if crit else Color("#F0D890")
	var cnt: int = 5 if crit else 3
	var h: int = _hash2(int(x), int(y))
	for k in range(cnt):
		if _hit_fx.size() >= HIT_FX_MAX:
			return
		var ang: float = TAU * float(k) / float(cnt) + float(h & 255) * 0.012
		var spd: float = (58.0 if crit else 42.0) * (0.72 + float((h >> (k * 3 + 2)) & 15) * 0.05)
		_hit_fx.append({
			"x": x, "y": y,
			"vx": cos(ang) * spd, "vy": sin(ang) * spd - 26.0,
			"life": HIT_FX_LIFE,
			"r": 1.9 if crit else 1.3,
			"c": base,
		})


func _draw_hit_fx() -> void:
	if _hit_fx.is_empty():
		return
	for h in _hit_fx:
		var a: float = clampf(float(h["life"]) / HIT_FX_LIFE, 0.0, 1.0)
		if a <= 0.02:
			continue
		var c: Color = h["c"]
		var px: float = roundf(float(h["x"]))
		var py: float = roundf(float(h["y"]))
		var rr: float = float(h["r"]) * (1.5 - a * 0.5)
		draw_circle(Vector2(px, py), rr, Color(c.r, c.g, c.b, 0.85 * a))
		draw_circle(Vector2(px, py), maxf(0.7, rr * 0.42), Color(1.0, 1.0, 0.94, 0.90 * a))


## 浮动伤害数字：读 run.dmg_events（x/y/amt/crit）+ run.dmg_life（剩余寿命）。
## 渲染层只读、绝不删除：run 的 _tick_dmg_events 按 dmg_life 自行过期（run.gd:1070 明确要求渲染层不删），
## 这里清空会让两条并行数组错位。同屏硬上限 40：只画最新的 40 条，其余自然被上限挡掉。
func _draw_damage_numbers() -> void:
	var evs = run.get("dmg_events")
	if not (evs is Array):
		return
	var arr: Array = evs
	var n: int = arr.size()
	if n <= 0:
		return
	var lf: PackedFloat32Array = PackedFloat32Array()
	var lives = run.get("dmg_life")
	if lives is PackedFloat32Array:
		lf = lives
	var has_life: bool = lf.size() >= n
	var f: Font = ThemeDB.fallback_font
	var i0: int = maxi(0, n - DMG_MAX)
	for i in range(i0, n):
		var e = arr[i]
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var amt: float = float(d.get("amt", 0.0))
		if amt < 1.0:
			continue
		# 没有寿命数组时按中段 alpha 画（不淡出，但也不会突然消失）
		var a: float = 0.6
		if has_life:
			a = clampf(lf[i] / DMG_LIFE, 0.0, 1.0)
		if a <= 0.02:
			continue
		var k: float = 1.0 - a
		var crit: bool = bool(d.get("crit", false))
		# 暴击：更大号更亮的金字（14 vs 8）+ 更重的描边，一眼能和普通伤害分开
		var fs: int = 14 if crit else 8
		var txt: String = str(int(round(amt)))
		var col: Color = Color("#FFD98A") if crit else Color("#F2E3B8")
		var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var rise: float = 20.0 if crit else 16.0
		var x: float = roundf(float(d.get("x", 0.0)) - w * 0.5)
		var y: float = roundf(float(d.get("y", 0.0)) - 8.0 - k * rise)
		if crit:
			# 暴击落点再加一圈金晕，配合更大的字号
			draw_circle(Vector2(x + w * 0.5, y - fs * 0.35), fs * 0.72, Color(1.0, 0.86, 0.42, 0.10 * a))
			draw_string(f, Vector2(x + 1.0, y + 1.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.34, 0.10, 0.02, 0.55 * a))
			draw_string(f, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, a))
		else:
			draw_string(f, Vector2(x + 1.0, y + 1.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.45 * a))
			draw_string(f, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, a))

## 地面银币：run.ground_coins = [{x, y, v, t}]，渲染层只读不写
func _draw_ground_coins() -> void:
	var raw = run.get("ground_coins")
	if not (raw is Array):
		return
	var arr: Array = raw
	if arr.is_empty():
		return
	var tex: Texture2D = _prop_tex()
	var view: Rect2 = _view_rect().grow(24.0)
	var elapsed: float = run.elapsed
	for c in arr:
		if not (c is Dictionary):
			continue
		var d: Dictionary = c
		var cx: float = float(d.get("x", 0.0))
		var cy: float = float(d.get("y", 0.0))
		if cx < view.position.x or cx > view.end.x or cy < view.position.y or cy > view.end.y:
			continue
		var bob: float = sin(elapsed * 3.2 + cx * 0.02) * 0.8
		if tex != null:
			draw_texture_rect_region(tex, Rect2(cx - 8.0, cy - 8.0 + bob, 16.0, 16.0), SpriteBank.prop_rect("coin", 0))
		else:
			draw_circle(Vector2(cx, cy), 3.0, Color("#D8D2C0"))
		var spark: float = 0.5 + 0.5 * sin(elapsed * 6.0 + cy * 0.05)
		draw_circle(Vector2(cx + 3.0, cy - 3.0 + bob), 0.9 + spark * 0.7, Color(1.0, 0.98, 0.86, 0.50))
