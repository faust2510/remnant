extends Node2D
## 单局流程：以拉谷。把模拟层接到渲染层与 UI 层，负责刷怪、掉落、祭坛、BOSS。

const DEFAULT_CHARACTER := "david"
const DEFAULT_STAGE := "elah_valley"
const VIEW := Vector2(640, 360)

var character_id: String = DEFAULT_CHARACTER
var stage_id: String = DEFAULT_STAGE
var stage_speed: float = 1.0
var stage_coin: float = 1.0
var stage_cd: float = 1.0
var seal: int = 1
var seal_override: int = 0
var no_meta: bool = false
var shot_end: bool = false
var seal_hp: float = 1.0
var seal_dmg: float = 1.0
var seal_rate: float = 1.0
var seal_ramp: float = 0.0
var reward: int = 0
var save_run: bool = false
var state: GameState
var enemies: EnemySim
var shots: ProjectileSim
var weapons: WeaponRunner
var stage: Dictionary

var world: WorldRenderer
var hud: HUD
var chooser: Chooser
var cam: Camera2D

var player: Vector2 = Vector2.ZERO
var player_hp: float = 100.0
var player_max_hp: float = 100.0
var aim_dir: Vector2 = Vector2.ZERO
var dash_iframe: float = 0.0
var dash_cd: float = 0.0
var dash_time: float = 0.0
var dash_dir: Vector2 = Vector2.RIGHT
var hit_cd: float = 0.0

var gems: Array = []
var altars: Array = []
var active_fx: Array = []
# ---- 局内系统（第 2 波）----
var stat_patch: RunStatPatch
var mechanics: RunMechanics
var rewards: RunRewards
var covenants: RunCovenants
var achievements: RunAchievements
var vision_radius: float = 0.0
var light_t: float = 0.0
var magnet_t: float = 0.0
var freeze_t: float = 0.0
var mech_shield: bool = false
var damage_taken_total: float = 0.0
## 伤害来源统计（sim 调平衡用）：来源 → 累计原始伤害
var dmg_by_src: Dictionary = {}
var elite_kills_total: int = 0
var armor_gained: int = 0
var watch_count: int = 0
var dashes_used: int = 0
var ach_flags: Dictionary = {}
var bonus_silver: int = 0
var meta_silver_bonus: int = 0
var codex_unlocked: bool = false
var fast_forward_available: bool = false
var endless_allowed: bool = false
var endless_continued: bool = false
var reroll_plus: bool = false
var chest_double: bool = false
var run_duration: float = 0.0
var boss_ai: RefCounted = null
var boss_ai_script: Script = null
var elapsed: float = 0.0
var spawn_acc: float = 0.0
var elite_done: int = 0
var boss_spawned: bool = false
var boss_index: int = -1
var perfect_flash: float = 0.0
var shake: float = 0.0
var last_move_dir: Vector2 = Vector2.ZERO
var toast_text: String = ""
var toast_t: float = 0.0
var hurt_flash: float = 0.0
var level_flash: float = 0.0
var sfx: Sfx
var watcher_t: float = 0.0
var move_acc: float = 0.0
var recycle_acc: float = 0.0
var modal: bool = false
var over: bool = false
var won: bool = false
var pending_levels: int = 0
var chooser_mode: String = ""
var rerolls: int = 2
var current_options: Array = []
var altar_done: int = 0
const ALTAR_TIMES := [180.0, 360.0, 540.0]
var autopilot: bool = false
var sim_mode: bool = false
var god: bool = false
var shot_mode: bool = false
var shot_path: String = "/tmp/remnant_shot.png"
var shot_at: float = 6.0
var sim_speed: int = 1
var seed_override: int = 0
var sim_log: Array = []
var shot_frames: int = 0
var shot_wait: int = 0
var shot_fast: int = 1
var shot_modal: bool = false

const CAM_ZOOM := 1.35
var rng := RandomNumberGenerator.new()

# ---------------------------------------------------------------- 初始化

func _ready() -> void:
	if RunCfg.character_id != "":
		character_id = RunCfg.character_id
	if RunCfg.stage_id != "":
		stage_id = RunCfg.stage_id
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a == "--sim":
			sim_mode = true
			autopilot = true
			sim_speed = 60
		elif a == "--sim-god":
			god = true
			sim_mode = true
			autopilot = true
		elif a == "--shot":
			shot_mode = true
			autopilot = true
			god = true
		elif a.begins_with("--shot-at="):
			shot_at = float(a.substr(10))
		elif a.begins_with("--shot-path="):
			shot_path = a.substr(12)
		elif a.begins_with("--sim-speed="):
			sim_speed = int(a.substr(12))
		elif a.begins_with("--seed="):
			seed_override = int(a.substr(7))
		elif a.begins_with("--shot-fast="):
			shot_fast = int(a.substr(12))
		elif a == "--shot-modal":
			shot_modal = true
		elif a.begins_with("--char="):
			character_id = a.substr(7)
		elif a == "--save":
			save_run = true
		elif a.begins_with("--seal="):
			seal_override = clampi(int(a.substr(7)), 1, 21)
		elif a.begins_with("--stage="):
			stage_id = a.substr(8)
		elif a == "--no-meta":
			no_meta = true
		elif a == "--shot-end":
			shot_end = true
			sim_mode = true
			autopilot = true
			sim_speed = maxi(sim_speed, 90)
			shot_wait = 8
	# --shot-fast 没配 --shot-at 时，把目标时间当成快进的终点（否则快进到 6 秒就拍照）
	if shot_fast > 1 and shot_at <= 6.0:
		shot_at = float(shot_fast)
	rng.seed = 20261116 if seed_override == 0 else seed_override
	stage = GameData.stages_by_id.get(stage_id, {})
	if stage.is_empty():
		# 阶段名写错时绝不静默回落：测试与玩家都该立刻看到（否则会拿以拉谷的数据冒充别章）
		print("[run] WARN stage '%s' not found, fallback to %s" % [stage_id, DEFAULT_STAGE])
		push_warning("stage not found: " + stage_id)
		stage_id = DEFAULT_STAGE
		stage = GameData.stages_by_id.get(DEFAULT_STAGE, {})
	var mods: Dictionary = stage.get("mods", {})
	stage_speed = float(mods.get("enemy_speed", 1.0))
	stage_coin = float(mods.get("shillings", 1.0))
	stage_cd = float(mods.get("cooldown", 1.0))
	seal = seal_override if seal_override > 0 else clampi(Meta.effective_tier(), 1, 21)
	# 1–7 印与旧公式逐位一致；8–21 阶走 store.json 的同斜率 API，数值连续（七印封印解锁后可用）
	seal_hp = Meta.tier_enemy_hp(seal)
	seal_dmg = Meta.tier_enemy_dmg(seal)
	# 前 3 分钟渐入：高印考的是构筑成型后的抗压，不是 0:00 一发打不死小兵断掉滚雪球
	seal_ramp = 1.0
	seal_rate = Meta.tier_spawn_rate(seal)
	state = GameState.new()
	state.setup(character_id, {} if no_meta else Meta.bonus(), [] if no_meta else Meta.relics)
	state.stage_cd = stage_cd
	state.recompute()

	enemies = EnemySim.new()
	var defs: Array = []
	for k in GameData.enemies.keys():
		defs.append(GameData.enemies[k])
	# BOSS 定义自 v2 起独立在 data/bosses.json，同样注册为敌人类型，stage.boss 才能按 id 生成
	for b in GameData.bosses:
		defs.append(b)
	enemies.setup(defs)

	shots = ProjectileSim.new()
	shots.setup()

	weapons = WeaponRunner.new()
	weapons.setup(state, enemies, shots)
	# 无头模拟必须完全可复现：敌人与武器各自用主 rng 派生的种子
	enemies.rng.seed = rng.randi()
	weapons.rng.seed = rng.randi()

	player = Vector2.ZERO
	player_max_hp = float(state.stats.get("max_hp", 100.0))
	player_hp = player_max_hp

	cam = Camera2D.new()
	cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
	add_child(cam)
	cam.make_current()

	sfx = Sfx.new()
	sfx.enabled = not sim_mode
	add_child(sfx)

	world = WorldRenderer.new()
	world.run = self
	add_child(world)

	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	hud = HUD.new()
	hud.run = self
	ui.add_child(hud)
	if sim_mode and not shot_end:
		world.visible = false
		hud.visible = false

	var ui2 := CanvasLayer.new()
	ui2.layer = 20
	add_child(ui2)
	chooser = Chooser.new()
	chooser.picked.connect(_on_picked)
	chooser.reroll_requested.connect(_on_reroll)
	ui2.add_child(chooser)

	# ---- 局内系统接线：属性补丁 → 机关 / 奖励 / 约 / 成就 ----
	run_duration = float(stage.get("duration", 780.0))
	stat_patch = RunStatPatch.new()
	stat_patch.setup(state)
	mechanics = RunMechanics.new()
	mechanics.setup(self)
	rewards = RunRewards.new()
	rewards.setup(self)
	covenants = RunCovenants.new()
	covenants.setup(self)
	achievements = RunAchievements.new()
	achievements.setup(self)
	_apply_relics()
	_sync_max_hp()

