class_name Sfx
extends Node
## 音频 V4：程序化音效包 + 可无缝循环的垫乐播放器。
##
## 对外契约（run.gd / hud.gd / camp_screen.gd / title_screen.gd / codex_screen.gd 的写法一律不改）：
##     play(id: String, vol_db: float = 0.0, pitch: float = 1.0, cd: float = 0.035) -> void
##     enabled: bool
## 未知音名静默忽略：不打日志、不 push_error、不阻塞。
##
## 结构：
##   * 12 个程序化合成的 wav 覆盖所有语义音名；中文语义名、旧写死音名都经 ALIASES 落到同一批文件，
##     「命中三档 / 死亡两变体 / 受伤两变体」这类靠每名音高与增益偏移复用，而不是多堆文件。
##   * SFX / Music 两条总线在运行时创建（项目里没有 default_bus_layout.tres，也不新增它）：
##     SFX -2 dB、Music -8 dB。set_sfx_enabled / set_music_enabled 控制总线静音。
##   * 无头（--headless / --sim、音频驱动为 Dummy）时完全不初始化音频：不建总线、不建播放器、
##     不加载任何流，play() 直接返回。这是硬门禁，绝不能因为没声卡而报错或卡住。

const SFX_DIR := "res://assets/sfx/"
const MUSIC_PATH := "res://assets/music/camp_loop.ogg"

const BUS_SFX := "SFX"
const BUS_MUSIC := "Music"
const SFX_BUS_DB := -2.0
const MUSIC_BUS_DB := -8.0
const POOL := 16
const MIN_CD := 0.0

## 每个文件的基础参数：gain 叠加调用方音量、pitch 乘调用方音高、cd 是该文件的最小冷却。
## 调用方传了更长的 cd 就取更长的一侧，避免 Boss 这种长音被密集触发。
const FILE_SPEC := {
	"slash": {"gain": 0.0, "pitch": 1.0, "cd": 0.02},
	"hit_light": {"gain": 0.0, "pitch": 1.0, "cd": 0.03},
	"hit_heavy": {"gain": 0.0, "pitch": 1.0, "cd": 0.04},
	"enemy_death": {"gain": 0.0, "pitch": 1.0, "cd": 0.04},
	"pickup_gem": {"gain": 0.0, "pitch": 1.0, "cd": 0.03},
	"pickup_coin": {"gain": 0.0, "pitch": 1.0, "cd": 0.03},
	"level_up": {"gain": 0.0, "pitch": 1.0, "cd": 0.20},
	"fuse": {"gain": 0.0, "pitch": 1.0, "cd": 0.20},
	"boss": {"gain": 0.0, "pitch": 1.0, "cd": 0.80},
	"hurt": {"gain": 0.0, "pitch": 1.0, "cd": 0.05},
	"defeat": {"gain": 0.0, "pitch": 1.0, "cd": 0.80},
	"ui": {"gain": 0.0, "pitch": 1.0, "cd": 0.015},
}

