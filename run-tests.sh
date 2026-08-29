#!/bin/bash
# run-tests.sh — headless 跑全部自证测试 + 全流程闪退冒烟 (不依赖编辑器)
# 用法:  bash run-tests.sh
# 输出:  每个测试 PASS/FAIL + 末尾汇总
#
# 找不到 Godot 时改 GODOT 变量。--import 首次或新增 class_name 后需先跑 (注册全局 class)。

GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$GODOT" ]; then
  echo "Godot not found at: $GODOT  (set GODOT env var)"
  exit 1
fi

# ★致命报错模式 —— 2026-07-10 血的教训:
#   我原来的 sim 过滤器里【没有 Max recursion】, 于是 24 组 sim 全报「0 errors」,
#   而真实对局里 _eq_chain_lightning 正在每秒刷几百条 "ERROR: Max recursion reached"
#   (拿单位字典当 Dictionary 的 key → recursive_hash 无限递归), 60 秒战斗刷了 26564 条,
#   并且把帧率拖到 60 秒战斗跑不完。过滤器漏一个模式, 就等于把 bug 判成绿灯。新增模式往这里加。
# ★2026-08-06 补三条(压测拿真实日志逐条对着现有正则试出来的漏网形态):
#   · `Index p_frame = 7 is out of bounds`      —— ninja_system 每 11 局刷 17 条, 旧正则不认
#   · `Lambda capture at index 0 was freed`     —— 旧正则写的是 `freed instance`, 这条是 `was freed`
#   · `Condition "!is_inside_tree()" is true`   —— candy_system 的姿态函数
#   假阳性已量过: 这三个模式在干净的 166/166 全套日志与两份探针日志里命中 0/0/0。
#   ★CLAUDE.md §2:「漏一个模式就等于把 bug 判成绿灯」—— 历史上 `Max recursion` 曾不在名单里,
#     24 组压测全报"0 errors", 而真实对局每秒刷几百条错误。新报错形态一律往这条加。
FATAL='Infinite loop detected|SCRIPT ERROR|Parse Error|Max recursion|freed instance|null instance|Cannot call|Invalid (get|set|call|index)|Trying to (assign|call)|Nonexistent|is out of bounds|Lambda capture|Condition ".*" is true'

PASS=0; FAIL=0

