extends Node
## 装备演示台录像(不是门禁, 2026-11-24)。用户 11-24:「我不建议你这么去录…一整把一整把录…我们应该专门的这个演示台…去录视频」
##   「在小台上，你能摆放一个友方单位…可以是小龟，可以是任何召唤物。同样，我们有个敌方的靶子…观察特效会很方便」。
## 走真调试场(DEBUG_EDIT): 按 CASES 里那一条写好摆位存档(单独存档目录里的 user://debug_setup.json) → 进调试场(自动恢复摆位)
##   → 折叠编辑面板 → 点「开始」同一个入口(_edit_start_battle) → 录 REC_SEC 秒收工。
## 跑法(右屏、静音、单独存档目录; 一条一段):
##   APPDATA=<目录> XDG_DATA_HOME=<目录> SHIP=1 TURTLE_SUPABASE=" " TURTLE_BACKEND=" " REC_CASE=cracker WINDOW=1 \
##     bash godot-quiet.sh --path . --resolution 1280x720 --position 2000,80 --write-movie <输出>/cracker.avi --fixed-fps 30 \
##     res://tests/_rec_eq_stage.tscn
## 摆位: 场地中心 (868,474); 我方在左、靶子在右。字段同调试场存档: id / side / px / py / hp / killable / equips / minion / role /
##   ghost_eq(召唤物笔刷: 隐形携带者带这件) / ai(敌方会动会打) / fe(满龟能)。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const C := Vector2(868, 474)


static func _eq(ids: Array, star: int = 3) -> Array:
	var a: Array = []
	for i in ids:
		a.append({"id": "p2eq_%03d" % int(i), "star": star})
	return a


static func _u(id: String, side: String, d: Vector2, extra: Dictionary = {}) -> Dictionary:
	var u := {"id": id, "side": side, "px": C.x + d.x, "py": C.y + d.y, "hp": 6000.0, "killable": side == "left", "equips": []}
	u.merge(extra, true)
	return u


## 我方携带者: 近战小将, 只会普攻(清掉技能; 小将本来就没有被动) —— 用户 11-24「友方带一件这件装备…只能攻击，不应该有任何除了攻击以外的东西」
static func _me(d: Vector2, eq: Array, extra: Dictionary = {}) -> Dictionary:
	var u := _u("__minion__", "left", d, {"minion": true, "role": "front", "level": 1, "plain": true, "equips": eq, "hp": 8000.0, "killable": false})
	u.merge(extra, true)
	return u


## 靶子: 小将身板(不带任何被动)、站桩、打不死; `n` = 1 只或 3 只(范围类看半径)
static func _dummies(dx: float = 80.0, n: int = 3, ai: bool = false, hp: float = 20000.0, atk: float = 0.0) -> Array:
	var o: Array = []
	var spots := [Vector2(dx, 0), Vector2(dx + 70, -70), Vector2(dx + 70, 70)]
	for i in range(n):
		o.append(_u("__minion__", "right", spots[i], {"minion": true, "role": "front", "level": 1, "plain": true, "hp": hp, "killable": ai, "ai": ai, "atk": atk}))
	return o


## 靶子按给定偏移围着某点摆
static func _ring_dummies(at: Vector2, offs: Array) -> Array:
	var o: Array = []
	for d in offs:
		o.append(_u("__minion__", "right", at + Vector2(d), {"minion": true, "role": "front", "level": 1, "plain": true, "hp": 20000.0, "killable": false}))
	return o