func player_pos() -> Vector2:
	return player

func _process(delta: float) -> void:
	var d: float = minf(delta, 0.05)
	if sim_mode:
		if over:
			if shot_end:
				shot_wait -= 1
				_update_ui_only(d)
				if shot_wait <= 0:
					_save_shot()
			return
		for k in range(sim_speed):
			if over:
				break
			if modal:
				_sim_choose()
				continue
			step(1.0 / 60.0)
		_sim_log()
		if over and not shot_end:
			_sim_report()
		return
	# 截图前先快进到目标时间附近，避免为了看一眼 5 分钟的画面真的等 5 分钟
	if shot_mode and shot_fast > 1 and elapsed < shot_at - 6.0:
		for k in range(shot_fast):
			if over or elapsed >= shot_at - 6.0:
				break
			if modal:
				_sim_choose()
				continue
			step(1.0 / 60.0)
		if over:
			_finish(won)
		return
	if shot_mode and shot_wait > 0:
		shot_wait -= 1
		_update_ui_only(d)
		if shot_wait == 0:
			_save_shot()
		return
	if over or modal:
		if shot_mode and shot_modal and modal and elapsed >= shot_at and shot_wait <= 0:
			shot_wait = 3
			return
		if modal and (sim_mode or shot_mode):
			_sim_choose()
		_update_ui_only(d)
		return
	step(d)
	shot_frames += 1
	var shot_ready: bool = modal if shot_modal else not modal
	if shot_mode and shot_ready and (elapsed >= shot_at or shot_frames > 40000):
		shot_wait = 3

func _save_shot() -> void:
	RenderingServer.force_draw(false)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("[shot] no image (headless?) for ", shot_path)
		get_tree().quit()
		return
	img.save_png(shot_path)
	print("[shot] saved ", shot_path, " ", img.get_width(), "x", img.get_height())
	get_tree().quit()

func _update_ui_only(d: float) -> void:
	perfect_flash = maxf(perfect_flash - d, 0.0)
	if Input.is_action_just_pressed("pause") and over:
		get_tree().reload_current_scene()

# ---------------------------------------------------------------- 主循环

func step(delta: float) -> void:
	elapsed += delta
	perfect_flash = maxf(perfect_flash - delta, 0.0)
	hit_cd = maxf(hit_cd - delta, 0.0)
	toast_t = maxf(toast_t - delta, 0.0)
	shake = maxf(shake - delta * 26.0, 0.0)
	hurt_flash = maxf(hurt_flash - delta * 3.2, 0.0)
	level_flash = maxf(level_flash - delta * 2.4, 0.0)
	dash_cd = maxf(dash_cd - delta, 0.0)
	dash_iframe = maxf(dash_iframe - delta, 0.0)
	dash_time = maxf(dash_time - delta, 0.0)
	if watcher_t > 0.0:
		watcher_t -= delta
		enemies.speed_scale = 0.3
		if watcher_t <= 0.0:
			enemies.speed_scale = 1.0

	# 日头停留之约：完美闪避/升级冻结全场 2.2s
	if freeze_t > 0.0:
		freeze_t = maxf(freeze_t - delta, 0.0)
		enemies.speed_scale = 0.0
	elif watcher_t <= 0.0:
		enemies.speed_scale = 1.0

	seal_ramp = clampf(elapsed / 180.0, 0.25, 1.0)
	enemies.hp_scale = (1.0 + pow(maxf(elapsed, 0.0) / 60.0, 0.85) * 0.175) * (1.0 + (seal_hp - 1.0) * seal_ramp)

	# 局内系统：机关 / 奖励 / 约 / 属性补丁。放在武器结算之前，本帧拿到的 buff 立刻生效。
	magnet_t = maxf(magnet_t - delta, 0.0)
	if mechanics != null:
		mechanics.tick(delta)
	if rewards != null:
		rewards.tick(delta)
	if covenants != null:
		covenants.tick(delta)
	if stat_patch != null:
		stat_patch.apply()
	_sync_max_hp()
	# 持续治疗（圣烟、铜蛇、船尾灯笼、更美之约等）
	if float(state.stats.get("heal_per_sec", 0.0)) > 0.0 and player_hp > 0.0 and player_hp < player_max_hp:
		player_hp = minf(player_hp + float(state.stats["heal_per_sec"]) * delta, player_max_hp)

	_move_player(delta)
	enemies.rebuild_grid()

	weapons.tick(delta, player, aim_dir)
	if weapons.heal_pending > 0.0:
		# 金香坛（圣烟）持续治疗：只在未满血时结算
		if player_hp < player_max_hp:
			player_hp = minf(player_hp + weapons.heal_pending, player_max_hp)
		weapons.heal_pending = 0.0
	shots.update(delta, enemies, Callable(), player)

	var contact: float = enemies.update(delta, player, float(state.stats.get("dot_mult", 1.0)))
	if contact > 0.0:
		if dash_iframe > 0.0:
			_trigger_watcher()
		elif hit_cd <= 0.0:
			# 圣典 13 章门禁：普通接触伤害上限 10，BOSS 在场放宽到 18；无敌帧统一 0.60s
			var contact_cap: float = 18.0 if boss_index >= 0 else 10.0
			_take_damage(minf(contact, contact_cap) * seal_dmg, true, "contact")
	enemies.rebuild_grid()

	_drain_enemy_shots()
	var shot_dmg: float = shots.player_hit_damage(player.x, player.y, 6.0)
	if shot_dmg > 0.0:
		if dash_iframe > 0.0:
			_trigger_watcher()
		elif hit_cd <= 0.0:
			_take_damage(minf(shot_dmg, 18.0) * seal_dmg, true, "shot")

	_drain_fx(delta)
	_consume_deaths()
	_pickup_gems(delta)
	_check_ascend()
	_spawner(delta)
	_recycle_far(delta)
	_altars_and_events()
	_recompute_boss()
	_tick_boss_ai(delta)
	if not over and elapsed >= run_duration:
		# BOSS 一旦登场，计时胜利作废：必须把它打倒（否则「撑满时长」等于白拿通关）。
		# 留 150 秒宽限，打不动就判负，避免模拟卡死在打不死的 BOSS 上。
		if boss_spawned and boss_index >= 0:
			if elapsed >= run_duration + 150.0:
				_finish(false)
		else:
			_finish(true)

