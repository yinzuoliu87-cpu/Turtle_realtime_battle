extends Node
## verify_two_head_strike.gd — 双头技1(用户2026-07-11重设计)自证
##   远程灵能冲击炮弹爆炸: 200码内敌 1A+10%maxHp物理·圈外0(半径截断)
##   近战锤击落地: 目标受1.4A物理·双头获50%伤害盾
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

	var dh: Dictionary = sc._make_unit("two_head","left",Vector2(200,400))
	dh["atk"]=100.0; dh["crit"]=0.0; dh["armor_pen"]=0.0; dh["armor_pen_pct"]=0.0; dh["damage_amp"]=0.0
	dh["shield"]=0.0
	sc._units.append(dh)
	var land := Vector2(700.0,400.0)
	var near1: Dictionary = sc._make_unit("basic","right",Vector2(700,400))   # 距land 0
	var near2: Dictionary = sc._make_unit("basic","right",Vector2(850,400))   # 距land 150 (圈内)
	var far1: Dictionary = sc._make_unit("basic","right",Vector2(950,400))    # 距land 250 (圈外)
	for d in [near1,near2,far1]:
		d["def"]=0.0; d["base_def"]=0.0; d["damage_reduction"]=0.0; d["shield"]=0.0
		d["maxHp"]=1000.0; d["hp"]=1000.0; d["no_basic"]=true; d["no_move"]=true; d["_st_taken"]=0
		sc._units.append(d)

	# ── 灵能冲击炮弹爆炸(直接调 boom = 炮弹碰敌后的结算) ──
	# 每敌 = _atk_dmg(100,1.0,def0)=100 + 10%maxHp(1000)=100 → 200
	sc._two_head_cannon_boom(dh, land)
	_ok("圈内(≤200码)敌受伤 200(1A+10%maxHp)", int(near1["_st_taken"])==200 and int(near2["_st_taken"])==200, "n1=%d n2=%d"%[int(near1["_st_taken"]),int(near2["_st_taken"])])
	_ok("★圈外(>200码)敌 0(半径截断)", int(far1["_st_taken"])==0, "far=%d"%int(far1["_st_taken"]))

	# ── 近战锤击落地(直接调 land 结算) ──
	near1["hp"]=1000.0; near1["_st_taken"]=0
	dh["shield"]=0.0
	sc._two_head_hammer_land(dh, near1, near1["pos"], 140)
	_ok("锤击目标受伤 140", int(near1["_st_taken"])==140, "taken=%d"%int(near1["_st_taken"]))
	_ok("锤击双头获50%伤害盾(70)", int(round(float(dh["shield"])))==70, "shield=%.0f"%float(dh["shield"]))

	print("")
	print(("ALL PASS — 双头技1 正常" if _fail==0 else "FAIL x%d"%_fail))
	get_tree().quit(1 if _fail>0 else 0)
