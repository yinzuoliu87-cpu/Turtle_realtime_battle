extends Node
## verify_two_head_strike.gd — 双头技1(用户2026-07-11重设计)自证
##   远程灵能冲击炮弹爆炸: 200码内敌 1A+10%maxHp物理·圈外0(半径截断)
##   近战锤击落地: 目标受1.4A物理·双头获50%伤害盾
##   ★2026-10-20 锤击改范围(用户「这样，改为aoe」「范围200码」): 以锤头落点(TwoHeadSystem.hammer_point)为圆心
##     STRIKE_MELEE_RADIUS 内每个敌人各吃 1.4A 物理(各算各的护甲)、圈外 0; 护盾只按主目标那一下 × 50%(不随人数叠加)
##   炮弹飞行/跳跃弧线观感由用户 F5(走tween/async·headless不推进)

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0
func _ok(n,c,d=""):
	if c: print("  [PASS] ",n,("  "+d) if d!="" else "")
	else: _fail+=1; print("  [FAIL] ",n,"  ",d)

func _ready() -> void:
	await get_tree().process_frame
	var gs=get_node_or_null("/root/GameState")
	if gs!=null: gs.test_mode=true
	var sc=RTScene.new(); add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	sc.set_process(false); sc.set_physics_process(false)
	sc._units.clear(); sc._t=0.0; sc._over=false; sc._edit_mode=false

	var dh: Dictionary = sc._spawn._make_unit("two_head","left",Vector2(200,400))
	dh["atk"]=100.0; dh["crit"]=0.0; dh["armor_pen"]=0.0; dh["armor_pen_pct"]=0.0; dh["damage_amp"]=0.0
	dh["shield"]=0.0
	sc._units.append(dh)
	var land := Vector2(700.0,400.0)
	var near1: Dictionary = sc._spawn._make_unit("basic","right",Vector2(700,400))   # 距land 0
	var near2: Dictionary = sc._spawn._make_unit("basic","right",Vector2(850,400))   # 距land 150 (圈内)
	var far1: Dictionary = sc._spawn._make_unit("basic","right",Vector2(950,400))    # 距land 250 (圈外)
	for d in [near1,near2,far1]:
		d["def"]=0.0; d["base_def"]=0.0; d["damage_reduction"]=0.0; d["shield"]=0.0
		d["maxHp"]=1000.0; d["hp"]=1000.0; d["no_basic"]=true; d["no_move"]=true; d["_st_taken"]=0
		sc._units.append(d)

	# ── 灵能冲击炮弹爆炸(直接调 boom = 炮弹碰敌后的结算) ──
	# 每敌 = _atk_dmg(100,1.0,def0)=100 + 10%maxHp(1000)×补偿 1.5(def0 不减)=150 → 250
	# ★「+10% 最大生命」段真吃护甲(2026-10-11); ×1.5 隐藏补偿 10-16 已删(用户「删」), 按文案数值打
	sc._two_head_sys._two_head_cannon_boom(dh, land)
	var _want: int = 100 + int(round(1000.0 * TwoHeadSystem.STRIKE_RANGED_MAXHP))
	_ok("圈内(≤200码)敌受伤 %d(1A+10%%maxHp×补偿·0 护甲)" % _want, int(near1["_st_taken"])==_want and int(near2["_st_taken"])==_want, "n1=%d n2=%d"%[int(near1["_st_taken"]),int(near2["_st_taken"])])
	_ok("★圈外(>200码)敌 0(半径截断)", int(far1["_st_taken"])==0, "far=%d"%int(far1["_st_taken"]))

	# ── 近战锤击落地(直接调 land 结算) ──
	near1["hp"]=1000.0; near1["_st_taken"]=0
	dh["shield"]=0.0
	sc._two_head_sys._two_head_hammer_land(dh, near1, near1["pos"], 140)
	_ok("锤击目标受伤 140", int(near1["_st_taken"])==140, "taken=%d"%int(near1["_st_taken"]))
	_ok("锤击双头获50%伤害盾(70)", int(round(float(dh["shield"])))==70, "shield=%.0f"%float(dh["shield"]))

	# ── 锤击范围(2026-10-20): 圆心 = 锤头落点, 半径边界两侧各放一只 ──
	for u in sc._units.duplicate():
		if str(u.get("side", "")) == "right":
			sc._units.erase(u)
	var L := Vector2(500.0, 400.0)
	dh["face_right"] = true; dh["shield"] = 0.0
	var H: Vector2 = TwoHeadSystem.hammer_point(L, true)
	var R: float = TwoHeadSystem.STRIKE_MELEE_RADIUS
	var spots := {
		"主目标": [H + Vector2(11.0, 0.0), true, 0.0],
		"圈内·上方": [H + Vector2(0.0, -R * 0.6), true, 0.0],
		"圈内·边内5码": [H + Vector2(R - 5.0, 0.0), true, 0.0],
		"圈内·斜向·带护甲": [H + Vector2(-R * 0.5, R * 0.5), true, 50.0],
		"圈外·边外5码": [H + Vector2(R + 5.0, 0.0), false, 0.0],
		"圈外·远": [H + Vector2(0.0, R * 1.6), false, 0.0],
	}
	var mk := {}
	for k in spots:
		var e: Dictionary = sc._spawn._make_unit("basic", "right", spots[k][0])
		e["def"] = float(spots[k][2]); e["base_def"] = float(spots[k][2]); e["damage_reduction"] = 0.0; e["shield"] = 0.0
		e["maxHp"] = 5000.0; e["hp"] = 5000.0; e["no_basic"] = true; e["no_move"] = true; e["_st_taken"] = 0
		sc._units.append(e)
		mk[k] = e
	var main_dmg: int = 140
	sc._two_head_sys._two_head_hammer_land(dh, mk["主目标"], L, main_dmg)
	var in_n := 0; var in_hit := 0; var out_n := 0; var out_zero := 0; var lines := []
	for k in spots:
		var got: int = int(mk[k]["_st_taken"])
		lines.append("%s=%d" % [k, got])
		if bool(spots[k][1]):
			in_n += 1
			var want: int = main_dmg if k == "主目标" else int(sc._atk_dmg(dh, TwoHeadSystem.STRIKE_MELEE_COEF, mk[k]))
			if got == want and got > 0:
				in_hit += 1
		else:
			out_n += 1
			if got == 0:
				out_zero += 1
	_ok("分母: 圈内 ≥ 4 只(含边内 5 码与带护甲的)、圈外 ≥ 2 只(含边外 5 码)", in_n >= 4 and out_n >= 2, "圈内 %d · 圈外 %d" % [in_n, out_n])
	_ok("★锤击范围: 锤头落点 %.0f 码内每个敌人各吃一次 1.4A 物理(各算各的护甲)" % R, in_hit == in_n, "%d/%d · %s" % [in_hit, in_n, ", ".join(lines)])
	_ok("★锤击范围: 圈外(含边外 5 码)不吃", out_zero == out_n, "%d/%d" % [out_zero, out_n])
	_ok("分母: 带护甲那只确实比 0 护甲的少吃(护甲真的参与了)", int(mk["圈内·斜向·带护甲"]["_st_taken"]) < int(mk["圈内·上方"]["_st_taken"]) and int(mk["圈内·斜向·带护甲"]["_st_taken"]) > 0,
		"带甲 %d · 无甲 %d" % [int(mk["圈内·斜向·带护甲"]["_st_taken"]), int(mk["圈内·上方"]["_st_taken"])])
	_ok("★护盾只按主目标那一下 × 50%(不随命中人数叠加)", int(round(float(dh["shield"]))) == int(round(main_dmg * TwoHeadSystem.STRIKE_SHIELD_PCT)),
		"护盾 %.0f · 主目标伤害 %d · 命中 %d 只" % [float(dh["shield"]), main_dmg, in_hit])

	print("")
	print(("ALL PASS — 双头技1 正常" if _fail==0 else "FAIL x%d"%_fail))
	get_tree().quit(1 if _fail>0 else 0)
