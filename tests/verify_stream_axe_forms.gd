extends "res://tests/verify_stream_parity.gd"
## verify_stream_axe_forms.gd —— 小木斧高档位 / 最终造物的演出在逐帧直播里画得出来(2026-11-15)。
## 用户 11-15「我玩的时候看…(小木斧的钻石技能)整个技能特效都没出现啊，都有 bug」。
## 根因(探针 tests/probes/_probe_stream_diamond_axe.gd 量出): 钻石斧被动 6 的梯形预警 / 六边形网格 / 三层边线 / 跑动光点 /
##   砸地光盘、余烬的地面细环, 都是 SurfaceTool 现拼的网格、没挂出处键 ⇒ 直播流里手机只收到空壳(占位 65 / 2),
##   周末赛、直播、回放(都是服务器算、手机按流重放)里整段演出看不见; 本机直接跑一切正常。
##   直播覆盖扫描(verify_stream_coverage)跑小木斧用默认木斧档位, 被动 6 与造物根本不触发 ⇒ 一直没抓到。
## 做法: 父类 verify_stream_parity 的「录流 → 重放 → 逐采样点比」, 本机存档设成钻石斧 + 四种造物各录一局(左边带小木斧, 右边木桩)。
## 判据: 每局 ① 父类 ★★ 那几条(含「占位 = 0」: 手机拿到的每张网格都能现生成)② 分母: 这一局真放过主动(钻石斧 = 进过蓄力 / 造物 = 主动放过)。
## 反向验证(11-15): gen_axe_hex 去掉 VfxTex.tag ⇒ 钻石斧那局「占位 = 0」与镜像网格两条红; 还原后全绿。

const CASES := [
	{"final": "", "frames": 960},          # 钻石斧: 10.5 秒放治疗 → 4 秒蓄力 → 14.5 秒砸下
	{"final": "undead", "frames": 900},
	{"final": "seraph", "frames": 900},
	{"final": "holo", "frames": 900},
	{"final": "ember", "frames": 900},
]

var _casts := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	for cs in CASES:
		var fin: String = str(cs["final"])
		gs.set("axe_stage", 4)
		gs.set("axe_exp_total", 480 + (400 if fin != "" else 0))
		gs.set("axe_final", fin)
		var tag: String = "钻石斧" if fin == "" else ("造物 " + fin)
		_casts[tag] = 0
		var hook := func(n: Node) -> void:
			## 分母: 斧头主动的治疗光柱(钻石斧与造物共用的起手 eq096-heal)
			if n is Sprite3D and (n as Sprite3D).texture != null and (n as Sprite3D).texture.resource_path.ends_with("eq096-heal.png"):
				_casts[tag] = int(_casts[tag]) + 1
		get_tree().node_added.connect(hook)
		var sc := {"tag": tag, "frames": int(cs["frames"]), "seed": "424242", "loadouts": {}, "pairs": [
			["basic", "left", 420.0, 360.0, ["p2eq_096"]],
			["stone", "right", 680.0, 360.0, []]]}
		var nat: Dictionary = await _record_det(sc)
		get_tree().node_added.disconnect(hook)
		_ok("① 分母: 「%s」这一局斧头真放过主动(治疗光柱 %d 次)" % [tag, int(_casts[tag])], int(_casts[tag]) >= 1)
		await _play_and_compare("det " + tag, nat["chunks"], nat["meta"], nat)
	gs.set("axe_stage", 0)
	gs.set("axe_exp_total", 0)
	gs.set("axe_final", "")
	_finish()