func _move_player(delta: float) -> void:
	var v := Vector2.ZERO
	if autopilot:
		v = _autopilot_dir()
	else:
		v.x = Input.get_axis("move_left", "move_right")
		v.y = Input.get_axis("move_up", "move_down")
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() > 0.05:
		last_move_dir = v.normalized()

	var speed: float = float(state.stats.get("speed", 72.0))
	var before: Vector2 = player
	if dash_time > 0.0:
		player += dash_dir * speed * 3.2 * delta
	else:
		player += v * speed * delta

	# 约书亚：绕城七日 —— 每移动一定距离放一次全向震荡波
	var step_perk: float = float(state.perf("move_shockwave", 0.0))
	if step_perk > 0.0:
		move_acc += player.distance_to(before)
		if move_acc >= step_perk:
			move_acc = 0.0
			var dmg: float = 19.0 * float(state.stats.get("damage_mult", 1.0))
			enemies.damage_in_circle(player.x, player.y, 104.0, dmg, "", 0.0, 46.0)
			active_fx.append({ "kind": "nova", "x": player.x, "y": player.y, "r": 104.0, "life": 0.45, "color": Color("#E9D9A0") })
			if not sim_mode:
				shake = maxf(shake, 1.6)

	if autopilot:
		var want_dash: bool = dash_cd <= 0.0 and _threat_count(52.0) >= 2
		var ddir: Vector2 = v.normalized() if v.length() > 0.01 else Vector2.RIGHT
		if not want_dash and dash_cd <= 0.0:
			# 躲弹闪避：有敌弹在 52px 内且正朝自己飞来时，往弹道侧面闪
			for pi in range(shots.count):
				if int(shots.friendly[pi]) != 0:
					continue
				var bdx: float = shots.px[pi] - player.x
				var bdy: float = shots.py[pi] - player.y
				var bd2: float = bdx * bdx + bdy * bdy
				if bd2 > 2704.0:
					continue
				if shots.vx[pi] * bdx + shots.vy[pi] * bdy >= 0.0:
					continue
				var blen: float = maxf(sqrt(shots.vx[pi] * shots.vx[pi] + shots.vy[pi] * shots.vy[pi]), 1.0)
				var perp := Vector2(-shots.vy[pi] / blen, shots.vx[pi] / blen)
				if perp.dot(player - Vector2(shots.px[pi], shots.py[pi])) < 0.0:
					perp = -perp
				ddir = perp
				want_dash = true
				break
		if want_dash:
			dash_dir = ddir
			dash_time = 0.18
			dash_iframe = 0.15
			dash_cd = 0.9
			dashes_used += 1
			sfx.play("dash", -8.0, 1.0, 0.2)
	elif Input.is_action_just_pressed("dash") and dash_cd <= 0.0:
		pass
	if not autopilot:
		if Input.is_action_just_pressed("dash") and dash_cd <= 0.0:
			dash_dir = v.normalized() if v.length() > 0.01 else Vector2.RIGHT
			dash_time = 0.18
			dash_iframe = 0.15
			dash_cd = 0.9
			dashes_used += 1
			sfx.play("dash", -6.0, 1.0, 0.2)
		if Input.is_action_pressed("aim"):
			aim_dir = (get_global_mouse_position() - player).normalized()
			if aim_dir.length() < 0.1:
				aim_dir = Vector2.ZERO
		else:
			aim_dir = Vector2.ZERO

	cam.position = player
	if shake > 0.01:
		cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	else:
		cam.offset = Vector2.ZERO

func _threat_count(r: float) -> int:
	return enemies.query(player.x, player.y, r)

func _autopilot_dir() -> Vector2:
	var goal: Vector2 = _altar_target()
	if goal != Vector2.INF:
		return (goal - player).normalized()
	var best := Vector2.RIGHT
	var best_d: float = -1.0
	# 宝石坐标只扫一次（原来在 8 个方向里各扫一遍，场上几百颗宝石时是 O(8G)）
	var gx: PackedFloat32Array = PackedFloat32Array()
	var gy: PackedFloat32Array = PackedFloat32Array()
	for g in gems:
		var gp0 := Vector2(float(g["x"]), float(g["y"]))
		if player.distance_squared_to(gp0) < 57600.0:
			gx.append(gp0.x)
			gy.append(gp0.y)
	# 机关危险点：即将落下的雷击/陨星/火柱圈，以及苦水这类常驻伤害池
	var hzp: Array = []
	if mechanics != null:
		hzp = mechanics.hazards
	var pool: Array = []
	if mechanics != null:
		for s in mechanics.spots:
			var k: String = String(s.get("kind", ""))
			if k == "bitter" or k == "water_altar" or k == "fire":
				pool.append(s)
	# 红海水墙：用墙的实际位置当阈值（合拢时 210→140，写死 150 会在合拢期被夹进伤害带）
	var wall_x: float = 0.0
	if mechanics != null and String(stage.get("mechanic_id", "")) == "sea_walls":
		for s3 in mechanics.spots:
			if String(s3.get("kind", "")) == "wall":
				var ax: float = absf(float(s3["x"]))
				if wall_x <= 0.0 or ax < wall_x:
					wall_x = ax
	# 可躲的「安全区」（鱼腹的蓖麻树荫等）：站在里面才不掉血
	var shades: Array = []
	if mechanics != null:
		for s4 in mechanics.spots:
			if String(s4.get("kind", "")) == "shade":
				shades.append(s4)
	# 敌弹预筛：只收 210px 内的敌弹，避免 8 个方向 × 1400 发全扫
	var bx: PackedFloat32Array = PackedFloat32Array()
	var by: PackedFloat32Array = PackedFloat32Array()
	var bvx: PackedFloat32Array = PackedFloat32Array()
	var bvy: PackedFloat32Array = PackedFloat32Array()
	for pi in range(shots.count):
		if int(shots.friendly[pi]) != 0:
			continue
		var bpx: float = shots.px[pi]
		var bpy: float = shots.py[pi]
		if absf(bpx - player.x) < 210.0 and absf(bpy - player.y) < 210.0:
			bx.append(bpx); by.append(bpy)
			bvx.append(shots.vx[pi]); bvy.append(shots.vy[pi])
	for k in range(8):
		var a: float = TAU * float(k) / 8.0
		var p: Vector2 = player + Vector2.from_angle(a) * 70.0
		var d: float = 0.0
		var n: int = enemies.query(p.x, p.y, 90.0)
		for q in range(n):
			var i: int = enemies.query_buf[q]
			d += 1.0 / maxf(Vector2(enemies.px[i], enemies.py[i]).distance_to(p), 4.0)
		# 顺路捞经验：靠近宝石的方向有额外吸引力（200px 内才计入）
		for gi in range(gx.size()):
			var gd: float = Vector2(gx[gi], gy[gi]).distance_to(p)
			if gd < 200.0:
				d -= 0.9 / maxf(gd, 10.0)
		# 躲机关：宁可绕远，也别站在要落下的圈里
		for h in hzp:
			var hp := Vector2(float(h["x"]), float(h["y"]))
			var hr: float = float(h.get("r", 40.0)) + 20.0
			var hd: float = hp.distance_to(p)
			if hd < hr:
				d += 60.0 * (1.0 - hd / hr)
		for s2 in pool:
			var sp := Vector2(float(s2["x"]), float(s2["y"]))
			var sr: float = float(s2.get("r", 50.0)) + 12.0
			var sd: float = sp.distance_to(p)
			if sd < sr:
				d += 24.0 * (1.0 - sd / sr)
		# 躲弹：现在位置 + 0.25 秒后预测位置都算一遍（弹速 150–220，只看当下位置等于只躲已经过去的弹）
		for bi in range(bx.size()):
			var bfvx: float = bvx[bi]
			var bfvy: float = bvy[bi]
			for kk in range(2):
				var lead: float = 0.0 if kk == 0 else 0.25
				var px2: float = bx[bi] + bfvx * lead
				var py2: float = by[bi] + bfvy * lead
				var dbx: float = p.x - px2
				var dby: float = p.y - py2
				var bdist: float = sqrt(dbx * dbx + dby * dby)
				# 判定圈 84 做平方加权：弹速快，半径太小时自动驾驶等于没躲
				if bdist < 84.0 and (bfvx * dbx + bfvy * dby) > -20.0:
					var wgt: float = 40.0 if kk == 0 else 26.0
					d += wgt * (1.0 - bdist / 84.0) * (1.0 - bdist / 84.0)
		# 红海水墙：擦墙每秒 10 点 DoT 并把人夹向中心，逼近墙面时用强权重推回
		if wall_x > 0.0 and absf(p.x) > wall_x - 46.0:
			d += (absf(p.x) - (wall_x - 46.0)) * 3.0
		# 烈日/鱼腹：离安全区越远越该往回走（每秒 1 点无上限 DoT，靠走位规避）
		for s5 in shades:
			var sc := Vector2(float(s5["x"]), float(s5["y"]))
			var srad: float = float(s5.get("r", 90.0))
			var sdist: float = sc.distance_to(p)
			if sdist > srad * 0.7:
				d += (sdist - srad * 0.7) * 0.06
		if best_d < 0.0 or d < best_d:
			best_d = d
			best = Vector2.from_angle(a)
	return best

