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
    # 结算屏按钮可达: 建战斗场 + 造 28 个单位塑长名单 + 开统计面板
    #   + **喂过面板的 0.4 秒自刷周期**(它就是在那一刻把自己提到最前的)。
    #   ★喂不够就拍不到覆盖, 断言会假绿 —— 这正是帧预算不够的典型危害。
    verify_result_reachable) echo 3000 ;;   # 逐个进出 9 个菜单场景, 500 帧只够跑完 2 个
    # ★等【游戏内效果结算】的测试: CI 无头帧率远高于本机, 同样的游戏时间要跑多得多的帧。
    #   2026-07-23: verify_pirate_hook 本地 93 帧落地, CI 上 500 帧不够 → 被掐断 →
    #   没打 ALL PASS → 判 FAIL(rc=0、致命报错=0), 看着像断言失败, 其实是预算不足。
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
  "$GODOT" --headless --path "$DIR" "res://tests/$t.tscn" \
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
  if [ "$rc" -eq 0 ] && [ "$fatal" -eq 0 ] && { grep -q "ALL PASS" "$RAW/$name.log" || grep -q "自证完成" "$RAW/$name.log"; }; then
    PASS=$((PASS+1)); echo "  PASS  $name"
  else
    FAIL=$((FAIL+1)); echo "  FAIL  $name  (rc=$rc, 致命报错=$fatal)"
    grep -E "\[FAIL\]|✗|$FATAL" "$RAW/$name.log" 2>/dev/null | head -5 | sed 's/^/        /'
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
if [ "$SMOKE_RC" -eq 0 ] && [ "$SMOKE_FATAL" -eq 0 ] && echo "$SMOKE_OUT" | grep -q "SMOKE DONE"; then
  PASS=$((PASS+1)); echo "  PASS  smoke_scenes (9场景进出×4 + 战斗中途硬释放×3 + 60秒完整战斗)"
else
  FAIL=$((FAIL+1)); echo "  FAIL  smoke_scenes  (rc=$SMOKE_RC, 致命报错=$SMOKE_FATAL)"
  echo "$SMOKE_OUT" | grep -E "$FATAL" | sort | uniq -c | sort -rn | head -5 | sed 's/^/        /'
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
# ★地图构图与可玩性 (2026-07-31 新增)。由来: 重画 arena.json 时发现三条约束没人守 ——
#   战场内不能有 void(单位被 clamp 进去=站黑洞)、站位格不能是水、接战区不能是水(亮度98压深色龟)。
#   改前的老图恰好三条全踩(亮青池子铺满接战区)。第 4 条守"地图必须与生成器一致", 防手刷脱钩。
run_audit "tools/map_composition_audit.py" "ALL OK" "map_composition_audit (地图构图·战场无void/站位不在水/接战区不亮/与生成器一致)"
run_audit "tools/workflow_lint.py"        "ALL OK" "workflow_lint (CI 工作流 YAML 语法)"
run_audit "tools/arch_budget.py"          "ALL OK" "arch_budget (架构预算·不许上帝对象·欠债只减不增)"
run_audit "tools/style_lint.py"           "ALL OK" "style_lint (代码风格·全tab/snake_case/PascalCase 焊死)"
run_audit "tools/rng_discipline.py"        "ALL OK" "rng_discipline (裸随机冻结·护确定性不回退)"
run_audit "tools/docs_authority_lint.py"  "ALL OK" "docs_authority_lint (单一事实源纪律·三权威在位/消费链活/README无漂移/无冒名)"
run_audit "tools/plans_lint.py"          "ALL OK" "plans_lint (方案书生命周期·状态/骨架/实施回填)"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "ALL PASS ($PASS/$PASS)"
  exit 0
else
  echo "FAIL x$FAIL  (PASS $PASS)"
  exit 1
fi