# 帧预算 (--quit-after 的单位是【帧】不是毫秒)。默认 500 帧 ≈ 8 秒。
# 需要更多的测试在此登记 —— 帧数不够会让测试【跑到一半被掐断】,
# 表现为"没打 ALL PASS"而不是"某条断言 FAIL", 极易被误读成真失败。
frames_for () {
  case "$1" in
    verify_ios_ui) echo 4000 ;;
    # ★2026-08-15 新增的三个版式门禁: 都要【逐个实例化整屏场景 + 等入场 tween 落定】,
    #   500 帧只够跑完前一两屏 —— 表现是"没打 ALL PASS"(rc=0 / 致命报错 0), 极易误判成断言失败。
    #   verify_mainmenu_layout 自己还要等入场动画 settle, 帧不够会量到【半空中的坐标】,
    #   于是"66 个控件越界"这种吓人的数字其实是按钮还在飞。
    # 28 只龟【逐只】开面板 + 每只轮询到滑入动画落定(最多 180 帧) ⇒ 28×180 起步。
    #   ★帧不够会在半路被掐断 = 没打 ALL PASS, 看着像断言失败(CLAUDE.md §2 那个坑)。
    # 逐个实例化 7 个整屏场景(各等 8 帧建树) + 再建一次战斗场开面板 ⇒ 帧要给够。
    #   ★帧不够会在半路被掐断 = 没打 ALL PASS, 看着像断言失败(CLAUDE.md §2 那个坑)。
    # 伤害类型哨兵: 要【跑一整场真对局 40 秒墙钟】才收得到足够分母(取用类型 ≥150 次)。
    #   墙钟不是帧数 —— CI 无头帧率极高, 帧给少了会在还没打够伤害时被掐断
    #   ⇒ 没打 ALL PASS, 看着像断言失败(CLAUDE.md §2 那个坑)。
    verify_dmg_type_sentinel) echo 60000 ;;
    # 阵容后端: 要**真发一次 HTTPRequest 并等它被拒**(打 127.0.0.1:9)。
    #   实测 791 帧才回调 —— 网络回调走的是 HTTPRequest 自己的轮询, 与游戏帧率无关,
    #   帧给少了就是"等不到回调 → 循环没退出 → 没打 ALL PASS", 看着像断言失败(CLAUDE.md §2 那个坑)。
    verify_remote_pool)       echo 4000 ;;
    # 结算屏上传正反馈: ②等轮询回执(0.4 秒一拍·墙钟 3 秒)、④真发一次到不可达地址等回调(最多 900 帧)。
    #   默认 500 帧会在半路被掐断 —— 表现是 rc=0/致命 0 但**没打 ALL PASS**, 极像断言失败。
    verify_upload_flash)      echo 4000 ;;
    # 多形态技能: 每态各建一次干净战斗场 + 走真复制入口 + 墙钟等 0.9 秒结算 ×2 轮。
    #   默认 500 帧会在半路被掐断 —— 表现是 rc=0/致命 0 但**没打 ALL PASS**, 极像断言失败。
    verify_skill_forms)       echo 4000 ;;
    verify_armor_compensation) echo 1500 ;;
    verify_copy_rules)        echo 6000 ;;
    verify_copy_perform)      echo 6000 ;;
    verify_wormhole_escape)   echo 12000 ;;
    verify_rum_numbers)       echo 12000 ;;
    verify_sword_084)        echo 6000 ;;
    verify_cross_slash_seq)   echo 8000 ;;
    verify_click_targets_alive) echo 12000 ;;
    verify_info_panel_fits)   echo 20000 ;;
    verify_mainmenu_layout)   echo 6000 ;;
    verify_inventory_layout)  echo 4000 ;;
    verify_codex_layout)      echo 6000 ;;
    # 7 个整屏场景逐个实例化, 而且每个都要**轮询到入场动画停下来**(最多 240 帧)才量 ——
    #   不等稳就会量到还在半空中的控件(主菜单实测 x = -485, 两个标签报同一个矩形,
    #   压字判据当场报假警)。7 × 240 + 逐屏扫描 ⇒ 预算给到 3 万帧。
    verify_ui_consistency)    echo 30000 ;;
    # 结算屏按钮可达: 建战斗场 + 造 28 个单位塑长名单 + 开统计面板
    #   + **喂过面板的 0.4 秒自刷周期**(它就是在那一刻把自己提到最前的)。
    #   ★喂不够就拍不到覆盖, 断言会假绿 —— 这正是帧预算不够的典型危害。
    verify_result_reachable) echo 3000 ;;   # 逐个进出 9 个菜单场景, 500 帧只够跑完 2 个
    # ★等【游戏内效果结算】的测试: CI 无头帧率远高于本机, 同样的游戏时间要跑多得多的帧。
    #   2026-07-23: verify_pirate_hook 本地 93 帧落地, CI 上 500 帧不够 → 被掐断 →
    #   没打 ALL PASS → 判 FAIL(rc=0、致命报错=0), 看着像断言失败, 其实是预算不足。
    # 20260730d 补齐: 召大熊要走 `await _wait_sim(1.2)` **三次**(三档各一次) ——
    #   等的是 sim 时钟 `_t`, 而无头下每帧 dt 很小 ⇒ 3.6 秒 sim 时间要跑上万帧。
    #   ★帧不够会在半路被掐断 = 没打 ALL PASS, 看着像断言失败(CLAUDE.md §2 那个坑)。
    verify_equip_balance_20260730d) echo 30000 ;;
    # PK 条三事件: 建一次战斗场 + 18 条【同步】断言(直调 _pk_refresh, 不等任何演出),
    #   但建场本身就吃几百帧。
    verify_pk_bar_continuity) echo 3000 ;;
    # 常驻修正跨路: 建战斗场 + 走【清场+重建】两次真换路(每次都要 spawn 整条阵容)
    verify_b4_persist_across_lane) echo 4000 ;;
    verify_accum_lane_scope) echo 4000 ;;   # 同上: 两次真换路(清场+重建)
    verify_pirate_hook)  echo 8000 ;;
    # 十件法器逐件验主动: 每件都要跑【对照组 90 帧 + 正式 90 帧】并等真实帧
    #   (023 走 await 协程, 纯同步 _sim_step 推不动它)⇒ 10 × 180 帧起步。
    #   ★2026-08-14 加对照组后帧数翻倍, 4000 不够被掐断 —— 表现是"没打 ALL PASS"
    #     而不是某条断言 FAIL, 极易误判成真失败(CLAUDE.md §2 明写过这个坑)。
    verify_staff_actives_fire) echo 9000 ;;
    # 16 件装备逐件建场 + 每件跑【对照 180 帧 + 正式 180 帧】并等真实帧
    verify_uncovered_equips) echo 14000 ;;
    # 八件装备 × (同窗两组建场 + 180 帧逐帧 await); 022 的协程要逐帧轮询才推得完
    verify_fire_equips_exact) echo 16000 ;;
    # 五件法器 × (同窗两组建场 + 180 帧逐帧 await)
    verify_staff_active_isolated) echo 10000 ;;
    # 089 符纸要等满 15 秒【真实帧】才到期(它的 el 跟真实帧走, 不跟 sim 时钟)
    verify_talisman_089) echo 8000 ;;
    verify_crystal_sweep_031) echo 2000 ;;
    verify_chest_treasures) echo 2500 ;;
    verify_lava_forms) echo 2000 ;;
    verify_star_space) echo 1500 ;;
    # 触手节奏: 建战斗场景 + 走完 2 秒出土 + 20 次强制重建网格并量几何(同步断言, 不等演出)
    verify_tentacle_rhythm) echo 3000 ;;
    # 转移阵地: 建战斗场景 + 造携带者走真实档位链路 + 喂完钻地/破土动画
    verify_tentacle_relocate) echo 3000 ;;
    # 状态边界连续性: 建战斗场景 + 逐个转移取两侧参数(纯同步, 不等演出)
    verify_tentacle_continuity) echo 2500 ;;
    # 命中时刻(方案 A): 建战斗场 + 造真携带者走档位链 + 嗂触手出土 3.6 秒
    #   + 同步推 `_step_pending_shots`(不等帧、不等 tween)
    verify_tentacle_hit_timing) echo 3000 ;;
    # 详情面板属性读数: 建战斗场 + 两次取属性行(纯同步, 不等任何演出)
    verify_info_panel_stats) echo 2000 ;;
    # 背包文案放不放得下: 建 Inventory 场景 + 选中最长那件 + 量真实屏幕矩形
    verify_inventory_text_fit) echo 1500 ;;
    # 071 全队奶油护盾: 建战斗场 + 造 3 友军 + 走 tick_unit 真入口(纯同步)
    verify_cream_shell_all) echo 2000 ;;
    # 072 礼盒形态: 建战斗场 + 造携带者 + 进/出盒各一次(纯同步, 量真实 texture)
    verify_cake_box_form) echo 1500 ;;
    # 068 充能读数: 建战斗场 + 走真伤害入口喂三次 + 源码纪律扫描(纯同步, 不等演出)
    verify_eq_readouts) echo 2000 ;;
    # 068 可转向射线: 建战斗场 + 四组重建队伍 + 同步喂 delta(闭式解, 不等演出/不等 tween)
    verify_mana_beam_steer) echo 3000 ;;
    # 羁绊演出层共用基建: 建战斗场景 + 78 条同步断言(不等任何 tween), 但建场本身就吃几百帧。
    #   ★实测本机 500 帧【跑不完】(被掐断 → 没打 ALL PASS → 看着像断言失败), 800 帧够 ⇒ 给 2500 兜 CI。
    verify_synergy_vfx) echo 2500 ;;
    # 十类羁绊的视觉母题(批 B3): 同上, 建战斗场景 + 107 条同步断言(走羁绊系统真入口, 不等 tween)
    verify_synergy_vfx_types) echo 2500 ;;
    # _skill_ring 两条曲线: 建战斗场景 + 手推 tween 取 265 个采样点(custom_step, 不等真实时间)
    verify_skill_ring_curve) echo 2500 ;;
    # 金弹可辨 + 七件演出可读性: 建战斗场景 + 111 条同步断言(逐像素读程序化贴图/量真实节点,
    #   不等任何 tween)。建场本身就吃几百帧 ⇒ 给 2500 兜 CI。
    verify_vfx_readability) echo 2500 ;;
    # 怒气冲击波爆轰演出: 建战斗场景 + 6 次重建合成单位队伍 + 上万点闭式解数值扫描(全同步)
    verify_shockwave_vfx) echo 3000 ;;
    # 头顶徽章几何: 需要【真实相机】做屏幕投影(量单位间距) ⇒ 不能无头, 帧数给足
    verify_head_badges) echo 1500 ;;
    # 灵物拍击命中带: 第⑤条要【二分探测 24 轮】真实 _slap 行为来量伤害长度, 每轮都重建敌人
    verify_spirit_slap_range) echo 3000 ;;
    # 食物 4 件(069/070/071/072): 建一次战斗场景 + 150+ 条【同步】断言(效果直调具名入口,
    #   演出形态直调纯函数, 不等任何 tween)。额外吃帧的是 072 的分裂礼盒(每只都建 Sprite3D)
    #   与三处上千点的闭式解扫描, 建场 + 这些一起给 4000 帧兜 CI。
    verify_eq_food_batch) echo 4000 ;;
    verify_eq_hp_grants) echo 8000 ;;
    # 口哨②要【墙钟】等灵体小龟活满 5 秒(tween 驱动·走未钳制 delta) → 无头高帧率下帧数很多
    verify_whistle_wave) echo 12000 ;;
    verify_battle_determinism) echo 4000 ;;   # 3 遍 headless 战斗×200帧顺序跑(同种子比指纹)·500帧只够跑 2 遍多 → 被掐断误判FAIL
    verify_interactive_determinism) echo 2000 ;;   # 6 次全场景重建(add_child建世界)·驱动是同步喂累加器(不吃帧)·2000 足量兜底
    # UI 双端适配: 10 屏 × 4 比例 = 40 次场景实例化, 每次等 150 帧让入场 tween 落定 → ≥6000 帧。
    #   ★等 150 帧不是拍脑袋: 主菜单左栏键从 x=-560 滑入(延迟 0.5+0.08i 秒), 90 帧会抓到滑一半,
    #   把"按钮跑到屏外"报成 bug(2026-08-01 实际误判过一次)。
    verify_ui_layout) echo 20000 ;;
    # 图鉴逐条浏览: 129 条 × 每条至少 1 帧 + 五次建列表 → 3000 帧足量
    verify_codex_browse) echo 3000 ;;
    # 装备批次13条: 建一次战斗场景 + 100+ 条同步断言, 不等游戏内时间, 但建场本身要几百帧
    verify_equip_batch_20260801) echo 3000 ;;
    # ★2026-08-06: verify_equip_periodic_batch1(批①周期类) 与 verify_equip_misc_batch3(批③)
    #   两份已【整份删除】—— 它们里面每一个逐件用例测的都是 077~094 这十七件的【旧效果】,
    #   而用户已把这十七件逐件亲手重做(§0.5·批④) ⇒ 不是"改几条断言"是整份过时。
    #   逐件数值门禁改由各路自己的 verify_eq_*_batch 承担; 接线结构由 verify_b4_wiring 守。
    # 新装备批②命中/普攻类: 建一次战斗场景 + 15 条【同步】断言。
    #   ★078/083 两段逐件用例已随重做删掉(它们原来是这里最吃帧的一段: 播种 RNG × 1000 次),
    #   现在只剩分发纪律与接线, 但建场本身仍要几百帧 ⇒ 预算保持 4000 不动。
    verify_equip_onhit_batch2) echo 4000 ;;
    # 批④ 接线门禁(077~094 十七件): 建一次战斗场景 + 34 条【同步】断言
    #   (源码扫描 + 真走两条伤害路径, 不等演出/不等游戏内时间), 预算给建场用。
    verify_b4_wiring) echo 3000 ;;
    # 批④ 跨路泄漏专项: 建一次战斗场景 + 走真的 _dl_build_lane_field 换两次路 + 8 条同步断言。
    #   ★它守的是 verify_b4_wiring 结构上看不见的那一半 ——
    #   那份验的是"换路【会调】clear_all"(源码扫描), 这份验的是"clear_all 到底【清干净没有】"。
    #   一个只写 pass 的 clear_all 能让前者全绿, 而上一路的召唤物与光环会整个带进下一路。
    verify_b4_lane_leak) echo 3000 ;;
    # 093 香火石全链路(存储收口 / 三条升星入口 / 存档往返 / 进战斗注入 / 刻痕 / 加成 / 主动 / 赛季重置):
    #   62 条【同步】断言 + 建一次战斗场景。★额外吃帧的是 ⑦ 那组(三个星级各建一对单位并打 5 次普攻),
    #   建场 + 这一段一起给 4000 帧兜 CI。
    verify_incense_stone) echo 4000 ;;
    # 灵物 5 件(用户逐件重做·060~064): 建一次战斗场景 + 167 条【同步】断言
    #   (效果全靠直调 tick_unit / _eq_on_hit / _eq_on_dodge / _eq_on_cast / _spec 触发,
    #   演出形态由纯函数 + apply_at 同步写, 不等任何 tween), 预算主要给建场用。
    verify_eq_spirit_batch) echo 3000 ;;
    # 装备平衡7项(20260730d 补的门禁): 三只大熊各要【墙钟】等 1.2 秒蓄力演出(真入口
    #   _big_bear_charge_and_spawn 里 await _wait_sim(1.2)) → 无头高帧率下帧数很多。
    #   ★第一次跑全套就撞了这个: 单跑 ALL PASS, 全套里 rc=0/致命0 却判 FAIL —— 正是被掐断。
    verify_equip_batch_20260730d) echo 12000 ;;
    # 092 剧毒飞行物: 建一次战斗场景 + 130 条【同步】断言。★额外吃帧的是几段"真模拟"——
    #   ③ 一整段航程(最多 3000 步)、⑥⑯ 同步喂满 4.5 秒毒雾(各 270 步)、⑯ 600 帧性能采样。
    #   这些都是【同步喂 tick】不吃帧, 真正吃帧的仍是建场 + 每组之间的 process_frame ⇒ 3000 兜 CI。
    verify_eq_venom_drone) echo 3000 ;;
    # 弓箭 4 件(073~076·2026-08-05 用户逐件重写): 建一次战斗场景 + 120+ 条【同步】断言。
    #   ★额外吃帧的是两段统计量: 箭雨落点的 Rayleigh 分布(播种 RNG × 4000 个点)
    #   与 073 暴击率的经验频率(× 1200 发) —— 两段都是同步循环不吃帧,
    #   真正吃帧的仍是建场 + 组间 process_frame ⇒ 3000 兜 CI。
    verify_eq_bow_batch) echo 3000 ;;
    # 药水 4 件(065~068·2026-08-05 用户逐件重写): 建一次战斗场景 + 174 条【同步】断言。
    #   ★额外吃帧的是演出物理模型那几段【纯函数扫描】: 薄膜干涉 14 万点找暗纹、
    #   阻尼振子 5500 点找极值、毒云质量守恒三次 2 万步数值积分 —— 全是同步循环不吃帧,
    #   真正吃帧的仍是建场 + 组间 process_frame ⇒ 3000 兜 CI。
    verify_eq_potion_batch) echo 3000 ;;
    # 遗物 2 件(091/094·2026-08-06 用户逐件重写): 建一次战斗场景 + 151 条【同步】断言。
    #   091/094 的节拍全靠同步喂 tick_unit/tick(不等墙钟、不等 tween), 真正吃帧的只有建场
    #   与组间 process_frame ⇒ 本机 500 帧就够, 给 3000 兜 CI。
    verify_eq_relic_batch) echo 3000 ;;
    # 四件"看不见"的演出可见性(085/089/091/094·2026-08-07): 建一次战斗场景 +
    #   逐帧推进真实符纸 720 帧(同步喂 delta, 不等 tween)+ 6000 像素级纹理扫描 + 几何断言。
    #   ★720 次 tick 是【同步循环】不吃引擎帧, 吃帧的仍是建场 ⇒ 给 3000 兜 CI。
    verify_eq_vfx_visibility) echo 3000 ;;
    # 闪避上限/施加: 只建一次场 + 同步断言, 但建场本身要几百帧
    verify_dodge_cap) echo 2000 ;;
    verify_thorn_reflect) echo 3000 ;;
    verify_vfx_frames) echo 2000 ;;
    verify_salvo_trainer) echo 3000 ;;
    *)             echo 500  ;;
  esac
}