## 语义名 -> 文件。值为 String 表示直接复用文件默认参数；
## 值为 Dictionary 时 file 必填，pitch/gain/cd 覆盖默认值（这是变体复用的手段）。
const ALIASES := {
	# ---- 近战 ----
	"slash": "slash",
	"swing": "slash",
	"arc": "slash",
	"melee": "slash",
	"slash_arc": "slash",
	"挥砍": "slash",
	"挥击": "slash",
	"劈砍": "slash",
	"dash": {"file": "slash", "pitch": 0.78, "gain": -3.0, "cd": 0.12},
	"roll": {"file": "slash", "pitch": 0.71, "gain": -5.0, "cd": 0.12},
	"dodge": {"file": "slash", "pitch": 0.74, "gain": -4.0, "cd": 0.12},
	"冲刺": {"file": "slash", "pitch": 0.78, "gain": -3.0, "cd": 0.12},
	"闪避": {"file": "slash", "pitch": 0.74, "gain": -4.0, "cd": 0.12},

	# ---- 命中三档 + 暴击 ----
	"hit": "hit_light",
	"hit_light": "hit_light",
	"命中": "hit_light",
	"轻击": "hit_light",
	"命中轻": "hit_light",
	"hit_mid": {"file": "hit_heavy", "pitch": 1.22, "gain": -1.5},
	"hit_medium": {"file": "hit_heavy", "pitch": 1.22, "gain": -1.5},
	"命中中": {"file": "hit_heavy", "pitch": 1.22, "gain": -1.5},
	"hit_heavy": "hit_heavy",
	"重击": "hit_heavy",
	"命中重": "hit_heavy",
	"crit": {"file": "hit_heavy", "pitch": 1.34, "gain": 2.0, "cd": 0.06},
	"critical": {"file": "hit_heavy", "pitch": 1.34, "gain": 2.0, "cd": 0.06},
	"暴击": {"file": "hit_heavy", "pitch": 1.34, "gain": 2.0, "cd": 0.06},

	# ---- 敌人死亡两变体 ----
	"enemy_death": "enemy_death",
	"kill": "enemy_death",
	"敌人死亡": "enemy_death",
	"enemy_death_a": {"file": "enemy_death", "pitch": 0.94},
	"敌人死亡a": {"file": "enemy_death", "pitch": 0.94},
	"enemy_death_b": {"file": "enemy_death", "pitch": 1.07},
	"敌人死亡b": {"file": "enemy_death", "pitch": 1.07},

	# ---- 拾取 ----
	"pickup": "pickup_gem",
	"pickup_gem": "pickup_gem",
	"gem": "pickup_gem",
	"拾取": "pickup_gem",
	"宝石": "pickup_gem",
	"拾取宝石": "pickup_gem",
	"pickup_coin": "pickup_coin",
	"coin": "pickup_coin",
	"shilling": "pickup_coin",
	"银币": "pickup_coin",
	"舍客勒": "pickup_coin",
	"拾取银币": "pickup_coin",

	# ---- 升级 / 三选一 ----
	"level": "level_up",
	"level_up": "level_up",
	"upgrade": "level_up",
	"升级": "level_up",
	"领受升级": "level_up",
	"升级领受": "level_up",
	"confirm": {"file": "pickup_gem", "pitch": 0.80, "gain": -2.0, "cd": 0.10},
	"picked": {"file": "pickup_gem", "pitch": 0.80, "gain": -2.0, "cd": 0.10},
	"三选一确认": {"file": "pickup_gem", "pitch": 0.80, "gain": -2.0, "cd": 0.10},
	"确认": {"file": "pickup_gem", "pitch": 0.80, "gain": -2.0, "cd": 0.10},

	# ---- 武器合成 / 祝圣 ----
	"fuse": "fuse",
	"craft": "fuse",
	"weapon_craft": "fuse",
	"forge": "fuse",
	"consecrate": "fuse",
	"sanctify": "fuse",
	"合成": "fuse",
	"武器合成": "fuse",
	"祝圣": "fuse",

	# ---- Boss ----
	"boss": "boss",
	"boss_appear": "boss",
	"boss_spawn": "boss",
	"Boss出现": "boss",
	"BOSS出现": "boss",
	"boss_death": {"file": "defeat", "pitch": 0.80, "gain": 2.0, "cd": 0.8},
	"boss_defeat": {"file": "defeat", "pitch": 0.80, "gain": 2.0, "cd": 0.8},
	"Boss死亡": {"file": "defeat", "pitch": 0.80, "gain": 2.0, "cd": 0.8},

	# ---- 玩家 ----
	"hurt": "hurt",
	"player_hurt": "hurt",
	"受伤": "hurt",
	"玩家受伤": "hurt",
	"hurt_a": {"file": "hurt", "pitch": 0.95},
	"受伤a": {"file": "hurt", "pitch": 0.95},
	"hurt_b": {"file": "hurt", "pitch": 1.06},
	"受伤b": {"file": "hurt", "pitch": 1.06},
	"defeat": "defeat",
	"death": "defeat",
	"player_death": "defeat",
	"死亡": "defeat",
	"玩家死亡": "defeat",

	# ---- 场景与界面 ----
	"altar": {"file": "fuse", "pitch": 0.72, "gain": 1.0, "cd": 0.4},
	"shrine": {"file": "fuse", "pitch": 0.72, "gain": 1.0, "cd": 0.4},
	"祭坛": {"file": "fuse", "pitch": 0.72, "gain": 1.0, "cd": 0.4},
	"祭坛开启": {"file": "fuse", "pitch": 0.72, "gain": 1.0, "cd": 0.4},
	"chest": {"file": "pickup_gem", "pitch": 0.70, "gain": 1.0, "cd": 0.25},
	"宝箱": {"file": "pickup_gem", "pitch": 0.70, "gain": 1.0, "cd": 0.25},
	"宝箱开启": {"file": "pickup_gem", "pitch": 0.70, "gain": 1.0, "cd": 0.25},
	"pause": {"file": "ui", "pitch": 0.72, "gain": -4.0, "cd": 0.08},
	"暂停": {"file": "ui", "pitch": 0.72, "gain": -4.0, "cd": 0.08},
	"resume": {"file": "ui", "pitch": 0.85, "gain": -5.0, "cd": 0.08},
	"取消暂停": {"file": "ui", "pitch": 0.85, "gain": -5.0, "cd": 0.08},
	"hover": {"file": "ui", "pitch": 1.50, "gain": -13.0, "cd": 0.02},
	"ui_hover": {"file": "ui", "pitch": 1.50, "gain": -13.0, "cd": 0.02},
	"悬停": {"file": "ui", "pitch": 1.50, "gain": -13.0, "cd": 0.02},
	"click": {"file": "ui", "pitch": 1.0, "gain": -7.0, "cd": 0.02},
	"ui_click": {"file": "ui", "pitch": 1.0, "gain": -7.0, "cd": 0.02},
	"点击": {"file": "ui", "pitch": 1.0, "gain": -7.0, "cd": 0.02},
}