func _take_damage(amount: float, respect_cd: bool = true, src: String = "hit") -> void:
	if god or over:
		return
	# 统一无敌帧：机关/宝箱/齐射等所有离散伤害都在这里被 0.6 秒一次的上限收口
	if respect_cd and hit_cd > 0.0:
		return
	dmg_by_src[src] = float(dmg_by_src.get(src, 0.0)) + amount
	# 非拉铁非的免死盾（七灯台祝福）：抵挡一次伤害
	if mech_shield:
		mech_shield = false
		hit_cd = 0.60
		active_fx.append({ "kind": "nova", "x": player.x, "y": player.y, "r": 80.0, "life": 0.45, "color": Color("#BFD4FF") })
		sfx.play("pickup", -6.0, 1.25, 0.08)
		return
	var mult: float = state.incoming_damage_mult()
	var real: float = amount * mult
	player_hp -= real
	damage_taken_total += maxf(real, 0.0)
	hit_cd = 0.60
	active_fx.append({ "kind": "spark", "x": player.x, "y": player.y, "r": 6.0, "life": 0.3 })
	shake = maxf(shake, 4.5)
	hurt_flash = 1.0

	# 摩西：分开红海 —— 受击时把周围敌人推开
	var push: float = float(state.perf("hit_push", 0.0))
	if push > 0.0:
		var near: PackedInt32Array = enemies.indices_in_circle(player.x, player.y, 112.0)
		for idx in near:
			var dx: float = enemies.px[idx] - player.x
			var dy: float = enemies.py[idx] - player.y
			var l: float = maxf(sqrt(dx * dx + dy * dy), 1.0)
			enemies.knockback(idx, dx / l, dy / l, push)
		active_fx.append({ "kind": "nova", "x": player.x, "y": player.y, "r": 96.0, "life": 0.4, "color": Color("#8FC8E0") })
	# 肉心代石心之约：受伤时反弹（掉血 ×35 + 护甲 ×10）
	if bool(state.get_meta("covenant_reflect", false)):
		var refl: float = real * 35.0 + float(state.stats.get("armor", 0.0)) * 10.0
		enemies.damage_in_circle(player.x, player.y, 240.0, refl, "tremor", 0.0, 80.0)
		active_fx.append({ "kind": "nova", "x": player.x, "y": player.y, "r": 240.0, "life": 0.35, "color": Color("#E0A0A0") })
	sfx.play("hurt", -3.0, randf_range(0.94, 1.06), 0.12)
	if player_hp <= 0.0:
		player_hp = 0.0
		_finish(false)

func _trigger_watcher() -> void:
	if watcher_t > 0.0:
		return
	watcher_t = 1.5
	perfect_flash = 1.2
	watch_count += 1
	if watch_count >= 5:
		ach_flags["perfect_dodge_5"] = true
	if bool(state.get_meta("covenant_sun_stand", false)):
		freeze_t = 2.2
	active_fx.append({ "kind": "nova", "x": player.x, "y": player.y, "r": 160.0, "life": 0.6, "color": Color("#BFD4FF") })

## 无头模拟用的自动选择器：按「先凑满武器 → 堆满级 → 补祝圣所需被动 → 有火炭就祝圣」的顺序贪心挑选。
func _sim_choose() -> void:
	if current_options.is_empty():
		modal = false
		chooser_mode = ""
		return
	if chooser_mode == "altar" or chooser_mode == "covenant":
		_on_picked(0)
		return
	var best_i: int = 0
	var best_s: float = -999.0
	for i in range(current_options.size()):
		var o: Dictionary = current_options[i]
		var s: float = 0.0
		var kind: String = String(o["kind"])
		var id: String = String(o.get("id", ""))
		if kind == "up_weapon":
			var f: Dictionary = GameData.fusion_by_weapon.get(id, {})
			var lv: int = 0
			for w0 in state.weapons:
				if String(w0["id"]) == id:
					lv = int(w0["level"])
					break
			if not f.is_empty():
				# 有配方：越接近满级越值钱，且配材已在手时再加分
				s = 55.0 + lv * 4.0
				if state.has_passive(String(f.get("passive", ""))):
					s += 18.0
			else:
				s = 34.0 + lv * 3.0
		elif kind == "new_weapon":
			s = 52.0 if state.weapons.size() < 3 else 22.0
		elif kind == "new_passive":
			s = 24.0
			for w in state.weapons:
				var f2: Dictionary = GameData.fusion_by_weapon.get(String(w["id"]), {})
				if not f2.is_empty() and String(f2.get("passive", "")) == id:
					s = 72.0
		elif kind == "up_passive":
			s = 18.0
		if s > best_s:
			best_s = s
			best_i = i
	_on_picked(best_i)

func _sim_log() -> void:
	var bucket: int = int(elapsed / 15.0)
	if not sim_log.is_empty() and int(sim_log[-1]) == bucket:
		return
	sim_log.append(bucket)
	print("[sim] t=%d lv=%d kills=%d alive=%d hp=%.0f gems=%d coals=%d" % [
		int(elapsed), state.level, state.kills, enemies.count, player_hp, gems.size(), state.coals])

func _sim_report() -> void:
	print("[sim] ==== RESULT ====")
	print("[sim] victory=%s t=%.1f level=%d kills=%d hp=%.0f/%.0f coals=%d cd=%.2f" % [won, elapsed, state.level, state.kills, player_hp, player_max_hp, state.coals, float(state.stats.get("cooldown_mult", 1.0))])
	var parts: Array = []
	for w in state.weapons:
		parts.append("%s(Lv%d%s)" % [String(state.weapon_def(w).get("name", w["id"])), int(w["level"]), "★" if bool(w.get("ascended", false)) else ""])
	print("[sim] weapons=", ", ".join(parts))
	var pp: Array = []
	for p in state.passives:
		pp.append("%s(Lv%d)" % [String(GameData.passives.get(p["id"], {}).get("name", p["id"])), int(p["level"])])
	print("[sim] passives=", ", ".join(pp))
	print("[sim] stage=%s seal=%d reward=%d shillings=%d saved=%s armor=%d" % [stage_id, seal, reward, Meta.shillings, str(not sim_mode or save_run), state.armor.size()])
	var srcs: Array = []
	for k in dmg_by_src.keys():
		srcs.append("%s=%.0f" % [String(k), float(dmg_by_src[k])])
	srcs.sort()
	print("[sim] dmg_src %s total=%.0f" % [" ".join(PackedStringArray(srcs)), damage_taken_total])
	print("[sim] systems silver_run=%d meta_silver=%d covenants=%d coals=%d" % [
		int(rewards.silver_run) if rewards != null else 0,
		int(rewards.meta_silver_bonus) if rewards != null else 0,
		covenants.cards.size() if covenants != null else 0,
		state.coals])
	print("[sim] SIM_DONE")
	get_tree().quit()

