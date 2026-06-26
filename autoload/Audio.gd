extends Node

## Audio — 全局音频 (Autoload 单例)
##
## 用法:
##   Audio.play_sfx("hit-physical")
##   Audio.play_sfx_for_cls("crit-dmg")     # 按 VisualConstants cls 自动选音
##   Audio.play_bgm("battle")
##   Audio.stop_bgm()
##
## SFX 来源: PoC public/sfx/*.wav (直接拷过来)
## BGM 来源: PoC public/audio/*.mp3

const SFX_PATHS: Dictionary = {
	"hit-physical":  "res://assets/audio/sfx/hit-physical.wav",
	"hit-crit":      "res://assets/audio/sfx/hit-crit.wav",
	"heal":          "res://assets/audio/sfx/heal.wav",
	"shield-gain":   "res://assets/audio/sfx/shield-gain.wav",
	"shield-break":  "res://assets/audio/sfx/shield-break.wav",
	"defeat":        "res://assets/audio/sfx/defeat.wav",
	"rebirth":       "res://assets/audio/sfx/rebirth.wav",
}

const BGM_PATHS: Dictionary = {
	"menu":    "res://assets/audio/bgm/bgm-menu.mp3",
	"battle":  "res://assets/audio/bgm/bgm-battle.mp3",
	"boss":    "res://assets/audio/bgm/bgm-boss.mp3",
}

# 默认音量 (linear, 0-1)
var sfx_volume: float = 0.8
var bgm_volume: float = 0.45

# SFX 播放器池 (一次性 spawn, 自动 free)
var _sfx_cache: Dictionary = {}   # name → AudioStream

# BGM 单例
var _bgm_player: AudioStreamPlayer = null
var _current_bgm: String = ""


func _ready() -> void:
	# 预加载所有 SFX (小, < 1MB 全部进内存便宜)
	for name in SFX_PATHS:
		var path: String = SFX_PATHS[name]
		if ResourceLoader.exists(path):
			_sfx_cache[name] = load(path)

	# BGM player 常驻
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	add_child(_bgm_player)


## 把 bgm_volume 即时应用到正在播放的 BGM player (滑条拖动时实时听感, 无淡入).
func apply_bgm_volume() -> void:
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.volume_db = linear_to_db(maxf(bgm_volume, 0.0001))


# ─── SFX ──────────────────────────────────────────────────────

## play_sfx 加 pitch_scale + 默认 ±5% pitch 随机抖
##   破单调利器: 同一个音 5% 随机 pitch + 5% 随机 volume → 听感天差地别
func play_sfx(name: String, volume_scale: float = 1.0, pitch_base: float = 1.0,
		pitch_jitter: float = 0.05, vol_jitter: float = 0.05) -> void:
	var stream: AudioStream = _sfx_cache.get(name)
	if stream == null:
		return
	# 每次 spawn 一个临时 player, finished 后自动 free (避免重叠时 cut off 旧的)
	var p := AudioStreamPlayer.new()
	p.stream = stream
	var vol_mult: float = volume_scale * (1.0 + randf_range(-vol_jitter, vol_jitter))
	p.volume_db = linear_to_db(sfx_volume * maxf(0.01, vol_mult))
	p.pitch_scale = pitch_base * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## 按 VisualConstants cls (飘字类) 自动选 SFX, 跟 Phaser visual_dispatcher.ts:215-242 同步
## 用户报 "Phaser 都用同一个受击太单一" → 这里靠 pitch_base 按伤害类型分音色:
##   物理       pitch=1.0  (基础)
##   魔法       pitch=1.18 (更高更"zap")
##   真伤       pitch=0.85 (更低更"boom")
##   穿透/破盾  pitch=1.3  (短脆"叮")
##   DoT       pitch ≈ dmg_type 对应 (灼烧/中毒按魔法、流血按物理、诅咒按真伤)
##   暴击       走 hit-crit 强音
func play_sfx_for_cls(cls: String) -> void:
	if cls.begins_with("crit"):
		# 暴击专用音, 随机 pitch ±3% (爆裂感, 别变太多失去识别性)
		play_sfx("hit-crit", 1.0, 1.0, 0.03)
	elif cls in ["direct-dmg", "phys-dmg", "dot-bleed"]:
		play_sfx("hit-physical", 0.85, 1.0, 0.08)              # 物理: 基础 + 8% jitter
	elif cls in ["magic-dmg", "dot-dmg", "dot-poison"]:
		play_sfx("hit-physical", 0.85, 1.18, 0.08)             # 魔法: pitch +18%
	elif cls in ["true-dmg", "dot-curse"]:
		play_sfx("hit-physical", 0.95, 0.85, 0.05)             # 真伤: pitch -15% 更沉重
	elif cls == "pierce-dmg":
		play_sfx("hit-physical", 0.75, 1.3, 0.06)              # 穿透: pitch +30% 脆
	elif cls in ["heal-num", "heal"]:
		play_sfx("heal", 1.0, 1.0, 0.04)
	elif cls in ["shield-num", "shield-gain"]:
		play_sfx("shield-gain", 0.9, 1.0, 0.05)
	elif cls == "shield-dmg":
		play_sfx("shield-break", 1.0, 1.0, 0.06)
	elif cls in ["dodge-num", "miss"]:
		play_sfx("heal", 0.28, 1.26, 0.04)   # 1:1 PoC 闪避whoosh=heal.wav rate1.6/detune400 vol≈0.22 (sfx.ts:24/visual_dispatcher:241) — 原闪避无音
	# (删 death-explode→defeat 分支: 无人spawn该cls=死代码, 且PoC fireSfxForCls无此case=自创; 防日后接死爆float误响死亡音)


# ─── BGM ──────────────────────────────────────────────────────

## base_vol = 该场景 BGM 的基准音量 (1:1 PoC: menu 0.4 / battle·boss 0.35); 0.45=旧统一基准。
##   实际音量 = base_vol × (用户设置 bgm_volume / 0.45) → 用户没动设置时就是 PoC 基准, 动了按比例缩。
func play_bgm(name: String, fade_in_s: float = 1.0, base_vol: float = 0.45) -> void:
	if _current_bgm == name and _bgm_player.playing:
		return
	var path: String = BGM_PATHS.get(name, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true

	_current_bgm = name
	_bgm_player.stream = stream
	_bgm_player.volume_db = -80.0    # 起点静音
	_bgm_player.play()
	# 淡入 (1:1 PoC battle BGM volume 0→target, Sine.easeIn)
	var target_lin: float = base_vol * (bgm_volume / 0.45)
	var target_db: float = linear_to_db(maxf(0.0001, target_lin))
	var tween := create_tween()
	tween.tween_property(_bgm_player, "volume_db", target_db, fade_in_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func stop_bgm(fade_out_s: float = 0.5) -> void:
	if not _bgm_player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_bgm_player, "volume_db", -80.0, fade_out_s)
	tween.tween_callback(_bgm_player.stop)
	_current_bgm = ""
