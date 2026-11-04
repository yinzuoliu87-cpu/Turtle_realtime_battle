class_name EquipEffects
## 装备效果的「接线层」数据 —— A1 技能积木化第一步(2026-11-04 · 方案书 docs/plans/20261102b-参考黑箱学AI开发方式.md §8.4)。
##
## ★为什么: 黑箱 Demo 拆包实测, 它 179 个技能 = 「触发 × 目标 × 动作 × 参数」一张表, 引擎一个解释器跑;
##   我们的「原子动作」(_apply_damage_from / _spawn_eq_bolt / _queue_shots …)早就是共用函数,
##   缺的是「哪个触发 → 哪个动作 → 什么参数」这一层 —— 每件装备各写一份函数。这里把它写成数据,
##   由 scripts/systems/equip/effect_runner.gd 解释执行。新装备照这个表填一行即可, 不写新函数。
## ★判据: 迁移只换组织方式、不改结果 ⇒ verify_rules_fingerprint(全部装备)逐字相同、RULES_VER 不升;
##   改了这张表的数 ⇒ 指纹会红(反向验证: 048 三星 6 发改 7 发 ⇒ 红)。
##
## 字段(按「每星一档」写数组的, 下标 = 星级 − 1):
##   trigger  "interval" = 周期到点(间隔仍在 battle._EQ_CUSTOM_IV, iv 只做对账: verify_equip_effects 查两边相等)
##   action   "volley"   = 朝一个方向连射 N 发, 每发打直线上第一个敌人(可被前排挡)
##   aim      "nearest" 最近的敌人方向(没有敌人 ⇒ 朝右照射) / "farthest" 最远的敌人方向(没有 ⇒ 这一轮不射)
##   band     直线判定半宽(像素)
##   shots    每星发数;  gap 同一轮相邻两发间隔(秒)
##   dmg      {"coef": [每星 ×ATK]} 或 {"lost_hp_lerp": [满血 ×ATK, 损到位 ×ATK, 已损多少算到位]}(按目标已损生命插值)
##   fx       {"flash": 枪口闪色, "tex": 弹体贴图, "col": 弹体色, "psize": 弹体像素尺寸}
## ★静态函数而不是 const: 表里引 EquipSystem 的常量, 而 EquipSystem → EffectRunner → 本表 ⇒ 写成 const 会在加载期撞循环引用;
##   函数体里的引用到第一次调用才解析。
static var _specs: Dictionary = {}


static func specs() -> Dictionary:
	if not _specs.is_empty():
		return _specs
	_specs = {
		## 黄铜手铳: 每 8 秒朝最近的敌人方向依次射 4 / 5 / 6 发, 每发命中直线上第一个敌人(原 equip_system._eq_pistol_volley)
		"p2eq_048": {"trigger": "interval", "iv": EquipSystem.HANDGUN_IV, "action": "volley", "aim": "nearest", "band": 36.0,
			"shots": [4, 5, 6], "gap": 0.08, "dmg": {"coef": [0.5, 0.54, 0.6]},
			"fx": {"flash": "#ffe08a", "tex": "res://assets/sprites/vfx/bullet.png", "col": "#fff0b0", "psize": 0.026}},
		## 连发弩: 每 8 秒朝最远的敌人方向依次射 1 / 2 / 3 发, 按目标已损生命加伤(原 equip_system._eq_crossbow_volley)
		"p2eq_049": {"trigger": "interval", "iv": EquipSystem.XBOW_IV, "action": "volley", "aim": "farthest", "band": 42.0,
			"shots": [1, 2, 3], "gap": EquipSystem.XBOW_GAP,
			"dmg": {"lost_hp_lerp": [EquipSystem.XBOW_MIN_COEF, EquipSystem.XBOW_MAX_COEF, EquipSystem.XBOW_LOST_FULL]},
			"fx": {"flash": "#d8f0a8", "tex": "res://assets/sprites/vfx/crossbow-bolt.png", "col": "#eaffd0", "psize": 0.032}},
	}
	return _specs