func _finish(victory: bool) -> void:
	if over:
		return
	over = true
	won = victory
	modal = false
	chooser.close()
	reward = int(round(float(Meta.reward_for(victory, state.kills, elapsed, seal)) * stage_coin))
	if rewards != null:
		reward += int(round(float(rewards.silver_run) * stage_coin + float(rewards.meta_silver_bonus)))
	var commit: bool = (not sim_mode or save_run) and not no_meta
	# 毗努伊勒：全程不闪避（ach_28）
	if dashes_used <= 0:
		ach_flags["no_dodge"] = true
	var got: Array = []
	if achievements != null:
		got = achievements.evaluate(victory, commit)
	if sim_mode:
		var names: Array = []
		for g in got:
			names.append(String(g["id"]))
		print("[sim] achievements=", ", ".join(names))
	if commit:
		Meta.register_run(victory, state.kills, elapsed, seal)
		# 局外银两（寡妇的油瓶 / 钱袋）：结算时一次性入账
		if rewards != null and int(rewards.meta_silver_bonus) > 0:
			Meta.shillings += int(rewards.meta_silver_bonus)
		# 觉醒：三阶及以上通关点亮（圣典 3 章：觉醒是终局成长，不再另外消耗银两）
		if victory and Meta.effective_tier() >= 3:
			Meta.set_awakened(character_id)
		Meta.save_save()
	shake = maxf(shake, 6.0)
	if victory:
		sfx.play("fuse", 0.0, 0.75, 1.0)
	else:
		sfx.play("defeat", 0.0, 1.0, 1.0)

func _unhandled_input(e: InputEvent) -> void:
	if not over or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if e.keycode == KEY_R:
		get_tree().change_scene_to_file.call_deferred("res://scenes/camp.tscn")

func _drain_enemy_shots() -> void:
	var k: int = 0
	while k < enemies.shot_count:
		var o: int = k * 5
		var vx: float = enemies.shot_queue[o + 2]
		var vy: float = enemies.shot_queue[o + 3]
		var friendly: bool = false
		# 巴别变乱口音：弹幕偏转 35° 并转为友方（打敌人）
		if mechanics != null:
			var mod: Dictionary = mechanics.enemy_bullet_mod()
			if bool(mod.get("active", false)):
				var ang: float = float(mod.get("angle", 0.0))
				var nx: float = vx * cos(ang) - vy * sin(ang)
				var ny: float = vx * sin(ang) + vy * cos(ang)
				vx = nx
				vy = ny
				friendly = bool(mod.get("friendly", false))
		var sp: float = sqrt(vx * vx + vy * vy)
		if sp < 1.0:
			sp = 1.0
		shots.spawn(enemies.shot_queue[o], enemies.shot_queue[o + 1], vx, vy, sp, enemies.shot_queue[o + 4], friendly, {
			"life": 4.0, "radius": 2.5, "size": 3.0, "color": ProjectileSim.COL_SOUND if friendly else ProjectileSim.COL_ENEMY
		})
		k += 1
	enemies.shot_count = 0

	var s: int = 0
	while s < enemies.summon_count:
		var o2: int = s * 3
		enemies.spawn(int(enemies.summon_queue[o2 + 2]), enemies.summon_queue[o2], enemies.summon_queue[o2 + 1])
		s += 1
	enemies.summon_count = 0

func _drain_fx(delta: float) -> void:
	for f in weapons.drain_fx():
		active_fx.append(f)
	var i: int = active_fx.size() - 1
	while i >= 0:
		var f: Dictionary = active_fx[i]
		f["life"] = float(f["life"]) - delta
		if float(f["life"]) <= 0.0:
			active_fx.remove_at(i)
		i -= 1

func _consume_deaths() -> void:
	var steal: float = float(state.stats.get("lifesteal", 0.0)) * player_max_hp
	var pop_i: int = 0
	for d in enemies.deaths:
		state.kills += 1
		pop_i += 1
		if pop_i % 2 == 1:
			active_fx.append({ "kind": "pop", "x": float(d["x"]), "y": float(d["y"]), "r": 5.0, "life": 0.22, "color": Color("#F2D9A0") })
		if steal > 0.0 and not god and player_hp > 0.0:
			player_hp = minf(player_hp + steal, player_max_hp)
		var dpos := Vector2(float(d["x"]), float(d["y"]))
		if mechanics != null:
			mechanics.on_kill(dpos)
		var xp: int = int(float(d["xp"]) * (mechanics.xp_mult_at(dpos) if mechanics != null else 1.0))
		if rewards != null:
			rewards.add_gem(dpos.x, dpos.y, xp)
		else:
			gems.append({ "x": dpos.x, "y": dpos.y, "val": xp })
		if int(d["coal"]) > 0:
			state.coals += int(d["coal"])
		if bool(d["boss"]):
			if sim_mode:
				print("[sim] boss_killed t=%.1f" % elapsed)
			if endless_allowed and not endless_continued:
				_start_endless()
			else:
				_finish(true)
		elif bool(d["elite"]):
			elite_kills_total += 1
			_grant_armor()
			if rewards != null:
				if mechanics != null and mechanics.elite_chest_tier() == "gold":
					rewards.spawn_chest("gold", dpos.x, dpos.y)
				else:
					rewards.on_elite_killed(dpos.x, dpos.y)
	if not enemies.deaths.is_empty():
		sfx.play("hit", -6.0, randf_range(0.9, 1.15), 0.045)
	enemies.deaths.clear()

func _pickup_gems(delta: float) -> void:
	var pr: float = float(state.stats.get("pickup_radius", 30.0))
	if magnet_t > 0.0:
		pr *= 14.0
	var i: int = gems.size() - 1
	var gained: int = 0
	while i >= 0:
		var g: Dictionary = gems[i]
		var gp := Vector2(float(g["x"]), float(g["y"]))
		var d: float = gp.distance_to(player)
		if d < pr:
			gained += state.add_xp(float(g["val"]))
			gems.remove_at(i)
		elif d < pr * 4.0:
			var t: float = clampf(320.0 * delta / maxf(d, 1.0), 0.0, 1.0)
			g["x"] = float(g["x"]) + (player.x - gp.x) * t
			g["y"] = float(g["y"]) + (player.y - gp.y) * t
		i -= 1
	if gained > 0:
		pending_levels += gained
		sfx.play("pickup", -9.0, randf_range(0.92, 1.18), 0.04)
	if pending_levels > 0 and not modal and not over:
		_open_levelup()

func _check_ascend() -> void:
	var newly: Array = state.try_ascend(state.kills)
	for n in newly:
		var evo: Dictionary = n["evolve"]
		weapons.trigger_nova(String(evo.get("brew", "")), player)
		sfx.play("fuse", 0.0, 1.35, 0.4)
		toast_text = "成全 · " + String(evo.get("name", String(evo.get("brew", ""))))
		toast_t = 2.4
		shake = maxf(shake, 5.0)
		active_fx.append({ "kind": "nova", "x": player.x, "y": player.y, "r": 150.0, "life": 0.42, "color": Color("#F3E3A8") })

# ---------------------------------------------------------------- 刷怪

## 追不上玩家的敌人会永远留在屏幕外，白吃 CPU 又让画面空。
## 每 0.5 秒把过远的普通敌人重新投放到视野外圈（BOSS 不动）。
func _recycle_far(delta: float) -> void:
	recycle_acc += delta
	if recycle_acc < 0.5:
		return
	recycle_acc = 0.0
	var e: EnemySim = enemies
	var lim2: float = 700.0 * 700.0
	for i in range(e.count):
		if e.is_boss(i):
			continue
		var dx: float = e.px[i] - player.x
		var dy: float = e.py[i] - player.y
		if dx * dx + dy * dy > lim2:
			# 70% 投放在移动方向的侧后方扇区（追击压迫），30% 全向随机（留一条走位走廊）
			var a: float = rng.randf() * TAU
			if last_move_dir != Vector2.ZERO and rng.randf() < 0.7:
				a = last_move_dir.angle() + PI + rng.randf_range(-0.9, 0.9)
			var d: float = 330.0 + rng.randf() * 110.0
			e.px[i] = player.x + cos(a) * d
			e.py[i] = player.y + sin(a) * d