var streams: Dictionary = {}
var players: Array = []
var next: int = 0
var cooldown: Dictionary = {}

## 兼容旧契约：false 时一切静音（run.gd 用它做暂停菜单静音 / 模拟模式关音）。
var enabled: bool = true
var sfx_enabled: bool = true
var music_enabled: bool = true
## 进入场景时自动起垫乐（默认开；某个场景想静音可以直接关掉）。
var autoplay_music: bool = true

var _audio_ok: bool = false
var _music_player: AudioStreamPlayer = null
var _music_path: String = ""
var _music_wanted: bool = false

## 流缓存是进程级的：四个界面各 new 一个 Sfx，没必要重复 decode 同一批 wav。
static var _stream_cache: Dictionary = {}
## 同一时刻只允许一个 Sfx 实例在放垫乐，防止场景切换时两路叠加。
static var _music_owner: int = 0


func _ready() -> void:
	_audio_ok = _detect_audio()
	if not _audio_ok:
		# 无头 / 无音频设备：彻底静默，连 _process 都不挂
		set_process(false)
		return
	_ensure_buses()
	_load_streams()
	for i in range(POOL):
		var ap := AudioStreamPlayer.new()
		ap.bus = BUS_SFX
		add_child(ap)
		players.append(ap)
	_apply_bus_mute(BUS_SFX, not sfx_enabled)
	_apply_bus_mute(BUS_MUSIC, not music_enabled)
	if autoplay_music and bool(enabled) and music_enabled:
		_music_wanted = true
		_restart_music_if_needed()


func _exit_tree() -> void:
	if _music_owner == get_instance_id():
		_music_owner = 0


func _process(_delta: float) -> void:
	if not _audio_ok:
		return
	var should_play: bool = _music_wanted and bool(enabled) and music_enabled
	if should_play:
		_restart_music_if_needed()
	elif _music_player != null and _music_player.playing:
		_music_player.stop()


# ---------------------------------------------------------------- 播放

## 播放一个语义音名。未知音名安静忽略：项目里旧调用点写死的名字继续有效。
func play(id: String, vol_db: float = 0.0, pitch: float = 1.0, cd: float = 0.035) -> void:
	if not _audio_ok or not bool(enabled) or not sfx_enabled:
		return
	if players.is_empty():
		return
	var spec := _resolve(id)
	if spec.is_empty():
		return
	var key: String = spec["file"]
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var use_cd: float = maxf(cd, float(spec["cd"]))
	if use_cd > MIN_CD and now - float(cooldown.get(key, -999.0)) < use_cd:
		return
	cooldown[key] = now
	var ap := players[next] as AudioStreamPlayer
	next = (next + 1) % players.size()
	ap.stream = streams[key]
	ap.volume_db = clampf(vol_db + float(spec["gain"]), -60.0, 6.0)
	ap.pitch_scale = clampf(pitch * float(spec["pitch"]), 0.5, 2.0)
	ap.play()


## 是否有这个语义名（含中英文别名）。调试 / 单测用。
func has_sound(id: String) -> bool:
	return not _resolve(id).is_empty()


## 全部可解析的音名（排序后），给图鉴 / 调试面板列清单。
func sound_names() -> Array:
	return ALIASES.keys()


# ---------------------------------------------------------------- 垫乐

## 循环播放垫乐。缺文件、无音频设备、被关掉时都静默返回。
func play_music(path: String = MUSIC_PATH, vol_db: float = 0.0, fade_s: float = 1.2) -> void:
	if not _audio_ok:
		return
	if not ResourceLoader.exists(path):
		return
	_music_wanted = true
	_music_path = path
	_restart_music_if_needed(vol_db, fade_s)


## 淡出并停止垫乐。
func stop_music(fade_s: float = 0.6) -> void:
	_music_wanted = false
	if _music_player == null:
		return
	if fade_s <= 0.0:
		_music_player.stop()
		return
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", -60.0, fade_s)
	tw.tween_callback(_music_player.stop)
	if _music_owner == get_instance_id():
		_music_owner = 0


