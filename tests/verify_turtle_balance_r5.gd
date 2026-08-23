extends Node
## verify_turtle_balance_r5.gd — 第五轮龟平衡 + 对照环境修正 (用户 2026-07-29 夜)
##
## 方案书: docs/plans/20260730-第五轮龟平衡.md
##
## ★期望值一律写【用户口述的字面需求值】，不从代码常量读回来 ——
##   拿代码跟它自己比是恒真式；verify_trainer_magicstone 曾经就是这样，把常量改坏照样 ALL PASS。
##
## 查四组：
##   ① 对照环境 —— NO_TRAINER 开关存在 + _duel.gd 真的设上 + 首场体检会因大师>0 而停
##      （由来：_duel.gd 第20行「关训龟大师」写了四轮，代码里从来没有关它的地方）
##   ② 小将 —— 前后排拆开且写【最终值】（不许再有 ×3 / ×1.5 补丁倍率）
##   ③ 4 个削弱 + 7 个加强的数值
##   ④ 两处「本轮故意不动」的焊死（水晶壁垒锁龟能 / 双头 −30% 攻击惩罚）——
##      它们是下一轮的判据：若第五轮仍垫底即确认根因在此，所以本轮必须保证没被顺手改掉
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_turtle_balance_r5.tscn

# ── 需求值 ──
const WANT_FRONT := {"hp": 850, "atk": 45, "def": 13, "mr": 13}
const WANT_BACK := {"hp": 770, "atk": 55, "def": 9, "mr": 9}
const WANT_BOMB_ENERGY := 120.0
const WANT_BOMB_DEFDOWN := 0.20
const WANT_STORM_CURSE := 4.0
const WANT_SLAM_ATK := 1.0
const WANT_SLAM_HPMUL := 0.002        # 0.2% × ATK × 最大生命
const WANT_SPLASH_ATK := 0.3
const WANT_SPLASH_HPMUL := 0.0013     # 0.13% × ATK × 主目标最大生命
const WANT_CHIWAVE := 2.0
const WANT_DICE_MIN := 5
const WANT_DICE_HEAL := 0.15
const WANT_ALLIN_COIN := 0.30
const WANT_BUYEQUIP_FIRST := 10.0
const WANT_FUSION_ENERGY := 85.0
const WANT_BUBBLE_MAGIC_MULT := 1.5
const WANT_BUBBLE_PHYS := 1.5
const WANT_CRYSTAL_POP := 0.22
const WANT_BURST_MAGIC := 1.2         # 三段合计 (每段 0.4)
const WANT_BURST_TRUE := 1.2
const WANT_SPIKE_TRUE := 1.5

var _fail := 0
var _S := {}


func _ready() -> void:
	print("=== 第五轮龟平衡 + 对照环境修正 ===")
	for k in ["res://scripts/gamedata/phase2_minion.gd",
			"res://scripts/systems/skill_energy.gd",
			"res://scripts/systems/skills/ninja_system.gd",
			"res://scripts/systems/skills/ghost_system.gd",
			"res://scripts/systems/skills/fortune_system.gd",
			"res://scripts/systems/skills/bubble_system.gd",
			"res://scripts/systems/skills/crystal_system.gd",
			"res://scripts/systems/skills/two_head_system.gd",
			"res://scripts/systems/skills/ice_system.gd",
			"res://scripts/scenes/RealtimeBattle3DScene.gd",
			"res://scripts/scenes/battle/battle_spawn.gd",
			"res://tests/_duel.gd"]:
		_S[k.get_file()] = FileAccess.get_file_as_string(k)
	var tot := 0
	for v in _S.values():
		tot += str(v).length()
	print("  ★分母: 读到 %d 份源码 / %d 字符" % [_S.size(), tot])
	_chk("★分母: 十二份源码都非空", _S.size() == 12 and tot > 250000)

	_env()
	_minion()
	_nerfs()
	_buffs()
	_frozen()

	if _fail == 0:
		print("ALL PASS — 第五轮龟平衡")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)