func _spawner(delta: float) -> void:
	var budget: Dictionary = stage.get("budget", {})
	# 七印的刷怪加成前 5 分钟渐入（开局不至于被淹没，后期才真正变密集）
	var rate_seal: float = 1.0 + (seal_rate - 1.0) * clampf(elapsed / 300.0, 0.0, 1.0)
	var rate: float = (float(budget.get("base", 58)) + float(budget.get("per_minute", 22)) * (elapsed / 60.0)) * rate_seal / 60.0
	# 开局渐入：前 75 秒只放 45%→100%，避免「比玩家快的敌人」一上来就贴脸滴血
	var ramp_in: float = lerpf(0.45, 1.0, clampf(elapsed / 75.0, 0.0, 1.0))
	rate *= ramp_in
	var max_alive: int = int(budget.get("max_alive", 420))
	spawn_acc += rate * delta
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if enemies.count >= max_alive:
			break
		_spawn_mix()

func _spawn_mix() -> void:
	var mix: Array = stage.get("mix", [])
	if mix.is_empty():
		return
	var chosen: Dictionary = mix[0]
	for m in mix:
		if elapsed >= float(m.get("t", 0)):
			chosen = m
	var list: Array = chosen.get("enemies", [])
	var total: int = 0
	for e in list:
		total += int(e.get("w", 0))
	if total <= 0:
		return
	var roll: int = rng.randi_range(1, total)
	var acc: int = 0
	var pick_id: String = ""
	for e in list:
		acc += int(e.get("w", 0))
		if roll <= acc:
			pick_id = String(e.get("id", ""))
			break
	var ti: int = enemies.type_index_of(pick_id)
	if ti < 0:
		return
	_spawn_at_ring(ti)

func _spawn_at_ring(ti: int, margin_min: float = 34.0, margin_max: float = 96.0) -> void:
	# 在可视矩形外沿生成，永远不从屏幕里凭空出现
	var m: float = rng.randf_range(margin_min, margin_max)
	var hw: float = 320.0 / CAM_ZOOM + m
	var hh: float = 180.0 / CAM_ZOOM + m
	var a: float = rng.randf() * TAU
	var dx: float = cos(a)
	var dy: float = sin(a)
	var t: float = minf(hw / maxf(absf(dx), 0.0001), hh / maxf(absf(dy), 0.0001))
	enemies.spawn(ti, player.x + dx * t, player.y + dy * t)
	if stage_speed != 1.0 and enemies.count > 0:
		enemies.spd[enemies.count - 1] *= stage_speed

func _altars_and_events() -> void:
	var elites: Array = stage.get("elites", [])
	while elite_done < elites.size() and elapsed >= float(elites[elite_done].get("t", 1e9)):
		# 契约 9 节用 n；老数据是 count，两个都读
		var cnt: int = int(elites[elite_done].get("n", elites[elite_done].get("count", 1)))
		var ti: int = enemies.type_index_of(String(elites[elite_done].get("id", "")))
		for c in range(cnt):
			if ti >= 0:
				_spawn_at_ring(ti, 110.0, 150.0)
		elite_done += 1

	if not boss_spawned and elapsed >= float(stage.get("boss_at", 690)):
		boss_spawned = true
		var bti: int = enemies.type_index_of(String(stage.get("boss", "goliath")))
		if bti >= 0:
			_spawn_at_ring(bti, 150.0, 175.0)
			# BOSS 血量按「章号预算」定标，不再吃 time hp_scale：
			# 否则第 24 章 40000 × 2.34 ≈ 9.4 万，90 秒窗口内根本打不完（实测 600~900 DPS）。
			var bi: int = enemies.count - 1
			if bi >= 0 and bi == enemies.boss_idx:
				var chapter: float = float(stage.get("chapter", 13))
				var target_hp: float = 9000.0 + 1250.0 * (chapter - 1.0)
				enemies.max_hp[bi] = target_hp
				enemies.hp[bi] = target_hp
			_recompute_boss()
			# 机关在 BOSS 登场时的结算：干涸溪床五石子削血、试探石饼加血……
			if mechanics != null:
				mechanics.on_boss_spawn()
			_ensure_boss_ai()
			shake = 9.0
			sfx.play("boss", 0.0, 1.0, 1.0)
			if sim_mode:
				print("[sim] boss_spawn id=%s hp=%.0f t=%.0f" % [String(stage.get("boss", "")), float(enemies.max_hp[enemies.count - 1]), elapsed])
		else:
			if sim_mode:
				print("[sim] boss_missing id=%s" % String(stage.get("boss", "")))

	# 祭坛：3:00 / 6:00 / 9:00 各放一座
	while altar_done < ALTAR_TIMES.size() and elapsed >= float(ALTAR_TIMES[altar_done]):
		altar_done += 1
		var a: float = rng.randf() * TAU
		altars.append({ "x": player.x + cos(a) * 96.0, "y": player.y + sin(a) * 96.0, "used": false })

	if sim_mode:
		_auto_altar()
	elif Input.is_action_just_pressed("interact"):
		_try_altar()

func _auto_altar() -> void:
	if not _altar_useful():
		return
	for a in altars:
		if bool(a.get("used", false)):
			continue
		if Vector2(float(a["x"]), float(a["y"])).distance_to(player) < 46.0:
			_open_altar(a)
			return

## 祭坛值不值得跑：要么已经能祝圣，要么还能领到「配材之光」把差一块砖的武器补上。
## （原来只判 available_fusions，导致模拟模式永远吃不到 _grant_partner 的赠送）
func _altar_useful() -> bool:
	if not state.available_fusions(true).is_empty():
		return true
	if state.passives.size() >= state.max_passive_slots():
		return false
	for w in state.weapons:
		if String(w.get("kind", "base")) != "base":
			continue
		var fd: Dictionary = GameData.fusion_by_weapon.get(String(w["id"]), {})
		if fd.is_empty():
			continue
		var pid: String = String(fd.get("passive", ""))
		if GameData.passives.has(pid) and not state.has_passive(pid):
			return true
	return false

## 有火炭且场上有未用祭坛时，自动驾驶先走过去
func _altar_target() -> Vector2:
	if not _altar_useful():
		return Vector2.INF
	for a in altars:
		if not bool(a.get("used", false)):
			return Vector2(float(a["x"]), float(a["y"]))
	return Vector2.INF

func _try_altar() -> void:
	if modal or over:
		return
	for a in altars:
		if not bool(a.get("used", false)) and Vector2(float(a["x"]), float(a["y"])).distance_to(player) < 46.0:
			_open_altar(a)
			return

func _recompute_boss() -> void:
	boss_index = -1
	for i in range(enemies.count):
		if enemies.is_boss(i):
			boss_index = i
			break
	if boss_index >= 0 and boss_ai == null:
		_ensure_boss_ai()

# ---------------------------------------------------------------- 面板

func _open_levelup() -> void:
	pending_levels -= 1
	var opts: Array = _level_options()
	if opts.is_empty():
		modal = false
		chooser.close()
		return
	modal = true
	chooser_mode = "level"
	current_options = opts
	chooser.open("领受 · Lv %d" % state.level, opts, rerolls)
	shake = maxf(shake, 2.0)
	level_flash = 1.0
	sfx.play("level", -2.0, 1.0, 0.3)

