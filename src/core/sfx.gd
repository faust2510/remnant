class_name Sfx
extends Node
## 极简音效池：预载 assets/sfx/*.wav，按名字播放。
## 同名有冷却，避免高击杀频率把耳朵炸掉；无头模拟下由调用方跳过。

const NAMES := ["hit", "pickup", "level", "hurt", "fuse", "dash", "boss", "defeat"]
const POOL := 14

var streams: Dictionary = {}
var players: Array = []
var next: int = 0
var cooldown: Dictionary = {}
var enabled: bool = true

func _ready() -> void:
	for n in NAMES:
		var p := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(p):
			streams[n] = load(p)
	for i in range(POOL):
		var ap := AudioStreamPlayer.new()
		add_child(ap)
		players.append(ap)

func play(id: String, vol_db: float = 0.0, pitch: float = 1.0, cd: float = 0.035) -> void:
	if not enabled or players.is_empty() or not streams.has(id):
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now - float(cooldown.get(id, -99.0)) < cd:
		return
	cooldown[id] = now
	var ap: AudioStreamPlayer = players[next]
	next = (next + 1) % players.size()
	ap.stream = streams[id]
	ap.volume_db = vol_db
	ap.pitch_scale = clampf(pitch, 0.5, 2.0)
	ap.play()