## 每条: [摆位, 录几秒]
static func cases() -> Dictionary:
	return {
		## 羁绊: 持有人不动不打(只为凑 3 件炸弹 = 1 档), 只看导弹本身
		"missile": [[_me(Vector2(-300, 0), _eq([102, 103, 97]), {"idle": true})] + _dummies(60, 3) + [_u("__minion__", "right", Vector2(280, 0), {"minion": true, "plain": true, "hp": 20000.0, "killable": false})], 15.0],
		"cracker": [[_me(Vector2(-10, 0), _eq([97]))] + _dummies(60, 3), 12.0],
		## 爆竹筒范围 120 码: 三个靶子围在携带者 70~85 码内(都在范围里, 看得出一圈都被击退)
		"tube": [[_me(Vector2(-10, 0), _eq([98]))] + _ring_dummies(Vector2(-10, 0), [Vector2(70, 0), Vector2(30, -78), Vector2(30, 78)]), 16.0],
		## 手雷: 携带者站在远处不动(看得到一道弧线扔过去)
		"grenade": [[_me(Vector2(-280, 0), _eq([99]), {"hold": true})] + _dummies(60, 3), 16.0],
		## 烟雾弹: 两只会打的敌人冲过来, 看它们选不中烟里的我方
		"smoke": [[_me(Vector2(-200, -40), _eq([100]), {"hold": true}), _me(Vector2(-200, 60), [], {"hold": true})] + _dummies(150, 2, true, 8000.0, 60.0), 20.0],
		"sticky": [[_me(Vector2(-10, 0), _eq([101]))] + _dummies(60, 3), 20.0],
		## 地雷: 我方站住, 两只会动的敌人走过来踩雷
		"mine": [[_me(Vector2(-400, 0), _eq([102]), {"hold": true})] + _dummies(250, 2, true, 20000.0, 30.0), 14.0],
		## 炸药桶: 我方站住、血少, 会打的敌人把它打死
		## 炸药桶: 我方站住、血少, 会打的敌人把它打死; 后面再放一只不动不打、打不死的小将 —— 否则携带者一死我方全灭、立刻弹结算盖住爆炸
		"barrel": [[_me(Vector2(-10, 0), _eq([103]), {"hold": true, "hp": 400.0, "killable": true}), _me(Vector2(-420, 160), [], {"idle": true})] + _dummies(60, 3, true, 20000.0, 300.0), 14.0],
		"timer": [[_me(Vector2(-10, 0), _eq([104]))] + _dummies(60, 3), 23.0],
		"cannon": [[_u("__summon__", "left", Vector2(-40, 0), {"ghost_eq": "p2eq_105", "equips": _eq([105]), "minion": true, "fe": true})] + _dummies(160, 3), 14.0],
		## 正常情况(不给满龟能): 从 0 攒, 看头顶龟能条怎么涨 → 满了进重炮 → 一发发往下掉(用户 11-24「给我看看正常情况这个龟能条怎么变」)
		"cannon_norm": [[_u("__summon__", "left", Vector2(-40, 0), {"ghost_eq": "p2eq_105", "equips": _eq([105], 3), "minion": true})] + _dummies(160, 3), 40.0],
		"cannon_norm1": [[_u("__summon__", "left", Vector2(-40, 0), {"ghost_eq": "p2eq_105", "equips": _eq([105], 1), "minion": true})] + _dummies(160, 3), 46.0],
		"cannon_norm2": [[_u("__summon__", "left", Vector2(-40, 0), {"ghost_eq": "p2eq_105", "equips": _eq([105], 2), "minion": true})] + _dummies(160, 3), 70.0],
		"remote": [[_u("__summon__", "left", Vector2(-300, 0), {"ghost_eq": "p2eq_106", "equips": _eq([106], 1), "minion": true})] + _dummies(150, 3), 14.0],
		"katana": [[_u("__summon__", "left", Vector2(-160, 0), {"ghost_eq": "p2eq_107", "equips": _eq([107]), "minion": true, "fe": true})] + _dummies(60, 3), 16.0],
		## 看动作(配 REC_ZOOM): 三个不动的靶子竖着隔开站, 小将走过去打, 不被挤住挡住动作
		"katana_show": [[_u("__summon__", "left", Vector2(-220, 0), {"ghost_eq": "p2eq_107", "equips": _eq([107]), "minion": true, "fe": true})]
			+ _ring_dummies(Vector2(-220, 0), [Vector2(300, 0), Vector2(380, -120), Vector2(380, 120)]), 21.0],
		## 敌人会走过来打小将(掉点血) ⇒ 第 4 下蓄力回血看得见
		"katana_hit": [[_u("__summon__", "left", Vector2(-160, 0), {"ghost_eq": "p2eq_107", "equips": _eq([107]), "minion": true, "fe": true})] + _dummies(150, 3, true, 20000.0, 40.0), 19.0],
		## ── 匕首批(11-25) ──
		## 羁绊【刺杀】二档: 携带者凑 6 件不同匕首(108/109/110/111/112/113), 旁边两只不带装备的友方 —— 开打和第 10 秒全队头顶各闪一次, 下一下普攻猩红长斩
		"assassin": [[_me(Vector2(-10, 0), _eq([108, 109, 110, 111, 112, 113], 1)), _me(Vector2(-10, -90), []), _me(Vector2(-10, 90), [])] + _dummies(60, 3), 16.0],
		"fold": [[_me(Vector2(-10, 0), _eq([108]))] + _dummies(60, 3), 6.0],
		## 柳叶飞刀: 携带者站远处不动, 靶子一前一后排成一条 —— 看飞刀只打中途经的第一个
		"knife": [[_me(Vector2(-320, 0), _eq([109]), {"hold": true})] + _ring_dummies(Vector2(0, 0), [Vector2(40, 0), Vector2(200, 0), Vector2(120, -110)]), 14.0],
		"kunai": [[_me(Vector2(-260, 0), _eq([110]), {"hold": true, "hp": 6000.0})] + _dummies(60, 3), 12.0],
		## 毒牙要暴击才触发: 同时带 116(3 星 50% 暴击)
		"fang": [[_me(Vector2(-10, 0), _eq([111, 116]))] + _dummies(60, 3), 12.0],
		"pierce": [[_me(Vector2(-10, 0), _eq([112]))] + _dummies(60, 3), 6.0],
		## 弯匕 / 仪式: 靶子血少、打得死(击杀后攻速暴涨 / 斩杀 + 刻血契)
		"kris": [[_me(Vector2(-10, 0), _eq([113]))] + _ring_dummies(Vector2(-10, 0), [Vector2(70, 0), Vector2(110, -80), Vector2(110, 80)]).map(func(x): x["hp"] = 700.0; x["killable"] = true; return x), 12.0],
		"ritual": [[_me(Vector2(-10, 0), _eq([114]))] + _ring_dummies(Vector2(-10, 0), [Vector2(70, 0), Vector2(110, -80), Vector2(110, 80)]).map(func(x): x["hp"] = 350.0; x["killable"] = true; return x), 14.0],
		"obs": [[_me(Vector2(-10, 0), _eq([116]))] + _dummies(60, 3, false, 4000.0).map(func(x): x["killable"] = true; return x), 14.0],
		## 暗影忍者: 满龟能开局(马上看影袭); 两只会打的敌人把它打到半血 ⇒ 分影子 ⇒ 下一次影袭两名忍者一起掷手里剑
		"ninja": [[_u("__summon__", "left", Vector2(-220, 0), {"ghost_eq": "p2eq_115", "equips": _eq([115]), "minion": true, "fe": true})]
			+ _dummies(150, 3, true, 30000.0, 450.0), 24.0],
		## ── 魔法书批(11-25) ── 施法类要真的放技能: 携带者用天使龟(远程) / 钻石龟(近战) —— 熔岩龟自己的技能特效太大, 盖住魔法书的东西, 满龟能开局
		## 羁绊【飞弹】: 三本不同的魔法书放在一只不动不打的小将身上(凑 1 档), 天使龟空手放技能 ⇒ 飞弹从天使龟身上飞出
		"mb_missile": [[_me(Vector2(-380, 160), _eq([117, 118, 121], 1), {"idle": true}), _u("angel", "left", Vector2(-260, 0), {"fe": true, "hp": 8000.0, "killable": false})]
			+ _dummies(80, 3), 14.0],
		"mb_note": [[_me(Vector2(-10, 0), _eq([117]))] + _dummies(80, 3), 10.0],
		"mb_scroll": [[_u("angel", "left", Vector2(-200, 0), {"fe": true, "equips": _eq([118]), "hp": 8000.0, "killable": false})] + _dummies(80, 3), 10.0],
		"mb_fire": [[_u("angel", "left", Vector2(-260, 0), {"fe": true, "equips": _eq([119]), "hp": 8000.0, "killable": false})] + _dummies(80, 3), 12.0],
		## 冰霜新星 300 码: 靶子围在携带者 150~250 码(圈里), 再放一只 420 码外(圈外不挨)
		"mb_frost": [[_u("diamond", "left", Vector2(-10, 0), {"fe": true, "equips": _eq([120]), "hp": 8000.0, "killable": false})]
			+ _ring_dummies(Vector2(-10, 0), [Vector2(150, 0), Vector2(120, -150), Vector2(120, 150), Vector2(420, 0)]), 12.0],
		"mb_storm": [[_me(Vector2(-260, 0), _eq([121]), {"hold": true})] + _dummies(80, 3), 14.0],
		## 治愈圣典: 旁边站一只半血的友方(生命比例最低 ⇒ 挂在它身上)
		"mb_holy": [[_u("angel", "left", Vector2(-260, 0), {"fe": true, "equips": _eq([122]), "hp": 8000.0, "killable": false}), _me(Vector2(-260, 130), [], {"idle": true, "hp_pct": 0.4, "killable": true})]
			+ _dummies(80, 3), 14.0],
		## 亡者之书: 两次技能召两具(随机种类), 敌人会打 ⇒ 骷髅有对手
		"mb_skel": [[_u("angel", "left", Vector2(-170, 0), {"fe": true, "equips": _eq([123]), "hp": 8000.0, "killable": false})]
			+ _ring_dummies(Vector2(-170, 0), [Vector2(320, -90), Vector2(380, 40), Vector2(300, 150)]), 30.0],
		"mb_mirror": [[_u("angel", "left", Vector2(-260, 0), {"fe": true, "equips": _eq([124]), "hp": 8000.0, "killable": false})] + _dummies(80, 3), 12.0],
		"mb_forb": [[_u("angel", "left", Vector2(-260, 0), {"fe": true, "equips": _eq([125]), "hp": 8000.0, "killable": false})] + _dummies(80, 3), 12.0],
		## 近战书页: 只会站着的小将带(钻石龟自己的技能白光把书页盖住, 11-25 录像自查); 三只靶子正好站在书页转的那一圈上 ⇒ 看每张书页扫过才挨打
		"mb_tome_melee": [[_me(Vector2(-10, 0), _eq([126]), {"idle": true})]
			+ _ring_dummies(Vector2(-10, 0), [Vector2(120, 0), Vector2(-60, 104), Vector2(-60, -104)]), 12.0],
		## 远程书页格挡: 敌人一下打 ≥ 6% 最大生命(攻击力调高、携带者血量压到 3000 ⇒ 门槛 180) ⇒ 书页闪到身前挡
		"mb_tome_ranged": [[_u("angel", "left", Vector2(-260, 0), {"fe": true, "hold": true, "equips": _eq([126]), "hp": 3000.0, "killable": false})]
			+ _dummies(-60, 2, true, 30000.0, 700.0), 14.0],
		## ── 面具批(11-26) ──
		## 黄金面具: 一星, 三只会打的靶子各 2500 血 ⇒ 看金光钉一只到死 → 8 秒冷却 → 钉下一只
		"mk_gold": [[_me(Vector2(-260, 0), _eq([135], 1), {"hold": true})] + _dummies(80, 3, true, 2500.0, 0.0), 26.0],
		## 舞狮头: 舞狮冲撞(靶子会动会打)
		"mk_lion": [[_me(Vector2(-300, 0), _eq([130], 1), {"idle": true})] + _dummies(60, 3, true, 6000.0, 60.0), 22.0],
		## 千面: 第 8 秒拽一只进里世界; 9.5 秒自动点「观看里世界」, 15 秒切回主世界(REC_OW 自动点按钮)
		"mk_ow": [[_me(Vector2(-200, 0), _eq([136], 1)), _me(Vector2(-200, 150), [])] + _dummies(60, 3, true, 8000.0, 40.0), 24.0],
		## 威尼斯面具: 携带者 1500 血, 靶子攻击 400 ⇒ 很快被打倒 → 倒地 2.5 秒回到 30% → 继续
		"mk_venice": [[_me(Vector2(-60, 0), _eq([134], 1), {"hp": 1500.0, "killable": true})] + _dummies(60, 3, true, 30000.0, 250.0), 16.0],
		## 鬼面: 靶子打到它半血 ⇒ 潜行(半透明) → 攻击现形
		"mk_ghost": [[_me(Vector2(-60, 0), _eq([132], 1), {"hp": 3000.0, "killable": true})] + _dummies(60, 3, true, 30000.0, 120.0), 16.0],
		## 偷脸: 三件不同面具放在一只不动不打的小将身上(凑 1 档 ⇒ 每路偷 1 只); 敌人是会打的天使龟 + 两只靶子 ⇒ 看魂面具飞过去、复制体发蓝;
		##   复制体只有原版一半血, 被靶子打死 ⇒ 金绿光球飞向最近的友军
		"mk_steal": [[_me(Vector2(-300, 0), _eq([127, 128, 133], 1), {"idle": true}), _me(Vector2(-300, 150), [], {"idle": true})]
			+ [_u("angel", "right", Vector2(200, 0), {"hp": 3000.0, "killable": true, "ai": true})] + _dummies(60, 2, true, 6000.0, 160.0), 16.0],
		## 纸面具: 三只会打的靶子围着打 ⇒ 每一下都朝打它的那只掷一片纸刃
		"mk_paper": [[_me(Vector2(-60, 0), _eq([127], 1), {"hold": true})] + _dummies(60, 3, true, 30000.0, 60.0), 12.0],
		## 京剧脸谱: 18 秒 ⇒ 第 8 秒红→黑、第 16 秒黑→白; 红脸普攻冒红火花、白脸普攻偷龟能
		"mk_face": [[_me(Vector2(-60, 0), _eq([129], 1))] + _dummies(60, 3, false, 30000.0), 18.0],
		## 小丑面具: 天使龟满龟能开局放技能 ⇒ 附近敌人头上挂嘲笑小丑脸
		"mk_clown": [[_u("angel", "left", Vector2(-120, 0), {"fe": true, "equips": _eq([131], 1), "hp": 8000.0, "killable": false})] + _dummies(40, 3, true, 30000.0, 40.0), 10.0],
		## ── 长矛(11-26) ── 两只只会站着的小将各带 5 件不同的长矛 = 10 件 4 档; 百夫长第 8 秒登场
		"sp_cent": [[_me(Vector2(-380, -120), _eq([137, 138, 139, 140, 141], 1), {"idle": true}), _me(Vector2(-380, 120), _eq([142, 143, 144, 145, 146], 1), {"idle": true})]
			+ _dummies(60, 3, true, 12000.0, 60.0), 30.0],
		## 10 件长矛(11-26 夜): 每件单独一段, 靶子按触发条件摆
		## 竹矛: 三只靶子站成一条线 ⇒ 第 3 下穿到身后那只
		"sp_bamboo": [[_me(Vector2(-60, 0), _eq([137], 1))] + _ring_dummies(Vector2(-60, 0), [Vector2(70, 0), Vector2(150, 0), Vector2(230, 0)]), 10.0],
		## 鱼叉(11-26 夜改): 远处站着不动的靶子(会走的靶子第 10 秒已经贴脸, 叉飞不出去看不清); 第 10 秒叉过去、眩晕里一下下往回拽
		"sp_barb": [[_me(Vector2(-300, 0), _eq([138], 1), {"hold": true})] + _dummies(250, 3, false, 30000.0), 14.0],
		"sp_javelin": [[_me(Vector2(-300, 0), _eq([139], 1), {"hold": true})] + _dummies(150, 3, false, 30000.0), 14.0],
		## 骑枪: 靶子站在远处 ⇒ 跑过去攒冲势, 第一下冲阵
		"sp_lance": [[_me(Vector2(-380, 0), _eq([140], 1))] + _dummies(200, 3, false, 30000.0), 12.0],
		"sp_halb": [[_me(Vector2(-60, 0), _eq([141], 1))] + _dummies(40, 3, false, 30000.0), 10.0],
		## 盾矛: 三只会打的靶子都在正面 ⇒ 正面减伤 + 每 5 下反刺
		"sp_shsp": [[_me(Vector2(-60, 0), _eq([142], 1), {"hold": true})] + _dummies(40, 3, true, 30000.0, 60.0), 14.0],
		## 方天画戟(11-26 夜改): 三只会打的靶子围着打 ⇒ 挨够 30% 最大生命 ⇒ 蓄力 → 跃起 → 砸地, 之后攻击带横扫
		"sp_ftj": [[_me(Vector2(-10, 0), _eq([143], 1), {"hp": 4000.0})] + _ring_dummies(Vector2(-10, 0), [Vector2(90, 0), Vector2(-60, 80), Vector2(-60, -80)]).map(func(x): x["ai"] = true; x["atk"] = 120.0; x["hp"] = 30000.0; return x), 16.0],
		"sp_atl": [[_me(Vector2(-300, 0), _eq([144], 1), {"hold": true})] + _ring_dummies(Vector2(-300, 0), [Vector2(380, 0), Vector2(420, -60), Vector2(420, 60), Vector2(460, 0)]), 14.0],
		"sp_eternal": [[_me(Vector2(-300, 0), _eq([145], 1), {"hold": true})] + _dummies(150, 3, false, 30000.0), 12.0],
		"sp_holy": [[_me(Vector2(-60, 0), _eq([146], 1))] + _dummies(40, 1, false, 30000.0), 10.0],
		## 筹码: 黑 + 紫两枚放在一只小将身上, 旁边两只友军 ⇒ 开场每人头上落一枚; 金色第 8 秒全队护罩; 灰色挨打叠满; 棕色倒地复活
		"ch_shield": [[_me(Vector2(-200, 0), _eq([151, 152], 1)), _me(Vector2(-200, 140), [], {"idle": true}), _me(Vector2(-200, -140), [], {"idle": true})] + _dummies(80, 3, true, 30000.0, 40.0), 8.0],
		"ch_gold": [[_me(Vector2(-200, 0), _eq([155], 1)), _me(Vector2(-200, 140), [], {"idle": true})] + _dummies(80, 3, true, 30000.0, 40.0), 14.0],
		"ch_grey": [[_me(Vector2(-60, 0), _eq([156], 1), {"hold": true})] + _dummies(40, 3, true, 30000.0, 80.0), 16.0],
		"ch_brown": [[_me(Vector2(-60, 0), _eq([154], 1), {"hp": 300.0, "killable": true})] + _dummies(60, 3, true, 30000.0, 400.0), 14.0],
		## 看动作(配 REC_ZOOM=2): 靶子不动不打、竖着隔开站
		"ninja_show": [[_u("__summon__", "left", Vector2(-220, 0), {"ghost_eq": "p2eq_115", "equips": _eq([115]), "minion": true, "fe": true})]
			+ _ring_dummies(Vector2(-220, 0), [Vector2(300, 0), Vector2(380, -120), Vector2(380, 120)]), 16.0],
	}