func _level_options() -> Array:
	var cand: Array = []
	for id in GameData.weapons.keys():
		if not state.has_weapon(id) and not state.consumed_weapons.has(id) and state.weapons.size() < state.max_weapon_slots():
			var d: Dictionary = GameData.weapons[id]
			cand.append({ "kind": "new_weapon", "id": id, "name": String(d.get("name", id)), "tag": "新武器", "desc": String(d.get("desc", "")), "color": Color(String(d.get("color", "#C9A66B"))) })
	for i in range(state.weapons.size()):
		var w: Dictionary = state.weapons[i]
		if int(w["level"]) >= state.weapon_max_level(w):
			continue
		var d2: Dictionary = state.weapon_def(w)
		cand.append({ "kind": "up_weapon", "id": String(w["id"]), "name": String(d2.get("name", w["id"])), "tag": "强化 Lv%d → Lv%d" % [int(w["level"]), int(w["level"]) + 1], "desc": String(d2.get("desc", "")), "color": Color(String(d2.get("color", "#C9A66B"))) })
	for pid in GameData.passives.keys():
		if state.has_passive(pid):
			continue
		if state.passives.size() >= state.max_passive_slots():
			break
		var pd: Dictionary = GameData.passives[pid]
		if String(pd.get("kind", "")) == "armor":
			continue
		cand.append({ "kind": "new_passive", "id": pid, "name": String(pd.get("name", pid)), "tag": "新被动", "desc": String(pd.get("desc", "")), "color": Color("#B8C4A8") })
	for j in range(state.passives.size()):
		var ps: Dictionary = state.passives[j]
		var pdef: Dictionary = GameData.passives.get(ps["id"], {})
		if int(ps["level"]) >= int(pdef.get("max_level", 5)):
			continue
		cand.append({ "kind": "up_passive", "id": String(ps["id"]), "name": String(pdef.get("name", ps["id"])), "tag": "强化 Lv%d → Lv%d" % [int(ps["level"]), int(ps["level"]) + 1], "desc": String(pdef.get("desc", "")), "color": Color("#B8C4A8") })
	if cand.is_empty():
		return []
	# 洗牌取 3
	for i in range(cand.size() - 1, 0, -1):
		var j2: int = rng.randi_range(0, i)
		var tmp: Variant = cand[i]
		cand[i] = cand[j2]
		cand[j2] = tmp
	var out: Array = cand.slice(0, mini(3, cand.size()))
	# 保底：只要还有武器可选，三张里至少有一张武器（否则容易连开三轮被动，形成死局）
	var has_weapon_opt: bool = false
	for o in out:
		var k: String = String(o.get("kind", ""))
		if k == "new_weapon" or k == "up_weapon":
			has_weapon_opt = true
			break
	if not has_weapon_opt and not out.is_empty():
		for o in cand:
			var k2: String = String(o.get("kind", ""))
			if k2 == "new_weapon" or k2 == "up_weapon":
				out[out.size() - 1] = o
				break
	# 首升互补：第一次领受时只有一把单体线弹，强制给一张 AOE 形态的新武器
	# （否则前 5 级连抽强化/被动，画面里永远只有一个方向的弹道，高印直接断档）
	if state.level <= 2 and state.weapons.size() == 1:
		var cur_beh: String = String(state.weapon_def(state.weapons[0]).get("behavior", ""))
		var aoe: Array = []
		for o2 in cand:
			if String(o2.get("kind", "")) != "new_weapon":
				continue
			var beh: String = String(GameData.weapons.get(String(o2["id"]), {}).get("behavior", ""))
			if beh != cur_beh and (beh == "orbit" or beh == "zone" or beh == "arc_melee"):
				aoe.append(o2)
		if not aoe.is_empty():
			var has_aoe: bool = false
			for o3 in out:
				if String(o3.get("kind", "")) == "new_weapon" and aoe.has(o3):
					has_aoe = true
					break
			if not has_aoe and not out.is_empty():
				out[0] = aoe[rng.randi_range(0, aoe.size() - 1)]
	# 祝圣的预备：差一级满级的武器 + 已有配材 → 该强化保底出现，避免差一块砖却抽不到的挫败
	var pri: String = _fusion_ready_weapon()
	if pri != "":
		var found: bool = false
		for o in out:
			if String(o.get("kind", "")) == "up_weapon" and String(o.get("id", "")) == pri:
				found = true
				break
		if not found and not out.is_empty():
			for o in cand:
				if String(o.get("kind", "")) == "up_weapon" and String(o.get("id", "")) == pri:
					out[0] = o
					break
	return out

## 精英掉落：全副军装（不占被动槽、不参与祝圣配方），让击杀六指巨人这类精英有即时的爽感。
func _grant_armor() -> void:
	var pool: Array = []
	for pid in GameData.passives.keys():
		var pd: Dictionary = GameData.passives[pid]
		if String(pd.get("kind", "")) != "armor":
			continue
		if state.has_armor(pid):
			continue
		pool.append(pid)
	if pool.is_empty():
		return
	var pick: String = String(pool[rng.randi_range(0, pool.size() - 1)])
	if not state.add_armor(pick):
		return
	armor_gained += 1
	if armor_gained >= 3:
		ach_flags["armor_treasure_3"] = true
	var nm: String = String(GameData.passives.get(pick, {}).get("name", pick))
	toast_text = "得军装 · " + nm
	toast_t = 1.8
	active_fx.append({ "kind": "nova", "x": player.x, "y": player.y, "r": 54.0, "life": 0.45, "color": Color("#D8C48A") })
	sfx.play("level", -4.0, 0.9, 0.25)
## 差一级就能祝圣的武器（Lv4 且配材已到手），返回 id 或空串。
func _fusion_ready_weapon() -> String:
	for w in state.weapons:
		if String(w.get("kind", "base")) != "base":
			continue
		if int(w["level"]) < state.weapon_max_level(w) - 1:
			continue
		var f: Dictionary = GameData.fusion_by_weapon.get(String(w["id"]), {})
		if f.is_empty():
			continue
		if state.has_passive(String(f.get("passive", ""))):
			return String(w["id"])
	return ""

func _open_altar(a: Dictionary) -> void:
	# 天使从坛上取火炭（赛 6:6）：抵达祭坛即得一枚火炭，保证 3/6/9 分钟的祝圣一定能体验
	if state.coals <= 0:
		state.coals = 1
		active_fx.append({ "kind": "nova", "x": player.x, "y": player.y, "r": 90.0, "life": 0.5, "color": Color("#FF8A3C") })
	var avail: Array = state.available_fusions()
	if avail.is_empty() and _grant_partner():
		avail = state.available_fusions()
	if avail.is_empty():
		return
	var opts: Array = []
	for item in avail:
		var fusion: Dictionary = item["fusion"]
		opts.append({
			"kind": "fusion",
			"slot": int(item["slot"]),
			"slot_b": int(item.get("slot_b", -1)),
			"fusion_id": String(fusion.get("id", "")),
			"name": String(fusion.get("name", "")),
			"tag": String(fusion.get("scripture", "")),
			"desc": String(fusion.get("desc", "")),
			"color": Color("#E0B85A")
		})
	if opts.is_empty():
		return
	a["used"] = true
	modal = true
	chooser_mode = "altar"
	current_options = opts
	chooser.open("祭坛 · 祝圣与合鸣", opts, 0)

func _on_picked(index: int) -> void:
	var mode: String = chooser_mode
	chooser_mode = ""
	if mode == "level":
		_apply_level_choice(index)
		if pending_levels > 0:
			_open_levelup()
		else:
			modal = false
			chooser.close()
	elif mode == "altar":
		_apply_altar_choice(index)
		modal = false
		chooser.close()
	elif mode == "covenant":
		if covenants != null:
			covenants.pick(index)
		modal = false
		chooser.close()

func _on_reroll() -> void:
	if chooser_mode != "level" or rerolls <= 0:
		return
	rerolls -= 1
	var opts: Array = _level_options()
	if opts.is_empty():
		return
	current_options = opts
	chooser.set_options(opts)
	chooser.rerolls = rerolls
	sfx.play("pickup", -6.0, 0.86, 0.06)

