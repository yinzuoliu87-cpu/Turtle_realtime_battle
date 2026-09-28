extends Node
## _probe_newuser.gd — 只读侦察: 全新玩家第一次打开 App 看到什么。
## 不改产品代码, 只读真实字符串与状态。跑法:
##   APPDATA=<空目录> godot --headless --path . res://tests/_probe_newuser.tscn --quit-after 900

const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const _SB := preload("res://scripts/net/supabase.gd")
const _MENU := preload("res://scripts/scenes/MainMenuScene.gd")
const _BE := preload("res://scripts/net/backend.gd")

const WD_CN := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]


func _p(s: String) -> void:
	print(s)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_p("[ABORT] 没有 GameState"); get_tree().quit(1); return

	_p("================ 0. 环境 ================")
	_p("  backend enabled()   = %s" % str(_SB.enabled()))
	_p("  base_url            = '%s'" % _SB.base_url())
	_p("  anon_key 长度       = %d" % _SB.anon_key().length())
	_p("  service_state()     = %s" % _SB.service_state())
	_p("  login_wall_on()     = %s   ← true = 新用户第一屏是【设置·登录墙】而不是主菜单"
		% str(_P2C.login_wall_on(_SB.enabled(), str(gs.account_email))))
	_p("  save 文件存在?      = %s" % str(FileAccess.file_exists("user://savegame.json")))
	_p("  test_mode           = %s" % str(gs.test_mode))

	_p("================ 1. 全新存档的真实数值 ================")
	_p("  hearts=%d  season_id=%d  season_level=%d  season_xp=%d" % [
		int(gs.hearts), int(gs.season_id), int(gs.season_level), int(gs.season_xp)])
	_p("  season_total_battles=%d  ranked_used=%d/%d  season_wins=%d" % [
		int(gs.season_total_battles), int(gs.ranked_used), int(_P2C.RANKED_QUOTA), int(gs.season_wins)])
	_p("  coins(龟币)=%d  meta_deepsea_coins(深海币)=%d" % [int(gs.coins), int(gs.meta_deepsea_coins)])
	_p("  inventory(装备)=%d 件  bench_inventory=%d" % [gs.inventory.size(), gs.bench_inventory.size()])
	_p("  left_team=%s  right_team=%s" % [str(gs.left_team), str(gs.right_team)])
	_p("  promoted=%s  gauntlet_eligible=%s  is_eliminated=%s" % [
		str(gs.promoted), str(gs.gauntlet_eligible()), str(gs.is_eliminated())])
	_p("  onboarded=%s  tutorial_active=%s" % [str(gs.onboarded), str(gs.tutorial_active)])
	_p("  nickname='%s'  account_email='%s'  account_id='%s'" % [
		str(gs.nickname), str(gs.account_email), str(gs.account_id)])
	_p("  titles=%s" % str(gs.titles))
	_p("  week_anchor_ts=%d  season_start_ts=%d  week_phase='%s'" % [
		int(gs.week_anchor_ts), int(gs.season_start_ts), str(gs.week_phase)])
	_p("  trainer_appearance='%s'  trainer_skill='%s'" % [
		str(gs.trainer_appearance), str(gs.trainer_skill)])
	_p("  team_equip_cap(Lv%d)=%d  UNIT_EQUIP_CAP=%d" % [
		int(gs.season_level), int(_P2C.team_equip_cap(int(gs.season_level))), int(_P2C.UNIT_EQUIP_CAP)])

	_p("================ 2. 七天 × 全新用户: 屏幕上的原文 ================")
	var m = _MENU.new()          # 脱树实例: 只调纯逻辑/建标签, 不进场景树
	var anchor: int = _P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	for d in range(1, 8):
		var ts: int = anchor + (d - 1) * 86400 + 12 * 3600      # 当天 UTC 正午
		var ph: String = _P2C.phase_at_utc(ts)
		_p("── %s (%s) ts=%d ──" % [WD_CN[d - 1], _P2C.PHASE_LABEL.get(ph, ph), ts])
		_p("   phase_mode_live      = %s" % str(_P2C.phase_mode_live(ph)))
		_p("   uses_ranked_quota    = %s" % str(_P2C.phase_uses_ranked_quota(ph)))
		var blk: String = str(m._battle_block_msg(ts))
		_p("   点「⚔ 开始战斗」     = %s" % ("【放行, 进选龟】" if blk == "" else "拦: " + blk))
		# 商店入口: 复刻 _open_shop 的三条判据顺序(_toast 需要视口, 脱树调不了)
		var shop_msg := ""
		if gs.is_eliminated():
			shop_msg = str(m._msg_eliminated())
		elif gs.ranked_quota_full(ts):
			shop_msg = str(m._msg_quota_full())
		elif int(gs.season_total_battles) <= 0:
			shop_msg = "🔒 本大轮打完第一场才开店"
		_p("   点「商店」           = %s" % ("【放行】" if shop_msg == "" else "拦: " + shop_msg))
		_p("   状态行闯关段         = '%s'" % str(m._gauntlet_status_line(ts)))
		var kind: String = _MENU.close_block_kind(ph, _P2C.phase_mode_live(_P2C.PHASE_FINALS),
			_SB.service_state() == _SB.ST_MAINTENANCE, _P2C.close_left_sec(ts),
			_P2C.can_start_match_utc(ts))
		var cb = m._week_close_block(ts)
		var txts: Array = []
		_gather_text(cb, txts)
		_p("   赛程条右端(%s)  = %s" % [kind, str(txts)])
		cb.free()
	m.free()

	_p("================ 3. 排行榜: 全新用户看到什么 ================")
	var pool: Dictionary = _BE.load_pool()
	var buckets: Dictionary = pool.get(_BE.POOL_KEY, {})
	var tot := 0
	for b in buckets.keys():
		tot += (buckets[b] as Array).size()
	_p("  池子桶数=%d  快照总条数=%d (分母)" % [buckets.size(), tot])
	var rows: Array = _BE.leaderboard(pool, _BE.player_display_name(),
		int(gs.season_wins), int(gs.hearts), int(gs.season_sweeps), 1 << 30)
	_p("  leaderboard rows=%d  我的显示名='%s'" % [rows.size(), _BE.player_display_name()])
	for r in rows:
		_p("    %s" % str(r))
	var hint := ""
	if rows.size() <= 1:
		hint = "（打几局上传阵容后, 这里会出现更多对手排名）"
	_p("  底部提示行 = '%s'" % hint)

	_p("================ 4. 主菜单实屏文字(真实例, 全新档) ================")
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	var packed = load("res://scenes/MainMenu.tscn")
	var menu = packed.instantiate()
	get_tree().root.add_child(menu)
	if menu is Control:
		(menu as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(menu as Control).size = Vector2(1280, 720)
	for i in range(140):
		await get_tree().process_frame
	var all: Array = []
	_gather_text(menu, all)
	_p("  可见文字 %d 条:" % all.size())
	for t in all:
		_p("    · %s" % str(t))
	menu.queue_free()

	_p("================ 5. 收尾 ================")
	_p("  ask_count=%d  auth_try_count=%d  token='%s'" % [
		_SB.ask_count(), _SB.auth_try_count(), _SB.access_token()])
	_p("  service_state()(末) = %s" % _SB.service_state())
	_p("PROBE DONE")
	get_tree().quit(0)


func _gather_text(n: Node, out: Array) -> void:
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append("[BTN] " + (n as Button).text)
	elif n is RichTextLabel and (n as RichTextLabel).text.strip_edges() != "":
		out.append("[RT] " + (n as RichTextLabel).text)
	elif n is LineEdit:
		out.append("[EDIT ph='%s' txt='%s']" % [(n as LineEdit).placeholder_text, (n as LineEdit).text])
	for c in n.get_children():
		_gather_text(c, out)