## ① 对照环境: 训龟大师必须关得掉, 而且 _duel.gd 真的关了
func _env() -> void:
	print("  ── ① 对照环境(前四轮的隐形污染) ──")
	var rb: String = _S["RealtimeBattle3DScene.gd"]
	var sp: String = _S["battle_spawn.gd"]
	var du: String = _S["_duel.gd"]
	_chk("① NO_TRAINER 开关存在", rb.contains("static var NO_TRAINER := false"))
	_chk("① _spawn_trainers 认这个开关",
		sp.contains('OS.has_environment("NO_TRAINER")') and sp.contains("battle.NO_TRAINER"))
	_chk("① _duel.gd 真的设上了(注释写了四轮都没设)", du.contains("RB.NO_TRAINER = true"))
	# ★不只查"设了", 还要查【首场体检会因此停】—— 注释骗过四轮, 所以要它自己证明
	_chk("① _duel.gd 首场体检统计训龟大师数", du.contains('u.get("is_trainer", false)') and du.contains("训龟大师在场"))
	_chk("① ★大师 >0 直接 quit(1)(不许只打印不停)",
		du.contains("if tr > 0:") and du.contains("get_tree().quit(1)"))


## ② 小将: 前后排拆开 + 写最终值(不许有补丁倍率)
func _minion() -> void:
	print("  ── ② 小将(常量写最终值) ──")
	var m: String = _S["phase2_minion.gd"]
	for k in WANT_FRONT.keys():
		_chk("② 前排 %s = %d" % [k, int(WANT_FRONT[k])],
			m.contains("const FRONT_%s := %d" % [k.to_upper(), int(WANT_FRONT[k])]))
	for k in WANT_BACK.keys():
		_chk("② 后排 %s = %d" % [k, int(WANT_BACK[k])],
			m.contains("const BACK_%s := %d" % [k.to_upper(), int(WANT_BACK[k])]))
	# ★用户 2026-07-29:「别搞这种补丁倍率，直接以最终值」
	_chk("② ★没有 ×3 补丁倍率(旧: BASE_HP 250 × 3)", not m.contains("BASE_HP * m)) * 3"))
	_chk("② ★没有 ×1.5 补丁倍率(旧: BASE_ATK 30 × 1.5)", not m.contains("BASE_ATK * m * 1.5"))
	_chk("② ★旧的共用基数常量已消失", not m.contains("const BASE_HP :=") and not m.contains("const BASE_ATK :="))


func _nerfs() -> void:
	print("  ── ③ 削弱 ──")
	var se: String = _S["skill_energy.gd"]
	var nj: String = _S["ninja_system.gd"]
	var gh: String = _S["ghost_system.gd"]
	var rb: String = _S["RealtimeBattle3DScene.gd"]
	_chk("③ 忍者炸弹龟能 = %d" % int(WANT_BOMB_ENERGY), se.contains('"ninjaBomb": %.1f' % WANT_BOMB_ENERGY))
	_chk("③ 忍者炸弹旧值 100 已消失", not se.contains('"ninjaBomb": 100.0'))
	_chk("③ 忍者炸弹破甲 = %d%%" % int(WANT_BOMB_DEFDOWN * 100.0),
		nj.contains('"defDown": %.2f' % WANT_BOMB_DEFDOWN))
	_chk("③ 忍者炸弹破甲旧值 0.25 已消失", not nj.contains('"defDown": 0.25'))
	_chk("③ 灵魂风暴诅咒 = %.1f 秒" % WANT_STORM_CURSE,
		gh.contains("const STORM_CURSE_SEC := %.1f" % WANT_STORM_CURSE))
	_chk("③ 灵魂风暴诅咒旧值 6.0 已消失", not gh.contains("const STORM_CURSE_SEC := 6.0"))
	# 过肩摔: 新公式是【乘法结构】(ATK × 最大生命), 不再是纯 %最大生命
	_chk("③ 过肩摔主目标 = %.1fA + %.1f%%×ATK×最大生命" % [WANT_SLAM_ATK, WANT_SLAM_HPMUL * 100.0],
		## ★比【常量的值】不比源码字面串(2026-08-22 根除已提成具名常量)
		is_equal_approx(BasicConsts.SLAM_MAIN_ATK, WANT_SLAM_ATK)
			and is_equal_approx(BasicConsts.SLAM_MAIN_HP_PER_ATK, WANT_SLAM_HPMUL))
	_chk("③ 过肩摔周围 = %.1fA + %.2f%%×ATK×主目标最大生命" % [WANT_SPLASH_ATK, WANT_SPLASH_HPMUL * 100.0],
		is_equal_approx(BasicConsts.SLAM_SPLASH_ATK, WANT_SPLASH_ATK)
			and is_equal_approx(BasicConsts.SLAM_SPLASH_HP_PER_ATK, WANT_SPLASH_HPMUL))
	_chk("③ 过肩摔旧的纯%最大生命公式已消失",
		not rb.contains("int(tmax * 0.23)") and not rb.contains("int(tmax * 0.18)"))
	_chk("③ 龟派气波 = %.1fA" % WANT_CHIWAVE, is_equal_approx(BasicConsts.CHI_ATK_COEF, WANT_CHIWAVE))
	_chk("③ 龟派气波旧值 3.0 已消失", not is_equal_approx(BasicConsts.CHI_ATK_COEF, 3.0))