## 祝圣的预备：若已有 Lv5 武器却缺配材（圣灵的果子），祭坛主动补上缺失的那一件。
## 目的：把「前三分钟能不能凑出祝圣」从运气问题变成确定性路径。
func _grant_partner() -> bool:
	if state.passives.size() >= state.max_passive_slots():
		return false
	var best: int = -1
	var best_lv: int = -1
	var best_pid: String = ""
	for i in range(state.weapons.size()):
		var w: Dictionary = state.weapons[i]
		if String(w.get("kind", "base")) != "base":
			continue
		var f: Dictionary = GameData.fusion_by_weapon.get(String(w["id"]), {})
		if f.is_empty():
			continue
		var pid: String = String(f.get("passive", ""))
		if pid == "" or state.has_passive(pid) or not GameData.passives.has(pid):
			continue
		# 只补「快成型」的武器（Lv3+）：给 1 级武器配材等于提前浪费一个果子槽
		if int(w["level"]) < 3:
			continue
		if int(w["level"]) > best_lv:
			best_lv = int(w["level"])
			best = i
			best_pid = pid
	if best < 0:
		return false
	if not state.add_passive(best_pid):
		return false
	active_fx.append({ "kind": "nova", "x": player.x, "y": player.y, "r": 120.0, "life": 0.6, "color": Color("#B8C4A8") })
	sfx.play("level", -4.0, 1.12, 0.3)
	return true
func _apply_level_choice(index: int) -> void:
	if index < 0 or index >= current_options.size():
		return
	var o: Dictionary = current_options[index]
	var id: String = String(o["id"])
	match String(o["kind"]):
		"new_weapon":
			state.add_weapon(id)
		"up_weapon":
			for i in range(state.weapons.size()):
				if String(state.weapons[i]["id"]) == id:
					state.upgrade_weapon_at(i)
					break
		"new_passive":
			state.add_passive(id)
		"up_passive":
			for i in range(state.passives.size()):
				if String(state.passives[i]["id"]) == id:
					state.upgrade_passive_at(i)
					break
	player_max_hp = float(state.stats.get("max_hp", player_max_hp))
	# 领受即得安慰：每次升级回复 12% 生命上限
	if not god and player_hp > 0.0:
		player_hp = minf(player_hp + player_max_hp * float(state.stats.get("level_heal", 0.15)), player_max_hp)
	# 升级时也给机关 / 约一个钩子
	if mechanics != null:
		mechanics.on_level_up()
	# 日头停留之约：升级也冻结全场
	if bool(state.get_meta("covenant_sun_stand", false)) and not over:
		freeze_t = maxf(freeze_t, 2.2)

func _apply_altar_choice(index: int) -> void:
	if index < 0 or index >= current_options.size():
		return
	var o: Dictionary = current_options[index]
	var fid: String = String(o["fusion_id"])
	var fusion: Dictionary = GameData.fusion_by_id.get(fid, {})
	if fusion.is_empty():
		return
	state.apply_fusion(fusion, int(o["slot"]), int(o["slot_b"]), state.kills)
	active_fx.append({ "kind": "nova", "x": player.x, "y": player.y, "r": 240.0, "life": 0.8, "color": Color("#E0B85A") })
	shake = maxf(shake, 7.0)
	sfx.play("fuse", -1.0, 1.0, 0.4)

# ---------------------------------------------------------------- 圣物 / 无尽 / BOSS AI / 对外接口

## 圣物：局内只读（Meta.relics），按 relics.json 的 effect 分发。前 6 件给实际效果，
## 其余只做标记（银两 / 磁力 / 约 / 宝箱翻倍），保证不写回局外存档。
func _apply_relics() -> void:
	for rid in state.relics:
		var eff: String = String(GameData.relic_def(String(rid)).get("effect", ""))
		match eff:
			"codex":
				codex_unlocked = true
			"dps_meter":
				pass
			"all_treasures":
				_grant_armor()
			"fast_forward":
				fast_forward_available = true
			"covenant_system":
				pass
			"jukebox":
				pass
			"silver_magnet":
				if stat_patch != null:
					stat_patch.add("relic_R07", "silver_mult", "mul", 1.4)
					stat_patch.add("relic_R07", "speed", "mul", 1.2)
					stat_patch.add("relic_R07", "proj_speed_mult", "mul", 1.2)
			"endless":
				endless_allowed = true
			"banish", "reroll_plus":
				reroll_plus = true
				rerolls += 2
			"seal_shop":
				pass
			"chest_double":
				chest_double = true
	if sim_mode:
		print("[sim] relics=%s codex=%s fast_forward=%s endless=%s reroll+=%s chest_double=%s" % [
			str(state.relics), str(codex_unlocked), str(fast_forward_available), str(endless_allowed), str(reroll_plus), str(chest_double)])

## 生命上限同步：升级 / 约 / 圣物改 max_hp 时，玩家当前血量跟着涨（不白扣血）。
func _sync_max_hp() -> void:
	var nm: float = float(state.stats.get("max_hp", player_max_hp))
	if nm > player_max_hp and player_hp > 0.0:
		player_hp += nm - player_max_hp
	player_max_hp = nm
	player_hp = clampf(player_hp, 0.0, player_max_hp)

## 给机关 / 奖励系统用的治疗入口（不会超过上限）。
func heal_player(amount: float) -> void:
	if amount <= 0.0 or over or player_hp <= 0.0:
		return
	# 活水之约：满血也触发治疗，并把治疗量转成 140px 冲击波（治疗量 ×8）
	if bool(state.get_meta("covenant_heal_wave", false)) and player_hp >= player_max_hp:
		enemies.damage_in_circle(player.x, player.y, 140.0, amount * 8.0, "wet", 2.0, 90.0)
		active_fx.append({ "kind": "nova", "x": player.x, "y": player.y, "r": 140.0, "life": 0.4, "color": Color("#8FC8E0") })
		return
	player_hp = minf(player_hp + amount, player_max_hp)

## 给机关 / 奖励系统用的伤害入口（走统一减伤与无敌帧）。
func hurt_player(amount: float) -> void:
	if amount <= 0.0 or over or god:
		return
	_take_damage(amount, true, "mech")

## 持续伤害入口（水墙/苦水/烈日这类按 delta 累积的机关）：不吃无敌帧，本身就是连续量。
func hurt_player_dot(amount: float) -> void:
	if amount <= 0.0 or over or god:
		return
	_take_damage(amount, false, "dot")

## 无尽模式（R08 / R10）：BOSS 倒下不结算，把本局延长到 30 分钟，波次继续加码。
func _start_endless() -> void:
	if endless_continued:
		return
	endless_continued = true
	run_duration = maxf(run_duration, 1800.0)
	boss_spawned = true
	boss_ai = null
	toast_text = "无尽 · 守望到黎明"
	toast_t = 3.2
	shake = maxf(shake, 8.0)
	active_fx.append({ "kind": "nova", "x": player.x, "y": player.y, "r": 300.0, "life": 0.9, "color": Color("#F3E3A8") })
	if sim_mode:
		print("[sim] endless t=%.1f" % elapsed)

## BOSS AI（战斗代理实现 src/sim/boss_ai.gd）：文件还没落地时静默跳过，不影响其余系统。
func _ensure_boss_ai() -> void:
	if boss_index < 0:
		return
	# EnemySim 在 spawn 时已经给 BOSS 挂了 BossAI 并每帧驱动（enemy_sim.gd 单驱动保护）。
	# 优先接管那个实例，只给它补上 ProjectileSim，避免两个实例抢驱动。
	if enemies != null and enemies.boss_ai != null:
		boss_ai = enemies.boss_ai
		if boss_ai.shots == null:
			boss_ai.shots = shots
		return
	if boss_ai != null:
		return
	var path: String = "res://src/sim/boss_ai.gd"
	if not ResourceLoader.exists(path):
		return
	if boss_ai_script == null:
		boss_ai_script = load(path)
	if boss_ai_script == null:
		return
	var inst: Variant = boss_ai_script.new()
	if inst == null:
		return
	boss_ai = inst
	if boss_ai.has_method("setup"):
		var def: Dictionary = GameData.boss_def(String(stage.get("boss", "")))
		boss_ai.setup(enemies, boss_index, def, shots, rng)

func _tick_boss_ai(delta: float) -> void:
	if boss_ai == null:
		return
	if boss_index < 0:
		boss_ai = null
		return
	# 已由 EnemySim 内部驱动（enemies.boss_ai == boss_ai）时不再重复 tick
	if enemies != null and enemies.boss_ai == boss_ai:
		return
	if boss_ai.has_method("tick"):
		boss_ai.tick(delta, player)