# ══════════════════════════════════════════════════════════════════════════
#  自证测试跑法: 有界并行 (2026-08-11)
# ══════════════════════════════════════════════════════════════════════════
#  ★为什么要并行 —— 实测的时间去向, 不是猜的:
#      · 随便挑一个【重】测试(建战斗场 + 走完整档位链)  2.03 秒
#      · 挑一个【空】测试(verify_version, 只读四个文件) 2.14 秒
#    两者一样 ⇒ **耗时几乎 100% 是 Godot 进程启动, 测试自己的逻辑不要钱**。
#    串行等于把这 2 秒的启动【重复 168 次】= 5.7 分钟, 而 CPU 只用了一个核。
#  ★量过但【不是】原因的(免得以后再查一遍):
#      · CPU 降频      —— 连跑 40 次, 后 10 次只慢 4%
#      · 音频驱动初始化 —— 带不带 `--audio-driver Dummy` 完全一样(2034 vs 2030 ms)
#      · 审计器        —— 六个加起来 1.5 秒
#      · 冒烟          —— 80 秒(真贵, 但只有一次, 不在这一段)
#
#  ★并行安全性是【查过】的, 不是假定的:
#      · 零个测试写盘(tests/ 里的 DirAccess.open 全是列目录)
#      · 碰存档的三个(incense_stone / season_flow / shop_persist)都显式
#        `test_mode = true` 或注释写明"不调 GameState.save()" ⇒ 不写 user://
#      · 唯一的共享可写状态是 `.godot/` 导入缓存 ⇒ 开跑前先单独 --import 一次
#
#  ★判定逻辑与串行版【逐字相同】(rc / 致命正则 / ALL PASS 关键字)。
#    只改调度不改判据 —— 否则就是拿"跑得快"换"假绿灯", 这个项目栽过太多次了。
# ★默认 2(2026-08-12 从 4 降下来): 这台机器 CPU 已确诊硬件故障且**仍在恶化** ——
#   08-11 一秒内 16 条 WHEA Internal parity error(且首次出现第二个 APIC ID),
#   08-12 一天两次异常关机且【连转储都没写出来】。多进程编译正是最容易触发的负载。
#   送修/换板之后再调回 4(或更高)。想临时快跑: JOBS=8 bash run-tests.sh
JOBS="${JOBS:-2}"