func is_music_playing() -> bool:
	return _music_player != null and _music_player.playing


# ---------------------------------------------------------------- 总线 / 开关

func set_sfx_enabled(v: bool) -> void:
	sfx_enabled = v
	_apply_bus_mute(BUS_SFX, not v)


func set_music_enabled(v: bool) -> void:
	music_enabled = v
	_apply_bus_mute(BUS_MUSIC, not v)
	if not v and _music_player != null:
		_music_player.stop()


func is_sfx_enabled() -> bool:
	return sfx_enabled


func is_music_enabled() -> bool:
	return music_enabled


## 总线绝对电平（默认 SFX -2 dB / Music -8 dB）。
func set_bus_volumes(sfx_db: float, music_db: float) -> void:
	if not _audio_ok:
		return
	var si := AudioServer.get_bus_index(BUS_SFX)
	if si >= 0:
		AudioServer.set_bus_volume_db(si, sfx_db)
	var mi := AudioServer.get_bus_index(BUS_MUSIC)
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, music_db)


# ---------------------------------------------------------------- 内部

func _detect_audio() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var driver := AudioServer.get_driver_name()
	if driver.is_empty() or driver.to_lower() == "dummy":
		return false
	return true


func _ensure_buses() -> void:
	_ensure_bus(BUS_SFX, SFX_BUS_DB)
	_ensure_bus(BUS_MUSIC, MUSIC_BUS_DB)


func _ensure_bus(bus_name: String, volume_db: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, volume_db)


func _apply_bus_mute(bus_name: String, muted: bool) -> void:
	if not _audio_ok:
		return
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)


func _load_streams() -> void:
	for key in FILE_SPEC:
		var path: String = SFX_DIR + String(key) + ".wav"
		var st := _load_cached(path)
		if st != null:
			streams[key] = st


func _resolve(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	var key := id.strip_edges()
	var entry: Variant = ALIASES.get(key, null)
	if entry == null:
		entry = ALIASES.get(key.to_lower(), null)
	if entry == null:
		return {}
	var file_key := ""
	var pitch_mul := 1.0
	var gain := 0.0
	var extra_cd := 0.0
	if entry is String:
		file_key = String(entry)
	else:
		var d: Dictionary = entry
		file_key = String(d.get("file", ""))
		pitch_mul = float(d.get("pitch", 1.0))
		gain = float(d.get("gain", 0.0))
		extra_cd = float(d.get("cd", 0.0))
	if file_key.is_empty() or not streams.has(file_key):
		return {}
	var base: Dictionary = FILE_SPEC.get(file_key, {})
	return {
		"file": file_key,
		"pitch": pitch_mul * float(base.get("pitch", 1.0)),
		"gain": gain + float(base.get("gain", 0.0)),
		"cd": maxf(extra_cd, float(base.get("cd", 0.0))),
	}


static func _load_cached(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path] as AudioStream
	var st: AudioStream = null
	if ResourceLoader.exists(path):
		st = load(path) as AudioStream
	_stream_cache[path] = st
	return st


func _restart_music_if_needed(vol_db: float = 0.0, fade_s: float = 1.2) -> void:
	if not _audio_ok or not music_enabled or not bool(enabled):
		return
	if _music_owner != 0 and _music_owner != get_instance_id():
		return
	var path := _music_path if not _music_path.is_empty() else MUSIC_PATH
	var st := _load_cached(path)
	if st == null:
		return
	_prepare_loop(st)
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.bus = BUS_MUSIC
		add_child(_music_player)
	if _music_player.playing and _music_player.stream == st:
		_music_player.volume_db = vol_db
		return
	_music_owner = get_instance_id()
	_music_player.stream = st
	_music_player.volume_db = vol_db - 40.0 if fade_s > 0.05 else vol_db
	_music_player.play()
	if fade_s > 0.05:
		var tw := create_tween()
		tw.tween_property(_music_player, "volume_db", vol_db, fade_s)


func _prepare_loop(st: AudioStream) -> void:
	# 循环点交给流自己：ogg 逐样本循环，wav 兜底时把 loop_end 推到末尾
	if st is AudioStreamOggVorbis:
		var ogg := st as AudioStreamOggVorbis
		ogg.loop = true
		ogg.loop_offset = 0.0
	elif st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = true
	elif st is AudioStreamWAV:
		var wav := st as AudioStreamWAV
		var frame_bytes := 1
		if wav.format == AudioStreamWAV.FORMAT_16_BITS:
			frame_bytes = 2
		if wav.stereo:
			frame_bytes *= 2
		if frame_bytes > 0 and wav.data.size() > 0:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = wav.data.size() / frame_bytes