func _buffs() -> void:
	print("  ── ④ 加强 ──")
	var se: String = _S["skill_energy.gd"]
	var fo: String = _S["fortune_system.gd"]
	var bu: String = _S["bubble_system.gd"]
	var cr: String = _S["crystal_system.gd"]
	var rb: String = _S["RealtimeBattle3DScene.gd"]
	_chk("④ 财神骰子金币 = %d~8" % WANT_DICE_MIN, fo.contains("randi_range(%d, 8)" % WANT_DICE_MIN))
	_chk("④ 财神骰子回血 = %d%%" % int(WANT_DICE_HEAL * 100.0),
		fo.contains('u["maxHp"] * %.2f' % WANT_DICE_HEAL))
	_chk("④ 财神骰子旧值 (3,8)/0.10 已消失",
		not fo.contains("randi_range(3, 8)") and not fo.contains('u["maxHp"] * 0.10'))
	_chk("④ 梭哈每枚物理 = %.2fA" % WANT_ALLIN_COIN, rb.contains("_atk_dmg(src, %.2f, tgt, false)" % WANT_ALLIN_COIN))
	_chk("④ 梭哈每枚真伤 = %.2fA" % WANT_ALLIN_COIN, rb.contains('"coin_true": int(src["atk"] * %.2f)' % WANT_ALLIN_COIN))
	_chk("④ 梭哈旧值 0.18 已消失", not rb.contains("_atk_dmg(src, 0.18, tgt, false)"))
	# ★首释价 = skill_energy 的基准值; 升星价 120/180/300 是抽完之后才改写的, 别混
	_chk("④ 招财进宝【首释】龟能 = %d" % int(WANT_BUYEQUIP_FIRST),
		se.contains('"fortuneBuyEquip": %.1f' % WANT_BUYEQUIP_FIRST))
	_chk("④ 招财进宝升星价仍是 120/180/300(本轮不动)", fo.contains("60.0 + [60.0, 120.0, 240.0]"))
	_chk("④ 融合魔法波龟能 = %d" % int(WANT_FUSION_ENERGY), se.contains('"twoHeadFusion": %.1f' % WANT_FUSION_ENERGY))
	_chk("④ 融合旧值 125 已消失", not se.contains('"twoHeadFusion": 125.0'))
	_chk("④ 泡泡爆破魔法 = 消耗量 ×%.1f / 物理 = %.1fA" % [WANT_BUBBLE_MAGIC_MULT, WANT_BUBBLE_PHYS],
		bu.contains("cons * %.1f" % WANT_BUBBLE_MAGIC_MULT) and bu.contains("_atk_dmg(uu, %.1f, o)" % WANT_BUBBLE_PHYS))
	_chk("④ 泡泡爆破旧值(×1.0 + 0.8A) 已消失", not bu.contains("_atk_dmg(uu, 0.8, o)"))
	## ★2026-08-20 判据升级: 原来查源码里有没有 `tgt["maxHp"] * 0.22` 这个**字面量**。
	##   那个魔数已提成具名常量 `BURST_MAXHP_PCT`(为了让文案能用 {C:...} 引用它),
	##   所以改成**验那个常量的值 + 确认代码真的在用它** —— 比验字面量更强:
	##   字面量版只要有人把 0.22 抄到别处也算过, 常量版盯的是唯一那一份。
	_chk("④ 水晶引爆 = %d%% 目标最大生命(常量值)" % int(WANT_CRYSTAL_POP * 100.0),
		cr.contains("const BURST_MAXHP_PCT := %.2f" % WANT_CRYSTAL_POP))
	_chk("④ 引爆真的在用那个常量(不是又抄了一个字面量)",
		cr.contains('tgt["maxHp"] * BURST_MAXHP_PCT'))
	_chk("④ 水晶引爆旧值 0.19 已消失", not cr.contains('tgt["maxHp"] * 0.19'))
	_chk("④ 碎晶三段合计 = %.1fA 魔 + %.1fA 真(每段 0.4+0.4)" % [WANT_BURST_MAGIC, WANT_BURST_TRUE],
		cr.contains("const BURST_MAGIC := %.1f" % WANT_BURST_MAGIC)
		and cr.contains("const BURST_TRUE := %.1f" % WANT_BURST_TRUE))
	_chk("④ 碎晶旧值 0.8/0.3 已消失",
		not cr.contains("const BURST_MAGIC := 0.8") and not cr.contains("const BURST_TRUE := 0.3"))
	_chk("④ 水晶刺 = %.1fA 真实(原零伤害)" % WANT_SPIKE_TRUE,
		## ★比【常量的值】不比源码字面串(2026-08-22 根除已提成具名常量)
		is_equal_approx(CrystalSystem.SPIKE_TRUE_COEF, WANT_SPIKE_TRUE))