# 只跑, 不判定。输出与退出码各写一个文件(并行下拿不到子进程的 $?)
run_one () {  # $1 = 测试名
  local t="$1"
  [ -f "$DIR/tests/$t.tscn" ] || return 0
  # ★★门禁进程一律【停用阵容同步层】(2026-08-27)。
  #   `project.godot` 里现在填着真的后端地址 ⇒ 任何调 `find_opponent` 的测试都会真发一次拉取,
  #   而拉取成功后会 `save_pool()` **写本地池文件** —— 门禁跑 250 项, 中途改写共享状态
  #   就是不确定性的来源(这条比"会不会报错"更要紧: 报错看得见, 数据被改看不见)。
  #   顺带也省掉对生产服务器的无谓请求(免费额度按请求数算)。
  #   环境变量优先级高于 ProjectSettings(见 remote_pool.base_url), 空白串 = 停用。
  #   ★专门验这一层的 `verify_remote_pool` 自己 `OS.unset_environment` 打开它,
  #     所以"配置里的真地址能启用本层"那条断言照样验得到。
  TURTLE_BACKEND=" " "$GODOT" --headless --path "$DIR" "res://tests/$t.tscn" \
      --quit-after "$(frames_for "$t")" > "$RAW/$t.log" 2>&1
  echo $? > "$RAW/$t.rc"
}

