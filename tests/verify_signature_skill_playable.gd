extends Node
## verify_signature_skill_playable.gd —— 每只龟的签名技(skillPool[1])都要能被机器人/队列模拟选到(2026-10-11 全项目通读·赛制第 8 条)
##
## ★读码发现: SkillChoice.playable_indices 只收 impl==true 的条目; 钻石/彩虹/宝箱三只龟的 idx1 缺 impl ⇒
##   机器人与模拟选手永远不选这三招(玩家侧 dev_locked 对 idx1 单独放过, 所以玩家看不出来)。
##   三招都已实装、也在战斗分派表 _IMPL_SKILLS 里。
## ★判据: 28 只龟逐只, idx1 必须在 playable_indices 里; 且 impl 标了的招都在战斗的 _IMPL_SKILLS 里(不许乱标)。

const SC := preload("res://scripts/gamedata/skill_choice.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 签名技能被机器人选到 ===")
	var pets: Array = DataRegistry.launch_pets
	_ok("★分母: 读到 28 只龟", pets.size() >= 28, "%d" % pets.size())
	var miss: Array = []
	var fake: Array = []
	for p in pets:
		var pd: Dictionary = p
		if not (1 in SC.playable_indices(pd)):
			miss.append(str(pd.get("id", "?")))
		var pool: Array = pd.get("skillPool", [])
		for i in range(1, pool.size()):
			var sk = pool[i]
			if sk is Dictionary and bool((sk as Dictionary).get("impl", false)):
				var ty := str((sk as Dictionary).get("type", ""))
				if not RB._IMPL_SKILLS.has(ty) and not RB.PASSIVE_SKILL_TYPES.has(ty):
					fake.append("%s:%s" % [str(pd.get("id", "")), ty])
	_ok("★★每只龟的签名技都能被选到(playable_indices 含 1)", miss.is_empty(), "缺: %s" % str(miss))
	_ok("★标了 impl 的招都在战斗分派表里(不许为了过门禁乱标)", fake.is_empty(), str(fake))
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