## ⑤ 两处「本轮故意不动」—— 它们是下一轮的判据, 必须保证没被顺手改掉
func _frozen() -> void:
	print("  ── ⑤ 本轮故意不动的(下一轮判据) ──")
	var rb: String = _S["RealtimeBattle3DScene.gd"]
	var th: String = _S["two_head_system.gd"]
	_chk("⑤ ★水晶壁垒仍然锁龟能(数据信号最强·下轮若仍垫底即确认根因在此)",
		rb.contains('u.get("_bulwark_armed", false)') and rb.contains("水晶壁垒: 持盾期锁龟能"))
	_chk("⑤ ★双头近战攻击惩罚仍是 0.30(第四轮加血无效已指向它)",
		is_equal_approx(TwoHeadSystem.MELEE_ATK_PENALTY, 0.30))   # ★比【常量的值】不比源码里的字面量: 后者把写法焊死, 挡的是正常重构(2026-08-22 文案根除把它提成了具名常量)
	# 冰霜特效重做: 三张【新生成】素材必须在位(用户「别复用，自己搞新的」)
	var ic: String = _S["ice_system.gd"]
	for tex in ["frost-icicle-fall", "frost-field-ground", "frost-chip"]:
		_chk("⑤ 冰霜新素材 %s 在位" % tex,
			ic.contains(tex) and FileAccess.file_exists("res://assets/sprites/vfx/%s.png" % tex))
	_chk("⑤ 冰霜用上了 GPU 粒子(不是图片平移)", ic.contains("GPUParticles3D"))
	_chk("⑤ 冰霜坠落是加速的(TRANS_QUAD/EASE_IN·旧版线性)",
		ic.contains("set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)"))


func _chk(name: String, ok: bool) -> void:
	print("  [%s] %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fail += 1