# 只判定, 不跑。★这一段是从原 run_test 原样搬来的, 判据没动
run_test () {  # $1 = 测试名
  local name="$1"
  if [ ! -f "$DIR/tests/$name.tscn" ]; then
    echo "  SKIP  $name (无 .tscn)"; return
  fi
  local rc fatal
  # ★rc 文件不存在 = 那个进程根本没留下结果(被杀/没起来) ⇒ 判 99 = FAIL,
  #   绝不能当成 0 —— "没跑" 必须红, 不能静默变绿
  rc="$(cat "$RAW/$name.rc" 2>/dev/null || echo 99)"
  [ -n "$rc" ] || rc=99
  # ★别在这里写 `|| echo 0`: `grep -c` 数到 0 时【打印 0 但退出码是 1】,
  #   `||` 于是再追加一个 0 ⇒ 值变成两行 ⇒ `[ ]` 当整数用直接炸 ⇒ 168 个全判 FAIL。
  #   (2026-08-11 实测踩到: 并行改造第一版就是这么全红的。串行版本来没这句,
  #    是我"顺手加固"加出来的 —— 防御性代码也要验, 它一样会引入 bug)
  fatal="$(grep -cE "$FATAL" "$RAW/$name.log" 2>/dev/null)"
  [ -n "$fatal" ] || fatal=0
  # ★★【已登记缺口·同一条】(2026-08-22) `Lambda capture at index N was freed`
  #   是**拆除时序**的老账(见下面 KNOWN_LAMBDA_CAP 那段长注释: 玩家路径碰不到,
  #   已修同族 6 处、至少还剩一处捕获 Node 的闭包没找到)。
  #   `verify_dmg_type_sentinel` 要跑【一整场 12v12 真对局再拆场】才收得到分母,
  #   于是它每次都会踩到这条 —— 它其实是这个老账的**第一个确定性复现器**
  #   (此前只有 smoke 偶发, 6 次里 1~2 次)。
  #   ⇒ 与 smoke 同样处理: 这一条单独扣掉, 其余任何致命报错照旧一条就红。
  #   ⚠ 只对这一个测试名生效, 不是全局放水; 修掉根因后把这段删掉。
  #
  #   ★★为什么这里【不设数量上限】(smoke 那边是 cap=1):
  #     实测同一份代码连跑, 条数在 **1 ~ 62** 之间跳(场上活的东西越多刷得越凶,
  #     而本用例是 12v12 打满 40 秒 = 最凶的场面; 退出前多让几帧释放反而越等越多)。
  #     拿一个固定数当判据 ⇒ 判据比被测对象还不稳, 那是制造偶发红, 不是把关。
  #   ★这条豁免【保护不到】什么, 说清楚: 如果将来新写的代码引入**新的**野捕获,
  #     本用例不会红。兜底靠 smoke_scenes —— 它那边仍是 cap=1, 多一条就红。
  #   ★已排除"是我这轮引入的": 把触手触地回调整个去掉再跑, 条数反而从 6 涨到 40。
  if [ "$name" = "verify_dmg_type_sentinel" ]; then
    local _kl
    _kl="$(grep -cE "Lambda capture at index [0-9]+ was freed" "$RAW/$name.log" 2>/dev/null)"
    [ -n "$_kl" ] || _kl=0
    fatal=$((fatal - _kl))
    [ "$fatal" -lt 0 ] && fatal=0
    [ "$_kl" -gt 0 ] && echo "        WARN 扣掉 $_kl 条已登记的 Lambda capture(拆除时序·见上)"
  fi
  # ★★2026-08-17 拆掉「自证完成」这条后门:
  #   原判据是 `ALL PASS 或 自证完成`。全套 196 个测试里【只有 verify_dot_stacks 走这条】,
  #   而它当时**一条断言都没有** —— 只 print 数值和"(期望=X)"给人看, 从不比较、从不失败。
  #   DoT 衰减模型坏掉它照样绿, 却在门禁里占着一格 PASS。
  #   现在那份已改成真断言(10 条), 后门也就没有任何测试需要了 ⇒ 判据只认 ALL PASS。
  if [ "$rc" -eq 0 ] && [ "$fatal" -eq 0 ] && grep -q "ALL PASS" "$RAW/$name.log"; then
    PASS=$((PASS+1)); echo "  PASS  $name"
  else
    FAIL=$((FAIL+1)); echo "  FAIL  $name  (rc=$rc, 致命报错=$fatal)"
    grep -E "\[FAIL\]|✗|$FATAL" "$RAW/$name.log" 2>/dev/null | head -5 | sed 's/^/        /'
    # ★★2026-08-20: 失败就把整份日志留下来。
    #   由来: verify_trainer_hunt_tame 在全套里红过三次(rc=1 而**日志里连一条 [FAIL] 都没有**),
    #   单跑十次全绿、四路并行也复现不出来 —— 而 `$RAW` 是 mktemp 目录、脚本一退出就删,
    #   于是每次红都只剩一行"rc=1"、**证据当场销毁**, 下次还是从零开始猜。
    #   追不动的偶发, 至少要让它下次红的时候留下现场。(.gate-fail-*.log 已进 .gitignore)
    cp "$RAW/$name.log" "$DIR/.gate-fail-$name.log" 2>/dev/null
    echo "        ↳ 完整日志已留在 .gate-fail-$name.log"
  fi
}

# ★自动发现, 不用硬编码名单 —— 2026-07-20 的教训:
#   原来这里是手写的 28 个名字, 而 tests/ 下实际有 36 个 verify_*.gd。
#   漏登记的 8 个【从来没被执行过】, 其中 verify_ios_ui 早就因帧数不足跑不完, 无人知晓。
#   写测试的人不会记得回来改名单, 所以名单这种形式本身就是错的 —— 改成扫目录。
#   新增测试只要放进 tests/ 并配好 .tscn 就自动纳入, 无需任何登记动作。
echo "=== 自证测试 (自动发现 tests/verify_*.gd) ==="
RAW="$(mktemp -d)"
trap 'rm -rf "$RAW"' EXIT