var _b = null
var _el := 0.0
var _max := 14.0
var _started := false


func _ready() -> void:
	await get_tree().process_frame
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	var case := OS.get_environment("REC_CASE") if OS.has_environment("REC_CASE") else "cracker"
	if OS.has_environment("REC_SEC"):
		_max = float(OS.get_environment("REC_SEC"))
	var row: Array = cases().get(case, [[], 0.0])
	var units: Array = row[0]
	if not OS.has_environment("REC_SEC"):
		_max = float(row[1])
	if units.is_empty():
		print("[REC] 没有这个演示: ", case)
		get_tree().quit(1)
		return
	GameState.test_mode = true
	var f := FileAccess.open("user://debug_setup.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"units": units, "loadouts": {}, "theme": BattleDebugArena.DEV_THEME}))
	f.close()
	BattleDebugArena.enter_with_saved_theme()
	RB.DEBUG_EDIT = true
	RB._edit_collapsed = true
	_b = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_b)
	print("[REC] 演示 ", case, " · ", units.size(), " 个单位")


func _process(d: float) -> void:
	_el += d
	if _b == null or not is_instance_valid(_b):
		return
	if not _started and _el > 0.6:
		_started = true
		_b._debug._edit_start_battle()
		## 录像只要战场: 调试场的笔刷栏 / 编辑面板整个藏掉(11-24 自查: 底部一直露着「左队[友军]」选龟栏)
		for nd in [_b.get("_edit_brush_bar"), _b.get("_edit_palette")]:
			if nd is CanvasItem and is_instance_valid(nd):
				(nd as CanvasItem).visible = false
		print("[REC] %.2f 开打 · 场上 %d 单位" % [_el, _b._units.size()])
		## 摆位里写了 hp_pct 的单位: 开打时调试场会按等级重算血量回满, 这里再压一次(11-25 魔法书 122: 看治疗挂在半血友军身上)
		for uu in _b._units:
			if uu is Dictionary and float(uu.get("_edit_hp_pct", 1.0)) < 1.0:
				uu["hp"] = float(uu["maxHp"]) * float(uu["_edit_hp_pct"])
		## REC_ZOOM=2 ⇒ 镜头拉近(11-25 武士刀小将动作录像: 默认镜头下小将只有二十来像素, 动作看不清)
		if OS.has_environment("REC_ZOOM"):
			_b._cam_zoom = float(OS.get_environment("REC_ZOOM"))
			_b._apply_cam_zoom()
	var ds = _b._equip_sys._dagger_sys
	for k in ds.stat:
		if int(ds.stat[k]) != int(_seen.get("d_" + k, 0)):
			print("[EV] %.2f %s %d" % [_el, k, int(ds.stat[k])])
			_seen["d_" + k] = int(ds.stat[k])
	if int(_b._dagger_syn.armed) != int(_seen.get("armed", 0)):
		print("[EV] %.2f assassin_armed %d" % [_el, int(_b._dagger_syn.armed)])
		_seen["armed"] = int(_b._dagger_syn.armed)
	var bs = _b._equip_sys._bomb_sys
	for k in bs.stat:
		if int(bs.stat[k]) != int(_seen.get(k, 0)):
			print("[EV] %.2f %s %d" % [_el, k, int(bs.stat[k])])
			_seen[k] = int(bs.stat[k])
	if OS.has_environment("REC_EN") and int(_el) != int(_el - d):
		for c in bs._cannons:
			print("[EN] %d 秒 龟能 %d 重炮 %s" % [int(_el), int(c["en"]), str(c["heavy"])])
	if int(_b._bomb_syn.strikes) != int(_seen.get("missile", 0)):
		print("[EV] %.2f missile %d" % [_el, int(_b._bomb_syn.strikes)])
		_seen["missile"] = int(_b._bomb_syn.strikes)
	if OS.has_environment("REC_PROBE") and int(_el * 2.0) != int((_el - d) * 2.0):
		for u in _b._units:
			print("[PROBE] %.1f %s %s pos=%s hp=%s alive=%s nm=%s nb=%s sk=%s st=%s atk=%s cd=%s rng=%s stun=%s" % [_el, str(u.get("side", "")), str(u.get("id", "")), str(u.get("pos", "")), str(int(u.get("hp", 0))), str(u.get("alive", false)), str(u.get("no_move", false)), str(u.get("no_basic", false)), str(u.get("active_skills", [])), str(u.get("state", "")), str(u.get("atk", 0)), str(u.get("atk_cd", 0)), str(u.get("atk_range", 0)), str(u.get("stun_until", 0))])
		print("[PROBE] mines ", _b._equip_sys._bomb_sys._mines.size(), " over=", _b._over, " edit=", _b._edit_mode)
	if OS.has_environment("REC_CENT_PROBE") and int(_el * 10.0) != int((_el - d) * 10.0):
		for u in _b._units:
			if str(u.get("id", "")) == "_summon_centurion":
				var sp = u.get("sprite", null)
				print("[CP] %.1f voff=%s spr=%s vis=%s mod=%s sc=%s anim=%s" % [_el, str(u.get("_slam_voff", Vector3.ZERO)), str(sp.position) if is_instance_valid(sp) else "-", str(sp.visible) if is_instance_valid(sp) else "-", str(sp.modulate) if is_instance_valid(sp) else "-", str(sp.scale) if is_instance_valid(sp) else "-", str(u.get("anim_action", ""))])
	var spx = _b._spear_syn
	for k in spx.stat:
		if int(spx.stat[k]) != int(_seen.get("s_" + k, 0)):
			print("[EV] %.2f %s %d" % [_el, k, int(spx.stat[k])])
			_seen["s_" + k] = int(spx.stat[k])
	for pair in [["i_", _b._equip_sys._spear_sys], ["c_", _b._equip_sys._chip_sys]]:   # 10 件长矛 / 筹码的事件(11-26 夜)
		var bx = pair[1]
		for k in bx.stat:
			if int(bx.stat[k]) != int(_seen.get(str(pair[0]) + k, 0)):
				print("[EV] %.2f %s %d" % [_el, k, int(bx.stat[k])])
				_seen[str(pair[0]) + k] = int(bx.stat[k])
	var ms = _b._equip_sys._mask_sys
	for k in ms.stat:
		if int(ms.stat[k]) != int(_seen.get("m_" + k, 0)):
			print("[EV] %.2f %s %d" % [_el, k, int(ms.stat[k])])
			_seen["m_" + k] = int(ms.stat[k])
	if bool(ms.ow.active) != bool(_seen.get("ow", false)):
		print("[EV] %.2f ow_active %s" % [_el, str(ms.ow.active)])
		_seen["ow"] = bool(ms.ow.active)
	## 千面演示: 里世界开着时自动点一次「观看里世界」, 隔 5 秒再点回主世界(看按钮切视角)
	if OS.get_environment("REC_CASE") == "mk_ow" and ms.ow.active:
		var ot: float = float(_b._t) - float(ms.ow.t0)
		if ot > 1.5 and not bool(_seen.get("ow_v1", false)):
			_seen["ow_v1"] = true
			ms.vfx._ow_toggle()
		if ot > 6.5 and not bool(_seen.get("ow_v2", false)):
			_seen["ow_v2"] = true
			ms.vfx._ow_toggle()
	if _el > _max:
		print("[REC] %.2f 收工" % _el)
		get_tree().quit(0)


var _seen := {}