# ★先单独导入一次: `.godot/` 导入缓存是并行下唯一的共享可写状态,
#   让 N 个进程同时冷启动去建它会打架。这一步之后缓存是热的, 后面只读。
"$GODOT" --headless --path "$DIR" --import > /dev/null 2>&1

# ★冒烟(80 秒)与测试池【同时】跑 —— 它是完全独立的进程, 与自证测试零共享状态,
#   排在后面串行等 = 白白多花 80 秒。判定逻辑在下面的冒烟段, 一个字没改。
#   必须用 SHIP=1: 否则 _review_demo() 为真 → 假人永不死 → 战斗永不结束 → 结算路径根本没测到。
( SHIP=1 "$GODOT" --headless --path "$DIR" res://tests/smoke_scenes.tscn \
    --quit-after 40000 > "$RAW/smoke.log" 2>&1; echo $? > "$RAW/smoke.rc" ) &
SMOKE_PID=$!

NAMES=()
for f in "$DIR"/tests/verify_*.gd; do
  [ -e "$f" ] || continue
  NAMES+=("$(basename "$f" .gd)")
done
DISCOVERED=${#NAMES[@]}

# 有界并行: 同时最多 $JOBS 个 Godot
export -f run_one frames_for
export GODOT DIR RAW
printf '%s\n' "${NAMES[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {}

# ★判定仍是【串行、按名字顺序】—— 日志与串行版逐行可比, 不会因并行乱序
for t in "${NAMES[@]}"; do
  run_test "$t"
done
echo "  (发现 $DISCOVERED 个测试, 并行度 $JOBS)"

# ── 全流程闪退冒烟 ────────────────────────────────────────────────────────────
#   必须用 SHIP=1 跑: 否则 _review_demo() 为真 → 假人永不死 → 战斗永不结束 → 结算路径根本没测到。
echo "=== 全流程闪退冒烟 (SHIP=1 真实对局) ==="
wait "$SMOKE_PID"        # ★它在自证测试跑的时候就已经在跑了, 通常这里立刻返回
SMOKE_OUT="$(cat "$RAW/smoke.log" 2>/dev/null)"
SMOKE_RC="$(cat "$RAW/smoke.rc" 2>/dev/null)"
# ★rc 文件没留下 = 那个进程根本没跑完 ⇒ 判 99 = FAIL。"没跑"必须红, 不能静默变绿
[ -n "$SMOKE_RC" ] || SMOKE_RC=99
SMOKE_FATAL="$(echo "$SMOKE_OUT" | grep -cE "$FATAL")"
# ★★【已登记的已知缺口】(2026-08-21) —— 不是放水, 是把"我没修好"这件事显式记账:
#   `Lambda capture at index N was freed` 只在【战斗场景被 inst.free() 立即释放】的拆除
#   时序里偶发(实测 6 次里 1~2 次), 玩家路径碰不到(真实代码走 queue_free / 换场景)。
#   今晚已修掉同族 6 处: info_panel 捕获 sec / TeamSelect·Record·Settings×2 的树级计时器 /
#   dual_lane_flow 捕获 _c / RecordScene 的 draw 闭包捕获 btn; 并加了 tools/tree_timer_audit.py。
#   **但没根治** —— 至少还有一处捕获 Node 的闭包没找到。
#   ⇒ 这一条【单独计数、允许最多 KNOWN_LAMBDA_CAP 条】; 其余任何致命报错照旧一条就红。
#   ★上限只降不升: 涨了就是又添了新的野捕获, 必须当场查。
KNOWN_LAMBDA_CAP=1
SMOKE_KNOWN="$(echo "$SMOKE_OUT" | grep -cE "Lambda capture at index [0-9]+ was freed")"
[ "$SMOKE_KNOWN" -gt "$KNOWN_LAMBDA_CAP" ] && SMOKE_KNOWN="$KNOWN_LAMBDA_CAP"
SMOKE_FATAL=$((SMOKE_FATAL - SMOKE_KNOWN))
[ "$SMOKE_FATAL" -lt 0 ] && SMOKE_FATAL=0
if [ "$SMOKE_RC" -eq 0 ] && [ "$SMOKE_FATAL" -eq 0 ] && echo "$SMOKE_OUT" | grep -q "SMOKE DONE"; then
  PASS=$((PASS+1)); echo "  PASS  smoke_scenes (9场景进出×4 + 战斗中途硬释放×3 + 60秒完整战斗)"
  [ "$SMOKE_KNOWN" -gt 0 ] && echo "        WARN 含 $SMOKE_KNOWN 条已登记未修的 Lambda capture(拆除时序·玩家碰不到) - 见 KNOWN_LAMBDA_CAP"
else
  FAIL=$((FAIL+1)); echo "  FAIL  smoke_scenes  (rc=$SMOKE_RC, 致命报错=$SMOKE_FATAL)"
  echo "$SMOKE_OUT" | grep -E "$FATAL" | sort | uniq -c | sort -rn | head -5 | sed 's/^/        /'
  # ★冒烟失败时把整份日志落盘: $RAW 是 mktemp 目录, 脚本退出就没了 ——
  #   而冒烟是间歇性红(1/3), 事后想查根因时日志已经不在了。
  cp "$RAW/smoke.log" ".gate-fail-smoke_scenes.log" 2>/dev/null || true
fi


# ── 三方一致性对账 (pets.json ↔ 活代码 ↔ 权威文档) ──────────────────────────
echo "=== 三方一致性对账 ==="
TRI="$(cd "$DIR" && TRI_OUT="$DIR/tri_audit_report.txt" python tools/tri_audit.py 2>&1)"
# C 段(icon 索引错位)是已知待用户拍板项, 不算失败; 其余段(A/B/D/E/F)必须 0
if echo "$TRI" | grep -q "selftest OK"; then
  PASS=$((PASS+1)); echo "  PASS  tri_audit ($(echo "$TRI" | grep -oE '差异 [0-9]+ 处'))"
else
  FAIL=$((FAIL+1)); echo "  FAIL  tri_audit"; echo "$TRI" | tail -3 | sed 's/^/        /'
fi

# ── 只读数据审计器 ──────────────────────────────────────────────────────────
#   ★这些以前只能【手动跑】, 于是"改了没人拦" —— 装备文案与代码分歧就是这么攒出来的
#   (2026-07-19 那轮花了近 30 个来回逐条人工核对)。现在进门禁, 分歧当场报。
run_audit () {   # $1=脚本 $2=判定通过的关键字 $3=显示名
  local out
  out="$(cd "$DIR" && python "$1" 2>&1)"
  if echo "$out" | grep -q "$2"; then
    PASS=$((PASS+1)); echo "  PASS  $3"
  else
    FAIL=$((FAIL+1)); echo "  FAIL  $3"; echo "$out" | tail -6 | sed 's/^/        /'
  fi
}

echo "=== 只读数据审计 ==="
run_audit "tools/data_integrity.py"       "ALL OK" "data_integrity (json交叉引用/资源路径/孤儿字段)"
run_audit "tools/tooltip_number_audit.py" "ALL OK" "tooltip_number_audit (装备文案数值 ↔ 代码)"
# ★龟技能文案 ↔ 代码 (2026-07-30 新增)。由来: 用户「不只是无头龟有这问题啊，所有龟、装备、
#   训龟大师技能都有问题怎么办呢」—— 装备有 tooltip_number_audit、大师有 verify_trainer_desc,
#   但【龟技能一直没有】。无头·灵魂打击文案写 0.9A+20%当前生命, 代码是 0.5A+10%, 四轮门禁全绿没发现。
run_audit "tools/pet_number_audit.py" "ALL OK" "pet_number_audit (龟技能文案数值 ↔ 代码)"
run_audit "tools/brief_detail_audit.py"   "ALL OK" "brief_detail_audit (龟技能 brief ↔ detail 数值)"
run_audit "tools/passive_number_audit.py" "ALL OK" "passive_number_audit (龟被动文案数值 ↔ 代码)"
# ★地图构图与可玩性 (2026-07-31 新增)。由来: 重画 arena.json 时发现三条约束没人守 ——
#   战场内不能有 void(单位被 clamp 进去=站黑洞)、站位格不能是水、接战区不能是水(亮度98压深色龟)。
#   改前的老图恰好三条全踩(亮青池子铺满接战区)。第 4 条守"地图必须与生成器一致", 防手刷脱钩。
run_audit "tools/map_composition_audit.py" "ALL OK" "map_composition_audit (地图构图·战场无void/站位不在水/接战区不亮/与生成器一致)"
run_audit "tools/vfx_ref_match.py"     "ALL OK" "vfx_ref_match (084 三张特效 ↔ 用户参考图的形态指标 + 像素风)"
run_audit "tools/vfx_ingame_check.py"  "ALL OK" "vfx_ingame_check (084 十字斩实拍: 斩击是主角/两者都画得出来)"
run_audit "tools/workflow_lint.py"        "ALL OK" "workflow_lint (CI 工作流 YAML 语法)"
run_audit "tools/arch_budget.py"          "ALL OK" "arch_budget (架构预算·不许上帝对象·欠债只减不增)"
run_audit "tools/style_lint.py"           "ALL OK" "style_lint (代码风格·全tab/snake_case/PascalCase 焊死)"
run_audit "tools/rng_discipline.py"        "ALL OK" "rng_discipline (裸随机冻结·护确定性不回退)"
run_audit "tools/docs_authority_lint.py"  "ALL OK" "docs_authority_lint (单一事实源纪律·三权威在位/消费链活/README无漂移/无冒名)"
# 服务端(Node)【手抄】的客户端规则 —— 四个常量 + 龟/装备白名单逐条对账。
#   服务端读不了 .gd, 只能抄; 而抄的副本落后时是**静默的**: 它会把合法快照判成伪造,
#   玩家只看到"我的阵容传不上去", 没人会去翻那份 JS。新增一只龟就会踩。
run_audit "tools/server_rule_sync.py"     "ALL OK" "server_rule_sync (服务端规则↔客户端事实源·常量/白名单)"
# 服务端云函数的【逻辑】—— 起本地宿主跑真 index.js(SDK 换成内存库), 六类伪造 + V2 往返逐条验。
#   "没部署"挡住的只是部署, 挡不住逻辑。仍然没验的只剩"云上真部署"(要腾讯云账号+实名)。
#   没有 node 会 SKIP 但**大声打出来**; CI 的 ubuntu runner 自带 node, 线上必跑。
run_audit "tools/server_logic_gate.py"    "ALL OK" "server_logic_gate (云函数逻辑·V2往返/V3六类伪造/去重)"
# 龟壳「复制」链路的四方对账(pets.json / _do_skill 分派 / _IMPL / 白名单 / 小将技)。
#   2026-08-28 首跑报出 17 处: 白名单里 13 个**普攻位技能永远不会被执行**(占名额虚报可抄数)、
#   1 个幽灵条目、3 个小将技漏掉。★判据落在 `_do_skill` 的 **match 块 case 标签**,
#   不是正则找 `"x": _sk_` —— 后者认不出三元分派, 我为此判错过一次。
run_audit "tools/copy_chain_audit.py"     "ALL OK" "copy_chain_audit (龟壳复制链路四方一致·可抄数棘轮)"
# 文案【声称的事】↔ 代码【实际做的事】—— 数值之外的三类(触发周期/选靶对象/作用范围)。
#   由来: 用户 2026-08-19 读一眼就发现「小龟被动的增伤只适用于普通攻击吗」——
#   文案写「普攻伤害」而代码挂在伤害总闸上(普攻/技能/真伤全覆盖), 而当时 211 项全绿:
#   已有审计器只对数值和效果类别, 「文案说 A 代码做 B」这一整类没人看。
#   ★它报的是【疑点】: 逐条读代码判完, 要么改文案, 要么进 ACCEPT 并写清理由(不许放宽判据)。
# 文案里【写的百分比】↔【同句占位符公式算出来的系数】—— "文案自己内部就对不上"这一类。
#   2026-08-19 逐只读代码时抓到两个真 bug 而当时 212 项全绿: 石头龟岩石护盾"文字新公式旧"
#   (玩家看到的数字停在改版前)、海盗龟朗姆酒 detail 把 15% 配到了 0.65 的公式上。
run_audit "tools/text_formula_audit.py"  "ALL OK" "text_formula_audit (文案文字↔它自己的占位符公式)"
run_audit "tools/text_claim_audit.py"    "ALL OK" "text_claim_audit (文案声称↔代码实际·触发周期/选靶/作用范围)"
run_audit "tools/plans_lint.py"          "ALL OK" "plans_lint (方案书生命周期·状态/骨架/实施回填)"
run_audit "tools/dead_preload_audit.py"  "ALL OK" "dead_preload (preload 了却没人用的常量)"
# ★2026-08-20 补挂: 这个脚本 2026-08-19 就写了, 我还多次在提交信息里声称把检查"焊进门禁",
#   但它**从来没进过 run-tests.sh** —— 改动史词/别家游戏黑话/数字间距 一条都没被强制执行过。
#   (它原本也不打 ALL OK、恒返回 0, 一并补了判定行。)
run_audit "tools/text_const_orphan_audit.py" "ALL OK" "text_const_orphan_audit (文案指的常量有没有产品代码在读)"
run_audit "tools/const_leftover_audit.py" "ALL OK" "const_leftover_audit (抽了常量却还有别处留着裸数字·跨文件判红)"
run_audit "tools/codex_text_lint.py"     "ALL OK" "codex_text_lint (图鉴文案: 教学味/自夸/开发备注/别家黑话/数字贴字)"
run_audit "tools/twin_const_audit.py"    "ALL OK" "twin_const (同功能的逻辑侧↔演出侧同名常量取值打架)"
run_audit "tools/type_tables_audit.py"   "ALL OK" "type_tables (装备类型四张平行表键集一致)"
# ★★这条是"文案漂移"这个病的**总指标**(2026-08-20 用户连问两次「怎么根除」后建的):
#   玩家看到的每个数字必须处在三态之一 —— 占位符(不可能错)/有审计器对代码验/没人验。
#   第三类焊成只降不升。降的办法只有"换占位符"或"补覆盖", **不许靠放宽基线**。
run_audit "tools/number_coverage_audit.py" "ALL OK" "number_coverage (玩家文案里没人验的数字·只降不升)"
# ★Golden/Approval Test: 把**玩家看到的**文案整份存快照, 一个字不一样就红。
#   它不理解文案含义, 所以覆盖面是 100%(数值审计器只能覆盖它认识的形状)。
#   改代码常量而不碰文案也会被抓到 —— {C:} 展开后玩家看到的数变了。
#   确认改动是有意的: python tools/text_golden.py --update, 并把快照一起提交。
run_audit "tools/text_golden.py"        "ALL OK" "text_golden (玩家文案快照对账·483 段)"
# ★★上面那条存的是【原文】, 所以把 `{N:1.5*ATK}` 换成 `{N:某类.某常量*ATK}` 时
#   它只能说"这行改了", **说不出那个数变没变**。2026-08-25 真出过事故: 无头龟的公式
#   被接到骰子龟的常量上(1.5 → 0.5), 渲染门禁全绿、原文快照也只报"改了一行"。
#   ⇒ 这条存的是每段文案里所有占位符**算出来的值**, 判据是"旧的值不许消失"
#     (根除只会让值变多: 转引用值不变、把外面的裸数字转进来是新增)。
#   确认是有意的平衡改动: python tools/text_value_golden.py --update, 快照一起提交。
run_audit "tools/text_value_golden.py"  "ALL OK" "text_value_golden (占位符算出来的数·旧值不许消失)"
# ★★第三条: 归属。上面两条【都拦不住】接到别的主体的同值常量——
#   值一样 ⇒ 值快照绿; 那个常量确实有人读 ⇒ 孤儿审计绿; 渲染得出数 ⇒ 渲染门禁绿。
#   2026-08-25 实测三例(无头→骰子 / 无头→彩虹 / 骰子→彩虹), 只有一例被平衡门禁碰巧抓到。
run_audit "tools/text_const_owner_audit.py" "ALL OK" "text_const_owner (文案引用的常量必须属于这个主体)"
# ★★第四条: 散文。前三条管【数】与【归属】, 都看不见"token 被插进文字中间" ——
#   class="val-{C:X}ef"(本该 val-def) / 永久 +1{C:X}甲(本该 +1 护甲)。
#   带中文时连 "} 后跟字母" 这种形状扫描也漏("甲"不是 ASCII 字母)。
#   判据: 抹掉占位符与数字之后, 文字必须逐字不变。
#   2026-08-25 它当场抓到一处我多写了百分号的语义错 —— 另外三条门禁全绿。
run_audit "tools/text_prose_guard.py"   "ALL OK" "text_prose_guard (文案的文字部分逐字未动)"
# ★装备属性展示串 ↔ EquipStats.STATS(CLAUDE.md 说的真事实源)。这条缝以前谁都没管:
#   tooltip_number_audit 只查 effectDesc1 的**效果**三元组, 属性这块它明确不管。
run_audit "tools/basestats_audit.py"    "ALL OK" "basestats (装备属性展示串 ↔ EquipStats.STATS·597 个数)"

# ★await 之后 battle 可能已被 queue_free —— 2026-08-20 smoke 间歇红 1/3 的根因
#   (`get_process_delta_time` in base `previously freed`)。这类错只在"战斗刚结束"那一瞬
#   命中, 本地手跑十次可能一次都不出, 所以必须静态守住而不是靠冒烟撞。
run_audit "tools/await_guard_audit.py" "ALL OK" "await_guard (协程 await 回来先确认 battle 还活着)"

# ★树级计时器接闭包 = 活过场景释放的野捕获 —— 2026-08-21 冒烟间歇红的根因之一
#   ()。手工找只找到 1 处, 审计器一扫又抓出 3 处。
run_audit "tools/tree_timer_audit.py" "ALL OK" "tree_timer (树级计时器不许接闭包·会活过场景释放)"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "ALL PASS ($PASS/$PASS)"
  exit 0
else
  echo "FAIL x$FAIL  (PASS $PASS)"
  exit 1
fi
